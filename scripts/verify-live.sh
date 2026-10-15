#!/usr/bin/env bash
#
# verify-live.sh - check that what's merged on main is what users actually get.
#
# Run it after every merge that bumps a plugin (RELEASING.md, "Verify the live sync"). Users install
# from the GitHub marketplace (`/plugin marketplace add cportka/claude-plugins`), so "live" means
# the published main branch as Claude Code resolves it, not just a green merge. Three legs:
#
#   1. RAW   - the marketplace.json + each plugin.json GitHub serves for --ref match the expected
#              versions (default: origin/main of this checkout, fetched fresh).
#   2. INSTALL (needs the `claude` CLI; skip with --no-install) - in a throwaway HOME, add the
#              marketplace, install every plugin, and check that (a) the installed version is the
#              expected one, (b) the installed files are byte-identical to the expected tree, and
#              (c) every shell script parses and each entrypoint's --help runs.
#   3. COMMUNITY (informational; skip with --no-community) - whether anthropics/claude-plugins-
#              community lists our plugins yet, and at which pinned commit. That catalog is synced
#              nightly by Anthropic's review pipeline, so a lag of a day after a merge is normal.
#
# Usage:
#   scripts/verify-live.sh                     # all three legs against origin/main
#   scripts/verify-live.sh --ref <branch|sha>  # check a different published ref
#   scripts/verify-live.sh --no-install --no-community
#   scripts/verify-live.sh -h | --help
#
# Exit 0 = legs 1-2 match; 1 = a mismatch (named); 2 = usage / environment error. Leg 3 never fails
# the run. Writes nothing outside a temp dir it removes on exit.
#
set -euo pipefail

REF="main"; DO_INSTALL=1; DO_COMMUNITY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --no-install) DO_INSTALL=""; shift ;;
    --no-community) DO_COMMUNITY=""; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MP=".claude-plugin/marketplace.json"
MARKET_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$MP")"
SLUG=""
_url="$(git config --get remote.origin.url 2>/dev/null || true)"
if [[ "$_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
  SLUG="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
elif [[ "$_url" =~ /git/([^/]+)/([^/.]+)$ ]]; then   # hosted git proxy remotes
  SLUG="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
fi
[[ -n "$SLUG" ]] || SLUG="cportka/claude-plugins"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
good() { printf '  ok    %s\n' "$1"; }
info() { printf '  info  %s\n' "$1"; }

# Expected = the ref as git sees it right now (fetched fresh, so a stale local ref can't vouch).
git fetch -q origin "$REF" 2>/dev/null || { echo "cannot fetch origin $REF" >&2; exit 2; }
EXPECT="$(git rev-parse FETCH_HEAD)"
mkdir -p "$TMP/expect"
git archive "$EXPECT" plugins .claude-plugin | tar -x -C "$TMP/expect" \
  || { echo "cannot extract $REF's plugin tree" >&2; exit 2; }
PLUGINS="$(python3 -c 'import json,sys; print(" ".join(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' "$TMP/expect/$MP")"
ver_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$1" 2>/dev/null || true; }

echo "verify-live: $SLUG @ $REF ($(git rev-parse --short "$EXPECT")) - marketplace '$MARKET_NAME'"

# --- 1. raw files GitHub serves ---------------------------------------------------------------
echo "[1/3] raw.githubusercontent.com"
RAW="https://raw.githubusercontent.com/$SLUG/$EXPECT"
if curl -fsS --max-time 30 "$RAW/$MP" -o "$TMP/raw-mp.json" 2>/dev/null; then
  if cmp -s "$TMP/raw-mp.json" "$TMP/expect/$MP"; then good "marketplace.json matches"
  else bad "marketplace.json served differs from the expected tree"; fi
  for p in $PLUGINS; do
    m="plugins/$p/.claude-plugin/plugin.json"; want="$(ver_of "$TMP/expect/$m")"
    if curl -fsS --max-time 30 "$RAW/$m" -o "$TMP/raw-$p.json" 2>/dev/null; then
      got="$(ver_of "$TMP/raw-$p.json")"
      if [[ "$got" == "$want" ]]; then good "$p $got"; else bad "$p serves $got, expected $want"; fi
    else
      bad "$p: could not fetch $m"
    fi
  done
else
  bad "could not fetch $RAW/$MP (network policy?)"
fi

# --- 2. a real install, as a user gets it -----------------------------------------------------
echo "[2/3] clean install via the claude CLI"
if [[ -z "$DO_INSTALL" ]]; then
  info "skipped (--no-install)"
elif ! command -v claude >/dev/null 2>&1; then
  info "skipped (no claude CLI on PATH)"
else
  H="$TMP/home"; mkdir -p "$H"
  # A throwaway HOME so the user's real plugin cache and settings are never touched. The add uses
  # the repo slug + ref exactly as a user would (a ref other than main pins the marketplace to it).
  _src="$SLUG"; [[ "$REF" == "main" ]] || _src="$SLUG#$REF"
  if ! (cd "$TMP" && HOME="$H" timeout 300 claude plugin marketplace add "$_src" >"$TMP/add.log" 2>&1); then
    bad "marketplace add $_src failed: $(tail -1 "$TMP/add.log")"
  else
    for p in $PLUGINS; do
      (cd "$TMP" && HOME="$H" timeout 300 claude plugin install "$p@$MARKET_NAME" >"$TMP/i-$p.log" 2>&1) \
        || bad "install $p failed: $(tail -1 "$TMP/i-$p.log")"
    done
    (cd "$TMP" && HOME="$H" timeout 60 claude plugin list --json >"$TMP/list.json" 2>/dev/null) || echo "[]" >"$TMP/list.json"
    for p in $PLUGINS; do
      want="$(ver_of "$TMP/expect/plugins/$p/.claude-plugin/plugin.json")"
      read -r got path < <(python3 -c '
import json, sys
for e in json.load(open(sys.argv[1])):
    if e.get("id") == sys.argv[2]:
        print(e.get("version", ""), e.get("installPath", "")); break
else:
    print("- -")' "$TMP/list.json" "$p@$MARKET_NAME")
      if [[ "$got" != "$want" ]]; then bad "$p installed as $got, expected $want"; continue; fi
      # Byte-identical to the expected tree. The installer drops its own marker dotfiles into the
      # cache dir (.in_use, .orphaned_at, …) — ignore dotfiles that exist ONLY on the installed
      # side; anything else (a changed file, or an expected file that's missing) is a mismatch.
      diff -r "$TMP/expect/plugins/$p" "$path" 2>&1 \
        | grep -vE "^Only in ${path}(/[^:]*)?: \." >"$TMP/d-$p.txt" || true
      if [[ -s "$TMP/d-$p.txt" ]]; then
        bad "$p $got installed, but its files differ from $REF: $(head -1 "$TMP/d-$p.txt")"; continue
      fi
      smoke=""
      while IFS= read -r -d '' sh; do
        bash -n "$sh" 2>/dev/null || smoke="${smoke:+$smoke, }syntax:${sh#"$path"/}"
      done < <(find "$path" -name '*.sh' -print0)
      for ep in skills/video-bug-analysis/scripts/extract-frames.sh \
                skills/repo-bootstrap/scripts/bootstrap-repo.sh \
                skills/app-evaluation/scripts/evaluate-site.sh \
                skills/tab-formatting/scripts/format-tab.py; do
        [[ -f "$path/$ep" ]] || continue
        case "$ep" in
          *.py) python3 "$path/$ep" --help >/dev/null 2>&1 || smoke="${smoke:+$smoke, }--help:$ep" ;;
          *)    bash "$path/$ep" --help >/dev/null 2>&1 || smoke="${smoke:+$smoke, }--help:$ep" ;;
        esac
      done
      if [[ -z "$smoke" ]]; then good "$p $got installed, files identical, scripts run"
      else bad "$p $got: $smoke"; fi
    done
  fi
fi

# --- 3. Anthropic community catalog (informational) -------------------------------------------
echo "[3/3] anthropics/claude-plugins-community (informational)"
if [[ -z "$DO_COMMUNITY" ]]; then
  info "skipped (--no-community)"
elif curl -fsS --max-time 60 "https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json" -o "$TMP/community.json" 2>/dev/null; then
  # shellcheck disable=SC2086  # $PLUGINS is a space-separated list of kebab-case names, split on purpose
  SLUG="$SLUG" python3 - "$TMP/community.json" $PLUGINS <<'PY' || true
import json, os, sys
data = json.load(open(sys.argv[1]))
slug = os.environ["SLUG"].lower()
ours = {}
for e in data.get("plugins", []):
    src = e.get("source") or {}
    blob = json.dumps(src).lower() + " " + str(e.get("homepage", "")).lower()
    if slug in blob:
        ours[e.get("name")] = src
for p in sys.argv[2:]:
    if p in ours:
        s = ours[p]
        print(f"  info  {p}: listed (pinned {str(s.get('sha') or s.get('ref') or 'unpinned')[:12]})")
    else:
        print(f"  info  {p}: not listed yet (approval pending, or the nightly sync hasn't run)")
print(f"  info  catalog has {len(data.get('plugins', []))} plugins; {len(ours)} from {os.environ['SLUG']}")
PY
else
  info "could not fetch the community catalog (network policy?)"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "verify-live: OK - $REF is live and installs as expected."
else
  echo "verify-live: MISMATCH - see FAIL lines above."
fi
exit "$fail"
