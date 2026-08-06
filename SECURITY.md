# Security Policy

Thanks for helping keep `portka-tools` and its users safe.

## Reporting a vulnerability

**Please report privately — do not open a public issue for a security problem.**

- **Preferred:** GitHub private vulnerability reporting —
  **[Report a vulnerability](https://github.com/cportka/claude-plugins/security/advisories/new)**
  (repo → **Security** → *Report a vulnerability*). This opens a private channel with the maintainer.

You'll get an acknowledgement within a few days. Once a fix is ready we'll coordinate a release and
credit you in the advisory unless you'd rather stay anonymous. There's no bounty — this is a small
open-source project — but reports are genuinely appreciated.

## What these plugins do and don't do on your machine

The full disclosure, as of **1.15.0**. The governing rule: **nothing privileged, global, or
unverified happens without an explicit, per-invocation opt-in.** A SessionStart hook runs unattended
at every session start and can never ask you anything, so hooks here only ever *report*.

| | Default behavior | Opt in with |
| :-- | :-- | :-- |
| Install software / run `sudo` | **Never.** `extract-frames.sh` reports missing `ffmpeg`/`ffprobe` and stops; the SessionStart hook only reports. | `VBA_ALLOW_INSTALL=1` (package manager, may use sudo) |
| Download a binary | **Never.** | `VBA_ALLOW_DOWNLOAD=1` — and the archive must pass a checksum (`VBA_FFMPEG_SHA256` pin, else the publisher's `.sha256`/`.md5`); an unverifiable download is **refused** unless you also set `VBA_ALLOW_UNVERIFIED=1`. Installs into the plugin's own cache dir, never system-wide. |
| Write into the repository you're working in | `.claude/*` files that `repo-bootstrap` is explicitly invoked to write, plus `git config user.name/email` in that repo when it commits its own `.claude/commit-identity` and the identity is unset or a `noreply@` default. Opt out with `PORTKA_NO_IDENTITY=1`. | — |
| Write into `~/.claude` | `bootstrap-repo.sh --portka-standard` with `--scope user` or `both` (**`both` is that flag's default**) writes `~/.claude/CLAUDE.md` and merges the git/`gh` allowlist into `~/.claude/settings.json` — that is the documented purpose of user scope. Pass `--scope project` to keep everything inside the repo. Nothing else writes there. | `--scope user`/`both` (explicit command) |
| Replace `~/.claude/stop-hook-git-check.sh` | **Never automatically** — not from the SessionStart hook, and not from `--portka-standard` either (both only report it). | `bootstrap-repo.sh --heal-stop-hook`, or `PORTKA_HEAL_STOP_HOOK=1` for one session. A `.stock.bak` backup is kept (an existing one is never overwritten), a customized hook is never touched, and a consented heal only ever writes inside **your** `$HOME` — a stock hook found in another account's home is reported, not modified. |
| Network access | `--check-update` (a version string from raw.githubusercontent.com) and `app-website-evaluator --url` (the site you asked it to audit). No telemetry, ever. | — |

Prior versions (≤ 1.14.1) installed `ffmpeg` via `sudo apt-get` from the SessionStart hook and
replaced the stock stop-hook silently on every session. Both were removed in 1.15.0; the test suite
now asserts that no shipped hook contains an executed `sudo`/package-manager/download command.

## What's in scope

These plugins are local Claude Code tools (shell + Python scripts). The security-relevant surface:

- **Malicious input handling** — a crafted video/image, or (in `app-website-evaluator --url` mode) a
  hostile web response, that makes a plugin crash, hang, write outside its output directory, or run
  an unintended command.
- **Argument / path injection** — a filename, ROI, URL, or flag value that escapes the intended
  quoting into a shell, `ffmpeg`, or `python` call.
- **Supply chain** — `video-bug-analyzer` can download an `ffmpeg` static build when `ffmpeg` is
  missing and the environment permits it; issues with that install path are in scope.

**Out of scope:** vulnerabilities in the third-party tools themselves (`ffmpeg`, `tesseract`,
headless Chromium, `curl`, `python`) — report those upstream; anything that requires an
already-compromised machine or account; and the security of Claude Code / the Anthropic platform,
which is [Anthropic's](https://www.anthropic.com/legal/privacy) to handle.

## Supported versions

Only the **latest release** is supported. Fixes ship in a new version following
[SemVer](https://semver.org); see [CHANGELOG.md](./CHANGELOG.md). Update with
`claude plugin update <name>@portka-tools`.

## Security posture

- Scripts run **locally** with your own privileges and process your files in place — they don't
  collect, store, or transmit your data. See [PRIVACY.md](./PRIVACY.md) for the full network
  touchpoint list.
- No servers, secrets, accounts, or user data are held by this project.
- Every change is gated by CI + a test suite, and non-trivial changes get an adversarial review
  before merge; scripts are `shellcheck`-clean and run under `set -euo pipefail`.

A machine-readable contact is published at
[`/.well-known/security.txt`](https://cportka.github.io/claude-plugins/.well-known/security.txt)
([RFC 9116](https://www.rfc-editor.org/rfc/rfc9116)).
