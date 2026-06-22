# claude-plugins

My own engineering contributions to the exciting and brand new field of cognitive instructions describing how to do a thing.

> **Version:** 1.0.0-rc.19 · **Site:** [cportka.github.io/claude-plugins](https://cportka.github.io/claude-plugins/) · **License:** [MIT](./LICENSE) · **Changelog:** [CHANGELOG.md](./CHANGELOG.md) · **Roadmap:** [IMPROVEMENTS.md](./IMPROVEMENTS.md)

The **`portka-tools`** [Claude Code](https://code.claude.com) plugin marketplace. Add it
once; plugins then work in your local CLI and in ephemeral web sessions.

## Plugins

| Plugin | Version | What it does |
| :-- | :-- | :-- |
| [`video-bug-analyzer`](./plugins/video-bug-analyzer) | 1.0.0-rc.19 | Diagnose a bug in a screen recording — extract frames (overview contact sheet, scene cuts, or per-timestamp zoom + before/after strips) and reason over them. Strong on persistent visual bugs; honest about flickers, timing, and off-screen state. |
| [`repo-bootstrap`](./plugins/repo-bootstrap) | 1.0.0-rc.1 | Onboard a repo to this marketplace — write/merge `.claude/settings.json` (+ optional CI). |

## Add a plugin

You never copy plugin code into your repo — only a marketplace reference.

- **All local repos (CLI):** `/plugin marketplace add cportka/claude-plugins`, then
  `/plugin install video-bug-analyzer@portka-tools` (or any `<name>@portka-tools`). Persists in `~/.claude`.
- **A specific repo / web session:** commit `.claude/settings.json` (below). Web containers
  start fresh each session, so this committed file is what loads the plugin. Let
  `repo-bootstrap` write it, or add it by hand.

```json
{
  "extraKnownMarketplaces": {
    "portka-tools": { "source": { "source": "github", "repo": "cportka/claude-plugins" } }
  },
  "enabledPlugins": { "video-bug-analyzer@portka-tools": true }
}
```

Generate that with `repo-bootstrap`:

```
plugins/repo-bootstrap/skills/repo-bootstrap/scripts/bootstrap-repo.sh --plugin video-bug-analyzer --ci
```

Onboarding another repo or session? Drop in **[docs/INTEGRATE.md](./docs/INTEGRATE.md)** —
a portable guide with enable steps, verification, and ffmpeg troubleshooting.

## Usage

**video-bug-analyzer** — give Claude a screen recording and roughly when the bug happens; it
runs the `video-bug-analysis` skill. Or extract frames directly:

```
S=plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh
"$S" --video bug.mov --fps 2 --contact            # 1) cheap overview contact sheet
"$S" --video bug.mov --timestamps 0:12,0:34 --fps 8  # 2) zoom + before/after strip per moment
```

Needs `ffmpeg`. The plugin tries to install it (apt → brew → a GitHub static build), **but a
sandbox may block the download or require you to approve it** — see
[docs/INTEGRATE.md](./docs/INTEGRATE.md). If it can't install, give Claude a **still
screenshot** of the bad moment instead — that always works.

**repo-bootstrap** — see [Add a plugin](#add-a-plugin). Flags: `--plugin` (repeatable),
`--marketplace-name`, `--marketplace-repo`, `--ci`, `--dir`, `--force`. Needs `python3`.

## Tests

```
bash tests/run-tests.sh
```

Self-contained: validates manifests, marketplace↔plugin consistency, versions, skill
frontmatter, hooks, script behavior, and the bootstrap scaffolding; ffmpeg/shellcheck steps
run when available, else `SKIP`. Powers the [`validate`](./.github/workflows/validate.yml) CI.

## Feedback

Hit a problem? Open a **Plugin feedback** issue (Issues → New issue → *Plugin feedback*)
with the plugin version, environment, `ffmpeg -version`, command, and error. It's triaged
into a fix and a new version.

## Versioning

[SemVer](https://semver.org) — every PR bumps the version and adds a
[CHANGELOG](./CHANGELOG.md) entry. Known gaps and ideas: [IMPROVEMENTS.md](./IMPROVEMENTS.md).

## License

[MIT](./LICENSE) — free to use, with attribution to Chris Portka preserved.
