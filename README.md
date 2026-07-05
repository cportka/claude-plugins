# claude-plugins

My own engineering contributions to the exciting and brand new field of cognitive instructions describing how to do a thing.

> **Version:** 1.4.0 · **Site:** [cportka.github.io/claude-plugins](https://cportka.github.io/claude-plugins/) · **License:** [MIT](./LICENSE) · **Changelog:** [CHANGELOG.md](./CHANGELOG.md) · **Roadmap:** [IMPROVEMENTS.md](./IMPROVEMENTS.md)

The **`portka-tools`** [Claude Code](https://code.claude.com) plugin marketplace. Add it
once; plugins then work in your local CLI and in ephemeral web sessions.

## Plugins

| Plugin | Version | What it does |
| :-- | :-- | :-- |
| [`video-bug-analyzer`](./plugins/video-bug-analyzer) | 1.4.0 | Analyze a screen recording — extract frames (contact sheet, scene cuts, per-timestamp zoom + before/after strips, ROI time-stack `--stack`) and reason over them, plus analysis modes: black-screen detection, ROI OCR, feature measurement, palettes, cross-clip diff/compare, stutter / dropped-frame + freeze gaps (`--stutter`), frame-pacing jitter (`--pacing`), motion, swirl-vs-suck flow (`--flow`), subject extent (`--occupancy`) & saturation timelines. Runs never overwrite a previous extraction; `--check-update` spots a stale install. |
| [`repo-bootstrap`](./plugins/repo-bootstrap) | 1.2.0 | Onboard a repo to this marketplace — safely merge `.claude/settings.json` (+ optional CI), with `--list`/`--dry-run`/`--print-only` and a one-paste `/plugin` CLI fallback. With `--portka-standard`, also install the Portka standard: a workflow `CLAUDE.md`, a git/`gh` permissions allowlist, and an enforced SemVer version sync bound to the repo's existing version + a basic test suite (and a native `node:test`/`unittest` version-sync test for JS/Python repos). |
| [`app-website-evaluator`](./plugins/app-website-evaluator) | 1.3.1 | Evaluate an app/website with a standardized, coverage-honest scorecard — each dimension 0–100 + letter grade, a weighted overall that's **starred** when unassessed weight is excluded (e.g. Security in dir mode), and optional `--json`. AI-readiness parse-validates JSON-LD and credits rich schema types. Covers SEO, crawlability, AI-readiness, social/sharing, security, performance, and growth — tailored to the site's type and community. |
| [`tab-chord-formatter`](./plugins/tab-chord-formatter) | 1.2.0 | Format a messy guitar tab/chord sheet into a clean, readable layout for screen, or render a consistent monospace **PDF songbook** (one or many songs, a target songs-per-page) — standardized `[Section]` labels, chords aligned over the right lyrics, a tidy metadata header, and well-formed 6-line ASCII tab blocks. |

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
runs the `video-bug-analysis` skill (invoke explicitly with
`Skill(skill="video-bug-analyzer:video-bug-analysis")`). Or extract frames directly:

```
S=plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh
"$S" --video bug.mov --fps 2 --contact            # 1) cheap overview contact sheet
"$S" --video bug.mov --timestamps 0:12,0:34 --fps 8  # 2) zoom + before/after strip per moment
```

Needs `ffmpeg`. The plugin tries to install it (apt → brew → a GitHub static build), **but a
sandbox may block the download or require you to approve it** — see
[docs/INTEGRATE.md](./docs/INTEGRATE.md). If it can't install, give Claude a **still
screenshot** of the bad moment instead — that always works.

Beyond the two core modes, `extract-frames.sh` has focused analysis modes — `--blackdetect`,
`--ocr-roi`, `--measure`, `--probe`, `--palette`, `--ab`/`--compare-videos`,
`--cadence`/`--stutter` (FPS stutter, dropped frames + freeze gaps), `--motion`, `--saturation`,
and the `--intro` load-bug preset — each documented in `--help` and the skill's `reference.md`.

> **Not installed (web/headless/CI)?** Plugins load at session start, so if the skill isn't in
> the registry yet, the script is fully standalone — the repo is public, so an agent can fetch and
> run just `extract-frames.sh` (it self-installs ffmpeg and reports its own version):
> ```
> curl -fsSL https://raw.githubusercontent.com/cportka/claude-plugins/main/plugins/video-bug-analyzer/skills/video-bug-analysis/scripts/extract-frames.sh -o /tmp/extract-frames.sh
> bash /tmp/extract-frames.sh --video bug.mov --intro     # or add --dry-run to just print the commands
> ```

**app-website-evaluator** — ask Claude to audit a site/app; it runs the `app-evaluation` skill
(classify → gather evidence → prioritized report). Or run the checker directly:

```
E=plugins/app-website-evaluator/skills/app-evaluation/scripts/evaluate-site.sh
"$E" --url https://example.com     # live: crawlability, SEO, social, security headers, …
"$E" --dir ./dist                  # a local build (no network)
```

**tab-chord-formatter** — paste or link a messy guitar tab / chord sheet and ask Claude to clean
it up; it runs the `tab-formatting` skill (normalize → re-align chords → output standard plain
text). Or run the deterministic normalizer directly:

```
F=plugins/tab-chord-formatter/skills/tab-formatting/scripts/format-tab.py
"$F" messy-tab.txt        # decode HTML/entities, standardize [Section]s, tidy whitespace
cat messy-tab.txt | "$F"  # or from stdin
```

The script does only the safe mechanical cleanup (it never touches a line's internal alignment);
the skill does the judgment — re-aligning chords over the right syllables and inferring structure.
Needs `python3`.

**repo-bootstrap** — see [Add a plugin](#add-a-plugin). Flags: `--plugin` (repeatable),
`--marketplace-name`, `--marketplace-repo`, `--ci`, `--dir`, `--force`, `--list`, `--dry-run`,
`--print-only` (print the files for a classifier-safe manual write — see [Updating](#updating)),
`--auto-update` (sets `autoUpdate` on the marketplace — see [Updating](#updating) for the caveat),
`--portka-standard` (install the Portka standard: a workflow `CLAUDE.md` + a git/`gh` permissions
allowlist + an enforced SemVer version sync that binds to the repo's existing version, with a basic
test suite + CI), `--scope` (`user`|`project`|`both`, default `both`), `--home`. Needs `python3`.

## Tests

```
bash tests/run-tests.sh
```

Self-contained: validates manifests, marketplace↔plugin consistency, versions, skill
frontmatter, hooks, script behavior, and the bootstrap scaffolding; ffmpeg/shellcheck steps
run when available, else `SKIP`. Powers the [`validate`](./.github/workflows/validate.yml) CI.

## Updating

Plugins are pinned by `version`, so after a new release you need to pull it in:

- **Per plugin:** `claude plugin update <name>@portka-tools`, then `/reload-plugins` (or start a
  new session). This is the **reliable** path — use it when a fix has shipped.
- **Auto-update (per marketplace):** toggle it in `/plugin` → *Marketplaces* → `portka-tools` →
  *Enable auto-update*, or have `repo-bootstrap` write it with `--auto-update`. **Caveat:** as of
  mid-2026, auto-update on a *third-party* marketplace is reported to refresh the catalog but
  **not re-install plugin code** ([anthropics/claude-code#61854](https://github.com/anthropics/claude-code/issues/61854)) — so `claude plugin update` is still the dependable move.
- **For a whole repo/team:** commit a project-scope `.claude/settings.json` (let `repo-bootstrap`
  write it, optionally `--auto-update`) so collaborators pick up the marketplace.
- **Kill switches:** `DISABLE_AUTOUPDATER` (disable all auto-update); `FORCE_AUTOUPDATE_PLUGINS=1`
  (update plugins while freezing the CLI). Re-verify settings against
  [the docs](https://code.claude.com/docs/en/settings) before relying on them.

## Feedback

Hit a problem? Open a **Plugin feedback** issue (Issues → New issue → *Plugin feedback*)
with the plugin version, environment, `ffmpeg -version`, command, and error. It's triaged
into a fix and a new version.

## Versioning

[SemVer](https://semver.org) — every PR bumps the version and adds a
[CHANGELOG](./CHANGELOG.md) entry. Known gaps and ideas: [IMPROVEMENTS.md](./IMPROVEMENTS.md).
Cutting a release or submitting the marketplace: [RELEASING.md](./RELEASING.md).

## License

[MIT](./LICENSE) — free to use, with attribution to Chris Portka preserved.
