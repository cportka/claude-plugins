---
name: repo-bootstrap
description: Set up a repository to use Claude Code plugins from the portka-tools marketplace, especially for Claude Code on the web. Use when the user wants to onboard a repo to a marketplace/plugin, enable a plugin in a specific repo, scaffold .claude/settings.json (+ optional CI) for ephemeral web sessions, or asks for the Portka standard / to standardize how Claude works in a repo.
---

# Repo Bootstrap

Make marketplace plugins load in a repo — including **web sessions**, where `~/.claude`
doesn't persist. The durable mechanism is a committed **`.claude/settings.json`** that
declares the marketplace and enables the plugins. This skill writes it (and optional CI).

Local-CLI-only use doesn't need this: `/plugin marketplace add cportka/claude-plugins` then
`/plugin install <name>@portka-tools` persists in `~/.claude` across all local repos.

## Steps

1. **Ask** which plugins to enable (e.g. `video-bug-analyzer`), whether to add CI, and whether to
   apply the **Portka standard setup** (`--portka-standard`, below).
   Default marketplace: `portka-tools` (`cportka/claude-plugins`).
2. **Run** the script:
   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
     --plugin <name> [--plugin <name> ...] [--ci] [--dir <repo-root>] [--dry-run] [--auto-update] \
     [--portka-standard] [--scope user|project|both] [--print-only]
   ```
   `--dry-run` previews without writing (and states the real outcome per file). `--auto-update`
   is catalog-only on third-party marketplaces — `claude plugin update <name>@<marketplace>` is
   the reliable refresh (see `--help`). Merges never clobber other keys; invalid existing JSON
   stops the run rather than risk data loss.
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

## Portka standard setup (`--portka-standard`)

Adds the standing **"how we work" setup** so each session stays focused on the code instead of
re-explaining process (all idempotent, never clobbering; the full inventory is in `--help`):
the managed **workflow `CLAUDE.md`** block, a git/`gh` **permissions allowlist**, an enforced
**SemVer sync** bound to the repo's existing version source with a `tests/run-tests.sh` + CI
(native `node --test`/`pytest` version-sync tests for JS/Python repos), and — at user scope —
the **corrected `stop-hook-git-check.sh`** that stops hosted sessions false-flagging GitHub's
squash-merge commits and the repo's declared commit identity (also auto-refreshed by this
plugin's SessionStart hook each session).

The decisions the agent must make: **which plugins**, **`--scope`** (`user` = `~/.claude`,
`project` = committed `./.claude` for web sessions + team, `both` = default), and **committing
the project files** so fresh web sessions pick them up. Existing files are never overwritten
(test runner only with `--force`); `--home` redirects user-scope writes (mainly for tests).

## When the `.claude/settings.json` write is blocked (`--print-only`)

In a **web session under auto mode**, Claude Code's permission classifier can **refuse** an
agent-written `.claude/settings.json` (it flags adding a marketplace + enabling plugins + a
permissions allowlist as untrusted self-modification). That's the very file this skill exists to
write. When that happens:

1. **Ask the user to approve** the write explicitly, rather than silently eating the denial.
2. If still blocked, run with **`--print-only`**: it prints the exact `.claude/settings.json` (and,
   with `--portka-standard`, the `CLAUDE.md` workflow block) to stdout. Have the **user create/paste
   the file by hand** — a human-authored write isn't classifier-gated — then commit it. The
   version/sync scaffold isn't classifier-gated, so re-run without `--print-only` to write it.
