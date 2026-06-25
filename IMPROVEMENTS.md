# Roadmap & Known Weaknesses

Forward-looking notes: what each plugin does well, where it's weak, and ideas not yet built.
Kept here — not in the skills — so in-context instructions stay lean. **Shipped history lives in
[CHANGELOG.md](./CHANGELOG.md)**; user-reported problems arrive via the **Plugin feedback** issue
form and are triaged into the items below.

## video-bug-analyzer

**Strengths**
- Repeatable, bug-tuned frame extraction (dense / scene-change / contact-sheet) plus a deep set
  of analysis modes (blackdetect, OCR, measure, probe, palette, ab/compare, cadence, motion,
  saturation) — most emit a CSV/report and exit, so they compose.
- Contact-sheet reads a whole span in one image (big token saver); the skill states confidence
  and caveats instead of bluffing; ffmpeg is handled (SessionStart hook + on-first-use fallback).

**Weaknesses / cons**
- Blind between samples: fast flickers / one-frame glitches can be missed.
- No true timing: race / ordering / duration bugs are poorly served by frames.
- Off-screen state (console / network / memory) is invisible — `--ocr-roi` + the state-vs-render
  steer are the in-tool half; the rest needs logs / a repro.
- Scene-change is heuristic (threshold per clip); many PNGs cost tokens if the window/fps isn't tight.

**Ideas (not yet built)**
- **Optical-flow / trajectory overlay** — `--motion` gives magnitude; *direction/coherence*
  ("spiralling inward, ~2.5 turns" vs random drift) needs flow vectors or per-blob tracking.
- **Numeric plot over a CSV** — the OCR/measure/motion/saturation modes emit `t,value`; rendering
  a quick plot (or min/max/dips) would beat reading the CSV by eye.
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
  enforced `VERSION`/`CHANGELOG`/`README` sync with a basic `tests/run-tests.sh` + CI.

**Weaknesses / ideas (not yet built)**
- Requires `python3` (no pure-bash/`jq` fallback yet).
- The scaffolded sync assumes a top-level `VERSION` file; could also detect/target a
  `package.json` / `pyproject.toml` version, and offer a vanilla (non-Portka) settings profile.

## app-website-evaluator

**Strengths**
- Self-referential: classifies the target (type/audience/goal) and judges every property — and
  its own advice — against what's best for *that* kind of site and community.
- `evaluate-site.sh` gives a concrete evidence base from a live URL **or** a local build (offline),
  spanning crawlability, SEO, social, assets, AI-readiness (`llms.txt`), security headers, perf.

**Weaknesses / ideas (not yet built)**
- HTML checks are grep-heuristic (best-effort), not a DOM parse; a JS-rendered SPA can hide content
  from a simple fetch — note it and prefer the built/SSR output or repo.
- No real Core Web Vitals / Lighthouse run (points the user there); could integrate if a headless
  browser is available. No automated link-check or a11y contrast scan yet.
- Could emit a machine-readable JSON report and a letter grade per dimension.

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
