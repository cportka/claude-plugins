# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

## [1.0.0-rc.18] - 2026-06-22

From the fresh-vs-replay dogfood (#41): comparing two clips of the same intro meant running the
tool twice and eyeballing two sheets with different time axes, and the "is it choppy" smoking gun
(avg_frame_rate 24 vs nominal 60) lived in raw ffprobe, outside the tool.
`video-bug-analyzer` → 1.0.0-rc.18.

### Added
- **`--compare-videos a,b`** (issue #41, "a top-3 real request") — one stacked contact sheet, a
  **row per clip**, each sampled into `--cols` tiles across its **own** duration (a normalized
  phase axis) so different-length clips line up by % through the sequence, not absolute time.
  The visual companion to `--ab`'s divergence number. Writes `<out>/compare.png`; `--label` burns
  each tile's timestamp; needs `ffprobe`.
- **Automatic `smoothness:` header on every run** — effective (`avg_frame_rate`) vs nominal
  (`r_frame_rate`) fps plus a dropped/duplicated-frame estimate. The single best free "is it
  choppy?" number; no more reaching for raw ffprobe.

### Changed
- **`--label` now applies to contact tiles** (and `--compare-videos`) — drawtext is burned
  per-frame before tiling, which is exactly what timing analysis wants. The old "not applied to
  contact" note is gone.

### Notes
- #41's event-alignment ask (`--align-on scene` / per-clip `--t0`, so two clips line up on an
  event when it lands at a different phase fraction) is logged in IMPROVEMENTS as the next step
  for compare. #41's motion-magnitude reaffirmation shipped in rc.17 (`--motion`).

## [1.0.0-rc.17] - 2026-06-22

A 1.0.0 shore-up: incorporates the latest dogfood (#39) and tightens tests + token usage ahead
of the final release. `video-bug-analyzer` → 1.0.0-rc.17.

### Added
- **`--motion`** (issue #39) — motion timeline: prints `t,motion` (mean inter-frame pixel delta,
  0–255) per sampled frame, so "is it moving / where does motion concentrate / does it feel too
  long?" becomes a number. The quantitative companion to `--diff` (built on
  `tblend=difference` + `signalstats`); headlines the average and peak moment. Needs `python3`.

### Changed
- **SKILL.md slimmed ~29%** (1468→1047 words): the per-mode prose (which duplicated
  `reference.md`) is now a compact "pick by the question" table plus the key *frames-can't-see-
  state* steer. All detail still lives in `reference.md` + `--help`. Lower context cost every
  session, same discoverability.
- **Tests: the `--help` documentation check is now derived from the argparse** (every `--flag`
  case arm must appear in `--help`) instead of a hand-maintained list — auto-covers new flags and
  removes an upkeep footgun. Added `--motion` e2e + dry-run.

### Docs
- reference.md: a capture-side note that **headless virtual time doesn't drive the compositor**,
  so CSS animations won't advance unless you freeze `getAnimations().currentTime` or use real
  wall-clock — explains a "nothing moving" clip (#39).

### Notes
- #39's optical-flow/trajectory overlay (coherent-vs-random motion) and per-shot saturation/hue
  histogram remain logged in IMPROVEMENTS; `--motion` covers the magnitude/"where" half.

## [1.0.0-rc.16] - 2026-06-22

From the stutter-localization dogfood (#37, OSP v0.16.3 WebGPU splash): the avg-vs-nominal
frame-rate split caught the choppiness, but the reporter wanted to see *when* it stutters, not
just an average. `video-bug-analyzer` → 1.0.0-rc.16.

### Added
- **`--cadence`** (issue #37) — frame-cadence / jitter timeline. Reports the container's nominal
  rate (`r_frame_rate`) vs its real average (`avg_frame_rate`) — a big gap = dropped/duplicated
  frames (the dogfood MVP that localized the perf bug to overdraw) — then runs `mpdecimate` to
  count *unique* frames per `--window` bin (default 0.5s), printing a `t,unique_frames,fps` CSV
  and headlining the choppiest windows so a hitch localizes to a span (e.g. an end-of-splash
  burst). Measures unique-content cadence (a static scene reads low — the honest signal). Honors
  `--start`/`--end`; uses ffmpeg `mpdecimate` + `ffprobe`, needs `python3`. Documented in
  `--help`, SKILL.md, reference.md; covered by e2e + dry-run + help-doc tests.

### Notes
- #37's other asks logged in IMPROVEMENTS: a per-shot **saturation histogram** (HSV, to make
  "clownish vs elegant" measurable — tractable via `signalstats`, likely next), an **overdraw/
  fill-rate** hint (not derivable from pixels — needs DPR/CSS size), and **motion-coherence**
  (optical flow). The avg/nominal split surfaced here pairs with rc.13's `--probe`.

## [1.0.0-rc.15] - 2026-06-21

From the cross-browser dogfood (#35): two captures of the same intro (Safari iOS vs Firefox/
macOS) used to find a splash bug that only appears on one browser. Side-by-side tiles made the
divergence visible; the ask was to flag *where* in time two clips differ.
`video-bug-analyzer` → 1.0.0-rc.15.

### Added
- **`--ab <other>`** (issue #35) — A/B divergence: compares `--video` against another capture of
  the same sequence and prints a `t,ssim` CSV (1.0 = identical, lower = more different),
  headlining the most divergent moments — i.e. "these intros differ most at 0.20–0.28 s" in one
  step. Both clips are sampled at `--fps` and scaled to the primary's size; `--start`/`--end`
  align the window on both. Built on ffmpeg's `ssim` filter. The headline cross-browser-bug tool.

### Notes
- #35's other asks are logged in IMPROVEMENTS as the next priorities: a cadence/stutter timeline
  (dropped/duplicated frames + frame-time variance — the reporter hand-ran `mpdecimate`), and a
  per-blob motion/trajectory readout. Different aspect ratios are stretched to compare; a
  letterboxed compare is a possible follow-up.

## [1.0.0-rc.14] - 2026-06-21

A GitHub Pages landing page for the marketplace, plus a colour-palette mode from the
art-direction dogfood (#33, where the workflow was used to reverse-engineer a reference clip's
choreography and palette). `video-bug-analyzer` → 1.0.0-rc.14.

### Added
- **GitHub Pages site** — a self-contained `index.html` (with `.nojekyll`) at the repo root,
  served from `main`: what Portka Tools is, the two plugins, how to add and use them, and a
  feedback link. Linked from the README header. This also chips at the discoverability gap
  (issue #21) by giving the project a real web page.
- **`--palette`** (issue #33) prints a clip's dominant colours as a hex swatch list
  (`#rrggbb  rgb(...)`), `--colors <n>` for how many (default 8). Narrow with `--start`/`--end`
  to read one phase's palette — for an art-direction *reference*, the colours are the
  deliverable. Built on ffmpeg `palettegen`; `python3` reads the swatch PPM. Documented in
  `--help`, SKILL.md, reference.md; covered by e2e + dry-run + help-doc tests.

### Notes
- #33's phase *boundaries* are already served by `--list-scenes` (+ a timestamped contact tile
  for the phase timeline); SKILL.md now frames the reference-reading workflow. Deferred to
  IMPROVEMENTS: automatic phase *labeling* (semantic) and a motion/trajectory readout.
- No plugin behaviour changed beyond the new `--palette` mode.

## [1.0.0-rc.13] - 2026-06-21

From the v0.15.x **mobile (portrait) intro** dogfood (#31): tuning a load splash on a 1170×2532
capture, where the splash is authored in `vmin` — which is viewport *width* in portrait but
*height* in landscape — so a feature's "fraction of the viewport" depends on orientation. The
ask was capture-context + orientation-aware measurements. `video-bug-analyzer` → 1.0.0-rc.13.

### Added
- **`--probe`** prints the capture's geometry — dimensions, aspect ratio (reduced + decimal),
  **orientation** (portrait/landscape/square), fps, duration — and which axis CSS `vmin` maps to,
  with a note that devicePixelRatio can't be read from pixels alone. Run it before measuring so
  percentages are read on the right axis. Uses `ffprobe`.

### Changed
- **`--measure`** now reports **both** axes: the CSV is
  `t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy` (was a single `diam_pct` = % of width). The
  run summary names the capture's orientation and which column is the `vmin` axis, so
  responsive-UI tuning doesn't reason about the wrong dimension.

### Notes
- #31's circle-diameter-over-time ask was already shipped as `--measure` in rc.12 (the reporter's
  recordings predate it); this round makes it orientation-aware. Still deferred to IMPROVEMENTS:
  a two-timestamp centered overlay/diff, and a numeric-plot rendering over the CSVs.

## [1.0.0-rc.12] - 2026-06-20

From the v0.15.0 intro dogfood (#29): aligning a load-splash's forming event horizon with the
real render's shadow — a *measurement* task ("how big is the splash core vs the real shadow, as
a fraction of the viewport"). Timing and the obvious size jump were easy; the gap was geometry —
a naive center-row dark-run gave garbage because the photon ring and accretion disk break the
dark run. `video-bug-analyzer` → 1.0.0-rc.12.

### Added
- **`--measure W:H:X:Y`** — geometry/measurement: inside the ROI, bounds a feature once per
  sampled frame (ffmpeg extracts grayscale frames, **python3** thresholds each and computes a
  true 2-D bounding box — robust where a center-row scan fails) and prints
  `t,w_px,h_px,diam_px,diam_pct,cx,cy`: bounding-box size, the major-axis **diameter** in px and
  **% of viewport width**, and the **center** in full-frame px. **`--measure-bright`** measures a
  bright feature (a ring/glow) instead of the default dark one; **`--measure-limit <n>`** is the
  luma threshold (default 80). `--fps` sets the rate; honors `--start`/`--end`; `ffprobe`
  supplies the % column. Reporting as % of viewport also answers
  #29's dpr/units ask — the `diam_pct` column is dpr-independent (retina px don't mislead).
  Documented in `--help`, SKILL.md, reference.md; covered by e2e + dry-run + help-doc tests.
- SKILL guidance for "how big / where" (visual-tuning) vs "what's wrong" (bug-spotting), and to
  report sizes as % of viewport.

### Notes
- Deferred to IMPROVEMENTS: a two-timestamp overlay/diff at matched scale (#29's request #2;
  `--strip` is the current side-by-side), and a numeric-plot rendering over the measure/OCR CSVs.

## [1.0.0-rc.11] - 2026-06-20

From the OneStillPoint v0.14.5 dogfood (#27): chasing "adding a body sometimes drops the
count" — a **state/logic bug whose only symptom was a panel number changing** (4→5→4), with
the offending bodies leaving *off-screen*. Frame analysis alone couldn't root-cause it; the
tester had to write a headless sim harness. The repeatedly-requested ROI value tracker (asked
in #23, #25, and #27 — "the single biggest gap") closes most of that gap.
`video-bug-analyzer` → 1.0.0-rc.11.

### Added
- **`--ocr-roi W:H:X:Y`** — value tracker: OCRs a small region (a panel readout — body counts,
  a Speed value, a timer) once per sampled frame and prints a `t,text` CSV to stdout, so a
  number changing over time is localised in seconds where staring at frames can't help.
  **`--ocr-digits`** restricts recognition to digits + a few separators (cleaner for numeric
  readouts); `--fps` sets the sample rate; honors `--start`/`--end`. Requires `tesseract` (the
  one mode beyond ffmpeg) — prints an apt/brew install hint and exits if it's missing. CI now
  installs `tesseract-ocr` so the e2e runs. Documented in `--help`, SKILL.md, reference.md.
- **State-vs-render diagnostic steer** (SKILL.md + reference.md + an on-run note): if a tracked
  value changes with no correlated pixel change, the cause is off-screen logic/state — say so
  and point at logs / a small headless repro instead of extracting more frames.

### Notes
- Deferred to IMPROVEMENTS: an app-state/console-log hook at flagged timestamps (#27), cursor/
  click tracking, and contact-sheet timestamp burn-in + a `frame,t` CSV index.

## [1.0.0-rc.10] - 2026-06-20

From a black-screen RCA dogfood on OneStillPoint v0.14.4 (#25), where the analysis nailed the
bug but the tester had to hand-crop the canvas and write a custom luminance trace because
`blackdetect` was fooled by a persistent UI panel. `video-bug-analyzer` → 1.0.0-rc.10.

### Added
- **`--blackdetect`** finds blacked-out spans and classifies each as **PERMANENT** (sustained
  to EOF — a stuck/crashed renderer) or **transient** (a flash), printing
  `black START -> END (dur) — …`. Permanence uses `ffprobe` for the source duration; spans
  still list without it. Honors `--crop` (so a static UI overlay — the dogfood's lil-gui panel
  — can be excluded before the black-ratio test, the exact manual step the reporter did by
  hand) and `--start`/`--end`. Tunables: **`--black-min <sec>`** (min span, default 0.1) and
  **`--black-ratio <r>`** (`pic_th`, default 0.98; lower if an overlay keeps pixels lit).
  Documented in `--help`, SKILL.md, reference.md; covered by e2e + dry-run + help-doc tests.

### Notes
- Pairs with rc.9's `--crop`: the reporter's two manual steps (crop the render canvas, then
  test for black) are now `--blackdetect --crop …`.
- Deferred to IMPROVEMENTS as future ideas: panel/HUD OCR at the failure frame, cursor/click
  tracking, and timestamp burn-in on the contact sheet + a `frame,t` CSV index.

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

[1.0.0-rc.18]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.18
[1.0.0-rc.17]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.17
[1.0.0-rc.16]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.16
[1.0.0-rc.15]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.15
[1.0.0-rc.14]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.14
[1.0.0-rc.13]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.13
[1.0.0-rc.12]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.12
[1.0.0-rc.11]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.11
[1.0.0-rc.10]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.10
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
