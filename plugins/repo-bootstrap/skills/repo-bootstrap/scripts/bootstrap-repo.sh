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
#   --plugin <name>            Enable plugin <name>@<marketplace-name>. Repeatable.
#   --marketplace-name <name>  Marketplace handle. Default: portka-tools.
#   --marketplace-repo <o/r>   GitHub repo hosting the marketplace.
#                              Default: cportka/claude-plugins.
#   --ci                       Also add .github/workflows/validate.yml (runs
#                              tests/run-tests.sh when present).
#   --dir <path>               Target repo root. Default: current directory.
#   --force                    Overwrite the CI workflow if it already exists.
#   -h, --help                 Show this help.
#
# Examples:
#   bootstrap-repo.sh --plugin video-bug-analyzer --ci
#   bootstrap-repo.sh --plugin video-bug-analyzer --plugin other-plugin
#
set -euo pipefail

MARKET_NAME="portka-tools"
MARKET_REPO="cportka/claude-plugins"
PLUGINS=()
ADD_CI=""
DIR="."
FORCE=""

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin) PLUGINS+=("${2:-}"); shift 2 ;;
    --marketplace-name) MARKET_NAME="${2:-}"; shift 2 ;;
    --marketplace-repo) MARKET_REPO="${2:-}"; shift 2 ;;
    --ci)    ADD_CI="1"; shift ;;
    --dir)   DIR="${2:-}"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required (used to safely merge JSON)." >&2
  exit 1
fi

if [[ ! -d "$DIR" ]]; then
  echo "Error: target dir not found: $DIR" >&2
  exit 1
fi

SETTINGS_DIR="$DIR/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"

# Merge the marketplace + enabled plugins into .claude/settings.json without clobbering
# any keys that are already there. python3 does the JSON read/merge/write safely.
SETTINGS="$SETTINGS" MARKET_NAME="$MARKET_NAME" MARKET_REPO="$MARKET_REPO" \
PLUGINS_CSV="$(IFS=,; echo "${PLUGINS[*]:-}")" \
python3 <<'PY'
import json, os

settings = os.environ["SETTINGS"]
name = os.environ["MARKET_NAME"]
repo = os.environ["MARKET_REPO"]
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

with open(settings, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")

print(f"Wrote {settings}: marketplace '{name}' -> {repo}; enabled {len(plugins)} plugin(s).")
PY

if [[ -n "$ADD_CI" ]]; then
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

echo "Done. Commit .claude/settings.json (and any workflow) so it applies in web sessions."
