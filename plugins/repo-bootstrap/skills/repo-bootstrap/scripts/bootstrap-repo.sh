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
#                              repo — an enforced SemVer version sync that BINDS to the repo's
#                              existing version (package.json / pyproject.toml / Cargo.toml / VERSION
#                              / README **Version:**), seeding a bare VERSION 0.1.0 only on a
#                              greenfield repo, plus a basic tests/run-tests.sh and CI to run it.
#   --scope <user|project|both>  Where --portka-standard writes the CLAUDE.md + permissions:
#                              user = ~/.claude (your machine), project = ./.claude (committed; web
#                              sessions + team), both = default. The version/sync scaffold is always
#                              written to the repo (existing files are never clobbered).
#   --home <path>              Home dir for user-scope writes (default: $HOME). Mainly for testing.
#   --print-only               Write nothing; print .claude/settings.json (and, with
#                              --portka-standard, the CLAUDE.md workflow block) to stdout for you to
#                              create by hand. A human-authored write isn't subject to Claude Code's
#                              auto-mode permission classifier the way an agent write can be (#59).
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
PRINT_ONLY=""             # ADDED (1.1.2, #59): print settings/CLAUDE.md to stdout for manual creation

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

# Detect a repo's version source of truth, echoing "<source>\t<version>" for the first one found
# (package.json, pyproject.toml, Cargo.toml, a bare VERSION, or a README **Version:** line), or
# nothing. Lets --portka-standard bind the sync check to an existing version instead of seeding a
# conflicting bare VERSION on a mature repo (#59).
detect_version() {
  TARGET="$1" python3 <<'PY'
import json, os, re
d = os.environ["TARGET"]
def emit(src, ver):
    ver = (ver or "").strip()
    if ver:
        print(f"{src}\t{ver}")
        raise SystemExit(0)
p = os.path.join(d, "package.json")
if os.path.isfile(p):
    try:
        emit("package.json", json.load(open(p)).get("version"))
    except Exception:
        pass
for fn in ("pyproject.toml", "Cargo.toml"):
    p = os.path.join(d, fn)
    if os.path.isfile(p):
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
        except Exception:
            txt = ""
        m = re.search(r'(?m)^\s*version\s*=\s*"([^"]+)"', txt)
        if m:
            emit(fn, m.group(1))
p = os.path.join(d, "VERSION")
if os.path.isfile(p):
    try:
        emit("VERSION", open(p).read())
    except Exception:
        pass
p = os.path.join(d, "README.md")
if os.path.isfile(p):
    try:
        txt = open(p, encoding="utf-8", errors="ignore").read()
    except Exception:
        txt = ""
    m = re.search(r'(?m)^\s*>?\s*\*\*Version:\*\*\s*([0-9][^\s|]*)', txt)
    if m:
        emit("README.md", m.group(1).rstrip(".,;·"))
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
    --print-only) PRINT_ONLY="1"; shift ;;            # ADDED (1.1.2, #59)
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# --portka-standard defaults its scope. (CI for the standard is written by the standard block under
# a specific name with collision detection — #59 — not via the generic --ci path.)
if [[ -n "$PORTKA_STANDARD" ]]; then
  SCOPE="${SCOPE:-both}"
  case "$SCOPE" in
    user|project|both) ;;
    *) echo "Error: --scope must be user|project|both (got '$SCOPE')." >&2; exit 2 ;;
  esac
fi

# --print-only and --dry-run are both no-write modes.
NO_WRITE=""
[[ -n "$DRY_RUN" || -n "$PRINT_ONLY" ]] && NO_WRITE="1"

# Portka standard: the git/gh permissions allowlist + the workflow text, defined once so that both
# --print-only (manual mode) and the writing path below emit the same content. ADDED (1.1.2).
STD_PERMS_JSON='["Bash(git status:*)","Bash(git checkout:*)","Bash(git switch:*)","Bash(git pull:*)","Bash(git fetch:*)","Bash(git branch:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git push:*)","Bash(git merge:*)","Bash(git rebase:*)","Bash(git diff:*)","Bash(git log:*)","Bash(gh pr:*)","Bash(gh run:*)","Bash(gh workflow:*)"]'
BEGIN_MARK="<!-- BEGIN portka-standard (managed by repo-bootstrap — edit between the markers, or re-run to refresh) -->"
END_MARK="<!-- END portka-standard -->"
STD_CLAUDE_BLOCK=""
if [[ -n "$PORTKA_STANDARD" ]]; then
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
fixes. Keep one source of truth and the other places in agreement, and bump the right part:

- the **version source of truth** — your project manifest (`package.json` / `pyproject.toml` /
  `Cargo.toml`), or a bare `VERSION` file if the repo has no manifest.
- `CHANGELOG.md` — a section for each released version (Keep a Changelog).
- `README.md` — a `**Version:**` line, if you keep one, that matches.

`tests/run-tests.sh` checks the version is valid SemVer and that these agree; CI runs it on every
push/PR, so they can't drift.
MD
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

# --print-only: emit the file(s) for the user to create by hand (a human write isn't gated by
# Claude Code's auto-mode classifier the way an agent write can be — #59), then exit without writing.
if [[ -n "$PRINT_ONLY" ]]; then
  echo "# Portka manual setup — create the file(s) below by hand (nothing was written)."
  echo ""
  echo "===== .claude/settings.json ====="
  SETTINGS="$SETTINGS" MARKET_NAME="$MARKET_NAME" MARKET_REPO="$MARKET_REPO" \
  AUTO_UPDATE="$AUTO_UPDATE" PLUGINS_CSV="$(IFS=,; echo "${PLUGINS[*]:-}")" \
  PERMS="$([[ -n "$PORTKA_STANDARD" ]] && printf '%s' "$STD_PERMS_JSON" || printf '[]')" \
  python3 <<'PY'
import json, os
settings = os.environ["SETTINGS"]
name = os.environ["MARKET_NAME"]
repo = os.environ["MARKET_REPO"]
plugins = [p for p in os.environ.get("PLUGINS_CSV", "").split(",") if p]
auto = bool(os.environ.get("AUTO_UPDATE"))
perms = json.loads(os.environ.get("PERMS", "[]"))
data = {}
if os.path.exists(settings):
    try:
        data = json.load(open(settings))
    except json.JSONDecodeError:
        data = {}
entry = data.setdefault("extraKnownMarketplaces", {}).setdefault(name, {})
entry["source"] = {"source": "github", "repo": repo}
if auto:
    entry["autoUpdate"] = True
enabled = data.setdefault("enabledPlugins", {})
for p in plugins:
    enabled[f"{p}@{name}"] = True
if perms:
    allow = data.setdefault("permissions", {}).setdefault("allow", [])
    for r in perms:
        if r not in allow:
            allow.append(r)
print(json.dumps(data, indent=2))
PY
  if [[ -n "$PORTKA_STANDARD" ]]; then
    echo ""
    echo "===== .claude/CLAUDE.md (append this block) ====="
    printf '%s\n%s\n%s\n' "$BEGIN_MARK" "$STD_CLAUDE_BLOCK" "$END_MARK"
  fi
  echo ""
  echo "Create the file(s) above by hand (or have the user paste them) and commit them — a"
  echo "human-authored write isn't subject to the auto-mode classifier that can refuse an"
  echo "agent-written .claude/settings.json. The version/sync scaffold is not classifier-gated;"
  echo "re-run without --print-only to write it."
  exit 0
fi

[[ -n "$NO_WRITE" ]] || mkdir -p "$SETTINGS_DIR"   # no writes in --dry-run / --print-only

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
# allowlist (user and/or project scope), plus an enforced SemVer version sync bound to the repo's
# existing version source (a manifest, or a bare VERSION on a greenfield repo). ADDED (1.1.1);
# native-version binding + collision-aware CI in 1.1.2 (#59).
# ----------------------------------------------------------------------------------------
if [[ -n "$PORTKA_STANDARD" ]]; then
  WANT_USER=""; WANT_PROJECT=""
  case "$SCOPE" in
    user) WANT_USER="1" ;;
    project) WANT_PROJECT="1" ;;
    both) WANT_USER="1"; WANT_PROJECT="1" ;;
  esac

  # STD_PERMS_JSON, STD_CLAUDE_BLOCK, BEGIN_MARK and END_MARK are defined once near the top (so
  # --print-only can reuse the same content); this block just writes them.

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

  # Repo scaffold: bind the version sync to the repo's existing source of truth (#59) — a project
  # manifest if present, else a bare VERSION — and enforce it with a basic test runner. Always
  # written to the repo (the sync is a property of the repo, not a scope). Existing
  # VERSION/CHANGELOG/README are never clobbered; the test runner only with --force.
  TODAY="$(date +%F)"
  REPO_NAME="$(python3 -c 'import os,sys; print(os.path.basename(os.path.abspath(sys.argv[1])))' "$DIR")"
  _ver_line="$(detect_version "$DIR")"          # "<src>\t<ver>" or empty
  if [[ -n "$_ver_line" ]]; then
    NATIVE_SRC="$(printf '%s' "$_ver_line" | cut -f1)"
    SYNC_VER="$(printf '%s' "$_ver_line" | cut -f2-)"
    echo "Detected version $SYNC_VER from $NATIVE_SRC — binding the sync check to it (not seeding VERSION)."
  else
    SYNC_VER="0.1.0"                             # greenfield: seed a bare VERSION as the source of truth
    seed_if_absent "$DIR/VERSION" "version source of truth" <<EOF
$SYNC_VER
EOF
  fi

  seed_if_absent "$DIR/CHANGELOG.md" "Keep a Changelog history" <<EOF
# Changelog

All notable changes to this project are documented here. The format follows Keep a Changelog
(https://keepachangelog.com) and the project uses Semantic Versioning (https://semver.org).
Every change bumps the version and adds an entry below.

## [$SYNC_VER] - $TODAY

### Added
- Initial scaffold via repo-bootstrap (Portka standard): branch-per-change workflow, an enforced
  SemVer version sync, a basic test suite, and CI.
EOF

  seed_if_absent "$DIR/README.md" "README with a synced version line" <<EOF
# $REPO_NAME

> **Version:** $SYNC_VER

## Development

This repo follows the Portka standard workflow (see .claude/CLAUDE.md): every change goes on a
branch, updates tests + CI, and merges on green. The version follows SemVer and stays in sync with
CHANGELOG.md and the line above — enforced by:

    bash tests/run-tests.sh
EOF

  # A basic, dependency-light test runner that binds to the repo's version source (manifest /
  # VERSION / README) and checks SemVer + CHANGELOG/README agreement.
  RUNTESTS_PATH="$DIR/tests/run-tests.sh"
  if [[ -n "$NO_WRITE" ]]; then
    echo "[dry-run] would write $RUNTESTS_PATH (version-sync suite)"
  elif [[ -f "$RUNTESTS_PATH" && -z "$FORCE" ]]; then
    echo "test runner already exists (use --force to overwrite): $RUNTESTS_PATH" >&2
  else
    mkdir -p "$DIR/tests"
    cat > "$RUNTESTS_PATH" <<'RUNTESTS'
#!/usr/bin/env bash
#
# run-tests.sh — basic suite scaffolded by repo-bootstrap (Portka standard).
# Binds to the repo's version source of truth (package.json / pyproject.toml / Cargo.toml /
# VERSION / README **Version:**), checks it is SemVer and that CHANGELOG.md and the README
# version line agree, then runs any tests/cases/*.sh. Exit 0 if nothing FAILed, 1 otherwise.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root: $ROOT" >&2; exit 1; }

PASS=0; FAIL=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }

# Find the version source of truth, preferring a project manifest over a bare VERSION / README.
detect_version() {
  local v=""
  if [[ -f package.json ]]; then
    if command -v node >/dev/null 2>&1; then
      v="$(node -e 'try{process.stdout.write(String(require("./package.json").version||""))}catch(e){}' 2>/dev/null)"
    elif command -v python3 >/dev/null 2>&1; then
      v="$(python3 -c 'import json;print(json.load(open("package.json")).get("version") or "")' 2>/dev/null)"
    else
      v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -1)"
    fi
    if [[ -n "$v" ]]; then printf 'package.json\t%s\n' "$v"; return; fi
  fi
  local f
  for f in pyproject.toml Cargo.toml; do
    if [[ -f "$f" ]]; then
      v="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)"
      if [[ -n "$v" ]]; then printf '%s\t%s\n' "$f" "$v"; return; fi
    fi
  done
  if [[ -f VERSION ]]; then
    v="$(tr -d '[:space:]' < VERSION)"
    if [[ -n "$v" ]]; then printf 'VERSION\t%s\n' "$v"; return; fi
  fi
  if [[ -f README.md ]]; then
    v="$(sed -n 's/.*\*\*Version:\*\*[[:space:]]*\([0-9][^ |]*\).*/\1/p' README.md | head -1)"
    if [[ -n "$v" ]]; then printf 'README.md\t%s\n' "$v"; return; fi
  fi
}

SRC_VER="$(detect_version)"
SRC="$(printf '%s' "$SRC_VER" | cut -f1)"
VER="$(printf '%s' "$SRC_VER" | cut -f2-)"

if [[ -z "$SRC_VER" ]]; then
  fail "no version source found (package.json / pyproject.toml / Cargo.toml / VERSION / README **Version:**)"
else
  if [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.]+)?$ ]]; then
    pass "version is SemVer ($VER from $SRC)"
  else
    fail "version '$VER' (from $SRC) is not SemVer"
  fi
  if [[ -f CHANGELOG.md ]]; then
    if grep -qF "$VER" CHANGELOG.md; then
      pass "CHANGELOG.md references $VER"
    else
      fail "CHANGELOG.md has no entry for $VER"
    fi
  fi
  # Cross-check the README version line only when one exists (don't force the convention on repos
  # that track their version elsewhere — requiring it is what made the old scaffold ship red, #59).
  if [[ -f README.md ]] && grep -q '\*\*Version:\*\*' README.md; then
    if grep -qF "**Version:** $VER" README.md; then
      pass "README **Version:** line matches ($VER)"
    else
      fail "README **Version:** line disagrees with $SRC ($VER)"
    fi
  fi
fi

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

  # Native version-sync test (1.2.0): when the repo has a JS/Python manifest, also emit the sync
  # check in its OWN runner (node:test / unittest) so `npm test` / `pytest` enforces it — not just
  # the standalone bash runner the #59 reporter wanted to avoid. (Cargo/others: see IMPROVEMENTS.)
  case "${NATIVE_SRC:-}" in
    package.json)
      NT="$DIR/tests/version-sync.test.mjs"
      if [[ -n "$NO_WRITE" ]]; then
        echo "[dry-run] would write $NT (node:test version sync)"
      elif [[ -e "$NT" ]]; then
        echo "exists, leaving as-is: $NT" >&2
      else
        mkdir -p "$DIR/tests"
        cat > "$NT" <<'MJS'
// version-sync.test.mjs — assert package.json's version is valid SemVer and documented in
// CHANGELOG.md. Scaffolded by repo-bootstrap (Portka standard); run with `node --test` (or vitest).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const version = JSON.parse(readFileSync(new URL("../package.json", import.meta.url))).version;

test("version is valid SemVer", () => {
  assert.match(version, /^\d+\.\d+\.\d+([-+][0-9A-Za-z.]+)?$/);
});

test("CHANGELOG.md documents the current version", () => {
  const log = readFileSync(new URL("../CHANGELOG.md", import.meta.url), "utf8");
  assert.ok(log.includes(version), `CHANGELOG.md has no entry for ${version}`);
});
MJS
        echo "Wrote $NT (node:test — run with 'node --test')"
      fi
      ;;
    pyproject.toml)
      NT="$DIR/tests/test_version_sync.py"
      if [[ -n "$NO_WRITE" ]]; then
        echo "[dry-run] would write $NT (unittest version sync)"
      elif [[ -e "$NT" ]]; then
        echo "exists, leaving as-is: $NT" >&2
      else
        mkdir -p "$DIR/tests"
        cat > "$NT" <<'PYT'
# test_version_sync.py — assert pyproject.toml's version is valid SemVer and documented in
# CHANGELOG.md. Scaffolded by repo-bootstrap (Portka standard); run with `pytest` or `python -m unittest`.
import re
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def project_version():
    txt = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    m = re.search(r'(?m)^\s*version\s*=\s*"([^"]+)"', txt)
    return m.group(1) if m else ""


class VersionSync(unittest.TestCase):
    def test_semver(self):
        self.assertRegex(project_version(), r"^\d+\.\d+\.\d+([-+][0-9A-Za-z.]+)?$")

    def test_changelog_has_version(self):
        v = project_version()
        self.assertTrue(v, "no version in pyproject.toml")
        self.assertIn(v, (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
PYT
        echo "Wrote $NT (unittest — run with 'pytest' or 'python -m unittest')"
      fi
      ;;
  esac

  # CI for the standard: a specifically-named workflow that runs the suite. Skip when the repo
  # already has CI so we don't collide with / duplicate it, unless --force (#59 minor).
  WF_STD="$DIR/.github/workflows/portka-standard.yml"
  shopt -s nullglob
  _existing_wf=("$DIR"/.github/workflows/*.yml "$DIR"/.github/workflows/*.yaml)
  shopt -u nullglob
  if [[ -n "$NO_WRITE" ]]; then
    echo "[dry-run] would write $WF_STD (runs tests/run-tests.sh), unless existing CI is detected"
  elif [[ ${#_existing_wf[@]} -gt 0 && -z "$FORCE" ]]; then
    echo "existing CI detected (${#_existing_wf[@]} workflow(s)); not adding portka-standard.yml — make sure your CI runs 'bash tests/run-tests.sh' (use --force to add it anyway)." >&2
  elif [[ -f "$WF_STD" && -z "$FORCE" ]]; then
    echo "CI workflow already exists (use --force to overwrite): $WF_STD" >&2
  else
    mkdir -p "$DIR/.github/workflows"
    cat > "$WF_STD" <<'YAML'
name: portka-standard

on:
  push:
  pull_request:

jobs:
  checks:
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
    echo "Wrote $WF_STD"
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
