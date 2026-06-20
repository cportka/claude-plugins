# Improvements & Known Weaknesses

Honest notes on what each plugin does well, where it's weak, and how it could improve. Kept
here — not in the skills — so the in-context instructions stay lean. User-reported problems
arrive via the **Plugin feedback** issue form and are triaged into the items below.

## video-bug-analyzer

**Strengths**
- Repeatable frame extraction tuned to the bug: dense / scene-change / contact-sheet.
- Contact-sheet mode reads a whole span in one image — large token saver.
- The skill states confidence and caveats instead of bluffing.
- ffmpeg is handled (SessionStart hook + on-first-use fallback).

**Weaknesses / cons**
- Blind between samples: fast flickers and one-frame glitches can be missed.
- No true timing: race / ordering / duration bugs are poorly served by frames.
- Off-screen state (console / network / memory) is invisible.
- Scene-change mode is heuristic; the threshold needs tuning per clip.
- Many PNGs (token cost) if the window/fps isn't tightened.

**Ideas**
- Auto-fallback to a contact sheet when frame count would blow a token budget.
- Optional per-frame timestamp burn-in for clearer timeline references.
- A crop/region flag to zoom on a UI area and cut tokens.
- Auto-enable `--text` when a sampled frame looks text/UI-heavy (needs an OCR/edge-density
  heuristic — deferred from the rc.3 dogfood; manual `--text` for now).

**Hard constraint (not fixable in the plugin)**
- Claude Code's auto-mode classifier will **not silently run a download-and-execute of an
  agent-chosen binary** — the user must approve it. So ffmpeg can't fully self-install in a
  fresh sandbox; the screenshot path is the only zero-friction option there. Docs lean into
  this (approve the install, or use a screenshot).

**Shipped**
- 0.2.2: `-fps_mode vfr` on modern ffmpeg (was deprecated `-vsync`), with `-vsync` fallback
  and an ffmpeg-version diagnostic line.
- 0.2.3: static-ffmpeg download fallback in the extractor and SessionStart hook.
- 0.3.0: GitHub (BtbN) static build as the primary download source (reachable where apt
  isn't); `--timestamps` dense-burst + before/after strip; `--window`/`--frame-width`;
  screenshot-fallback promoted to first-class.
- 1.0.0-rc.2: `--tile-width` default 480 + `--text` preset; `--strip` (hstack two frames);
  `report-feedback.sh` (one-click prefilled issue link).
- 1.0.0-rc.3: per-video default output dir (no clobber); `--strip` normalizes heights for
  mismatched resolutions; `ffprobe` sparse-capture warning.
- 1.0.0-rc.4: broadened the skill trigger to non-bug "read the screen" tasks; portrait
  auto-`--cols 2` + `--portrait`; contact legibility guard (warns on heavy downscale).
- 1.0.0-rc.5: `--dry-run` prints the exact ffmpeg commands without running them, so a live
  agent that can't load the plugin mid-session can replicate the workflow by hand (issue #16).

**Ideas (cont.)**
- A broader catalog/`plugin.json` description (or a sibling "read-a-screen-recording" skill)
  so the plugin is discoverable for non-bug reads, not just bugs (issue #14). Deferred to keep
  the locked submission copy stable through RCs.
- Scene-cut/keyframe detector that *prints the timestamps* of detected cuts to auto-pick
  interesting moments (issue #16). (`--scene` already extracts at cuts; this would surface
  their times.)
- Frame-diff / optical-flow overlay to confirm motion direction instead of eyeballing strips
  (issue #16) — heavier ffmpeg filtergraph; needs care + a font/filter availability check.
- Optional per-frame timestamp burn-in (`drawtext`) — the #16 dogfooder did this by hand and
  found it valuable; gated on `drawtext`/freetype being compiled into the ffmpeg build.
  (A high-fps burst around a flagged moment is already `--timestamps <t> --fps 12 --window`.)

**Still open**
- A slim, self-hosted ffmpeg release asset on this repo (allowlisted, lighter than BtbN's
  ~100MB) — needs a binary published as a release asset; wire the installer to prefer it.

## repo-bootstrap

**Strengths**
- Non-clobbering, idempotent JSON merge; refuses to touch invalid settings.
- One command wires up web-session plugin loading + optional CI.

**Weaknesses / cons**
- Requires `python3` (assumed present; no pure-bash fallback).
- Generated CI is intentionally minimal (runs `tests/run-tests.sh` if present).
- No `CLAUDE.md` or test-harness scaffolding yet.

**Shipped**
- 1.0.0-rc.1: `--list`, and a non-fatal warning when a `--plugin` name isn't in a locatable
  `marketplace.json`.

**Ideas**
- Optional `CLAUDE.md` and `tests/run-tests.sh` starters.
- `jq` fallback when `python3` is absent.

## Repo / tests

**Strengths**
- One self-contained runner; tool-dependent steps SKIP cleanly; CI runs them for real.
- Covers manifests, marketplace↔plugin consistency, versions, frontmatter, hooks, script
  CLI, bootstrap scaffolding, and ffmpeg extraction.

**Weaknesses / cons**
- Version-sync check is a substring match, not a structured table parse.
- No markdown link-checking or spell/style linting.
- Single CI job (ubuntu); no macOS leg for the `brew` install path.

**Ideas**
- Structured README-table ↔ `plugin.json` version check.
- Markdown link lint; optional macOS CI leg.
