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
#                     [--frame-width <px>] [--max-width <px>] [--diff] [--label] [--out <dir>]
#   extract-frames.sh --strip <before.png,after.png> [--out <dir>]   # stitch existing frames
#   extract-frames.sh --video <path> --list-scenes [--scene <thr>]   # print scene-cut times
#
# Options:
#   --video <path>      Input video file (required).
#   --start <ts>        Start time (e.g. 12, 0:12, 00:00:12.5). Default: start of clip.
#   --end <ts>          End time. Default: end of clip.
#   --fps <n>           Frames per second to sample (dense / contact / timestamp burst).
#                       Default: 4. Use 2 for an overview, 8+ to catch sub-second transients.
#   --scene <thr>       Scene-change mode: capture frames where the scene score exceeds
#                       <thr> (e.g. 0.1). Overrides --fps. Good for an unknown moment.
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
#   --diff              Frame-difference mode: emit diff_*.png where each frame is the change
#                       from the previous one (bright = motion). Confirms what moved / where.
#   --label             Burn the source timestamp onto each frame (dense/--diff/--timestamps).
#                       Best-effort: needs ffmpeg drawtext + a font; silently skipped if not.
#   --list-scenes       Print the timestamps (seconds) of detected scene cuts and exit; tune
#                       with --scene <thr> (default 0.3). Feed the cuts into --timestamps.
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
#
set -euo pipefail

VIDEO=""
START=""
END=""
FPS="4"
SCENE=""
CONTACT=""
COLS="4"
COLS_SET=""        # ADDED: track whether --cols was passed explicitly
ROWS="4"
PORTRAIT=""        # ADDED: --portrait (or auto-detected) -> fewer cols for tall captures
TILEW="480"        # CHANGED: was 320 — too small for text/code UIs (per DedTxt dogfood)
TILEW_SET=""       # ADDED: track whether --tile-width was passed explicitly
TEXT=""            # ADDED: --text preset (legible tiles for code/transcript UIs)
STRIP=""           # ADDED: --strip a,b -> hstack two existing frames (no --video needed)
TIMESTAMPS=""
WINDOW="0.5"
FRAMEW="820"
MAXW="1280"   # ADDED: cap width for dense/scene frames so native 4K doesn't blow tokens
OUT="./.frames"
OUT_SET=""    # ADDED: track whether --out was passed (else default per-video, see below)
DRY_RUN=""    # ADDED: --dry-run prints the exact ffmpeg commands instead of running them
DIFF=""       # ADDED: --diff emits frame-difference images (motion highlight)
LABEL=""      # ADDED: --label burns the source timestamp onto each frame (best-effort)
LIST_SCENES="" # ADDED: --list-scenes prints detected scene-cut timestamps, then exits
LABEL_VF=""   # computed drawtext filter segment (empty unless --label works on this build)

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# Convert a timestamp (SS | MM:SS | HH:MM:SS[.frac]) to seconds, for window arithmetic.
to_seconds() {
  awk -F: '{ s=$NF; if (NF>=2) s+=$(NF-1)*60; if (NF>=3) s+=$(NF-2)*3600; printf "%.3f", s }' <<<"$1"
}

# ADDED: warn (best-effort) when the source's real frame rate is well below the requested
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

# ADDED: echo "<width> <height>" of the source via ffprobe, or nothing if unavailable.
probe_wh() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=s=x:p=0 "$VIDEO" 2>/dev/null | tr 'x' ' '
}

# ADDED: contact-sheet tuning for tall/dense captures (issue #14). Auto-drops --cols to 2 for
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

# ADDED: find a usable TrueType font for --label (drawtext). Echoes a path or nothing.
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

# ADDED: build the --label drawtext segment, but only after PROBING that drawtext + the font
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
    --fps)   FPS="${2:-}";   shift 2 ;;
    --scene) SCENE="${2:-}"; shift 2 ;;
    --contact) CONTACT="1"; shift ;;
    --portrait) PORTRAIT="1"; shift ;;                 # ADDED: tall-capture contact preset
    --cols)  COLS="${2:-}";  COLS_SET=1; shift 2 ;;    # CHANGED: mark explicit override
    --rows)  ROWS="${2:-}";  shift 2 ;;
    --tile-width) TILEW="${2:-}"; TILEW_SET=1; shift 2 ;;   # CHANGED: mark explicit override
    --text) TEXT="1"; shift ;;                              # ADDED: legible-tiles preset
    --strip|--compare) STRIP="${2:-}"; shift 2 ;;           # ADDED: hstack two existing frames
    --timestamps) TIMESTAMPS="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --frame-width) FRAMEW="${2:-}"; shift 2 ;;
    --max-width) MAXW="${2:-}"; shift 2 ;;   # ADDED: cap for dense/scene frame width
    --out)   OUT="${2:-}";   OUT_SET=1; shift 2 ;;   # CHANGED: mark explicit override
    --dry-run) DRY_RUN=1; shift ;;                   # ADDED: print ffmpeg commands, don't run
    --diff)  DIFF=1; shift ;;                         # ADDED: frame-difference (motion) frames
    --label) LABEL=1; shift ;;                        # ADDED: burn source timestamp on frames
    --list-scenes) LIST_SCENES=1; shift ;;            # ADDED: print scene-cut timestamps, exit
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# ADDED: --text preset bumps contact tiles to a code/transcript-legible width unless the
# user set --tile-width explicitly.
[[ -n "$TEXT" && -z "$TILEW_SET" ]] && TILEW="640"

# CHANGED: --video is required EXCEPT in --strip mode (which operates on existing frames).
if [[ -z "$STRIP" ]]; then
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

# ADDED: default output to a per-video dir so a second clip in the same session doesn't
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

# CHANGED: skip install/diagnostic in --dry-run (no ffmpeg needed just to print commands).
[[ -n "$DRY_RUN" ]] || ensure_ffmpeg

# Diagnostic: which ffmpeg is in use (cite this when reporting extraction problems).
[[ -n "$DRY_RUN" ]] || echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1)" >&2

# ADDED: run an ffmpeg command, or — under --dry-run — print it (copy-pasteable) instead.
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
  # CHANGED: no ffmpeg (e.g. --dry-run on a host without it)? assume modern, don't crash.
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

[[ -n "$DRY_RUN" ]] || mkdir -p "$OUT"   # CHANGED: don't create dirs in --dry-run

# ADDED: --strip mode — stitch two EXISTING frames into a before/after strip (no --video).
# The single most useful artifact for a UI-state-transition bug (per DedTxt dogfood).
if [[ -n "$STRIP" ]]; then
  IFS=',' read -r _sa _sb <<<"$STRIP"
  if [[ -z "${_sa:-}" || -z "${_sb:-}" ]]; then
    echo "Error: --strip needs two frames: --strip before.png,after.png" >&2
    exit 2
  fi
  if [[ -z "$DRY_RUN" ]]; then   # CHANGED: skip existence check when only printing commands
    for _img in "$_sa" "$_sb"; do
      [[ -f "$_img" ]] || { echo "Error: --strip frame not found: $_img" >&2; exit 1; }
    done
  fi
  echo "Strip mode: $_sa | $_sb -> $OUT/strip.png" >&2
  # CHANGED: normalize both frames to a common height (even width via -2) before hstack, so
  # mismatched resolutions (e.g. a .mov frame vs a .webm frame) still stitch cleanly.
  run_ff -hide_banner -loglevel error -i "$_sa" -i "$_sb" \
    -filter_complex "[0:v]scale=-2:720[a];[1:v]scale=-2:720[b];[a][b]hstack=inputs=2" \
    -frames:v 1 "$OUT/strip.png"
  [[ -n "$DRY_RUN" ]] || echo "Wrote $OUT/strip.png (before/after; left=$_sa right=$_sb)."
  exit 0
fi

# ADDED: --list-scenes — print the timestamps (seconds, one per line) of detected scene cuts,
# then exit. Feed the interesting ones back into --timestamps. Threshold from --scene (def 0.3).
if [[ -n "$LIST_SCENES" ]]; then
  _thr="${SCENE:-0.3}"
  if [[ -n "$DRY_RUN" ]]; then
    run_ff -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" -f null -
    echo "(dry run — the command above prints showinfo lines; their pts_time values are the cuts)"
    exit 0
  fi
  echo "Scene cuts (threshold=$_thr) in $VIDEO — pts_time seconds:" >&2
  ffmpeg -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" -f null - 2>&1 \
    | sed -n 's/.*pts_time:\([0-9.][0-9.]*\).*/\1/p' || true
  exit 0
fi

# ADDED: prepare the optional --label timestamp-burn-in segment (probed; empty if unsupported).
build_label_vf

# ADDED: heads-up if the clip is sparser than the requested fps (dense/contact/timestamps).
[[ -z "$SCENE" && -z "$DRY_RUN" ]] && warn_if_sparse "$FPS"

# Build the leading seek/duration args (apply -ss/-to before -i for speed/accuracy).
PRE_ARGS=()
[[ -n "$START" ]] && PRE_ARGS+=(-ss "$START")
[[ -n "$END"   ]] && PRE_ARGS+=(-to "$END")

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
      -vf "fps=${FPS},scale=${FRAMEW}:-1${LABEL_VF}" \
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
  [[ -n "$LABEL" ]] && echo "Note: --label isn't applied to contact tiles; use it with dense/--diff/--timestamps." >&2
  echo "Contact-sheet mode [$MODE_DESC], ${COLS}x${ROWS} per sheet -> $OUT" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},scale=${TILEW}:-1,tile=${COLS}x${ROWS}" \
    "$OUT/contact_%04d.png"
elif [[ -n "$DIFF" ]]; then
  # ADDED: frame-difference mode — each frame is |this − previous| (tblend), so motion lights
  # up. Scan consecutive diffs to see what moved and infer direction (issue #16).
  set_vfr_flag
  echo "Frame-diff mode (fps=$FPS) -> $OUT (bright = changed pixels between frames)" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "fps=${FPS},tblend=all_mode=difference,scale='min(${MAXW},iw)':-1${LABEL_VF}" \
    "$OUT/diff_%04d.png"
elif [[ -n "$SCENE" ]]; then
  echo "Scene-change mode (threshold=$SCENE) -> $OUT" >&2
  # CHANGED: cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},scale='min(${MAXW},iw)':-1${LABEL_VF}" \
    "$OUT/scene_%04d.png"
else
  echo "Dense mode (fps=$FPS) -> $OUT" >&2
  # CHANGED: cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "${SELECT},scale='min(${MAXW},iw)':-1${LABEL_VF}" \
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
