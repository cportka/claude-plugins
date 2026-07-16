<!-- BEGIN portka-standard (managed by repo-bootstrap — edit between the markers, or re-run to refresh) -->
# Portka standard workflow

Standing conventions for how Claude Code works here. Follow them for every change, without being
asked, so our back-and-forth stays on the code — not on process.

For each change you make **in this repository**:

1. **Update `main` first.** Begin by switching to `main` and pulling the latest. A previous
   change's branch being gone is the user's confirmation that they saw it (see step 5).
   *Branch-pinned session?* In a hosted/branch-pinned environment (e.g. Claude Code on the web) the
   harness assigns you a feature branch and forbids **pushing directly to `main`** — so **skip the
   `main` checkout** and work on your assigned branch. Nothing else changes: you still open the PR
   and merge it on green — see the note after step 5.
2. **Branch for everything (in this repo).** Every fix, update, or change goes on a new branch here —
   never commit to `main` directly. If another repo is open in the same session (e.g. a plugin
   marketplace you installed tools from), it is **read-only reference**: do all your branches and PRs
   on *this* repo, never on it.
3. **Tests + CI, then a PR.** Update the relevant tests, keep CI running them, and open a pull
   request (opening it is pre-authorized — see the note after step 5; don't stop at "branch pushed"
   to ask). If the repo has no CI yet, add a basic workflow that runs the test suite.
4. **Green, then merge.** Wait until every check has **registered and finished** — an empty or
   still-populating check list is *not* green — then merge the PR. Never merge on red or before CI
   completes.
5. **Hand back a short PR link.** Give the user a short link to the PR — merged if you were able to,
   otherwise green and ready for them to merge, saying which. They delete the branch when satisfied —
   which you pick up next time you update `main` (step 1).

**Opening the PR and merging are authorized — this file is the "explicit ask."** Some hosted
harnesses default to *"don't open a pull request unless the user explicitly asks for one."* The repo
owner committed this standard, so **its presence is that standing instruction**: open the PR
proactively at step 3 for every change — do **not** stop at "branch pushed" and ask whether to open
one. Then **merge it yourself once CI is green.** Merging a PR happens through GitHub, not a local
push to `main`, so a branch-pin usually doesn't block it — but that's not guaranteed: branch
protection (e.g. a required approving review you can't give as the PR's author), the harness's token
scope, or org policy can still refuse a merge on a green PR. So **attempt the merge; if GitHub
refuses, hand back the green PR** and say it's ready for them to merge — never self-approve, bypass
protection, or admin/force-merge around a refusal. The owner's expected flow is open → green → you
merge → they delete the branch.

**Releasing is the user's manual step — don't tag or cut releases.** Merging the PR is *not*
releasing. Prepare the release *in the PR* (bump the version, update `CHANGELOG.md`), but do **not**
create or push a git tag and do **not** run `gh release` / publish a GitHub Release. Hosted/sandbox
environments block tag pushes, so it just fails. After the PR merges, the user tags the release and
cuts it from the GitHub web UI.

## Reporting feedback on the tools you use

Hit a bug or rough edge in a plugin you installed (or in this standard)? **File it as a GitHub issue
on the marketplace repo the tool came from — `cportka/claude-plugins` — using the "Plugin feedback"
template.** Do **not** open a branch, commit, or PR on that repo: you don't have write access there
and it isn't how feedback is collected. One command:

```
gh issue create --repo cportka/claude-plugins --label feedback \
  --title "[feedback] <plugin>: <one-line summary>" \
  --body "What you ran, expected vs. actual, environment, and a concrete suggestion."
```

Keep *this* repo's branches and PRs about *your* code; route tool feedback to the marketplace's
issue tracker, where it gets triaged into a fix and a new version.

## Versioning — SemVer (enforced)

Versions follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH` — **MAJOR** for
breaking changes, **MINOR** for backward-compatible features, **PATCH** for backward-compatible
fixes. Keep one source of truth and the other places in agreement, and bump the right part:

- the **version source of truth** — your project manifest (`package.json` / `pyproject.toml` /
  `Cargo.toml`), or a bare `VERSION` file if the repo has no manifest.
- `CHANGELOG.md` — a section for each released version (Keep a Changelog).
- `README.md` — a `**Version:**` line, if you keep one, that matches.

`tests/run-tests.sh` checks the version is valid SemVer and that these agree; CI runs it on every
push/PR, so they can't drift.
<!-- END portka-standard -->

# This repo's specifics (outside the managed block, so a bootstrap refresh keeps them)

The block above is the generic Portka standard. Two points differ **in this repository**:

- **Version source of truth is per-plugin:** each `plugins/<name>/.claude-plugin/plugin.json`
  `version` — not a root manifest. A plugin's version = the marketplace release in which its files
  last changed; the README header tracks the repo release; `CHANGELOG.md` has one `## [x.y.z]`
  section per release with per-plugin notes inside. The suite + the CI `version-bump-guard`
  enforce all of it. Full model: `RELEASING.md`; maintainer map: `docs/HANDOFF.md`.
- **Feedback lands HERE:** this repo *is* the marketplace, so plugin feedback arrives as GitHub
  issues on this repo (the "Plugin feedback" form, `feedback` label). Triage each into fixes or an
  `IMPROVEMENTS.md` entry, release, then close the issue with a shipped/deferred comment.
