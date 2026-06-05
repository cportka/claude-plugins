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

## 2. Commit it, then START A NEW SESSION

This is the step people miss: **`.claude/settings.json` is read only at session start.**
Enabling a plugin mid-session does **not** surface its skill.

1. **Commit** `.claude/settings.json` (web/remote sessions clone the repo fresh).
2. **Start a new session** (web) or `/clear`; on the CLI, run `/plugin marketplace add
   cportka/claude-plugins` then `/plugin install video-bug-analyzer@portka-tools` (update
   later with `/plugin marketplace update portka-tools`).
3. The new session fetches the marketplace, enables the plugin, and the SessionStart hook
   tries to pre-install `ffmpeg`.

## 3. ffmpeg install & permissions — read this

The method needs `ffmpeg`. The plugin tries `apt → brew → a static GitHub build`, **but two
things commonly stop a silent install in a sandbox:**

- **Network allowlist.** `apt`/`johnvansickle` are often blocked; **GitHub release assets
  usually aren't**, which is why the installer now prefers a GitHub build (override with the
  `VBA_FFMPEG_URL` env var).
- **The permission classifier.** Claude Code will **not silently download-and-run an external
  binary** — you must approve it. A settings rule can't fully pre-authorize executing
  downloaded code, so **approve the install when prompted** (one time). You can pre-allow the
  *script* to cut prompts:

  ```json
  { "permissions": { "allow": [
      "Bash(plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh:*)"
  ] } }
  ```

  (The internal binary download may still ask once — that's expected.)

**Simplest path of all:** if ffmpeg won't install, **give Claude a still screenshot of the
exact bad moment.** No ffmpeg, no permissions, works every time. This is a first-class option,
not a last resort.

## 4. Use it instead of ad-hoc ffmpeg

Give Claude the screen recording and roughly **when** the bug happens; tell it *"use the
video-bug-analysis skill"* so it stops hand-rolling ffmpeg. The skill does overview →
zoom → timeline → confirm-in-code → report. Direct use:

```
S=plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh
"$S" --video bug.mov --fps 2 --contact              # overview contact sheet
"$S" --video bug.mov --timestamps 0:12,0:34 --fps 8 # zoom + before/after strip per moment
```

## 5. Verify

- `.claude/settings.json` is valid JSON with the marketplace + `enabledPlugins` entry.
- `/plugin` lists `video-bug-analyzer@portka-tools` as enabled (CLI).
- Asking Claude to analyze a recording triggers the `video-bug-analysis` skill.
- `extract-frames.sh --help` prints usage; a real run prints an `ffmpeg: ...` version line.

## 6. ffmpeg troubleshooting

| Symptom | Fix |
| :-- | :-- |
| `ffmpeg not found` / install blocked | Installer tries `apt → brew → GitHub static build`. If it's **denied for approval**, approve it (§3) or pre-allow the script. If the network is fully locked down, give Claude a **still screenshot** of the bad moment — no ffmpeg needed. |
| Install download keeps getting denied | The classifier won't auto-run a downloaded binary; approve once, or use a screenshot (§3). |
| Deprecation warnings / scene mode misbehaves | Fixed in ≥ 0.2.2 (`-fps_mode` on modern ffmpeg). `/plugin marketplace update portka-tools` or re-fetch in a fresh session. |
| Scene mode writes 0 frames | Lower the threshold (`--scene 0.05`) or go dense (`--fps 4`). |
| Too many frames / token blowup | Use `--fps 2 --contact` for the overview, then `--timestamps` to zoom. |

## 7. Report a problem → drives a new version

If something still breaks, open a **Plugin feedback** issue at
`cportka/claude-plugins` (Issues → New issue → *Plugin feedback*). Include the plugin
version, environment (CLI/web), `ffmpeg -version`, the exact command, and the error output.
That intake is triaged into a fix and a new plugin version.
