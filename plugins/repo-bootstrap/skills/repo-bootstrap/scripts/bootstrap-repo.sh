#!/usr/bin/env bash
#
# bootstrap-repo.sh — set up a repository to use Claude Code plugins from a marketplace.
#
# Writes (or merges into) .claude/settings.json so a marketplace is known and the chosen
# plugins are enabled — which is what makes plugins load in ephemeral Claude Code web
# sessions, where ~/.claude does not persist. Optionally drops a GitHub Actions workflow
# that runs your test script.
#
# Usage:
#   bootstrap-repo.sh [--plugin <name>]... [--marketplace-name <name>]
#                     [--marketplace-repo <owner/repo>] [--ci] [--dir <path>] [--force]
#
# Options:
#   --plugin <name>            Enable plugin <name>@<marketplace-name>. Repeatable. If the
#                              marketplace.json is locatable, unknown names warn (non-fatal).
#   --marketplace-name <name>  Marketplace handle. Default: portka-tools.
#   --marketplace-repo <o/r>   GitHub repo hosting the marketplace.
#                              Default: cportka/claude-plugins.
#   --list                     List known plugin names (if marketplace.json is locatable).
#   --ci                       Also add .github/workflows/validate.yml (runs
#                              tests/run-tests.sh when present).
#   --dir <path>               Target repo root. Default: current directory.
#   --force                    Overwrite the CI workflow if it already exists.
#   --dry-run                  Print the resulting settings.json and planned actions; write nothing.
#   -h, --help                 Show this help.
#
# Examples:
#   bootstrap-repo.sh --plugin video-bug-analyzer --ci
#   bootstrap-repo.sh --plugin video-bug-analyzer --plugin other-plugin
#   bootstrap-repo.sh --list
#
set -euo pipefail

MARKET_NAME="portka-tools"
MARKET_REPO="cportka/claude-plugins"
PLUGINS=()
ADD_CI=""
DIR="."
FORCE=""
LIST=""   # --list flag
DRY_RUN=""   # --dry-run previews without writing

# resolve where this script lives, so we can find the marketplace manifest when the
# script is run from a checkout of the marketplace repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# locate marketplace.json (env override, the target repo, or this repo checkout).
locate_marketplace() {
  local c
  for c in \
    "${VBA_MARKETPLACE_JSON:-}" \
    "$DIR/.claude-plugin/marketplace.json" \
    "$SCRIPT_DIR/../../../../../.claude-plugin/marketplace.json"; do
    [[ -n "$c" && -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# print the plugin names declared in a marketplace.json, one per line.
known_plugin_names() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for p in d.get("plugins", []):
        if p.get("name"):
            print(p["name"])
except Exception:
    pass
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin) PLUGINS+=("${2:-}"); shift 2 ;;
    --marketplace-name) MARKET_NAME="${2:-}"; shift 2 ;;
    --marketplace-repo) MARKET_REPO="${2:-}"; shift 2 ;;
    --list)  LIST="1"; shift ;;   # ADDED
    --ci)    ADD_CI="1"; shift ;;
    --dir)   DIR="${2:-}"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;   # ADDED (1.0.0)
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required (used to safely merge JSON)." >&2
  exit 1
fi

# --list known plugins, then exit.
if [[ -n "$LIST" ]]; then
  if _mj="$(locate_marketplace)"; then
    echo "Known plugins in $MARKET_NAME ($_mj):"
    known_plugin_names "$_mj" | sed 's/^/  /'
  else
    echo "Could not locate marketplace.json (run from the marketplace repo or set VBA_MARKETPLACE_JSON)." >&2
    exit 1
  fi
  exit 0
fi

if [[ ! -d "$DIR" ]]; then
  echo "Error: target dir not found: $DIR" >&2
  exit 1
fi

# warn (non-fatal) about --plugin names that aren't in the marketplace, when we can
# see it. A user may legitimately bootstrap before a plugin exists locally, so don't fail.
if [[ ${#PLUGINS[@]} -gt 0 ]] && _mj="$(locate_marketplace)"; then
  mapfile -t _known < <(known_plugin_names "$_mj")
  for _p in "${PLUGINS[@]}"; do
    _hit=0
    for _k in "${_known[@]:-}"; do [[ "$_p" == "$_k" ]] && { _hit=1; break; }; done
    [[ "$_hit" -eq 1 ]] || echo "warning: '$_p' is not a known $MARKET_NAME plugin (continuing anyway)." >&2
  done
fi

SETTINGS_DIR="$DIR/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
[[ -n "$DRY_RUN" ]] || mkdir -p "$SETTINGS_DIR"   # no writes in --dry-run

# Merge the marketplace + enabled plugins into .claude/settings.json without clobbering
# any keys that are already there. python3 does the JSON read/merge/write safely.
# under --dry-run, print the merged result instead of writing it.
SETTINGS="$SETTINGS" MARKET_NAME="$MARKET_NAME" MARKET_REPO="$MARKET_REPO" \
DRY_RUN="$DRY_RUN" \
PLUGINS_CSV="$(IFS=,; echo "${PLUGINS[*]:-}")" \
python3 <<'PY'
import json, os

settings = os.environ["SETTINGS"]
name = os.environ["MARKET_NAME"]
repo = os.environ["MARKET_REPO"]
dry = bool(os.environ.get("DRY_RUN"))
plugins = [p for p in os.environ.get("PLUGINS_CSV", "").split(",") if p]

data = {}
if os.path.exists(settings):
    with open(settings) as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError:
            raise SystemExit(
                f"Error: {settings} exists but is not valid JSON; fix or remove it first."
            )

markets = data.setdefault("extraKnownMarketplaces", {})
markets[name] = {"source": {"source": "github", "repo": repo}}

enabled = data.setdefault("enabledPlugins", {})
for p in plugins:
    enabled[f"{p}@{name}"] = True

if dry:
    print(f"[dry-run] would write {settings} as:")
    print(json.dumps(data, indent=2))
else:
    with open(settings, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print(f"Wrote {settings}: marketplace '{name}' -> {repo}; enabled {len(plugins)} plugin(s).")
PY

if [[ -n "$ADD_CI" && -n "$DRY_RUN" ]]; then
  echo "[dry-run] would write $DIR/.github/workflows/validate.yml (runs tests/run-tests.sh)"
elif [[ -n "$ADD_CI" ]]; then
  WF_DIR="$DIR/.github/workflows"
  WF="$WF_DIR/validate.yml"
  mkdir -p "$WF_DIR"
  if [[ -f "$WF" && -z "$FORCE" ]]; then
    echo "CI workflow already exists (use --force to overwrite): $WF" >&2
  else
    cat > "$WF" <<'YAML'
name: validate

on:
  push:
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          if [ -f tests/run-tests.sh ]; then
            bash tests/run-tests.sh
          else
            echo "No tests/run-tests.sh found; nothing to validate."
          fi
YAML
    echo "Wrote $WF"
  fi
fi

# Claude Code's auto-permission classifier may DENY the committed-settings
# path (it flags enabling a third-party plugin as self-modification / untrusted integration)
# until the user approves. Emit the one-paste CLI fallback that needs no settings write.
{
  echo ""
  echo "Note: committing .claude/settings.json may be blocked by Claude Code's permission"
  echo "classifier (enabling a third-party plugin) until you approve it. One-paste CLI fallback:"
  echo "  /plugin marketplace add ${MARKET_REPO}"
  if [[ ${#PLUGINS[@]} -gt 0 ]]; then
    for _p in "${PLUGINS[@]}"; do
      [[ -n "$_p" ]] && echo "  /plugin install ${_p}@${MARKET_NAME}"
    done
  else
    echo "  /plugin install <name>@${MARKET_NAME}"
  fi
} >&2

if [[ -n "$DRY_RUN" ]]; then
  echo "Done (dry-run — nothing was written). Re-run without --dry-run to apply."
else
  echo "Done. Commit .claude/settings.json (and any workflow) so it applies in web sessions."
fi
