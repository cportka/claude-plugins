#!/usr/bin/env bash
#
# portka-session-start.sh — SessionStart hook for the repo-bootstrap plugin (since 1.14.0).
#
# The standard's session healer: three jobs, each idempotent and best-effort (never fails the
# session; each emits at most one context line, and only when it actually did/found something).
#
# SIDE EFFECTS, IN FULL (1.15.0 — a plugin should be auditable in one read):
#   * Job 1 writes `git config user.name/user.email` in the CURRENT REPOSITORY only, and only when
#     that repo itself commits `.claude/commit-identity` (an explicit, in-repo declaration) AND the
#     configured identity is unset or a `noreply@` harness default. Never global, never another repo.
#     Opt out entirely with PORTKA_NO_IDENTITY=1.
#   * Job 2 writes NOTHING by default. It only reports a stock stop-hook; replacing it (a file
#     outside the plugin directory) requires the explicit PORTKA_HEAL_STOP_HOOK=1 or a
#     `bootstrap-repo.sh --heal-stop-hook` run you typed yourself.
#   * Job 3 only reads. No network, no downloads, no package installs, no sudo — ever.
#
#   1. APPLY THE DECLARED COMMIT IDENTITY (#98/#109/user directive). The repo commits its identity
#      in .claude/commit-identity ("Name <email>"); apply it to the repo's git config when identity
#      is unset or still a hosted noreply@ default — so agent commits land as the owner intends
#      with ZERO per-session setup. A deliberately different local identity is left. (bootstrap-repo.sh
#      applies the same declaration itself at bootstrap time, #116, so even session 1 is covered.)
#   2. REPORT A STOCK stop-hook-git-check.sh (#109; healing since 1.13.0, consent-gated in 1.15.0).
#      Hosted containers re-provision ~/.claude each session, so the stock hook (which false-flags
#      GitHub's squash-merge commits and demands a hardcoded identity) keeps coming back. This hook
#      names it and how to fix it; it replaces it only with explicit consent (backup kept; custom
#      hooks untouched either way).
#   3. FLAG A STALE STANDARD BLOCK (1.14.0). The managed CLAUDE.md block carries a
#      portka-standard-version stamp; when it's older than the version in which the BLOCK TEXT last
#      changed (skills/repo-bootstrap/standard-version.txt — NOT the plugin version, or every
#      unrelated fix would nag), or missing entirely (pre-1.14), say so, so the refresh gets folded
#      into the next PR instead of the repo running an old standard forever. This is why pre-1.13
#      repos never learned the authorship fixes.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# An env opt-in must be genuinely ON (1.15.0 review): a bare `-n` test read PORTKA_HEAL_STOP_HOOK=0
# as consent, so turning the feature OFF that way still performed the write.
_truthy() { case "${1:-}" in ""|0|false|FALSE|False|no|NO|off|OFF) return 1 ;; *) return 0 ;; esac; }

# Jobs 1 and 3 are about THE REPO, not the cwd — a session can start in a subdirectory (review
# finding: cwd-relative paths silently no-op'd there). Resolve the work-tree root once.
REPO_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# --- 1. declared commit identity -------------------------------------------------------
# PORTKA_NO_IDENTITY=1 opts out of the one write this hook makes by default (1.15.0).
if ! _truthy "${PORTKA_NO_IDENTITY:-}" && [[ -n "$REPO_TOP" && -f "$REPO_TOP/.claude/commit-identity" ]]; then
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

# --- 2. report (or, with consent, heal) a stock stop-hook -------------------------------
# CONSENT MODEL (1.15.0): through 1.14.1 this OVERWROTE ~/.claude/stop-hook-git-check.sh on every
# session start — a silent write outside the plugin directory, unattended, which is exactly the
# pattern plugin review flags ("no filesystem access outside the plugin directory"). It now only
# REPORTS by default and names the two consented ways to apply the fix. Set PORTKA_HEAL_STOP_HOOK=1
# (env, per-session opt-in) or run `bootstrap-repo.sh --heal-stop-hook` (an explicit command you
# typed) to actually replace it. The corrected hook itself is unchanged.
CANON="$PLUGIN_ROOT/skills/repo-bootstrap/scripts/stop-hook-git-check.sh"
STOCK_MARKER='user.email noreply@anthropic.com'
if [[ -f "$CANON" ]]; then
  # PORTKA_HOOK_DIRS (space-separated) overrides the search list — the test suite sets it so
  # exercising this hook can never touch the REAL environment's stop-hook (review finding:
  # the literal /root path escaped the tests' $HOME sandbox and healed the live hook).
  if [[ -n "${PORTKA_HOOK_DIRS:-}" ]]; then
    read -r -a _dirs <<<"$PORTKA_HOOK_DIRS"
  else
    _dirs=("${HOME:-/root}/.claude" /home/claude/.claude /root/.claude)
  fi
  # WRITE SCOPE (1.15.0 review): the search list includes the well-known hosted paths so a stock
  # hook is still *reported* wherever it lives, but a consented write only ever touches THIS user's
  # $HOME (or exactly the dirs PORTKA_HOOK_DIRS names). One person's opt-in must not rewrite files
  # in /home/claude or /root when those aren't theirs.
  _writable_dirs=()
  if [[ -n "${PORTKA_HOOK_DIRS:-}" ]]; then
    _writable_dirs=(${_dirs[@]+"${_dirs[@]}"})
  elif [[ -n "${HOME:-}" ]]; then
    _writable_dirs=("$HOME/.claude")
  fi
  _may_write() {
    local d
    for d in ${_writable_dirs[@]+"${_writable_dirs[@]}"}; do [[ "$1" == "$d" ]] && return 0; done
    return 1
  }
  fixed_any=""; found_any=""; skipped_any=""
  for dir in ${_dirs[@]+"${_dirs[@]}"}; do
    hook="$dir/stop-hook-git-check.sh"
    [[ -f "$hook" ]] || continue
    grep -qF "$STOCK_MARKER" "$hook" 2>/dev/null || continue   # not the stock hook — leave it alone
    found_any="${found_any:+$found_any, }$hook"
    _truthy "${PORTKA_HEAL_STOP_HOOK:-}" || continue
    if ! _may_write "$dir"; then
      skipped_any="${skipped_any:+$skipped_any, }$hook"
      continue
    fi
    [[ -w "$hook" ]] || continue
    [[ -f "$hook.stock.bak" ]] || cp "$hook" "$hook.stock.bak" 2>/dev/null || true
    if cp "$CANON" "$hook" 2>/dev/null; then
      chmod +x "$hook" 2>/dev/null || true
      fixed_any="${fixed_any:+$fixed_any, }$hook"
    fi
  done
  if [[ -n "$fixed_any" ]]; then
    echo "repo-bootstrap: PORTKA_HEAL_STOP_HOOK=1 — replaced the stock stop-hook-git-check.sh with the corrected edition at $fixed_any (backup: *.stock.bak). Merged squash commits and the declared commit identity are no longer false-flagged; unpushed-work nudges still fire.${skipped_any:+ NOT touched (outside your \$HOME): $skipped_any — heal those deliberately with bootstrap-repo.sh --heal-stop-hook --home <that home>.}"
  elif [[ -n "$skipped_any" ]]; then
    echo "repo-bootstrap: a stock stop-hook-git-check.sh exists at $skipped_any, but that is outside your \$HOME so this hook did not modify it. If it's yours, heal it deliberately: bootstrap-repo.sh --heal-stop-hook --home <that home>."
  elif [[ -n "$found_any" ]]; then
    echo "repo-bootstrap: the stock stop-hook-git-check.sh is installed at $found_any. It flags GitHub's own squash-merge commits as 'unverified authorship' every turn and demands a hardcoded noreply@anthropic.com committer — a false positive this plugin ships a corrected edition for. This plugin will NOT modify it on its own (it lives outside the plugin directory). To apply the fix, run: bootstrap-repo.sh --heal-stop-hook   (or set PORTKA_HEAL_STOP_HOOK=1 for this session). Either way a .stock.bak backup is kept. If you'd rather not touch it, ignore its authorship demands per the standard's Commit identity section — never rewrite merged history to satisfy it."
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
