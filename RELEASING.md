# Releasing & submitting

How to cut a release of the `portka-tools` marketplace and get it discovered. Steps marked
**(manual)** can't be done from this automated environment (the git proxy blocks tag pushes, and
there's no MCP tool for repo settings / external submissions) — they're for a maintainer.

## 1. Cut the release (in a PR)

1. Bump `version` in each changed plugin's `.claude-plugin/plugin.json` (SemVer; the marketplace
   moves to a release like `1.0.0`). The README **Version:** line and each plugin's table row must
   match — the test suite enforces the table↔manifest sync.
2. Add a dated entry to [CHANGELOG.md](./CHANGELOG.md) (Keep a Changelog format) and a footer link.
3. Keep [IMPROVEMENTS.md](./IMPROVEMENTS.md) forward-looking only (shipped history goes in CHANGELOG).
4. `bash tests/run-tests.sh` → 0 failures, and `claude plugin validate --strict <plugin>` (and `.`
   for the marketplace) clean for every plugin.
5. Open the PR, let CI (`.github/workflows/validate.yml`) go green, squash-merge to `main`.

## 2. Tag the release **(manual)**

Tags are cut **only** for real releases (not per-RC). After the release PR is merged to `main`:

```
git checkout main && git pull
git tag -a v1.0.0 -m "portka-tools 1.0.0"
git push origin v1.0.0
```

Then create a **GitHub Release** from that tag (paste the CHANGELOG section as the notes):
`gh release create v1.0.0 --title "v1.0.0" --notes-file <(...)`, or via the GitHub UI.

## 3. GitHub Pages **(manual, one-time)**

The landing page is `index.html` + `.nojekyll` at the repo root, served from `main`. Enable it
once: **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `(root)`**.
It serves at `https://cportka.github.io/claude-plugins/`. Verify it loads after enabling.

## 4. Repo description + topics **(manual)**

Boosts discoverability (Settings / the repo sidebar):
- **Description:** "Claude Code plugin marketplace (portka-tools): analyze screen recordings,
  evaluate websites/apps, bootstrap repos."
- **Topics:** `claude-code`, `claude-plugin`, `claude-code-plugin`, `marketplace`, `ffmpeg`,
  `video`, `debugging`, `seo`, `audit`, `website`.

## 5. Submit to the Anthropic community marketplace **(manual)**

Get the plugins listed where Claude Code users browse:
1. Read the current submission process at **https://code.claude.com/docs** (plugins /
   marketplaces section) — it has evolved, so follow the live docs rather than a cached process.
2. Typically: ensure `.claude-plugin/marketplace.json` is valid (it is — CI validates it), then
   open a PR/issue to the community marketplace registry pointing at `cportka/claude-plugins`, or
   submit via the documented form. Include the Pages URL and a one-line pitch per plugin.
3. After listing, verify a clean install end-to-end:
   ```
   /plugin marketplace add cportka/claude-plugins
   /plugin install video-bug-analyzer@portka-tools
   /plugin install app-website-evaluator@portka-tools
   /plugin install repo-bootstrap@portka-tools
   ```

## 6. Announce (optional, by audience)

For a dev-tool marketplace: a Show HN, the relevant subreddits, dev.to/Hashnode, and an
awesome-claude / awesome-mcp list PR are the natural channels. (Fittingly, the
`app-website-evaluator` skill can draft this growth plan for the repo itself.)

## Post-release

- Continue dogfood-driven feature work on new RC branches (`claude/vX_Y_Z-rcN`), squash-merging to
  `main`; only tag when cutting the next real release.
- The **Plugin feedback** issue form (`.github/ISSUE_TEMPLATE/plugin-feedback.yml`) is the intake;
  triage each into a CHANGELOG-tracked change.
