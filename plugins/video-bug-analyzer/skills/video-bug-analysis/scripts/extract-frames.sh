#!/usr/bin/env bash
#
# extract-frames.sh — pull still frames out of a screen-recording for bug analysis.
#
# Claude cannot watch video; it can only read still frames. This script extracts them
# either densely over a time window (default) or at scene-change boundaries, so the
# right moment is actually captured instead of being missed between sparse samples.
#
# Usage:
#   extract-frames.sh --video <path> [--start <ts>] [--end <ts>] [--fps <n>]
#                     [--scene <thr>] [--contact] [--text] [--cols <n>] [--rows <n>]
#                     [--tile-width <px>] [--timestamps <t1,t2,...>] [--window <sec>]
#                     [--frame-width <px>] [--max-width <px>] [--crop <W:H:X:Y>] [--diff]
#                     [--label] [--out <dir>]
#   extract-frames.sh --strip <before.png,after.png> [--out <dir>]   # stitch existing frames
#   extract-frames.sh --video <path> --list-scenes [--scene <thr>]   # print scene-cut times
#   extract-frames.sh --video <path> --blackdetect [--crop <W:H:X:Y>] # find black-out spans
#   extract-frames.sh --video <path> --ocr-roi <W:H:X:Y> [--fps <n>]  # OCR a region -> t,text CSV
#   extract-frames.sh --video <path> --measure <W:H:X:Y> [--fps <n>]  # feature diameter/center CSV
#   extract-frames.sh --video <path> --probe                         # capture geometry/orientation
#   extract-frames.sh --video <path> --palette [--colors <n>]        # dominant colours (hex)
#   extract-frames.sh --video <a> --ab <b> [--fps <n>]               # A/B divergence over time
#   extract-frames.sh --video <path> --cadence [--window <sec>]      # stutter / frame-cadence timeline
#   extract-frames.sh --video <path> --motion [--fps <n>]            # mean inter-frame motion timeline
#   extract-frames.sh --video <path> --saturation [--fps <n>]        # colour-saturation timeline
#   extract-frames.sh --compare-videos a.mov,b.mov [--cols <n>]      # one A/B phase-aligned sheet
#   extract-frames.sh --video <path> --intro                        # load/splash preset (first ~2s)
#
# Options:
#   --video <path>      Input video file (required).
#   --start <ts>        Start time (e.g. 12, 0:12, 00:00:12.5). Default: start of clip.
#   --end <ts>          End time. Default: end of clip.
#   --fps <n>           Frames per second to sample (dense / contact / timestamp burst).
#                       Default: 4. Use 2 for an overview, 8+ to catch sub-second transients.
#   --scene <thr>       Scene-change mode: capture frames where the scene score exceeds
#                       <thr> (e.g. 0.1). Overrides --fps. Good for an unknown moment.
#   --intro             Load/splash preset: the first ~2s as a dense, labelled contact sheet
#                       (= --start 0 --end 2 --fps 12 --contact --label, portrait-aware). Each
#                       part yields to an explicit flag (--end 3 / --fps 8 still win). Load and
#                       splash bugs live at t=0 and are sub-second — this is the right default.
#   --contact           Contact-sheet mode: tile the sampled frames into a single image
#                       (or a few), so the whole timeline can be read in one file with
#                       far fewer tokens. Combines with --fps or --scene for selection.
#   --text              Contact preset for code/transcript UIs: bumps tile width to 640
#                       (unless --tile-width is given) so on-screen text stays readable.
#   --portrait          Contact preset for tall phone captures: 2 columns (bigger tiles).
#                       Auto-enabled when ffprobe detects a portrait source. (Contact only.)
#   --cols <n>          Columns per contact sheet. Default: 4 (2 for portrait). (Contact only.)
#   --rows <n>          Rows per contact sheet. Default: 4. (Contact mode only.)
#   --tile-width <px>   Width each frame is scaled to in a contact sheet. Default: 480.
#   --strip <a,b>       (alias --compare) Stitch two EXISTING frames into a before/after
#                       strip (hstack) at <out>/strip.png. No --video needed. Best artifact
#                       for a UI-state-transition bug.
#   --timestamps <list> Comma-separated moments (e.g. "0:12,0:34"). For each, extract a
#                       dense burst over a +/-window plus a before/after strip image —
#                       great for showing a flagged transient. Ignores --scene/--contact.
#   --window <sec>      Half-width of each timestamp burst, in seconds. Default: 0.5.
#   --frame-width <px>  Width burst frames are scaled to. Default: 820 (keeps text legible).
#   --max-width <px>    Cap width for dense/scene frames so native (e.g. 4K) PNGs don't blow
#                       tokens. Never upscales smaller clips. Default: 1280.
#   --out <dir>         Output directory for PNG frames. Default: ./.frames/<video-name>
#                       (per-video, so a second clip doesn't clobber the first); ./.frames
#                       in --strip mode.
#   --dry-run           Print the exact ffmpeg command(s) this would run, without running
#                       them (no ffmpeg needed). Lets a live agent that can't load the
#                       plugin mid-session copy the commands and run them by hand.
#   --crop <W:H:X:Y>    Crop a region (ffmpeg geometry, e.g. 320:120:40:900) before scaling,
#                       so that region fills the frame — a zoom on an on-screen FPS/HUD, a
#                       counter, or any small UI area. Applies to dense/scene/contact/diff/
#                       timestamp modes. iw/ih expressions allowed (e.g. iw/4:ih/4:0:0).
#   --diff              Frame-difference mode: emit diff_*.png where each frame is the change
#                       from the previous one (bright = motion). Confirms what moved / where.
#   --label             Burn the source timestamp onto each frame (dense/--diff/--timestamps,
#                       and contact tiles + --compare-videos). Best-effort: needs ffmpeg
#                       drawtext + a font; silently skipped if unavailable.
#   --list-scenes       Print the timestamps (seconds) of detected scene cuts and exit; tune
#                       with --scene <thr> (default 0.3). Feed the cuts into --timestamps.
#   --blackdetect       Find blacked-out spans (black/blank screen bug) and exit, printing
#                       each as "black START -> END (dur) — PERMANENT/transient". Permanent =
#                       sustained to EOF (needs ffprobe). Combine with --crop to ignore a
#                       static UI overlay that keeps a few pixels lit (the common false-miss).
#   --black-min <sec>   Minimum black-span duration to report. Default: 0.1.
#   --black-ratio <r>   Fraction of pixels that must be black for a frame to count (pic_th,
#                       0..1). Default: 0.98. Lower (e.g. 0.90) if an overlay keeps pixels lit.
#   --ocr-roi <W:H:X:Y> Value tracker: OCR a small region (a panel readout — body counts, a
#                       Speed value) once per sampled frame and print a "t,text" CSV to stdout.
#                       Use when the symptom is a NUMBER changing (e.g. a count 4->5->4), not a
#                       render artifact — a value timeline localises a state/logic bug in
#                       seconds. Sample rate from --fps; honors --start/--end. Needs tesseract
#                       (the one mode beyond ffmpeg); prints an install hint if it's missing.
#   --ocr-digits        Restrict OCR to digits and a few separators (cleaner for numeric
#                       readouts: counts, speeds, timers). Use with --ocr-roi.
#   --measure <W:H:X:Y> Geometry/measurement: inside this ROI, measure the bounding box of a
#                       dark feature (an event-horizon shadow, a dot, a blob) once per sampled
#                       frame and print a CSV: t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy.
#                       diam_px is the major axis; diam_pct_w/h are % of viewport width/height
#                       (vmin flips by orientation — see --probe); cx,cy are full-frame px.
#                       For visual-tuning ("how big is this circle, over time"). Robust to a
#                       photon ring / accretion disk that breaks a naive center-row scan. Sample
#                       rate from --fps; honors --start/--end. Needs python3 (+ ffprobe for the
#                       % column): ffmpeg extracts grayscale frames, python3 measures the box.
#   --measure-bright    Measure a BRIGHT feature (a ring, a glow) instead of a dark one.
#   --measure-limit <n> Luma threshold 0..255: dark mode counts pixels BELOW it, bright mode
#                       ABOVE it. Default 80. Tune if too little / too much is bounded.
#   --probe             Print the capture's geometry — dimensions, aspect ratio, orientation
#                       (portrait/landscape), fps, duration — and which axis CSS vmin maps to.
#                       Use it before measuring so % figures are read on the right axis. (ffprobe.)
#   --palette           Print the clip's dominant colours as a hex swatch list (an art-direction
#                       reference's palette is part of the deliverable). Narrow with --start/--end
#                       to read one phase. Sample rate from --fps. Needs python3.
#   --colors <n>        How many dominant colours --palette extracts. Default: 8.
#   --ab <other>        A/B divergence: compare --video against <other> (two captures of the
#                       SAME sequence — e.g. a different browser/device) and print a t,ssim CSV
#                       (1.0 = identical, lower = more different), headlining the most divergent
#                       moments. Both are sampled at --fps and scaled to the primary's size, so
#                       it answers "these intros differ most at 0.20-0.28s". --start/--end align
#                       the window on both. The cross-browser-bug tool. (Uses ffmpeg ssim.)
#   --cadence           Stutter timeline: report the nominal frame rate vs the real average
#                       (dropped/duplicated frames = choppiness), then a per-window count of
#                       UNIQUE frames so you see WHEN it stutters. Prints t,unique_frames,fps and
#                       headlines the choppiest windows. --window sets the bin (default 0.5s);
#                       honors --start/--end. Measures UNIQUE-content cadence, so a deliberately
#                       static scene also reads low (nothing new). (ffmpeg mpdecimate + ffprobe;
#                       needs python3.)
#   --motion            Motion timeline: print t,motion (mean inter-frame pixel delta, 0..255)
#                       per sampled frame, so "is it moving / where does motion concentrate?"
#                       becomes a number. Quantifies --diff. Sample rate from --fps; honors
#                       --start/--end. (ffmpeg tblend+signalstats; needs python3.)
#   --saturation        Colour-saturation timeline: print t,saturation (signalstats SATAVG,
#                       0 grey .. ~180 vivid) per sampled frame, so "clownish/over-saturated vs
#                       muted/elegant" is measurable and verifiable after a fix. Sample rate from
#                       --fps; honors --start/--end. (ffmpeg signalstats; needs python3.)
#   --compare-videos a,b  A/B comparison sheet: ONE image, a row per clip, each clip sampled
#                       into <--cols> tiles spread across its OWN duration (normalized phase
#                       axis), so two clips of different lengths line up by % through the
#                       sequence — "why does B differ from A" (fresh vs replay, before/after,
#                       two browsers). Writes <out>/compare.png. --label burns each tile's
#                       timestamp. Needs ffprobe. (Names its own inputs; no --video.)
#   --version           Print the plugin version and exit.
#
# Every run prints a one-line "smoothness:" header (effective vs nominal fps + a dropped-frame
# estimate) — the quickest "is it choppy?" read; --cadence / --motion localize it.
#   -h, --help          Show this help.
#
# ffmpeg is required. It's already on PATH in many environments; if it's missing this tries
# apt -> brew -> a static build from GitHub (BtbN) then johnvansickle. A locked-down sandbox
# may block that or require approval — then give Claude a still screenshot of the bad moment.
#
# Examples:
#   extract-frames.sh --video bug.mov --fps 2 --contact --text       # legible overview
#   extract-frames.sh --video bug.mov --timestamps 0:12,0:34 --fps 8 # zoom + strips
#   extract-frames.sh --video bug.mov --start 0:11 --end 0:14 --fps 8
#   extract-frames.sh --strip .frames/frame_0003.png,.frames/frame_0009.png  # before/after
#   extract-frames.sh --video bug.mov --fps 8 --contact --dry-run    # print cmds, don't run
#   extract-frames.sh --video bug.mov --fps 8 --crop 320:120:40:900  # zoom an FPS/HUD region
#   extract-frames.sh --video bug.mov --blackdetect --crop 600:564:0:0  # find a black-screen bug
#   extract-frames.sh --video bug.mov --ocr-roi 180:40:20:8 --ocr-digits --fps 2  # count timeline
#   extract-frames.sh --video bug.mov --measure 400:400:760:340 --fps 5  # shadow diameter over time
#   extract-frames.sh --video bug.mov --probe                            # aspect/orientation/dpr note
#   extract-frames.sh --video ref.mov --start 4 --end 5.7 --palette      # one phase's colours
#   extract-frames.sh --video safari.mov --ab firefox.mov --fps 10       # where do they diverge?
#   extract-frames.sh --video splash.mov --cadence --window 0.5          # when does it stutter?
#   extract-frames.sh --video splash.mov --motion --fps 12               # when/where is motion?
#   extract-frames.sh --video splash.mov --saturation --fps 6            # vivid vs muted, over time
#   extract-frames.sh --compare-videos fresh.mov,replay.mov --label      # A vs B, phase-aligned
#   extract-frames.sh --video app.mov --intro                            # "the intro does X" — t=0
#
set -euo pipefail

ORIG_ARGS=("$@")   # remember the invocation for the end-of-run feedback link
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # locate plugin.json

VIDEO=""
START=""
END=""
FPS="4"
SCENE=""
CONTACT=""
COLS="4"
COLS_SET=""        # track whether --cols was passed explicitly
ROWS="4"
PORTRAIT=""        # --portrait (or auto-detected) -> fewer cols for tall captures
TILEW="480"        # was 320 — too small for text/code UIs (per DedTxt dogfood)
TILEW_SET=""       # track whether --tile-width was passed explicitly
TEXT=""            # --text preset (legible tiles for code/transcript UIs)
STRIP=""           # --strip a,b -> hstack two existing frames (no --video needed)
TIMESTAMPS=""
WINDOW="0.5"
FRAMEW="820"
MAXW="1280"   # cap width for dense/scene frames so native 4K doesn't blow tokens
OUT="./.frames"
OUT_SET=""    # track whether --out was passed (else default per-video, see below)
DRY_RUN=""    # --dry-run prints the exact ffmpeg commands instead of running them
DIFF=""       # --diff emits frame-difference images (motion highlight)
LABEL=""      # --label burns the source timestamp onto each frame (best-effort)
LIST_SCENES="" # --list-scenes prints detected scene-cut timestamps, then exits
LABEL_VF=""   # computed drawtext filter segment (empty unless --label works on this build)
CROP=""       # --crop W:H:X:Y (ffmpeg geometry) -> crop a region, then scale = zoom
CROP_VF=""    # computed crop filter segment (empty unless --crop given)
BLACKDETECT="" # --blackdetect finds blacked-out spans, then exits
BLACK_D="0.1"  # --black-min, minimum black-span duration (seconds) to report
BLACK_RATIO="0.98" # --black-ratio, fraction of pixels that must be black (pic_th)
OCR_ROI=""     # --ocr-roi W:H:X:Y -> OCR a region per frame -> t,text CSV
OCR_DIGITS=""  # --ocr-digits restricts OCR to a numeric whitelist (counts/readouts)
MEASURE=""     # --measure W:H:X:Y -> bounding box / diameter of a feature
MEASURE_LIMIT="80"  # --measure-limit, luma threshold (dark<thr / bright>thr) 0..255
MEASURE_BRIGHT=""   # --measure-bright measures a bright feature (else dark, default)
PROBE=""       # --probe prints capture geometry (aspect/orientation), exits
PALETTE=""     # --palette prints dominant colours (hex swatches), then exits
COLORS="8"     # --colors, how many dominant colours --palette extracts
AB=""          # --ab <other> SSIM-diffs two clips over time, then exits
CADENCE=""     # --cadence reports a frame-cadence/jitter timeline, then exits
MOTION=""      # --motion prints a mean inter-frame pixel-delta timeline, exits
CMP_VIDEOS=""  # --compare-videos a,b -> one stacked phase-aligned contact sheet
INTRO=""       # --intro = load/splash preset (first ~2s, dense contact + labels)
SATURATION=""  # --saturation prints a per-frame colour-saturation timeline, exits
FPS_SET=""     # track whether --fps was passed (so presets don't override it)

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# Convert a timestamp (SS | MM:SS | HH:MM:SS[.frac]) to seconds, for window arithmetic.
to_seconds() {
  awk -F: '{ s=$NF; if (NF>=2) s+=$(NF-1)*60; if (NF>=3) s+=$(NF-2)*3600; printf "%.3f", s }' <<<"$1"
}

# read this plugin's version from plugin.json (for --version and the feedback link).
_plugin_version() {
  local pj="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/.claude-plugin/plugin.json"
  [[ -f "$pj" ]] || { echo "unknown"; return 0; }
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version","unknown"))' "$pj" 2>/dev/null || echo unknown
  else
    grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/' || echo unknown
  fi
}

# at the end of a real run, print a one-click, pre-filled feedback link
# (plugin + ffmpeg version + the exact command already encoded) and a one-line nudge. Goes to
# stderr so it never pollutes output; suppress with VBA_NO_FEEDBACK_HINT=1.
feedback_hint() {
  [[ -z "$DRY_RUN" && -z "${VBA_NO_FEEDBACK_HINT:-}" ]] || return 0
  local ver ffv cmd url
  ver="$(_plugin_version || true)"
  ffv="$(ffmpeg -version 2>/dev/null | head -n1 || true)"
  cmd="extract-frames.sh ${ORIG_ARGS[*]:-}"
  if command -v python3 >/dev/null 2>&1; then
    url="$(FB_V="$ver" FB_F="$ffv" FB_C="$cmd" python3 - <<'PY' 2>/dev/null || true
import os, urllib.parse
base = "https://github.com/cportka/claude-plugins/issues/new"
p = {"template": "plugin-feedback.yml"}
for env, field in [("FB_V", "version"), ("FB_F", "ffmpeg"), ("FB_C", "command")]:
    v = os.environ.get(env, "").strip()
    if v:
        p[field] = v
print(base + "?" + urllib.parse.urlencode(p))
PY
)"
  fi
  [[ -n "${url:-}" ]] || url="https://github.com/cportka/claude-plugins/issues/new?template=plugin-feedback.yml"
  {
    echo ""
    echo "Helpful or buggy? One-click feedback (pre-filled): $url"
    echo "(Say if it helped or broke; you can attach a contact sheet from ${OUT}. Hide with VBA_NO_FEEDBACK_HINT=1.)"
  } >&2
}

# warn (best-effort) when the source's real frame rate is well below the requested
# --fps, so duplicate frames aren't a surprise. Needs ffprobe; silent no-op without it.
warn_if_sparse() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  local raf actual
  raf="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
    -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null)"
  [[ "$raf" == */* ]] || return 0                       # expect a "num/den" rate
  actual="$(awk -F/ '{ if (($2+0)>0) printf "%.1f", $1/$2 }' <<<"$raf")"
  [[ -n "$actual" ]] || return 0
  if awk -v req="$1" -v act="$actual" 'BEGIN{ exit !(act>0 && req > act*1.3) }'; then
    echo "Note: source captures ~${actual} real fps; --fps $1 won't add detail (frames repeat). Lower --fps or accept duplicates." >&2
  fi
  return 0
}

# echo "<width> <height>" of the source via ffprobe, or nothing if unavailable.
probe_wh() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=s=x:p=0 "$VIDEO" 2>/dev/null | tr 'x' ' '
}

# contact-sheet tuning for tall/dense captures (issue #14). Auto-drops --cols to 2 for
# portrait sources (unless --cols was given), and warns when tiles downscale the source so far
# that small UI text will be illegible — suggesting full-res individual frames instead.
tune_contact_for_source() {
  local wh w h
  wh="$(probe_wh || true)"           # never let a probe failure abort the run (set -e)
  read -r w h <<<"${wh:-}" || true   # empty here-string returns non-zero under set -e
  # Portrait: explicit --portrait, or ffprobe says taller-than-wide.
  if [[ -z "$COLS_SET" ]] && { [[ -n "$PORTRAIT" ]] || { [[ -n "${w:-}" && -n "${h:-}" ]] && (( h > w )); }; }; then
    COLS=2
    echo "Portrait capture: using --cols 2 (override with --cols). For dense small text, full-res individual frames (drop --contact) read better than any contact sheet." >&2
  fi
  # Legibility guard: if each tile downscales the source width a lot, small text blurs.
  if [[ -n "${w:-}" ]] && awk -v sw="$w" -v tw="$TILEW" 'BEGIN{ exit !(tw>0 && sw/tw > 2.5) }'; then
    echo "Heads-up: contact tiles downscale this ${w}px-wide source >2.5x; small UI text may be illegible — for dense text prefer full-res individual frames (drop --contact) or raise --tile-width / lower --cols." >&2
  fi
}

# find a usable TrueType font for --label (drawtext). Echoes a path or nothing.
_find_font() {
  local f
  if command -v fc-match >/dev/null 2>&1; then
    f="$(fc-match -f '%{file}' 2>/dev/null || true)"
    [[ -n "$f" && -f "$f" ]] && { printf '%s' "$f"; return 0; }
  fi
  for f in /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
           /usr/share/fonts/dejavu/DejaVuSans.ttf \
           /usr/share/fonts/TTF/DejaVuSans.ttf \
           /System/Library/Fonts/Supplemental/Arial.ttf; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# build the --label drawtext segment, but only after PROBING that drawtext + the font
# actually work on this ffmpeg build. If anything's off (no drawtext, no font, bad syntax),
# LABEL_VF stays empty and extraction proceeds unlabeled — the label never breaks a run.
build_label_vf() {
  LABEL_VF=""
  [[ -n "$LABEL" && -z "$DRY_RUN" ]] || return 0
  command -v ffmpeg >/dev/null 2>&1 || return 0
  local font filt
  font="$(_find_font || true)"
  [[ -n "$font" ]] || { echo "Note: --label found no usable font; skipping timestamp burn-in." >&2; return 0; }
  filt="drawtext=fontfile=${font}:text='%{pts\\:hms}':x=10:y=10:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.5"
  if ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=black:s=64x64:d=0.1" \
       -vf "$filt" -frames:v 1 -f null - >/dev/null 2>&1; then
    LABEL_VF=",$filt"
  else
    echo "Note: --label isn't supported by this ffmpeg/font; skipping timestamp burn-in." >&2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --start) START="${2:-}"; shift 2 ;;
    --end)   END="${2:-}";   shift 2 ;;
    --fps)   FPS="${2:-}";   FPS_SET=1; shift 2 ;;   # mark explicit override (issue #43)
    --scene) SCENE="${2:-}"; shift 2 ;;
    --contact) CONTACT="1"; shift ;;
    --portrait) PORTRAIT="1"; shift ;;                 # tall-capture contact preset
    --cols)  COLS="${2:-}";  COLS_SET=1; shift 2 ;;    # mark explicit override
    --rows)  ROWS="${2:-}";  shift 2 ;;
    --tile-width) TILEW="${2:-}"; TILEW_SET=1; shift 2 ;;   # mark explicit override
    --text) TEXT="1"; shift ;;                              # legible-tiles preset
    --strip|--compare) STRIP="${2:-}"; shift 2 ;;           # hstack two existing frames
    --timestamps) TIMESTAMPS="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --frame-width) FRAMEW="${2:-}"; shift 2 ;;
    --max-width) MAXW="${2:-}"; shift 2 ;;   # cap for dense/scene frame width
    --out)   OUT="${2:-}";   OUT_SET=1; shift 2 ;;   # mark explicit override
    --dry-run) DRY_RUN=1; shift ;;                   # print ffmpeg commands, don't run
    --diff)  DIFF=1; shift ;;                         # frame-difference (motion) frames
    --label) LABEL=1; shift ;;                        # burn source timestamp on frames
    --list-scenes) LIST_SCENES=1; shift ;;            # print scene-cut timestamps, exit
    --crop) CROP="${2:-}"; shift 2 ;;                  # crop region W:H:X:Y, then zoom
    --blackdetect) BLACKDETECT=1; shift ;;            # find black spans, exit
    --black-min) BLACK_D="${2:-}"; shift 2 ;;         # min black-span duration (seconds)
    --black-ratio) BLACK_RATIO="${2:-}"; shift 2 ;;   # black-pixel fraction (pic_th)
    --ocr-roi) OCR_ROI="${2:-}"; shift 2 ;;           # OCR a region -> CSV
    --ocr-digits) OCR_DIGITS=1; shift ;;              # numeric-only OCR whitelist
    --measure) MEASURE="${2:-}"; shift 2 ;;           # feature bbox/diameter
    --measure-limit) MEASURE_LIMIT="${2:-}"; shift 2 ;;  # cropdetect luma cutoff
    --measure-bright) MEASURE_BRIGHT=1; shift ;;      # measure a bright feature (not dark)
    --probe) PROBE=1; shift ;;                        # print capture geometry
    --palette) PALETTE=1; shift ;;                    # dominant colours, exit
    --colors) COLORS="${2:-}"; shift 2 ;;             # number of palette colours
    --ab) AB="${2:-}"; shift 2 ;;                      # A/B divergence vs <other>
    --cadence) CADENCE=1; shift ;;                    # frame-cadence timeline
    --motion) MOTION=1; shift ;;                      # inter-frame motion timeline
    --compare-videos) CMP_VIDEOS="${2:-}"; shift 2 ;; # A/B stacked contact sheet
    --intro) INTRO=1; shift ;;                        # first-seconds load preset
    --saturation) SATURATION=1; shift ;;             # colour-saturation timeline
    --version) echo "video-bug-analyzer $(_plugin_version)"; exit 0 ;;  # ADDED
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# --intro preset — load/splash bugs live at t=0 and are sub-second, so this
# is shorthand for "the first ~2s, densely, as a labelled contact sheet". Each piece yields to an
# explicit flag (e.g. --end 3 or --fps 8 still win); portrait auto-detection still applies.
if [[ -n "$INTRO" ]]; then
  [[ -z "$START" ]] && START="0"
  [[ -z "$END"   ]] && END="2"
  [[ -z "$FPS_SET" ]] && FPS="12"
  CONTACT="1"; LABEL="1"
fi

# --text preset bumps contact tiles to a code/transcript-legible width unless the
# user set --tile-width explicitly.
[[ -n "$TEXT" && -z "$TILEW_SET" ]] && TILEW="640"

# --video is required EXCEPT in --strip and --compare-videos modes (they name their
# own inputs / operate on existing frames).
if [[ -z "$STRIP" && -z "$CMP_VIDEOS" ]]; then
  if [[ -z "$VIDEO" ]]; then
    echo "Error: --video is required." >&2
    echo "Run with --help for usage." >&2
    exit 2
  fi
  if [[ ! -f "$VIDEO" ]]; then
    echo "Error: video file not found: $VIDEO" >&2
    exit 1
  fi
fi

# default output to a per-video dir so a second clip in the same session doesn't
# clobber the first's frames. --out overrides; --strip (no video) keeps the plain default.
[[ -z "$OUT_SET" && -n "$VIDEO" ]] && OUT=".frames/$(basename "${VIDEO%.*}")"

# --- Ensure ffmpeg is available -------------------------------------------------------
# Cache dir for a downloaded static ffmpeg; shared with the SessionStart hook so either
# can populate it and this script will find it.
FFMPEG_CACHE="${HOME:-/tmp}/.cache/portka-video-bug-analyzer/bin"

# Last resort when apt/brew aren't available: download a static ffmpeg build into the cache
# dir and add it to PATH for this run. Tries GitHub release assets first (reachable in many
# sandboxes where apt/other hosts are blocked), then johnvansickle. Override the source with
# $VBA_FFMPEG_URL. Best-effort; returns non-zero if it can't (no network/curl/wget/tar).
install_ffmpeg_static() {
  local gh_a jv_a u tmp found bindir
  command -v tar >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64|amd64)  gh_a=linux64;    jv_a=amd64 ;;
    aarch64|arm64) gh_a=linuxarm64; jv_a=arm64 ;;
    *) return 1 ;;
  esac
  local urls=(
    "${VBA_FFMPEG_URL:-}"
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n7.1-latest-${gh_a}-gpl.tar.xz"
    "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${jv_a}-static.tar.xz"
  )
  tmp="$(mktemp -d)" || return 1
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] || continue
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --max-time 300 "$u" -o "$tmp/ff.tar.xz" 2>/dev/null || continue
    else
      wget -q --timeout=300 -O "$tmp/ff.tar.xz" "$u" 2>/dev/null || continue
    fi
    tar -xJf "$tmp/ff.tar.xz" -C "$tmp" 2>/dev/null || continue
    found="$(find "$tmp" -type f -name ffmpeg -print -quit 2>/dev/null)"
    [[ -n "$found" ]] && break
  done
  [[ -n "${found:-}" ]] || { rm -rf "$tmp"; return 1; }
  bindir="$(dirname "$found")"
  mkdir -p "$FFMPEG_CACHE" || { rm -rf "$tmp"; return 1; }
  cp "$bindir/ffmpeg" "$FFMPEG_CACHE/" 2>/dev/null || true
  if [[ -f "$bindir/ffprobe" ]]; then cp "$bindir/ffprobe" "$FFMPEG_CACHE/" 2>/dev/null || true; fi
  chmod +x "$FFMPEG_CACHE/ffmpeg" 2>/dev/null || true
  rm -rf "$tmp"
  export PATH="$FFMPEG_CACHE:$PATH"
  command -v ffmpeg >/dev/null 2>&1
}

ensure_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1; then
    return 0
  fi
  echo "ffmpeg not found; attempting to install it..." >&2
  if command -v apt-get >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y >/dev/null 2>&1 || true
      sudo apt-get install -y ffmpeg >/dev/null 2>&1 || true
    else
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y ffmpeg >/dev/null 2>&1 || true
    fi
  elif command -v brew >/dev/null 2>&1; then
    brew install ffmpeg >/dev/null 2>&1 || true
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    return 0
  fi
  echo "Package manager unavailable or blocked; trying a static ffmpeg build..." >&2
  install_ffmpeg_static && return 0
  cat >&2 <<'EOF'
Error: ffmpeg is required but could not be installed automatically (apt/brew and the static
builds all failed — outbound network or the command's approval is likely restricted).
Options:
  - Approve / run the install yourself (see docs/INTEGRATE.md for the permission rule), or
  - Install manually:  sudo apt-get install -y ffmpeg   |   brew install ffmpeg
  - Static build (GitHub, often reachable): https://github.com/BtbN/FFmpeg-Builds/releases
  - Or skip the video entirely: give Claude a still screenshot of the exact bad moment.
EOF
  return 1
}

# Reuse a previously cached static build (e.g. installed by the SessionStart hook).
[[ -x "$FFMPEG_CACHE/ffmpeg" ]] && export PATH="$FFMPEG_CACHE:$PATH"

# skip install/diagnostic in --dry-run (no ffmpeg needed just to print commands).
[[ -n "$DRY_RUN" ]] || ensure_ffmpeg

# Diagnostic: which ffmpeg is in use (cite this when reporting extraction problems).
[[ -n "$DRY_RUN" ]] || echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1)" >&2

# a one-line smoothness header on every run — effective (avg) vs nominal (r)
# frame rate + a dropped/duplicated estimate. The single best "is it choppy?" number, for free
# (one ffprobe call), so it never has to be reached for by hand. Best-effort; silent without it.
print_smoothness() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  [[ -n "$VIDEO" && -f "$VIDEO" ]] || return 0
  local rfr afr
  rfr="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate   -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  afr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  [[ -n "$rfr" && -n "$afr" ]] || return 0
  awk -v r="$rfr" -v a="$afr" '
    function fr(s,  p){ if(index(s,"/")){split(s,p,"/"); return (p[2]+0)?p[1]/p[2]:0} return s+0 }
    BEGIN{ R=fr(r); A=fr(a); if(R<=0||A<=0) exit;
      printf "smoothness: effective %.1f fps vs nominal %.1f fps", A, R;
      if (A < R) { d=(1-A/R)*100; if (d>=5) printf "  (~%.0f%% frames dropped/duplicated — likely choppy; --cadence/--motion to localize)", d }
      printf "\n";
    }' >&2
}
[[ -n "$DRY_RUN" ]] || print_smoothness

# run an ffmpeg command, or — under --dry-run — print it (copy-pasteable) instead.
# Lets a live agent that can't load the plugin mid-session replicate the workflow by hand.
run_ff() {
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' "$@"; printf '\n'
  else
    ffmpeg "$@"
  fi
}

# Newer ffmpeg (>=5.1) replaced "-vsync vfr" with "-fps_mode vfr". Pick what this build
# supports so variable-rate frame selection works without deprecation warnings; fall back
# to -vsync on older builds (or if the version string can't be parsed).
VFR=()
set_vfr_flag() {
  # no ffmpeg (e.g. --dry-run on a host without it)? assume modern, don't crash.
  command -v ffmpeg >/dev/null 2>&1 || { VFR=(-fps_mode vfr); return 0; }
  local ver major minor
  ver="$(ffmpeg -version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
  major="${ver%%.*}"
  minor="${ver#*.}"
  if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] \
     && { (( major > 5 )) || { (( major == 5 )) && (( minor >= 1 )); }; }; then
    VFR=(-fps_mode vfr)
  else
    VFR=(-vsync vfr)
  fi
}

# blackdetect mode — find blacked-out spans and classify each as transient
# (a flash) or permanent (sustained to end of file). Honors --crop, so a static UI overlay
# (a lil-gui panel, a HUD) can be excluded from the black-ratio test before detection — the
# manual canvas-crop step the dogfood reporter had to do by hand. Uses CROP_VF / PRE_ARGS,
# so it must run after those are built.
run_blackdetect() {
  local vf="${CROP_VF}blackdetect=d=${BLACK_D}:pic_th=${BLACK_RATIO}"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -f null -
    printf '\n'
    echo "(dry run — the command above prints 'black_start:.. black_end:..' lines on stderr)"
    return 0
  fi
  echo "Black-frame detection (min ${BLACK_D}s, pic_th ${BLACK_RATIO}${CROP:+, crop ${CROP}}) in $VIDEO:" >&2
  # blackdetect logs "black_start:.. black_end:.. black_duration:.." to stderr at info level.
  local log
  log="$(ffmpeg -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -f null - 2>&1 || true)"
  # Source duration (for the permanent-vs-transient test); empty if ffprobe is unavailable.
  local dur=""
  if command -v ffprobe >/dev/null 2>&1; then
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null || true)"
  fi
  local _spans found=""
  _spans="$(grep -oE 'black_start:[0-9.]+ black_end:[0-9.]+ black_duration:[0-9.]+' <<<"$log" || true)"
  if [[ -n "$_spans" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      found=1
      local _s _e _d kind
      _s="${line#black_start:}"; _s="${_s%% *}"
      _e="${line#*black_end:}";  _e="${_e%% *}"
      _d="${line##*black_duration:}"
      kind="transient (recovers)"
      if [[ -n "$dur" ]]; then
        # Permanent if the span runs to (within 0.5s of) the end of the file.
        kind="$(awk -v e="$_e" -v d="$dur" 'BEGIN{ print (e >= d - 0.5) ? "PERMANENT (sustained to EOF)" : "transient (recovers)" }')"
      fi
      printf 'black %ss -> %ss (%.3fs) — %s\n' "$_s" "$_e" "$_d" "$kind"
    done <<<"$_spans"
  fi
  if [[ -z "$found" ]]; then
    echo "No black spans >= ${BLACK_D}s at pic_th ${BLACK_RATIO}." >&2
    echo "If a UI overlay keeps some pixels lit, crop to the app canvas (--crop W:H:X:Y) and/or lower --black-ratio (e.g. 0.90)." >&2
  fi
  [[ -z "$dur" ]] && echo "Note: ffprobe not found — can't classify permanent-vs-transient (showing spans only)." >&2
}

# ROI value tracker — sample a small region per frame and OCR it into a
# "t,text" CSV (on stdout). For state/logic bugs the symptom is a panel readout changing
# (a count going 4->5->4), not a render artifact — a value timeline localises it in seconds
# where staring at frames can't. Needs tesseract (the one mode beyond ffmpeg); degrades with a
# clear install hint if it's missing. Uses PRE_ARGS, so it must run after those are built.
run_ocr_roi() {
  local roi="$1"
  local vf="crop=${roi},fps=${FPS}"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "<tmp>/f_%05d.png"; printf '\n'
    echo "# then OCR each f_*.png with tesseract --psm 7 -> rows of: t,\"text\"  (t = start + (frame-1)/${FPS})"
    return 0
  fi
  if ! command -v tesseract >/dev/null 2>&1; then
    echo "Error: --ocr-roi needs tesseract (OCR) — the one mode beyond ffmpeg." >&2
    echo "Install: sudo apt-get install -y tesseract-ocr  |  brew install tesseract  — then re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "$d/f_%05d.png"
  local cfg=()
  # Numeric whitelist for count/speed readouts — cuts OCR noise when --ocr-digits is set.
  [[ -n "$OCR_DIGITS" ]] && cfg=(-c "tessedit_char_whitelist=0123456789.,:/x %-")
  local base; base="$(to_seconds "${START:-0}")"
  echo "t,text"
  local i=0 f t txt
  for f in "$d"/f_*.png; do
    [[ -e "$f" ]] || break
    i=$((i + 1))
    t="$(awk -v i="$i" -v fps="$FPS" -v b="$base" 'BEGIN{ printf "%.3f", b + (i-1)/fps }')"
    # --psm 7: treat the ROI as a single text line. Collapse whitespace; trim.
    txt="$(tesseract "$f" stdout --psm 7 "${cfg[@]}" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ *$//' || true)"
    printf '%s,"%s"\n' "$t" "${txt//\"/\"\"}"   # CSV-quote (double any embedded quotes)
  done
  rm -rf "$d"
  echo "OCR timeline: $i samples over ROI ${roi} at ${FPS} fps. If values change with no nearby" >&2
  echo "pixel change, the cause is likely logic/state (off-screen) — check logs / a headless repro." >&2
}

# geometry/measurement — measure the bounding box (apparent diameter +
# center) of a dark (or --measure-bright) feature inside an ROI, once per sampled frame, as a
# t,...,diam_px,diam_pct,cx,cy CSV. For visual-tuning/alignment work the question is often "how
# big is this circle, as a % of viewport, over time" — a naive center-row dark-run breaks on a
# photon ring or accretion disk, but a 2-D bounding box is robust. ffmpeg extracts grayscale PGM
# frames (the one bulletproof step); python3 thresholds each and computes the box (so the result
# doesn't depend on a particular ffmpeg's cropdetect log format). Uses PRE_ARGS — run after them.
run_measure() {
  local roi="$1"
  # ROI is W:H:X:Y — only the X,Y offset is needed (to map the bbox back to full-frame center).
  local mx my; IFS=: read -r _ _ mx my <<<"$roi"
  local kind="dark"; [[ -n "$MEASURE_BRIGHT" ]] && kind="bright"
  local vf="crop=${roi},fps=${FPS},format=gray"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "<tmp>/f_%05d.pgm"
    printf '\n'
    echo "# then threshold each PGM (limit ${MEASURE_LIMIT}, ${kind}) -> 2-D bounding box -> CSV"
    echo "# t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --measure needs python3 to compute the bounding box. Install python3 and re-run." >&2
    exit 2
  fi
  # Viewport width AND height for %-of-viewport on both axes (vmin flips by orientation, #31);
  # empty if no ffprobe. diam_pct_w / diam_pct_h let the caller pick the right axis.
  local vw="" vh=""
  if command -v ffprobe >/dev/null 2>&1; then
    vw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    vh="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "$d/f_%05d.pgm" >/dev/null 2>&1 || true
  local base; base="$(to_seconds "${START:-0}")"
  # Threshold + bounding box per PGM frame (P5 is trivially parseable with the stdlib).
  python3 - "$d" "$MEASURE_LIMIT" "$kind" "$mx" "$my" "$FPS" "$base" "${vw:-}" "${vh:-}" <<'PY'
import sys, os, glob
d, limit, kind, mx, my, fps, base, vw, vh = sys.argv[1:10]
limit=int(limit); mx=int(mx); my=int(my); fps=float(fps); base=float(base)
vw=float(vw) if vw else None
vh=float(vh) if vh else None
def read_pgm(p):
    with open(p,'rb') as f: data=f.read()
    if data[:2]!=b'P5': return 0,0,b''
    i=2; vals=[]
    while len(vals)<3:                       # parse width, height, maxval (skip ws/comments)
        while i<len(data) and data[i:i+1].isspace(): i+=1
        if data[i:i+1]==b'#':
            while i<len(data) and data[i:i+1]!=b'\n': i+=1
            continue
        j=i
        while j<len(data) and not data[j:j+1].isspace(): j+=1
        vals.append(int(data[i:j])); i=j
    w,h,_maxv=vals; i+=1                      # one whitespace byte follows maxval
    return w,h,data[i:i+w*h]
def pct(diam, dim): return ("%.2f" % (diam/dim*100)) if dim else ""
print("t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy")
for n,p in enumerate(sorted(glob.glob(os.path.join(d,"f_*.pgm")))):
    w,h,px=read_pgm(p)
    minx=miny=10**9; maxx=maxy=-1
    for y in range(h):
        row=px[y*w:(y+1)*w]
        for x in range(w):
            v=row[x]
            if (v<limit) if kind=="dark" else (v>limit):
                if x<minx: minx=x
                if x>maxx: maxx=x
                if y<miny: miny=y
                if y>maxy: maxy=y
    t=base+n/fps
    if maxx<0:                               # nothing matched the threshold this frame
        print("%.3f,0,0,0,,,0,0" % t); continue
    bw=maxx-minx+1; bh=maxy-miny+1; diam=bw if bw>bh else bh
    print("%.3f,%d,%d,%d,%s,%s,%d,%d" % (t, bw, bh, diam, pct(diam,vw), pct(diam,vh),
                                         mx+minx+bw//2, my+miny+bh//2))
PY
  local n; n="$(find "$d" -maxdepth 1 -name 'f_*.pgm' | wc -l)"
  rm -rf "$d"
  local orient="" axis=""
  if [[ -n "$vw" && -n "$vh" ]]; then
    if (( vw < vh )); then orient="portrait";  axis="diam_pct_w (= % of width)"
    elif (( vw > vh )); then orient="landscape"; axis="diam_pct_h (= % of height)"
    else orient="square"; axis="either axis"; fi
  fi
  echo "Measured $n frame(s) of the ${kind} feature in ROI ${roi}${vw:+ (${vw}x${vh}${orient:+, $orient})}." >&2
  [[ -n "$orient" ]] && echo "For vmin-authored UI on a ${orient} capture, read ${axis}." >&2
  if [[ "$n" -eq 0 ]]; then
    echo "No frames sampled — check the clip and --start/--end." >&2
  fi
  [[ -z "$vw" ]] && echo "Note: ffprobe not found — diam_pct_* left blank (px only)." >&2
}

# --probe — print the capture's geometry (dimensions, aspect, orientation,
# fps, duration) so measurements aren't reasoned about on the wrong axis. dpr can't be known
# from pixels alone, so we report orientation + which axis vmin maps to instead.
run_probe() {
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffprobe'; printf ' %q' -v error -select_streams v:0 \
      -show_entries stream=width,height,avg_frame_rate -of default=nw=1 "$VIDEO"
    printf '\n'
    echo "# + format=duration; then derive aspect (gcd), orientation, and the vmin axis"
    return 0
  fi
  command -v ffprobe >/dev/null 2>&1 || { echo "Error: --probe needs ffprobe." >&2; exit 2; }
  local w h fr dur
  w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  fr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  [[ -n "$w" && -n "$h" ]] || { echo "Error: could not read dimensions from $VIDEO." >&2; exit 2; }
  # NOTE: gcd() is a top-level awk function (awk forbids defining it inside BEGIN); params use
  # distinct names from the split() array to avoid a name collision on stricter awks (mawk).
  awk -v w="$w" -v h="$h" -v fr="${fr:-0/0}" -v dur="${dur:-}" '
  function gcd(m,n,   t){ while(n){ t=m%n; m=n; n=t } return m }
  BEGIN{
    g=gcd(w,h); if(g<1)g=1;
    orient = (w<h)?"portrait":((w>h)?"landscape":"square");
    vmin   = (w<h)?"width":((w>h)?"height":"either");
    num=fr; den=1; if (index(fr,"/")){ split(fr,parts,"/"); num=parts[1]; den=(parts[2]==0?1:parts[2]) }
    fps=(den!=0)?num/den:0;
    printf "video: %dx%d\n", w, h;
    printf "aspect: %d:%d (%.3f W/H)\n", w/g, h/g, w/h;
    printf "orientation: %s\n", orient;
    if (fps>0) printf "fps: %.2f\n", fps;
    if (dur!="") printf "duration: %.2fs\n", dur;
    printf "note: on a %s capture, CSS vmin maps to viewport %s; report measurements as %% of that axis.\n", orient, vmin;
    printf "      (devicePixelRatio is not knowable from pixels alone — divide by dpr for CSS px if the capture is retina.)\n";
  }'
}

# --palette — extract the dominant colours of a clip (or a --start/--end
# window, e.g. one phase of a reference) as a hex swatch list. For art-direction reference work
# the palette IS part of the deliverable. ffmpeg's palettegen computes a representative palette
# to a PPM; python3 reads the swatches (so no PNG decoder is needed). Uses PRE_ARGS — run after.
run_palette() {
  local vf="fps=${FPS},palettegen=max_colors=${COLORS}:reserve_transparent=0:stats_mode=full"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v 1 "<tmp>/palette.ppm"
    printf '\n'
    echo "# then read the PPM swatches -> hex colour list (#rrggbb)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --palette needs python3 to read the swatches. Install python3 and re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v 1 "$d/palette.ppm" >/dev/null 2>&1 || true
  python3 - "$d/palette.ppm" "$COLORS" <<'PY'
import sys
p, k = sys.argv[1], int(sys.argv[2])
try:
    data = open(p, 'rb').read()
except OSError:
    sys.exit(0)
if data[:2] != b'P6':
    sys.exit(0)
i=2; vals=[]
while len(vals) < 3:                          # parse width, height, maxval (skip ws/comments)
    while i < len(data) and data[i:i+1].isspace(): i+=1
    if data[i:i+1] == b'#':
        while i < len(data) and data[i:i+1] != b'\n': i+=1
        continue
    j=i
    while j < len(data) and not data[j:j+1].isspace(): j+=1
    vals.append(int(data[i:j])); i=j
w,h,_mx = vals; i+=1
px = data[i:i+w*h*3]
seen=[]; s=set()
for o in range(0, len(px), 3):                 # unique colours, first-seen order
    c=(px[o], px[o+1], px[o+2])
    if c not in s:
        s.add(c); seen.append(c)
for (r,g,b) in seen[:k]:
    print("#%02x%02x%02x  rgb(%d,%d,%d)" % (r,g,b,r,g,b))
PY
  rm -rf "$d"
  echo "Palette: up to ${COLORS} dominant colours${START:+ from ${START}}${END:+ to ${END}} (sampled at ${FPS} fps)." >&2
}

# A/B divergence — compare two captures of the SAME sequence (e.g. the same
# intro on two browsers) and flag WHERE in time they diverge. Both are sampled at --fps and
# scaled to the primary's dimensions, then ffmpeg's ssim filter scores per-frame similarity to a
# stats file; we emit a t,ssim CSV (lower = more different) and headline the most divergent
# moments. The headline cross-browser-bug tool. Uses PRE_ARGS (applied to both) — run after them.
run_ab() {
  local other="$1"
  [[ -f "$other" ]] || { echo "Error: --ab comparison file not found: $other" >&2; exit 2; }
  local W="" H=""
  if command -v ffprobe >/dev/null 2>&1; then
    W="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    H="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$W" && -n "$H" ]] || { W=640; H=360; }   # fallback if ffprobe is unavailable
  local fc_pre="[0:v]fps=${FPS},scale=${W}:${H},setsar=1[a];[1:v]fps=${FPS},scale=${W}:${H},setsar=1[b];[a][b]ssim=stats_file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      "${PRE_ARGS[@]}" -i "$other" -filter_complex "${fc_pre}<tmp>/ssim.log" -f null -
    printf '\n'
    echo "# parse the ssim stats (n: / All:) -> CSV t,ssim; lowest SSIM = most divergent moment"
    return 0
  fi
  local sf; sf="$(mktemp)"
  # PRE_ARGS (-ss/-to) go before BOTH inputs so the two clips are aligned to the same window.
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" "${PRE_ARGS[@]}" -i "$other" \
    -filter_complex "${fc_pre}${sf}" -f null - >/dev/null 2>&1 || true
  local base; base="$(to_seconds "${START:-0}")"
  local csv
  csv="$(awk -v fps="$FPS" -v base="$base" '
    { n=""; s="";
      for(i=1;i<=NF;i++){ if($i ~ /^n:/) n=substr($i,3); if($i ~ /^All:/) s=substr($i,5) }
      if(n!="" && s!=""){ printf "%.3f,%s\n", base+(n-1)/fps, s } }' "$sf")"
  rm -f "$sf"
  echo "t,ssim"
  printf '%s\n' "$csv"
  if [[ -n "$csv" ]]; then
    echo "A/B divergence (1.0 = identical; lower = more different) — most divergent moments:" >&2
    printf '%s\n' "$csv" | sort -t, -k2 -g | head -n 3 | while IFS=, read -r _t _s; do
      printf '  t=%ss  ssim=%s\n' "$_t" "$_s" >&2
    done
  else
    echo "No SSIM samples — check both clips decode and overlap in time." >&2
  fi
  echo "(Both scaled to ${W}x${H} @ ${FPS} fps to compare; differing aspect ratios are stretched.)" >&2
}

# frame-cadence / jitter timeline. The container's nominal rate (r_frame_rate)
# vs its real average (avg_frame_rate) localizes choppiness to dropped/duplicated frames (the
# dogfood MVP); then mpdecimate finds the UNIQUE frames and we bucket them into --window bins so
# you see WHEN the stutter is (e.g. concentrated during an end-of-splash burst), not just an
# average. Emits a t,unique_frames,fps CSV; headlines nominal/effective + the choppiest windows.
run_cadence() {
  local rfr="" afr="" dur=""
  if command -v ffprobe >/dev/null 2>&1; then
    rfr="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate   -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    afr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "mpdecimate,showinfo" -an -f null -
    printf '\n'
    echo "# + ffprobe r_frame_rate/avg_frame_rate; bucket unique-frame pts_time into --window bins"
    echo "# -> CSV t,unique_frames,fps; headline nominal-vs-effective + choppiest windows"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --cadence needs python3 to bucket the timeline. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(to_seconds "${START:-0}")"
  # mpdecimate drops near-duplicate frames; showinfo logs the surviving (unique) frames' times.
  # Write them to a temp file and pass its PATH to python — a `python3 - <<'PY'` heredoc already
  # uses stdin for the program, so the frame times can't also come in on stdin.
  local tf; tf="$(mktemp)"
  ffmpeg -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "mpdecimate,showinfo" -an -f null - 2>&1 \
    | sed -n 's/.*pts_time:\([0-9.][0-9.]*\).*/\1/p' > "$tf" || true
  python3 - "${WINDOW}" "$base" "${rfr:-0}" "${afr:-0}" "${dur:-0}" "$tf" <<'PY'
import sys, math
window=float(sys.argv[1]) or 0.5
base=float(sys.argv[2])
def fr(s):
    try:
        if '/' in s:
            a,b=s.split('/'); b=float(b) or 1.0; return float(a)/b
        return float(s)
    except Exception:
        return 0.0
nominal=fr(sys.argv[3]); avg=fr(sys.argv[4])
try: duration=float(sys.argv[5])
except Exception: duration=0.0
times=sorted(base+float(x) for x in open(sys.argv[6]).read().split())
uniq=len(times)
span=(times[-1]-times[0]) if uniq>=2 else (duration or 0.0)
eff=uniq/span if span>0 else 0.0
# windowed unique-frame timeline
print("t,unique_frames,fps")
rows=[]
if times:
    t0=times[0]; tN=times[-1]
    nb=max(1, int(math.ceil((tN-t0)/window)) ) if window>0 else 1
    buckets={}
    for t in times:
        k=int((t-t0)//window)
        buckets[k]=buckets.get(k,0)+1
    for k in range(nb):
        cnt=buckets.get(k,0); ws=t0+k*window; fps=cnt/window
        rows.append((ws,cnt,fps)); print("%.3f,%d,%.2f"%(ws,cnt,fps))
e=sys.stderr
e.write("Cadence: nominal %.2f fps (r_frame_rate); container avg %.2f fps; unique %.2f fps over %.2fs (%d unique frames).\n"
        % (nominal, avg, eff, span, uniq))
if nominal>0 and eff>0 and eff < 0.85*nominal:
    e.write("Effective cadence is well below nominal -> dropped/duplicated frames (stutter). Choppiest windows:\n")
    for ws,cnt,fps in sorted(rows, key=lambda r:r[2])[:3]:
        e.write("  @%.2fs: %.1f fps (%d unique in %.2fs)\n" % (ws, fps, cnt, window))
else:
    e.write("Cadence looks steady (effective near nominal).\n")
PY
  rm -f "$tf"
}

# motion timeline — the mean inter-frame pixel delta over time, so "feels too
# long / choppy / is the dust even moving?" becomes a number and you can see WHERE motion
# concentrates. tblend=difference gives |this - previous|; signalstats' YAVG is that frame's
# average magnitude; metadata=print dumps it. Quantifies what --diff shows visually. Uses
# PRE_ARGS — run after them. Honors --crop? No: full-frame motion (crop the source first if needed).
run_motion() {
  local vf="fps=${FPS},tblend=all_mode=difference,signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.YAVG (mean |frame - prev|) per frame -> CSV t,motion (0..255)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --motion needs python3 to read the per-frame stats. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(to_seconds "${START:-0}")"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" <<'PY'
import sys
mfile, base, fps = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]) or 1.0
t=None; n=0; rows=[]
print("t,motion")
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        # frame:N pts:.. pts_time:..
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.YAVG="):
        try: y=float(line.split("=",1)[1])
        except ValueError: continue
        tt = (base+t) if t is not None else (base+n/fps)
        # n==0 is the first frame (no previous) — tblend passes it through, so skip the spurious value.
        if n>0:
            rows.append((tt,y)); print("%.3f,%.2f" % (tt,y))
        n+=1
e=sys.stderr
if rows:
    peak=max(rows,key=lambda r:r[1]); avg=sum(r[1] for r in rows)/len(rows)
    e.write("Motion: mean inter-frame delta %.2f (0-255 luma); peak %.2f @ %.2fs over %d samples.\n"
            % (avg, peak[1], peak[0], len(rows)))
    e.write("Brightest = most motion; flat-low spans = little/no change (static).\n")
else:
    e.write("No motion samples — clip too short or --fps too low.\n")
PY
  rm -f "$mfile"
}

# colour-saturation timeline — signalstats' SATAVG per sampled frame, so "is this
# clownish/over-saturated or muted/elegant?" is a number you can verify after a fix (requested in
# the rc.16/rc.17 dogfeeds). 0 ≈ greyscale; higher ≈ more vivid (SAT maxes ~180). Uses PRE_ARGS.
run_saturation() {
  local vf="fps=${FPS},signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.SATAVG per frame -> CSV t,saturation (0 grey .. ~180 vivid)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --saturation needs python3 to read the per-frame stats. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(to_seconds "${START:-0}")"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" <<'PY'
import sys
mfile, base, fps = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]) or 1.0
t=None; n=0; rows=[]
print("t,saturation")
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.SATAVG="):
        try: s=float(line.split("=",1)[1])
        except ValueError: continue
        tt = (base+t) if t is not None else (base+n/fps)
        rows.append((tt,s)); print("%.3f,%.2f" % (tt,s)); n+=1
e=sys.stderr
if rows:
    peak=max(rows,key=lambda r:r[1]); avg=sum(r[1] for r in rows)/len(rows)
    e.write("Saturation: average %.1f (0 grey .. ~180 vivid); peak %.1f @ %.2fs over %d frames.\n"
            % (avg, peak[1], peak[0], len(rows)))
    e.write("High/sustained = vivid/'clownish'; low = muted/'elegant'. Compare against the look you want.\n")
else:
    e.write("No saturation samples — clip too short or --fps too low.\n")
PY
  rm -f "$mfile"
}

[[ -n "$DRY_RUN" ]] || mkdir -p "$OUT"   # don't create dirs in --dry-run

# --strip mode — stitch two EXISTING frames into a before/after strip (no --video).
# The single most useful artifact for a UI-state-transition bug (per DedTxt dogfood).
if [[ -n "$STRIP" ]]; then
  IFS=',' read -r _sa _sb <<<"$STRIP"
  if [[ -z "${_sa:-}" || -z "${_sb:-}" ]]; then
    echo "Error: --strip needs two frames: --strip before.png,after.png" >&2
    exit 2
  fi
  if [[ -z "$DRY_RUN" ]]; then   # skip existence check when only printing commands
    for _img in "$_sa" "$_sb"; do
      [[ -f "$_img" ]] || { echo "Error: --strip frame not found: $_img" >&2; exit 1; }
    done
  fi
  echo "Strip mode: $_sa | $_sb -> $OUT/strip.png" >&2
  # normalize both frames to a common height (even width via -2) before hstack, so
  # mismatched resolutions (e.g. a .mov frame vs a .webm frame) still stitch cleanly.
  run_ff -hide_banner -loglevel error -i "$_sa" -i "$_sb" \
    -filter_complex "[0:v]scale=-2:720[a];[1:v]scale=-2:720[b];[a][b]hstack=inputs=2" \
    -frames:v 1 "$OUT/strip.png"
  [[ -n "$DRY_RUN" ]] || echo "Wrote $OUT/strip.png (before/after; left=$_sa right=$_sb)."
  feedback_hint
  exit 0
fi

# --list-scenes — print the timestamps (seconds, one per line) of detected scene cuts,
# then exit. Feed the interesting ones back into --timestamps. Threshold from --scene (def 0.3).
if [[ -n "$LIST_SCENES" ]]; then
  _thr="${SCENE:-0.3}"
  if [[ -n "$DRY_RUN" ]]; then
    run_ff -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" -f null -
    echo "(dry run — the command above prints showinfo lines; their pts_time values are the cuts)"
    exit 0
  fi
  echo "Scene cuts (threshold=$_thr) in $VIDEO — pts_time seconds:" >&2
  # capture, then guide the user if no cuts were found at this threshold.
  _cuts="$(ffmpeg -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" \
    -f null - 2>&1 | sed -n 's/.*pts_time:\([0-9.][0-9.]*\).*/\1/p' || true)"
  if [[ -n "$_cuts" ]]; then
    printf '%s\n' "$_cuts"
  else
    echo "No scene cuts at threshold ${_thr}. Try a lower --scene (e.g. 0.1), or sample steadily with --fps." >&2
  fi
  feedback_hint
  exit 0
fi

# prepare the optional --label timestamp-burn-in segment (probed; empty if unsupported).
build_label_vf

# --compare-videos a,b — ONE stacked contact sheet, a row per clip on a
# NORMALIZED phase axis (N columns spread across each clip's own duration), so two clips of
# different lengths line up by % through the sequence, not by absolute time. Answers "why does B
# differ from A" (fresh vs replay, before/after a fix, two browsers) in a single image. With
# --label, each tile gets its source timestamp burned in. Uses LABEL_VF — runs after build_label_vf.
run_compare_videos() {
  local a b; IFS=',' read -r a b <<<"$CMP_VIDEOS"
  if [[ -z "$a" || -z "$b" ]]; then
    echo "Error: --compare-videos needs two files: --compare-videos a.mov,b.mov" >&2; exit 2
  fi
  local cols="$COLS"; [[ -z "$COLS_SET" ]] && cols=8   # finer default phase axis for a comparison
  local da db
  da="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$a" 2>/dev/null | head -n1 || true)"
  db="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$b" 2>/dev/null | head -n1 || true)"
  # Frames-per-second to land ~cols frames across each clip's full duration (the phase axis).
  local fa fb
  fa="$(awk -v c="$cols" -v d="${da:-0}" 'BEGIN{ printf "%.6f", (d>0)?c/d:c }')"
  fb="$(awk -v c="$cols" -v d="${db:-0}" 'BEGIN{ printf "%.6f", (d>0)?c/d:c }')"
  local fc="[0:v]fps=${fa},scale=${TILEW}:-1${LABEL_VF},tile=${cols}x1[a];[1:v]fps=${fb},scale=${TILEW}:-1${LABEL_VF},tile=${cols}x1[b];[a][b]vstack=inputs=2"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error -i "$a" -i "$b" -filter_complex "$fc" -frames:v 1 "${OUT}/compare.png"
    printf '\n'
    echo "# top row = $a, bottom row = $b; ${cols} columns each = % through that clip (normalized phase axis)"
    return 0
  fi
  for f in "$a" "$b"; do [[ -f "$f" ]] || { echo "Error: --compare-videos file not found: $f" >&2; exit 2; }; done
  if [[ -z "$da" || -z "$db" ]]; then
    echo "Error: --compare-videos needs ffprobe to read each clip's duration." >&2; exit 2
  fi
  if ffmpeg -hide_banner -loglevel error -i "$a" -i "$b" -filter_complex "$fc" -frames:v 1 "$OUT/compare.png"; then
    echo "Wrote $OUT/compare.png — top row $a (${da}s), bottom row $b (${db}s), ${cols} cols across each." >&2
    echo "Columns align by % through each clip (normalized phase axis), NOT absolute time." >&2
  else
    echo "Error: --compare-videos failed (do both files decode?)." >&2; exit 1
  fi
}
if [[ -n "$CMP_VIDEOS" ]]; then
  run_compare_videos
  feedback_hint
  exit 0
fi

# crop a region (e.g. an on-screen FPS/HUD), applied before scale so the
# region is zoomed. Geometry is ffmpeg crop syntax W:H:X:Y (expressions like iw/ih allowed).
[[ -n "$CROP" ]] && CROP_VF="crop=${CROP},"

# heads-up if the clip is sparser than the requested fps (dense/contact/timestamps).
[[ -z "$SCENE" && -z "$DRY_RUN" ]] && warn_if_sparse "$FPS"

# Build the leading seek/duration args (apply -ss/-to before -i for speed/accuracy).
PRE_ARGS=()
[[ -n "$START" ]] && PRE_ARGS+=(-ss "$START")
[[ -n "$END"   ]] && PRE_ARGS+=(-to "$END")

# blackdetect is an analysis mode (no PNGs) — report spans and exit.
if [[ -n "$BLACKDETECT" ]]; then
  run_blackdetect
  feedback_hint
  exit 0
fi

# --ocr-roi is an analysis mode — emit a t,text value timeline and exit.
if [[ -n "$OCR_ROI" ]]; then
  run_ocr_roi "$OCR_ROI"
  feedback_hint
  exit 0
fi

# --measure is an analysis mode — emit a geometry timeline and exit.
if [[ -n "$MEASURE" ]]; then
  run_measure "$MEASURE"
  feedback_hint
  exit 0
fi

# --probe is an analysis mode — print capture geometry and exit.
if [[ -n "$PROBE" ]]; then
  run_probe
  feedback_hint
  exit 0
fi

# --palette is an analysis mode — print dominant colours and exit.
if [[ -n "$PALETTE" ]]; then
  run_palette
  feedback_hint
  exit 0
fi

# --ab is an analysis mode — print an A/B divergence timeline and exit.
if [[ -n "$AB" ]]; then
  run_ab "$AB"
  feedback_hint
  exit 0
fi

# --cadence is an analysis mode — print a frame-cadence timeline and exit.
if [[ -n "$CADENCE" ]]; then
  run_cadence
  feedback_hint
  exit 0
fi

# --motion is an analysis mode — print an inter-frame motion timeline and exit.
if [[ -n "$MOTION" ]]; then
  run_motion
  feedback_hint
  exit 0
fi

# --saturation is an analysis mode — print a colour-saturation timeline and exit.
if [[ -n "$SATURATION" ]]; then
  run_saturation
  feedback_hint
  exit 0
fi

# Choose how frames are selected: scene-change boundaries or a fixed sample rate.
if [[ -n "$SCENE" ]]; then
  SELECT="select='gt(scene,${SCENE})'"
  set_vfr_flag
  MODE_DESC="scene-change (threshold=$SCENE)"
else
  SELECT="fps=${FPS}"
  MODE_DESC="dense (fps=$FPS)"
fi

if [[ -n "$TIMESTAMPS" ]]; then
  # Timestamp mode: for each moment, a dense burst over a +/-window plus a before/after
  # strip (first & last burst frame side by side) — ideal for showing a transient.
  set_vfr_flag
  IFS=',' read -r -a _ts <<<"$TIMESTAMPS"
  i=0
  for t in "${_ts[@]}"; do
    [[ -n "$t" ]] || continue
    i=$((i + 1))
    idx="$(printf '%02d' "$i")"
    tsec="$(to_seconds "$t")"
    bstart="$(awk -v x="$tsec" -v w="$WINDOW" 'BEGIN{ s=x-w; if (s<0) s=0; printf "%.3f", s }')"
    bend="$(awk -v x="$tsec" -v w="$WINDOW" 'BEGIN{ printf "%.3f", x+w }')"
    echo "Timestamp $t -> burst [$bstart,$bend] @${FPS}fps -> $OUT/ts${idx}_*" >&2
    run_ff -hide_banner -loglevel error \
      -ss "$bstart" -to "$bend" -i "$VIDEO" "${VFR[@]}" \
      -vf "fps=${FPS},${CROP_VF}scale=${FRAMEW}:-1${LABEL_VF}" \
      "$OUT/ts${idx}_%03d.png"
    # Before/after strip from the first and last frame of the burst. (Skipped in --dry-run,
    # since it depends on the frames the burst above would have written.)
    [[ -n "$DRY_RUN" ]] && continue
    mapfile -t _f < <(find "$OUT" -maxdepth 1 -type f -name "ts${idx}_[0-9]*.png" | sort)
    if (( ${#_f[@]} >= 2 )); then
      run_ff -hide_banner -loglevel error \
        -i "${_f[0]}" -i "${_f[$(( ${#_f[@]} - 1 ))]}" \
        -filter_complex hstack -frames:v 1 \
        "$OUT/ts${idx}_strip.png"
    fi
  done
elif [[ -n "$CONTACT" ]]; then
  # Contact-sheet mode: scale each selected frame down and tile them into a grid, so the
  # whole timeline is one image (or a few). Spills into contact_0002.png, ... if needed.
  [[ -n "$DRY_RUN" ]] || tune_contact_for_source   # portrait auto-cols + illegibility (issue #14)
  # --label now burns the source timestamp into each tile too (drawtext is
  # applied per-frame, before tiling), which is exactly what timing analysis wants.
  echo "Contact-sheet mode [$MODE_DESC], ${COLS}x${ROWS} per sheet -> $OUT" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},${CROP_VF}scale=${TILEW}:-1${LABEL_VF},tile=${COLS}x${ROWS}" \
    "$OUT/contact_%04d.png"
elif [[ -n "$DIFF" ]]; then
  # frame-difference mode — each frame is |this − previous| (tblend), so motion lights
  # up. Scan consecutive diffs to see what moved and infer direction (issue #16).
  set_vfr_flag
  echo "Frame-diff mode (fps=$FPS) -> $OUT (bright = changed pixels between frames)" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "fps=${FPS},${CROP_VF}tblend=all_mode=difference,scale='min(${MAXW},iw)':-1${LABEL_VF}" \
    "$OUT/diff_%04d.png"
elif [[ -n "$SCENE" ]]; then
  echo "Scene-change mode (threshold=$SCENE) -> $OUT" >&2
  # cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},${CROP_VF}scale='min(${MAXW},iw)':-1${LABEL_VF}" \
    "$OUT/scene_%04d.png"
else
  echo "Dense mode (fps=$FPS) -> $OUT" >&2
  # cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "${SELECT},${CROP_VF}scale='min(${MAXW},iw)':-1${LABEL_VF}" \
    "$OUT/frame_%04d.png"
fi

if [[ -n "$DRY_RUN" ]]; then
  echo "(dry run — the ffmpeg command(s) above were printed, not executed; no files written)"
else
  COUNT=$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
  echo "Extracted ${COUNT} image(s) to: ${OUT}"
  if [[ -n "$CONTACT" ]]; then
    echo "Each contact sheet tiles frames left-to-right, top-to-bottom in time order."
  else
    echo "Read them in filename order to reconstruct the timeline."
  fi
fi

feedback_hint   # one-click pre-filled feedback nudge at end of run
