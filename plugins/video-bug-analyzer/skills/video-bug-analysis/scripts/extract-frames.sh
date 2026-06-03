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
#                     [--scene <thr>] [--out <dir>]
#
# Options:
#   --video <path>   Input video file (required).
#   --start <ts>     Start time (e.g. 12, 0:12, 00:00:12.5). Default: start of clip.
#   --end <ts>       End time. Default: end of clip.
#   --fps <n>        Frames per second to sample in dense mode. Default: 4.
#   --scene <thr>    Scene-change mode: capture frames where the scene score exceeds
#                    <thr> (e.g. 0.1). Overrides --fps. Good for an unknown moment.
#   --out <dir>      Output directory for PNG frames. Default: ./.frames
#   -h, --help       Show this help.
#
# Examples:
#   extract-frames.sh --video bug.mov --start 0:11 --end 0:14 --fps 8
#   extract-frames.sh --video bug.mov --scene 0.1
#
set -euo pipefail

VIDEO=""
START=""
END=""
FPS="4"
SCENE=""
OUT="./.frames"

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --start) START="${2:-}"; shift 2 ;;
    --end)   END="${2:-}";   shift 2 ;;
    --fps)   FPS="${2:-}";   shift 2 ;;
    --scene) SCENE="${2:-}"; shift 2 ;;
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
  cat >&2 <<'EOF'
Error: ffmpeg is required but could not be installed automatically.
Install it and re-run:
  - Debian/Ubuntu: sudo apt-get install -y ffmpeg
  - macOS (Homebrew): brew install ffmpeg
  - Other: https://ffmpeg.org/download.html
(If this is a sandboxed/web session, network access may be restricted by policy.)
EOF
  return 1
}

ensure_ffmpeg

mkdir -p "$OUT"

# Build the leading seek/duration args (apply -ss/-to before -i for speed/accuracy).
PRE_ARGS=()
[[ -n "$START" ]] && PRE_ARGS+=(-ss "$START")
[[ -n "$END"   ]] && PRE_ARGS+=(-to "$END")

if [[ -n "$SCENE" ]]; then
  echo "Scene-change mode (threshold=$SCENE) -> $OUT" >&2
  ffmpeg -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "select='gt(scene,${SCENE})'" -vsync vfr \
    "$OUT/scene_%04d.png"
else
  echo "Dense mode (fps=$FPS) -> $OUT" >&2
  ffmpeg -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "fps=${FPS}" \
    "$OUT/frame_%04d.png"
fi

COUNT=$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
echo "Extracted ${COUNT} frame(s) to: ${OUT}"
echo "Read them in filename order to reconstruct the timeline."
