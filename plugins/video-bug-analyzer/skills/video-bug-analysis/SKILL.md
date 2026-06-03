---
name: video-bug-analysis
description: Analyze a screen-recording / video of a bug by extracting frames and diagnosing it. Use when the user provides a video or screen recording of a bug, glitch, crash, freeze, or UI problem to investigate or fix.
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

A **still screenshot of the bad moment** beats hunting inside a clip — prefer it.

## 2. Extract frames

```
${CLAUDE_PLUGIN_ROOT}/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video <path> [--start <ts>] [--end <ts>] [--fps <n>] [--scene <thr>] [--contact]
```

- **Known moment:** dense (`--fps 4`–`10`) over a tight `--start`/`--end`. Never 1 fps
  across the whole clip — transient glitches fall between samples.
- **Unknown moment:** `--scene 0.1` first to find transitions, then re-extract densely.
- **Overview cheaply:** `--contact` tiles frames into one image; read it to locate the
  region, then re-extract that region densely. Fewer files, fewer tokens.

`ffmpeg` is auto-installed (SessionStart hook, with on-first-use fallback).

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
