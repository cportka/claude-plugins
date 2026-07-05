# Privacy

**Short version: these plugins don't collect, store, or transmit your data. Everything runs
locally on your machine (or inside your Claude Code sandbox). There is no telemetry, no analytics,
no accounts, no cookies, and no tracking.**

_Last updated: 2026-07-05._

## What happens to your content

The plugins process your files **in place** and never upload them:

- **video-bug-analyzer** runs `ffmpeg` on your video locally and writes frames to a local folder.
- **app-website-evaluator** in `--dir` mode reads a local build/repo; nothing leaves your machine.
- **tab-chord-formatter** formats text locally; the PDF is rendered by a local headless Chromium.
- **repo-bootstrap** only reads and writes files in the repo you point it at.

Your videos, screenshots, tab sheets, site builds, and their extracted results stay on your device.

## The only times anything talks to the network

All outbound requests are for the tool's stated job — none of them send your content anywhere:

1. **Installing `ffmpeg` (optional).** If `ffmpeg` is missing, `video-bug-analyzer` may download it
   from your OS package manager (apt/Homebrew) or a public static build on GitHub — only when it's
   absent and your environment permits it. You can skip this by installing `ffmpeg` yourself.
2. **`--check-update` (video-bug-analyzer).** Fetches the marketplace's public `plugin.json` from
   GitHub to compare version numbers. It sends no data about you — just an anonymous GET, and only
   when you run that flag.
3. **`app-website-evaluator --url <site>`.** Fetches the site **you specify** (plus its
   `robots.txt` / `sitemap.xml` / `llms.txt` and response headers), the same as any HTTP client.
   Use `--dir` for a fully offline audit.

That's the complete list. Nothing else phones home.

## Feedback issues are public and user-initiated

The "Plugin feedback" flow builds a **pre-filled GitHub issue link** — it doesn't submit anything
on its own. If you choose to open and post that issue, whatever you type or attach becomes public on
GitHub. Don't include anything sensitive.

## Running inside Claude Code

These plugins run inside [Claude Code](https://code.claude.com). Claude Code's own data handling is
governed by **Anthropic's [Privacy Policy](https://www.anthropic.com/legal/privacy)** — the plugins
don't change or extend it. Any third-party tools a plugin invokes (`ffmpeg`, `tesseract`, headless
Chromium, `curl`, `python3`) behave according to their own projects.

## The website

The landing page at [cportka.github.io/claude-plugins](https://cportka.github.io/claude-plugins/)
is a static page with **no analytics, trackers, cookies, or third-party scripts**. It's served by
GitHub Pages, which may log ordinary request metadata (e.g. IP address) per
[GitHub's Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Changes & contact

This is a small open-source project; this document may change as the plugins evolve, with the date
above updated. Questions or concerns? Open an issue on
[the repository](https://github.com/cportka/claude-plugins/issues).
