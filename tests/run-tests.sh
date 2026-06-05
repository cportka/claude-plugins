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
BOOTSTRAP="plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh"

# --- 1. JSON manifests parse ----------------------------------------------------------
section "JSON manifests parse"
shopt -s nullglob
manifests=(.claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json)
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

# --- 2b. marketplace <-> plugins consistency ------------------------------------------
section "marketplace <-> plugins consistency"
if python3 <<'PY'
import glob, json, os
mp = json.load(open(".claude-plugin/marketplace.json"))
registered = {os.path.normpath(e["source"]): e for e in mp["plugins"]}
# Every plugin directory on disk must be registered (no orphan plugins).
for pj in glob.glob("plugins/*/.claude-plugin/plugin.json"):
    d = os.path.dirname(os.path.dirname(pj))
    assert d in registered, f"plugin dir {d} is not registered in marketplace.json"
# Every registered entry must have a plugin.json whose name matches entry + directory.
for src, entry in registered.items():
    pj = os.path.join(src, ".claude-plugin", "plugin.json")
    assert os.path.isfile(pj), f"missing {pj} for marketplace entry '{entry['name']}'"
    pdata = json.load(open(pj))
    assert pdata["name"] == entry["name"], (
        f"name mismatch: plugin.json '{pdata['name']}' vs marketplace '{entry['name']}'")
    assert pdata["name"] == os.path.basename(src), (
        f"name '{pdata['name']}' != directory '{os.path.basename(src)}'")
PY
then
  pass "every plugin is registered and names match (entry == plugin.json == dir)"
else
  fail "marketplace/plugin mismatch (see error above)"
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

# --- 3b. semver + README version sync -------------------------------------------------
section "versions: semver + README sync"
for pj in plugins/*/.claude-plugin/plugin.json; do
  ver="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$pj")"
  name="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$pj")"
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "semver $ver: $name"
  else
    fail "non-semver version '$ver': $pj"
  fi
  if grep -qF "$ver" README.md; then
    pass "README lists $name $ver"
  else
    fail "README does not mention $name version $ver"
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

# --- 4b. plugin hooks (if any) --------------------------------------------------------
section "plugin hooks"
hooks_found=0
for hj in plugins/*/hooks/hooks.json; do
  hooks_found=1
  hook_dir="$(dirname "$hj")"
  if python3 - "$hj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hooks = d.get("hooks", {})
assert isinstance(hooks, dict) and hooks, "'hooks' must be a non-empty object"
for event, entries in hooks.items():
    assert isinstance(entries, list) and entries, f"{event} must be a non-empty list"
    for entry in entries:
        for h in entry.get("hooks", []):
            assert h.get("command"), "hook entry missing 'command'"
PY
  then
    pass "valid hooks config: $hj"
  else
    fail "invalid hooks config: $hj"
    continue
  fi
  # Every ${CLAUDE_PLUGIN_ROOT}-relative script the hooks reference must exist.
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    target="$hook_dir/../$rel"
    if [[ ! -f "$target" ]]; then
      fail "hook script missing: $rel (referenced by $hj)"
    elif [[ ! -x "$target" ]]; then
      fail "hook script not executable: $rel"
    else
      pass "hook script present + executable: $rel"
    fi
  done < <(python3 - "$hj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for entries in d.get("hooks", {}).values():
    for entry in entries:
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            if "${CLAUDE_PLUGIN_ROOT}/" in cmd:
                print(cmd.split("${CLAUDE_PLUGIN_ROOT}/", 1)[1].split()[0])
PY
)
done
[[ $hooks_found -eq 1 ]] || skip "no plugin hooks to validate"

# --- 4c. issue templates (if any) -----------------------------------------------------
section "issue templates"
it_found=0
for tmpl in .github/ISSUE_TEMPLATE/*.yml; do
  base="$(basename "$tmpl")"
  [[ "$base" == "config.yml" ]] && continue   # config.yml is settings, not a form
  it_found=1
  if [[ -s "$tmpl" ]] && grep -q '^name:' "$tmpl" && grep -q '^description:' "$tmpl"; then
    pass "issue form has name + description: $tmpl"
  else
    fail "issue form empty or missing name/description: $tmpl"
  fi
done
[[ $it_found -eq 1 ]] || skip "no issue form templates"

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
    # Contact-sheet mode: should tile frames into at least one contact_*.png.
    if bash "$SCRIPT" --video "$clip" --start 0 --end 3 --fps 4 --contact --out "$tmp/contact" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/contact" -name 'contact_*.png' | wc -l)" -gt 0 ]]; then
      pass "contact-sheet mode produced a sheet"
    else
      fail "contact-sheet mode produced no sheet"
    fi
    # Timestamp mode: a burst + a before/after strip per timestamp.
    if bash "$SCRIPT" --video "$clip" --timestamps 1,2 --fps 6 --window 0.4 --out "$tmp/ts" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/ts" -name 'ts01_[0-9]*.png' | wc -l)" -gt 0 ]] \
       && [[ -f "$tmp/ts/ts01_strip.png" ]]; then
      pass "timestamp mode produced burst + before/after strip"
    else
      fail "timestamp mode did not produce burst/strip"
    fi
  else
    fail "could not generate test clip with ffmpeg"
  fi
  rm -rf "$tmp"
else
  skip "ffmpeg not installed (end-to-end extraction)"
fi

# --- 11. repo-bootstrap end-to-end ----------------------------------------------------
section "repo-bootstrap end-to-end"
if [[ -f "$BOOTSTRAP" ]]; then
  # --help exits 0.
  if bash "$BOOTSTRAP" --help >/dev/null 2>&1; then
    pass "bootstrap --help exits 0"
  else
    fail "bootstrap --help did not exit 0"
  fi
  # Unknown argument exits 2.
  bash "$BOOTSTRAP" --bogus >/dev/null 2>&1
  bcode=$?
  if [[ $bcode -eq 2 ]]; then
    pass "bootstrap rejects unknown args (exit 2)"
  else
    fail "bootstrap exited $bcode on unknown arg (expected 2)"
  fi
  # Scaffolds a valid settings.json + CI workflow, merges idempotently, preserves keys.
  bt="$(mktemp -d)"
  if bash "$BOOTSTRAP" --plugin video-bug-analyzer --ci --dir "$bt" >/dev/null 2>&1 \
     && [[ -f "$bt/.github/workflows/validate.yml" ]] \
     && python3 - "$bt/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["extraKnownMarketplaces"]["portka-tools"]["source"]["repo"] == "cportka/claude-plugins"
assert d["enabledPlugins"]["video-bug-analyzer@portka-tools"] is True
PY
  then
    pass "bootstrap writes valid settings.json + CI workflow"
  else
    fail "bootstrap did not produce expected settings.json / workflow"
  fi
  # Re-run with an extra plugin and a pre-existing custom key: must merge, not clobber.
  python3 - "$bt/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["customKey"] = "keep-me"
json.dump(d, open(p, "w"), indent=2)
PY
  if bash "$BOOTSTRAP" --plugin other-plugin --dir "$bt" >/dev/null 2>&1 \
     && python3 - "$bt/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["customKey"] == "keep-me", "clobbered an existing key"
assert d["enabledPlugins"]["video-bug-analyzer@portka-tools"] is True
assert d["enabledPlugins"]["other-plugin@portka-tools"] is True
PY
  then
    pass "bootstrap merges idempotently and preserves existing keys"
  else
    fail "bootstrap merge clobbered or dropped data"
  fi
  rm -rf "$bt"
else
  fail "bootstrap script not found: $BOOTSTRAP"
fi

# --- 12. ffmpeg static fallback wired -------------------------------------------------
section "ffmpeg static fallback"
for f in \
  plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh \
  plugins/video-bug-analyzer/hooks/ensure-ffmpeg.sh; do
  if grep -q 'install_ffmpeg_static' "$f"; then
    pass "static ffmpeg fallback present: $f"
  else
    fail "static ffmpeg fallback missing: $f"
  fi
done

# --- Summary --------------------------------------------------------------------------
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
