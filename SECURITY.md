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
