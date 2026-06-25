---
name: repo-bootstrap
description: Set up a repository to use Claude Code plugins from the portka-tools marketplace, especially for Claude Code on the web. Use when the user wants to onboard a repo to a marketplace/plugin, enable a portka-tools plugin in a specific repo, or scaffold .claude/settings.json (and optional CI) so plugins load in ephemeral web sessions. Also installs the Portka standard setup — a workflow CLAUDE.md, a git/gh permissions allowlist, and an enforced VERSION/CHANGELOG/README sync with a basic test suite — when the user asks for the Portka standard, or to standardize how Claude works in a repo.
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

## Portka standard setup (`--portka-standard`)

Adds the standing **"how we work" setup** so each session stays focused on the code instead of
re-explaining process. It writes (all idempotent, never clobbering):

- A **workflow `CLAUDE.md`** (a managed block between `<!-- BEGIN/END portka-standard -->`) encoding
  the Portka process: update `main` first, branch for every change, tests + CI then a PR, merge on
  green, and hand back a short PR link the user deletes as confirmation.
- A **permissions allowlist** for the git/`gh` commands that workflow runs, merged into
  `settings.json` (so the loop isn't gated on re-approving the same tools).
- For the repo: an enforced **SemVer** (`MAJOR.MINOR.PATCH`) version sync that **binds to the repo's
  existing version source** — `package.json` / `pyproject.toml` / `Cargo.toml` / a bare `VERSION` /
  a README `**Version:**` line — and only seeds a `VERSION` 0.1.0 on a truly greenfield repo. A basic
  **`tests/run-tests.sh`** *enforces* valid SemVer + that `CHANGELOG.md` and the README line agree
  (the README line is checked only if one exists), plus a specifically-named **`portka-standard.yml`**
  CI (skipped if the repo already has CI, to avoid collisions).

`--scope` controls where the `CLAUDE.md` + permissions go — `user` (`~/.claude`, your machine),
`project` (committed `./.claude`, for web sessions + team), or `both` (default). The
version/sync scaffold always lands in the repo; existing `VERSION`/`CHANGELOG`/`README` are never
overwritten (and the test runner only with `--force`). Use `--dry-run` to preview, and `--home` to
point user-scope writes somewhere other than `$HOME` (mainly for tests). Commit the project files so
they apply in fresh web sessions.

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
