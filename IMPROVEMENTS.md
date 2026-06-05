# Improvements & Known Weaknesses

Honest notes on what each plugin does well, where it's weak, and how it could improve. Kept
here — not in the skills — so the in-context instructions stay lean. User-reported problems
arrive via the **Plugin feedback** issue form and are triaged into the items below.

## video-bug-analyzer

**Strengths**
- Repeatable frame extraction tuned to the bug: dense / scene-change / contact-sheet.
- Contact-sheet mode reads a whole span in one image — large token saver.
- The skill states confidence and caveats instead of bluffing.
- ffmpeg is handled (SessionStart hook + on-first-use fallback).

**Weaknesses / cons**
- Blind between samples: fast flickers and one-frame glitches can be missed.
- No true timing: race / ordering / duration bugs are poorly served by frames.
- Off-screen state (console / network / memory) is invisible.
- Scene-change mode is heuristic; the threshold needs tuning per clip.
- Many PNGs (token cost) if the window/fps isn't tightened.

**Ideas**
- `ffprobe`-based auto-duration and suggested fps/window.
- Auto-fallback to a contact sheet when frame count would blow a token budget.
- Optional per-frame timestamp burn-in for clearer timeline references.
- A crop/region flag to zoom on a UI area and cut tokens.

**Shipped**
- 0.2.2: `-fps_mode vfr` on modern ffmpeg (was deprecated `-vsync`), with `-vsync` fallback
  and an ffmpeg-version diagnostic line.
- 0.2.3: static-ffmpeg download fallback (apt → brew → static build → screenshot advice) in
  both the extractor and the SessionStart hook, for sessions where the package manager
  can't install ffmpeg. Only helps where outbound https is allowed.

## repo-bootstrap

**Strengths**
- Non-clobbering, idempotent JSON merge; refuses to touch invalid settings.
- One command wires up web-session plugin loading + optional CI.

**Weaknesses / cons**
- Requires `python3` (assumed present; no pure-bash fallback).
- Generated CI is intentionally minimal (runs `tests/run-tests.sh` if present).
- Doesn't validate that the named plugin actually exists in the marketplace.
- No `CLAUDE.md` or test-harness scaffolding yet.

**Ideas**
- Validate `--plugin` names against the marketplace; add `--list`.
- Optional `CLAUDE.md` and `tests/run-tests.sh` starters.
- `jq` fallback when `python3` is absent.

## Repo / tests

**Strengths**
- One self-contained runner; tool-dependent steps SKIP cleanly; CI runs them for real.
- Covers manifests, marketplace↔plugin consistency, versions, frontmatter, hooks, script
  CLI, bootstrap scaffolding, and ffmpeg extraction.

**Weaknesses / cons**
- Version-sync check is a substring match, not a structured table parse.
- No markdown link-checking or spell/style linting.
- Single CI job (ubuntu); no macOS leg for the `brew` install path.

**Ideas**
- Structured README-table ↔ `plugin.json` version check.
- Markdown link lint; optional macOS CI leg.
