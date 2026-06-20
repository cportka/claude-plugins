---
name: video-bug-analysis
description: Extract frames from a screen recording or video and reason over them — to diagnose a UI/rendering bug (glitch, flicker, crash, freeze, wrong render) OR to read and inventory on-screen text/UI (catalog a site's features, transcribe a demo, describe what's shown). Use whenever the user shares a video or screen recording (.mov/.mp4/.webm) and wants it analyzed or read, especially with an approximate timestamp.
---

# Video Bug Analysis

You can't watch video — only **still frames** `ffmpeg` extracts. Reconstruct what happened
from those snapshots plus what the user tells you. Despite the name, this also handles
**non-bug "read the screen" tasks** — inventorying a site's features, transcribing a demo,
or describing on-screen UI from a recording. Work this way:

> **Reading dense text/UI (not a bug)?** Skip the contact sheet — extract **full-resolution
> individual frames** (`--fps 1` to `2`, no `--contact`) and read them one by one. Contact
> tiles downscale too far for small text, especially on tall **portrait** phone captures
> (where the script auto-drops to `--cols 2`, but individual frames still read best).

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

For motion/timing work: **`--list-scenes`** prints the timestamps of detected scene cuts
(feed them into `--timestamps`); **`--diff`** emits frame-difference images (bright = what
moved, to confirm motion/direction); **`--label`** burns the source timestamp onto each
frame (dense/`--diff`/`--timestamps`; best-effort — needs ffmpeg drawtext + a font).

To zoom a small UI region (an on-screen FPS counter, a HUD, a tiny label), pass
**`--crop W:H:X:Y`** (ffmpeg geometry, e.g. `--crop 320:120:40:900`): the region is cropped
out and scaled up to fill the frame, so a few pixels become legible and tokens stay low.
Works in every mode (dense/scene/contact/diff/timestamps); `iw`/`ih` expressions allowed.

For a **black/blank-screen bug**, run **`--blackdetect`**: it reports each blacked-out span
as `black START -> END (dur) — PERMANENT/transient`, where *permanent* means it never
recovers before EOF — the key diagnostic for a stuck/crashed renderer. If a static UI overlay
(a settings panel, a HUD) keeps a few pixels lit, blackdetect can miss the blackout; crop to
the app canvas first with `--crop` (and/or lower `--black-ratio`, default 0.98).

Frames default to `.frames/<video-name>/` (so analyzing a second clip won't clobber the
first); pass `--out <dir>` to choose. If the clip's real frame rate is below your `--fps`,
the script warns that extra fps just repeats frames. Add **`--dry-run`** to print the exact
ffmpeg commands without running them — handy for replicating the workflow by hand (e.g. in a
session where the plugin isn't loaded).

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

`extract-frames.sh` already prints a **one-click, pre-filled feedback link** (plugin + ffmpeg
version + the exact command, encoded) on stderr at the end of each run — surface that line to
the user and encourage a click; it's how the tool improves. (Suppress with
`VBA_NO_FEEDBACK_HINT=1`.) For a fuller report, run
`${CLAUDE_PLUGIN_ROOT}/skills/video-bug-analysis/scripts/report-feedback.sh`
(`--ran`/`--outcome`/`--notes` optional). If you have a GitHub MCP/`gh` with write access to
`cportka/claude-plugins`, file it directly; otherwise hand the user the link (it needs no
GitHub scope or session network — it just opens in a browser).

**Session timing:** plugins load at session *start*, so a video dropped right after the
plugin was enabled won't have the skill/commands available until the next session. Enable one
session ahead; if a request arrives early, `extract-frames.sh --dry-run …` prints the exact
ffmpeg commands to run by hand.
