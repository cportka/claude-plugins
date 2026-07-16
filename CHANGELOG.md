# Changelog

All notable changes to this repository are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Every pull request bumps the
version and adds an entry below.

## [1.10.0] - 2026-07-16

The handoff release: triage of #94 plus a whole-repo handoff-readiness review (a multi-agent pass
over every plugin, the suite, CI, and docs — findings verified against the code before applying).
**All four plugins → 1.10.0.** MINOR: one new feature, three real bug fixes the review surfaced,
and comment/test/doc tightening throughout.

### Added (video-bug-analyzer → 1.10.0, #94)
- **`--marks <file>` — correlate the app's own instrumentation with the freeze timeline.** The one
  manual step left in every real triage round was matching analyzer-detected freezes against the
  app's `performance.mark` data by hand. `--stutter --marks perf.json` takes a JSON array of
  `{name, tMs, durMs?}` entries (ms, video clock) and annotates both the verdict and each freeze-gap
  line with the best-aligned mark — *"1000 ms freeze @1.00s — aligns with mark 'fullCompile'
  (starts 0.95s, 330 ms)"* — collapsing the diagnose-verify loop to a single read. A mark aligns
  when its span overlaps the freeze or ends within 0.5s of its start; best = most overlap, then
  nearest. Malformed/missing sidecars are a clean exit 2; `--marks` without `--stutter` errors.

### Fixed (handoff review — real bugs it surfaced)
- **tab-chord-formatter: the paste-from-web tag strip ate `<12>` guitar harmonic notation** (any
  `<...>` was treated as HTML). Tag names must start with a letter — harmonics now survive, real
  HTML still strips.
- **tab-chord-formatter: the documented form-feed songbook separator never worked in the print
  pipeline** — cleanup's `rstrip()` ate the lone `\f` (form feed is whitespace to Python) before
  `split_songs` ran, so a two-song book rendered as one. Preserved now; also `--mode` typos error
  instead of silently switching modes, and the duplicate `("prechorus", "prechorus")` literal is
  gone.
- **video-bug-analyzer: `run_palette` still used a stale pre-1.8.0 PPM parser** (no 16-bit
  handling — a 10-bit source printed garbage hexes). Deduplicated onto the hardened `_ppm_hexes`;
  output format unchanged.
- **Portability:** the last `mapfile` in each of `extract-frames.sh` and `bootstrap-repo.sh`
  replaced with `while read` (macOS system bash is 3.2), and the evaluator's `<title>` extraction
  no longer uses sed's GNU-only `I` flag (BSD sed errored).

### Changed (CI)
- **`validate.yml`'s `push` trigger is restricted to `main`.** An unrestricted `push:` ran every
  PR twice (both events) and made `version-bump-guard`'s push-event base (`HEAD^`) go red on any
  multi-commit PR whose later commit touched a plugin without re-bumping — the false positive that
  forced branch squashing. PR branches now run once (the thorough diff-vs-base check); pushes to
  `main` keep post-merge validation.

### Added (repo)
- **[docs/HANDOFF.md](./docs/HANDOFF.md)** — the read-this-first maintainer handoff: what the repo
  is, how work flows (the Portka standard), the versioning invariant and where it's enforced, test
  conventions, the sharp edges (Pages flakes, the egress proxy, bash 3.2/`set -u` array gotchas,
  the ffmpeg subtleties), and the state at handoff.
- Why-comments at every spot the review flagged as session-history-only knowledge: the evaluator's
  `weight_for`↔`sec` byte-match contract (now also CI-enforced by a test), the suite's deliberate
  no-`set -e` and the bash-3.2 exit-0 guard, `--loop-check`'s verdict bands, bootstrap's twin
  `detect_version` implementations, `NO_WRITE` vs `DRY_RUN` convention, the `VBA_MARKETPLACE_JSON`
  name, and the title-regex looseness in the tab formatter. The suite header now describes the
  whole suite; the dogfood gate fails (not vanishes) if the evaluator moves.

### Tests
- New coverage: `--marks` alignment (right mark chosen, unrelated one ignored; guards); the
  form-feed songbook split; `<12>` harmonic preservation; `--no-dedent` + `--mode` validation;
  `--auto-update`'s merge invariant; `--scope user` scoping; and the evaluator label↔weight sync.
  Suite: 234 passed, 0 failed, 1 skipped.

## [1.9.0] - 2026-07-15

Triage of four field reports (#89, #90, #91, #92 + the kevin-website default-branch finding) and one
review nit carried from 1.8.0. `app-website-evaluator`, `video-bug-analyzer`, and `repo-bootstrap`
all → 1.9.0 (`tab-chord-formatter` stays 1.2.0). MINOR: fixes + additive behavior, all
backward-compatible.

### Fixed (app-website-evaluator → 1.9.0, #90)
- **"UNSCORED: unbound variable" on a fully-scored run.** The scorecard arrays were `declare -a`'d
  but `UNSCORED` only ever gained elements when a dimension was *n/a* — on a fully-assembled site
  where every dimension scores, `${#UNSCORED[@]}` under `set -u` errored (bash 5.2). All four arrays
  are now initialized empty-but-set. Every prior test fixture left ≥1 dimension unscored, which is
  how it slipped through — a fully-scored regression fixture now guards it.

### Added (app-website-evaluator → 1.9.0, #91)
- **Filtered-proxy honesty: probe misses downgrade to INFO.** When the page GET itself fails (the
  "network is filtered" signal), a non-200 on robots.txt/sitemap.xml is ambiguous — a genuine 404 or
  the proxy — so those misses now report `INFO could not verify` instead of FAIL, and a note says
  why. A 200 still credits (a filter can't fake it). No more chasing a robots.txt the repo ships.
- **`--url` + `--html` hybrid.** Score the HTML you already fetched *while* running the live origin
  probes (headers, robots/sitemap/security.txt) — one run, one honest scorecard, instead of two runs
  mentally merged. `--headers` still pairs with `--html`-only; `--dir` combines with neither.
- **The header-fetch recipe is surfaced.** The script's UA'd `curl -sSI` often passes filters a bare
  curl doesn't; when the page GET fails but the header fetch worked, the exact reusable command is
  printed (and documented in `--help`) for `--html --headers` composition.
- Docs: a template-vs-built nuance note (evaluate `dist/`, not a Vite/webpack source template).
  Deferred → IMPROVEMENTS: the "snippet-hijack" heuristic (#91 item 5).

### Fixed (video-bug-analyzer → 1.9.0, #89)
- **VFR nominal-fps red herring.** macOS screen recordings carry `r_frame_rate` 240/1 as a
  *timebase*; the smoothness banner compared against it and called a healthy ~47 fps control clip
  "~80% dropped — likely choppy". A nominal ≥ 200 with plausible content fps now reads *"VFR/high-
  refresh capture: nominal 240 is the container timebase, not a target"* — while real display
  refreshes (90/120/144) keep the existing jank warnings (#83's contract is regression-tested).
- **`--stutter` now leads with a one-line verdict** — the worst freeze + median window fps (the
  actionable read), e.g. `verdict: 1133 ms freeze @2.85s; ~44 fps median otherwise` — instead of
  burying the freeze list at the bottom. The cadence headline flags a VFR timebase too.
- **`--freeze-min <sec>`** tunes the freeze-gap threshold (default 0.1s) — raise it to mute the
  ~100 ms borderline gaps a healthy 40–50 fps VFR capture produces.
- **Naming aligned:** `--stutter` is the primary name everywhere (README, SKILL table, report
  header "Stutter (cadence):"); `--cadence`/`--fps-drops` remain aliases.
- `reference.md` gains the **two-feature offset recipe** (constrain the second fit to an annulus
  around the first feature — unrelated same-hue pixels otherwise poison it); a built-in
  `--track-color` is deferred → IMPROVEMENTS.

### Fixed (video-bug-analyzer → 1.9.0, #85 review nit)
- `--palette --segments N` **without** `--over-time` now errors with the correct invocation instead
  of silently ignoring `--segments` (the wrong-mode footgun from the other direction).

### Added (repo-bootstrap → 1.9.0, kevin-website field report)
- **Default-branch normalization.** The standard assumes `main` (the workflow says "Update `main`
  first"), but a fresh `git init` can leave a repo on `master` — and the standard silently never
  engages. `--portka-standard` now renames the branch to `main` when it can't break anything (an
  unborn branch, or a repo with no remote), prints the exact migration commands when a remote
  exists (`git branch -m` + `git push -u` + `gh repo edit --default-branch main`), and hints
  `git init -b main` for a non-git dir. Dry-run aware.

### Changed (feedback form, #92)
- The **Plugin feedback** dropdown gains *"multiple plugins / cross-cutting"* so a field report
  spanning plugins doesn't have to mis-file under one (the form's one-plugin limit was itself the
  #92 meta-feedback). The form-sync test knows both escape options.

### Tests
- New coverage: the fully-scored #90 fixture (no unbound error, unstarred grade); filtered-proxy
  INFO downgrade + header-recipe hint; the `--url --html` hybrid; input-combo guards; the VFR
  240-timebase banner (with the #83 120 Hz contract still asserted); the `--stutter` verdict-first
  ordering; `--freeze-min` (raises threshold, rejects non-numbers); the `--segments` guard; and
  branch normalization (unborn `master` renamed; pushed `master` untouched + exact commands).
  Suite: 227 passed, 0 failed, 1 skipped.

## [1.8.0] - 2026-07-10

Triage of #85 — `video-bug-analyzer` as an art/aesthetic-reference tool (mining a library of animated
GIF loops for palette + motion). `video-bug-analyzer` → 1.8.0 (`repo-bootstrap` and
`app-website-evaluator` stay 1.7.0, `tab-chord-formatter` 1.2.0). MINOR: two new analysis modes, both
built on existing plumbing, plus a framing tweak.

### Added (video-bug-analyzer → 1.8.0, #85)
- **`--palette --over-time` — the colour *arc*, not one flattened ramp.** A seamless art loop often
  sweeps through very different colour states (powder-blue → magenta/cyan → back); a single dominant
  palette hides that. `--over-time` splits the clip into N windows (`--segments`, default 8) and prints
  each window's palette as `t<sec>  #hex #hex …`, so the colour *journey* is visible. Reuses
  `palettegen` per window + the existing PPM swatch reader; honors `--colors`, `--start`/`--end`.
- **`--loop-check` — is this a clean *seamless* loop?** Reports the **mean absolute pixel difference**
  between the first and last frame (0 = identical wrap; <1% "loops cleanly", <4% near-seamless, else a
  visible seam) and writes a `loopcheck.png` strip (first │ last) so the seam is visible. Built on the
  PPM reader + the `--strip` hstack. Broadly useful to anyone making loops, GIFs, or shader toys.
- **"Also useful for" framing (#85 item 5, echoing #14).** The header/README/marketplace now call out
  the non-bug uses — art/colour reference, asset/QA — and that **GIF input works on every mode**, so
  the tool surfaces for an aesthetic-reference task, not just "bug/glitch/crash".

### Deferred to [IMPROVEMENTS.md](./IMPROVEMENTS.md)
- `--montage a.gif,b.gif,…` — an N-way library survey (one representative tile per input), for
  eyeballing a whole collection at once (distinct from the pairwise `--compare-videos`).
- `--palette` (and `--over-time`) as an SVG/PNG **swatch sheet** artifact, not just hex text.

### Pre-merge adversarial review hardening
A multi-agent review of the new ffmpeg/python code caught several real edge cases, all fixed:
- **A window that decodes zero video frames no longer fabricates a stale palette** (the `-y` fix
  wasn't enough — ffmpeg's image muxer opens lazily, so the prior window's file survived): the span
  is clamped to the **video** stream duration and `win.ppm` is removed before each window.
- **A clip whose audio outlasts its video** no longer sends `--loop-check`'s tail seek into an
  audio-only region (a false "could not extract" error): both modes use the **video** stream
  duration, not `format=duration`.
- **A 10-bit/HDR source** (ffmpeg emits a 16-bit `rgb48be` PPM) is read correctly — `-pix_fmt rgb24`
  on frame grabs plus a parser that takes the high byte of each 16-bit sample — instead of garbage
  hex / a diff that ignores half the frame.
- A first/last frame **size mismatch** (a mid-clip resize) is reported as such rather than diffing
  misaligned pixels; a truncated/malformed PPM header no longer crashes the parser; `--segments` is
  capped at 200; and every ffmpeg write uses `-y -nostdin`.

### Tests
- New coverage: `--palette --over-time` prints a per-window arc whose windows genuinely **differ** (a
  regression guard for the stale-frame bug); `--loop-check` calls a static clip a clean loop (+ writes
  the strip) and a hue-sweeping clip a seam; a clip whose **audio outlasts its video** survives both
  modes (no stale rows, no false error); `--over-time` without `--palette` exits 2; and both dry-runs
  print their commands. Suite: 217 passed, 0 failed, 1 skipped.

## [1.7.0] - 2026-07-10

Triage of #86 (two independent cold-start field reports on the Portka standard). `repo-bootstrap` →
1.7.0 and `app-website-evaluator` → 1.7.0 (`video-bug-analyzer` stays 1.6.0, `tab-chord-formatter`
1.2.0). MINOR: a load-bearing standard-text fix + a new crawlability caveat, both backward-compatible.

### Fixed (repo-bootstrap → 1.7.0, #86) — the standard now drives the PR → merge flow hands-off
1.6.0's branch-pinned note (*"open the PR … and stop at step 3; a human merges"*) both **contradicted
step 4** (*"merge the PR automatically"*) and left the hosted harness's *"don't open a pull request
unless the user explicitly asks"* default un-defused — so in two separate cold-start web sessions the
agent stalled at "branch pushed" and asked whether to open a PR at all. The `--portka-standard`
`CLAUDE.md` template (and this repo's own copy) now resolves both:
- **This committed file is the "explicit ask."** A new note states plainly that the standard's
  presence *is* the repo owner's standing instruction to open a PR — so open it **proactively** at
  step 3 for every change, never stop at "pushed" and ask.
- **The agent merges on green.** Merging happens through GitHub, not a local push to `main`, so a
  branch-pin doesn't block it; the branch-pinned modification is now **only** skipping the step-1
  `main` checkout. The self-contradicting "a human merges" is gone. An adversarial review of the new
  wording hardened three seams: the verb now matches ("forbids **pushing** directly to `main`" ↔ "not
  a local push"); a merge that GitHub legitimately **refuses** (branch protection, a required review
  the author can't give, token scope) falls back to handing back the green PR — *never* self-approve
  or admin/force-merge around it; and "green" now requires checks to have **registered and finished**
  (an empty/still-populating check list is not green). "Merging the PR is not releasing" is called out
  so it doesn't collide with the manual-tag/release rule.
- **A discoverable onboarding entry point.** The README now has an *"Onboard a new repo onto the
  Portka standard"* section pointing at `repo-bootstrap --portka-standard` as the one command that
  scaffolds the whole setup (#86 item 3).

### Fixed (app-website-evaluator → 1.7.0, #86 item 5) — project-Pages robots.txt is host-root-only
A GitHub **project** Pages site (`https://user.github.io/repo/`) serves `robots.txt`/`sitemap.xml`
from a subpath that crawlers never read — only the **host root** (`https://user.github.io/robots.txt`)
is honored. `evaluate-site.sh --url` now detects a subpath deploy, says so, and **probes the host
root** for `robots.txt`, warning when a subpath robots.txt would be silently ignored. Documented in
`reference.md`.

### Deferred to [IMPROVEMENTS.md](./IMPROVEMENTS.md)
- Offer a minimal language manifest (e.g. `pyproject.toml` for a detected Python repo) instead of a
  bare `VERSION` on greenfield bootstrap — it would unlock the native version-sync test path (#86 item 4).

### Tests
- New coverage: the standard's `CLAUDE.md` authorizes a proactive PR + agent-merge-on-green with no
  self-contradiction (the old "a human merges"/"stop at step 3" wording is asserted **gone**); and
  `--url` on a subpath deploy flags the caveat and probes the host-root robots.txt (via a fake `curl`).
  Suite: 212 passed, 0 failed, 1 skipped.

## [1.6.0] - 2026-07-08

Triage round: `repo-bootstrap` #81 + a mis-filed field report, and `video-bug-analyzer` #83.
`repo-bootstrap` → 1.6.0 and `video-bug-analyzer` → 1.6.0 (`app-website-evaluator` stays 1.4.0,
`tab-chord-formatter` stays 1.2.0). MINOR overall: new Portka-standard guidance + backward-compatible
scaffold correctness fixes and a heuristic refinement.

### Portka standard — funnel feedback, leave releases to humans, respect branch-pinned sessions
The workflow `CLAUDE.md` that `repo-bootstrap --portka-standard` installs (and this repo's own copy)
gained three standing rules, prompted by a field report that arrived as a *branch on this repo*
instead of an issue — the funnel this fixes:
- **Feedback goes to the marketplace's issue tracker, not stray branches.** A new "Reporting feedback
  on the tools you use" section tells an agent to file a **Plugin feedback** issue on
  `cportka/claude-plugins` (with a ready `gh issue create … --label feedback` command) and to treat
  a co-located marketplace repo as **read-only** — never open a branch/commit/PR on it. `gh issue` is
  added to the permissions allowlist so the command is pre-approved.
- **Releasing is the user's manual step.** Prepare the release in the PR (version + CHANGELOG), but
  never create/push a git tag or run `gh release` — hosted/sandbox environments block tag pushes, so
  it just fails. The user tags and cuts the release from the GitHub web UI after merge.
- **Branch-pinned sessions.** Step 1 now acknowledges hosted runs (e.g. Claude Code on the web) where
  the harness pins work to a feature branch and forbids `main`: skip the `main` checkout, open the PR
  from the assigned branch, and let a human merge — resolving the update-main-first vs. never-touch-main
  tension the field report hit.

### Fixed (repo-bootstrap → 1.6.0, #81 + field report)
- **Scaffolded CHANGELOG check is now anchored to a real release heading.** The generated
  `tests/run-tests.sh`, `version-sync.test.mjs`, and `test_version_sync.py` matched the version as a
  bare substring — so a URL, a prose mention, or an unrelated version satisfied it and a CHANGELOG
  with no `## [x.y.z]` section for the current version could ship green. All three now require a
  `## [version]` heading (dots escaped, brackets optional).
- **`npm test` is wired up for manifest repos.** A `package.json` with no `test` script (the common
  case the #59 native binding targets) now gets `"test": "node --test"` merged in (never clobbering an
  existing one), so the repo's own command runs the sync test — and the "run with" hint uses bare
  `node --test`, never the `node --test tests/` form that throws `ERR_MODULE_NOT_FOUND`.

### Fixed (video-bug-analyzer → 1.6.0, #83)
- **The `smoothness:` banner no longer cries "choppy" on a high-refresh capture.** A 120 Hz ProMotion
  recording of a 60 fps app reads as ~57 effective fps vs 120 nominal — which the heuristic reported
  as "~52% frames dropped/duplicated — likely choppy," a false positive (the duplicated frames are
  expected when the display refreshes faster than the app renders, not jank). When the nominal rate is
  a high display refresh (≥ 90 Hz) and the effective rate lands near a common animation cadence
  (~30/~60 fps), the banner now says e.g. *"~57 fps content on a 120 Hz capture — normal for a 60 fps
  app, not choppy; --motion/--pacing to check for real stutter."* Irregular shortfalls (effective not
  near a common cadence) are still flagged, and normal-refresh captures are unchanged.

### Deferred to [IMPROVEMENTS.md](./IMPROVEMENTS.md)
- Greenfield `--portka-standard` CI ships no language toolchain (no `setup-node`/`npm ci`), so a repo
  whose `tests/cases/*.sh` call a real toolchain is red on the runner though green locally (#81).
- A bare `VERSION` plus a later-added manifest can silently drift (the runner binds to the
  top-priority source only); an optional `--pages` deploy scaffold for greenfield front-ends; and an
  end-of-run "wrote N files" summary.

### Tests
- New coverage: the scaffolded CHANGELOG check rejects a loose-only version mention (bash + node:test);
  `scripts.test` is wired for a script-less `package.json`; the managed `CLAUDE.md` carries the
  feedback-funnel, manual-release, and branch-pinned guidance; `gh issue` is in the allowlist; and the
  `smoothness:` banner treats a 60 fps app on a 120 Hz capture as normal while still flagging a real
  shortfall (a fake `ffprobe` injects the rates). Suite: 210 passed, 0 failed, 1 skipped.

## [1.5.0] - 2026-07-06

Triage of the DedTxt dogfood feedback #79 — `app-website-evaluator`'s **first real `--dir` run on a
shipping static site** (DedTxt scored `A*` 100/100 over 82% of weight). `app-website-evaluator` →
1.4.0 (`video-bug-analyzer` stays 1.4.1; `repo-bootstrap` and `tab-chord-formatter` unchanged at
1.2.0). MINOR: a new pre-fetched input mode + a source-visible Security sub-score, both
backward-compatible.

### Added (app-website-evaluator → 1.4.0, #79)
- **`--html <file|-> [--headers <file|->]` — score already-fetched HTML without curl reaching the
  origin.** The primary `--url` mode needs `curl` to hit the origin, but web/remote Claude Code runs
  behind an egress proxy that 403s arbitrary hosts (DedTxt was blocked outright), so the whole live
  path was unavailable. Now an agent that fetched the page another way — an MCP tool, a headless
  browser, `web_fetch` — can pipe it in (`… | evaluate-site.sh --html -`) or pass a file, and pair
  `--headers` (e.g. `curl -sSI` output) to still score the live **HSTS / CSP / X-Content-Type-Options
  / Referrer-Policy** header checks. Exactly one of `--url` / `--dir` / `--html`; `--headers` requires
  `--html`; `--html -` and `--headers -` can't both read stdin.
- **Source-visible Security sub-score — Security is no longer a blanket `n/a` off the network (18% of
  weight).** A static host *can't* set HTTP headers, but it ships controls that are visible in the
  build: a `<meta http-equiv="Content-Security-Policy">`, a `/.well-known/security.txt`, and its
  third-party `<script>` posture. `--dir` / `--html` now score these — a `<meta>` CSP and a shipped
  `security.txt` are credited, and **zero third-party `<script>` origins** (all scripts same-origin /
  relative) is scored as the real minimal-supply-chain-surface win it is; third-party origins are
  listed with a "pin with SRI" nudge. Header CSP still wins when present (the `<meta>` check stands
  down to avoid double-counting). A truly control-free static page still reads `n/a` — honest.
- **`--dir` source-tree foot-gun guard.** Many sites generate `robots.txt` / `sitemap.xml` /
  `.well-known/security.txt` at build time, so pointing `--dir` at `src/` false-negatives Crawlability
  *and* Security. When `--dir` looks like a source tree (a `package.json` build script, or a `src/`
  with no root robots.txt/sitemap.xml), the tool now prints a NOTE to target the built/deployed output
  (`dist/`, `build/`, `out/`).
- The scorecard's partial-coverage footnote now says source-visible Security *is* scored and only the
  live signals (HTTPS / response headers, real perf numbers) need the origin — via `--url`,
  `--html --headers`, or Lighthouse.

### Docs
- `SKILL.md` and `reference.md` document the three input sources, call out the build-vs-source
  gotcha explicitly (generated robots/sitemap/security.txt), and explain the source-visible Security
  signals; README gains a `--html`/proxy example and the plugin-table copy is refreshed.

### Tests
- New coverage: `--html` scores a pre-fetched page (file and stdin) with no origin fetch; `--headers`
  drives the security-header checks in `--html` mode; the argument guards (`--headers` without
  `--html`, both-stdin) exit 2; a `<meta>`-CSP + `security.txt` + no-third-party-scripts build makes
  Security a scored dimension; third-party `<script>` origins are flagged while same-origin `src`s are
  ignored; and a source-tree `--dir` warns to point at the build. The existing dir-mode star / #63
  coverage tests still hold (a control-free page keeps Security `n/a`).

## [1.4.1] - 2026-07-05

Triage of round-6 dogfood feedback #70. `video-bug-analyzer` → 1.4.1 (others unchanged). PATCH: a
correctness refinement to `--cadence`, backward-compatible.

### Fixed (video-bug-analyzer → 1.4.1, #70)
- **`--cadence`/`--stutter` no longer lets a recording's pre-roll dominate "choppiest windows".** A
  clip that starts on a black screen / URL bar / static splash reads (after `mpdecimate`) as a run of
  `0 fps` windows, which previously topped the choppiest-windows ranking and competed with the
  freeze-gap section — pointing a reader at the pre-roll seconds instead of the real stutter. On an
  unscoped scan the tool now detects that leading static/near-black **lead-in**, excludes it from the
  ranking, and notes where content starts (a frozen splash in the lead-in still surfaces in the
  freeze gaps, which correctly caught it). The freeze-gap pass — which the reporter confirmed mapped
  1:1 onto the app's own `compile`/`prime` timing marks — is unchanged. Scoped scans
  (`--start`/`--end`) are unaffected; a continuous clip still gets the generic scoping hint (#64).
- The reporter's low-priority "machine-readable freeze-gap CSV" ask is recorded in
  [IMPROVEMENTS.md](./IMPROVEMENTS.md) (it needs an output-shape decision so a second table doesn't
  confuse consumers of the existing `t,unique_frames,fps` stdout).

Pre-merge adversarial review hardening: the lead-in is only treated as pre-roll when it is genuinely
near-static (idle windows **and** a busiest window far quieter than the content) — so active content
that merely **freezes early** (active → 0 fps → active) is not mistaken for pre-roll and its frozen
windows stay in the ranking, which is exactly what `--cadence` must headline.

### Tests
- New coverage: a 3s-black-pre-roll + 2s-content clip confirms the dead lead-in is excluded from the
  choppiest windows, the content-start note fires, and the freeze-gap pass still reports the frozen
  splash; an active-then-early-freeze clip confirms the frozen windows are **kept** in the ranking
  (not misread as pre-roll) — while the continuous-clip #64 scoping behavior is preserved.

## [1.4.0] - 2026-07-05

Triage of the round-6 dogfood feedback (#69). `video-bug-analyzer` → 1.4.0 (`app-website-evaluator`
stays 1.3.1; `repo-bootstrap` and `tab-chord-formatter` unchanged at 1.2.0). MINOR: two new
analysis modes, both backward-compatible, built on the existing motion-sampling / thresholding
plumbing.

### Added (video-bug-analyzer → 1.4.0, #69)
- **`--flow` — motion *character*, not just magnitude.** `--motion`/`--diff` can't tell "a disk
  spinning in place" from "a disk spiralling inward" — both light up the same. `--flow` computes a
  coarse block-matching optical flow between sampled frames and decomposes it about a center into
  its **rotational** (curl / "swirl") and **radial** (divergence / "suck") components, printing
  `t,speed,curl,div`. Reads: spinning in place = `|curl|` high, `div≈0`; sucking inward = `div<0`;
  spiralling inward ("suck + twirl") = high `curl` **and** `div<0`; panning = both ≈0. The headline
  classifies the dominant pattern. Center from `--flow-center fx:fy` (default frame center) or
  `--crop`; `--fps` sets the rate (raise it for fast motion). Pure Python (stdlib — no numpy/opencv);
  full-search matching with an interior-block restriction so the field stays unbiased, frames fit to
  160×160 (both axes) and the sampled-frame count is **capped** (with a note) so a long recording
  can't hang — scope with `--start`/`--end`. Textured subjects (a churning disk) are its sweet spot;
  outward *expansion* is under-measured (block matching assumes translation), so inward "suck" and
  rotation are the reliable reads.
- **`--occupancy` — subject extent.** Answers "how much of the frame does the subject actually
  fill?" — the "present but too small to see" case brightness/colour modes miss. Thresholds each
  sampled frame above the background and prints `t,coverage_pct,x,y,w,h` (coverage fraction +
  bounding box). "The galaxy is tiny" becomes `coverage ≈ 3%`, watchable as a camera pulls back.
  `--occupancy-threshold N` sets the cutoff, `--occupancy-dark` flips to a dark subject; the
  counterpart to `--blackdetect`'s empty-frame threshold. Honors `--crop`, `--start`/`--end`.
- The multi-clip batch idea (#69's third, lower-priority ask — run the same modes over N clips,
  one report keyed by clip) is recorded in [IMPROVEMENTS.md](./IMPROVEMENTS.md) rather than built
  this round (it overlaps `--compare-videos`).

### Tests
- New coverage: `--flow` classifies rotating noise as spin-in-place and a zoom-out as inward "suck"
  (block-matching validated against rotation/zoom/pan/static archetypes); `--occupancy` reads a low
  coverage % + the "too small" hint for a small subject and high for a big one; dry-run command +
  CSV-header pins for both; the `--flow` frame cap and the numeric `--occupancy-threshold` guard.
- Pre-merge adversarial review hardening: `--flow` fits frames to 160×160 and caps the sampled-frame
  count (an unbounded full-search could hang a long/portrait clip); a truncated PGM (killed ffmpeg)
  is skipped instead of raising `IndexError` (also in `--measure`/`--occupancy`); a non-integer
  `--occupancy-threshold` gives a clean error, and a decimal cutoff is tolerated; a bad
  `--flow-center` (out-of-range / non-finite) falls back to the frame center.

## [1.3.1] - 2026-07-03

Triage of the round-5 dogfood feedback (#66, #67). `app-website-evaluator` → 1.3.1 and
`video-bug-analyzer` → 1.3.1 (`repo-bootstrap` and `tab-chord-formatter` unchanged at 1.2.0).
PATCH: correctness + a smarter hint, all backward-compatible.

### Fixed (app-website-evaluator → 1.3.1, #67)
- **Multi-line (Prettier) tags are no longer read as missing.** Prettier splits a long tag across
  lines, but the tag-presence checks grepped line-by-line — so an attribute-per-line
  `<meta name="viewport" …>`, `<meta name="description" …>`, or `og:description` reported FAIL/WARN
  on a page that had them. Checks now match against a **whitespace-collapsed** copy of the HTML, so
  a multi-line tag matches identically to a single-line one. (Content extraction like the `<title>`
  length still reads the raw HTML.)
- **`type="module"` scripts are no longer flagged render-blocking.** Vite emits
  `<script type="module" src=…>`, which defers by spec — but the performance check warned "external
  `<script>` without async/defer". It now enumerates each `<script …>` tag and counts as
  render-blocking only an external `src` script that is **not** `async`/`defer` **and not**
  `type="module"`, so a page mixing a blocking classic script with deferred modules is judged on the
  classic one (and reports how many).

### Fixed (video-bug-analyzer → 1.3.1, #66)
- **`--motion` now honors `--crop`.** It previously measured whole-frame motion and silently ignored
  `--crop`, so the suggested "crop to the dust region" workaround was a no-op. Cropping now measures
  motion over just that ROI — lifting a subtle signal (drifting motes, a slow spinner) above the
  whole-frame downscale noise floor where it otherwise reads ~0 and is indistinguishable from frozen.

### Added (video-bug-analyzer → 1.3.1, #66)
- **Amplitude-floor hint.** When the peak inter-frame delta stays under ~3/255, the `--motion`
  headline says the amplitude is near the floor and — if not already cropped — points at
  `--crop W:H:X:Y` to isolate the region. Cropped and still near-zero, it reports the region as
  genuinely static rather than scale-quantized, making `--motion --crop` a clean A/B "did my fix add
  motion here?" instrument. Documented in `reference.md` and `--help`.

### Tests
- New coverage: multi-line/Prettier `<meta>` tags credited + `type="module"` treated as deferred
  while a classic `<script src>` still WARNs (#67); `--motion` honors `--crop` (dry-run chain +
  runtime), and the amplitude-floor hint fires unscoped and reports a cropped region as static (#66).

## [1.3.0] - 2026-07-02

Triage of the round-4 dogfood feedback (#62, #63, #64). `video-bug-analyzer` → 1.3.0 and
`app-website-evaluator` → 1.3.0 (`repo-bootstrap` and `tab-chord-formatter` unchanged at 1.2.0).
MINOR: new capabilities, all backward-compatible.

### Fixed (video-bug-analyzer → 1.3.0, #64)
- **Runs no longer overwrite each other.** The per-video default dir plus sequential names
  (`contact_0001.png` …) meant a second extraction over a different time window silently clobbered
  the first (the reporter lost their 0–6s overview to a 4.4–6.4s burst). If the output dir already
  holds PNGs, the new run is written into a **mode+window-tagged subdirectory** (e.g.
  `dense_1-2/`, counter-suffixed `dense_1-2_2/` when the same mode+window repeats) with a note —
  earlier frames stay untouched. Applies to explicit `--out` and the default dir alike; also under
  `--dry-run` (so printed commands match a real run), glob-safe for bracketed video names
  (`clip [1].mp4`), and skipped for analysis modes that write no PNGs.
- **`--cadence`/`--stutter` now flags an unscoped scan**: when run without `--start`/`--end`, the
  choppiest-windows summary notes that pre-roll (URL-bar typing, tab switching) can top the
  ranking and suggests re-running scoped — exactly the false-positive the reporter hit.

### Added (video-bug-analyzer → 1.3.0, #62)
- **`--stack` — ROI time-stack.** Crop a fixed band (`--crop`, required — a scrub bar, HUD, status
  row) and tile the samples **vertically** into `stack_0001.png`, so one image reads that region's
  evolution top-to-bottom across the clip. This is the "region-of-interest time-stack" view the
  scrub-bar dogfood assembled by hand and asked to have first-class. Honors `--start`/`--end`,
  `--fps`, `--label`; spills past 48 rows.
- **`--check-update`** compares the installed version against the marketplace's `main`
  (`plugin.json` fetched raw) and prints the `claude plugin update` command when trailing —
  closing #62's "installed rc.6, didn't know it was stale" gap. SemVer-aware (`sort -V`): a dev
  copy that is *ahead* of the marketplace is reported as such, not told to downgrade. Degrades
  gracefully offline (survives `set -euo pipefail` on a failed fetch); needs no `--video`. (#62's other friction — a freshly enabled plugin not surfacing mid-session —
  is the documented platform constraint: plugins load at session start; see IMPROVEMENTS.md.)

### Fixed (app-website-evaluator → 1.3.0, #63)
- **The overall grade is now coverage-honest.** Dir mode can't assess Security (18% of weight), but
  the headline read "overall 100/100 (A)" as if it had. A partial-coverage overall is now
  **starred** — `overall 100/100 (A*)` — with `* computed over N% of weight; unscored: …` and a
  dir-mode hint to run `--url` (or Lighthouse) for Security + live perf. `--json` gains
  `overall.coverage_weight_pct` + `overall.unscored`.

### Added (app-website-evaluator → 1.3.0, #63)
- **AI-readiness now parse-validates JSON-LD**: a block that fails to parse **FAILs** (invalid
  JSON-LD is silently ignored by assistants/search — worse than none), clean blocks pass, and
  **rich schema types** (FAQPage / HowTo / Review / AggregateRating / Product / Article / …) are
  credited as a strong AEO signal, with an info nudge when only basic types are present.

### Tests
- New coverage: collision guard preserves run 1 + redirects run 2; `--stack` e2e + dry-run + early
  `--crop` validation; `--check-update` online/offline; the cadence scoping hint (fires unscoped,
  silent scoped); the starred partial-coverage scorecard + `--json` coverage fields; JSON-LD
  parse-validation (broken → FAIL, FAQPage → credited).

## [1.2.0] - 2026-06-26

A feature wave — one high-impact addition per plugin, so all four bump to 1.2.0 (the marketplace
release): a printable PDF songbook (`tab-chord-formatter`), a standardized scorecard
(`app-website-evaluator`), a from-scratch frame-pacing mode (`video-bug-analyzer`), and native
version-sync tests (`repo-bootstrap`). MINOR, since each is a backward-compatible new capability.

### Added (tab-chord-formatter → 1.2.0)
- **Print mode → PDF songbook.** `format-tab.py` now has two modes: **screen** (the existing plain
  text) and **print**, which renders a clean, **single-font/size monospace PDF** (Courier New 10pt
  by default) via headless Chromium — `--print --pdf out.pdf`. Handles a **multi-song songbook**
  (split on `Artist – Title` lines or form-feeds), with **`--songs-per-page N`** (default 1 song per
  page), `--font`, `--size`, and `--dedent` (on by default — strips each song's common leading
  indentation so the margin is consistent and wide lines don't overflow). `--html` emits
  print-ready HTML for environments without Chromium.

### Added (app-website-evaluator → 1.2.0)
- **Standardized scorecard.** Every check is PASS (1.0) / WARN (0.5) / FAIL (0.0); each **dimension
  scores 0–100 with a letter grade** (A ≥90 … F <60), and the report ends with a **weight-averaged
  overall** grade — a repeatable answer to "how good is my site?". **`--json`** emits the same
  scorecard machine-readably (stdout; the human report → stderr). The SKILL/reference now define the
  rubric and a consistent report order (classification → scorecard → top fixes → by dimension →
  growth → strengths).

### Added (video-bug-analyzer → 1.2.0)
- **`--pacing` — a from-scratch timing mode.** Where `--cadence`/`--stutter` count unique *content*
  (mpdecimate), `--pacing` reads the actual per-frame **presentation timestamps** (ffprobe) and
  reports the interval between displayed frames — so **uneven timing / jank / VFR / a long-frame
  hitch is caught even when every frame's content differs**. Emits `t,interval_ms` and headlines the
  median/p95/max interval plus the worst hitches.

### Added (repo-bootstrap → 1.2.0)
- **Native version-sync test.** When `--portka-standard` detects a **`package.json`** or
  **`pyproject.toml`**, it now also emits the version↔CHANGELOG sync check **in the repo's own test
  runner** — `tests/version-sync.test.mjs` (`node --test`) or `tests/test_version_sync.py`
  (`pytest`/`unittest`) — so `npm test` / `pytest` enforces it, not only the standalone bash runner
  (the #59 reporter's recommendation). Cargo support and "fully replace the bash runner" stay on the
  roadmap.

### Tests
- New per-plugin coverage: tab-chord print/HTML/PDF + songs-per-page + dedent; the evaluator's
  scorecard (complete > bare) + `--json` validity; `--pacing` dry-run + e2e; and the native
  node:test / unittest version-sync emission (both run and pass). Suite: 126 passed.

## [1.1.2] - 2026-06-25

Bundles the feedback that arrived right after 1.1.1: makes `--portka-standard` safe on a mature
repo (#59) and surfaces FPS-stutter analysis in `video-bug-analyzer` (#56). `repo-bootstrap` →
1.1.2, `video-bug-analyzer` → 1.1.2 (`app-website-evaluator` 1.0.1, `tab-chord-formatter` 1.0.0
unchanged). Also closes #55 — its release-hygiene recommendations all shipped back in 1.0.3.

### Fixed (repo-bootstrap → 1.1.2, #59)
- **`--portka-standard` no longer regresses a mature repo.** It now **binds the version sync to the
  repo's existing source of truth** — `package.json` / `pyproject.toml` / `Cargo.toml` / a bare
  `VERSION` / a README `**Version:**` line — instead of always seeding `VERSION=0.1.0`. On a repo
  whose `package.json` is `0.22.x`, the old scaffold seeded a contradictory `VERSION` and shipped a
  **red** `run-tests.sh` (it grepped for a `## [0.1.0]` / `**Version:** 0.1.0` that didn't exist);
  the scaffolded runner now reads the native version and checks the README line **only when one
  exists**.
- **The scaffolded CI no longer collides with existing CI.** It is written as a specifically-named
  `portka-standard.yml` and is **skipped when the repo already has workflows** (with a note to wire
  the suite into your CI) unless `--force`.

### Added (repo-bootstrap → 1.1.2, #59)
- **`--print-only`** prints the `.claude/settings.json` (and, with `--portka-standard`, the
  `CLAUDE.md` workflow block) to stdout for you to **create by hand** — a human-authored write isn't
  subject to Claude Code's auto-mode permission classifier, which can refuse an *agent*-written
  `.claude/settings.json` in a web session (the exact denial #59 reported). The skill now documents
  asking for approval and falling back to `--print-only`.

### Added (video-bug-analyzer → 1.1.2, #56)
- **`--stutter` / `--fps-drops`** (aliases for `--cadence`) make the stutter / dropped-frame timeline
  discoverable by the name people reach for, and the mode now also reports the **longest freeze
  gaps** (sustained frozen spans, e.g. `@1.4s frozen for 633 ms`) via `freezedetect` — quantifying
  the "multi-hundred-ms gaps" of an FPS stall, alongside the existing effective-fps-per-window.
  (#56 was filed from `1.0.0-rc.6`, before `--cadence` shipped; this closes the discoverability +
  freeze-gap gap.)

### Closed
- **#55** (release-hygiene recommendations) — every item shipped in 1.0.3: `version-bump-guard` and
  the CHANGELOG-consistency check (P0), `--auto-update` + the README **Updating** section (P1),
  hardened `locate_marketplace()` and the PR template (P2).

### Repo
- Dogfood: this repo now carries a committed `.claude/CLAUDE.md` (the Portka workflow) written by
  `repo-bootstrap --portka-standard`. New tests cover native-version binding, the mature-repo
  no-clobber path, `--print-only`, CI-collision skipping, and the `--stutter` freeze-gap timeline.

## [1.1.1] - 2026-06-25

Extends `repo-bootstrap` to install the **Portka standard setup**, so a repo (and your machine)
starts already knowing how we work — no re-explaining the process each session. `repo-bootstrap`
→ 1.1.1 (other plugins unchanged: `video-bug-analyzer` 1.0.3, `app-website-evaluator` 1.0.1,
`tab-chord-formatter` 1.0.0). A plugin's version is the marketplace release in which it last
changed (see RELEASING).

### Added (repo-bootstrap → 1.1.1)
- **`--portka-standard`** installs the standard setup in one run:
  - a **workflow `CLAUDE.md`** (a managed block, idempotent) encoding the Portka process — update
    `main` first, branch for every change, tests + CI then a PR, merge on green, and hand back a
    short PR link the user deletes as confirmation;
  - a **permissions allowlist** for the git/`gh` commands that workflow needs, merged into
    `settings.json` without clobbering existing keys (so the back-and-forth isn't gated on
    re-approving the same tools);
  - a repo **`VERSION` / `CHANGELOG.md` / `README.md`** version triplet on **SemVer**
    (`MAJOR.MINOR.PATCH`), kept in sync by a **basic `tests/run-tests.sh`** that *enforces* valid
    SemVer + that the three agree (and runs any `tests/cases/*.sh`), plus **CI** on every push/PR.
- **`--scope user|project|both`** (default `both`) chooses where the workflow `CLAUDE.md` +
  permissions land: `~/.claude` (your machine), committed `./.claude` (web sessions + team), or
  both. The version/sync scaffold is always written to the repo, and existing
  `VERSION`/`CHANGELOG`/`README` are never clobbered (the test runner is overwritten only with
  `--force`).
- **`--home <path>`** overrides the home dir for user-scope writes (keeps the test suite off your
  real `~/.claude`).

### Added (tests)
- New `repo-bootstrap --portka-standard` coverage: project + user scaffolding, permissions merged
  into both settings while the marketplace/plugins survive, **the scaffolded suite passes on a
  fresh repo and fails once the version sync is broken** (proving enforcement), managed-block
  idempotency, and `--dry-run` writing nothing.

## [1.1.0] - 2026-06-25

A new plugin joins the marketplace, so this is a MINOR bump (`video-bug-analyzer`,
`repo-bootstrap`, `app-website-evaluator` are unchanged; a plugin's version is the marketplace
release in which it last changed — see RELEASING).

### Added (tab-chord-formatter → 1.0.0, new plugin)
- A new **`tab-formatting`** skill that turns a messy guitar tab or chord sheet — copied from a
  web page, a forum, or an email, with broken alignment, HTML entities, and inconsistent labels —
  into a clean, standard, readable layout: a metadata header (Title / Artist / Capo / Key /
  Tuning), `[Section]` labels, chords aligned over the right lyric syllables, and well-formed
  6-line ASCII tab blocks.
- The split that makes it reliable: a bundled **`format-tab.py`** does only the deterministic,
  idempotent cleanup (strip HTML tags + decode entities, CRLF→LF, tabs→spaces, trim trailing
  whitespace **without ever touching a line's internal alignment**, standardize section labels,
  collapse blank runs); the skill applies the judgment the script can't — re-aligning chords over
  lyrics, lifting inline `[G]` chords onto a chord line, inferring/numbering sections, and
  standardizing chord spelling. The canonical format spec lives in the skill's `reference.md`.
- Tests: a dedicated `format-tab.py` section — section normalization (`VERSE 1` → `[Verse 1]`,
  `[intro]`/`chorus:` → `[Intro]`/`[Chorus]`), HTML-entity decode, **internal-alignment
  preservation**, blank-line collapse, idempotency (format twice == once), and `--help` exits 0.

### Added (repo / feedback hygiene)
- **Feedback form is now current and self-enforcing.** The **Plugin feedback** issue form's
  plugin dropdown gained `app-website-evaluator` and `tab-chord-formatter` (it had fallen behind),
  and a new CI test asserts the dropdown options (minus the "other / not sure" escape) **exactly
  match the plugins in `marketplace.json`** — so adding a plugin without updating the form now
  fails CI instead of silently drifting. Parsed without a YAML dependency, consistent with the
  other form checks.

## [1.0.3] - 2026-06-24

Acting on the round-2 dogfood feedback (#46, #48, #49, #51, #52, #53) and a release-hygiene
review. `video-bug-analyzer` → 1.0.3, `repo-bootstrap` → 1.0.3 (`app-website-evaluator` unchanged
at 1.0.1). A plugin's version is the marketplace release in which it last changed (see RELEASING).

### Fixed (video-bug-analyzer → 1.0.3)
- **`--label` now burns ABSOLUTE source time**, not burst-relative — timestamp bursts add the
  burst start (and `--start`-seeked dense/scene/diff/contact add `--start`) to the drawtext pts, so
  a label reads `00:01:18` instead of `00:00:01.5`. Raised in #51/#52/#53.
- **Feedback link no longer reports `version=unknown`** when the script runs standalone (fetched
  raw, no repo tree): an embedded `VBA_VERSION` is the fallback, kept in lockstep with `plugin.json`
  by a test. (#51/#52/#53)
- **A narrow `--timestamps` window now warns** ("--window 0.1s @ 2fps spans <1 frame … raise
  --window or --fps") instead of silently extracting 0 frames. (#53)

### Added (repo-bootstrap → 1.0.3)
- **`--auto-update`** sets `"autoUpdate": true` on the marketplace entry (verified shape against the
  settings schema), merging without clobbering existing keys. Documented with the #61854 caveat
  that, for third-party marketplaces, it currently refreshes the catalog but may not re-install
  plugin code — `claude plugin update` remains the reliable path.
- **Hardened `locate_marketplace()`**: walks upward (bounded) to find `marketplace.json` instead of
  a brittle fixed `../../../../../`, so resolution works from the installed-plugin cache layout too.

### Added (repo / release hygiene)
- **CI `version-bump-guard`**: a plugin whose files change must bump its `plugin.json` version, so
  fixes can't ship invisibly (P0-1).
- **CHANGELOG consistency check**: every `plugin.json` version must have a `## [x.y.z]` heading, so
  tag-driven release notes are never empty (P0-2).
- A **PR template** with a release checklist; an **Updating** section in the README (per-plugin
  `claude plugin update`, the auto-update toggle + #61854 caveat, kill switches); and a documented
  **versioning model** in RELEASING.md.

### Docs (web-session / discoverability, #51/#52)
- README documents the explicit `Skill(skill="video-bug-analyzer:video-bug-analysis")` invocation
  and a **standalone / not-installed** path (fetch `extract-frames.sh` raw and run it) — the
  enabled-but-not-loaded behavior on Claude Code web is a platform limitation, not something the
  plugin can fix from inside a session.

## [1.0.2] - 2026-06-22

Release tooling and submission prep — no plugin code changed (`video-bug-analyzer` 1.0.0,
`repo-bootstrap` 1.0.0, `app-website-evaluator` 1.0.1 are unchanged).

### Added
- **Auto-release workflow** (`.github/workflows/release.yml`): pushing a `vX.Y.Z` tag now creates
  a GitHub Release whose notes are extracted from the matching `## [x.y.z]` CHANGELOG section
  (falling back to GitHub's auto-generated notes). Applies to tags cut after this lands (v1.0.2+);
  v1.0.0/v1.0.1 are released manually.
- **buildwithclaude submission kit** (`submissions/buildwithclaude/`): `prepare.sh` stages the
  `video-bug-analysis` skill into a buildwithclaude fork (pointing back to `cportka/claude-plugins`
  via `plugin.json`), with a README of the fork/PR steps.
- Tests now lint scripts under `submissions/` and assert the release workflow is wired to tags +
  CHANGELOG, and that the current version has a CHANGELOG section. RELEASING.md updated.

## [1.0.1] - 2026-06-22

Dogfooding our own `app-website-evaluator` on the project's own GitHub Pages site, then fixing
what it flagged — brand + web assets the 1.0.0 site was missing.

### Added (repo / Pages site)
- **Brand assets:** an SVG **logo** (`assets/logo.svg`) + **favicon** (`favicon.svg`), an
  `apple-touch-icon` and a 1200×630 **`og:image`** (`assets/og.png`, rendered with ffmpeg) so
  shared links preview richly.
- **Social/SEO meta** in `index.html`: `og:image`/`twitter:card` (absolute URLs), `og:url`,
  `canonical`, `theme-color`, and the logo in the page header.
- **Crawlability / AI-readiness:** `robots.txt` (+ sitemap reference), `sitemap.xml`, and an
  **`llms.txt`** that maps the marketplace and its three plugins for LLMs.

### Changed
- **app-website-evaluator → 1.0.1:** the checker now also flags a missing `<meta name="theme-color">`
  (a gap the dogfood surfaced on our own site). `reference.md` brand checklist updated.

## [1.0.0] - 2026-06-22

First stable release of the **portka-tools** marketplace, after 19 release candidates of
dogfooding `video-bug-analyzer` on real bugs. All three plugins are now **1.0.0**.

### video-bug-analyzer 1.0.0
- Graduates from rc.19 with no behavioral change from rc.19 except the bonus below. The full
  feature set: contact-sheet / scene-cut / per-timestamp extraction; `--strip`, `--diff`,
  `--label`, `--crop`, `--intro`; and analysis modes `--blackdetect`, `--ocr-roi`, `--measure`,
  `--probe`, `--palette`, `--ab`, `--compare-videos`, `--cadence`, `--motion`, plus the automatic
  `smoothness:` header. (Per-RC history is the rc.1–rc.19 entries below.)
- **Added `--saturation`** — a colour-saturation timeline (`signalstats` SATAVG per frame), so
  "clownish/over-saturated vs muted/elegant" is measurable and verifiable after a fix (the
  recurring rc.16/rc.17/rc.19 dogfood ask).

### repo-bootstrap 1.0.0
- Graduates from rc.1. **Added `--dry-run`** (preview the merged `.claude/settings.json` and
  planned CI write without touching disk), complementing the existing idempotent merge, `--list`,
  `--ci`/`--force`, marketplace validation, and the one-paste `/plugin` CLI fallback.

### app-website-evaluator 1.0.0 (new plugin)
- A new **`app-evaluation`** skill: classify the target (type + audience + goal), gather evidence
  with the bundled **`evaluate-site.sh`** (`--url` live or `--dir` local; checks crawlability,
  SEO, social/sharing, brand assets, AI-readiness incl. `llms.txt`, security headers, and
  performance hints), then deliver a **prioritized, evidence-backed** report tailored to the
  site's type and community — including which communities to join/submit to and concrete PR wins.
  Self-referential: it judges each property (and its own advice) against what's best for *that*
  kind of app/website and *that* community. Full checklists, the by-type submission directory,
  and the impact×effort rubric live in the skill's `reference.md`.

### Repo
- **GitHub Pages** landing page (since rc.14) at `cportka.github.io/claude-plugins`.
- **Cleanup:** stripped the per-change `# ADDED:/# CHANGED:` provenance prefixes from the scripts
  (keeping the explanatory text); the shipped-history that lived in `IMPROVEMENTS.md` is now
  consolidated here, leaving IMPROVEMENTS as a forward-looking roadmap.
- Test suite: **102 checks**, including the new plugin's e2e, `--saturation`, and bootstrap
  `--dry-run`; the `--help` documentation check is derived from the argparse (no hand-kept list).

## [1.0.0-rc.19] - 2026-06-22

From the "splash doesn't play on mobile" dogfood (#43, iOS Safari vs MacBook Firefox). Its top
asks — compare mode, smoothness header, contact `--label` — already shipped in rc.17/rc.18; the
new one is a first-seconds preset, since load/splash bugs always live at t=0.
`video-bug-analyzer` → 1.0.0-rc.19.

### Added
- **`--intro`** (issue #43) — load/splash preset: the first ~2s as a dense, labelled contact
  sheet (= `--start 0 --end 2 --fps 12 --contact --label`, portrait-aware). Every part yields to
  an explicit flag (`--end 3` / `--fps 8` still win). "The intro does X" is the most common load
  report and people kept re-typing those flags.

### Docs
- An **"an animation didn't play"** note (SKILL + reference, issue #43): frames confirm the
  *absence* of an animation but not the *cause* (DOM-present-but-paused, deferred first paint, JS
  threw, reduced-motion) — pair the video pass with a DOM/console capture and a code read. Builds
  on the existing headless-virtual-time/`getAnimations()` capture note.

### Notes
- #43 re-raised compare mode (`--compare-videos`, rc.18), the smoothness header (rc.18), contact
  `--label` (rc.18), and motion magnitude (`--motion`, rc.17) — all already shipped; `--intro`
  was the remaining gap.

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

[1.4.1]: https://github.com/cportka/claude-plugins/releases/tag/v1.4.1
[1.4.0]: https://github.com/cportka/claude-plugins/releases/tag/v1.4.0
[1.3.1]: https://github.com/cportka/claude-plugins/releases/tag/v1.3.1
[1.3.0]: https://github.com/cportka/claude-plugins/releases/tag/v1.3.0
[1.2.0]: https://github.com/cportka/claude-plugins/releases/tag/v1.2.0
[1.1.2]: https://github.com/cportka/claude-plugins/releases/tag/v1.1.2
[1.1.1]: https://github.com/cportka/claude-plugins/releases/tag/v1.1.1
[1.1.0]: https://github.com/cportka/claude-plugins/releases/tag/v1.1.0
[1.0.3]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.3
[1.0.2]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.2
[1.0.1]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.1
[1.0.0]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0
[1.0.0-rc.19]: https://github.com/cportka/claude-plugins/releases/tag/v1.0.0-rc.19
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
