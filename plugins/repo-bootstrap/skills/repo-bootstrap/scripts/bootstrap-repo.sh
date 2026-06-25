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
#   --auto-update              Also set "autoUpdate": true on the marketplace entry so Claude Code
#                              refreshes the catalog on startup. CAVEAT: as of mid-2026 this is
#                              reported to refresh catalog metadata but NOT re-install plugin code
#                              for third-party marketplaces (anthropics/claude-code#61854) — the
#                              reliable way to get a published fix is `claude plugin update <name>`.
#   --portka-standard          Also install the Portka standard setup: a workflow CLAUDE.md (update
#                              main first, branch per change, tests+CI then a PR, merge on green), a
#                              permissions allowlist for the git/gh commands it needs, and — for the
#                              repo — a VERSION / CHANGELOG.md / README version line kept in sync, a
#                              basic tests/run-tests.sh that enforces that sync, and CI to run it.
#   --scope <user|project|both>  Where --portka-standard writes the CLAUDE.md + permissions:
#                              user = ~/.claude (your machine), project = ./.claude (committed; web
#                              sessions + team), both = default. The VERSION/CHANGELOG/tests scaffold
#                              is always written to the repo (existing files are never clobbered).
#   --home <path>              Home dir for user-scope writes (default: $HOME). Mainly for testing.
#   -h, --help                 Show this help.
#
# Examples:
#   bootstrap-repo.sh --plugin video-bug-analyzer --ci
#   bootstrap-repo.sh --plugin video-bug-analyzer --plugin other-plugin
#   bootstrap-repo.sh --plugin video-bug-analyzer --portka-standard   # + Portka standard setup
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
AUTO_UPDATE=""   # ADDED (1.0.3): --auto-update sets "autoUpdate": true on the marketplace entry
PORTKA_STANDARD=""        # ADDED (1.1.1): install the Portka standard setup (workflow + sync scaffold)
SCOPE=""                  # ADDED (1.1.1): user|project|both for --portka-standard (default: both)
HOME_DIR="${HOME:-}"      # ADDED (1.1.1): home dir for user-scope writes; overridable with --home

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
    "$DIR/.claude-plugin/marketplace.json"; do
    [[ -n "$c" && -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  # CHANGED (1.0.3, P2-1): walk upward from this script (bounded) instead of a brittle fixed
  # "../../../../../" — the depth differs between a repo checkout and the installed-plugin cache
  # (.../cache/<marketplace>/<plugin>/<version>/...). Find the nearest enclosing marketplace.json.
  local d="$SCRIPT_DIR" i
  for ((i = 0; i < 8; i++)); do
    [[ -f "$d/.claude-plugin/marketplace.json" ]] && { printf '%s\n' "$d/.claude-plugin/marketplace.json"; return 0; }
    d="$(dirname "$d")"
    [[ "$d" == "/" ]] && break
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
    --auto-update) AUTO_UPDATE="1"; shift ;;   # ADDED (1.0.3): set autoUpdate on the marketplace
    --portka-standard) PORTKA_STANDARD="1"; shift ;;   # ADDED (1.1.1)
    --scope) SCOPE="${2:-}"; shift 2 ;;                # ADDED (1.1.1)
    --home) HOME_DIR="${2:-}"; shift 2 ;;              # ADDED (1.1.1)
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# --portka-standard implies CI (so the scaffolded suite actually runs) and defaults its scope.
if [[ -n "$PORTKA_STANDARD" ]]; then
  ADD_CI="1"
  SCOPE="${SCOPE:-both}"
  case "$SCOPE" in
    user|project|both) ;;
    *) echo "Error: --scope must be user|project|both (got '$SCOPE')." >&2; exit 2 ;;
  esac
fi

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
DRY_RUN="$DRY_RUN" AUTO_UPDATE="$AUTO_UPDATE" \
PLUGINS_CSV="$(IFS=,; echo "${PLUGINS[*]:-}")" \
python3 <<'PY'
import json, os

settings = os.environ["SETTINGS"]
name = os.environ["MARKET_NAME"]
repo = os.environ["MARKET_REPO"]
dry = bool(os.environ.get("DRY_RUN"))
auto_update = bool(os.environ.get("AUTO_UPDATE"))
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
# Merge into any existing entry so other keys (incl. a user-set autoUpdate) survive (P1-1).
entry = markets.setdefault(name, {})
entry["source"] = {"source": "github", "repo": repo}
if auto_update:                      # only set when --auto-update is passed; never clobber otherwise
    entry["autoUpdate"] = True

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

# ----------------------------------------------------------------------------------------
# Portka standard setup (--portka-standard): a workflow CLAUDE.md + a git/gh permissions
# allowlist (user and/or project scope), plus a repo VERSION / CHANGELOG / README version
# triplet kept in sync by a basic, enforcing tests/run-tests.sh. ADDED (1.1.1).
# ----------------------------------------------------------------------------------------
if [[ -n "$PORTKA_STANDARD" ]]; then
  WANT_USER=""; WANT_PROJECT=""
  case "$SCOPE" in
    user) WANT_USER="1" ;;
    project) WANT_PROJECT="1" ;;
    both) WANT_USER="1"; WANT_PROJECT="1" ;;
  esac

  # Pre-approve the git/gh commands the workflow runs, so the back-and-forth stays on the code
  # rather than re-approving the same tools every session.
  STD_PERMS_JSON='["Bash(git status:*)","Bash(git checkout:*)","Bash(git switch:*)","Bash(git pull:*)","Bash(git fetch:*)","Bash(git branch:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git push:*)","Bash(git merge:*)","Bash(git rebase:*)","Bash(git diff:*)","Bash(git log:*)","Bash(gh pr:*)","Bash(gh run:*)","Bash(gh workflow:*)"]'

  # The standard workflow, written as a managed block into CLAUDE.md (the memory Claude loads
  # every session). Re-running replaces only the content between the markers.
  read -r -d '' STD_CLAUDE_BLOCK <<'MD' || true
# Portka standard workflow

Standing conventions for how Claude Code works here. Follow them for every change, without being
asked, so our back-and-forth stays on the code — not on process.

For each change you make:

1. **Update `main` first.** Begin by switching to `main` and pulling the latest. A previous
   change's branch being gone is the user's confirmation that they saw it (see step 5).
2. **Branch for everything.** Every fix, update, or change goes on a new branch — never commit to
   `main` directly.
3. **Tests + CI, then a PR.** Update the relevant tests, keep CI running them, and open a pull
   request. If the repo has no CI yet, add a basic workflow that runs the test suite.
4. **Green, then merge.** Wait until every check passes, then merge the PR automatically. Never
   merge on red.
5. **Hand back a short PR link.** Give the user a short link to the merged PR as confirmation. They
   delete the branch when satisfied — which you pick up next time you update `main` (step 1).

## Versioning — SemVer (enforced)

Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH` — **MAJOR** for
breaking changes, **MINOR** for backward-compatible features, **PATCH** for backward-compatible
fixes. One source of truth, three places kept in agreement, and every change bumps the right part:

- `VERSION` — the source of truth (a SemVer string).
- `CHANGELOG.md` — a `## [VERSION]` section (Keep a Changelog) for each released version.
- `README.md` — a `**Version:** VERSION` line that matches.

`tests/run-tests.sh` checks `VERSION` is valid SemVer and that all three agree; CI runs it on every
push/PR, so they can't drift.
MD

  BEGIN_MARK="<!-- BEGIN portka-standard (managed by repo-bootstrap — edit between the markers, or re-run to refresh) -->"
  END_MARK="<!-- END portka-standard -->"

  # write/refresh the managed CLAUDE.md block at a path (idempotent, dry-run aware).
  write_claude_md() {
    local path="$1"
    if [[ -n "$DRY_RUN" ]]; then
      echo "[dry-run] would write the Portka workflow block into $path"
      return 0
    fi
    mkdir -p "$(dirname "$path")"
    CLAUDE_PATH="$path" BEGIN_MARK="$BEGIN_MARK" END_MARK="$END_MARK" BLOCK="$STD_CLAUDE_BLOCK" \
    python3 <<'PY'
import os
path = os.environ["CLAUDE_PATH"]
begin, end = os.environ["BEGIN_MARK"], os.environ["END_MARK"]
block = os.environ["BLOCK"].rstrip("\n")
section = f"{begin}\n{block}\n{end}"
existing = ""
if os.path.exists(path):
    with open(path) as fh:
        existing = fh.read()
if begin in existing and end in existing:
    pre = existing.split(begin)[0]
    post = existing.split(end, 1)[1]
    out = f"{pre}{section}{post}"
else:
    if existing and not existing.endswith("\n"):
        existing += "\n"
    if existing and not existing.endswith("\n\n"):
        existing += "\n"
    out = f"{existing}{section}\n"
with open(path, "w") as fh:
    fh.write(out)
print(f"Wrote Portka workflow block -> {path}")
PY
  }

  # merge the standard permissions.allow into a settings.json (never clobber other keys).
  merge_perms() {
    local path="$1"
    [[ -n "$DRY_RUN" ]] || mkdir -p "$(dirname "$path")"
    SETTINGS="$path" PERMS="$STD_PERMS_JSON" DRY_RUN="$DRY_RUN" python3 <<'PY'
import json, os
path = os.environ["SETTINGS"]
perms = json.loads(os.environ["PERMS"])
dry = bool(os.environ.get("DRY_RUN"))
data = {}
if os.path.exists(path):
    with open(path) as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError:
            raise SystemExit(f"Error: {path} exists but is not valid JSON; fix or remove it first.")
allow = data.setdefault("permissions", {}).setdefault("allow", [])
added = [r for r in perms if r not in allow]
allow.extend(added)
if dry:
    print(f"[dry-run] would add {len(added)} permission rule(s) to {path}")
else:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print(f"Updated {path}: +{len(added)} permission rule(s) (allow).")
PY
  }

  # seed a content file only if absent — never clobber existing prose/history. content on stdin.
  seed_if_absent() {
    local path="$1" desc="$2" content
    content="$(cat)"
    if [[ -e "$path" ]]; then
      echo "exists, leaving as-is: $path" >&2
      return 0
    fi
    if [[ -n "$DRY_RUN" ]]; then
      echo "[dry-run] would write $path ($desc)"
      return 0
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "Wrote $path"
  }

  # User scope: ~/.claude/CLAUDE.md + ~/.claude/settings.json (your machine; persists locally).
  if [[ -n "$WANT_USER" ]]; then
    if [[ -z "$HOME_DIR" ]]; then
      echo "warning: no home dir (\$HOME unset and no --home); skipping user-scope writes." >&2
    else
      write_claude_md "$HOME_DIR/.claude/CLAUDE.md"
      merge_perms "$HOME_DIR/.claude/settings.json"
    fi
  fi

  # Project scope: ./.claude/CLAUDE.md + ./.claude/settings.json (committed; web sessions + team).
  if [[ -n "$WANT_PROJECT" ]]; then
    write_claude_md "$DIR/.claude/CLAUDE.md"
    merge_perms "$DIR/.claude/settings.json"
  fi

  # Repo scaffold: the VERSION / CHANGELOG / README version triplet + a basic enforcing test
  # suite. Always written to the repo (the sync is a property of the repo, not a scope). Existing
  # VERSION/CHANGELOG/README are never clobbered; the test runner only with --force.
  INIT_VERSION="0.1.0"
  TODAY="$(date +%F)"
  REPO_NAME="$(python3 -c 'import os,sys; print(os.path.basename(os.path.abspath(sys.argv[1])))' "$DIR")"

  seed_if_absent "$DIR/VERSION" "version source of truth" <<EOF
$INIT_VERSION
EOF

  seed_if_absent "$DIR/CHANGELOG.md" "Keep a Changelog history" <<EOF
# Changelog

All notable changes to this project are documented here. The format follows Keep a Changelog
(https://keepachangelog.com) and the project uses Semantic Versioning (https://semver.org).
Every change bumps VERSION and adds an entry below.

## [$INIT_VERSION] - $TODAY

### Added
- Initial scaffold via repo-bootstrap (Portka standard): branch-per-change workflow,
  version/CHANGELOG/README sync, a basic test suite, and CI.
EOF

  seed_if_absent "$DIR/README.md" "README with a synced version line" <<EOF
# $REPO_NAME

> **Version:** $INIT_VERSION

## Development

This repo follows the Portka standard workflow (see .claude/CLAUDE.md): every change goes on a
branch, updates tests + CI, and merges on green. The version follows SemVer, lives in VERSION, and
stays in sync with CHANGELOG.md and the line above — enforced by:

    bash tests/run-tests.sh
EOF

  # The basic, zero-dependency test runner that enforces the three-way version sync.
  RUNTESTS_PATH="$DIR/tests/run-tests.sh"
  if [[ -n "$DRY_RUN" ]]; then
    echo "[dry-run] would write $RUNTESTS_PATH (version/CHANGELOG/README sync suite)"
  elif [[ -f "$RUNTESTS_PATH" && -z "$FORCE" ]]; then
    echo "test runner already exists (use --force to overwrite): $RUNTESTS_PATH" >&2
  else
    mkdir -p "$DIR/tests"
    cat > "$RUNTESTS_PATH" <<'RUNTESTS'
#!/usr/bin/env bash
#
# run-tests.sh — basic suite scaffolded by repo-bootstrap (Portka standard).
# Enforces the VERSION / CHANGELOG.md / README.md version sync, then runs any tests/cases/*.sh.
# Exit 0 if nothing FAILed, 1 otherwise.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root: $ROOT" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }

# 1) VERSION exists and is SemVer.
VER=""
if [[ -f VERSION ]]; then
  VER="$(tr -d '[:space:]' < VERSION)"
  if [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$ ]]; then
    pass "VERSION is SemVer ($VER)"
  else
    fail "VERSION '$VER' is not SemVer"
  fi
else
  fail "VERSION file is missing"
fi

# 2) CHANGELOG.md has a section for VERSION.
if [[ -n "$VER" ]]; then
  if grep -qF "## [$VER]" CHANGELOG.md 2>/dev/null; then
    pass "CHANGELOG.md has a '## [$VER]' section"
  else
    fail "CHANGELOG.md is missing a '## [$VER]' heading"
  fi
fi

# 3) README.md's version line matches VERSION.
if [[ -n "$VER" && -f README.md ]]; then
  if grep -qF "**Version:** $VER" README.md; then
    pass "README.md version line matches ($VER)"
  else
    fail "README.md is missing a matching '**Version:** $VER' line"
  fi
fi

# 4) Project test cases (optional): every tests/cases/*.sh must exit 0.
shopt -s nullglob
for t in tests/cases/*.sh; do
  if bash "$t"; then pass "case: $t"; else fail "case: $t"; fi
done

echo
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
RUNTESTS
    chmod +x "$RUNTESTS_PATH"
    echo "Wrote $RUNTESTS_PATH"
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
