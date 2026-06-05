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
| Cheap timeline overview (do this first) | `--fps 2 --contact` |
| Zoom on flagged moment(s) | `--timestamps 0:12,0:34 --fps 8` (burst + before/after strip) |
| Known timestamp, normal UI bug | `--start <t-1s> --end <t+1s> --fps 4` |
| Known timestamp, fast/flicker bug | `--timestamps <t> --fps 15 --window 0.5` |
| Unknown moment, long clip | `--scene 0.1` first pass, then dense around the hit |
| Slow/steady-state bug | `--fps 1` over the relevant span is fine |

Higher fps = more frames = more tokens; tighten the window rather than raising fps across
the whole clip. Frames are width-scaled by mode: contact tiles to `--tile-width` (320),
timestamp bursts to `--frame-width` (820, enough to read transcript/UI text), and dense /
scene frames are capped at `--max-width` (1280) so native 4K recordings don't blow tokens
(smaller clips are never upscaled).

**Contact-sheet (`--contact`)** tiles frames into one image (`--cols`/`--rows`), ordered
left-to-right, top-to-bottom in time. Scan it, then zoom.

**Timestamps (`--timestamps "t1,t2"`)** — per moment, a dense `--fps` burst over a
`±--window` (default 0.5s) plus a `tsNN_strip.png` **before/after strip** (first & last burst
frame side by side). The strip is the clearest way to show the user a one-frame transient.

## When frames aren't enough

Ask the user for one of these instead of guessing:

- A **still screenshot** of the exact bad moment (most reliable).
- A **tighter timestamp** so you can sample densely in a small window.
- The **console/network logs** for the same moment, since those are invisible in the video.
