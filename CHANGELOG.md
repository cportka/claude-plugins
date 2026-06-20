# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

## [1.0.0-rc.9] - 2026-06-20

From an FPS-stamped perf-recording dogfood on the Claude.ai web app (#23), where the tester
hand-cropped the on-screen HUD and zoomed it to read FPS/res per second — "the fastest path
to the diagnosis." `video-bug-analyzer` → 1.0.0-rc.9.

### Added
- **`--crop W:H:X:Y`** crops a region (ffmpeg geometry) *before* scaling, so a small UI area —
  an on-screen FPS/HUD readout, a counter, a tiny status label — is zoomed to fill the frame
  and becomes legible while tokens stay low. Works in every mode (dense/scene/contact/diff/
  timestamps); `iw`/`ih` expressions are allowed (e.g. `--crop iw/4:ih/4:0:0`). Documented in
  `--help`, SKILL.md, and reference.md, with crop e2e + dry-run + help-doc tests.

### Notes
- Already shipped in earlier RCs (the tester was on rc.7): the end-of-run pre-filled feedback
  link (rc.7), the `repo-bootstrap` `/plugin …` one-paste CLI fallback (rc.7), and scene-cut
  detection via `--list-scenes`/`--scene` (rc.6).
- Deferred to IMPROVEMENTS as future ideas: OCR of an on-screen HUD into an FPS-over-time CSV,
  and an automatic stutter/cadence metric. The session-start hot-load gap is a Claude Code
  architecture limit (mitigated by `--dry-run` + "enable one session ahead").

## [1.0.0-rc.8] - 2026-06-20

From a `git clone` dogfood on the Claude.ai web app (#21). `video-bug-analyzer` → 1.0.0-rc.8.

### Fixed
- **Flaky help-doc tests:** `tests/run-tests.sh` piped `--help` into `grep -q` under
  `set -o pipefail`; `grep -q` closes the pipe on first match, the producer dies with SIGPIPE
  (PIPESTATUS 141), and pipefail then fails the pipeline — so documented flags intermittently
  reported as missing. All `… | grep -q` checks now capture output and match a here-string.

### Added / Changed
- `--list-scenes` now prints a clear hint ("no scene cuts at threshold N; try a lower
  `--scene`") when a clip has no cuts, instead of silent output.
- `--version` is now documented in `--help`; enriched `plugin.json` keywords.
- Feedback issue form gained a **"Claude.ai web app (not Claude Code)"** environment option
  (and "Claude API / SDK") — the #21 session wasn't Claude Code.

### Notes
- The README plugin table is already at the current version (the structured version-sync test
  enforces it); the reporter's `0.3.0` sighting was a stale clone. Discoverability (no registry
  entry / repo topics) is logged in IMPROVEMENTS — it's resolved by the community submission +
  GitHub repo description/topics (manual).

## [1.0.0-rc.7] - 2026-06-20

From the 2nd black-hole-visualizer dogfood (#19). `video-bug-analyzer` → 1.0.0-rc.7.

### Added
- **End-of-run feedback nudge:** `extract-frames.sh` now prints a one-click, pre-filled
  GitHub issue link (plugin + ffmpeg version + the exact command, URL-encoded) on stderr after
  a real run, with a one-line reminder to click it. Suppress with `VBA_NO_FEEDBACK_HINT=1`.
- **`--version`** prints the plugin version (easy to cite in feedback).
- `repo-bootstrap` now also prints a **`/plugin marketplace add` + `/plugin install` one-paste
  CLI fallback** and documents that the committed-settings path may be blocked by Claude
  Code's auto-permission classifier until approved (#19).

### Docs
- "Plugins load at session start — enable one session ahead; use `--dry-run` to get the
  commands if a request arrives early" (SKILL + INTEGRATE). Hot-load is a Claude Code limit,
  noted in IMPROVEMENTS. `plugin.json` remains the single source of truth for version.

## [1.0.0-rc.6] - 2026-06-20

Implements the three backlog ideas from the black-hole-visualizer feedback (#16) as new
options. `video-bug-analyzer` → 1.0.0-rc.6.

### Added
- **`--list-scenes`**: prints the timestamps (seconds) of detected scene cuts and exits —
  auto-pick interesting moments to feed into `--timestamps`. Threshold via `--scene` (def 0.3).
- **`--diff`**: frame-difference mode (`tblend`) — each frame is the change from the previous
  one (bright = motion), to confirm what moved and infer direction.
- **`--label`**: burns the source timestamp (`drawtext`) onto each frame in
  dense/`--diff`/`--timestamps` modes. Best-effort — a runtime drawtext+font *probe* means it
  silently no-ops (never breaks a run) when the ffmpeg build lacks drawtext or a font.
- Tests for all three (e2e + always-on dry-run/help checks).

## [1.0.0-rc.5] - 2026-06-20

From the black-hole-visualizer dogfood (#16). `video-bug-analyzer` → 1.0.0-rc.5.

### Added
- **`--dry-run`**: prints the exact ffmpeg command(s) the script would run, without running
  them (no ffmpeg required, nothing written). Lets a live agent that can't load the plugin
  mid-session replicate the workflow by hand — the standout ask from #16.

### Fixed
- `set_vfr_flag` no longer shells out to a missing ffmpeg (it assumes the modern `-fps_mode`
  when ffmpeg is absent), so `--dry-run` works on a host without ffmpeg.

### Notes
- A high-fps burst around a flagged moment is already `--timestamps <t> --fps 12 --window`.
  Scene-cut timestamp auto-pick, frame-diff/optical-flow overlays, and timestamp burn-in are
  logged in IMPROVEMENTS.

## [1.0.0-rc.4] - 2026-06-19

From the NFT Toolkit dogfood (#14) — used to *read on-screen text* from a portrait phone
capture (not a bug). `video-bug-analyzer` → 1.0.0-rc.4.

### Changed
- **Broader skill trigger:** the `video-bug-analysis` description now covers non-bug "read the
  screen" tasks (inventory a site's UI, transcribe a demo) in addition to bug diagnosis, so it
  surfaces for those; SKILL body steers dense-text reads to full-res individual frames.
- **Portrait contact sheets:** auto-drop to `--cols 2` for portrait sources (ffprobe-detected,
  or `--portrait`), with a note that full-res individual frames read best for dense small text.

### Added
- **Legibility guard:** contact mode warns (via ffprobe) when tiles downscale the source >2.5×,
  suggesting individual frames / fewer cols / larger `--tile-width`.
- `--portrait` flag; tests for portrait auto-cols and the legibility warning.

## [1.0.0-rc.3] - 2026-06-19

From the second DedTxt dogfood (#12; rc.2 succeeded and the feedback auto-submitted via the
prefilled one-click link). `video-bug-analyzer` → 1.0.0-rc.3.

### Changed
- **Per-video default output dir:** frames now default to `.frames/<video-name>/` so a second
  clip in the same session doesn't clobber the first. `--out` overrides; `--strip` stays
  `.frames`.
- **`--strip` handles mismatched resolutions:** both frames are scaled to a common height
  before `hstack`, so a `.mov` frame and a `.webm` frame stitch cleanly.

### Added
- **Sparse-capture warning:** when `ffprobe` is available and the source's real frame rate is
  well below the requested `--fps`, the script notes that extra fps just repeats frames.
- Tests for no-clobber output, mismatched-resolution `--strip`, and the sparse warning.
- IMPROVEMENTS: logged auto-`--text` (text-heavy detection) as a deferred idea.

## [1.0.0-rc.2] - 2026-06-05

From the DedTxt dogfood (rc.1 found + fixed a real layout bug end-to-end on the web; ffmpeg
was already on PATH). `video-bug-analyzer` → 1.0.0-rc.2.

### Changed
- Contact-sheet default `--tile-width` 320 → **480** (320 was illegible for text/code UIs).
- Softened the ffmpeg note in SKILL/usage: ffmpeg is preinstalled in many environments;
  install is only attempted if it's missing.

### Added
- **`--text`** contact preset (640px tiles for code/transcript UIs, unless `--tile-width` set).
- **`--strip a.png,b.png`** (alias `--compare`): hstack two existing frames into `strip.png`
  — a before/after with no re-extraction; needs no `--video`.
- **`report-feedback.sh`**: auto-collects plugin/ffmpeg/OS diagnostics and emits a copy-paste
  report **plus a prefilled one-click GitHub issue link** (no auth/scope/session-network
  needed). Documents why silent auto-submit is impossible (network allowlist + MCP repo-scope
  + permission classifier) and the file-directly-if-possible fallback.
- Tests for `--strip`, `--text`, and the feedback assembler.

## [1.0.0-rc.1] - 2026-06-05

First release candidate. Both plugins (`video-bug-analyzer`, `repo-bootstrap`) are at
`1.0.0-rc.1`; the final `1.0.0` follows after debugging + dogfooding (see the manual gate).

### Fixed
- **Token bomb in dense/scene extraction** (`extract-frames.sh`): dense (`--fps`) and scene
  (`--scene`) frames are now width-capped via a new `--max-width` (default 1280, never
  upscales) — previously they emitted native resolution, so a 4K recording dumped multi-MB
  PNGs into context. Contact/timestamp modes already scaled. `reference.md` corrected to
  describe the actual per-mode scaling.
- **Self-defeating SessionStart hook** (`ensure-ffmpeg.sh`): removed the slow static
  download from the hook — under its 120s timeout it was killed mid-download, so it neither
  installed ffmpeg nor reached its warning. The hook now does fast installs only (apt/brew +
  cached binary) and immediately emits its `additionalContext` fallback; the uncapped static
  download stays in `extract-frames.sh` on first use. Test section 12 updated to match.
- **Broken CHANGELOG release links**: cutting `v1.0.0-rc.1` as a real annotated tag/release so
  the `[1.0.0-rc.1]` link resolves (historical links may still 404 until back-tagged).
- **Description drift**: the `marketplace.json` entry now matches the canonical `plugin.json`
  description verbatim (the 0.5.1 "aligned" claim is now actually true).

### Added
- `repo-bootstrap`: `--list` to print known plugin names, and a non-fatal warning when a
  `--plugin` name isn't found in a locatable `marketplace.json`.
- Tightened the README version-sync test to a structured plugin-table parse (was a loose
  substring grep); added tests for the bootstrap warning/`--list`.

### Changed
- All versions → `1.0.0-rc.1`; README header + plugin table + CHANGELOG consistent.

## [0.5.1] - 2026-06-05

Submission-prep for the Anthropic community marketplace — docs/metadata only, no behavior
change.

### Changed
- `video-bug-analyzer` 0.3.1: `plugin.json` description now matches the submission copy
  (overview contact sheet / scene-cut / per-timestamp zoom with before/after strips,
  ffmpeg auto-install); `homepage` points at the plugin directory.
- Tightened the `video-bug-analysis` skill frontmatter description to be more
  trigger-precise (explicit `.mov`/`.mp4` + approximate-timestamp cues).
- Aligned the marketplace entry description with the above.
- Validated with `claude plugin validate --strict` (plugin + marketplace): passes clean.

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

[1.0.0-rc.9]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.9
[1.0.0-rc.8]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.8
[1.0.0-rc.7]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.7
[1.0.0-rc.6]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.6
[1.0.0-rc.5]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.5
[1.0.0-rc.4]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.1
[0.5.1]: https://github.com/cportka/claude-plugins/releases/tag/v0.5.1
[0.5.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.5.0
[0.4.1]: https://github.com/cportka/claude-plugins/releases/tag/v0.4.1
[0.4.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.4.0
[0.3.1]: https://github.com/cportka/claude-plugins/releases/tag/v0.3.1
[0.3.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.3.0
[0.2.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.2.0
[0.1.0]: https://github.com/cportka/claude-plugins/releases/tag/v0.1.0
