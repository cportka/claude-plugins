# claude-plugins

My own engineering contributions to the exciting and brand new field of cognitive instructions describing how to do a thing.

> **Version:** 0.1.0 · **License:** [MIT](./LICENSE) · **Changelog:** [CHANGELOG.md](./CHANGELOG.md)

This is the **`portka-tools`** [Claude Code](https://code.claude.com) plugin marketplace.
Add it once, then install any plugin below in your local CLI or any repo — including
ephemeral Claude Code web sessions where user-global config doesn't persist.

## Plugins

| Plugin | Version | What it does |
| :-- | :-- | :-- |
| [`video-bug-analyzer`](./plugins/video-bug-analyzer) | 0.1.0 | Extract frames from a screen-recording and diagnose the bug shown in it |

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

## Install

### Local Claude Code (CLI)

```
/plugin marketplace add cportka/claude-plugins
/plugin install video-bug-analyzer@portka-tools
```

### Any repo, including Claude Code on the web

Web sessions run in an ephemeral container, so user-level config doesn't persist. Commit
this to the repo's `.claude/settings.json` and the marketplace is fetched from GitHub and
the plugin installed at session start:

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

## Usage

Give Claude a screen recording and an approximate timestamp of the bug. Claude will invoke
the `video-bug-analysis` skill, extract frames, and walk the diagnosis workflow. You can
also extract frames directly:

```
plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video bug.mov --start 0:11 --end 0:14 --fps 8
```

Requires `ffmpeg` (the script installs it automatically where possible).

## Running the tests

Everything in this repo is covered by a single, self-contained test runner. From the repo
root:

```
bash tests/run-tests.sh
```

It validates the JSON manifests, the skill frontmatter, and the extraction script's
syntax and CLI behavior, and — when `ffmpeg`/`shellcheck` are available — runs an
end-to-end frame extraction and lints the scripts. Steps that need a missing tool are
reported as `SKIP` rather than failing, so the suite runs anywhere; CI installs both tools
so they run for real on every push and pull request. The same script powers the
[`validate`](./.github/workflows/validate.yml) GitHub Actions workflow.

## Contributing & versioning

This repo follows [Semantic Versioning](https://semver.org). Every pull request bumps the
version and adds an entry to [CHANGELOG.md](./CHANGELOG.md). Keep this README current with
any plugin or behavior changes in the same PR.

## License

[MIT](./LICENSE) — free to use, modify, and distribute, provided the copyright/attribution
notice for Chris Portka is preserved.
