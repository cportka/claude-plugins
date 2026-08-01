#!/usr/bin/env bash
#
# portka-session-start.sh — SessionStart hook for the repo-bootstrap plugin (since 1.14.0).
#
# The standard's session healer: three jobs, each idempotent and best-effort (never fails the
# session; each emits at most one context line, and only when it actually did/found something).
#
#   1. APPLY THE DECLARED COMMIT IDENTITY (#98/#109/user directive). The repo commits its identity
#      in .claude/commit-identity ("Name <email>"); apply it to the repo's git config when identity
#      is unset or still a hosted noreply@ default — so agent commits land as the owner intends
#      with ZERO per-session setup. A deliberately different local identity is left. (bootstrap-repo.sh
#      applies the same declaration itself at bootstrap time, #116, so even session 1 is covered.)
#   2. HEAL A STOCK stop-hook-git-check.sh (#109; since 1.13.0). Hosted containers re-provision
#      ~/.claude each session, so the stock hook (which false-flags GitHub's squash-merge commits
#      and demands a hardcoded identity) keeps coming back; replace it with the corrected edition
#      shipped in this plugin (backup kept; custom hooks untouched).
#   3. FLAG A STALE STANDARD BLOCK (1.14.0). The managed CLAUDE.md block carries a
#      portka-standard-version stamp; when it's older than the version in which the BLOCK TEXT last
#      changed (skills/repo-bootstrap/standard-version.txt — NOT the plugin version, or every
#      unrelated fix would nag), or missing entirely (pre-1.14), say so, so the refresh gets folded
#      into the next PR instead of the repo running an old standard forever. This is why pre-1.13
#      repos never learned the authorship fixes.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Jobs 1 and 3 are about THE REPO, not the cwd — a session can start in a subdirectory (review
# finding: cwd-relative paths silently no-op'd there). Resolve the work-tree root once.
REPO_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# --- 1. declared commit identity -------------------------------------------------------
if [[ -n "$REPO_TOP" && -f "$REPO_TOP/.claude/commit-identity" ]]; then
  _decl="$(grep -v '^[[:space:]]*#' "$REPO_TOP/.claude/commit-identity" | grep -v '^[[:space:]]*$' | head -1 | tr -d '\r')"
  _name="${_decl%% <*}"
  _email="$(printf '%s' "$_decl" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
  # The name must be a real name: an email-only line like "<a@b.c>" leaves the whole bracketed
  # string in _name (the %% pattern needs " <"), which would author commits as "<a@b.c> <a@b.c>".
  if [[ -n "$_name" && -n "$_email" && "$_name" != *"<"* ]]; then
    _cur="$(git config user.email 2>/dev/null || true)"
    # Any `noreply@` address is a harness default, never a deliberate identity (1.14.1) — the same
    # rule bootstrap-repo.sh uses to refuse SEEDING from one, so the two stay symmetric. A personal
    # GitHub privacy address (user@users.noreply.github.com) does not start with `noreply@`.
    if [[ -z "$_cur" || "$_cur" == noreply@* ]]; then
      # Only claim success when the writes actually land (a config.lock / read-only .git fails
      # them); a false "applied" line would talk the agent out of setting identity by hand.
      if git config user.name "$_name" 2>/dev/null && git config user.email "$_email" 2>/dev/null; then
        echo "repo-bootstrap: applied this repo's declared commit identity ($_name <$_email>) to git config — commits will land as the owner intends."
      else
        echo "repo-bootstrap: could NOT write git config (lock/permissions?) — set the declared identity by hand before committing: git config user.name \"$_name\"; git config user.email \"$_email\""
      fi
    fi
  fi
fi

# --- 2. heal a stock stop-hook ---------------------------------------------------------
CANON="$PLUGIN_ROOT/skills/repo-bootstrap/scripts/stop-hook-git-check.sh"
STOCK_MARKER='user.email noreply@anthropic.com'
if [[ -f "$CANON" ]]; then
  # PORTKA_HOOK_DIRS (space-separated) overrides the search list — the test suite sets it so
  # exercising this hook can never rewrite the REAL environment's stop-hook (review finding:
  # the literal /root path escaped the tests' $HOME sandbox and healed the live hook).
  if [[ -n "${PORTKA_HOOK_DIRS:-}" ]]; then
    read -r -a _dirs <<<"$PORTKA_HOOK_DIRS"
  else
    _dirs=("${HOME:-/root}/.claude" /home/claude/.claude /root/.claude)
  fi
  fixed_any=""
  for dir in ${_dirs[@]+"${_dirs[@]}"}; do
    hook="$dir/stop-hook-git-check.sh"
    [[ -f "$hook" && -w "$hook" ]] || continue
    grep -qF "$STOCK_MARKER" "$hook" 2>/dev/null || continue   # not the stock hook — leave it alone
    cp "$hook" "$hook.stock.bak" 2>/dev/null || true
    if cp "$CANON" "$hook" 2>/dev/null; then
      chmod +x "$hook" 2>/dev/null || true
      fixed_any="${fixed_any:+$fixed_any, }$hook"
    fi
  done
  if [[ -n "$fixed_any" ]]; then
    echo "repo-bootstrap: replaced the stock stop-hook-git-check.sh with the corrected edition at $fixed_any (backup: *.stock.bak). Merged squash commits and the declared commit identity are no longer false-flagged; unpushed-work nudges still fire."
  fi
fi

# --- 3. stale standard block -----------------------------------------------------------
if [[ -n "$REPO_TOP" && -f "$REPO_TOP/.claude/CLAUDE.md" ]] \
   && grep -q 'BEGIN portka-standard' "$REPO_TOP/.claude/CLAUDE.md" 2>/dev/null; then
  # The stamp may carry a pre-release suffix (this marketplace has shipped 1.0.0-rc.N releases):
  # capture it whole, but COMPARE on the MAJOR.MINOR.PATCH base only — sort -V orders "1.14.0"
  # before "1.14.0-rc1" (the inverse of SemVer precedence), so base-equality reads as current.
  _stamp="$(sed -n 's/.*portka-standard-version: \([0-9][0-9A-Za-z.-]*\).*/\1/p' "$REPO_TOP/.claude/CLAUDE.md" | head -1)"
  # Compare against the version in which the BLOCK TEXT last changed, not the plugin version
  # (1.14.1 review finding): otherwise every unrelated plugin fix tells every bootstrapped repo to
  # commit a refresh whose only diff is the stamp comment. plugin.json is the fallback for a
  # pre-1.14.1 plugin tree that has no standard-version.txt.
  _pver="$(grep -v '^[[:space:]]*#' "$PLUGIN_ROOT/skills/repo-bootstrap/standard-version.txt" 2>/dev/null | tr -d '[:space:]' | head -1)"
  [[ -n "$_pver" ]] || _pver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  if [[ -n "$_pver" ]]; then
    _sbase="${_stamp%%-*}"; _pbase="${_pver%%-*}"
    if [[ -z "$_stamp" ]]; then
      echo "repo-bootstrap: this repo's Portka standard block predates 1.14.0 (no version stamp) — it lacks the current authorship/branch-restart guidance. Fold a refresh into your next PR: bootstrap-repo.sh --portka-standard --scope project, commit the updated .claude/CLAUDE.md."
    elif [[ "$_sbase" != "$_pbase" && "$(printf '%s\n%s\n' "$_sbase" "$_pbase" | sort -V | head -1)" == "$_sbase" ]]; then
      echo "repo-bootstrap: this repo's Portka standard block is from $_stamp; the installed plugin is $_pver — fold a refresh into your next PR: bootstrap-repo.sh --portka-standard --scope project, commit the updated .claude/CLAUDE.md."
    fi
  fi
fi

exit 0
