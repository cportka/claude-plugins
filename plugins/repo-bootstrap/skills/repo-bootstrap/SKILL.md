---
name: repo-bootstrap
description: Set up a repository to use Claude Code plugins from the portka-tools marketplace, especially for Claude Code on the web. Use when the user wants to onboard a repo to a marketplace/plugin, enable a portka-tools plugin in a specific repo, or scaffold .claude/settings.json (and optional CI) so plugins load in ephemeral web sessions.
---

# Repo Bootstrap

Set up a repository so Claude Code can use marketplace plugins in it — including
**ephemeral web sessions**, where `~/.claude` does not persist and a user-level install is
gone every session. The durable mechanism is a committed **`.claude/settings.json`** that
(a) declares the marketplace and (b) enables the plugins. This skill writes that file for
you and can add a CI workflow.

## When to use which path

- **Local CLI, all your repos:** you don't need this skill — run `/plugin marketplace add
  cportka/claude-plugins` then `/plugin install <name>@portka-tools` once; it persists in
  `~/.claude` across every local repo.
- **A specific repo / Claude Code on the web:** use this skill. The committed
  `.claude/settings.json` is what makes the plugin load in fresh containers.

## Step 1 — Decide what to enable

Ask the user (skip what they've given):

- Which **plugins** to enable (e.g. `video-bug-analyzer`). Default marketplace is
  `portka-tools` (repo `cportka/claude-plugins`); override only if they use another.
- Whether to also add a **`validate` CI workflow** (runs `tests/run-tests.sh` when present).

## Step 2 — Run the bootstrap script

```
${CLAUDE_PLUGIN_ROOT}/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
  --plugin <name> [--plugin <name> ...] [--ci] [--dir <repo-root>]
```

It **merges** into any existing `.claude/settings.json` (never clobbers other keys), is
idempotent, and refuses to overwrite an existing CI workflow unless `--force` is given.
Defaults: marketplace name `portka-tools`, marketplace repo `cportka/claude-plugins`.

Example — enable the video bug analyzer and add CI:

```
${CLAUDE_PLUGIN_ROOT}/skills/repo-bootstrap/scripts/bootstrap-repo.sh \
  --plugin video-bug-analyzer --ci
```

## Step 3 — Review and commit

Show the user the resulting `.claude/settings.json`. It should look like:

```json
{
  "extraKnownMarketplaces": {
    "portka-tools": { "source": { "source": "github", "repo": "cportka/claude-plugins" } }
  },
  "enabledPlugins": { "video-bug-analyzer@portka-tools": true }
}
```

**Commit `.claude/settings.json`** (and any workflow). It only takes effect once committed,
because web sessions clone the repo fresh and read it at session start.

## Step 4 — Verify

- The file is valid JSON and contains the marketplace under `extraKnownMarketplaces` and
  each plugin under `enabledPlugins` as `<name>@<marketplace>`.
- In a new session for that repo, the plugin's skills/commands are available. (In the local
  CLI you can also confirm with `/plugin`.)

## Notes

- This sets repo-level config; it does not install anything globally.
- If `.claude/settings.json` already exists but is invalid JSON, the script stops and asks
  you to fix it rather than risk losing data.
