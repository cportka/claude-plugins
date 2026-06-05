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
#                     [--scene <thr>] [--contact] [--cols <n>] [--rows <n>]
#                     [--tile-width <px>] [--timestamps <t1,t2,...>] [--window <sec>]
#                     [--frame-width <px>] [--out <dir>]
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
#   --cols <n>          Columns per contact sheet. Default: 4. (Contact mode only.)
#   --rows <n>          Rows per contact sheet. Default: 4. (Contact mode only.)
#   --tile-width <px>   Width each frame is scaled to in a contact sheet. Default: 320.
#   --timestamps <list> Comma-separated moments (e.g. "0:12,0:34"). For each, extract a
#                       dense burst over a +/-window plus a before/after strip image —
#                       great for showing a flagged transient. Ignores --scene/--contact.
#   --window <sec>      Half-width of each timestamp burst, in seconds. Default: 0.5.
#   --frame-width <px>  Width burst frames are scaled to. Default: 820 (keeps text legible).
#   --out <dir>         Output directory for PNG frames. Default: ./.frames
#   -h, --help          Show this help.
#
# ffmpeg is required. If it's missing this tries apt -> brew -> a static build from GitHub
# (BtbN) then johnvansickle. In a locked-down sandbox the install may be blocked or need
# your approval — then give Claude a still screenshot of the bad moment instead.
#
# Examples:
#   extract-frames.sh --video bug.mov --fps 2 --contact             # cheap overview
#   extract-frames.sh --video bug.mov --timestamps 0:12,0:34 --fps 8 # zoom + strips
#   extract-frames.sh --video bug.mov --start 0:11 --end 0:14 --fps 8
#
set -euo pipefail

VIDEO=""
START=""
END=""
FPS="4"
SCENE=""
CONTACT=""
COLS="4"
ROWS="4"
TILEW="320"
TIMESTAMPS=""
WINDOW="0.5"
FRAMEW="820"
OUT="./.frames"

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# Convert a timestamp (SS | MM:SS | HH:MM:SS[.frac]) to seconds, for window arithmetic.
to_seconds() {
  awk -F: '{ s=$NF; if (NF>=2) s+=$(NF-1)*60; if (NF>=3) s+=$(NF-2)*3600; printf "%.3f", s }' <<<"$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --start) START="${2:-}"; shift 2 ;;
    --end)   END="${2:-}";   shift 2 ;;
    --fps)   FPS="${2:-}";   shift 2 ;;
    --scene) SCENE="${2:-}"; shift 2 ;;
    --contact) CONTACT="1"; shift ;;
    --cols)  COLS="${2:-}";  shift 2 ;;
    --rows)  ROWS="${2:-}";  shift 2 ;;
    --tile-width) TILEW="${2:-}"; shift 2 ;;
    --timestamps) TIMESTAMPS="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --frame-width) FRAMEW="${2:-}"; shift 2 ;;
    --out)   OUT="${2:-}";   shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if [[ -z "$VIDEO" ]]; then
  echo "Error: --video is required." >&2
  echo "Run with --help for usage." >&2
  exit 2
fi

if [[ ! -f "$VIDEO" ]]; then
  echo "Error: video file not found: $VIDEO" >&2
  exit 1
fi

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

ensure_ffmpeg

# Diagnostic: which ffmpeg is in use (cite this when reporting extraction problems).
echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1)" >&2

# Newer ffmpeg (>=5.1) replaced "-vsync vfr" with "-fps_mode vfr". Pick what this build
# supports so variable-rate frame selection works without deprecation warnings; fall back
# to -vsync on older builds (or if the version string can't be parsed).
VFR=()
set_vfr_flag() {
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

mkdir -p "$OUT"

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
    ffmpeg -hide_banner -loglevel error \
      -ss "$bstart" -to "$bend" -i "$VIDEO" "${VFR[@]}" \
      -vf "fps=${FPS},scale=${FRAMEW}:-1" \
      "$OUT/ts${idx}_%03d.png"
    # Before/after strip from the first and last frame of the burst.
    mapfile -t _f < <(find "$OUT" -maxdepth 1 -type f -name "ts${idx}_[0-9]*.png" | sort)
    if (( ${#_f[@]} >= 2 )); then
      ffmpeg -hide_banner -loglevel error \
        -i "${_f[0]}" -i "${_f[$(( ${#_f[@]} - 1 ))]}" \
        -filter_complex hstack -frames:v 1 \
        "$OUT/ts${idx}_strip.png"
    fi
  done
elif [[ -n "$CONTACT" ]]; then
  # Contact-sheet mode: scale each selected frame down and tile them into a grid, so the
  # whole timeline is one image (or a few). Spills into contact_0002.png, ... if needed.
  echo "Contact-sheet mode [$MODE_DESC], ${COLS}x${ROWS} per sheet -> $OUT" >&2
  ffmpeg -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},scale=${TILEW}:-1,tile=${COLS}x${ROWS}" \
    "$OUT/contact_%04d.png"
elif [[ -n "$SCENE" ]]; then
  echo "Scene-change mode (threshold=$SCENE) -> $OUT" >&2
  ffmpeg -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "$SELECT" \
    "$OUT/scene_%04d.png"
else
  echo "Dense mode (fps=$FPS) -> $OUT" >&2
  ffmpeg -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "$SELECT" \
    "$OUT/frame_%04d.png"
fi

COUNT=$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
echo "Extracted ${COUNT} image(s) to: ${OUT}"
if [[ -n "$CONTACT" ]]; then
  echo "Each contact sheet tiles frames left-to-right, top-to-bottom in time order."
else
  echo "Read them in filename order to reconstruct the timeline."
fi
