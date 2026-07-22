# Handoff — maintaining `cportka/claude-plugins` (portka-tools)

Read this first if you're a fresh maintainer or a fresh Claude session picking the repo up cold.
It explains what this is, how work flows through it, where every invariant is enforced, and the
sharp edges that will otherwise cost you an hour each. Written at repo version **1.10.0**
(2026-07-16); the version header in [README.md](../README.md) is always current.

## What this repo is

A [Claude Code plugin **marketplace**](https://code.claude.com/docs) named **`portka-tools`**,
serving four plugins. Users add it with `/plugin marketplace add cportka/claude-plugins` and
install plugins by name; a committed `.claude/settings.json` does the same for web sessions.

| Piece | Where | What it is |
| :-- | :-- | :-- |
| Marketplace catalog | `.claude-plugin/marketplace.json` | The four plugin entries; `source` paths are relative (`./plugins/<name>`) |
| `video-bug-analyzer` | `plugins/video-bug-analyzer/` | `extract-frames.sh` (largest script; `wc -l` for the current size) — frame extraction + ~20 analysis modes over ffmpeg/ffprobe/python3 |
| `app-website-evaluator` | `plugins/app-website-evaluator/` | `evaluate-site.sh` — coverage-honest site scorecard (url / dir / html / hybrid inputs) |
| `repo-bootstrap` | `plugins/repo-bootstrap/` | `bootstrap-repo.sh` — onboards a repo to this marketplace and/or the Portka standard |
| `tab-chord-formatter` | `plugins/tab-chord-formatter/` | `format-tab.py` — deterministic tab/chord cleanup + PDF songbook (headless Chromium) |
| Test suite | `tests/run-tests.sh` | ONE self-contained runner — manifests, version sync, per-script behavior, ffmpeg e2e |
| CI | `.github/workflows/validate.yml` | Runs the suite + a `version-bump-guard` job on every push/PR |
| Site | `index.html` (+ `assets/`, GitHub Pages) | The marketplace's public page; the suite dogfoods the evaluator against it |

Each plugin is `plugins/<name>/.claude-plugin/plugin.json` (manifest, **the version source of
truth**) + `skills/<skill>/SKILL.md` (the in-context instructions) + `reference.md` (depth the
skill defers to) + `scripts/` (the deterministic part). Scripts are standalone by design — a
session that can't load the plugin can `curl` the raw script and run it (`video-bug-analyzer`
embeds `VBA_VERSION` for exactly that case).

## How work flows (the Portka standard)

The committed [.claude/CLAUDE.md](../.claude/CLAUDE.md) is the **standing instruction** — its
presence is the "explicit ask" that authorizes the whole loop. Per change:

1. Update `main` (or skip the checkout in a branch-pinned session and use the assigned branch).
2. Branch; never commit to `main` directly.
3. Tests + CI, then **open the PR proactively** — don't stop at "branch pushed" and ask.
4. Wait until every check has **registered and finished** (an empty check list is not green),
   then merge it yourself — EXCEPT outward-facing/irreversible merges (a prod cutover, a coupled
   multi-service deploy): hand those back green for the owner's go/no-go (standard step 4's
   carve-out). If GitHub refuses a merge (branch protection, token scope), hand back the green PR
   — never self-approve or force-merge.
5. Hand back a short PR link. **Tags/releases are the human's manual step** — prepare version +
   CHANGELOG in the PR, never `git tag`/`gh release` (sandboxes block tag pushes).

Feedback on the tools arrives as **GitHub issues** (the "Plugin feedback" form; `feedback` label)
— never as branches/PRs from consuming repos. The cadence that built this repo: an issue lands →
triage into fixes (or defer to `IMPROVEMENTS.md` with a note on the issue) → one release PR →
merge on green → close the issue with a shipped/deferred comment.

## Versioning — the one invariant to internalize

**A plugin's `plugin.json` version = the marketplace release in which its files last changed.**
Versions differ across plugins and may skip numbers; `marketplace.json` entries carry no version.
Every release touches, in lockstep:

1. Each changed plugin's `plugin.json` `version` (+ `VBA_VERSION` in `extract-frames.sh` if the
   video plugin changed);
2. The plugin's row in the README table **and** the README header `> **Version:**` line (the
   header tracks the repo release);
3. A `## [x.y.z]` section in `CHANGELOG.md` (Keep a Changelog; per-plugin subsections inside).

You cannot get this wrong silently: the suite cross-checks all of it (semver shape, README table ↔
manifest, `## [ver]` headings for every manifest version, `VBA_VERSION` lockstep), and CI's
**version-bump-guard** fails any PR that changes a plugin without bumping it. Details:
[RELEASING.md](../RELEASING.md).

## Running and extending the tests

```
bash tests/run-tests.sh        # needs bash 4+; ffmpeg/shellcheck/tesseract steps SKIP when absent
```

Everything is in the one runner, in labeled sections. Conventions that matter (each learned the
hard way — see the issue numbers in comments):

- **Capture-then-grep**: `out="$(cmd ... || true)"; grep -q ... <<<"$out"` — piping a live
  producer into `grep -q` under `pipefail` SIGPIPEs the producer and flakes (issue #21).
- Fixtures are built inline with `mktemp -d` + heredocs/`ffmpeg -f lavfi`; **fake binaries on
  PATH** (a stub `curl`/`ffprobe`) inject network responses and frame rates deterministically.
- When a behavior depends on *absence* (e.g. #90's fully-scored run), the fixture must construct
  that absence — every earlier fixture accidentally guaranteed presence, which hid the bug.
- Strings the tests grep are load-bearing: if you rewrite a script's output line, grep the suite
  for the old text first.

## The sharp edges (read before they cost you)

- **`version-bump-guard` runs per-event with different bases.** The `pull_request` run diffs
  against the base branch (thorough); the `push` run diffs `HEAD^` and, as of 1.10.0, only fires
  on `main` (post-squash-merge, where `HEAD^` is correct). If you ever widen the push trigger
  again, multi-commit branches will re-grow the false positive that forced branch squashing.
- **GitHub Pages deploys flake under rapid merges** ("Deployment failed, try again later"). It's
  GitHub infra, not the repo; the site keeps serving the last good build. Re-run the failed
  "pages build and deployment" or just let the next merge redeploy.
- **The sandbox egress proxy 403s arbitrary hosts.** `curl` to random domains fails; this is why
  the evaluator grew `--html`/`--headers`/hybrid modes, and why `publish.sh`'s network steps are
  best-effort. Fetch external pages via WebFetch-style tools, not raw curl.
- **macOS ships bash 3.2, and BSD tools differ.** The suite requires bash 4+ and exits 0 with a
  clear "skipped" message (issue #75 — advisory inside `publish.sh`; note that macOS summary is a
  *skip*, not a green). The `plugins/` scripts themselves run on 3.2 (the last `mapfile`s were
  removed in 1.10.0) — keep it that way, and avoid GNU-only flags (sed `s///I` bit us once).
- **`set -u` + `declare -a`**: an array that's declared but never assigned is *unset* — `${#a[@]}`
  errors on bash 5.2 (issue #90). Initialize with `a=()`.
- **ffmpeg subtleties encoded in `extract-frames.sh`**: `-y` doesn't help when a window decodes
  zero frames (the image muxer opens lazily — `rm` the output first); `format=duration` includes
  audio (use the *video stream* duration); seeking to ~EOF then `-frames:v 1` overshoots (decode a
  tail with `-update 1`); >8-bit sources emit 16-bit PPMs (`-pix_fmt rgb24` or parse the high
  byte). All carry `#85`/`#89` comments at the code.
- **Every check string in the evaluator is scored** — `ok`/`warn`/`bad` tally into the dimension
  arithmetic; `info` doesn't. Adding a check changes scores; the coverage-star logic
  (`UNSCORED`/`COVERAGE`) assumes dimensions with zero scored checks are excluded.

## Where things are decided

- **`IMPROVEMENTS.md`** — the forward-looking roadmap; every deferred triage item lands here with
  its issue number. Shipped history lives only in `CHANGELOG.md`.
- **`RELEASING.md`** — release + tagging mechanics, and the community-submission process
  (Anthropic's directory pins a SHA but re-syncs from `main` nightly, so merged work flows out on
  its own; submissions are per-plugin subdirectory links).
- **`docs/DISTRIBUTION.md` + `scripts/publish.sh`** — the discovery playbook (topics, description,
  Pages, community catalog, announcements).
- **`docs/INTEGRATE.md`** — the portable "enable these plugins in another repo" guide.
- **`PRIVACY.md` / `SECURITY.md` / `.well-known/security.txt`** — posture: local-only scripts, no
  data collection; vulnerabilities via GitHub private reporting.

## State at handoff (refreshed each release — this stamp: 1.13.0, 2026-07-22)

- Versions: the README header + plugin table and each `plugins/*/.claude-plugin/plugin.json` are
  the live source of truth (per-plugin versions diverge by design). Suite size/green-ness: run
  `bash tests/run-tests.sh`; CI mirrors it.
- All feedback issues through #110 triaged; deferred items live in `IMPROVEMENTS.md` with issue
  numbers. Tags/GitHub Releases are the human's manual step and may lag main — that's expected.
- Community-directory submission state: check the open PR on anthropics' marketplace repo
  (see `docs/DISTRIBUTION.md`); the nightly sync picks up merged work once approved.

## The spirit of the thing

This repo runs on a tight dogfood loop: the plugins are used on real projects, every rough edge
comes back as a filed issue with concrete detail, and every release is issue-driven. Two habits
keep quality up more than anything else: **adversarial review before merging non-trivial script
changes** (it has caught real bugs — a stale-frame fabrication, an audio-longer-than-video false
error, a 16-bit PPM misparse — that green tests missed), and **encoding every hard-won lesson as
a `#NN`-referenced comment + a regression test** so the next maintainer inherits the *why*, not
just the *what*.
