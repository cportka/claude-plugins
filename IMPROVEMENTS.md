# Roadmap & Known Weaknesses

Forward-looking notes: what each plugin does well, where it's weak, and ideas not yet built.
Kept here — not in the skills — so in-context instructions stay lean. **Shipped history lives in
[CHANGELOG.md](./CHANGELOG.md)**; user-reported problems arrive via the **Plugin feedback** issue
form and are triaged into the items below.

## video-bug-analyzer

**Strengths**
- Repeatable, bug-tuned frame extraction (dense / scene-change / contact-sheet) plus a deep set
  of analysis modes (blackdetect, OCR, measure, probe, palette, ab/compare, cadence/stutter,
  pacing, motion, flow, occupancy, saturation) — most emit a CSV/report and exit, so they compose.
- `--flow` (1.4.0, #69) reads motion *character*, not just magnitude: a coarse block-matching
  optical flow decomposed about a center into swirl (rotational/curl) and suck (radial/divergence),
  so "spinning in place" (|curl| high, div≈0) is distinguishable from "spiralling inward" (high curl,
  div<0) — the read `--motion`/`--diff` (magnitude only) can't give.
- `--occupancy` (1.4.0, #69) quantifies subject extent — coverage % + bounding box per frame — so
  "the subject is too small to see" becomes a number and you can watch it grow; counterpart to
  `--blackdetect`'s empty-frame threshold.
- `--stutter`/`--fps-drops` (1.1.2) quantifies FPS stalls: effective-fps-per-window **and** the
  longest freeze gaps (freezedetect), so a "feels choppy" report becomes timestamps + durations.
  A static/near-black recording pre-roll is detected and excluded from the "choppiest windows"
  ranking (1.4.1, #70), so the lead-in stops competing with the freeze gaps for the top spots.
- `--pacing` (1.2.0) reads the real per-frame presentation timestamps (ffprobe) for a frame-pacing
  /jitter timeline — catches uneven timing even when every frame's content differs (which the
  content-based `--cadence`/`--stutter` can't), with median/p95/max + worst-hitch timestamps.
- `--stack` (1.3.0, #62) is the ROI time-stack: crop a band (scrub bar / HUD / status row) and tile
  the samples vertically so one image reads that region's evolution across the clip.
- Output hygiene (1.3.0, #64): a run never overwrites a previous extraction — collisions redirect
  into a mode+window subdir. `--check-update` (#62) spots a stale install vs the marketplace.
- Contact-sheet reads a whole span in one image (big token saver); the skill states confidence
  and caveats instead of bluffing; ffmpeg is handled (SessionStart hook + on-first-use fallback).

**Weaknesses / cons**
- Blind between samples: fast flickers / one-frame glitches can be missed.
- Timing is partly served now (`--stutter` localizes stalls/freeze gaps), but true race / ordering
  bugs still need logs or a repro, not frames.
- Off-screen state (console / network / memory) is invisible — `--ocr-roi` + the state-vs-render
  steer are the in-tool half; the rest needs logs / a repro.
- Scene-change is heuristic (threshold per clip); many PNGs cost tokens if the window/fps isn't tight.

**Ideas (not yet built)**
- **Denser / labelled flow** — `--flow` (1.4.0, #69) ships the swirl-vs-suck (curl/divergence) split
  that answers "spinning in place vs spiralling inward". Remaining: a *dense* per-blob trajectory
  overlay (turn count, drift direction), and better handling of pure **expansion** (outward `div` is
  under-measured because block matching assumes translation, not scaling) — a small-motion
  gradient/pyramid pass or a scale-aware match would close that.
- **Multi-clip batch** (#69) — run the same analysis modes over N clips and emit one report keyed by
  clip (the "same bug across Chrome + Firefox" case). Overlaps `--compare-videos` (which is a single
  phase-aligned A/B sheet, not a per-clip timeline batch); a `--batch a.mov,b.mov --motion` shape
  would run each mode over each clip and label the CSVs by source. Low priority.
- **Numeric plot over a CSV** — the OCR/measure/motion/saturation modes emit `t,value`; rendering
  a quick plot (or min/max/dips) would beat reading the CSV by eye.
- **Machine-readable freeze gaps** (#70) — the freeze-gap list is human-readable on stderr; a
  `t_start,dur_ms` CSV would let it be plotted against an app's own timing marks. Deferred over an
  output-shape choice: the `--cadence` stdout is already the `t,unique_frames,fps` CSV, so a second
  table needs either a separate `--freeze-csv` sink or a delimiter that won't confuse consumers.
- **Two-timestamp centered overlay / contour diff** — `--strip` is side-by-side; a matched-scale
  centered overlay (or edge diff) would show whether two features align.
- **Event alignment for compare** (`--align-on scene` / per-clip `--t0`) — `--compare-videos`
  aligns by phase fraction; align on a detected cut/event when it lands at a different fraction.
- **Letterboxed A/B** — `--ab`/`--compare-videos` stretch differing aspect ratios; preserve them.
- **Automatic phase labeling** — split a reference clip into phases with a one-line label each
  (needs vision beyond ffmpeg; `--list-scenes` + `--palette` are the boundaries + colours today).
- **Auto-fallback to contact** when a frame count would blow a token budget; auto-`--text` when a
  sampled frame looks text-heavy (needs an edge-density heuristic).
- **App-state / console-log hook** and **cursor/click tracking** — need the app/recording side to
  emit logs or input events; no ffmpeg-native source.
- **Slim self-hosted ffmpeg release asset** (allowlisted, lighter than BtbN's ~100MB) wired as the
  preferred download.

**Hard constraints (not fixable in the plugin)**
- Claude Code's auto-mode classifier won't silently download-and-execute an agent-chosen binary,
  so ffmpeg can't fully self-install in a fresh sandbox — approve the install or use a screenshot.
- Plugins load at session *start* (no hot-load), so a video dropped right after enabling can't use
  the skill until the next session — mitigated by `--dry-run` + "enable one session ahead".

## repo-bootstrap

**Strengths**
- Non-clobbering, idempotent JSON merge; refuses to touch invalid settings; `--list` and
  `--dry-run`; one command wires up web-session plugin loading + optional CI; prints a `/plugin`
  CLI fallback for when the settings write is permission-gated.
- `--portka-standard` scaffolds the whole standard setup in one run: a workflow `CLAUDE.md`
  (managed block, idempotent), a git/`gh` permissions allowlist merged into `settings.json`, and an
  enforced SemVer sync that **binds to the repo's native version** (`package.json` / `pyproject.toml`
  / `Cargo.toml` / `VERSION` / README) with a basic `tests/run-tests.sh` + a collision-aware CI.
- `--print-only` emits the `settings.json` (+ `CLAUDE.md`) for a human paste when the auto-mode
  classifier refuses an agent write (#59) — the only reliable path to a committed file in some
  web sessions.
- `--portka-standard` also emits a **native version-sync test** (1.2.0) in the repo's own runner —
  `node:test` for a `package.json` repo, `unittest` for a `pyproject.toml` repo — so `npm test` /
  `pytest` enforces the version↔CHANGELOG sync, not just the standalone bash runner.

**Weaknesses / ideas (not yet built)**
- Requires `python3` (no pure-bash/`jq` fallback yet).
- The native version-sync test covers JS + Python; **Cargo** (and other ecosystems) still get only
  the bash runner. And it's emitted *alongside* `tests/run-tests.sh` — could **replace** the
  standalone runner (and rewire CI to the native command) when a manifest is present, per #59.

## app-website-evaluator

**Strengths**
- Self-referential: classifies the target (type/audience/goal) and judges every property — and
  its own advice — against what's best for *that* kind of site and community.
- `evaluate-site.sh` gives a concrete evidence base from a live URL **or** a local build (offline),
  spanning crawlability, SEO, social, assets, AI-readiness (`llms.txt`), security headers, perf.
- **Standardized scorecard** (1.2.0): each dimension 0–100 + letter grade, a weight-averaged overall,
  and `--json` — a repeatable, comparable answer (and a CI-wireable artifact), not a loose checklist.
- **Coverage-honest overall** (1.3.0, #63): a partial-coverage grade is starred (`A*`) with the
  unassessed weight named, so a dir-mode A can't overstate; AI-readiness **parse-validates JSON-LD**
  (invalid → FAIL) and credits rich schema types (FAQPage/Review/Article/HowTo) — real AEO signals.

**Weaknesses / ideas (not yet built)**
- HTML checks are grep-heuristic (best-effort), not a DOM parse; a JS-rendered SPA can hide content
  from a simple fetch — note it and prefer the built/SSR output or repo.
- No real Core Web Vitals / Lighthouse run (points the user there); could integrate if a headless
  browser is available (Chromium now ships for the tab PDF — reuse it). No automated link-check or
  a11y contrast scan yet. Dimension **weights are fixed**; could auto-tune them by site type.
- **Sitemap freshness** (#63's remaining ask): the sitemap check is presence-only; could parse
  `<lastmod>` recency and reward a fresh sitemap as an AI-readiness/crawlability signal.

## tab-chord-formatter

**Strengths**
- Clean split of concerns: a deterministic script does the safe cleanup (HTML/entity decode,
  whitespace, section labels) and never touches a line's internal alignment; the skill does the
  judgment (re-aligning chords over syllables, inferring sections).
- **Print mode → PDF** (1.2.0): a consistent single-font/size monospace songbook via headless
  Chromium, multi-song aware, `--songs-per-page` (default 1), `--dedent` to normalize ragged
  margins; `--html` for a Chromium-free path.

**Weaknesses / ideas (not yet built)**
- Song splitting is a heuristic (`Artist – Title` un-indented + blank-preceded, or a form-feed); an
  explicit per-song separator or a front-matter header would be more robust for odd songbooks.
- Wide ASCII-tab blocks can overflow the page at the default size — today the lever is `--size`;
  could **auto-fit** the font to the widest line, or offer landscape / a transpose-and-rewrap.
- No structured export (ChordPro `.pro` / `.chordpro`, or an HTML view for the screen mode) yet;
  no built-in transpose/capo math.

## Repo / tests

**Strengths**
- One self-contained runner; tool-dependent steps SKIP cleanly, run for real in CI (ffmpeg +
  shellcheck + tesseract). Covers manifests, marketplace↔plugin consistency, version sync,
  frontmatter, hooks, every script's CLI, the ffmpeg/eval e2e, and the GitHub Pages page.

**Ideas (not yet built)**
- Markdown link-lint; an optional macOS CI leg for the `brew` install path.

## Discoverability
The marketplace now has a **GitHub Pages** site (`cportka.github.io/claude-plugins`) and enriched
`plugin.json` keywords. Remaining (manual, no MCP tool exposed here):
- Submit to the **Anthropic community marketplace** (see RELEASING.md).
- Set the GitHub repo **description** + **topics** (`claude-code`, `claude-plugin`, `video`,
  `debugging`, `ffmpeg`, `seo`, `audit`) and ensure **Pages** is enabled (Settings → Pages →
  deploy from `main`).
