#!/usr/bin/env bash
#
# run-tests.sh — self-contained, verifiable test suite for the claude-plugins repo.
#
# Validates the marketplace + plugin manifests, skill frontmatter, and the bundled
# extraction script (syntax, CLI behavior), then — when the tools are available — lints
# the scripts with shellcheck and runs a real end-to-end ffmpeg frame extraction.
#
# Steps that require a missing tool report SKIP instead of failing, so the suite runs
# anywhere. CI installs ffmpeg + shellcheck so every check runs for real.
#
# Usage:  bash tests/run-tests.sh
# Exit:   0 if no test FAILed, 1 otherwise.
#
set -uo pipefail

# Resolve repo root as the parent of this script's directory, regardless of CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root: $ROOT" >&2; exit 1; }

PASS=0
FAIL=0
SKIP=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; SKIP=$((SKIP + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

SCRIPT="plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh"

# --- 1. JSON manifests parse ----------------------------------------------------------
section "JSON manifests parse"
shopt -s nullglob
manifests=(.claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json)
if [[ ${#manifests[@]} -eq 0 ]]; then
  fail "no JSON manifests found"
fi
for f in "${manifests[@]}"; do
  if python3 -m json.tool "$f" >/dev/null 2>&1; then
    pass "valid JSON: $f"
  else
    fail "invalid JSON: $f"
  fi
done

# --- 2. marketplace.json structure ----------------------------------------------------
section "marketplace.json structure"
MP=".claude-plugin/marketplace.json"
if python3 - "$MP" <<'PY'
import json, os, sys
mp = sys.argv[1]
data = json.load(open(mp))
assert data.get("name"), "missing 'name'"
assert data.get("owner"), "missing 'owner'"
plugins = data.get("plugins")
assert isinstance(plugins, list) and plugins, "'plugins' must be a non-empty list"
root = os.path.dirname(os.path.dirname(mp))
for p in plugins:
    assert p.get("name"), "plugin entry missing 'name'"
    src = p.get("source")
    assert src, f"plugin {p.get('name')} missing 'source'"
    path = os.path.normpath(os.path.join(root, src))
    assert os.path.isdir(path), f"plugin source dir not found: {src}"
PY
then
  pass "marketplace.json has name/owner/plugins and every source dir exists"
else
  fail "marketplace.json structure invalid (see error above)"
fi

# --- 3. plugin.json required fields ---------------------------------------------------
section "plugin.json required fields"
for pj in plugins/*/.claude-plugin/plugin.json; do
  if python3 - "$pj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("name", "version", "license"):
    assert d.get(key), f"missing '{key}'"
PY
  then
    pass "has name/version/license: $pj"
  else
    fail "missing required field: $pj"
  fi
done

# --- 4. SKILL.md frontmatter ----------------------------------------------------------
section "SKILL.md frontmatter"
for skill in plugins/*/skills/*/SKILL.md; do
  if [[ "$(head -n1 "$skill")" == "---" ]] \
     && grep -q '^name:' "$skill" \
     && grep -q '^description:' "$skill"; then
    pass "frontmatter ok (name + description): $skill"
  else
    fail "frontmatter missing '---'/name/description: $skill"
  fi
done

# --- 5. extraction script present + executable ----------------------------------------
section "extraction script present + executable"
if [[ -f "$SCRIPT" ]]; then
  pass "script exists: $SCRIPT"
  if [[ -x "$SCRIPT" ]]; then
    pass "script is executable"
  else
    fail "script is not executable (chmod +x needed)"
  fi
else
  fail "script not found: $SCRIPT"
fi

# --- 6. bash syntax check on all plugin scripts ---------------------------------------
section "bash syntax check"
scripts=()
while IFS= read -r -d '' sh; do
  scripts+=("$sh")
done < <(find plugins tests -name '*.sh' -print0 2>/dev/null)
for sh in "${scripts[@]}"; do
  if bash -n "$sh" 2>/dev/null; then
    pass "bash -n clean: $sh"
  else
    fail "bash syntax error: $sh"
  fi
done

# --- 7. --help works ------------------------------------------------------------------
section "extract-frames.sh --help"
if help_out="$(bash "$SCRIPT" --help 2>&1)" && grep -qi 'usage' <<<"$help_out"; then
  pass "--help exits 0 and prints usage"
else
  fail "--help did not exit 0 / print usage"
fi

# --- 8. missing --video error path ----------------------------------------------------
section "extract-frames.sh error path"
bash "$SCRIPT" >/dev/null 2>&1
code=$?
if [[ $code -eq 2 ]]; then
  pass "missing --video exits 2"
else
  fail "missing --video exited $code (expected 2)"
fi

# --- 9. shellcheck (optional) ---------------------------------------------------------
section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  for sh in "${scripts[@]}"; do
    if shellcheck "$sh"; then
      pass "shellcheck clean: $sh"
    else
      fail "shellcheck findings: $sh"
    fi
  done
else
  skip "shellcheck not installed"
fi

# --- 10. end-to-end extraction (optional) ---------------------------------------------
section "end-to-end extraction"
if command -v ffmpeg >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  clip="$tmp/testclip.mp4"
  if ffmpeg -hide_banner -loglevel error -f lavfi \
       -i "testsrc=duration=3:size=320x240:rate=10" "$clip" -y 2>/dev/null; then
    # Dense mode: 1s window @ 5fps should yield several frames.
    if bash "$SCRIPT" --video "$clip" --start 1 --end 2 --fps 5 --out "$tmp/dense" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/dense" -name '*.png' | wc -l)" -gt 0 ]]; then
      pass "dense mode produced frames"
    else
      fail "dense mode produced no frames"
    fi
    # Scene mode should run without error.
    if bash "$SCRIPT" --video "$clip" --scene 0.1 --out "$tmp/scene" >/dev/null 2>&1; then
      pass "scene mode ran successfully"
    else
      fail "scene mode errored"
    fi
  else
    fail "could not generate test clip with ffmpeg"
  fi
  rm -rf "$tmp"
else
  skip "ffmpeg not installed (end-to-end extraction)"
fi

# --- Summary --------------------------------------------------------------------------
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
