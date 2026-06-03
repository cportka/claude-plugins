---
name: video-bug-analysis
description: Analyze a screen-recording / video of a bug by extracting frames and diagnosing it. Use when the user provides a video or screen recording of a bug, glitch, crash, freeze, or UI problem to investigate or fix.
---

# Video Bug Analysis

You are diagnosing a bug from a **screen-recording video**. You cannot watch video — you
only ever see **still frames** that `ffmpeg` extracts. Everything you conclude about
"what happens" is reconstructed from a discrete set of snapshots plus what the user tells
you. Follow this workflow; it is built around that limitation.

## Step 1 — Gather context before extracting anything

Ask the user (skip any they've already given):

- **When** does the bug appear? An approximate timestamp or range (e.g. "around 0:12") is
  the single biggest lever on accuracy — it lets you sample densely at the right moment.
- **Repro steps** and **expected vs. actual** behavior.
- Any **console output, network errors, or logs** — these do not appear in the video
  unless devtools are literally on screen, and they are often the real cause.
- The **relevant code area / repo**, if known.

If the user can give a **still screenshot of the exact bad moment**, prefer it — a single
correct frame is more reliable than asking you to find the moment inside a long clip.

## Step 2 — Extract frames

Use the bundled script:

```
${CLAUDE_PLUGIN_ROOT}/skills/video-bug-analysis/scripts/extract-frames.sh \
  --video <path> [--start <ts>] [--end <ts>] [--fps <n>] [--scene <thr>] [--out <dir>]
```

Guidance:

- **Known timestamp:** extract **densely** (`--fps 4` to `--fps 10`) over a tight
  `--start`/`--end` window around it. Do NOT sample 1 fps across the whole clip — that is
  how transient glitches get missed.
- **Unknown timestamp:** first pass with **scene-change mode** (`--scene 0.1`) to find
  transitions cheaply, then re-extract densely around the interesting region.
- The script prints the output directory and the number of frames it wrote.

## Step 3 — Read the frames in order

Read the extracted PNGs sequentially and build a **timeline** of observed UI states: what
is on screen, what changes between consecutive frames, where an error/glitch first
appears. Note the frame filename (it encodes order) for anything you reference.

## Step 4 — Cross-reference the code

The video gives you the **symptom and its location**. The **fix comes from reading the
actual source.** Locate the implicated component/handler/state before proposing any
change. Do not patch based on pixels alone.

## Step 5 — Report with explicit confidence

State what you saw, what you infer, and **how confident you are**, and call out the
limitations that apply (see `reference.md` for the full reliability matrix):

- Frames **between** samples are unseen — a fast flicker or one-frame render glitch can
  fall in a gap and look like "no bug."
- **Timing/race** bugs are poorly served by frames; you have no true sense of duration.
- **Small text and subtle visual diffs** can be misread, and you can occasionally
  hallucinate plausible-but-wrong details — verify against the code.
- **Off-screen state** (console, network, memory) is invisible unless rendered.

When uncertain, ask for a denser extraction, a tighter timestamp, or a still screenshot
rather than guessing.

See `reference.md` (in this skill directory) for the diagnosis checklist, the
reliable-vs-unreliable matrix, and recommended fps per bug class.
