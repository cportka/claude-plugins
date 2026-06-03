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

if command -v ffmpeg >/dev/null 2>&1; then
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

# Could not install (likely a restricted-network policy). Surface it as context but let
# the session continue; extract-frames.sh will retry on first use.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"video-bug-analyzer: ffmpeg is not installed and could not be auto-installed at session start (network policy may be restricting package installs). extract-frames.sh will retry on first use; if it still fails, ask the user for still screenshots of the bug instead of frames."}}
JSON
exit 0
