#!/usr/bin/env bash
#
# publish.sh - one-stop helper to publish / refresh this marketplace to the Claude Code community.
#
# It DOES the steps that have a real API (validate, GitHub topics, description, homepage, Pages, and
# - behind --release - a GitHub Release), and it PRINTS an exact, verified checklist for the steps
# that need a human web/OAuth action (the Anthropic community-marketplace submission, the social
# preview image, the awesome-list issue form, and the announcement channels). Everything here is
# grounded in docs/DISTRIBUTION.md, which carries the source links and confidence notes.
#
# Nothing runs by default - you get the plan. Add --run to execute the API-backed steps.
#
# Usage:
#   scripts/publish.sh                 # print the full plan + manual checklist (no changes)
#   scripts/publish.sh --dry-run       # same, but only the API commands (still executes nothing)
#   scripts/publish.sh --run           # execute the API-backed metadata steps (needs gh or GH_TOKEN)
#   scripts/publish.sh --run --skip-tests   # skip the local e2e test suite (advisory anyway)
#   scripts/publish.sh --run --release # also cut a GitHub Release for the current version
#   scripts/publish.sh -h | --help
#
# Auth for --run: either the GitHub CLI (`gh auth login`) or a GH_TOKEN env var with repo + admin
# scope. If neither is present, --run degrades to the same plan the default prints.
#
# The gate is the marketplace structure (validated inline, and via `claude plugin validate` when the
# CLI is present). The full test suite is ADVISORY: it needs ffmpeg/tesseract/chromium/GNU coreutils
# for its e2e legs, so a missing tool makes it fail rather than skip on some setups - publish.sh
# surfaces exactly what failed (and a tool check) but does NOT block the independent metadata steps.
# --skip-tests skips running it entirely; --verbose adds an up-front environment report.
#
# Repo-file edits (e.g. enriching marketplace.json) are NOT auto-applied - the script only reports
# what to add, so file changes still go through the branch -> PR -> green -> merge flow (CLAUDE.md).
#
set -euo pipefail

RUN=""            # --run: execute the API steps (else just plan)
DRY_RUN=""        # --dry-run: print the exact commands, execute nothing
DO_RELEASE=""     # --release: also cut a GitHub Release (with --run)
SKIP_TESTS=""     # --skip-tests: don't run the (advisory) local test suite
VERBOSE=""        # --verbose: print an environment/tool report up front

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --release) DO_RELEASE=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root" >&2; exit 1; }

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '  %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1" >&2; }
todo() { printf '  \033[33m[ ]\033[0m %s\n' "$1"; }
executing() { [[ -n "$RUN" && -z "$DRY_RUN" ]]; }

# Report which relevant tools are present - a missing one is the usual reason the e2e test suite
# "FAILED" instead of skipping. Prints to stderr so it never pollutes captured stdout.
tool_report() {
  local t
  for t in bash python3 ffmpeg ffprobe node shellcheck tesseract gh curl; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '    %-11s %s\n' "$t" "$(command -v "$t")" >&2
    else
      printf '    %-11s \033[33mMISSING\033[0m\n' "$t" >&2
    fi
  done
  printf '    %-11s %s\n' "bash-ver" "${BASH_VERSION:-unknown}" >&2
  printf '    %-11s %s\n' "uname" "$(uname -s 2>/dev/null || echo '?')" >&2
}

MP=".claude-plugin/marketplace.json"
[[ -f "$MP" ]] || { echo "Error: $MP not found - run from a marketplace repo." >&2; exit 2; }

# --- identifiers: derive from git + marketplace.json so this works on a fork too ----------------
OWNER=""; REPO=""
_url="$(git config --get remote.origin.url 2>/dev/null || true)"
if [[ "$_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"
fi
MARKETPLACE=""; PLUGINS=()
if command -v python3 >/dev/null 2>&1; then
  MARKETPLACE="$(python3 -c 'import json;print(json.load(open(".claude-plugin/marketplace.json")).get("name",""))' 2>/dev/null || true)"
  while IFS= read -r _p; do [[ -n "$_p" ]] && PLUGINS+=("$_p"); done < <(
    python3 -c 'import json;[print(p["name"]) for p in json.load(open(".claude-plugin/marketplace.json")).get("plugins",[])]' 2>/dev/null || true)
fi
OWNER="${OWNER:-cportka}"; REPO="${REPO:-claude-plugins}"; MARKETPLACE="${MARKETPLACE:-portka-tools}"
PAGES="https://${OWNER}.github.io/${REPO}"

# de-facto ecosystem topics (docs/DISTRIBUTION.md section 1; ~10 is right, max 20).
TOPICS=(claude-code-plugin claude-plugin claude-code-marketplace claude-code-plugins-marketplace \
        claude-code claude-plugins claude-skills mcp anthropic ai-agents)
DESC="Claude Code plugin marketplace - add with: /plugin marketplace add ${OWNER}/${REPO}"

# --- API plumbing: prefer gh, fall back to curl + GH_TOKEN, else plan-only ----------------------
API_MODE="none"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  API_MODE="gh"
elif [[ -n "${GH_TOKEN:-}" ]]; then
  API_MODE="curl"
fi

# gh_api METHOD PATH [json-body] - print the intended call; execute it only under --run.
# Called directly (not via a dispatcher) so it stays reachable + shellcheck-clean.
gh_api() {
  local method="$1" path="$2" body="${3:-}"
  case "$API_MODE" in
    gh)   printf '    $ gh api -X %s %s%s\n' "$method" "$path" "${body:+ --input -}" ;;
    curl) printf '    $ curl -X %s https://api.github.com/%s%s\n' "$method" "$path" "${body:+ -d <json>}" ;;
    none) printf '    (needs gh or GH_TOKEN to run) %s %s\n' "$method" "$path" ;;
  esac
  executing || return 0
  case "$API_MODE" in
    gh)
      if [[ -n "$body" ]]; then gh api -X "$method" "$path" --input - <<<"$body" >/dev/null
      else gh api -X "$method" "$path" >/dev/null; fi ;;
    curl)
      if [[ -n "$body" ]]; then
        curl -fsS -X "$method" -H "Authorization: Bearer ${GH_TOKEN}" \
          -H "Accept: application/vnd.github+json" "https://api.github.com/${path}" -d "$body" >/dev/null
      else
        curl -fsS -X "$method" -H "Authorization: Bearer ${GH_TOKEN}" \
          -H "Accept: application/vnd.github+json" "https://api.github.com/${path}" >/dev/null
      fi ;;
    *) return 0 ;;
  esac
}

bold "Publish plan for ${MARKETPLACE} (${OWNER}/${REPO})"
note "plugins: ${PLUGINS[*]:-<none parsed>}"
note "pages:   ${PAGES}"
if [[ -n "$RUN" && "$API_MODE" == "none" ]]; then
  note "--run requested but no auth found (no gh login, no GH_TOKEN) - printing the plan instead."
  RUN=""
fi
case "$API_MODE" in
  gh)   note "auth: GitHub CLI (gh)" ;;
  curl) note "auth: GH_TOKEN via curl" ;;
  none) note "auth: none (plan only; install gh or set GH_TOKEN to execute)" ;;
esac
if [[ -n "$VERBOSE" ]]; then
  step "Environment"
  tool_report
fi

# --- 1. validate (the gate) ---------------------------------------------------------------------
step "1. Validate the marketplace + plugins (gate)"
# Structural gate that does NOT need the claude CLI: JSON parses, required fields, source dirs exist,
# kebab-case names. This is the real go/no-go for the metadata steps below.
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$MP" <<'PY'
import json, os, re, sys
mp = json.load(open(sys.argv[1]))
assert mp.get("name"), "marketplace 'name' missing"
assert mp.get("owner"), "marketplace 'owner' missing"
plugins = mp.get("plugins")
assert isinstance(plugins, list) and plugins, "'plugins' must be a non-empty list"
root = os.path.dirname(os.path.dirname(sys.argv[1]))
bad = []
for p in plugins:
    n = p.get("name", "")
    if not n: bad.append("a plugin entry is missing 'name'")
    if n and not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", n): bad.append(f"{n}: not kebab-case (claude.ai sync rejects it)")
    src = p.get("source", "")
    if not src: bad.append(f"{n or '?'}: missing 'source'")
    elif not os.path.isdir(os.path.join(root, src)): bad.append(f"{n or src}: source dir not found ({src})")
if bad:
    print("\n".join("  - " + b for b in bad), file=sys.stderr); sys.exit(1)
PY
  then
    note "marketplace.json: valid (name/owner/plugins, kebab-case, source dirs exist)"
  else
    echo "  marketplace.json is INVALID - fix before publishing (details above)." >&2; exit 1
  fi
else
  warn "python3 not found - cannot structurally validate marketplace.json (install python3)."
fi
# Deeper validation via the Claude Code CLI when it's on PATH (also what the submission runs).
if command -v claude >/dev/null 2>&1; then
  note '$ claude plugin validate .'
  if executing; then
    if claude plugin validate .; then note "claude plugin validate: clean"; else echo "  claude plugin validate FAILED - fix before publishing." >&2; exit 1; fi
  fi
  note "(kebab-case names are required for the claude.ai sync)"
else
  note "claude CLI not on PATH - skipped (the inline check above already gated the structure;"
  note " run 'claude plugin validate .' yourself for the deeper skill/agent/hook frontmatter checks)."
fi
# The full test suite is ADVISORY (its e2e legs need ffmpeg/tesseract/chromium/GNU tools). Surface
# exactly what fails + a tool report, but don't block the independent metadata steps.
if [[ -x tests/run-tests.sh ]]; then
  if [[ -n "$SKIP_TESTS" ]]; then
    note "test suite: skipped (--skip-tests)"
  elif executing; then
    note "Running the repo test suite (advisory: version sync + e2e)..."
    _testlog="$(mktemp)"
    if bash tests/run-tests.sh >"$_testlog" 2>&1; then
      note "test suite: $(sed 's/\x1b\[[0-9;]*m//g' "$_testlog" | grep -oE '[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped' | tail -1)"
      rm -f "$_testlog"
    else
      warn "test suite reported failures (advisory - NOT blocking the metadata steps below):"
      sed 's/\x1b\[[0-9;]*m//g' "$_testlog" | grep -E '^[[:space:]]*FAIL[[:space:]]' | sed 's/^ */    /' >&2 || true
      sed 's/\x1b\[[0-9;]*m//g' "$_testlog" | grep -E 'Summary:' | sed 's/^/    /' >&2 || true
      echo "    full log: $_testlog" >&2
      echo "    tool check (a MISSING tool usually explains an e2e failure that should have skipped):" >&2
      tool_report
      echo "    -> if the failures are just missing tools, they don't affect publishing; re-run with" >&2
      echo "       --skip-tests to quiet this. Otherwise 'bash tests/run-tests.sh' locally to fix them." >&2
    fi
  else
    note "test suite: run 'bash tests/run-tests.sh' (runs automatically under --run; advisory)"
  fi
fi

# --- 2. topics ----------------------------------------------------------------------------------
step "2. Set GitHub topics (feeds aggregators + GitHub topic/search pages)"
_topics_json="$(printf '%s\n' "${TOPICS[@]}" | python3 -c 'import json,sys;print(json.dumps({"names":[l.strip() for l in sys.stdin if l.strip()]}))' 2>/dev/null || echo '{}')"
gh_api PUT "repos/${OWNER}/${REPO}/topics" "$_topics_json" || note "topics: skipped/failed"
note "topics: ${TOPICS[*]}"

# --- 3. description + homepage ------------------------------------------------------------------
step "3. Set repo description + homepage (default-ranked GitHub search fields)"
_repo_json="$(python3 -c 'import json,sys;print(json.dumps({"description":sys.argv[1],"homepage":sys.argv[2]}))' "$DESC" "$PAGES" 2>/dev/null || echo '{}')"
gh_api PATCH "repos/${OWNER}/${REPO}" "$_repo_json" || note "description: skipped/failed"
note "description: ${DESC}"
note "homepage:    ${PAGES}"

# --- 4. GitHub Pages ----------------------------------------------------------------------------
step "4. Ensure GitHub Pages serves the landing page (main /)"
if [[ -f index.html && -f .nojekyll ]]; then
  # POST enables; if already enabled it errors, so reconcile with PUT.
  if ! gh_api POST "repos/${OWNER}/${REPO}/pages" '{"source":{"branch":"main","path":"/"}}'; then
    gh_api PUT "repos/${OWNER}/${REPO}/pages" '{"source":{"branch":"main","path":"/"}}' \
      || note "pages: already enabled, or enable it once via Settings -> Pages"
  fi
  note "serves: ${PAGES}  (a human landing surface only - users still add the marketplace as ${OWNER}/${REPO})"
else
  note "no index.html/.nojekyll at root - skipping Pages."
fi

# --- 5. GitHub Release (flag-gated) -------------------------------------------------------------
step "5. Cut a GitHub Release for the current version (optional; --release)"
VERSION="$(sed -n 's/^> \*\*Version:\*\* \([0-9][0-9.A-Za-z-]*\).*/\1/p' README.md 2>/dev/null | head -n1 || true)"
note "current version (README header): ${VERSION:-unknown}"
if [[ -n "$DO_RELEASE" && -n "$VERSION" ]]; then
  note "\$ git tag -a v${VERSION} -m \"${MARKETPLACE} ${VERSION}\" && git push origin v${VERSION}"
  note "(a v* tag triggers .github/workflows/release.yml, which reads the CHANGELOG section)"
  if executing && command -v gh >/dev/null 2>&1; then
    if gh release view "v${VERSION}" >/dev/null 2>&1; then
      note "release v${VERSION} already exists - nothing to do."
    else
      gh release create "v${VERSION}" --generate-notes --title "v${VERSION}" || note "release: create it via the tag push above"
    fi
  fi
else
  note "(pass --release to cut it; or tag manually - see RELEASING.md)"
fi

# --- 6. marketplace.json discovery metadata (report only - repo edits go via PR) ----------------
step "6. marketplace.json discovery metadata (report; edits go via a PR)"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$MP" <<'PY' || true
import json, sys
mp = json.load(open(sys.argv[1]))
if not mp.get("description"):
    print("  [ ] add a top-level marketplace 'description'")
for p in mp.get("plugins", []):
    miss = [k for k in ("description", "homepage", "repository", "license", "keywords") if not p.get(k)]
    if miss:
        print(f"  [ ] {p['name']}: add {', '.join(miss)} to its marketplace entry (or plugin.json)")
    if p.get("version"):
        print(f"  [ ] {p['name']}: 'version' set in the entry - keep it in one place (plugin.json OR the entry)")
print("  (these power the in-client Discover search + aggregator cards; add on a branch -> PR)")
PY
fi

# --- 7. community-marketplace landing check -----------------------------------------------------
step "7. Check whether your plugins have landed in the Anthropic community catalog"
_cat="https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json"
if [[ ${#PLUGINS[@]} -gt 0 ]] && command -v curl >/dev/null 2>&1; then
  _catjson="$(curl -fsSL --max-time 15 "$_cat" 2>/dev/null || true)"
  if [[ -n "$_catjson" ]]; then
    for _p in "${PLUGINS[@]}"; do
      if grep -q "\"${_p}\"" <<<"$_catjson"; then note "listed: ${_p} [ok]"; else note "not yet listed: ${_p} (submit + wait for the nightly sync - see section 8)"; fi
    done
  else
    note "could not fetch the community catalog (offline?) - check manually: ${_cat}"
  fi
else
  note "skipped (need curl + parsed plugin names)."
fi

# --- 8. manual checklist (human web / OAuth - verified URLs) ------------------------------------
step "8. MANUAL steps (no API - do these in a browser; verified in docs/DISTRIBUTION.md)"
bold "  Primary - get into the client where users browse:"
todo "Submit each plugin to the Anthropic COMMUNITY marketplace: https://clau.de/plugin-directory-submission"
note "     (individual authors: https://platform.claude.com/plugins/submit)"
note "     After approval it syncs nightly; users install with: /plugin install <name>@claude-community"
todo "Upload a 1280x640 social-preview PNG: repo Settings -> General -> Social preview -> Edit"
bold "  Directories (developers browse these; some crawl GitHub daily):"
todo "awesome-claude-code (issue form, NOT a PR): https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml"
todo "buildwithclaude (PR): fork davepoon/buildwithclaude, stage with submissions/buildwithclaude/prepare.sh, gh pr create"
note "claudemarketplaces.com: auto-crawls GitHub daily for a valid marketplace.json - you already qualify; just verify the listing appears."
bold "  Announce (personal accounts; read each venue's self-promo rules first):"
todo "Show HN: https://news.ycombinator.com/submit  (title 'Show HN: ${MARKETPLACE} - <one line>', URL = the repo)"
todo "X/Twitter: short thread + demo GIF, tag @ClaudeDevs @AnthropicAI, #ClaudeCode"
todo "r/ClaudeCode + r/ClaudeAI: READ the sidebar/self-promo rules first; don't cross-post identical text"
todo "dev.to launch/tutorial (canonical_url -> repo), optionally cross-post to Hashnode"
todo "Official Claude Discord (invite via https://claude.com/community) -> the showcase/community-projects channel"

printf '\n'
bold "Full playbook with sources + confidence notes: docs/DISTRIBUTION.md"
[[ -z "$RUN" ]] && note "This was a plan only - re-run with --run to execute steps 2-4 (and --release for step 5)."
exit 0
