---
name: repo-bootstrap
description: Set up a repository to use Claude Code plugins from the portka-tools marketplace, especially for Claude Code on the web. Use when the user wants to onboard a repo to a marketplace/plugin, enable a portka-tools plugin in a specific repo, or scaffold .claude/settings.json (and optional CI) so plugins load in ephemeral web sessions.
---

# Repo Bootstrap

Make marketplace plugins load in a repo — including **web sessions**, where `~/.claude`
doesn't persist. The durable mechanism is a committed **`.claude/settings.json`** that
declares the marketplace and enables the plugins. This skill writes it (and optional CI).

Local-CLI-only use doesn't need this: `/plugin marketplace add cportka/claude-plugins` then
`/plugin install <name>@portka-tools` persists in `~/.claude` across all local repos.

## Steps

1. **Ask** which plugins to enable (e.g. `video-bug-analyzer`) and whether to add CI.
   Default marketplace: `portka-tools` (`cportka/claude-plugins`).
2. **Run** the script:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
     --plugin <name> [--plugin <name> ...] [--ci] [--dir <repo-root>] [--dry-run] [--auto-update]
   ```
   `--dry-run` previews without writing. `--auto-update` also sets `"autoUpdate": true` on the
   marketplace entry — but note that for third-party marketplaces it currently refreshes the
   catalog without re-installing plugin code (anthropics/claude-code#61854); tell the user the
   reliable way to get a published fix is `claude plugin update <name>@<marketplace>`.
   It merges into any existing `.claude/settings.json` (never clobbers other keys), is
   idempotent, and won't overwrite a CI workflow without `--force`. If the existing settings
   file is invalid JSON it stops rather than risk losing data.
3. **Review + commit** `.claude/settings.json` (and any workflow). It only takes effect once
   committed — web sessions clone the repo fresh and read it at session start.

Resulting file:

```json
{
  "extraKnownMarketplaces": {
    "portka-tools": { "source": { "source": "github", "repo": "cportka/claude-plugins" } }
  },
  "enabledPlugins": { "video-bug-analyzer@portka-tools": true }
}
```
