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

**Zoom a region (`--crop W:H:X:Y`):** crop a rectangle (ffmpeg geometry — width, height, and
top-left x, y, e.g. `--crop 320:120:40:900`) *before* scaling, so the region fills the frame.
Ideal for a tiny on-screen FPS/HUD readout, a counter, or a small status label that's too few
pixels to read at full-frame scale. Applies in every mode (dense/scene/contact/diff/
timestamps); `iw`/`ih` expressions are allowed (e.g. `--crop iw/4:ih/4:0:0` for the top-left
quadrant). Combine with `--fps 8`+ to catch a fast-changing counter, or `--diff` to see only
what changes inside the cropped region.

**Black-screen detection (`--blackdetect`):** for a blank/black-screen bug, this runs ffmpeg's
`blackdetect` filter and prints each black span as `black START -> END (dur) — PERMANENT/
transient`. **Permanent** = the span runs to (within 0.5s of) the end of the file — i.e. the
renderer went black and never recovered (a stuck NaN uniform, a crashed canvas), versus a
one-frame flash. Permanence classification needs `ffprobe` (for the source duration); without
it, spans are still listed. Tunables: `--black-min <sec>` (minimum span length, default 0.1)
and `--black-ratio <r>` (fraction of pixels that must be black, `pic_th`, default 0.98).
**Gotcha:** a persistent DOM/UI overlay (a settings panel, a HUD) keeps some pixels lit, so a
real blackout can fall under the ratio and be missed — crop to the app canvas first with
`--crop W:H:X:Y` (and/or lower `--black-ratio`, e.g. 0.90). Honors `--start`/`--end`.

**ROI value tracker (`--ocr-roi W:H:X:Y`):** OCRs a small region (a panel readout) once per
sampled frame and prints a `t,text` CSV to stdout — a *value timeline*. This is the tool for a
**state/logic bug whose symptom is a number, not a render artifact** (a body count flickering
4→5→4, a Speed value, a timer): scanning frames can't reveal it, but the timeline shows exactly
when the value jumped. `--ocr-digits` restricts recognition to digits + a few separators
(cleaner for counts/speeds); `--fps` sets the sample rate; honors `--start`/`--end`. Requires
`tesseract` — the only mode that needs more than ffmpeg; it prints an apt/brew install hint and
exits if tesseract isn't found. **Diagnostic steer:** if the value changes but no pixels near it
change, the cause is off-screen logic/state — stop extracting frames and move to console logs or
a small headless repro (the v0.14.5 dogfood needed a headless sim harness, not more frames).

**Capture context (`--probe`):** before measuring, print the clip's dimensions, aspect ratio,
**orientation** (portrait/landscape/square), fps, and duration. This matters because CSS `vmin`
maps to viewport *width* in portrait and *height* in landscape, so a feature's "fraction of the
viewport" depends on orientation; `--probe` says which axis `vmin` is. devicePixelRatio can't be
read from pixels alone (it's device px vs CSS px), so `--probe` reports orientation + the vmin
axis and reminds you to divide by dpr for CSS px on a retina capture. Needs `ffprobe`.

**Geometry / measurement (`--measure W:H:X:Y`):** for visual-tuning and alignment work — *how
big* a feature is and *where* it sits, over time — this bounds a feature inside the ROI once per
sampled frame and prints `t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy`: the bounding-box
width/height, the major-axis **diameter** in px and as **% of viewport width and height**, and
the **center** in full-frame px. It thresholds the ROI and computes a true 2-D bounding box
(ffmpeg extracts grayscale frames; **python3** measures the box) — robust where a naive
center-row dark-run fails (a photon ring or accretion disk breaks the dark run and yields
garbage). `--measure-bright` measures a bright feature (a ring/glow) instead of the default dark
one; `--measure-limit <n>` is the luma threshold (0–255; dark counts pixels below it, bright
above; default 80). `--fps` sets the rate; honors `--start`/`--end`; needs `python3`, plus
`ffprobe` for the % columns (px-only without it). **Pick the axis by orientation** (see
`--probe`): `diam_pct_w` for a vmin-authored UI in portrait, `diam_pct_h` in landscape; the
`--measure` run prints which. Retina captures (dpr 2) make device px misleading — the percentage
columns are dpr-independent. This is the tool for "splash core ≈ 12% vs real shadow ≈ 30%"-type
measurements; for a two-feature comparison, measure each and compare the percentages (or stitch
the frames with `--strip`).

**Palette / dominant colours (`--palette`):** print the clip's dominant colours as a hex swatch
list (`#rrggbb  rgb(r,g,b)`), `--colors <n>` for how many (default 8). When a clip is an
*art-direction reference*, the palette is part of the deliverable — read the exact ring/flash
colours instead of eyeballing them. Narrow with `--start`/`--end` to get one phase's palette
(pair with `--list-scenes` to find the phase boundaries); `--fps` sets the sample rate. Built on
ffmpeg `palettegen`; needs `python3` to read the swatch image. For *reference* reads generally,
a timestamped contact tile gives the phase timeline and `--palette` gives the colours — together
they turn "here's a clip I like" into a structured spec.

**A/B divergence (`--ab other.mov`):** for two captures of the *same* sequence (the same intro on
two browsers/devices, or a before/after), this aligns them by time and prints a `t,ssim` CSV —
1.0 means identical, lower means more different — then headlines the most divergent moments, so
"these intros differ most at 0.20–0.28 s" falls out in one step. Both clips are sampled at
`--fps` and scaled to the primary's dimensions (differing aspect ratios are stretched), and
`--start`/`--end` align the window on both. Built on ffmpeg's `ssim` filter; no extra deps. It's
the cross-browser-bug tool: find *when* they diverge here, then pull side-by-side timestamped
tiles at that moment to *see* how.

**A/B contact sheet (`--compare-videos a,b`):** one image, a **row per clip**, each clip sampled
into `--cols` tiles spread across its **own** duration (a normalized *phase* axis), so two clips
of different lengths line up by **% through the sequence**, not by absolute time. This is the
visual companion to `--ab` (which gives the divergence *number*): use it to see "why does B differ
from A" — fresh-load vs replay, before/after a fix, two browsers — in a single sheet (top row A,
bottom row B). Default 8 columns (`--cols` to change); `--label` burns each tile's source
timestamp. Writes `<out>/compare.png`; needs `ffprobe`. Note the axis is phase-normalized — if an
event (a flash) lands at a different *fraction* in each clip the columns won't coincide; that's
the known gap a future `--align-on scene`/`--t0` would close.

**Smoothness header (automatic):** every real run prints one line — `smoothness: effective <avg>
fps vs nominal <r> fps` and, when the average trails the nominal rate, a `~N% frames
dropped/duplicated` estimate. It's the single quickest "is it choppy?" read (one `ffprobe` call,
on by default); `--cadence` and `--motion` localize *when/where*.

**Cadence / stutter timeline (`--cadence`):** localizes choppiness in time. It reports the
container's nominal rate (`r_frame_rate`) vs its real average (`avg_frame_rate`) — a large gap
means dropped/duplicated frames, i.e. perceived stutter — then runs `mpdecimate` to count
*unique* frames per `--window` bin and prints a `t,unique_frames,fps` CSV, headlining the
choppiest windows (e.g. "stutter concentrated at the end-of-splash burst"). It measures
unique-*content* cadence, so a deliberately static scene also reads low (nothing new is drawn) —
the honest signal. `--start`/`--end` scope it; needs `python3` (and `ffprobe` for the
nominal/average split). The avg-vs-nominal number alone often localizes a perf bug to overdraw;
the per-window timeline tells you *when*.

**Motion timeline (`--motion`):** prints `t,motion` where `motion` is the mean inter-frame pixel
delta (0–255 luma) per sampled frame — the *quantitative* companion to `--diff`. It turns "feels
too long / choppy / is the dust even moving?" into a number and shows **where** motion
concentrates (e.g. a flat-low span = nothing moving, a spike = a cut or burst). Built on
`tblend=difference` + `signalstats` (YAVG); the headline reports the average and the peak moment.
The first frame is skipped (no previous to difference against). `--fps` sets the rate; honors
`--start`/`--end`; needs `python3`. It measures *magnitude*, not direction — for the **character** of
motion (spinning in place vs spiralling inward), reach for **`--flow`** (below), which splits the
flow into swirl (rotation) and suck (radial) components.

*Amplitude floor & `--crop` (a common misread):* averaged over the **whole frame** and then
downscaled, low-amplitude motion — drifting dust motes, a slow spinner, a subtle settle — quantizes
down toward `0.00–3`, where "a little life" is hard to tell from "frozen". When the peak stays under
`~3/255`, the headline says so and suggests re-running with **`--crop W:H:X:Y`** on just that region:
`--motion` now honors `--crop`, so measuring the ROI alone lifts the signal above the whole-frame
noise floor. If it still reads near-zero *cropped*, that's a genuine freeze, not a scale artifact —
which makes `--motion --crop` a clean A/B instrument for "did my fix actually add motion here?".

**Flow character (`--flow`):** `--motion`/`--diff` give motion *magnitude* and *where*, but not its
*character* — "a disk spinning in place" and "a disk spiralling inward" light them up identically.
`--flow` computes a coarse block-matching optical flow between sampled frames and decomposes it
about a center into its **rotational** (curl / mean tangential = "swirl") and **radial** (divergence
/ mean inward-outward = "suck") components, printing `t,speed,curl,div`. Read it:
- **spinning in place** → `|curl|` high, `div ≈ 0`
- **sucking inward** (a plunge into a well) → `div < 0`
- **expanding outward** → `div > 0`
- **spiralling inward** ("suck + twirl") → `|curl|` high **and** `div < 0`
- **panning/translating** → both `curl` and `div` ≈ 0

The headline classifies the dominant pattern. Center defaults to the frame center; set it with
`--flow-center fx:fy` (fractions of the frame, e.g. `0.4:0.55`) or just `--crop` so the feature is
centered. `--fps` sets the temporal rate — **raise it for fast motion** (the search caps at ~8 px
of displacement per frame; more fps ⇒ smaller per-frame steps ⇒ a cleaner field). The pure-python
matcher analyzes a **bounded number of frames** (the first ~200 sampled; it says so when it caps),
so point it at the beat you care about with `--start`/`--end` rather than a whole long recording.
Honors `--crop`,
`--start`/`--end`; needs `python3` (stdlib only — no numpy/opencv). It works best on a **textured**
subject (a churning disk, particles); flat/low-contrast blocks are skipped, and because it matches
*translation*, pure **expansion/scaling** (outward `div`) is under-measured — inward "suck" and
rotation are the reliable reads. This is the quantified answer to "is it swirling or sucking?" that
the frames alone can't give.

**Subject extent (`--occupancy`):** answers "how much of the frame does the subject actually
occupy?" — the "present but too small to see" case that brightness/colour modes miss. It thresholds
each sampled frame above the background and prints `t,coverage_pct,x,y,w,h` (the subject's coverage
fraction + bounding box, in the downscaled sample's px). "The galaxy is tiny" becomes `coverage ≈
3%`, and you can watch it climb as a camera auto-frames or pulls back. The bright-on-dark default
(a visualizer on black) is flipped with `--occupancy-dark`; the `--occupancy-threshold N` (0–255,
default 40) sets the subject/background cutoff. The counterpart to `--blackdetect` (which thresholds
for the *empty* case). Honors `--crop`, `--start`/`--end`; needs `python3`.

**Saturation timeline (`--saturation`):** prints `t,saturation` — the mean colour saturation
(`signalstats` SATAVG, 0 ≈ greyscale, higher ≈ more vivid, maxing ~180) per sampled frame — so
"clownish / over-saturated vs muted / elegant" is a number you can verify after a palette fix.
Pairs with `--palette` (which colours) and `--motion` (how much movement). `--fps` sets the rate;
honors `--start`/`--end`; needs `python3`.

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

## "An animation didn't play" — a cause frames can't see

Frames reliably show that an animation is **absent** (e.g. an iOS sheet jumps straight to the
formed state, skipping the splash), but **not why**. Common invisible causes: the element is in
the DOM but its CSS animation never started (deferred first paint / a backgrounded tab), JS threw
before kicking it off, or a media query/`prefers-reduced-motion` disabled it. So when the symptom
is "X didn't animate," confirm the absence from frames, then **pair the video pass with a
DOM/console capture** (computed styles + `getAnimations()` state + console errors at t≈0) and a
**code read** — don't conclude the cause from pixels. `--intro` is the fast way to confirm the
absence; the cause comes from the page state.

## Capturing a recording (note for whoever produces the clip)

If a clip is being generated **headlessly** with virtual/synthetic time (e.g. a screenshot
script that advances a fake clock), be aware that **virtual time does not drive the
compositor** — CSS keyframe/transition animations won't advance, so the capture can look frozen
even though the page "logically" progressed. To screenshot CSS animations deterministically,
freeze them by setting `Element.getAnimations()[i].currentTime` (Web Animations API) at each
step, or capture against **real wall-clock** time. This is a capture-side gotcha, not something
the extractor can detect — but it explains a "nothing is moving" clip that `--motion` reads as
flat-zero.
