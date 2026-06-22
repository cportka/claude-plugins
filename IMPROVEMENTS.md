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
- Auto-enable `--text` when a sampled frame looks text/UI-heavy (needs an OCR/edge-density
  heuristic — deferred from the rc.3 dogfood; manual `--text` for now).
- **Numeric plot over a CSV (extends `--ocr-roi`/`--measure`, issues #23/#27/#29).** The OCR
  and measure modes emit `t,value` timelines; auto-parsing the numbers and rendering a plot (or
  min/max/dips, or diameter-over-time) would beat reading the CSV by eye. Open.
- **Two-timestamp overlay / contour diff (issue #29).** Overlay frame A onto frame B at matched
  scale + center (with opacity, or an edge/contour diff) to eyeball whether two circles align.
  `--strip` does side-by-side hstack today; a true centered overlay is open.
- **Per-shot saturation/HSV histogram (issues #37, #39 — next up).** A saturation distribution per
  sampled frame ("80% of dust pixels are >0.7 saturation") to make "clownish vs elegant"
  measurable and verify a palette fix objectively. Tractable via ffmpeg `signalstats`
  (SATAVG/SATMAX per frame) → a saturation-over-time CSV; complements `--palette`.
- **Overdraw / fill-rate hint (issue #37).** "Canvas backing store is N× the CSS size on this
  DPR" would name a retina-overdraw perf cause directly. Not derivable from pixels alone (needs
  the DPR + CSS viewport, like the dpr note in `--probe`); open.
- **Optical-flow / trajectory overlay (issues #35, #37, #39).** `--motion` (rc.17) quantifies
  motion *magnitude* over time; the open half is *direction/coherence* — "two objects spiralling
  inward, ~2.5 turns" vs random drift — which needs optical-flow vectors or per-blob tracking
  (heavier, filter/version-dependent). Open.
- **Letterboxed A/B compare (issue #35).** `--ab` stretches differing aspect ratios to a common
  size; a letterbox-preserving compare would avoid distortion when the two captures differ in
  shape. Open.
- **Phase detection** to split "intro" vs "steady state" so a report can compare FPS across
  phases (builds on `--list-scenes`).
- **App-state / console-log hook at flagged timestamps (issue #27).** Optional bridge to
  capture console logs or a state dump at a bug timestamp. Render bugs are perfect for pixels;
  state-machine bugs (the v0.14.5 count-drop) need state. No ffmpeg-native source — needs the
  app/recording side to emit logs; open. (`--ocr-roi` + the state-vs-render steer is the
  in-tool half of this.)
- **Cursor / click tracking (issue #25).** Surface pointer position + click events; the cursor
  on a button at the failure frame identifies the trigger action. No ffmpeg-native source for
  this (needs the recording tool to capture input events); open.
- **Contact-sheet `frame,t` CSV index (issue #25).** `--label` now burns `t` onto contact tiles
  too (rc.18); a machine-readable `frame,t` sidecar CSV alongside the sheet is the remaining bit.
- **Event alignment for compare (`--align-on scene` / per-clip `--t0`, issue #41).**
  `--compare-videos` aligns by *phase fraction* (cols across each clip's duration); if a key event
  (a merger flash) lands at a different fraction in each clip, the columns won't coincide. An
  `--align-on scene` (detect a cut and align both to it) or per-clip `--t0 0.45` offset would line
  clips up on the *event*. Next step for compare.
- **Automatic phase labeling (issue #33).** Auto-split a reference clip into motion phases and
  describe each ("two blobs orbiting", "radial burst", "expanding rings"). `--list-scenes` gives
  the boundaries and `--palette` the colours, but a one-line semantic label per segment needs
  vision/heuristics beyond ffmpeg — open.
- **Motion / trajectory readout (issue #33).** "Two objects spiralling inward, ~2.5 turns,
  accelerating" → keyframes. Needs optical-flow tracking; `--diff` shows motion magnitude only.
  Open.

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
- 1.0.0-rc.6 (issue #16): `--list-scenes` prints detected scene-cut timestamps; `--diff`
  emits frame-difference (motion) images; `--label` burns the source timestamp onto frames
  (best-effort, drawtext-probed so it never breaks a run).
- 1.0.0-rc.7 (issue #19): end-of-run one-click pre-filled feedback link (auto, on stderr;
  `VBA_NO_FEEDBACK_HINT=1` to hide); `--version`; `repo-bootstrap` now prints a `/plugin …`
  one-paste CLI fallback + documents the auto-permission gate; "enable one session ahead" docs.
- 1.0.0-rc.9 (issue #23): `--crop W:H:X:Y` zooms a UI region (on-screen FPS/HUD, counter,
  small label) by cropping before scaling — legible at low token cost, in every mode. The
  tester's hand-cropped HUD strip was "the fastest path to the diagnosis"; this makes it a flag.
- 1.0.0-rc.10 (issue #25): `--blackdetect` finds blacked-out spans and flags PERMANENT
  (sustained to EOF) vs transient — the key signature for a stuck/crashed renderer. Honors
  `--crop` so a static UI overlay can be excluded before the black-ratio test (`--black-ratio`,
  `--black-min`); together with rc.9's `--crop` this automates the reporter's two manual steps.
- 1.0.0-rc.11 (issue #27, also asked in #23/#25 — "the single biggest gap"): `--ocr-roi
  W:H:X:Y` OCRs a panel readout per frame into a `t,text` CSV (`--ocr-digits` for numeric
  readouts), so a state/logic bug whose only symptom is a changing number (a count 4→5→4) is
  localised in seconds. Plus a state-vs-render diagnostic steer (value changes with no nearby
  pixel change ⇒ off-screen logic, go to logs/headless repro). Needs `tesseract` (now in CI).
- 1.0.0-rc.12 (issue #29 — "the biggest gap for alignment/tuning work"): `--measure W:H:X:Y`
  bounds a feature in the ROI per frame (ffmpeg extracts grayscale frames; python3 thresholds +
  computes a 2-D bounding box) → `t,...,diam_px,...,cx,cy` CSV, giving a feature's diameter (px
  and % of viewport) and center over time. `--measure-bright` for rings/glows, `--measure-limit`
  to tune. Robust where a center-row dark run fails (photon ring / disk).
- 1.0.0-rc.13 (issue #31): `--probe` reports capture geometry — dimensions, aspect, orientation,
  fps, duration — and which axis CSS `vmin` maps to; `--measure` now emits `diam_pct_w` AND
  `diam_pct_h` (% of width and height) and names the orientation/vmin axis, so responsive-UI
  (vmin) tuning reads the right axis. devicePixelRatio isn't knowable from pixels — noted, not
  invented.
- 1.0.0-rc.14 (issue #33): `--palette [--colors n]` extracts a clip's dominant colours as a hex
  swatch list (ffmpeg `palettegen` → python3 reads the PPM); narrow with `--start`/`--end` for
  one phase. For an art-direction *reference* the palette is the deliverable. Plus a GitHub Pages
  landing page (`index.html` + `.nojekyll`, served from `main`) — see Discoverability below.
- 1.0.0-rc.15 (issue #35 — "the big one for cross-browser bugs"): `--ab <other>` compares two
  captures of the same sequence and prints a `t,ssim` divergence timeline (ffmpeg `ssim`),
  headlining the most divergent moments — "these intros differ most at 0.20–0.28 s" in one step.
- 1.0.0-rc.16 (issue #37 — ranked #1): `--cadence` reports nominal-vs-effective frame rate
  (dropped/duplicated frames = stutter) and a per-`--window` unique-frame timeline (ffmpeg
  `mpdecimate` + `ffprobe`) so choppiness localizes to a span, not just an average.
- 1.0.0-rc.18 (issue #41): `--compare-videos a,b` emits one stacked, phase-normalized contact
  sheet (a row per clip) for "why does B differ from A"; an automatic `smoothness:` header
  (effective vs nominal fps + dropped estimate) on every run; and `--label` now burns timestamps
  onto contact tiles + compare rows.
- 1.0.0-rc.19 (issue #43): `--intro` load/splash preset (first ~2s, dense labelled contact,
  portrait-aware; explicit flags still win), plus an "animation didn't play → frames show absence
  not cause; pair with a DOM/console capture" doc note. #43's other asks shipped earlier
  (compare/smoothness/label rc.18, motion rc.17).
- 1.0.0-rc.17 (issue #39): `--motion` prints a `t,motion` mean-inter-frame-delta timeline
  (`tblend` + `signalstats`) — motion as a number, the quantitative companion to `--diff`. Also
  a 1.0.0 shore-up: SKILL.md slimmed ~29% (prose → a "pick by the question" table; detail stays
  in reference.md), and the `--help` doc test is now derived from the argparse (no hand-kept
  list). reference.md gained a headless-virtual-time/CSS-animation capture note.

**Hard constraint (Claude Code, not the plugin)**
- Plugins load at session *start* — there's no supported hot-load, so a video dropped right
  after enabling the plugin can't use it until the next session. Mitigations shipped:
  `--dry-run` (print commands to run by hand) and "enable one session ahead" guidance.

**Ideas (cont.)**
- A broader catalog/`plugin.json` description (or a sibling "read-a-screen-recording" skill)
  so the plugin is discoverable for non-bug reads, not just bugs (issue #14). Deferred to keep
  the locked submission copy stable through RCs.
- True optical-flow *vector* overlay (direction arrows) — `--diff` shows motion magnitude;
  proper flow visualization is heavier/filter-dependent and still open.

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
- No markdown link-checking or spell/style linting.
- Single CI job (ubuntu); no macOS leg for the `brew` install path.

**Ideas**
- Markdown link lint; optional macOS CI leg.

**Shipped**
- 1.0.0-rc.3: structured README-table ↔ `plugin.json` version-sync check (was a substring grep).
- 1.0.0-rc.8 (issue #21): fixed flaky `--help | grep -q` tests (SIGPIPE under `pipefail`) by
  capturing output and matching a here-string; `--list-scenes` now guides you when a clip has
  no cuts at the threshold; feedback form gained a "Claude.ai web app (not Claude Code)" option.

## Discoverability (issue #21, open)
The plugin isn't findable autonomously — no MCP connector-registry entry, and the GitHub repo
lacks a description/topics. Progress: a **GitHub Pages site** now exists (rc.14,
`index.html` served from `main` at `cportka.github.io/claude-plugins`), giving "Portka Tools" a
real web page. Remaining real fixes are outside the code: (a) submit `video-bug-analyzer` to the
Anthropic community marketplace (planned at final 1.0.0), and (b) set the GitHub repo
**description** + **topics** (`claude-code`, `claude-plugin`, `video`, `debugging`, `ffmpeg`) —
both manual, no MCP tool exposed here. Also enable Pages (Settings → Pages → deploy from `main`)
if not already on. Enriched `plugin.json` keywords as a small step.
