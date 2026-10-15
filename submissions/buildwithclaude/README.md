# buildwithclaude submission — `video-bug-analysis`

Staging kit for listing the **video-bug-analysis** skill on
[buildwithclaude](https://github.com/davepoon/buildwithclaude) (the community component directory
at buildwithclaude.com). The canonical home stays this repo (`cportka/claude-plugins`,
`portka-tools` marketplace) — the listing points back to it.

We submit **only this one skill for now**; the others (`app-evaluation`, `repo-bootstrap`) can be
added later the same way.

## How to submit

1. **Fork** https://github.com/davepoon/buildwithclaude and clone your fork locally.
2. From *this* repo, stage the skill into your fork:
   ```
   submissions/buildwithclaude/prepare.sh /path/to/your/buildwithclaude-fork
   ```
   It copies `SKILL.md` + `reference.md` + `scripts/` to
   `plugins/all-skills/skills/video-bug-analysis/` and drops the source-pointing
   [`plugin.json`](./plugin.json) (repository/homepage/author → `cportka/claude-plugins`).
3. Follow the printed steps: branch `add-video-bug-analysis-skill`, commit, `npm test`, push, and
   open a PR titled **"Add video-bug-analysis skill"**. In the PR body, note the canonical source
   (`cportka/claude-plugins`), MIT license, author Chris Portka.

## Notes
- The skill is self-contained: it needs `ffmpeg`/`ffprobe` on PATH and never installs them on its
  own — `extract-frames.sh` says what's missing and honors the explicit `VBA_ALLOW_INSTALL=1` opt-in
  — so it works in the directory without this repo's SessionStart hook.
- Keep `plugin.json` here in sync with `plugins/video-bug-analyzer/.claude-plugin/plugin.json`
  (description/keywords when they change; the `version` always — the suite enforces it). This copy
  adds the explicit "canonical source" line.
- If buildwithclaude's layout has changed since this was written, place the skill folder wherever
  their current CONTRIBUTING.md says skills go — the SKILL.md + scripts are what matter.
