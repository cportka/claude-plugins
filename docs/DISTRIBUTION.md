# Distributing portka-tools to the Claude Code community

How to get this marketplace discovered and installed. It complements [RELEASING.md](../RELEASING.md)
(which is about *cutting* a release); this is about *spreading* one.

**Shortcut:** [`scripts/publish.sh`](../scripts/publish.sh) automates the API-backed steps and prints
this checklist with your repo's details filled in:

```bash
scripts/publish.sh              # print the plan + manual checklist (changes nothing)
scripts/publish.sh --dry-run    # show the exact API commands it would run
scripts/publish.sh --run        # execute steps 2-4 (needs `gh auth login` or a GH_TOKEN)
scripts/publish.sh --run --release   # also cut the GitHub Release
```

Key naming nuance the whole ecosystem turns on: the **marketplace name is `portka-tools`** but the
**repo is `cportka/claude-plugins`**. Users *add* by repo and *install* by marketplace name:

```
/plugin marketplace add cportka/claude-plugins
/plugin install video-bug-analyzer@portka-tools
```

Because `marketplace.json` uses **relative** `./plugins/...` sources, the marketplace must be added
as a git repo (`owner/repo`) — never as a URL to `marketplace.json`, and the GitHub Pages URL is a
human landing page only, not an install source.

Confidence tags below: **[solid]** = verified against live 2026 docs; **[recheck]** = re-verify at
run time (auth-gated pages / fast-moving); **[low]** = mechanism uncertain.

---

## 1. Automatable — run via `scripts/publish.sh` (gh CLI or curl + `GH_TOKEN`)

1. **Validate first (the gate).** `claude plugin validate .` — the same check the submission pipeline
   runs. Kebab-case plugin names are required for the claude.ai sync. **[solid]**
2. **GitHub topics** — feed the aggregators and GitHub's own topic/search pages (Claude Code itself
   does *not* read topics — it reads `marketplace.json`). ~10 topics, e.g. `claude-code-plugin`,
   `claude-plugin`, `claude-code-marketplace`, `claude-code`, `claude-skills`, `mcp`, `anthropic`.
   `PUT /repos/OWNER/REPO/topics`. **[solid]**
3. **Description + homepage** — default-ranked GitHub search fields. Put the literal phrase "Claude
   Code plugin marketplace" + the add command in the description; homepage = the Pages URL.
   `PATCH /repos/OWNER/REPO`. **[solid]**
4. **GitHub Pages** — serve the landing page from `main` `/` (`index.html` + `.nojekyll` are already
   there). `POST /repos/OWNER/REPO/pages` (or `PUT` to reconcile if already enabled). **[solid]**
5. **GitHub Release** (optional, `--release`) — not required for installs (version resolves from
   `plugin.json` -> marketplace entry -> commit SHA), but nice for humans and release channels.
   The proxy blocks tag pushes from automation, so tag from your own shell:
   `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z` (fires `release.yml`). **[solid]**
6. **`marketplace.json` metadata** — add `keywords`/`homepage`/`repository`/`license` to each plugin
   entry (powers in-client Discover search + aggregator cards). Keep `version` in exactly one place
   (`plugin.json` **or** the entry). `publish.sh` *reports* the gaps; the edit goes via a PR. **[solid]**

## 2. One-time GitHub setting with no API

- **Social-preview image** — the Open Graph card shown when the repo is shared. The one metadata
  field with **no** REST/`gh` path: repo **Settings -> General -> Social preview -> Edit -> Upload**
  (1280x640 PNG, <1MB). Browser-automation tools exist but are best-effort, not a stable API. **[solid]**

## 3. External directories / registries

- **Anthropic community marketplace — the primary channel.** A web form (no PR/API):
  <https://clau.de/plugin-directory-submission> (individual authors:
  <https://platform.claude.com/plugins/submit>). Runs an automated safety + `claude plugin validate`
  review; on approval your plugin is pinned into `anthropics/claude-plugins-community` and the public
  catalog syncs **nightly**. Users then `/plugin marketplace add anthropics/claude-plugins-community`
  and install `<name>@claude-community`. **Do not open a PR** against that repo — it is a read-only
  mirror and direct PRs are auto-closed. **[solid]** (submit each of the four plugins)
  - The **official** directory (`claude.com/plugins`, auto-available in the client) is *curated by
    Anthropic at their discretion* — there is no self-serve form for it. Treat inclusion as a result
    of a high-quality repo + community traction, not a task. **[solid]**
- **awesome-claude-code** (hesreallyhim, ~48k stars) — the canonical list. **Issue form only, never a
  PR** (a PR risks an interaction ban): <https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml>.
  One-line factual description, no emojis. No dedicated Plugins category — file under the closest fit
  (e.g. Skills). **[solid]**
- **buildwithclaude** (davepoon, buildwithclaude.com) — PR-based, and a staging kit already exists at
  [`submissions/buildwithclaude/`](../submissions/buildwithclaude): `prepare.sh <fork>` stages a
  skill, then follow the printed branch/PR steps. Merges auto-deploy. **[solid]**
- **claudemarketplaces.com** — **auto-crawls GitHub daily** for repos with a valid
  `.claude-plugin/marketplace.json`. You already qualify; no submission — just verify the listing
  appears after the next sync. (Same passive model: `aitmpl.com/plugins`, `crossaitools.com`.) **[solid]**
- **Secondary awesome-lists** (lower authority, each PR-based): `ccplugins/awesome-claude-code-plugins`,
  `ComposioHQ/awesome-claude-plugins`, `rohitg00/awesome-claude-code-toolkit`. Standard fork -> add
  entry -> PR. **[solid]**
- **Smithery / Glama** — MCP-server-centric; only relevant if a plugin bundles an MCP server (none of
  ours do today). Skip unless that changes. **[low]**

## 4. Announcements (personal accounts; read each venue's rules first)

- **Show HN** — best fit for a runnable OSS dev tool. <https://news.ycombinator.com/submit>, URL = the
  repo (not the landing page). Title `Show HN: portka-tools - <plain one-liner>`; add a first comment
  with backstory; weekday-morning US; never ask for upvotes. **[solid]**
- **X/Twitter** — short thread + a demo GIF; tag `@ClaudeDevs`, `@AnthropicAI`; `#ClaudeCode`. **[solid]**
- **Reddit** — r/ClaudeCode (~292k) and r/ClaudeAI (~986k). **Read the sidebar / self-promo rules and
  any "show and tell" megathread first**, respect the 90/10 rule, don't paste identical text to both.
  **[recheck — rules govern, could not fetch live]**
- **dev.to** — a value-first tutorial; up to 4 tags (`#claudecode #claude #ai #devtools`); set
  `canonical_url` to the repo. Scriptable via `POST https://dev.to/api/articles` with a Settings key.
  Cross-post to **Hashnode** with the canonical URL set. **[solid]**
- **Official Claude Discord** — invite via <https://claude.com/community>; post a brief intro + link in
  the showcase/community-projects channel per the server's self-promo rules. **[solid]**
- **Newsletters** — no submit form; they discover you from the above. "This Week in Claude"
  (claudemarketplaces.com/digest) is the most marketplace-targeted. **[recheck]**

---

*This playbook was assembled by fact-checking each channel against live 2026 sources. Re-verify the
**[recheck]** items before relying on them — the Claude Code plugin ecosystem moves fast.*
