# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

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

[0.1.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.1.0
