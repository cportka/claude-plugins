# Feedback — Portka Tools & Standards (`repo-bootstrap --portka-standard`)

Field report from applying the Portka standard to a brand-new repo,
[`cportka/infinite-ambient`](https://github.com/cportka/infinite-ambient) — a static, no-build
Web Audio app. This covers what the `repo-bootstrap` skill (v1.2.0) and its `--portka-standard`
setup did well, the friction hit in practice, and concrete, prioritized suggestions. Every claim
below was observed by actually running the script, not read off the source.

> **Context of the run**
> ```
> bootstrap-repo.sh --portka-standard --scope project --dir infinite-ambient
> ```
> The repo already had a `package.json` (`0.1.0`) and a minimal `README.md` (no `**Version:**`
> line), and no CI. So this exercises the "mature-ish manifest + greenfield everything else" path.

## What worked well

- **Native version binding (#59) is correct and quiet.** It detected `0.1.0` from `package.json`
  and bound the sync check to it — *"Detected version 0.1.0 from package.json — binding the sync
  check to it (not seeding VERSION)."* No stray `VERSION` file, no competing source of truth. This
  is exactly the behavior a manifest repo wants.
- **Idempotent, non-clobbering merges.** A second run to enable a plugin
  (`--plugin repo-bootstrap`) merged into the existing `.claude/settings.json` without disturbing
  the marketplace entry or the 16 permission rules, and left the hand-written `README.md` untouched
  (*"exists, leaving as-is"*). Re-runs are safe, which matters for a "re-run to refresh" tool.
- **The native `node:test` sync test is the right call.** Emitting `tests/version-sync.test.mjs`
  means the repo's *own* test command enforces the sync, not just the standalone bash runner — so
  the invariant holds even for someone who never runs `tests/run-tests.sh` directly.
- **Collision-aware CI.** With no existing workflow it wrote `portka-standard.yml`; the messaging is
  explicit about when it will and won't add CI. Clear and predictable.
- **The README `**Version:**` check is opt-in.** The scaffolded `run-tests.sh` only cross-checks the
  README line *if one exists*, so a repo that tracks its version elsewhere doesn't ship red. This is
  the #59 fix working — my README had no version line and the suite was green on the first run.
- **Good failure guidance.** The stderr note about the auto-mode permission classifier plus the
  one-paste `/plugin` CLI fallback is genuinely useful; it anticipates the exact web-session denial.

## Friction & bugs (observed)

### 1. [P1] The manifest repo is left without a working `test` script — and the obvious invocation fails

The scaffold writes `tests/version-sync.test.mjs` and tells you to *"run with `node --test`"*, but
it does **not** set/patch `package.json`'s `scripts.test`. A repo that already has a `package.json`
(the common case the #59 binding targets) is left with **no wired-up `npm test`**.

Worse, the natural first guess is a trap. On Node ≥ 20:

```
$ node --test tests/
Error [ERR_MODULE_NOT_FOUND]: Cannot find module '/…/tests'
```

`node --test tests/` treats `tests` as a *module path*, not a directory to scan. The working forms
are bare `node --test` (auto-discovery) or an explicit glob (`node --test 'tests/*.test.mjs'`). I
hit this directly and lost time to it before switching to bare `node --test`.

**Suggestion:** when a `package.json` is present and has no `scripts.test`, add
`"test": "node --test"` (merged safely, like the settings.json merge). If a `test` script already
exists, leave it and print the exact command to fold in. At minimum, the "run with" hint should show
the *working* invocation, never `node --test tests/`.

### 2. [P2] The scaffolded CHANGELOG check is a bare substring match — weaker than the standard it models

`tests/run-tests.sh` verifies the changelog with:

```sh
if grep -qF "$VER" CHANGELOG.md; then …   # line 59 of the generated runner
```

`grep -qF "0.1.0"` also passes on `## [10.1.0]`, on `v0.1.0-notes` links, or on any incidental
mention — it doesn't require a Keep-a-Changelog *heading* for the version. This repo's own suite is
stricter (P0-2 requires a `## [version]` heading so release notes are never empty). The scaffold
should hold the same bar it teaches:

```sh
if grep -qE "^## \[$VER\]" CHANGELOG.md; then …   # anchor to a real heading
```

(`$VER` should be regex-escaped, or matched with a small awk/`grep -F` on the `## [` prefix.)

### 3. [P2] The workflow `CLAUDE.md` collides with branch-pinned / hosted environments

The managed block instructs Claude to *"Update `main` first … merge on green … hand back a PR
link."* In a **Claude Code web / branch-pinned session**, the harness pins all work to a designated
feature branch and forbids pushing to `main`. Applying the standard in exactly that environment put
its two instruction sets in direct tension (update-main-first vs. never-touch-main).

**Suggestion:** add one sentence to the managed block acknowledging hosted runs, e.g. *"In a
branch-pinned environment (e.g. Claude Code on the web), skip the `main` checkout: open the PR from
your assigned branch and stop — a human merges."* It keeps the workflow honest where it's most
likely to be read by an agent.

### 4. [P2] No deploy path for the most common greenfield case (a front-end)

The standard scaffolds *test* CI but nothing for shipping. A large share of greenfield repos are
static front-ends whose next question is immediately "how does this get online?" For
`infinite-ambient` I hand-wrote a `.github/workflows/pages.yml` (+ `.nojekyll`). An optional
`--pages` flag that drops a Pages deploy workflow (and `.nojekyll`) would round out the "green PR
that merges and ships" story the workflow already promises. Keep it opt-in and collision-aware, same
as `portka-standard.yml`.

### 5. [P3] Minor polish
- The seeded `CHANGELOG.md` entry ("Initial scaffold via repo-bootstrap …") always has to be
  rewritten for a real first release. Fine, but a shorter placeholder (or a `### Added\n- ` stub)
  would invite editing rather than deletion.
- `--portka-standard` writes a lot across several trees (`.claude/`, repo root, `.github/`,
  `tests/`). A one-line summary at the end ("wrote N files across settings/version-sync/CI") would
  help the reader confirm scope at a glance; today you reconstruct it from the streamed log.
- Consider a native sync test for Cargo repos too (IMPROVEMENTS already tracks this) so Rust repos
  get the same "own test command enforces it" property JS/Python get.

## Net

The core promise — *bind to the real version source, enforce SemVer + changelog agreement, make it
survive fresh web sessions, don't clobber anything* — is delivered and pleasant to use. The binding
logic and idempotency are the standout wins. The one change with real leverage is **#1**: wiring
(or correctly documenting) `npm test` so a manifest repo isn't left a step short with a
failure-prone hint. **#2** closes a correctness gap against the project's own standard, and **#3**
makes the workflow honest in the environment where an agent is most likely to execute it.

---
*Submitted from the `infinite-ambient` build-out, applying `repo-bootstrap` v1.2.0.*
