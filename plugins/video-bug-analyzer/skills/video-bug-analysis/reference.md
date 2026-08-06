# Video Bug Analysis — Reference

What `--help` can't hold: the diagnosis checklist, reliability matrix, tuning tables, and the
misread traps. Flag syntax, defaults, and dependencies live in `extract-frames.sh --help` —
they are deliberately NOT restated here (drift between the two is how docs start lying).

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
| Transient flash / one-frame flicker | **Low** | Falls between samples unless fps is very high (`--content-revert` boosts to 10) |
| Timing / race / ordering bug | **Low** | No true sense of duration between frames (`--pacing` reads real timestamps) |
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

Higher fps = more frames = more tokens; tighten the window rather than raising fps across the
whole clip. Contact tiles, bursts, and dense frames are width-capped by mode (see `--help`) so
4K recordings don't blow tokens. **Reading dense text/UI** (inventory, transcription): skip
contact sheets — full-res individual frames (`--fps 1`–`2`, no `--contact`) read best,
especially portrait phone captures.

## Mode index (details: `--help`)

Extraction: `--contact` `--timestamps` `--intro` `--scene`/`--list-scenes` `--diff` `--strip`
`--stack` `--label` `--crop` `--text`. Analysis (CSV/verdict, no frames): `--stutter`(=`--cadence`)
`--pacing` `--stall` `--whiteout` `--content-revert` `--motion` `--flow` `--occupancy`
`--saturation` `--blackdetect` `--ocr-roi` `--measure` `--probe` `--palette`(`--over-time`)
`--loop-check` `--ab` `--compare-videos`. Cross-cutting: `--start/--end` (scope), `--t0`
(session-clock relabel for split captures, 1.11.0), `--marks` (perf-mark overlay on `--stutter`),
`--check-update`, `--dry-run`. Every run prints a one-line `playback cadence:` header (effective
vs nominal fps, duplicate-vs-dropped aware) — a measurement of frame timing only, never a
verdict on whether the content is correct.

## Interpretation guides (the part a flag listing can't teach)

**Choppiness family — pick the right axis.** `--stutter` = unique-CONTENT cadence + freeze gaps
(frozen moments during motion). `--pacing` = frame TIMING jitter (uneven presentation intervals
even when every frame differs). `--stall` = NOTHING changes for seconds (hang/dead canvas — reads
"smooth" to the other two). `--content-revert` = content goes BACKWARD (A→B→A; words dropped then
restored — playback smooth, content wrong). A static scene reads low on `--stutter` by design
(nothing new is drawn) — that's the honest signal, not a bug.

**Reading `--flow` (`t,speed,curl,div`):** spinning in place → |curl| high, div ≈ 0 · sucking
inward → div < 0 · expanding → div > 0 (under-measured — the matcher assumes translation) ·
spiral = both · panning → both ≈ 0. Raise `--fps` for fast motion (search caps ~8 px/frame);
it needs a textured subject and analyzes a bounded frame count — scope with `--start/--end`.

**`--ocr-roi` steer:** if the tracked value changes but no pixels near it change, the cause is
off-screen logic/state — stop extracting and move to console logs or a headless repro.

**`--measure`/`--probe` axis rule:** report sizes as % of viewport, and pick the axis by
orientation (CSS `vmin` = width in portrait, height in landscape — `--probe` says which).
Retina dpr makes raw device px misleading; the % columns are dpr-independent.

## Misread traps (each burned us once)

- **Motion amplitude floor:** whole-frame + downscale quantizes subtle motion toward 0, where
  "a little life" ≈ "frozen". Peak < ~3/255 → re-run `--motion --crop W:H:X:Y` on the region;
  still ~0 cropped = genuinely frozen (a clean A/B instrument for "did my fix add motion?").
- **`--blackdetect` overlay gotcha:** a persistent HUD/panel keeps pixels lit, so a real blackout
  can fall under the ratio — crop to the app canvas first (and/or lower `--black-ratio`).
- **Two-feature offset (annulus recipe, #89):** "is the ring centered on the body?" = measure A,
  then fit B with the fit **constrained to an annulus around A's center** — a naive hue filter
  ingests unrelated same-hue pixels (lensed star arcs, UI accents) and returns garbage.
- **`--compare-videos` phase axis:** rows align by % through each clip, not absolute time — an
  event at a different fraction won't line up columns (`--align-on scene` is a roadmap item;
  the global `--t0` offset shipped in 1.11.0 and covers split-capture session clocks).
- **`--content-revert` region discipline:** a looping animation inside the sampled region is
  A→B→A too and will (correctly) trigger — crop to the text/live region you actually care about.
- **Virtual-time captures:** a headless screenshot script that advances a fake clock does not
  drive the compositor — CSS animations won't advance and the capture looks frozen. Freeze
  animations via `getAnimations()[i].currentTime` per step, or capture on wall-clock time.

## "An animation didn't play" — a cause frames can't see

Frames prove an animation is **absent**, never **why** (element present but animation unstarted,
JS threw, `prefers-reduced-motion`, deferred first paint). Confirm absence from frames
(`--intro`), then pair a DOM/console capture (computed styles, `getAnimations()`, errors at t≈0)
with a code read — don't conclude cause from pixels.

## When frames aren't enough

Ask for a **still screenshot** of the exact moment (most reliable), a **tighter timestamp** for
dense sampling, or the **console/network logs** for that moment — instead of guessing.
