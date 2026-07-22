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
- Doubles as an **art/colour-reference** tool (1.8.0, #85): `--palette --over-time` emits the colour
  *arc* (`t,[hex…]` per window) so a loop's colour journey is visible, and `--loop-check` reports the
  first-vs-last-frame seam diff (+ a strip) for a seamless loop; GIF input works on every mode.
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
- **Token-level `--content-revert`** (#108, the remaining half): the shipped detector diffs frame
  *signatures* (A→B→A on pixels); an OCR variant would diff word SETS so "which words dropped"
  is named in the verdict, and an auto-FPS-boost around detected change regions would catch
  transients even shorter than the 10 fps default samples. `--ocr-roi` covers it manually today.
- **`--app-crop` — mobile-chrome auto-crop** (#96). On portrait phone captures the URL bar + toolbar
  + status bar eat ~25% of every contact tile, right where legibility is scarcest. Heuristic: find the
  stable chrome bands (top/bottom) by per-row temporal variance — chrome never changes, the app always
  does — and crop to the live region, so portrait sheets read as cleanly as desktop with zero manual
  `--crop` math. Fussier than `--t0` (needs a multi-frame variance pass + a band-continuity rule);
  the manual `--crop W:H:X:Y` covers it today.
- **`--concat a.mov,b.mov` — one timeline across split parts** (#96). `--t0` (1.11.0) already removes
  the *correlation* error for multi-part sessions by relabeling reported times into session time;
  `--concat` would go further and analyze the parts as a single stream. Fussier — a VFR splice, where
  each part's timebase differs, so the join needs pts normalization — deferred behind `--t0`, which
  solves the reported pain (freeze-vs-mark correlation) directly.
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
- **`--montage a.gif,b.gif,…`** (#85) — an N-way *library survey*: one representative tile per input,
  one contact sheet, to eyeball a whole collection's range at a glance. Distinct from the pairwise
  phase-aligned `--compare-videos`; overlaps the multi-clip batch idea above (shape here is survey).
- **Palette as a swatch artifact** (#85) — `--palette`/`--palette --over-time` emit hex text; a small
  SVG/PNG swatch sheet would be a drop-in reference asset, closing "analyze → usable design artifact".
- **`--track-color <hue> --tol <n>`** (#89) — emit `t,x,y,r` for a colour-matched feature so two-feature
  relative offsets ("is the selection ring centered on the body?") compose from `--measure` + this,
  instead of hand-rolled circle-fit scripts. See the annulus-constraint recipe in `reference.md`
  (unrelated same-hue pixels — lensed star arcs, UI accents — otherwise poison the fit).
- **Machine-readable freeze gaps** (#70) — the freeze-gap list is human-readable on stderr; a
  `t_start,dur_ms` CSV would let it be plotted against an app's own timing marks. Deferred over an
  output-shape choice: the `--cadence` stdout is already the `t,unique_frames,fps` CSV, so a second
  table needs either a separate `--freeze-csv` sink or a delimiter that won't confuse consumers.
- **Two-timestamp centered overlay / contour diff** — `--strip` is side-by-side; a matched-scale
  centered overlay (or edge diff) would show whether two features align.
- **Event alignment for compare** (`--align-on scene`) — `--compare-videos` aligns by phase fraction;
  align on a detected cut/event when it lands at a different fraction. (The global `--t0` session
  offset shipped in 1.11.0, #96; this remaining idea is per-clip *event* alignment for the A/B sheet.)
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
  `pytest` enforces the version↔CHANGELOG sync, not just the standalone bash runner. The managed
  `CLAUDE.md` (1.6.0) funnels tool feedback to the marketplace's **issues** (not stray branches),
  leaves tagging/releasing to a human, and handles branch-pinned web sessions; the scaffolded suite's
  CHANGELOG check is anchored to a real `## [version]` heading and a script-less `package.json` gets
  `npm test` wired to `node --test`.

**Weaknesses / ideas (not yet built)**
- Requires `python3` (no pure-bash/`jq` fallback yet).
- The native version-sync test covers JS + Python; **Cargo** (and other ecosystems) still get only
  the bash runner. And it's emitted *alongside* `tests/run-tests.sh` — could **replace** the
  standalone runner (and rewire CI to the native command) when a manifest is present, per #59.
- **Greenfield CI ships no language toolchain** (#81): `portka-standard.yml` runs `bash
  tests/run-tests.sh` with no `actions/setup-node`/`npm ci` (or python/rust). Right default for a
  docs/bash repo, but the moment a repo's `tests/cases/*.sh` invoke a real toolchain (`tsc`,
  `node --test`, `esbuild`) CI is red though green locally. When a manifest is detected, emit a
  matching setup + install step (or scaffold it commented) so buildable repos are green out of the box.
- **All-present version sources should agree** (#81): a greenfield `VERSION` (0.1.0) plus a
  later-added `package.json` silently drift — the runner binds to the top-priority source and stops
  checking `VERSION`. On re-run / when a manifest appears, drop the redundant `VERSION` or assert all
  present sources match.
- **Optional `--pages` deploy scaffold** (field report): a large share of greenfield repos are static
  front-ends whose next question is "how does this ship?" An opt-in, collision-aware `--pages` that
  drops a Pages workflow (+ `.nojekyll`) would round out the "green PR that merges and ships" story.
- **End-of-run summary**: `--portka-standard` writes across several trees; a one-line "wrote N files
  across settings/version-sync/CI" at the end would confirm scope at a glance.
- **Seed a minimal language manifest instead of bare `VERSION`** (#86): on a greenfield repo of a
  recognized language (e.g. a Python repo with no `pyproject.toml`), offer a minimal manifest — more
  idiomatic *and* it unlocks the native `test_version_sync.py` path, which is currently only emitted
  when a `package.json`/`pyproject.toml` already exists at bootstrap time. Keep it opt-in so a
  docs/bash repo still gets the bare `VERSION`.
- **Cross-check an in-code `VERSION` export** (#100): many JS libraries export a `VERSION`/`version`
  constant from their entry module (`main`/`module`); the sync binds to `package.json`/`CHANGELOG`/`README`
  only, so an in-code constant can silently drift. Optionally detect and compare it for JS/Python repos.
  Fussy (parsing an arbitrary entry module for a constant); the scaffolded native `node --test`/`pytest`
  run (1.12.0, #100) already lets a repo add its own assertion in the meantime.
- **GitHub Pages branch-deploy vs Actions-deploy is an unflagged fork** (#100): the standard (and the
  deferred `--pages` scaffold above) assume an **Actions-based** Pages pipeline, but a repo can be
  configured to **deploy from a branch root** instead — the two conflict (an Actions workflow fights a
  branch deploy). When `--pages` lands, detect which Pages mode the repo uses; for branch-deploy, skip the
  Actions workflow and just guarantee `.nojekyll` + root-served files.
- **Stop-hook should read the declared commit identity** (#98): the standard now *declares* a "Commit
  identity" convention (1.11.0), but the enforcement lives in a global `~/.claude/stop-hook-git-check.sh`
  — out of this repo's scope. Once that hook is maintained here (or shipped by a plugin), teach it three
  exemptions: skip GitHub's own squash-merge commits (`noreply@github.com`, reachable from
  `origin/main`); read the expected identity from the repo declaration instead of hardcoding
  `noreply@anthropic.com`; and report unsigned commits as INFO (not a fix-it) when `user.signingkey`
  is empty / the signer is a known hosted-env stub, or skip the signature check on squash-merge repos.

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
- **"Snippet-hijack" check** (#91): Google's live snippet can ignore a present, passing meta
  description and stitch together hidden a11y text (a visually-hidden `<h1>` + boilerplate) — common
  on full-canvas apps whose visible DOM is thin. A heuristic (meta description present + `<h1>`
  carrying an sr-only/clip class + little visible text) could INFO-flag the risk. Needs design so it
  doesn't false-positive ordinary sr-only headings on content-rich pages.
- **AEO `ItemList`/`CreativeWork` for portfolios** (#92/#97): the AI-readiness credit rewards
  FAQPage/Review/Article/HowTo, but a portfolio or gallery site's natural schema is an `ItemList` of
  `CreativeWork`s — currently unrewarded. Credit those types (and suggest them for a portfolio-classed
  target) so the advice fits creative sites, not just content/commerce ones.
- **Waterfall/size-blind render-blocking CSS check** (#97, the remaining gap): the warn itself is
  source-visible only — no fetch, so no sizes/waterfall, and it can't see an `@import` chain inside
  a stylesheet it never opens. A `--url`-mode fetch of first-party CSS would close it.
- **Runtime CSP verification** (#110, the remaining gap): the `strict-dynamic` inert-allowlist WARN
  is static; actually confirming each third-party script loads under the policy needs a headless
  browser run (the Chromium shipped for tab-PDF could be reused).
- **More source-derivable perf signals to lift `--dir` Perf off `n/a`** (#101): the Performance dimension
  reads `n/a` (starred) when a minimal site has no external scripts/stylesheets/images to score. Crediting
  more *source-level* signals — `loading="lazy"` (already), `async`/`defer` (already), plus a new
  **oversized-inline-data** check (a very large inline `<script>`/`<style>` block or `data:` URI that bloats
  first paint) — would let `--dir` mode earn a non-starred Perf grade on its own. Needs a size heuristic
  that doesn't false-positive on a legitimately self-contained single-file app.

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
Remaining ideas: the announcement channels in [docs/DISTRIBUTION.md](./docs/DISTRIBUTION.md)
(awesome-lists, posts) as releases warrant. (Shipped groundwork — Pages site, keywords,
community-directory submission — is tracked in `docs/HANDOFF.md`'s state section and CHANGELOG.)

## Repo / CI (ideas)
- **Run the `--pdf` e2e in CI**: `validate.yml` never installs a Playwright Chromium, so the
  format-tab PDF test always SKIPs there (it runs locally where `PLAYWRIGHT_BROWSERS_PATH` is
  set). A pinned `npx playwright install chromium` step would cover it, at the cost of CI time.
- **Cache CI apt packages + pin shellcheck** (audit): validate.yml apt-installs
  ffmpeg/shellcheck/tesseract on every run (~30–60s) and takes whatever shellcheck the runner
  image ships — a runner bump can inject new SC findings with zero repo changes. Cache the
  packages and pin a shellcheck version (static binary + actions/cache).
- **Run `claude plugin validate --strict` in CI** (audit): the documented release gate is
  manual-only today (RELEASING.md says so); a best-effort CI step (install the claude CLI, run
  per-plugin + marketplace) would automate it once stable in headless runners.
- **Trim `extract-frames.sh --help` further** (token audit): option entries still carry
  release/issue annotations and multi-line histories (~5.5K tokens per print); a disciplined
  1–3-lines-per-flag pass would halve it. The in-code comments keep the history.
- **Evaluator suite fixture reuse** (audit): the e2e section re-runs the same `good`/`bad`
  fixtures several times where one captured run could feed multiple greps (~seconds per run);
  same for halving the `--flow` fixture size once its verdict margins are re-verified.
