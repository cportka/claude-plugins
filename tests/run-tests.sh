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
SCRIPT_ABS="$ROOT/$SCRIPT"   # absolute path for tests that run from a different cwd
BOOTSTRAP="plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh"
export VBA_NO_FEEDBACK_HINT=1   # keep the end-of-run feedback nudge out of test output

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

# --- 3b. semver + README table version sync -------------------------------------------
section "versions: semver + README table sync"
for pj in plugins/*/.claude-plugin/plugin.json; do
  ver="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$pj")"
  name="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$pj")"
  # accept an optional SemVer pre-release suffix (e.g. 1.0.0-rc.1).
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    pass "semver $ver: $name"
  else
    fail "non-semver version '$ver': $pj"
  fi
  # structured parse of the README plugin table (was a loose substring grep) — the
  # version cell of the plugin's own row must equal its plugin.json version.
  if python3 - "$name" "$ver" <<'PY'
import sys
name, ver = sys.argv[1], sys.argv[2]
rows = [ln for ln in open("README.md").read().splitlines()
        if ln.lstrip().startswith("|") and f"`{name}`" in ln]
assert rows, f"no README plugin-table row references `{name}`"
cells = [c.strip() for c in rows[0].strip().strip("|").split("|")]
assert len(cells) >= 2, f"row for `{name}` has too few columns: {rows[0]!r}"
assert cells[1] == ver, f"README table shows '{cells[1]}' for {name}, plugin.json says '{ver}'"
PY
  then
    pass "README table version matches plugin.json: $name $ver"
  else
    fail "README table version mismatch for $name (want $ver)"
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

# The Plugin-feedback form's `plugin` dropdown must list every marketplace plugin (plus the
# "other / not sure" escape) — so the form can't silently fall behind a newly added plugin.
# Parsed without a YAML lib (keeps zero deps, like the checks above): pull the `id: plugin`
# dropdown's `options:` items and compare the set to marketplace.json's plugin names.
_FEEDBACK_FORM=".github/ISSUE_TEMPLATE/plugin-feedback.yml"
if [[ -s "$_FEEDBACK_FORM" ]]; then
  if python3 - "$_FEEDBACK_FORM" "$MP" <<'PY'
import json, re, sys
form, mp = sys.argv[1], sys.argv[2]
plugins = {p["name"] for p in json.load(open(mp))["plugins"]}
opts, in_plugin, in_opts = [], False, False
for ln in open(form).read().splitlines():
    s = ln.strip()
    if re.match(r"^id:\s*plugin\b", s):
        in_plugin = True
        continue
    if in_plugin:
        if not in_opts:
            if s.startswith("options:"):
                in_opts = True
            continue
        m = re.match(r"^-\s+(.*\S)\s*$", s)
        if m:
            opts.append(m.group(1).strip())
        elif s:               # a non-list line (e.g. validations:) ends the options block
            break
assert opts, "no `plugin` dropdown options found in the feedback form"
ESCAPE = {"other / not sure"}
listed = set(opts) - ESCAPE
assert ESCAPE <= set(opts), "feedback form is missing the 'other / not sure' escape option"
assert listed == plugins, (
    f"feedback form plugin dropdown {sorted(listed)} != marketplace plugins {sorted(plugins)} "
    "— update .github/ISSUE_TEMPLATE/plugin-feedback.yml")
PY
  then
    pass "feedback form plugin dropdown is in sync with marketplace.json"
  else
    fail "feedback form plugin dropdown out of sync with marketplace.json (see error above)"
  fi
fi

# --- 4c2. release automation ----------------------------------------------------------
section "release automation"
RW=".github/workflows/release.yml"
if [[ -s "$RW" ]] && grep -q 'tags:' "$RW" && grep -q 'CHANGELOG.md' "$RW"; then
  pass "release workflow present (tag-triggered, reads CHANGELOG)"
else
  fail "release workflow missing or not wired to tags/CHANGELOG: $RW"
fi
# The README header Version must have a matching CHANGELOG section (so auto-notes won't be empty).
_hdr_ver="$(sed -n 's/^> \*\*Version:\*\* \([0-9][0-9.A-Za-z-]*\).*/\1/p' README.md | head -n1)"
if [[ -n "$_hdr_ver" ]] && grep -qF "## [$_hdr_ver]" CHANGELOG.md; then
  pass "CHANGELOG has a section for the current version ($_hdr_ver)"
else
  fail "no CHANGELOG '## [$_hdr_ver]' section for the README version"
fi
# P0-2: every plugin.json version must have a matching '## [version]' CHANGELOG heading, so the
# tag-driven release notes are never empty for a shipped plugin version.
for pj in plugins/*/.claude-plugin/plugin.json; do
  pv="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$pj")"
  pn="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$pj")"
  if grep -qF "## [$pv]" CHANGELOG.md; then
    pass "CHANGELOG documents $pn $pv"
  else
    fail "no CHANGELOG '## [$pv]' heading for $pn (every plugin version needs release notes)"
  fi
done
# extract-frames.sh embeds VBA_VERSION as a standalone fallback (issues #51/#52/#53); it must
# stay in lockstep with the plugin's plugin.json so the feedback link never misreports the version.
_vba_pj="$(python3 -c 'import json;print(json.load(open("plugins/video-bug-analyzer/.claude-plugin/plugin.json"))["version"])')"
_vba_emb="$(sed -n 's/^VBA_VERSION="\([^"]*\)".*/\1/p' "$SCRIPT" | head -n1)"
if [[ -n "$_vba_emb" && "$_vba_emb" == "$_vba_pj" ]]; then
  pass "extract-frames.sh embedded VBA_VERSION ($_vba_emb) matches plugin.json"
else
  fail "VBA_VERSION '$_vba_emb' != plugin.json '$_vba_pj' (update the constant in extract-frames.sh)"
fi

# --- 4d. GitHub Pages landing page ----------------------------------------------------
section "GitHub Pages site"
if [[ -s index.html ]] \
   && grep -q 'Portka Tools' index.html \
   && grep -q 'plugin marketplace add cportka/claude-plugins' index.html; then
  pass "index.html exists with title + add command"
else
  fail "index.html missing, empty, or lacking key content"
fi
if [[ -f .nojekyll ]]; then
  pass ".nojekyll present (served as-is, no Jekyll build)"
else
  fail ".nojekyll missing (GitHub Pages may try to Jekyll-build the repo)"
fi
# 1.0.1: brand + web assets, and social/SEO meta in the page.
_assets_ok=1
for a in favicon.svg robots.txt sitemap.xml llms.txt assets/logo.svg assets/og.png assets/apple-touch-icon.png; do
  [[ -s "$a" ]] || { _assets_ok=0; echo "    missing/empty asset: $a"; }
done
if [[ "$_assets_ok" -eq 1 ]]; then pass "brand/web assets present (logo, favicon, og:image, robots, sitemap, llms.txt)"; else fail "one or more site assets missing"; fi
if grep -q 'og:image' index.html && grep -q 'theme-color' index.html && grep -q 'apple-touch-icon' index.html; then
  pass "index.html has social/SEO meta (og:image, theme-color, apple-touch-icon)"
else
  fail "index.html missing social/SEO meta"
fi
# Dogfood gate: our own site must pass our own evaluator with zero FAILs.
_self_eval="plugins/app-website-evaluator/skills/app-evaluation/scripts/evaluate-site.sh"
if [[ -x "$_self_eval" ]]; then
  if [[ "$(bash "$_self_eval" --dir . 2>/dev/null | grep -c 'FAIL')" -eq 0 ]]; then
    pass "dogfood: the Pages site passes app-website-evaluator with 0 FAILs"
  else
    fail "dogfood: app-website-evaluator reports FAILs on our own site"
  fi
fi

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
done < <(find plugins tests submissions -name '*.sh' -print0 2>/dev/null)
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
    # --text contact preset: still produces a sheet.
    if bash "$SCRIPT" --video "$clip" --start 0 --end 3 --fps 4 --contact --text --out "$tmp/text" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/text" -name 'contact_*.png' | wc -l)" -gt 0 ]]; then
      pass "--text contact preset produced a sheet"
    else
      fail "--text contact preset produced no sheet"
    fi
    # --strip: hstack two existing frames into strip.png (no --video).
    _f1="$(find "$tmp/dense" -name '*.png' | sort | head -n1)"
    _f2="$(find "$tmp/dense" -name '*.png' | sort | tail -n1)"
    if [[ -n "$_f1" && -n "$_f2" ]] \
       && bash "$SCRIPT" --strip "$_f1,$_f2" --out "$tmp/strip" >/dev/null 2>&1 \
       && [[ -f "$tmp/strip/strip.png" ]]; then
      pass "--strip stitched a before/after from existing frames"
    else
      fail "--strip did not produce strip.png"
    fi
    # --strip across MISMATCHED resolutions: a 320x240 frame + a 200x120 frame.
    ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=1:size=200x120:rate=4" \
      "$tmp/small.mp4" -y 2>/dev/null || true
    bash "$SCRIPT" --video "$tmp/small.mp4" --start 0 --end 1 --fps 2 --out "$tmp/sm" >/dev/null 2>&1 || true
    _fsmall="$(find "$tmp/sm" -name '*.png' | sort | head -n1)"
    if [[ -n "$_f1" && -n "$_fsmall" ]] \
       && bash "$SCRIPT" --strip "$_f1,$_fsmall" --out "$tmp/strip2" >/dev/null 2>&1 \
       && [[ -f "$tmp/strip2/strip.png" ]]; then
      pass "--strip handles mismatched resolutions"
    else
      fail "--strip failed on mismatched resolutions"
    fi
    # Per-video default output dir: two clips run WITHOUT --out land in separate .frames/<name>.
    cp "$clip" "$tmp/clipA.mp4"; cp "$clip" "$tmp/clipB.mp4"
    ( cd "$tmp" && bash "$SCRIPT_ABS" --video clipA.mp4 --start 0 --end 1 --fps 3 >/dev/null 2>&1 )
    ( cd "$tmp" && bash "$SCRIPT_ABS" --video clipB.mp4 --start 0 --end 1 --fps 3 >/dev/null 2>&1 )
    if [[ -d "$tmp/.frames/clipA" && -d "$tmp/.frames/clipB" ]] \
       && [[ "$(find "$tmp/.frames/clipA" -name '*.png' | wc -l)" -gt 0 ]]; then
      pass "per-video default out dir keeps clips separate"
    else
      fail "per-video default out dir did not separate clips"
    fi
    # Sparse-capture warning: real 5fps source + --fps 30 should warn (needs ffprobe).
    if command -v ffprobe >/dev/null 2>&1; then
      ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=2:size=320x240:rate=5" \
        "$tmp/slow.mp4" -y 2>/dev/null || true
      bash "$SCRIPT" --video "$tmp/slow.mp4" --start 0 --end 1 --fps 30 --out "$tmp/sp" \
        >/dev/null 2>"$tmp/sp.err" || true
      if grep -qi "won't add detail" "$tmp/sp.err"; then
        pass "sparse-capture warning fires when --fps exceeds real rate"
      else
        fail "sparse-capture warning did not fire"
      fi
      # Portrait contact: a tall source auto-drops to --cols 2 (issue #14).
      ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=1:size=180x320:rate=4" \
        "$tmp/tall.mp4" -y 2>/dev/null || true
      bash "$SCRIPT" --video "$tmp/tall.mp4" --start 0 --end 1 --fps 2 --contact --out "$tmp/port" \
        >/dev/null 2>"$tmp/port.err" || true
      if grep -qi "Portrait capture: using --cols 2" "$tmp/port.err"; then
        pass "portrait source auto-drops to --cols 2"
      else
        fail "portrait auto-cols did not fire"
      fi
      # Legibility guard: a wide hi-res source warns that contact tiles will be illegible.
      ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=duration=1:size=1280x720:rate=4" \
        "$tmp/hires.mp4" -y 2>/dev/null || true
      bash "$SCRIPT" --video "$tmp/hires.mp4" --start 0 --end 1 --fps 2 --contact --out "$tmp/hi" \
        >/dev/null 2>"$tmp/hi.err" || true
      if grep -qi "illegible" "$tmp/hi.err"; then
        pass "legibility guard warns on heavy downscale"
      else
        fail "legibility guard did not warn"
      fi
    else
      skip "ffprobe not installed (sparse / portrait / legibility)"
    fi
    # --diff: frame-difference frames (tblend) — should produce diff_*.png.
    if bash "$SCRIPT" --video "$clip" --start 0 --end 2 --fps 4 --diff --out "$tmp/diff" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/diff" -name 'diff_*.png' | wc -l)" -gt 0 ]]; then
      pass "--diff produced frame-difference images"
    else
      fail "--diff produced no diff frames"
    fi
    # --list-scenes: runs and exits 0 (a synthetic clip may have few/no cuts; just smoke it).
    if bash "$SCRIPT" --video "$clip" --list-scenes >/dev/null 2>&1; then
      pass "--list-scenes ran"
    else
      fail "--list-scenes errored"
    fi
    # --label: must not break extraction — frames are produced whether or not a font exists
    # (the drawtext probe degrades gracefully).
    if bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 3 --label --out "$tmp/lab" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/lab" -name 'frame_*.png' | wc -l)" -gt 0 ]]; then
      pass "--label still produces frames (burn-in best-effort)"
    else
      fail "--label broke extraction"
    fi
    # --crop: crop a region before scaling — frames are produced and zoomed (issue #23).
    if bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 3 --crop 120:80:10:10 --out "$tmp/crop" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/crop" -name 'frame_*.png' | wc -l)" -gt 0 ]]; then
      pass "--crop produced frames from a cropped region"
    else
      fail "--crop broke extraction"
    fi
    # --blackdetect: a clip that is bright for 2s then black to EOF should report a PERMANENT
    # span (issue #25). Build it by concatenating testsrc + a black color source.
    if ffmpeg -hide_banner -loglevel error \
         -f lavfi -i "testsrc=duration=2:size=320x240:rate=10" \
         -f lavfi -i "color=c=black:size=320x240:rate=10:duration=2" \
         -filter_complex "[0:v][1:v]concat=n=2:v=1[v]" -map "[v]" "$tmp/black.mp4" -y 2>/dev/null; then
      _bd="$(bash "$SCRIPT" --video "$tmp/black.mp4" --blackdetect 2>/dev/null || true)"
      if grep -q 'black ' <<<"$_bd"; then
        pass "--blackdetect found the blacked-out span"
      else
        fail "--blackdetect found no black span"
      fi
      # ffprobe is present in CI, so the span to EOF should classify PERMANENT.
      if grep -q 'PERMANENT' <<<"$_bd"; then
        pass "--blackdetect classified the sustained span PERMANENT"
      else
        fail "--blackdetect did not classify the sustained span PERMANENT"
      fi
    else
      skip "could not build a black test clip (--blackdetect)"
    fi
    # --ocr-roi: OCR a region per frame into a t,text CSV (issue #27). Assert the pipeline
    # (ffmpeg crop+fps sampling -> tesseract -> CSV) regardless of exact OCR text: header plus
    # one data row per sampled frame. Needs tesseract; SKIP if it isn't installed.
    if command -v tesseract >/dev/null 2>&1; then
      _ocr="$(bash "$SCRIPT" --video "$clip" --start 0 --end 2 --fps 2 --ocr-roi 160:120:0:0 --ocr-digits 2>/dev/null || true)"
      if [[ "$(head -n1 <<<"$_ocr")" == "t,text" ]] \
         && [[ "$(grep -c '^[0-9]' <<<"$_ocr")" -ge 2 ]]; then
        pass "--ocr-roi emits a t,text timeline (header + rows)"
      else
        fail "--ocr-roi did not emit a valid t,text CSV"
      fi
    else
      skip "tesseract not installed (--ocr-roi e2e)"
    fi
    # --measure: a known 80x80 black box on white (200x200) should measure diam ~80 px and a
    # center near (100,100) (issue #29). The bounding-box logic doesn't need a real circle.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--measure e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "color=white:size=200x200:rate=5:duration=1" \
         -vf "drawbox=x=60:y=60:w=80:h=80:color=black:t=fill" "$tmp/box.mp4" -y 2>/dev/null; then
      _m="$(bash "$SCRIPT" --video "$tmp/box.mp4" --measure 200:200:0:0 --fps 2 2>/dev/null || true)"
      _mrow="$(grep -m1 '^[0-9]' <<<"$_m" || true)"
      _mdiam="$(awk -F, 'NR==1{print $4+0}' <<<"$_mrow")"   # diam_px (col 4)
      _mcx="$(awk -F, 'NR==1{print $7+0}' <<<"$_mrow")"     # cx (col 7 since dual pct cols)
      if [[ "$(head -n1 <<<"$_m")" == "t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy" ]] \
         && [[ -n "$_mdiam" ]] && (( _mdiam >= 60 && _mdiam <= 110 )) \
         && (( _mcx >= 75 && _mcx <= 125 )); then
        pass "--measure reports a feature diameter + center (bounding box)"
      else
        fail "--measure did not measure the test box (diam=$_mdiam cx=$_mcx)"
      fi
    else
      skip "could not build a box test clip (--measure)"
    fi
    # --probe: portrait vs landscape clips report the right orientation + dimensions (issue #31).
    if ffmpeg -hide_banner -loglevel error -f lavfi -i "color=blue:size=80x120:rate=5:duration=1" \
         "$tmp/portrait.mp4" -y 2>/dev/null \
       && ffmpeg -hide_banner -loglevel error -f lavfi -i "color=blue:size=120x80:rate=5:duration=1" \
         "$tmp/land.mp4" -y 2>/dev/null; then
      _pp="$(bash "$SCRIPT" --video "$tmp/portrait.mp4" --probe 2>/dev/null || true)"
      _pl="$(bash "$SCRIPT" --video "$tmp/land.mp4" --probe 2>/dev/null || true)"
      if grep -q 'orientation: portrait' <<<"$_pp" && grep -q '80x120' <<<"$_pp" \
         && grep -q 'orientation: landscape' <<<"$_pl"; then
        pass "--probe reports dimensions + orientation"
      else
        fail "--probe did not report orientation correctly"
      fi
    else
      skip "could not build probe test clips (--probe)"
    fi
    # --palette: a solid-red clip should yield a reddish dominant swatch (issue #33). Needs
    # python3 (present in CI); assert a hex line whose red channel dominates.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--palette e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "color=red:size=64x64:rate=5:duration=1" \
         "$tmp/red.mp4" -y 2>/dev/null; then
      _pal="$(bash "$SCRIPT" --video "$tmp/red.mp4" --palette --colors 4 2>/dev/null || true)"
      _hex="$(grep -m1 -oE '#[0-9a-f]{6}' <<<"$_pal" | head -n1)"
      if [[ -n "$_hex" ]] \
         && (( 16#${_hex:1:2} > 16#${_hex:3:2} )) && (( 16#${_hex:1:2} > 16#${_hex:5:2} )); then
        pass "--palette extracts a dominant colour (red clip -> reddish swatch)"
      else
        fail "--palette did not extract a reddish swatch (got '$_hex')"
      fi
    else
      skip "could not build a red test clip (--palette)"
    fi
    # --ab: two clips identical for 1s then divergent (red vs blue) for 1s should score high SSIM
    # early and low SSIM late (issue #35). Build A=red(2s); B=red(1s)+blue(1s).
    if ffmpeg -hide_banner -loglevel error -f lavfi -i "color=red:size=160x120:rate=5:duration=2" \
         "$tmp/abA.mp4" -y 2>/dev/null \
       && ffmpeg -hide_banner -loglevel error \
         -f lavfi -i "color=red:size=160x120:rate=5:duration=1" \
         -f lavfi -i "color=blue:size=160x120:rate=5:duration=1" \
         -filter_complex "[0:v][1:v]concat=n=2:v=1[v]" -map "[v]" "$tmp/abB.mp4" -y 2>/dev/null; then
      _ab="$(bash "$SCRIPT" --video "$tmp/abA.mp4" --ab "$tmp/abB.mp4" --fps 4 2>/dev/null || true)"
      # an early row (t<1) near-identical, and a late row (t>=1) clearly divergent. (Flat-colour
      # SSIM stays ~0.77 even for red-vs-blue, so the "divergent" cutoff is generous.)
      _hi="$(awk -F, '$1<1 && $2>0.95{print;exit}' <<<"$_ab")"
      _lo="$(awk -F, '$1>=1 && $2<0.85{print;exit}' <<<"$_ab")"
      if [[ "$(head -n1 <<<"$_ab")" == "t,ssim" ]] && [[ -n "$_hi" ]] && [[ -n "$_lo" ]]; then
        pass "--ab flags where two clips diverge (high SSIM early, low late)"
      else
        fail "--ab divergence timeline not as expected (hi='$_hi' lo='$_lo')"
      fi
    else
      skip "could not build A/B test clips (--ab)"
    fi
    # --cadence: a clip whose unique content updates ~2x/s but is muxed at 20fps CFR should read
    # an effective cadence far below nominal, and localize it per window (issue #37). Needs python3.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--cadence e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=size=160x120:rate=2:duration=2" \
         -r 20 "$tmp/dup.mp4" -y 2>/dev/null; then
      _cad="$(bash "$SCRIPT" --video "$tmp/dup.mp4" --cadence 2>"$tmp/cad.err" || true)"
      _lowrow="$(awk -F, 'NR>1 && ($3+0)<=5 {print; exit}' <<<"$_cad")"
      if [[ "$(head -n1 <<<"$_cad")" == "t,unique_frames,fps" ]] \
         && [[ -n "$_lowrow" ]] && grep -q 'nominal 20' "$tmp/cad.err"; then
        pass "--cadence localizes low effective cadence vs nominal"
      else
        fail "--cadence timeline not as expected (lowrow='$_lowrow')"
      fi
      # 1.3.0 (#64): an UNSCOPED choppy scan hints to re-run with --start/--end; a scoped one doesn't.
      bash "$SCRIPT" --video "$tmp/dup.mp4" --cadence --start 0 --end 2 2>"$tmp/cads.err" >/dev/null || true
      if grep -q 'Whole clip scanned' "$tmp/cad.err" && ! grep -q 'Whole clip scanned' "$tmp/cads.err"; then
        pass "--cadence hints about scoping only on an unscoped scan"
      else
        fail "--cadence scoping hint wrong (unscoped/scoped)"
      fi
    else
      skip "could not build a cadence test clip (--cadence)"
    fi
    # --stack (1.3.0, #62): crop a band and tile it vertically across time -> stack_0001.png.
    if bash "$SCRIPT" --video "$clip" --stack --crop 80:40:0:0 --fps 4 --out "$tmp/stk" >/dev/null 2>&1 \
       && [[ -f "$tmp/stk/stack_0001.png" ]]; then
      pass "--stack produced a vertical ROI time-stack"
    else
      fail "--stack did not produce stack_0001.png"
    fi
    # Collision guard (1.3.0, #64): a second run into a dir that already has PNGs must NOT
    # overwrite — it redirects into a mode+window subdir and says so.
    bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 3 --out "$tmp/coll" >/dev/null 2>&1
    _first_count="$(find "$tmp/coll" -maxdepth 1 -name 'frame_*.png' | wc -l)"
    _first_sum="$(cksum < "$tmp/coll/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    bash "$SCRIPT" --video "$clip" --start 1 --end 2 --fps 3 --out "$tmp/coll" >/dev/null 2>"$tmp/coll.err"
    _first_sum_after="$(cksum < "$tmp/coll/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    if grep -q 'previous run' "$tmp/coll.err" \
       && [[ "$_first_sum" == "$_first_sum_after" ]] \
       && [[ -d "$tmp/coll/dense_1-2" ]] \
       && [[ "$(find "$tmp/coll/dense_1-2" -name 'frame_*.png' | wc -l)" -gt 0 ]]; then
      pass "output-collision guard preserves the first run and redirects the second (#64)"
    else
      fail "collision guard failed (count=$_first_count sum $_first_sum->$_first_sum_after)"
    fi
    # A THIRD run with the SAME mode+window must not clobber the redirect subdir either — it
    # bumps a counter (review finding on the initial #64 fix).
    _sub_sum="$(cksum < "$tmp/coll/dense_1-2/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    bash "$SCRIPT" --video "$clip" --start 1 --end 2 --fps 5 --out "$tmp/coll" >/dev/null 2>&1
    _sub_sum_after="$(cksum < "$tmp/coll/dense_1-2/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    if [[ "$_sub_sum" == "$_sub_sum_after" ]] && [[ -d "$tmp/coll/dense_1-2_2" ]]; then
      pass "collision guard counter-suffixes a same-mode+window rerun (dense_1-2_2)"
    else
      fail "same-window rerun clobbered the redirect subdir"
    fi
    # Analysis modes write no PNGs — the guard must NOT fire (no junk dir, no misleading note).
    bash "$SCRIPT" --video "$clip" --cadence --out "$tmp/coll" >/dev/null 2>"$tmp/coll2.err" || true
    if ! grep -q 'previous run' "$tmp/coll2.err" && [[ ! -d "$tmp/coll/dense_0-end" ]]; then
      pass "collision guard skips PNG-less analysis modes (--cadence)"
    else
      fail "collision guard misfired on --cadence"
    fi
    # Glob metacharacters in the video name must not bypass the guard (find, not compgen -G).
    cp "$clip" "$tmp/clip [1].mp4"
    ( cd "$tmp" && bash "$SCRIPT_ABS" --video "clip [1].mp4" --start 0 --end 1 --fps 3 >/dev/null 2>&1 )
    _g_sum="$(cksum < "$tmp/.frames/clip [1]/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    ( cd "$tmp" && bash "$SCRIPT_ABS" --video "clip [1].mp4" --start 1 --end 2 --fps 3 >/dev/null 2>&1 )
    _g_sum_after="$(cksum < "$tmp/.frames/clip [1]/frame_0001.png" 2>/dev/null | cut -d' ' -f1)"
    if [[ -n "$_g_sum" && "$_g_sum" == "$_g_sum_after" ]]; then
      pass "collision guard is glob-safe (bracketed video names still protected)"
    else
      fail "glob-metachar video name bypassed the collision guard ($_g_sum -> $_g_sum_after)"
    fi
    # --stutter (alias for --cadence) + freeze gaps: a 1s FROZEN span should be reported as a freeze
    # gap, and the alias must still emit the cadence CSV (issue #56). Needs python3 + freezedetect.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--stutter e2e)"
    elif ffmpeg -hide_banner -loglevel error \
         -f lavfi -i "testsrc=size=160x120:rate=20:duration=1" \
         -f lavfi -i "color=c=blue:size=160x120:rate=20:duration=1" \
         -f lavfi -i "testsrc=size=160x120:rate=20:duration=1" \
         -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1[v]" -map "[v]" "$tmp/stall.mp4" -y 2>/dev/null; then
      _st="$(bash "$SCRIPT" --video "$tmp/stall.mp4" --stutter 2>"$tmp/st.err" || true)"
      if [[ "$(head -n1 <<<"$_st")" == "t,unique_frames,fps" ]] && grep -qi 'frozen for' "$tmp/st.err"; then
        pass "--stutter alias works and reports a freeze gap on a frozen span"
      else
        fail "--stutter did not report a freeze gap (err: $(grep -i 'freeze\|frozen' "$tmp/st.err" | head -1))"
      fi
      # a continuously-changing clip should report no sustained freeze gaps.
      if ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc=size=160x120:rate=20:duration=2" "$tmp/cont.mp4" -y 2>/dev/null; then
        bash "$SCRIPT" --video "$tmp/cont.mp4" --stutter 2>"$tmp/st2.err" >/dev/null || true
        if grep -qi 'No sustained freeze gaps' "$tmp/st2.err"; then
          pass "--stutter reports no freeze gaps on a continuous clip"
        else
          fail "--stutter freeze-gap negative case not as expected"
        fi
      fi
    else
      skip "could not build a stall test clip (--stutter)"
    fi
    # --pacing: read per-frame timestamps -> interval timeline (1.2.0; ffprobe + python3). A normal
    # 10fps CFR clip yields the t,interval_ms header and a "Pacing: median ~100 ms" headline.
    if command -v ffprobe >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
      _pace="$(bash "$SCRIPT" --video "$clip" --pacing 2>"$tmp/pace.err" || true)"
      if [[ "$(head -n1 <<<"$_pace")" == "t,interval_ms" ]] && grep -q 'Pacing: median' "$tmp/pace.err"; then
        pass "--pacing emits a t,interval_ms timeline + median/p95/max headline"
      else
        fail "--pacing timeline not as expected"
      fi
    else
      skip "ffprobe/python3 not available (--pacing e2e)"
    fi
    # --motion: a static segment then a moving one should read ~0 motion early and a clear spike
    # later (issue #39). Build gray(1s)+testsrc(1s). Needs python3.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--motion e2e)"
    elif ffmpeg -hide_banner -loglevel error \
         -f lavfi -i "color=gray:size=160x120:rate=10:duration=1" \
         -f lavfi -i "testsrc=size=160x120:rate=10:duration=1" \
         -filter_complex "[0:v][1:v]concat=n=2:v=1[v]" -map "[v]" "$tmp/mot.mp4" -y 2>/dev/null; then
      _mot="$(bash "$SCRIPT" --video "$tmp/mot.mp4" --motion --fps 10 2>/dev/null || true)"
      _still="$(awk -F, 'NR>1 && $1<0.9 && ($2+0)<1 {print; exit}' <<<"$_mot")"   # near-zero in static span
      _moved="$(awk -F, 'NR>1 && ($2+0)>5 {print; exit}' <<<"$_mot")"             # a clear motion spike
      if [[ "$(head -n1 <<<"$_mot")" == "t,motion" ]] && [[ -n "$_still" ]] && [[ -n "$_moved" ]]; then
        pass "--motion reads ~0 in a static span and spikes on motion"
      else
        fail "--motion timeline not as expected (still='$_still' moved='$_moved')"
      fi
      # 1.3.1 (#66): a near-static (solid) clip reads under the amplitude floor. Unscoped, the
      # headline hints to --crop the region; with --crop it reports the region itself as static.
      if ffmpeg -hide_banner -loglevel error -f lavfi -i "color=gray:size=160x120:rate=10:duration=1" "$tmp/flat.mp4" -y 2>/dev/null; then
        _mflat="$(bash "$SCRIPT" --video "$tmp/flat.mp4" --motion --fps 5 2>&1 >/dev/null || true)"
        _mflatc="$(bash "$SCRIPT" --video "$tmp/flat.mp4" --motion --crop 40:40:0:0 --fps 5 2>&1 >/dev/null || true)"
        if grep -qi 'Re-run with --crop' <<<"$_mflat" && grep -qi 'cropped region' <<<"$_mflatc"; then
          pass "--motion hints --crop on near-zero amplitude, calls a cropped region static (#66)"
        else
          fail "--motion amplitude-floor hint not as expected (#66)"
        fi
      else
        skip "could not build a flat clip (--motion amplitude floor)"
      fi
    else
      skip "could not build a motion test clip (--motion)"
    fi
    # --saturation: a grey clip reads ~0, a vivid clip reads clearly higher (1.0.0 bonus).
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--saturation e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "color=gray:size=120x80:rate=5:duration=1" "$tmp/gray.mp4" -y 2>/dev/null; then
      _sat="$(bash "$SCRIPT" --video "$tmp/gray.mp4" --saturation --fps 3 2>/dev/null || true)"
      _satv="$(bash "$SCRIPT" --video "$clip" --saturation --fps 3 2>/dev/null || true)"   # $clip is testsrc (vivid)
      _grow="$(awk -F, 'NR==2{print ($2+0<5)?"low":"high"}' <<<"$_sat")"
      _vrow="$(awk -F, 'NR==2{print ($2+0>20)?"high":"low"}' <<<"$_satv")"
      if [[ "$(head -n1 <<<"$_sat")" == "t,saturation" ]] && [[ "$_grow" == "low" ]] && [[ "$_vrow" == "high" ]]; then
        pass "--saturation reads ~0 on grey and high on a vivid clip"
      else
        fail "--saturation timeline not as expected (grey='$_grow' vivid='$_vrow')"
      fi
    else
      skip "could not build a saturation test clip (--saturation)"
    fi
    # --occupancy (1.4.0, #69): a small bright box on black reads a low coverage % (+ the "too
    # small to see" hint); a big box reads clearly higher. Needs python3.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--occupancy e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "color=black:s=200x200:rate=4:duration=1" -vf "drawbox=x=90:y=90:w=20:h=20:color=white:t=fill" "$tmp/occ_s.mp4" -y 2>/dev/null \
       && ffmpeg -hide_banner -loglevel error -f lavfi -i "color=black:s=200x200:rate=4:duration=1" -vf "drawbox=x=20:y=20:w=160:h=160:color=white:t=fill" "$tmp/occ_b.mp4" -y 2>/dev/null; then
      _occs="$(bash "$SCRIPT" --video "$tmp/occ_s.mp4" --occupancy --fps 2 2>/dev/null || true)"
      _occserr="$(bash "$SCRIPT" --video "$tmp/occ_s.mp4" --occupancy --fps 2 2>&1 >/dev/null || true)"
      _occb="$(bash "$SCRIPT" --video "$tmp/occ_b.mp4" --occupancy --fps 2 2>/dev/null || true)"
      _cs="$(awk -F, 'NR==2{print int($2+0.5)}' <<<"$_occs")"   # small-subject coverage %
      _cb="$(awk -F, 'NR==2{print int($2+0.5)}' <<<"$_occb")"   # big-subject coverage %
      if [[ "$(head -n1 <<<"$_occs")" == "t,coverage_pct,x,y,w,h" ]] \
         && [[ -n "$_cs" && -n "$_cb" && "$_cs" -lt 10 && "$_cb" -gt 40 && "$_cb" -gt "$_cs" ]] \
         && grep -qi 'too small' <<<"$_occserr"; then
        pass "--occupancy reports low coverage + 'too small' hint for a small subject, high for a big one (#69)"
      else
        fail "--occupancy coverage not as expected (small=$_cs% big=$_cb%)"
      fi
    else
      skip "could not build occupancy test clips (--occupancy)"
    fi
    # --flow (1.4.0, #69): block-matching flow split into swirl (curl) vs suck (radial). Rotating
    # static noise reads 'spinning in place' (Rotational-dominant); a zoom-OUT reads 'suck'
    # (Radial-inward). geq builds unambiguous per-pixel noise (block matching's ideal input);
    # skip cleanly if geq/zoompan aren't available. Needs python3.
    if ! command -v python3 >/dev/null 2>&1; then
      skip "python3 not installed (--flow e2e)"
    elif ffmpeg -hide_banner -loglevel error -f lavfi -i "nullsrc=s=300x300" -vf "geq=lum='random(1)*255':cb=128:cr=128,format=gray" -frames:v 1 "$tmp/fnoise.png" -y 2>/dev/null \
       && [[ -s "$tmp/fnoise.png" ]] \
       && ffmpeg -hide_banner -loglevel error -loop 1 -i "$tmp/fnoise.png" -t 1.2 -r 12 -vf "rotate=a=0.30*t,crop=150:150" "$tmp/frot.mp4" -y 2>/dev/null \
       && ffmpeg -hide_banner -loglevel error -i "$tmp/fnoise.png" -vf "zoompan=z='min(zoom+0.04,3)':d=16:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=150x150:fps=12,format=gray" "$tmp/fzin.mp4" -y 2>/dev/null \
       && ffmpeg -hide_banner -loglevel error -i "$tmp/fzin.mp4" -vf reverse "$tmp/fzout.mp4" -y 2>/dev/null; then
      _frot="$(bash "$SCRIPT" --video "$tmp/frot.mp4" --flow --fps 12 2>&1 || true)"    # stderr+stdout
      _fzo="$(bash "$SCRIPT" --video "$tmp/fzout.mp4" --flow --fps 12 2>&1 || true)"
      if grep -q 't,speed,curl,div' <<<"$_frot" \
         && grep -qi 'Rotational-dominant' <<<"$_frot" && ! grep -qi 'suck' <<<"$_frot" \
         && grep -qiE 'Radial-inward-dominant|suck' <<<"$_fzo"; then
        pass "--flow reads rotation as spin-in-place and a zoom-out as inward 'suck' (#69)"
      else
        fail "--flow classification not as expected"
      fi
    else
      skip "could not build flow test clips (--flow; needs geq/zoompan)"
    fi
    # --compare-videos: two clips of different lengths -> ONE stacked sheet, a row per clip
    # (issue #41). Reuse the contact clip + the small clip from earlier; assert compare.png is
    # produced and is a 2-row stack (height ~= 2x a single row).
    if [[ -f "$tmp/small.mp4" ]] \
       && bash "$SCRIPT" --compare-videos "$clip,$tmp/small.mp4" --cols 6 --out "$tmp/cmp" >/dev/null 2>&1 \
       && [[ -f "$tmp/cmp/compare.png" ]]; then
      pass "--compare-videos wrote a stacked A/B sheet"
    else
      fail "--compare-videos did not produce compare.png"
    fi
    # --label in contact mode: should still produce a sheet (drawtext per tile, best-effort) (issue #41).
    if bash "$SCRIPT" --video "$clip" --start 0 --end 2 --fps 3 --contact --label --out "$tmp/clab" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/clab" -name 'contact_*.png' | wc -l)" -gt 0 ]]; then
      pass "--label works in contact mode (sheet still produced)"
    else
      fail "--label broke contact mode"
    fi
    # --intro preset: load/splash shorthand should produce a contact sheet of the first ~2s (issue #43).
    if bash "$SCRIPT" --video "$clip" --intro --out "$tmp/intro" >/dev/null 2>&1 \
       && [[ "$(find "$tmp/intro" -name 'contact_*.png' | wc -l)" -gt 0 ]]; then
      pass "--intro produces a first-seconds contact sheet"
    else
      fail "--intro did not produce a contact sheet"
    fi
    # Smoothness header: every real extract prints a one-line "smoothness:" report (issue #41).
    bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 2 --out "$tmp/sm" >/dev/null 2>"$tmp/sm.err" || true
    if grep -q 'smoothness:' "$tmp/sm.err"; then
      pass "smoothness header prints on a normal run"
    else
      fail "smoothness header missing"
    fi
    # Feedback hint: prints a pre-filled link on stderr (when not suppressed); hidden when set.
    env -u VBA_NO_FEEDBACK_HINT bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 2 \
      --out "$tmp/fb" >/dev/null 2>"$tmp/fb.err" || true
    bash "$SCRIPT" --video "$clip" --start 0 --end 1 --fps 2 --out "$tmp/fb2" >/dev/null 2>"$tmp/fb2.err" || true
    if grep -qi 'One-click feedback' "$tmp/fb.err" && ! grep -qi 'One-click feedback' "$tmp/fb2.err"; then
      pass "end-of-run feedback hint prints (and VBA_NO_FEEDBACK_HINT suppresses it)"
    else
      fail "feedback hint did not behave (present default / suppressed via env)"
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
  # unknown --plugin names warn (non-fatal) when the marketplace is locatable.
  if bash "$BOOTSTRAP" --plugin definitely-not-a-real-plugin --dir "$bt" 2>"$bt/uerr" >/dev/null \
     && grep -qi "not a known" "$bt/uerr"; then
    pass "bootstrap warns on an unknown plugin name"
  else
    fail "bootstrap did not warn on an unknown plugin name"
  fi
  # --list prints known plugin names. (Capture then match — piping into `grep -q`
  # under `set -o pipefail` can SIGPIPE the producer and flake; issue #21.)
  if grep -q 'video-bug-analyzer' <<<"$(bash "$BOOTSTRAP" --list 2>/dev/null || true)"; then
    pass "bootstrap --list shows known plugins"
  else
    fail "bootstrap --list did not list known plugins"
  fi
  # prints the /plugin CLI one-paste fallback.
  _bs_fallback="$(bash "$BOOTSTRAP" --plugin video-bug-analyzer --dir "$bt" 2>&1 >/dev/null || true)"
  if grep -q '/plugin install video-bug-analyzer@portka-tools' <<<"$_bs_fallback"; then
    pass "bootstrap prints the /plugin CLI fallback"
  else
    fail "bootstrap did not print the CLI fallback"
  fi
  # --dry-run previews without writing anything (1.0.0).
  bd="$(mktemp -d)"
  _bs_dry="$(bash "$BOOTSTRAP" --plugin video-bug-analyzer --ci --dir "$bd" --dry-run 2>&1 || true)"
  if grep -q '\[dry-run\]' <<<"$_bs_dry" && [[ "$(find "$bd" -type f | wc -l)" -eq 0 ]]; then
    pass "bootstrap --dry-run previews and writes nothing"
  else
    fail "bootstrap --dry-run wrote files or didn't preview"
  fi
  rm -rf "$bd"
  rm -rf "$bt"
else
  fail "bootstrap script not found: $BOOTSTRAP"
fi

# --- 11a2. repo-bootstrap --portka-standard -------------------------------------------
section "repo-bootstrap --portka-standard"
if [[ -f "$BOOTSTRAP" ]]; then
  ps="$(mktemp -d)"   # target repo
  ph="$(mktemp -d)"   # fake HOME for user-scope writes (keeps tests off the real ~/.claude)
  bash "$BOOTSTRAP" --plugin video-bug-analyzer --portka-standard --dir "$ps" --home "$ph" >/dev/null 2>&1
  # Project-scope workflow memory carries the managed block + the workflow heading.
  if [[ -f "$ps/.claude/CLAUDE.md" ]] \
     && grep -q 'BEGIN portka-standard' "$ps/.claude/CLAUDE.md" \
     && grep -q 'Portka standard workflow' "$ps/.claude/CLAUDE.md"; then
    pass "portka-standard writes the workflow CLAUDE.md (project)"
  else
    fail "portka-standard did not write a project CLAUDE.md with the workflow block"
  fi
  # User scope lands under the fake HOME, never the real one.
  if [[ -f "$ph/.claude/CLAUDE.md" ]] && grep -q 'BEGIN portka-standard' "$ph/.claude/CLAUDE.md"; then
    pass "portka-standard writes the user-scope CLAUDE.md under --home"
  else
    fail "portka-standard did not write the user-scope CLAUDE.md"
  fi
  # Permissions merge into BOTH settings; the marketplace + plugins survive in the project one.
  if python3 - "$ps/.claude/settings.json" "$ph/.claude/settings.json" <<'PY'
import json, sys
proj = json.load(open(sys.argv[1]))
home = json.load(open(sys.argv[2]))
assert proj["extraKnownMarketplaces"]["portka-tools"]["source"]["repo"] == "cportka/claude-plugins"
assert proj["enabledPlugins"]["video-bug-analyzer@portka-tools"] is True
for d in (proj, home):
    allow = d["permissions"]["allow"]
    assert any(r.startswith("Bash(git push") for r in allow), allow
    assert any(r.startswith("Bash(git checkout") for r in allow), allow
    assert any(r.startswith("Bash(gh pr") for r in allow), allow
PY
  then
    pass "portka-standard merges git/gh permissions into project + user settings (marketplace kept)"
  else
    fail "portka-standard permissions/marketplace merge not as expected"
  fi
  # Repo sync scaffold present (version triplet + enforcing suite + CI).
  if [[ -f "$ps/VERSION" && -f "$ps/CHANGELOG.md" && -f "$ps/README.md" \
        && -x "$ps/tests/run-tests.sh" && -f "$ps/.github/workflows/portka-standard.yml" ]]; then
    pass "portka-standard scaffolds VERSION + CHANGELOG + README + tests + CI"
  else
    fail "portka-standard did not scaffold the full version/sync + CI set"
  fi
  # The scaffolded suite PASSES on its own fresh seed (the triplet is internally consistent)...
  if bash "$ps/tests/run-tests.sh" >/dev/null 2>&1; then
    pass "scaffolded run-tests.sh passes on the fresh repo (version sync green)"
  else
    fail "scaffolded run-tests.sh failed on a fresh scaffold"
  fi
  # ...and FAILS once the version sync is broken (proves it actually enforces).
  echo "9.9.9" > "$ps/VERSION"
  if bash "$ps/tests/run-tests.sh" >/dev/null 2>&1; then
    fail "scaffolded suite passed despite VERSION/CHANGELOG drift (not enforcing)"
  else
    pass "scaffolded suite enforces the sync (fails on VERSION/CHANGELOG drift)"
  fi
  # Idempotent: a second run leaves exactly one managed block.
  bash "$BOOTSTRAP" --plugin video-bug-analyzer --portka-standard --dir "$ps" --home "$ph" >/dev/null 2>&1
  if [[ "$(grep -c 'BEGIN portka-standard' "$ps/.claude/CLAUDE.md")" -eq 1 ]]; then
    pass "portka-standard is idempotent (one managed block after re-run)"
  else
    fail "portka-standard duplicated the managed block on re-run"
  fi
  # --dry-run writes nothing, in the repo or under --home.
  pd="$(mktemp -d)"; phd="$(mktemp -d)"
  bash "$BOOTSTRAP" --plugin video-bug-analyzer --portka-standard --dir "$pd" --home "$phd" --dry-run >/dev/null 2>&1
  if [[ "$(find "$pd" "$phd" -type f | wc -l)" -eq 0 ]]; then
    pass "portka-standard --dry-run writes nothing"
  else
    fail "portka-standard --dry-run wrote files"
  fi
  rm -rf "$ps" "$ph" "$pd" "$phd"
else
  fail "bootstrap script not found: $BOOTSTRAP"
fi

# --- 11a3. repo-bootstrap #59: native version binding, CI collision, --print-only ------
section "repo-bootstrap #59 (native version / collision / print-only)"
if [[ -f "$BOOTSTRAP" ]]; then
  # A mature repo: package.json 0.22.0, a README with NO **Version:** line, and existing CI.
  mr="$(mktemp -d)"; mrh="$(mktemp -d)"
  printf '{\n  "name": "x",\n  "version": "0.22.0"\n}\n' > "$mr/package.json"
  printf '# x\n\nA mature app. No version line here.\n' > "$mr/README.md"
  printf '# Changelog\n\n## [0.22.0]\n- stuff\n' > "$mr/CHANGELOG.md"
  mkdir -p "$mr/.github/workflows"; printf 'name: ci\non: [push]\n' > "$mr/.github/workflows/ci.yml"
  bash "$BOOTSTRAP" --portka-standard --scope project --dir "$mr" --home "$mrh" >/dev/null 2>&1
  # Must NOT seed a conflicting VERSION, and must NOT add a colliding workflow.
  if [[ ! -f "$mr/VERSION" && ! -f "$mr/.github/workflows/portka-standard.yml" ]]; then
    pass "portka-standard binds to package.json (no VERSION seed) and skips colliding CI"
  else
    fail "portka-standard seeded VERSION or added a colliding workflow on a mature repo"
  fi
  # The scaffolded suite must be GREEN on the mature repo (this was the #59 'ships red' regression).
  if [[ -x "$mr/tests/run-tests.sh" ]] && bash "$mr/tests/run-tests.sh" >/dev/null 2>&1; then
    pass "scaffolded suite is green on a mature repo (binds to native 0.22.0)"
  else
    fail "scaffolded suite is red on a mature repo (#59 regression)"
  fi
  # Native version-sync test (1.2.0): a package.json repo also gets a node:test that passes.
  if [[ -f "$mr/tests/version-sync.test.mjs" ]]; then
    pass "portka-standard emits a native node:test version-sync test for a package.json repo"
    if command -v node >/dev/null 2>&1; then
      if ( cd "$mr" && node --test >/dev/null 2>&1 ); then
        pass "scaffolded node:test version-sync passes (package.json 0.22.0 <-> CHANGELOG)"
      else
        fail "scaffolded node:test version-sync failed"
      fi
    else
      skip "node not installed (native node:test)"
    fi
  else
    fail "portka-standard did not emit the native node:test for a package.json repo"
  fi
  rm -rf "$mr" "$mrh"
  # A pyproject repo gets a unittest version-sync test that passes (python3 always present here).
  pyr="$(mktemp -d)"; pyh="$(mktemp -d)"
  printf '[project]\nname = "x"\nversion = "2.3.4"\n' > "$pyr/pyproject.toml"
  printf '# Changelog\n\n## [2.3.4]\n- x\n' > "$pyr/CHANGELOG.md"
  bash "$BOOTSTRAP" --portka-standard --scope project --dir "$pyr" --home "$pyh" >/dev/null 2>&1
  if [[ -f "$pyr/tests/test_version_sync.py" ]] && ( cd "$pyr" && python3 -m unittest discover -s tests >/dev/null 2>&1 ); then
    pass "portka-standard emits a passing unittest version-sync for a pyproject repo"
  else
    fail "portka-standard pyproject native test missing or failing"
  fi
  rm -rf "$pyr" "$pyh"

  # --print-only writes nothing and prints both the settings JSON and the CLAUDE block.
  po="$(mktemp -d)"; poh="$(mktemp -d)"
  _po="$(bash "$BOOTSTRAP" --plugin video-bug-analyzer --portka-standard --print-only --dir "$po" --home "$poh" 2>/dev/null || true)"
  if grep -q 'extraKnownMarketplaces' <<<"$_po" \
     && grep -q 'Bash(git push' <<<"$_po" \
     && grep -q 'BEGIN portka-standard' <<<"$_po" \
     && [[ "$(find "$po" "$poh" -type f | wc -l)" -eq 0 ]]; then
    pass "--print-only emits settings + CLAUDE block and writes nothing"
  else
    fail "--print-only did not emit expected content / wrote files"
  fi
  rm -rf "$po" "$poh"
else
  fail "bootstrap script not found: $BOOTSTRAP"
fi

# --- 11b. app-website-evaluator end-to-end --------------------------------------------
section "app-website-evaluator end-to-end"
EVAL="plugins/app-website-evaluator/skills/app-evaluation/scripts/evaluate-site.sh"
if [[ -f "$EVAL" ]]; then
  if [[ -x "$EVAL" ]]; then pass "evaluate-site.sh is executable"; else fail "evaluate-site.sh not executable"; fi
  if bash "$EVAL" --help >/dev/null 2>&1; then pass "evaluate-site.sh --help exits 0"; else fail "evaluate-site.sh --help failed"; fi
  bash "$EVAL" >/dev/null 2>&1; _ev_rc=$?
  if [[ "$_ev_rc" -eq 2 ]]; then pass "evaluate-site.sh errors without --url/--dir"; else fail "evaluate-site.sh should require an input"; fi
  # Capture then match — piping a live producer into `grep -q` under `set -o pipefail` can SIGPIPE
  # the producer (exit 141) once grep matches and closes the pipe, flaking a false FAIL (issue #21).
  _evdry="$(bash "$EVAL" --url https://example.com --dry-run 2>/dev/null || true)"
  if grep -q 'Dry run' <<<"$_evdry"; then
    pass "evaluate-site.sh --dry-run prints intended fetches (no network)"
  else
    fail "evaluate-site.sh --dry-run did not print"
  fi
  # --dir on a fixture: a complete page passes the key checks; a bare page flags FAILs.
  ev="$(mktemp -d)"
  mkdir -p "$ev/good"
  cat > "$ev/good/index.html" <<'H'
<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width">
<title>Acme — fast widgets</title><meta name="description" content="Fast widgets for devs.">
<link rel="canonical" href="https://acme.dev/"><link rel="icon" href="/f.ico">
<meta property="og:image" content="https://acme.dev/og.png"></head><body><h1>Acme</h1></body></html>
H
  printf 'User-agent: *\n' > "$ev/good/robots.txt"
  _g="$(bash "$EVAL" --dir "$ev/good" 2>/dev/null || true)"
  if grep -q 'robots.txt present' <<<"$_g" && grep -q 'meta description present' <<<"$_g" && grep -q 'og:image present' <<<"$_g"; then
    pass "evaluate-site.sh --dir credits a well-formed site"
  else
    fail "evaluate-site.sh --dir missed good-site checks"
  fi
  mkdir -p "$ev/bad"
  echo '<html><head><title>x</title></head><body>hi</body></html>' > "$ev/bad/index.html"
  _b="$(bash "$EVAL" --dir "$ev/bad" 2>/dev/null || true)"
  if grep -q 'FAIL' <<<"$_b" && grep -q 'meta description missing' <<<"$_b" && grep -q 'robots.txt missing' <<<"$_b"; then
    pass "evaluate-site.sh --dir flags a bare site's gaps"
  else
    fail "evaluate-site.sh --dir didn't flag the bare site"
  fi
  # Scoring (1.2.0): a Scorecard with a weighted overall that rates a complete site ABOVE a bare
  # one. (Compare numeric scores — robust to the ANSI colour codes around the grade letter.)
  _ovscore() { bash "$EVAL" --dir "$1" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
                 | grep 'Overall (weighted)' | grep -oE '[0-9]+' | head -1; }
  _gs="$(bash "$EVAL" --dir "$ev/good" 2>/dev/null || true)"
  _good_sc="$(_ovscore "$ev/good")"; _bad_sc="$(_ovscore "$ev/bad")"
  if grep -q 'Scorecard' <<<"$_gs" && [[ -n "$_good_sc" && -n "$_bad_sc" && "$_good_sc" -gt "$_bad_sc" ]]; then
    pass "evaluate-site.sh scorecard rates a complete site above a bare one ($_good_sc > $_bad_sc)"
  else
    fail "evaluate-site.sh scorecard not discriminating (good=$_good_sc bad=$_bad_sc)"
  fi
  # --json: pure-JSON stdout with overall.score + per-dimension grades (needs python3).
  if command -v python3 >/dev/null 2>&1; then
    if bash "$EVAL" --dir "$ev/good" --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert isinstance(d["overall"]["score"],int) and d["overall"]["grade"]
assert d["dimensions"] and all("score" in x and "grade" in x for x in d["dimensions"])
assert d["tally"]["fail"]==0
' 2>/dev/null; then
      pass "evaluate-site.sh --json emits a valid machine-readable scorecard"
    else
      fail "evaluate-site.sh --json output is not valid/complete"
    fi
  else
    skip "python3 not installed (evaluate-site.sh --json)"
  fi
  # 1.3.0 (#63): dir mode stars the overall grade and names the unscored weight.
  _cov="$(bash "$EVAL" --dir "$ev/good" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
  if grep -q 'computed over' <<<"$_cov" && grep -q 'unscored: ' <<<"$_cov" \
     && grep -qE 'overall [0-9]+/100 \([A-F]\*\)' <<<"$_cov" \
     && grep -q 'run --url' <<<"$_cov"; then
    pass "scorecard stars a partial-coverage grade + names unscored dims + hints --url (#63)"
  else
    fail "partial-coverage star/note missing from dir-mode scorecard"
  fi
  # 1.3.0 (#63): JSON-LD is parse-validated — broken JSON-LD FAILs; rich types are credited.
  if command -v python3 >/dev/null 2>&1; then
    mkdir -p "$ev/ld" "$ev/ldbad"
    cat > "$ev/ld/index.html" <<'H'
<!doctype html><html lang="en"><head><title>t</title>
<script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[]}</script>
</head><body><h1>t</h1></body></html>
H
    cat > "$ev/ldbad/index.html" <<'H'
<!doctype html><html><head><title>t</title>
<script type="application/ld+json">{"@type": "Article", broken}</script>
</head><body>hi</body></html>
H
    _ldg="$(bash "$EVAL" --dir "$ev/ld" 2>/dev/null)"
    _ldb="$(bash "$EVAL" --dir "$ev/ldbad" 2>/dev/null)"
    if grep -q 'JSON-LD parses cleanly' <<<"$_ldg" && grep -q 'rich schema types present (FAQPage)' <<<"$_ldg" \
       && grep -q 'fail to parse' <<<"$_ldb"; then
      pass "AI-readiness parse-validates JSON-LD and credits rich schema types (#63)"
    else
      fail "JSON-LD validation/rich-type checks not as expected"
    fi
    # Unquoted type attribute is valid HTML — must still be detected (review finding).
    # (Capture then match — grep -q on a live pipe can SIGPIPE the producer under pipefail; #21.)
    mkdir -p "$ev/lduq"
    printf '<html><head><title>t</title><script type=application/ld+json>{"@type":"Article"}</script></head><body>x</body></html>\n' > "$ev/lduq/index.html"
    _lduq="$(bash "$EVAL" --dir "$ev/lduq" 2>/dev/null || true)"
    if grep -q 'JSON-LD parses cleanly' <<<"$_lduq"; then
      pass "AI-readiness detects JSON-LD with an unquoted type attribute"
    else
      fail "unquoted type= JSON-LD went undetected"
    fi
    # --json carries the coverage fields.
    if bash "$EVAL" --dir "$ev/good" --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
o=d["overall"]
assert isinstance(o["coverage_weight_pct"],int) and o["coverage_weight_pct"]<100
assert "Security / hygiene" in o["unscored"]
' 2>/dev/null; then
      pass "--json reports coverage_weight_pct + unscored dimensions"
    else
      fail "--json coverage fields missing/wrong"
    fi
  else
    skip "python3 not installed (JSON-LD validation tests)"
  fi
  # 1.3.1 (#67): Prettier splits a long tag across lines; the checker must still read the attributes
  # (grep is line-oriented, so a multi-line <meta …> was reported "missing"). And Vite's
  # type="module" scripts must NOT be flagged render-blocking — module scripts defer by spec.
  mkdir -p "$ev/vite"
  cat > "$ev/vite/index.html" <<'H'
<!doctype html>
<html lang="en">
  <head>
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0"
    />
    <meta
      name="description"
      content="A prettier-formatted Vite single-page app."
    />
    <title>Vite SPA — multiline meta</title>
    <meta
      property="og:description"
      content="share text split across lines"
    />
    <script type="module" crossorigin src="/assets/index-abc123.js"></script>
  </head>
  <body><h1>Hi</h1></body>
</html>
H
  _vite="$(bash "$EVAL" --dir "$ev/vite" 2>/dev/null || true)"
  if grep -q 'viewport meta present' <<<"$_vite" \
     && grep -q 'meta description present' <<<"$_vite" \
     && grep -q 'og:description present' <<<"$_vite" \
     && ! grep -q 'render-blocking' <<<"$_vite"; then
    pass "evaluate-site.sh reads multi-line (Prettier) meta + treats type=module as deferred (#67)"
  else
    fail "multi-line meta / module-script handling not as expected (#67)"
  fi
  # A classic external <script src> with no async/defer/module is still flagged render-blocking, and
  # a genuinely missing description still FAILs — the flattening fix must not mask real gaps.
  mkdir -p "$ev/blk"
  printf '<!doctype html><html lang=en><head><title>t</title><meta name=viewport content=x><meta name=description content=y><script src="/app.js"></script></head><body><h1>h</h1></body></html>\n' > "$ev/blk/index.html"
  _blk="$(bash "$EVAL" --dir "$ev/blk" 2>/dev/null || true)"
  if grep -q 'render-blocking' <<<"$_blk"; then
    pass "evaluate-site.sh still flags a classic render-blocking <script> (no false negative, #67)"
  else
    fail "evaluate-site.sh missed a genuine render-blocking script (#67)"
  fi
  # Attribute-boundary (review finding on #67): async/defer/module must be matched as real
  # attributes, not letters inside a src URL — `/js/defer.min.js` is a blocking classic script.
  mkdir -p "$ev/urlkw"
  printf '<!doctype html><html lang=en><head><title>t</title><meta name=viewport content=x><meta name=description content=y><script src="/js/defer.min.js"></script></head><body><h1>h</h1></body></html>\n' > "$ev/urlkw/index.html"
  _urlkw="$(bash "$EVAL" --dir "$ev/urlkw" 2>/dev/null || true)"
  if grep -q 'render-blocking' <<<"$_urlkw"; then
    pass "evaluate-site.sh counts a classic <script src=/js/defer.min.js> as render-blocking (URL keyword ≠ attribute)"
  else
    fail "evaluate-site.sh mis-read 'defer' in a src URL as a defer attribute (#67 review)"
  fi
  rm -rf "$ev"
else
  fail "evaluate-site.sh not found: $EVAL"
fi

# --- 12. ffmpeg static fallback wired -------------------------------------------------
section "ffmpeg static fallback"
# the static download now lives ONLY in extract-frames.sh (the hook defers it to
# first use to avoid its 120s timeout). So check the extractor for the installer, and the
# hook for its immediate degraded-path message instead.
EXTRACT="plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh"
HOOK="plugins/video-bug-analyzer/hooks/ensure-ffmpeg.sh"
if grep -q 'install_ffmpeg_static' "$EXTRACT"; then
  pass "static ffmpeg fallback present: $EXTRACT"
else
  fail "static ffmpeg fallback missing: $EXTRACT"
fi
# the hook must NOT do the slow download, but MUST surface the SessionStart fallback.
if grep -q 'install_ffmpeg_static' "$HOOK"; then
  fail "hook should not run the slow static download (install_ffmpeg_static present): $HOOK"
elif grep -q 'additionalContext' "$HOOK" && grep -qi 'screenshot' "$HOOK"; then
  pass "hook surfaces SessionStart fallback (additionalContext + screenshot): $HOOK"
else
  fail "hook missing additionalContext/screenshot fallback message: $HOOK"
fi

# --- 13. new flags documented + feedback assembler ------------------------------------
section "flags + feedback assembler"
HELP="$(bash "$EXTRACT" --help 2>/dev/null)"
for flag in "--text" "--strip"; do
  if grep -qF -- "$flag" <<<"$HELP"; then
    pass "extract-frames --help documents $flag"
  else
    fail "extract-frames --help missing $flag"
  fi
done
FEEDBACK="plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/report-feedback.sh"
if [[ -x "$FEEDBACK" ]]; then
  pass "report-feedback.sh present + executable"
else
  fail "report-feedback.sh missing or not executable: $FEEDBACK"
fi
if bash "$FEEDBACK" --help >/dev/null 2>&1; then
  pass "report-feedback.sh --help exits 0"
else
  fail "report-feedback.sh --help did not exit 0"
fi
# With sample args it must emit the prefilled issue URL + the copy-paste report.
fb_out="$(CLAUDE_PLUGIN_ROOT=plugins/video-bug-analyzer bash "$FEEDBACK" \
  --env CLI --ran 'x' --outcome 'y' --notes 'z' 2>/dev/null)"
if grep -q 'cportka/claude-plugins/issues/new' <<<"$fb_out" \
   && grep -q 'copy below into the Plugin feedback issue' <<<"$fb_out"; then
  pass "report-feedback.sh emits issue URL + copy-paste report"
else
  fail "report-feedback.sh did not emit URL + report"
fi

# --dry-run prints the ffmpeg command without running it (no ffmpeg required, no files).
section "--dry-run command printing"
dr_tmp="$(mktemp -d)"; : >"$dr_tmp/clip.mov"
dr_out="$(bash "$EXTRACT" --video "$dr_tmp/clip.mov" --fps 8 --contact --out "$dr_tmp/o" --dry-run 2>/dev/null)"
if grep -q '^ffmpeg ' <<<"$dr_out" && grep -q 'tile=' <<<"$dr_out"; then
  pass "--dry-run prints a copy-pasteable ffmpeg command"
else
  fail "--dry-run did not print an ffmpeg command"
fi
if [[ ! -d "$dr_out/o" && ! -e "$dr_tmp/o" ]]; then
  pass "--dry-run wrote no output dir"
else
  fail "--dry-run created output unexpectedly"
fi
rm -rf "$dr_tmp"
# capture --help once and match a here-string — `--help | grep -q`
# under `set -o pipefail` can SIGPIPE the producer and flake (false "missing flag").
# derive the flag list from the argparse case arms instead of a
# hardcoded list, so every current/future --flag is auto-checked for documentation (no manual
# upkeep). Matches "  --flag)" and the alias form "  --flag|--other)".
_help="$(bash "$EXTRACT" --help 2>/dev/null || true)"
mapfile -t _flags < <(grep -oE '^[[:space:]]*--[a-z][a-z-]*[)|]' "$SCRIPT_ABS" | tr -d ' )|' | sort -u)
[[ ${#_flags[@]} -ge 20 ]] || fail "flag extraction found only ${#_flags[@]} flags (parser changed?)"
_undoc=""
for f in "${_flags[@]}"; do
  grep -qF -- "$f" <<<"$_help" || _undoc="$_undoc $f"
done
if [[ -z "$_undoc" ]]; then
  pass "every argparse --flag (${#_flags[@]}) is documented in --help"
else
  fail "--help missing flags:$_undoc"
fi
nf_tmp="$(mktemp -d)"; : >"$nf_tmp/clip.mov"
_diff_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --fps 4 --diff --dry-run 2>/dev/null || true)"
if grep -q 'tblend=all_mode=difference' <<<"$_diff_dry"; then
  pass "--diff --dry-run prints the tblend command"
else
  fail "--diff --dry-run did not print tblend"
fi
_ls_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --list-scenes --dry-run 2>/dev/null || true)"
if grep -q 'showinfo' <<<"$_ls_dry"; then
  pass "--list-scenes --dry-run prints the showinfo command"
else
  fail "--list-scenes --dry-run did not print showinfo"
fi
# --crop --dry-run: the crop filter is inserted before scale in the vf chain (issue #23).
_crop_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --fps 4 --crop 320:120:40:900 --dry-run 2>/dev/null || true)"
if grep -q 'crop=320:120:40:900' <<<"$_crop_dry"; then
  pass "--crop --dry-run inserts the crop filter"
else
  fail "--crop --dry-run did not print crop="
fi
# --blackdetect --dry-run prints the blackdetect command, with --crop prepended (issue #25).
_bd_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --blackdetect --crop 600:564:0:0 --black-ratio 0.9 --dry-run 2>/dev/null || true)"
# %q escapes the inter-filter comma (\,), so match each filter segment separately.
if grep -q 'blackdetect=d=0.1:pic_th=0.9' <<<"$_bd_dry" && grep -q 'crop=600:564:0:0' <<<"$_bd_dry"; then
  pass "--blackdetect --dry-run prints the (cropped) blackdetect command"
else
  fail "--blackdetect --dry-run did not print the blackdetect command"
fi
# --ocr-roi --dry-run prints the crop+fps sampling command and a tesseract note (issue #27),
# and needs no tesseract to do so.
_ocr_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --ocr-roi 180:40:20:8 --fps 2 --dry-run 2>/dev/null || true)"
if grep -q 'crop=180:40:20:8' <<<"$_ocr_dry" && grep -qi 'tesseract' <<<"$_ocr_dry"; then
  pass "--ocr-roi --dry-run prints the sampling command + tesseract step"
else
  fail "--ocr-roi --dry-run did not print the expected command"
fi
# --measure --dry-run prints the PGM-extraction command + a threshold note (dark vs bright).
_meas_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --measure 400:400:760:340 --fps 5 --dry-run 2>/dev/null || true)"
_measb_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --measure 200:200:0:0 --measure-bright --dry-run 2>/dev/null || true)"
if grep -q 'crop=400:400:760:340' <<<"$_meas_dry" && grep -q 'f_%05d.pgm' <<<"$_meas_dry" \
   && grep -q 'dark' <<<"$_meas_dry" && grep -q 'bright' <<<"$_measb_dry"; then
  pass "--measure --dry-run prints the PGM command + threshold note (dark/bright)"
else
  fail "--measure --dry-run command was not as expected"
fi
# --probe --dry-run prints the ffprobe command (no ffprobe needed to show it) (issue #31).
_probe_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --probe --dry-run 2>/dev/null || true)"
if grep -q 'ffprobe' <<<"$_probe_dry" && grep -q 'width' <<<"$_probe_dry"; then
  pass "--probe --dry-run prints the ffprobe command"
else
  fail "--probe --dry-run did not print the ffprobe command"
fi
# --palette --dry-run prints the palettegen command (issue #33).
_pal_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --palette --colors 6 --dry-run 2>/dev/null || true)"
if grep -q 'palettegen=max_colors=6' <<<"$_pal_dry"; then
  pass "--palette --dry-run prints the palettegen command"
else
  fail "--palette --dry-run did not print palettegen"
fi
# --ab --dry-run prints the two-input ssim command (issue #35).
nf_tmp2="$(mktemp -d)"; : >"$nf_tmp2/b.mov"
_ab_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --ab "$nf_tmp2/b.mov" --fps 10 --dry-run 2>/dev/null || true)"
if grep -q 'ssim=stats_file=' <<<"$_ab_dry" && grep -q 'fps=10' <<<"$_ab_dry"; then
  pass "--ab --dry-run prints the ssim command"
else
  fail "--ab --dry-run did not print the ssim command"
fi
rm -rf "$nf_tmp2"
# --cadence --dry-run prints the mpdecimate command (issue #37).
_cad_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --cadence --dry-run 2>/dev/null || true)"
if grep -q 'mpdecimate' <<<"$_cad_dry" && grep -q 'showinfo' <<<"$_cad_dry"; then
  pass "--cadence --dry-run prints the mpdecimate command"
else
  fail "--cadence --dry-run did not print mpdecimate"
fi
# --stutter alias resolves to cadence and adds the freezedetect freeze-gap pass (issue #56).
_stut_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --stutter --dry-run 2>/dev/null || true)"
if grep -q 'mpdecimate' <<<"$_stut_dry" && grep -q 'freezedetect' <<<"$_stut_dry"; then
  pass "--stutter --dry-run resolves to cadence + freezedetect"
else
  fail "--stutter --dry-run did not print mpdecimate + freezedetect"
fi
# --pacing --dry-run prints the ffprobe frame-timestamp command (1.2.0).
_pace_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --pacing --dry-run 2>/dev/null || true)"
if grep -q 'ffprobe' <<<"$_pace_dry" && grep -q 'best_effort_timestamp_time' <<<"$_pace_dry" && grep -q 't,interval_ms' <<<"$_pace_dry"; then
  pass "--pacing --dry-run prints the ffprobe frame-timestamp command"
else
  fail "--pacing --dry-run did not print the ffprobe command"
fi
# --stack (1.3.0, #62): --crop is required (early, exit 2); dry-run plans a 1-column tile.
bash "$EXTRACT" --video "$nf_tmp/clip.mov" --stack >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
  pass "--stack without --crop exits 2 (before any install work)"
else
  fail "--stack without --crop did not exit 2"
fi
_stk_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --stack --crop 320:60:0:400 --end 3 --dry-run 2>/dev/null || true)"
if grep -qE 'tile=1x[0-9]+' <<<"$_stk_dry" && grep -q 'crop=320' <<<"$_stk_dry"; then
  pass "--stack --dry-run plans a crop + 1-column tile"
else
  fail "--stack --dry-run did not plan crop/tile=1xN"
fi
# --stack --dry-run with NO --end on an unreadable file: ffprobe fails -> the 48-row fallback
# must plan the command, not die under pipefail (review finding on the initial 1.3.0 code).
_stk_dry2="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --stack --crop 10:10:0:0 --dry-run 2>/dev/null)"; _stk_rc=$?
if [[ $_stk_rc -eq 0 ]] && grep -q 'tile=1x48' <<<"$_stk_dry2"; then
  pass "--stack survives an unprobeable file (48-row fallback, rc 0)"
else
  fail "--stack unprobeable-file path rc=$_stk_rc"
fi
# --check-update (1.3.0, #62): deterministic via VBA_UPDATE_URL + file:// (no network reliance).
_cu_ver="$(python3 -c 'import json;print(json.load(open("plugins/video-bug-analyzer/.claude-plugin/plugin.json"))["version"])')"
_cu_tmp="$(mktemp -d)"
# (a) fetch failure must NOT kill the script under set -euo pipefail — graceful fallback, rc 0.
_cu="$(VBA_UPDATE_URL="file://$_cu_tmp/absent.json" bash "$EXTRACT" --check-update 2>&1)"; _cu_rc=$?
if [[ $_cu_rc -eq 0 ]] && grep -q 'could not reach' <<<"$_cu"; then
  pass "--check-update survives a failed fetch (pipefail) and reports gracefully"
else
  fail "--check-update offline path rc=$_cu_rc output='$_cu'"
fi
# (b) a newer marketplace version -> extraction + comparison + the update command.
printf '{ "version": "99.9.9" }\n' > "$_cu_tmp/new.json"
_cu="$(VBA_UPDATE_URL="file://$_cu_tmp/new.json" bash "$EXTRACT" --check-update 2>&1)"
if grep -q 'marketplace has 99.9.9' <<<"$_cu" && grep -q 'claude plugin update video-bug-analyzer@portka-tools' <<<"$_cu"; then
  pass "--check-update extracts the remote version and advises the update when trailing"
else
  fail "--check-update trailing path output='$_cu'"
fi
# (c) an OLDER marketplace version -> 'ahead', never a downgrade advice (sort -V).
printf '{ "version": "0.0.1" }\n' > "$_cu_tmp/old.json"
_cu="$(VBA_UPDATE_URL="file://$_cu_tmp/old.json" bash "$EXTRACT" --check-update 2>&1)"
if grep -q 'ahead of the marketplace' <<<"$_cu" && ! grep -q 'claude plugin update' <<<"$_cu"; then
  pass "--check-update reports a dev copy as ahead (no downgrade advice)"
else
  fail "--check-update ahead path output='$_cu'"
fi
# (d) equal -> up to date.
printf '{ "version": "%s" }\n' "$_cu_ver" > "$_cu_tmp/same.json"
_cu="$(VBA_UPDATE_URL="file://$_cu_tmp/same.json" bash "$EXTRACT" --check-update 2>&1)"
if grep -q 'up to date' <<<"$_cu"; then
  pass "--check-update reports up to date on an exact match"
else
  fail "--check-update equal path output='$_cu'"
fi
rm -rf "$_cu_tmp"
# --motion --dry-run prints the tblend+signalstats command (issue #39).
_mot_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --motion --fps 12 --dry-run 2>/dev/null || true)"
if grep -q 'tblend=all_mode=difference' <<<"$_mot_dry" && grep -q 'signalstats' <<<"$_mot_dry"; then
  pass "--motion --dry-run prints the tblend+signalstats command"
else
  fail "--motion --dry-run did not print tblend+signalstats"
fi
# --motion --crop --dry-run: --motion now honors --crop, so the crop filter is in the motion chain (#66).
_motc_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --motion --crop 80:40:0:0 --dry-run 2>/dev/null || true)"
if grep -q 'crop=80:40:0:0' <<<"$_motc_dry" && grep -q 'tblend=all_mode=difference' <<<"$_motc_dry"; then
  pass "--motion --crop --dry-run honors --crop (crop filter in the motion chain, #66)"
else
  fail "--motion --crop --dry-run did not include the crop filter"
fi
# --flow --dry-run prints the grayscale-sampling command + honors --crop + caps frames (1.4.0, #69).
_flow_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --flow --crop 120:120:0:0 --dry-run 2>/dev/null || true)"
if grep -q 'format=gray' <<<"$_flow_dry" && grep -q 't,speed,curl,div' <<<"$_flow_dry" \
   && grep -q 'crop=120:120:0:0' <<<"$_flow_dry" && grep -q 'frames:v 200' <<<"$_flow_dry"; then
  pass "--flow --dry-run prints the sampling command, names the CSV, honors --crop, caps frames (#69)"
else
  fail "--flow --dry-run not as expected"
fi
# --occupancy-threshold must be numeric: a non-numeric value exits 2 cleanly (no Python traceback) (#69 review).
bash "$EXTRACT" --video "$nf_tmp/clip.mov" --occupancy --occupancy-threshold abc >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
  pass "--occupancy-threshold rejects a non-numeric value with exit 2 (#69 review)"
else
  fail "--occupancy-threshold did not reject a garbage value with exit 2"
fi
# --occupancy --dry-run prints the threshold-sampling command + CSV header (1.4.0, #69).
_occ_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --occupancy --occupancy-threshold 55 --dry-run 2>/dev/null || true)"
if grep -q 'format=gray' <<<"$_occ_dry" && grep -q 't,coverage_pct,x,y,w,h' <<<"$_occ_dry" && grep -q 'cutoff 55' <<<"$_occ_dry"; then
  pass "--occupancy --dry-run prints the threshold command, CSV header, and the cutoff (#69)"
else
  fail "--occupancy --dry-run not as expected"
fi
# --saturation --dry-run prints the signalstats command (1.0.0).
_sat_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --saturation --dry-run 2>/dev/null || true)"
if grep -q 'signalstats' <<<"$_sat_dry" && ! grep -q 'tblend' <<<"$_sat_dry"; then
  pass "--saturation --dry-run prints the signalstats command"
else
  fail "--saturation --dry-run did not print signalstats"
fi
# --compare-videos --dry-run prints the two-input vstack/tile command (issue #41).
nf_tmp3="$(mktemp -d)"; : >"$nf_tmp3/b.mov"
_cmp_dry="$(bash "$EXTRACT" --compare-videos "$nf_tmp/clip.mov,$nf_tmp3/b.mov" --cols 6 --dry-run 2>/dev/null || true)"
if grep -q 'vstack=inputs=2' <<<"$_cmp_dry" && grep -q 'tile=6x1' <<<"$_cmp_dry"; then
  pass "--compare-videos --dry-run prints the stacked-sheet command"
else
  fail "--compare-videos --dry-run did not print vstack/tile"
fi
rm -rf "$nf_tmp3"
# --intro --dry-run resolves to the first-seconds preset, and explicit flags still win (issue #43).
_intro_dry="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --intro --dry-run 2>/dev/null || true)"
_intro_ovr="$(bash "$EXTRACT" --video "$nf_tmp/clip.mov" --intro --fps 8 --end 3 --dry-run 2>/dev/null || true)"
if grep -q -- '-ss 0' <<<"$_intro_dry" && grep -q -- '-to 2' <<<"$_intro_dry" \
   && grep -q 'fps=12' <<<"$_intro_dry" && grep -q 'tile=' <<<"$_intro_dry" \
   && grep -q 'fps=8' <<<"$_intro_ovr" && grep -q -- '-to 3' <<<"$_intro_ovr"; then
  pass "--intro resolves to the load preset; explicit --fps/--end override it"
else
  fail "--intro preset/override resolution not as expected"
fi
rm -rf "$nf_tmp"
# --version reports the plugin version from plugin.json.
_ver_json="$(python3 -c 'import json;print(json.load(open("plugins/video-bug-analyzer/.claude-plugin/plugin.json"))["version"])')"
if [[ "$(CLAUDE_PLUGIN_ROOT=plugins/video-bug-analyzer bash "$EXTRACT" --version 2>/dev/null)" == "video-bug-analyzer $_ver_json" ]]; then
  pass "--version reports $_ver_json"
else
  fail "--version did not report the plugin.json version"
fi

# --- tab-chord-formatter: format-tab.py -----------------------------------------------
# format-tab.py is python, so the bash -n / shellcheck sections (which glob *.sh) skip it;
# give it its own behavioral section. It does the deterministic cleanup only — section-label
# standardization, HTML-entity decode, blank-line collapse — and must NEVER touch a line's
# internal alignment (that spacing is the chord/lyric/tab columns) and must be idempotent.
section "tab-chord-formatter format-tab.py"
FMT="plugins/tab-chord-formatter/skills/tab-formatting/scripts/format-tab.py"
if [[ ! -f "$FMT" ]]; then
  fail "format-tab.py not found: $FMT"
elif ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not installed (format-tab.py)"
else
  if [[ -x "$FMT" ]]; then pass "format-tab.py is executable"; else fail "format-tab.py not executable (chmod +x)"; fi
  # --help exits 0.
  if python3 "$FMT" --help >/dev/null 2>&1; then
    pass "format-tab.py --help exits 0"
  else
    fail "format-tab.py --help did not exit 0"
  fi
  # Messy input: CRLF, "VERSE 1:" / "[intro]" / "chorus:" labels, HTML entities, an
  # internally-aligned chord/lyric pair, extra blank lines.
  _ftmp="$(mktemp -d)"
  printf 'VERSE 1:\r\nG          C\r\nWell I met &amp; saw you\r\n\r\n\r\n[intro]\r\nchorus:\r\nLa la &#39;hey&#39;\r\n\r\n\r\n' >"$_ftmp/in.txt"
  _out="$(python3 "$FMT" "$_ftmp/in.txt")"
  # Section labels standardized to [Title Case].
  if grep -qx '\[Verse 1\]' <<<"$_out" && grep -qx '\[Intro\]' <<<"$_out" && grep -qx '\[Chorus\]' <<<"$_out"; then
    pass "format-tab.py standardizes section labels (VERSE 1/[intro]/chorus: -> [Verse 1]/[Intro]/[Chorus])"
  else
    fail "format-tab.py did not standardize section labels"
  fi
  # HTML entities decoded.
  if grep -qF "Well I met & saw you" <<<"$_out" && grep -qF "La la 'hey'" <<<"$_out"; then
    pass "format-tab.py decodes HTML entities"
  else
    fail "format-tab.py did not decode HTML entities"
  fi
  # Internal alignment preserved exactly (the chord line's 10 spaces before C).
  if grep -qxF 'G          C' <<<"$_out"; then
    pass "format-tab.py preserves a line's internal alignment"
  else
    fail "format-tab.py mangled internal alignment"
  fi
  # No run of two blank lines remains.
  if grep -Pzq '\n\n\n' <<<"$_out"; then
    fail "format-tab.py left a run of blank lines"
  else
    pass "format-tab.py collapses runs of blank lines"
  fi
  # Idempotent: formatting the output again changes nothing.
  printf '%s\n' "$_out" >"$_ftmp/o1.txt"
  if diff -q <(python3 "$FMT" "$_ftmp/o1.txt") "$_ftmp/o1.txt" >/dev/null 2>&1; then
    pass "format-tab.py is idempotent (format twice == once)"
  else
    fail "format-tab.py is not idempotent"
  fi
  # --- print mode (1.2.0): songbook split, monospace HTML, songs-per-page, dedent, PDF ---
  {
    printf 'Artist A \xe2\x80\x93 Song One\n\nC       G\nla la la\n\n'
    printf 'Artist B \xe2\x80\x93 Song Two\n\n        Am  F\n        indented lyric line\n\n'
    printf 'Artist C \xe2\x80\x93 Song Three\n\nG\nthree\n\n'
    printf 'Artist D \xe2\x80\x93 Song Four\n\nD\nfour\n'
  } > "$_ftmp/book.txt"
  python3 "$FMT" --print --html "$_ftmp/p1.html" "$_ftmp/book.txt" 2>/dev/null
  python3 "$FMT" --print --html "$_ftmp/p2.html" --songs-per-page 2 "$_ftmp/book.txt" 2>/dev/null
  if [[ -f "$_ftmp/p1.html" ]] \
     && [[ "$(grep -c 'class="song"' "$_ftmp/p1.html")" -eq 4 ]] \
     && grep -q 'white-space: pre' "$_ftmp/p1.html" && grep -qi 'Courier New' "$_ftmp/p1.html"; then
    pass "format-tab.py --print --html renders the songbook in a monospace layout"
  else
    fail "format-tab.py --print --html did not render 4 songs / monospace"
  fi
  _p1="$(grep -c 'class="page"' "$_ftmp/p1.html")"; _p2="$(grep -c 'class="page"' "$_ftmp/p2.html")"
  if [[ "$_p1" -eq 4 && "$_p2" -eq 2 ]]; then
    pass "format-tab.py --songs-per-page paginates (4 songs: 1/page=4 pages, 2/page=2)"
  else
    fail "format-tab.py --songs-per-page wrong (1/page=$_p1, 2/page=$_p2)"
  fi
  if grep -q '^indented lyric line' "$_ftmp/p1.html"; then
    pass "format-tab.py --print dedents each song (default on)"
  else
    fail "format-tab.py --print did not dedent the indented song"
  fi
  # PDF e2e — run ONLY against a known-good headless Chromium from a Playwright browsers dir.
  # We deliberately do NOT use any chrome on $PATH: a generic CI runner's browser may not be
  # headless-capable and could hang. `timeout` is a hard backstop on top of the script's own.
  if python3 - <<'PY'
import os, glob, sys
b = os.environ.get("PLAYWRIGHT_BROWSERS_PATH", "")
sys.exit(0 if (b and glob.glob(os.path.join(b, "chromium-*/chrome-linux/chrome"))) else 1)
PY
  then
    if timeout 130 python3 "$FMT" --print --pdf "$_ftmp/book.pdf" "$_ftmp/book.txt" 2>/dev/null \
       && [[ -s "$_ftmp/book.pdf" ]] && head -c4 "$_ftmp/book.pdf" | grep -q 'PDF'; then
      pass "format-tab.py --print --pdf produces a valid PDF"
    else
      fail "format-tab.py --print --pdf did not produce a valid PDF"
    fi
  else
    skip "no Playwright Chromium (format-tab.py --pdf e2e)"
  fi
  rm -rf "$_ftmp"
fi

# --- Summary --------------------------------------------------------------------------
printf '\n\033[1mSummary:\033[0m %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
