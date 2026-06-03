# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

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

[0.3.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.3.0
[0.2.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.2.0
[0.1.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.1.0
