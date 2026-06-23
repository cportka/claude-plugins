#!/usr/bin/env bash
#
# prepare.sh — stage the `video-bug-analysis` skill into a buildwithclaude fork for submission.
#
# buildwithclaude (https://github.com/davepoon/buildwithclaude) is a community directory that
# expects skills at  plugins/all-skills/skills/<skill-name>/SKILL.md , with a per-component
# .claude-plugin/plugin.json. This copies the canonical skill (SKILL.md + reference.md + scripts)
# out of this repo into your fork, plus the source-pointing plugin.json next to it, then prints
# the branch/commit/PR steps. The skill stays self-contained: extract-frames.sh installs ffmpeg
# on first use, so it works in the directory without our SessionStart hook.
#
# Usage:
#   submissions/buildwithclaude/prepare.sh <path-to-your-buildwithclaude-fork>
#
set -euo pipefail

FORK="${1:-}"
if [[ -z "$FORK" || ! -d "$FORK" ]]; then
  echo "Usage: $0 <path-to-your-buildwithclaude-fork>" >&2
  echo "  (clone/fork https://github.com/davepoon/buildwithclaude first, then pass its path)" >&2
  exit 2
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SRC="$REPO_ROOT/plugins/video-bug-analyzer/skills/video-bug-analysis"
[[ -f "$SRC/SKILL.md" ]] || { echo "Error: skill source not found at $SRC" >&2; exit 1; }

DEST="$FORK/plugins/all-skills/skills/video-bug-analysis"
echo "Staging video-bug-analysis -> $DEST"
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"                                  # SKILL.md, reference.md, scripts/
mkdir -p "$DEST/.claude-plugin"
cp "$SELF_DIR/plugin.json" "$DEST/.claude-plugin/plugin.json"   # source-pointing manifest
chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true

cat <<EOF

Staged. The submission tree (under your fork):
  plugins/all-skills/skills/video-bug-analysis/
    SKILL.md  reference.md  scripts/  .claude-plugin/plugin.json

Next steps (in the fork), per buildwithclaude CONTRIBUTING.md:
  cd "$FORK"
  git checkout -b add-video-bug-analysis-skill
  git add plugins/all-skills/skills/video-bug-analysis
  git commit -m "Add video-bug-analysis skill"
  npm test           # run their validation before submitting
  git push -u origin add-video-bug-analysis-skill
  # then open a PR titled: "Add video-bug-analysis skill"
  # PR body: note the canonical source is cportka/claude-plugins (portka-tools), MIT, by Chris Portka.

If their structure differs from plugins/all-skills/skills/<name>/, move the folder to match what
you see in the fork — the skill itself (SKILL.md + scripts) is what matters.
EOF
