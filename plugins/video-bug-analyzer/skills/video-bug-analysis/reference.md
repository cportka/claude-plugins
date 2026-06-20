# Video Bug Analysis — Reference

Detail for the `video-bug-analysis` skill: checklist, reliability matrix, extraction tuning.

## Diagnosis checklist

1. **Context captured?** Timestamp/range, repro steps, expected vs. actual, console/network
   output, relevant code area.
2. **Extraction matched to the bug?** Dense fps around a known moment; scene-change first
   pass when unknown. Re-extract denser if the cause falls between frames.
3. **Timeline built?** Ordered list of observed states and the first frame where the
   symptom appears.
4. **Code located?** The component/handler/state behind the symptom has been read.
5. **Confidence + caveats stated?** Each conclusion labeled; relevant limitations called out.
6. **Next step offered when unsure?** Denser extraction, tighter timestamp, or a still
   screenshot — instead of guessing.

## Reliability matrix

| Bug class | Reliability from frames | Why |
| :-- | :-- | :-- |
| Persistent broken layout / missing element / wrong text | **High** | On screen long enough to be sampled |
| Visible error message / stack trace / modal | **High** | Static, legible if resolution is decent |
| Wrong color / theme state | **Medium** | Can be sampled, but shades can be misjudged |
| Transient flash / one-frame flicker | **Low** | Falls between samples unless fps is very high |
| Timing / race / ordering bug | **Low** | No true sense of duration between frames |
| Subtle visual diff (few px, small font) | **Low** | Easy to misread; risk of hallucinated detail |
| Console / network / memory issue | **None** (from video) | Not rendered unless devtools are on screen |

## Recommended extraction settings

| Situation | Suggested flags |
| :-- | :-- |
| Cheap timeline overview (do this first) | `--fps 2 --contact` (add `--text` for code/UI) |
| Zoom on flagged moment(s) | `--timestamps 0:12,0:34 --fps 8` (burst + before/after strip) |
| Before/after from two frames you have | `--strip before.png,after.png` |
| Known timestamp, normal UI bug | `--start <t-1s> --end <t+1s> --fps 4` |
| Known timestamp, fast/flicker bug | `--timestamps <t> --fps 15 --window 0.5` |
| Unknown moment, long clip | `--scene 0.1` first pass, then dense around the hit |
| Slow/steady-state bug | `--fps 1` over the relevant span is fine |

Higher fps = more frames = more tokens; tighten the window rather than raising fps across
the whole clip. Frames are width-scaled by mode: contact tiles to `--tile-width` (default
480; `--text` bumps to 640 for code/transcript legibility), timestamp bursts to
`--frame-width` (820), and dense / scene frames are capped at `--max-width` (1280) so native
4K recordings don't blow tokens (smaller clips are never upscaled).

**Contact-sheet (`--contact`)** tiles frames into one image (`--cols`/`--rows`), ordered
left-to-right, top-to-bottom in time. Scan it, then zoom. Use `--text` for text/code UIs.
Portrait phone captures auto-drop to `--cols 2` (or pass `--portrait`); the script warns when
tiles downscale the source so far that small UI text will be illegible.

**Dry run (`--dry-run`)** prints the exact ffmpeg command(s) it would run — no ffmpeg needed,
nothing written. Use it to replicate the workflow by hand when the plugin isn't loaded in the
current session, or to inspect/tweak a command before running it.

**Motion/timing options:** `--list-scenes` prints detected scene-cut timestamps (seconds; tune
with `--scene <thr>`, default 0.3) so you can feed the interesting ones into `--timestamps`.
`--diff` emits frame-difference images (`tblend`) where bright pixels = change between
consecutive frames — scan them to see what moved and infer direction. `--label` burns the
source timestamp (`drawtext`) onto each frame in dense/`--diff`/`--timestamps` modes (not
contact tiles); it's best-effort and silently skips if the ffmpeg build lacks drawtext/a font.

**Reading dense text/UI** (inventory features, transcribe a demo — not a bug): contact sheets
pack too tightly for small text. Extract **full-resolution individual frames** (`--fps 1`–`2`,
no `--contact`) and read them one at a time. This is the most reliable path for portrait phone
captures.

**Strip (`--strip a.png,b.png`, alias `--compare`)** hstacks two existing frames into
`strip.png` — a before/after with no re-extraction; needs no `--video`.

**Timestamps (`--timestamps "t1,t2"`)** — per moment, a dense `--fps` burst over a
`±--window` (default 0.5s) plus a `tsNN_strip.png` **before/after strip** (first & last burst
frame side by side). The strip is the clearest way to show the user a one-frame transient.

**Output & sparse clips** — frames default to `.frames/<video-name>/` so analyzing a second
clip in the same session doesn't overwrite the first (`--out` overrides; `--strip` uses
`.frames`). `--strip` scales both inputs to a common height, so mismatched resolutions
(e.g. a `.mov` vs a `.webm` frame) still stitch. If a clip's real frame rate (via `ffprobe`)
is well below `--fps`, the script warns that the extra fps just repeats frames.

## When frames aren't enough

Ask the user for one of these instead of guessing:

- A **still screenshot** of the exact bad moment (most reliable).
- A **tighter timestamp** so you can sample densely in a small window.
- The **console/network logs** for the same moment, since those are invisible in the video.
