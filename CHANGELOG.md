# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

## [0.5.0] - 2026-06-05

Driven by a first-user report: the method works well; getting ffmpeg installed is the whole
ballgame in sandboxes.

### Added
- `video-bug-analyzer` 0.3.0 **`--timestamps`** mode: for each moment, extract a dense burst
  over a `--window` plus a **before/after strip** (`hstack` of the first & last frame) — the
  by-hand "show the transient" workflow, now built in. New `--window` and `--frame-width`
  (default 820px, keeps text legible) flags.

### Changed
- Installer now tries a **GitHub static build** (BtbN/FFmpeg-Builds, pinned `n7.1`) before
  johnvansickle, since GitHub release assets are reachable in many sandboxes where apt and
  other hosts are blocked. Override with `$VBA_FFMPEG_URL`. Applies to `extract-frames.sh`
  and the SessionStart hook.
- Skill + docs make the **still-screenshot fallback first-class** (not a last resort) and
  make **"commit `.claude/settings.json`, then start a NEW session"** the loud first step.
- `docs/INTEGRATE.md` documents the permission reality: a downloaded binary can't be silently
  self-installed — the user must approve it (with the exact `permissions.allow` rule shown).

## [0.4.1] - 2026-06-05

### Fixed
- `video-bug-analyzer` 0.2.3: when `apt`/`brew` are unavailable or blocked, `extract-frames.sh`
  and the SessionStart hook now fall back to downloading a **static ffmpeg build** (arch-
  detected) into a shared cache and adding it to PATH — addresses sessions where ffmpeg
  simply isn't installed and the package manager can't run. If that also fails (fully
  offline), the give-up message points to a still screenshot. A `find | head` pipe in the
  installer was replaced with `-print -quit` to avoid a `pipefail`/SIGPIPE edge under
  `set -e`.

## [0.4.0] - 2026-06-05

### Fixed
- `video-bug-analyzer` 0.2.2: `extract-frames.sh` now uses `-fps_mode vfr` on modern ffmpeg
  (≥5.1) instead of the deprecated `-vsync vfr`, falling back to `-vsync` on older builds —
  fixes deprecation warnings and scene/contact-mode misbehavior on recent ffmpeg. Also
  prints the ffmpeg version at startup to aid troubleshooting.

### Added
- `docs/INTEGRATE.md`: portable drop-in guide for adopting the marketplace in another repo
  or session (enable steps, verification, ffmpeg troubleshooting).
- GitHub issue form `.github/ISSUE_TEMPLATE/plugin-feedback.yml` (+ `config.yml`) to collect
  structured feedback that drives new versions.
- Tests: validate any `.github/ISSUE_TEMPLATE/*.yml` is non-empty with `name:`/`description:`.

## [0.3.1] - 2026-06-03

Polish only — no behavior changes.

### Changed
- Trimmed the `video-bug-analysis` and `repo-bootstrap` skill docs (and `reference.md`) for
  lower token use while keeping every caveat and instruction exact.
- Rewrote the README far more concisely (kept all essential guidance).
- Bumped `video-bug-analyzer` to 0.2.1 and `repo-bootstrap` to 0.1.1 (doc-only).

### Added
- `IMPROVEMENTS.md`: pros / cons / weaknesses and improvement ideas per plugin and for the
  tests, kept out of the skills to keep in-context instructions lean.
- Tests: marketplace↔plugin consistency (no orphans, name matches dir + entry), semver check
  on each `plugin.json`, and a README version-sync check.

## [0.3.0] - 2026-06-03

### Added
- New **`repo-bootstrap`** plugin (v0.1.0): a `repo-bootstrap` skill plus
  `bootstrap-repo.sh`, which writes/merges a repo's `.claude/settings.json` to enable
  `portka-tools` plugins (so they load in ephemeral Claude Code web sessions) and can add a
  `validate` CI workflow. JSON merges are non-clobbering and idempotent.
- Always-on end-to-end tests for `repo-bootstrap` (settings scaffolding, `--ci` workflow,
  merge-safety) — these run even without ffmpeg.

### Changed
- README: explicit "Adding a plugin to a repo or session" instructions covering local CLI,
  a specific repo / web session (via `repo-bootstrap` or by hand), and one-off session use;
  added the `repo-bootstrap` plugin and usage sections; bumped to repo v0.3.0.

## [0.2.0] - 2026-06-03

### Added
- `video-bug-analyzer` **contact-sheet mode** (`--contact`, with `--cols`/`--rows`/
  `--tile-width`): tiles sampled frames into a single image so a whole span can be read in
  one file with far fewer tokens, then re-extracted densely on the symptom region.
- `video-bug-analyzer` **SessionStart hook** (`hooks/hooks.json` + `hooks/ensure-ffmpeg.sh`)
  that best-effort pre-installs ffmpeg at session start; idempotent and non-blocking, and
  reports via `additionalContext` when a restricted network prevents installation.
- Test coverage for the new hook (JSON + script lint) and contact-sheet extraction.

### Changed
- Bumped `video-bug-analyzer` to 0.2.0; updated SKILL.md, reference.md, and README to
  document contact-sheet mode and the ffmpeg hook.

## [0.1.0] - 2026-06-03

### Added
- Initial `portka-tools` marketplace (`.claude-plugin/marketplace.json`).
- `video-bug-analyzer` plugin (v0.1.0) with the `video-bug-analysis` skill: workflow,
  `reference.md` reliability matrix, and the `extract-frames.sh` extraction script.
- MIT `LICENSE` (© 2026 Chris Portka).
- Fleshed-out `README.md` with install, usage, plugin table, and test instructions.
- Self-contained test runner `tests/run-tests.sh` covering manifest validation, skill
  frontmatter, script syntax/CLI behavior, shellcheck, and end-to-end ffmpeg extraction.
- `validate` GitHub Actions workflow that runs the test runner with `ffmpeg` and
  `shellcheck` installed.

[0.5.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.5.0
[0.4.1]: https://github.com/cportka/claude-plugins/releases/tag/v0.4.1
[0.4.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.4.0
[0.3.1]: https://github.com/cportka/claude-plugins/releases/tag/v0.3.1
[0.3.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.3.0
[0.2.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.2.0
[0.1.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.1.0
