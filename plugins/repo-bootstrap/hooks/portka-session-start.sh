#!/usr/bin/env bash
#
# portka-session-start.sh — SessionStart hook for the repo-bootstrap plugin (1.14.0).
#
# The standard's session healer: three jobs, each idempotent and best-effort (never fails the
# session; each emits at most one context line, and only when it actually did/found something).
#
#   1. APPLY THE DECLARED COMMIT IDENTITY (#98/#109/user directive). The repo commits its identity
#      in .claude/commit-identity ("Name <email>"); apply it to the repo's git config when identity
#      is unset or still the hosted noreply@anthropic.com default — so agent commits land as the
#      owner intends with ZERO per-session setup. A deliberately different local identity is left.
#   2. HEAL A STOCK stop-hook-git-check.sh (#109; since 1.13.0). Hosted containers re-provision
#      ~/.claude each session, so the stock hook (which false-flags GitHub's squash-merge commits
#      and demands a hardcoded identity) keeps coming back; replace it with the corrected edition
#      shipped in this plugin (backup kept; custom hooks untouched).
#   3. FLAG A STALE STANDARD BLOCK (1.14.0). The managed CLAUDE.md block carries a
#      portka-standard-version stamp; when it's older than the installed plugin (or missing —
#      pre-1.14), say so, so the refresh gets folded into the next PR instead of the repo running
#      an old standard forever. This is why pre-1.13 repos never learned the authorship fixes.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- 1. declared commit identity -------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ -f .claude/commit-identity ]]; then
  _decl="$(grep -v '^[[:space:]]*#' .claude/commit-identity | grep -v '^[[:space:]]*$' | head -1)"
  _name="${_decl%% <*}"
  _email="$(printf '%s' "$_decl" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
  if [[ -n "$_name" && -n "$_email" ]]; then
    _cur="$(git config user.email 2>/dev/null || true)"
    if [[ -z "$_cur" || "$_cur" == "noreply@anthropic.com" ]]; then
      git config user.name "$_name" 2>/dev/null || true
      git config user.email "$_email" 2>/dev/null || true
      echo "repo-bootstrap: applied this repo's declared commit identity ($_name <$_email>) to git config — commits will land as the owner intends."
    fi
  fi
fi

# --- 2. heal a stock stop-hook ---------------------------------------------------------
CANON="$PLUGIN_ROOT/skills/repo-bootstrap/scripts/stop-hook-git-check.sh"
STOCK_MARKER='user.email noreply@anthropic.com'
if [[ -f "$CANON" ]]; then
  fixed_any=""
  for dir in "${HOME:-/root}/.claude" /home/claude/.claude /root/.claude; do
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
if [[ -f .claude/CLAUDE.md ]] && grep -q 'BEGIN portka-standard' .claude/CLAUDE.md 2>/dev/null; then
  _stamp="$(sed -n 's/.*portka-standard-version: \([0-9][0-9.]*\).*/\1/p' .claude/CLAUDE.md | head -1)"
  _pver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  if [[ -n "$_pver" ]]; then
    if [[ -z "$_stamp" ]]; then
      echo "repo-bootstrap: this repo's Portka standard block predates 1.14.0 (no version stamp) — it lacks the current authorship/branch-restart guidance. Fold a refresh into your next PR: bootstrap-repo.sh --portka-standard --scope project, commit the updated .claude/CLAUDE.md."
    elif [[ "$_stamp" != "$_pver" && "$(printf '%s\n%s\n' "$_stamp" "$_pver" | sort -V | head -1)" == "$_stamp" ]]; then
      echo "repo-bootstrap: this repo's Portka standard block is from $_stamp; the installed plugin is $_pver — fold a refresh into your next PR: bootstrap-repo.sh --portka-standard --scope project, commit the updated .claude/CLAUDE.md."
    fi
  fi
fi

exit 0
