# claude-plugins

My own engineering contributions to the exciting and brand new field of cognitive instructions describing how to do a thing.

> **Version:** 0.3.0 · **License:** [MIT](./LICENSE) · **Changelog:** [CHANGELOG.md](./CHANGELOG.md)

This is the **`portka-tools`** [Claude Code](https://code.claude.com) plugin marketplace.
Add it once, then install any plugin below in your local CLI or any repo — including
ephemeral Claude Code web sessions where user-global config doesn't persist.

## Plugins

| Plugin | Version | What it does |
| :-- | :-- | :-- |
| [`video-bug-analyzer`](./plugins/video-bug-analyzer) | 0.2.0 | Extract frames from a screen-recording and diagnose the bug shown in it |
| [`repo-bootstrap`](./plugins/repo-bootstrap) | 0.1.0 | Set up a repo to use portka-tools plugins (writes `.claude/settings.json` + optional CI) |

### `video-bug-analyzer`

Analyze **screen-recording videos of bugs** by extracting frames and diagnosing the issue.

Claude can't watch video — it only ever sees still frames pulled out by `ffmpeg`. This
plugin makes that workflow **reliable and repeatable**: it captures frames densely around
the moment a bug occurs (or at scene changes when the moment is unknown), reconstructs a
timeline, cross-references the actual code, and reports findings **with explicit
confidence and honest caveats** about what frames can and can't reveal.

**What it's good at:** persistent visual bugs — broken layout, missing elements, wrong
text, visible error messages/modals.
**What it's weak at:** transient flickers, timing/race conditions, subtle pixel-level
diffs, and anything off-screen (console/network). The skill says so out loud rather than
guessing.

### `repo-bootstrap`

Onboard a repository to this marketplace. It writes (or safely merges into) a repo's
`.claude/settings.json` so the `portka-tools` marketplace is known and the plugins you pick
are enabled — which is what makes them load in **Claude Code web sessions**, where a
user-level install doesn't persist. It can also drop a `validate` CI workflow. See
[Adding a plugin to a repo or session](#adding-a-plugin-to-a-repo-or-session) below.

## Adding a plugin to a repo or session

There are three ways to use a `portka-tools` plugin, depending on where you need it. **You
never copy plugin code into your repo** — the plugin lives here in the marketplace; you
only add a marketplace reference and enable the plugin.

### 1. Across all your local repos (Claude Code CLI)

Run once in the local CLI. It installs to your user scope (`~/.claude`) and is then
available in every local repo on that machine — no per-repo files:

```
/plugin marketplace add cportka/claude-plugins
/plugin install video-bug-analyzer@portka-tools
```

Manage installs anytime with `/plugin`.

### 2. In a specific repo, including Claude Code on the web

Web/remote sessions run in a fresh, ephemeral container, so `~/.claude` is gone each
session. The durable mechanism is a **committed `.claude/settings.json`** that declares the
marketplace and enables the plugins; Claude Code reads it at session start.

**Easiest — let `repo-bootstrap` write it for you.** With `repo-bootstrap` enabled (or run
the script directly), from the repo root:

```
plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
  --plugin video-bug-analyzer --ci
```

That creates/merges `.claude/settings.json` (and, with `--ci`, a `validate` workflow).
Then commit it.

**Or add it by hand** — create `.claude/settings.json` in the repo with:

```json
{
  "extraKnownMarketplaces": {
    "portka-tools": {
      "source": { "source": "github", "repo": "cportka/claude-plugins" }
    }
  },
  "enabledPlugins": {
    "video-bug-analyzer@portka-tools": true
  }
}
```

Enable more plugins by adding rows under `enabledPlugins` (e.g.
`"repo-bootstrap@portka-tools": true`). **Commit the file** — it only takes effect once it's
in the repo, because web sessions clone it fresh.

### 3. One-off in the current CLI session

Just add the marketplace and install for this session:

```
/plugin marketplace add cportka/claude-plugins
/plugin install <name>@portka-tools
```

## Usage

### `video-bug-analyzer`

Give Claude a screen recording and an approximate timestamp of the bug. Claude will invoke
the `video-bug-analysis` skill, extract frames, and walk the diagnosis workflow. You can
also extract frames directly:

```
plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video bug.mov --start 0:11 --end 0:14 --fps 8
```

Add `--contact` to tile the sampled frames into a single **contact-sheet** image — a
cheap, one-file overview of a span to find the symptom region before extracting it densely:

```
plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video bug.mov --start 0:08 --end 0:16 --fps 3 --contact
```

Requires `ffmpeg`. A bundled **SessionStart hook** pre-installs it where possible, and the
extraction script also installs it on first use as a fallback.

### `repo-bootstrap`

Ask Claude to "set this repo up to use the video-bug-analyzer plugin," or run the script
directly to write/merge `.claude/settings.json` (and optionally a CI workflow):

```
plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
  --plugin video-bug-analyzer --ci
```

Flags: `--plugin <name>` (repeatable), `--marketplace-name`, `--marketplace-repo`, `--ci`,
`--dir <repo-root>`, `--force`. It merges into existing settings without clobbering other
keys and is safe to re-run. Requires `python3`. Then commit `.claude/settings.json`.

## Running the tests

Everything in this repo is covered by a single, self-contained test runner. From the repo
root:

```
bash tests/run-tests.sh
```

It validates the JSON manifests, the skill frontmatter, plugin hooks, and each script's
syntax and CLI behavior; runs the `repo-bootstrap` scaffolding end-to-end (asserting it
writes valid, merge-safe settings); and — when `ffmpeg`/`shellcheck` are available — runs
an end-to-end frame extraction and lints the scripts. Steps that need a missing tool are
reported as `SKIP` rather than failing, so the suite runs anywhere; CI installs those tools
so they run for real on every push and pull request. The same script powers the
[`validate`](./.github/workflows/validate.yml) GitHub Actions workflow.

## Contributing & versioning

This repo follows [Semantic Versioning](https://semver.org). Every pull request bumps the
version and adds an entry to [CHANGELOG.md](./CHANGELOG.md). Keep this README current with
any plugin or behavior changes in the same PR.

## License

[MIT](./LICENSE) — free to use, modify, and distribute, provided the copyright/attribution
notice for Chris Portka is preserved.
