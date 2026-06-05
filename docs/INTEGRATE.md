# Integrating `claude-plugins` (portka-tools) into a repo

Drop this file into any repo to onboard it — and its Claude Code session — to the
`portka-tools` marketplace at [`cportka/claude-plugins`](https://github.com/cportka/claude-plugins).
You never copy plugin code in; you add a marketplace **reference** and enable the plugins.

## 1. Enable the marketplace

**Option A — let `repo-bootstrap` write it** (if you have the plugin or the repo checked out):

```
plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh --plugin video-bug-analyzer --ci
```

**Option B — by hand.** Create `.claude/settings.json` in the repo root:

```json
{
  "extraKnownMarketplaces": {
    "portka-tools": { "source": { "source": "github", "repo": "cportka/claude-plugins" } }
  },
  "enabledPlugins": { "video-bug-analyzer@portka-tools": true }
}
```

Add more plugins as extra `enabledPlugins` rows (e.g. `"repo-bootstrap@portka-tools": true`).

## 2. Make the session pick it up

- **Commit** `.claude/settings.json` — web/remote sessions clone the repo fresh and only read
  committed config.
- **Claude Code on the web:** start a **new** session (or `/clear`) for the repo. At startup it
  fetches the marketplace, enables the plugins, and the `video-bug-analyzer` SessionStart hook
  pre-installs `ffmpeg` where the network allows.
- **Local CLI:** `/plugin marketplace add cportka/claude-plugins` then
  `/plugin install video-bug-analyzer@portka-tools`. To pull a newer version later:
  `/plugin marketplace update portka-tools`.

A running session won't see the change until it restarts/clears (web) or you re-run the
`/plugin` commands (CLI).

## 3. Use it instead of ad-hoc ffmpeg

Give Claude the screen recording and roughly **when** the bug happens; it runs the
`video-bug-analysis` skill (gather context → extract frames → build a timeline → confirm in
code → report with caveats). Tell the session: *"use the video-bug-analysis skill"* so it
stops hand-rolling ffmpeg. Direct use:

```
plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video bug.mov --start 0:11 --end 0:14 --fps 8
# add --contact for a one-image overview of a span (cheap, then re-extract densely)
```

## 4. Verify

- `.claude/settings.json` is valid JSON with the marketplace + `enabledPlugins` entry.
- `/plugin` lists `video-bug-analyzer@portka-tools` as enabled (CLI).
- Asking Claude to analyze a recording triggers the `video-bug-analysis` skill.
- `extract-frames.sh --help` prints usage; a real run prints an `ffmpeg: ...` version line.

## 5. ffmpeg troubleshooting

| Symptom | Fix |
| :-- | :-- |
| `ffmpeg not found` / install fails | Restricted-network policy blocked the SessionStart install. Install manually: `apt-get install -y ffmpeg` or `brew install ffmpeg`. The script retries on first use. |
| Deprecation warnings / scene mode misbehaves (`-vsync`) | Fixed in `video-bug-analyzer` ≥ 0.2.2 (uses `-fps_mode` on modern ffmpeg). Update: `/plugin marketplace update portka-tools`, or re-fetch the marketplace in a fresh web session. |
| Scene mode writes 0 frames | Lower the threshold (`--scene 0.05`) or switch to dense (`--fps 4`). |
| Too many frames / token blowup | Tighten `--start/--end`, lower `--fps`, or use `--contact` for an overview first. |
| Garbled / partial frames | Note your `ffmpeg -version` (printed at run start) and file feedback (below). |

## 6. Report a problem → drives a new version

If something still breaks, open a **Plugin feedback** issue at
`cportka/claude-plugins` (Issues → New issue → *Plugin feedback*). Include the plugin
version, environment (CLI/web), `ffmpeg -version`, the exact command, and the error output.
That intake is triaged into a fix and a new plugin version.
