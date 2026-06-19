---
name: video-bug-analysis
description: Diagnose a UI or rendering bug from a screen recording by extracting frames and reasoning over them. Use when the user shares a video or screen recording (e.g. a .mov or .mp4) of a bug, glitch, flicker, crash, freeze, or incorrect rendering — especially with an approximate timestamp — and wants it investigated or fixed.
---

# Video Bug Analysis

You can't watch video — only **still frames** `ffmpeg` extracts. Reconstruct the bug from
those snapshots plus what the user tells you. Work this way:

## 1. Get context first

Ask for whatever's missing:

- **When** the bug appears (a timestamp/range like "~0:12") — the biggest accuracy lever.
- **Repro steps** and **expected vs. actual**.
- **Console / network / logs** — invisible in the video unless devtools are on screen, and
  often the real cause.
- **Relevant code area**, if known.

A **still screenshot of the bad moment** beats hunting inside a clip — **prefer it, and ask
for one** whenever a timestamp is fuzzy or ffmpeg isn't available (see the ffmpeg note below).

## 2. Extract frames

```
${CLAUDE_PLUGIN_ROOT}/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video <path> [--fps <n>] [--scene <thr>] [--contact] [--timestamps <t1,t2>]
```

Default workflow:

1. **Overview:** `--fps 2 --contact` → one contact sheet of the whole span; read it to find
   where the symptom is. For **text/code-heavy UIs add `--text`** (bigger tiles) or the sheet
   will be illegible.
2. **Zoom:** `--timestamps 0:12,0:34 --fps 8` → per moment, a dense burst (catches
   sub-second transients) plus a **before/after strip** (`tsNN_strip.png`) that's the best
   way to show the user a one-frame change.

Other knobs: `--scene 0.1` to find transitions when the moment is unknown; `--start/--end`
for a manual window; `--window`/`--frame-width` to tune bursts; **`--strip a.png,b.png`** to
stitch a before/after from two frames you already extracted. Tighten the window rather than
raising fps across the whole clip.

Frames default to `.frames/<video-name>/` (so analyzing a second clip won't clobber the
first); pass `--out <dir>` to choose. If the clip's real frame rate is below your `--fps`,
the script warns that extra fps just repeats frames.

**ffmpeg note:** ffmpeg is already on PATH in many environments (incl. many web containers).
If it's missing the plugin tries apt → brew → a GitHub static build; a locked-down sandbox
may block that or require approval. If it truly can't be installed, **don't keep retrying —
ask the user to approve the install OR (simpler) paste a still screenshot of the bad moment.**

## 3. Build a timeline

Read the PNGs in filename order; note what's on screen, what changes between frames, and
where the symptom first appears. Cite frames by filename.

## 4. Confirm in the code

Frames give the symptom and its location; the fix comes from the **source**. Read the
implicated component/handler/state before proposing a change — never patch from pixels alone.

## 5. Report with confidence + caveats

Label what you saw vs. inferred, and how sure you are. Call out the limits that apply:

- Gaps between samples hide fast flickers / one-frame glitches.
- Timing/race bugs: frames give no real sense of duration.
- Small text / subtle diffs are easy to misread or hallucinate — verify against code.
- Off-screen state (console/network/memory) is invisible.

When unsure, ask for a denser extraction, a tighter timestamp, or a still — don't guess.

See `reference.md` for the reliability matrix, fps-per-bug-class table, and checklist.

## Reporting feedback

If the user wants to report a problem or suggestion, run
`${CLAUDE_PLUGIN_ROOT}/skills/video-bug-analysis/scripts/report-feedback.sh`
(`--ran`/`--outcome`/`--notes` optional) — it prints a copy-paste report **and a prefilled
one-click GitHub issue link**. If you have a GitHub MCP/`gh` with write access to
`cportka/claude-plugins`, file it directly; otherwise hand the user the link (it needs no
GitHub scope or session network — it just opens in a browser).
