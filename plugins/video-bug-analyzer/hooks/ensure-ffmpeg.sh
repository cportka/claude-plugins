#!/usr/bin/env bash
#
# ensure-ffmpeg.sh — SessionStart hook for the video-bug-analyzer plugin.
#
# CONSENT MODEL (1.15.0): this hook DETECTS and REPORTS. It installs nothing, runs no `sudo`,
# downloads nothing, and writes nothing outside the plugin's own cache — a SessionStart hook runs
# unattended at every session start, so privilege escalation here can never be consented to.
# (Through 1.14.1 it ran `sudo apt-get install -y ffmpeg` automatically; a marketplace reviewer
# reads that as "the plugin escalates privileges without asking", and they're right.)
#
# What it does instead: report whether ffmpeg/ffprobe are available, so the model knows the
# limitation up front, and name the one-line opt-in that extract-frames.sh honors when the user
# actually asks for video work.
set -uo pipefail

# Cache dir for a user-approved static build; shared with extract-frames.sh, which adds it to
# PATH on use — so an approved build is found even when it isn't on the session PATH.
FFMPEG_CACHE="${HOME:-/tmp}/.cache/portka-video-bug-analyzer/bin"

_have() { command -v "$1" >/dev/null 2>&1 || [[ -x "$FFMPEG_CACHE/$1" ]]; }

_ffmpeg_ok=""; _ffprobe_ok=""
_have ffmpeg  && _ffmpeg_ok=1
_have ffprobe && _ffprobe_ok=1

# Both present: nothing to say.
if [[ -n "$_ffmpeg_ok" && -n "$_ffprobe_ok" ]]; then
  exit 0
fi

# ffmpeg without ffprobe is a real and confusing state (#120): an npm/static ffmpeg-only PATH
# passes a `command -v ffmpeg` check, then --probe/--list-scenes/--pacing/--stutter and the
# duration lookups all fail. Name it specifically rather than reporting "ffmpeg missing".
if [[ -n "$_ffmpeg_ok" && -z "$_ffprobe_ok" ]]; then
  _msg="video-bug-analyzer: ffmpeg is available but ffprobe is NOT (an ffmpeg-only PATH, e.g. npm ffmpeg-static). Frame extraction works; the modes that need ffprobe (--probe, --list-scenes, --pacing, --stutter, --compare-videos, duration/orientation lookups) will error. Fix with a package that ships both: 'sudo apt-get install -y ffmpeg' or 'brew install ffmpeg'."
else
  _msg="video-bug-analyzer: ffmpeg is not installed in this session, so frame extraction is unavailable until it is. This plugin does NOT install it automatically (no unattended sudo). To proceed, either run one of these yourself — 'sudo apt-get install -y ffmpeg' / 'brew install ffmpeg' — or re-run the extractor with the explicit opt-in 'VBA_ALLOW_INSTALL=1' (add VBA_ALLOW_DOWNLOAD=1 to also permit a checksum-verified static build when no package manager is available). Simplest alternative: ask the user for a still screenshot of the exact bad moment."
fi

# JSON-encode via python3 when available (a quoted message must not break the envelope); the
# messages above are plain ASCII with no quotes, so the literal fallback is safe.
if command -v python3 >/dev/null 2>&1; then
  MSG="$_msg" python3 -c '
import json, os
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": os.environ["MSG"]}}))'
else
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$_msg"
fi
exit 0
