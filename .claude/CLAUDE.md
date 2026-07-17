<!-- BEGIN portka-standard (managed by repo-bootstrap — edit between the markers, or re-run to refresh) -->
# Portka standard workflow

Standing conventions for how Claude Code works here. Follow them for every change, without being
asked, so our back-and-forth stays on the code — not on process.

For each change you make **in this repository**:

1. **Update `main` first.** Begin by switching to `main` and pulling the latest. A previous
   change's branch being gone is the user's confirmation that they saw it (see step 5).
   *Greenfield repo?* If `main` doesn't exist yet, establish it from your first green commit **before
   anything else** — the standard, GitHub Pages' environment protection, and the delete-the-branch
   signal (step 5) all assume `main` exists and is the repo's **default** branch. Flipping the default
   is a GitHub **Settings-only, human step** (no API for typical agent toolsets): create `main`, push
   it, then hand the default-branch flip back to the owner explicitly.
   *Branch-pinned session?* In a hosted/branch-pinned environment (e.g. Claude Code on the web) the
   harness assigns you **one** feature branch and forbids **pushing directly to `main`** — so **skip
   the `main` checkout** and work on that branch. Because the name is reused for the whole session,
   step 2's "new branch per change" becomes: after each merge, **restart the pinned branch from
   `origin/main`** (`git fetch origin main && git checkout -B <pinned> origin/main`, matching the
   harness's own merged-PR guidance), and expect **`git push --force-with-lease`** to be routine.
   Nothing else changes: you still open the PR and merge it on green — see the note after step 5.
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
   which you pick up next time you update `main` (step 1). *Branch-pinned caveat:* with a single
   reused branch name, deletion can't happen mid-session, so this confirmation signal only fires
   **between** sessions — don't wait on it within one.

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

No `gh` in a hosted/web session? File the same issue through your GitHub tools (an MCP
`create_issue` / issue-write tool) or the web UI's **New issue → Plugin feedback** form — same repo,
same `feedback` label, same fields.

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

## Commit identity

Set git's author/committer identity **before your first commit**, from the identity this repo
declares (see the repo-specific note below; ask the owner if none is set yet):

```
git config user.name  "<declared name>"
git config user.email "<declared email>"
```

Use that same identity for every automated/agent commit so history stays consistent — don't fall
back to a generic `noreply@` default. Follow any trailer convention the repo names (e.g. a
`Co-authored-by:` line). In hosted/sandbox environments commit **signing** is often unavailable (an
empty signing key or a stub signing program), so commits land unsigned — that's expected: don't force
a signature, and never rewrite already-merged history to "fix" the authorship of GitHub's own
squash-merge commit (committer `noreply@github.com`, reachable from `main`).
<!-- END portka-standard -->

# This repo's specifics (outside the managed block, so a bootstrap refresh keeps them)

The block above is the generic Portka standard. A few points are concrete **in this repository**:

- **Version source of truth is per-plugin:** each `plugins/<name>/.claude-plugin/plugin.json`
  `version` — not a root manifest. A plugin's version = the marketplace release in which its files
  last changed; the README header tracks the repo release; `CHANGELOG.md` has one `## [x.y.z]`
  section per release with per-plugin notes inside. The suite + the CI `version-bump-guard`
  enforce all of it. Full model: `RELEASING.md`; maintainer map: `docs/HANDOFF.md`.
- **Commit identity for this repo:** author/committer commits as `Chris Portka
  <chrisportka@gmail.com>` (`git config user.name "Chris Portka"; git config user.email
  "chrisportka@gmail.com"`) — the concrete value the managed block's *Commit identity*
  section points at.
- **Feedback lands HERE:** this repo *is* the marketplace, so plugin feedback arrives as GitHub
  issues on this repo (the "Plugin feedback" form, `feedback` label). Triage each into fixes or an
  `IMPROVEMENTS.md` entry, release, then close the issue with a shipped/deferred comment.
