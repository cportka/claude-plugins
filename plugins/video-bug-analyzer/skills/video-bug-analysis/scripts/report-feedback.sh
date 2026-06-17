#!/usr/bin/env bash
#
# report-feedback.sh — assemble a portka-tools plugin feedback report.
#
# There is no way to silently auto-submit feedback from an arbitrary Claude Code session
# (the environment's network allowlist, the session's GitHub MCP repo-scope, and the
# permission classifier each block it). So instead of pretending, this collects the
# diagnostics automatically and hands you two zero-friction ways to file:
#   1. A prefilled GitHub issue-form link you open in ANY browser (no auth/scope needed).
#   2. A copy-paste markdown report (for when there's no browser or to relay to a maintainer).
# If a GitHub MCP/gh with write access to cportka/claude-plugins IS available, Claude can
# also file it directly — but that's a bonus, not the contract.
#
# Usage:
#   report-feedback.sh [--plugin <name>] [--env <text>] [--ran <text>]
#                      [--outcome <text>] [--notes <text>]
#
# Options:
#   --plugin <name>   Plugin the feedback is about. Default: video-bug-analyzer.
#   --env <text>      Environment, e.g. "Claude Code on the web" / "CLI".
#   --ran <text>      The command(s) or request you made.
#   --outcome <text>  What happened vs. what you expected.
#   --notes <text>    Suggestions / extra notes.
#   -h, --help        Show this help.
#
set -uo pipefail

PLUGIN="video-bug-analyzer"
ENVI=""
RAN=""
OUTCOME=""
NOTES=""

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin)  PLUGIN="${2:-}";  shift 2 ;;
    --env)     ENVI="${2:-}";    shift 2 ;;
    --ran)     RAN="${2:-}";     shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --notes)   NOTES="${2:-}";   shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-collect diagnostics.
PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/.claude-plugin/plugin.json"
VERSION="unknown"
if [[ -f "$PLUGIN_JSON" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","unknown"))' "$PLUGIN_JSON" 2>/dev/null || echo unknown)"
  else
    VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
  fi
fi
if command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG_V="$(ffmpeg -version 2>/dev/null | head -n1)"
else
  FFMPEG_V="not installed"
fi
OS_INFO="$(uname -sr 2>/dev/null) $(uname -m 2>/dev/null)"

# Copy-paste markdown report.
cat <<EOF

----- copy below into the Plugin feedback issue -----
**Plugin / version:** ${PLUGIN} ${VERSION}
**Environment:** ${ENVI:-<CLI or web?>}
**ffmpeg:** ${FFMPEG_V}
**OS:** ${OS_INFO}
**What I ran:**
${RAN:-<commands or request>}
**Outcome:**
${OUTCOME:-<what happened vs. expected>}
**Notes / suggestions:**
${NOTES:-<optional>}
-----------------------------------------------------
EOF

# Prefilled GitHub issue-form deep link (opens in any browser; no auth/scope/egress needed).
if command -v python3 >/dev/null 2>&1; then
  FB_PLUGIN="$PLUGIN" FB_VERSION="$VERSION" FB_ENV="$ENVI" FB_FFMPEG="$FFMPEG_V" \
  FB_RAN="$RAN" FB_OUTCOME="$OUTCOME" FB_NOTES="$NOTES" \
  python3 - <<'PY'
import os, urllib.parse
base = "https://github.com/cportka/claude-plugins/issues/new"
params = {"template": "plugin-feedback.yml"}
# Form-field ids (text/textarea) prefill via query params; the plugin/environment dropdowns
# are picked manually in the form.
for env_key, field in [("FB_VERSION", "version"), ("FB_FFMPEG", "ffmpeg"),
                       ("FB_RAN", "command"), ("FB_OUTCOME", "outcome"),
                       ("FB_NOTES", "logs")]:
    v = os.environ.get(env_key, "").strip()
    if v:
        params[field] = v
print("\nOpen this in any browser to file it (no GitHub scope or session network needed):")
print(base + "?" + urllib.parse.urlencode(params))
PY
else
  echo
  echo "Open this in any browser and paste the block above (python3 not found, so not prefilled):"
  echo "https://github.com/cportka/claude-plugins/issues/new?template=plugin-feedback.yml"
fi

echo
echo "If a GitHub MCP/gh with write access to cportka/claude-plugins is available, Claude can file it directly instead."
