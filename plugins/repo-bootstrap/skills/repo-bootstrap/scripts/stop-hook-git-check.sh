#!/bin/bash
#
# stop-hook-git-check.sh — end-of-turn git hygiene check (Portka corrected edition, 1.13.0).
#
# A drop-in replacement for the stock hosted-environment Stop hook of the same name, fixing the
# three recurring false positives field-reported in #98 and #109 (root cause verified there):
#
#   1. MERGED HISTORY IS NEVER FLAGGED. The stock hook diffs `origin/<branch>..HEAD`; after the
#      standard's merge → branch-restart cycle, the remote branch is deleted but the LOCAL
#      remote-tracking ref lingers (a refspec-scoped fetch never prunes it), so that stale range
#      spans GitHub's own squash-merge commit (committer noreply@github.com) — flagged every turn,
#      with a suggested fix (rewrite it) that the standard rightly forbids. This edition scopes
#      every check to commits that are BOTH unpushed AND unmerged: `HEAD --not <upstream> <default>`
#      — a commit reachable from the remote default branch can never be flagged, stale ref or not.
#   2. THE DECLARED IDENTITY WINS. The stock hook demands committer noreply@anthropic.com; the
#      Portka standard has agents commit as the REPO-DECLARED identity (its CLAUDE.md "Commit
#      identity" section, applied via git config). This edition reads the expectation from the
#      repo's own `git config user.email` and only notes a mismatch/missing config — naming the
#      configured values, never a hardcoded default, and never for already-pushed commits.
#   3. SIGNATURES ARE INFORMATIONAL. Hosted sandboxes configure commit.gpgsign with an empty or
#      stub signing key, so nothing in-session can sign — and on squash-merge repos, branch-commit
#      signatures never reach the default branch anyway. Unsigned commits are mentioned only when
#      a usable key exists, and then as a note, not a fix-it.
#
# Still enforced (the useful nudges): uncommitted changes, untracked files, and unpushed commits
# end the turn with an actionable "commit/push" message. The remedy is always to PUSH — this hook
# never suggests amending or rebasing history that is reachable from any remote ref.
#
# Install: repo-bootstrap --portka-standard (user scope) refreshes ~/.claude/stop-hook-git-check.sh
# when it holds the stock hook (backup kept); the plugin's SessionStart hook does the same each
# session, so a re-provisioned container heals itself. Standalone: copy this file over the stock one.

input=$(cat)

# Recursion prevention (the harness re-invokes the hook with stop_hook_active=true).
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active' 2>/dev/null)
[[ "$stop_hook_active" == "true" ]] && exit 0

# Not a git repo / no remote: nothing to check (a push nudge is meaningless without a remote).
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ -z "$(git remote)" ]] && exit 0

# Uncommitted / untracked work: the classic end-of-turn nudges, unchanged from the stock hook.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "There are uncommitted changes in the repository. Please commit and push these changes to the remote branch." >&2
  exit 2
fi
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "There are untracked files in the repository. Please commit and push these changes to the remote branch." >&2
  exit 2
fi

current_branch=$(git branch --show-current)
[[ -z "$current_branch" ]] && exit 0

# Build the exclusion set: the branch's upstream (when it exists) AND the remote default branch.
# Excluding the default branch is the #109 fix — an already-merged commit (GitHub's squash-merge,
# committer noreply@github.com) is reachable from it and so can never enter the checked range,
# even when a stale origin/<branch> ref survives a merge + branch-restart.
# CAUTION: `--not` TOGGLES negation in rev-list — `--not A --not B` re-includes B. It must appear
# ONCE, followed by every base: `HEAD --not A B`.
bases=()
if git rev-parse -q --verify "origin/$current_branch" >/dev/null 2>&1; then
  bases+=("origin/$current_branch")
fi
default_ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
if [[ -z "$default_ref" ]]; then
  for c in origin/main origin/master; do
    git rev-parse -q --verify "$c" >/dev/null 2>&1 && { default_ref="$c"; break; }
  done
fi
[[ -n "$default_ref" ]] && bases+=("$default_ref")
[[ ${#bases[@]} -eq 0 ]] && exit 0
not_args=(--not "${bases[@]}")

pending_count=$(git rev-list --count HEAD "${not_args[@]}" 2>/dev/null || echo 0)
[[ "$pending_count" -eq 0 ]] && exit 0

# There IS unpushed, unmerged work — that's the one actionable state. Attach identity/signing
# notes (informational, with the repo's DECLARED values) to the push message.
notes=""
expected_email=$(git config user.email)
expected_name=$(git config user.name)
if [[ -z "$expected_email" ]]; then
  notes+=$'\n'"note: no git identity configured in this repo — set it from the repo's declared identity (see its CLAUDE.md \"Commit identity\" section): git config user.name \"<declared name>\" && git config user.email \"<declared email>\""
else
  mismatched=$(git log --format='%h %ae %ce' HEAD "${not_args[@]}" 2>/dev/null \
    | awk -v e="$expected_email" '$2 != e || $3 != e' | head -3)
  if [[ -n "$mismatched" ]]; then
    notes+=$'\n'"note: unpushed commit(s) not authored as the repo's configured identity ($expected_name <$expected_email>):"$'\n'"$mismatched"$'\n'"For UNPUSHED commits only, you may fix the tip with: git commit --amend --no-edit --reset-author. Never rewrite pushed or merged history for this."
  fi
fi
if [[ "$(git config --type=bool commit.gpgsign 2>/dev/null)" == "true" ]]; then
  keyfile=$(git config user.signingkey 2>/dev/null)
  if [[ -n "$keyfile" && -s "$keyfile" ]]; then
    unsigned=$(git log --format='%h %G?' HEAD "${not_args[@]}" 2>/dev/null | awk '$2 == "N"' | head -3)
    [[ -n "$unsigned" ]] && notes+=$'\n'"note: unsigned unpushed commit(s) (informational — on a squash-merge repo, branch signatures never reach the default branch):"$'\n'"$unsigned"
  fi
  # An empty/missing signing key means nothing in this environment can sign — say nothing.
fi

echo "There are $pending_count unpushed commit(s) on branch '$current_branch'. Please push these changes to the remote repository.$notes" >&2
exit 2
