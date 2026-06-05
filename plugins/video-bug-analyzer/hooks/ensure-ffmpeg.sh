#!/usr/bin/env bash
#
# ensure-ffmpeg.sh — SessionStart hook for the video-bug-analyzer plugin.
#
# Best-effort pre-install of ffmpeg so the video-bug-analysis workflow is ready the moment
# it's needed — instead of pausing to install (and possibly hitting a restricted-network
# wall) in the middle of a diagnosis. Idempotent and non-blocking: it never fails the
# session. If ffmpeg can't be installed, it tells the model via additionalContext so the
# limitation is known up front.
#
set -uo pipefail

# Cache dir for a downloaded static ffmpeg; shared with extract-frames.sh, which adds this
# to PATH on use — so a build installed here is found even if it's not on the session PATH.
FFMPEG_CACHE="${HOME:-/tmp}/.cache/portka-video-bug-analyzer/bin"

# Best-effort static ffmpeg download (no root/apt). Tries GitHub release assets first
# (reachable in many sandboxes), then johnvansickle. Override with $VBA_FFMPEG_URL.
# Returns non-zero if it can't.
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

if command -v ffmpeg >/dev/null 2>&1 || [[ -x "$FFMPEG_CACHE/ffmpeg" ]]; then
  exit 0
fi

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
  exit 0
fi

# Package manager unavailable/blocked — try a static build into the shared cache.
install_ffmpeg_static && exit 0

# Could not install (likely a restricted-network policy). Surface it as context but let
# the session continue; extract-frames.sh will retry on first use.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"video-bug-analyzer: ffmpeg is not installed and could not be auto-installed at session start (apt/brew and a static download all failed — outbound network is likely restricted by policy). extract-frames.sh will retry on first use; if it still fails, ask the user for a still screenshot of the exact bad moment instead of video frames."}}
JSON
exit 0
