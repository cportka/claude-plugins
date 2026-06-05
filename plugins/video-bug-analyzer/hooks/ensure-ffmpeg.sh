#!/usr/bin/env bash
#
# ensure-ffmpeg.sh — SessionStart hook for the video-bug-analyzer plugin.
#
# CHANGED: fast install only. Tries the package manager (apt/brew) and a cached static
# build, but does NOT attempt the slow static download here — under the hook's 120s timeout
# that download gets killed mid-flight (it neither installs ffmpeg nor reaches the warning
# below). extract-frames.sh owns the static download on first use, with no 120s cap.
# Idempotent and non-blocking: never fails the session. If ffmpeg isn't installed at
# startup, it tells the model via additionalContext so the limitation is known up front.
#
set -uo pipefail

# Cache dir for a downloaded static ffmpeg; shared with extract-frames.sh, which adds this
# to PATH on use — so a build installed here is found even if it's not on the session PATH.
FFMPEG_CACHE="${HOME:-/tmp}/.cache/portka-video-bug-analyzer/bin"

# REMOVED: the static-download helper lived here. The slow download moved entirely to
# extract-frames.sh (called on first use, no 120s cap). The hook only does fast installs.

# Already present, or a static build cached by a prior extract-frames.sh run? Done.
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

# CHANGED: no static download here (it would be killed by the hook's 120s timeout). The
# package manager couldn't install ffmpeg, so surface the fallback immediately and let the
# session continue — extract-frames.sh attempts the static build (uncapped) on first use.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"video-bug-analyzer: ffmpeg was not installed at session start (no package manager, or it's blocked). extract-frames.sh will try a static build from GitHub on first use; if that's also blocked, ask the user for a still screenshot of the exact bad moment instead of video frames."}}
JSON
exit 0
