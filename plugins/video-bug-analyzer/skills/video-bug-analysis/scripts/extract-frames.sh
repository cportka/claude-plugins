#!/usr/bin/env bash
#
# extract-frames.sh — pull still frames out of a screen-recording for bug analysis.
#
# Claude cannot watch video; it can only read still frames. This script extracts them
# either densely over a time window (default) or at scene-change boundaries, so the
# right moment is actually captured instead of being missed between sparse samples.
#
# Also useful beyond bug-hunting: it's a general "reason over a clip's look + motion" tool —
# art/aesthetic reference (mining a library of animated loops for palette + motion to drive a
# generator), colour extraction (--palette, --palette --over-time for the colour arc), asset/QA
# (--loop-check for a seamless loop, --probe/--contact for a quick read). GIF input works on every mode.
#
# Usage:
#   extract-frames.sh --video <path> [--start <ts>] [--end <ts>] [--fps <n>]
#                     [--scene <thr>] [--contact] [--text] [--cols <n>] [--rows <n>]
#                     [--tile-width <px>] [--timestamps <t1,t2,...>] [--window <sec>]
#                     [--frame-width <px>] [--max-width <px>] [--crop <W:H:X:Y>] [--diff]
#                     [--label] [--out <dir>]
#   extract-frames.sh --strip <before.png,after.png> [--out <dir>]   # stitch existing frames
#   extract-frames.sh --video <path> --list-scenes [--scene <thr>]   # print scene-cut times
#   extract-frames.sh --video <path> --blackdetect [--crop <W:H:X:Y>] # find black-out spans
#   extract-frames.sh --video <path> --ocr-roi <W:H:X:Y> [--fps <n>]  # OCR a region -> t,text CSV
#   extract-frames.sh --video <path> --measure <W:H:X:Y> [--fps <n>]  # feature diameter/center CSV
#   extract-frames.sh --video <path> --probe                         # capture geometry/orientation
#   extract-frames.sh --video <path> --palette [--colors <n>]        # dominant colours (hex)
#   extract-frames.sh --video <path> --palette --over-time [--segments <n>]  # colour arc: t,[hex...] per window
#   extract-frames.sh --video <path> --loop-check                    # seam diff: first vs last frame + strip
#   extract-frames.sh --video <a> --ab <b> [--fps <n>]               # A/B divergence over time
#   extract-frames.sh --video <path> --stutter [--window <sec>]      # stutter: dropped frames + freeze gaps
#   extract-frames.sh --video <path> --pacing                        # frame-timestamp (jitter) timeline
#   extract-frames.sh --video <path> --motion [--fps <n>]            # mean inter-frame motion timeline
#   extract-frames.sh --video <path> --stall [--stall-min <sec>]     # hang/loop: N sec of no change
#   extract-frames.sh --video <path> --whiteout [--white-min <sec>]  # blown-highlight / dropout spans
#   extract-frames.sh --video <path> --saturation [--fps <n>]        # colour-saturation timeline
#   extract-frames.sh --video <path> --stack --crop <W:H:X:Y>        # ROI time-stack (band over time)
#   extract-frames.sh --compare-videos a.mov,b.mov [--cols <n>]      # one A/B phase-aligned sheet
#   extract-frames.sh --video <path> --intro                        # load/splash preset (first ~2s)
#   extract-frames.sh --check-update                                 # installed vs marketplace version
#
# Options:
#   --video <path>      Input video file (required).
#   --start <ts>        Start time (e.g. 12, 0:12, 00:00:12.5). Default: start of clip.
#   --end <ts>          End time. Default: end of clip.
#   --fps <n>           Frames per second to sample (dense / contact / timestamp burst).
#                       Default: 4. Use 2 for an overview, 8+ to catch sub-second transients.
#   --scene <thr>       Scene-change mode: capture frames where the scene score exceeds
#                       <thr> (e.g. 0.1). Overrides --fps. Good for an unknown moment.
#   --intro             Load/splash preset: the first ~2s as a dense, labelled contact sheet
#                       (= --start 0 --end 2 --fps 12 --contact --label, portrait-aware). Each
#                       part yields to an explicit flag (--end 3 / --fps 8 still win). Load and
#                       splash bugs live at t=0 and are sub-second — this is the right default.
#   --contact           Contact-sheet mode: tile the sampled frames into a single image
#                       (or a few), so the whole timeline can be read in one file with
#                       far fewer tokens. Combines with --fps or --scene for selection.
#   --text              Contact preset for code/transcript UIs: bumps tile width to 640
#                       (unless --tile-width is given) so on-screen text stays readable.
#   --portrait          Contact preset for tall phone captures: 2 columns (bigger tiles).
#                       Auto-enabled when ffprobe detects a portrait source. (Contact only.)
#   --cols <n>          Columns per contact sheet. Default: 4 (2 for portrait). (Contact only.)
#   --rows <n>          Rows per contact sheet. Default: 4. (Contact mode only.)
#   --tile-width <px>   Width each frame is scaled to in a contact sheet. Default: 480.
#   --strip <a,b>       (alias --compare) Stitch two EXISTING frames into a before/after
#                       strip (hstack) at <out>/strip.png. No --video needed. Best artifact
#                       for a UI-state-transition bug.
#   --timestamps <list> Comma-separated moments (e.g. "0:12,0:34"). For each, extract a
#                       dense burst over a +/-window plus a before/after strip image —
#                       great for showing a flagged transient. Ignores --scene/--contact.
#   --window <sec>      Half-width of each timestamp burst, in seconds. Default: 0.5.
#   --frame-width <px>  Width burst frames are scaled to. Default: 820 (keeps text legible).
#   --max-width <px>    Cap width for dense/scene frames so native (e.g. 4K) PNGs don't blow
#                       tokens. Never upscales smaller clips. Default: 1280.
#   --out <dir>         Output directory for PNG frames. Default: ./.frames/<video-name>
#                       (per-video, so a second clip doesn't clobber the first); ./.frames
#                       in --strip mode. If the dir already holds a previous run's PNGs, this
#                       run goes into a mode+window subdir instead of overwriting (see #64).
#   --dry-run           Print the exact ffmpeg command(s) this would run, without running
#                       them (no ffmpeg needed). Lets a live agent that can't load the
#                       plugin mid-session copy the commands and run them by hand.
#   --crop <W:H:X:Y>    Crop a region (ffmpeg geometry, e.g. 320:120:40:900) before scaling,
#                       so that region fills the frame — a zoom on an on-screen FPS/HUD, a
#                       counter, or any small UI area. Applies to dense/scene/contact/diff/
#                       timestamp modes. iw/ih expressions allowed (e.g. iw/4:ih/4:0:0).
#   --diff              Frame-difference mode: emit diff_*.png where each frame is the change
#                       from the previous one (bright = motion). Confirms what moved / where.
#   --label             Burn the source timestamp onto each frame (dense/--diff/--timestamps,
#                       and contact tiles + --compare-videos). Best-effort: needs ffmpeg
#                       drawtext + a font; silently skipped if unavailable.
#   --list-scenes       Print the timestamps (seconds) of detected scene cuts and exit; tune
#                       with --scene <thr> (default 0.3). Feed the cuts into --timestamps.
#   --blackdetect       Find blacked-out spans (black/blank screen bug) and exit, printing
#                       each as "black START -> END (dur) — PERMANENT/transient". Permanent =
#                       sustained to EOF (needs ffprobe). Combine with --crop to ignore a
#                       static UI overlay that keeps a few pixels lit (the common false-miss).
#   --black-min <sec>   Minimum black-span duration to report. Default: 0.1.
#   --black-ratio <r>   Fraction of pixels that must be black for a frame to count (pic_th,
#                       0..1). Default: 0.98. Lower (e.g. 0.90) if an overlay keeps pixels lit.
#   --ocr-roi <W:H:X:Y> Value tracker: OCR a small region (a panel readout — body counts, a
#                       Speed value) once per sampled frame and print a "t,text" CSV to stdout.
#                       Use when the symptom is a NUMBER changing (e.g. a count 4->5->4), not a
#                       render artifact — a value timeline localises a state/logic bug in
#                       seconds. Sample rate from --fps; honors --start/--end. Needs tesseract
#                       (the one mode beyond ffmpeg); prints an install hint if it's missing.
#   --ocr-digits        Restrict OCR to digits and a few separators (cleaner for numeric
#                       readouts: counts, speeds, timers). Use with --ocr-roi.
#   --measure <W:H:X:Y> Geometry/measurement: inside this ROI, measure the bounding box of a
#                       dark feature (an event-horizon shadow, a dot, a blob) once per sampled
#                       frame and print a CSV: t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy.
#                       diam_px is the major axis; diam_pct_w/h are % of viewport width/height
#                       (vmin flips by orientation — see --probe); cx,cy are full-frame px.
#                       For visual-tuning ("how big is this circle, over time"). Robust to a
#                       photon ring / accretion disk that breaks a naive center-row scan. Sample
#                       rate from --fps; honors --start/--end. Needs python3 (+ ffprobe for the
#                       % column): ffmpeg extracts grayscale frames, python3 measures the box.
#   --measure-bright    Measure a BRIGHT feature (a ring, a glow) instead of a dark one.
#   --measure-limit <n> Luma threshold 0..255: dark mode counts pixels BELOW it, bright mode
#                       ABOVE it. Default 80. Tune if too little / too much is bounded.
#   --probe             Print the capture's geometry — dimensions, aspect ratio, orientation
#                       (portrait/landscape), fps, duration — and which axis CSS vmin maps to.
#                       Use it before measuring so % figures are read on the right axis. (ffprobe.)
#   --palette           Print the clip's dominant colours as a hex swatch list (an art-direction
#                       reference's palette is part of the deliverable). Narrow with --start/--end
#                       to read one phase. Sample rate from --fps. Needs python3.
#   --colors <n>        How many dominant colours --palette extracts. Default: 8.
#   --over-time         (with --palette) the colour *arc*: split the clip into N windows and print
#                       each window's palette as `t<sec>  #hex #hex ...`, so a loop that sweeps
#                       through colour states shows its journey, not one flattened ramp. (1.8.0, #85)
#   --segments <n>      How many time windows --palette --over-time samples. Default: 8.
#   --loop-check        Is this a clean *seamless* loop? Report the mean absolute pixel difference
#                       between the first and last frame (0 = identical wrap) and write a
#                       loopcheck.png strip (first | last) so a seam is visible. (1.8.0, #85; python3.)
#   --ab <other>        A/B divergence: compare --video against <other> (two captures of the
#                       SAME sequence — e.g. a different browser/device) and print a t,ssim CSV
#                       (1.0 = identical, lower = more different), headlining the most divergent
#                       moments. Both are sampled at --fps and scaled to the primary's size, so
#                       it answers "these intros differ most at 0.20-0.28s". --start/--end align
#                       the window on both. The cross-browser-bug tool. (Uses ffmpeg ssim.)
#   --stutter           Stutter timeline (aliases: --cadence, --fps-drops — one mode, --stutter is
#                       the primary name): leads with a one-line VERDICT (worst freeze + median
#                       window fps — the actionable read), then the nominal-vs-real rates and a
#                       per-window count of UNIQUE frames so you see WHEN it stutters. Prints
#                       t,unique_frames,fps and headlines the choppiest windows; also lists the
#                       longest FREEZE GAPS (sustained frozen spans, e.g. "@1.4s frozen for 633 ms").
#                       A static/near-black pre-roll is detected and kept out of the ranking; a VFR
#                       capture's high nominal (macOS: 240) is flagged as a timebase, not a target
#                       (#89). --window sets the bin (default 0.5s); --freeze-min <sec> tunes the
#                       freeze-gap threshold (default 0.1 — raise to 0.2 to mute ~100ms VFR noise);
#                       honors --start/--end. Measures UNIQUE-content cadence, so a static scene
#                       also reads low. (ffmpeg mpdecimate + freezedetect + ffprobe; python3.)
#   --marks <file>      (with --stutter) Correlate the app's own instrumentation with the freeze
#                       timeline: a JSON array of performance.mark-style entries
#                       [{"name":"fullCompile","tMs":2000,"durMs":330}, ...] (times in ms, video
#                       clock). The verdict and each freeze-gap line note the best-aligned mark —
#                       "freeze 970 ms @2.10s — aligns with mark 'fullCompile' (starts 2.00s,
#                       330 ms)" — collapsing the diagnose-verify loop to one read. (1.10.0, #94.)
#   --t0 <sec|mm:ss>    Add a session offset to EVERY reported timestamp — the --stutter/--cadence
#                       verdict, freeze gaps, choppiest windows, --pacing hitches, and the
#                       --timestamps on-frame label. For multi-part captures: analyze "part 2"
#                       (which starts at 0) with --t0 30 and its "freeze @14.7s" prints as the
#                       session's @44.7s, lining up with app perf marks (--marks) — no manual offset
#                       arithmetic. Relabels times only; does NOT move the seek (--start does that).
#                       (1.11.0, #96.)
#   --pacing            Frame-PACING timeline (a from-scratch counterpart to --cadence): read the
#                       actual per-frame presentation timestamps and print t,interval_ms — the time
#                       between consecutive DISPLAYED frames. Catches uneven timing / jank / VFR / a
#                       long-frame hitch even when every frame's CONTENT differs (which --cadence
#                       can't see). Headlines median/p95/max + the worst hitches. (ffprobe; python3.)
#   --motion            Motion timeline: print t,motion (mean inter-frame pixel delta, 0..255)
#                       per sampled frame, so "is it moving / where does motion concentrate?"
#                       becomes a number. Quantifies --diff. Sample rate from --fps; honors
#                       --start/--end and --crop (crop to a spinner/dust region to lift a subtle
#                       signal above the whole-frame noise floor). (ffmpeg tblend+signalstats; python3.)
#   --stall             HANG/LOOP detector — the counterpart to --stutter (which finds freezes DURING
#                       motion). Flags the longest span where NOTHING changes (mean inter-frame delta
#                       below --stall-thresh, default 1.5/255) for >= --stall-min seconds (default 2):
#                       a boot hang, dead canvas, or infinite splash/overlay loop, which a jank
#                       detector reads as "smooth". One-line STALL verdict; honors --crop/--start/
#                       --end/--t0. (ffmpeg tblend+signalstats; python3.) (1.12.0, #102.)
#   --whiteout          BLOWN-HIGHLIGHT detector (+ black-dropout companion) — reads each frame's mean
#                       luma and reports spans at/above --white-thresh (default 220/255, a merge/flash
#                       whiteout) or at/below the black cutoff (a dropout) lasting >= --white-min
#                       (default 0.2s), each with start/end/duration/peak. For pixel-ratio black,
#                       --blackdetect is more precise. Honors --crop/--start/--end/--t0. (ffmpeg
#                       signalstats; python3.) (1.12.0, #102.)
#   --saturation        Colour-saturation timeline: print t,saturation (signalstats SATAVG,
#                       0 grey .. ~180 vivid) per sampled frame, so "clownish/over-saturated vs
#                       muted/elegant" is measurable and verifiable after a fix. Sample rate from
#                       --fps; honors --start/--end. (ffmpeg signalstats; needs python3.)
#   --flow              Flow *character*, not just magnitude: coarse block-matching optical flow
#                       between sampled frames, decomposed about a center into its rotational
#                       (curl / "swirl") and radial (divergence / "suck") parts -> t,speed,curl,div.
#                       Distinguishes "spinning in place" (|curl| high, div~0) from "sucking inward"
#                       (div<0) — what --motion/--diff (magnitude only) can't. Center from
#                       --flow-center fx:fy (fraction of frame, default 0.5:0.5); honors --crop,
#                       --start/--end; --fps sets the rate (raise it for fast motion). (python3.)
#   --flow-center fx:fy  Center the --flow swirl/radial split is measured about, as fractions of
#                       the frame (0..1). Default 0.5:0.5 (frame center) — or --crop so the feature centers.
#   --occupancy         Subject-extent timeline: how much of the frame the subject actually fills.
#                       Threshold above the background and print t,coverage_pct,x,y,w,h (bounding box
#                       in sampled px) per frame — the "subject present but small" counterpart to
#                       --blackdetect. "The galaxy is tiny" becomes coverage ~3%, and you watch it
#                       grow as a camera pulls back. --occupancy-threshold sets the cutoff,
#                       --occupancy-dark flips to a dark subject; honors --crop, --start/--end. (python3.)
#   --occupancy-threshold N  Luma cutoff (0..255) splitting subject from background for --occupancy
#                       (default 40; subject = brighter than N, or darker with --occupancy-dark).
#   --occupancy-dark    --occupancy measures a dark subject on a light background (default is the
#                       reverse: a bright subject on a dark background, e.g. a visualizer on black).
#   --stack             ROI time-stack: crop a fixed band (--crop, required — a scrub bar, HUD,
#                       status row) and tile the samples VERTICALLY into stack_0001.png, so one
#                       image reads that region's evolution top-to-bottom across the clip. Sample
#                       rate from --fps; honors --start/--end and --label; spills into
#                       stack_0002.png past 48 rows.
#   --check-update      Compare this installed version against the marketplace's latest
#                       (raw plugin.json on GitHub main) and print the update command if it
#                       trails. Needs no --video; degrades gracefully offline. Exits 0.
#   --compare-videos a,b  A/B comparison sheet: ONE image, a row per clip, each clip sampled
#                       into <--cols> tiles spread across its OWN duration (normalized phase
#                       axis), so two clips of different lengths line up by % through the
#                       sequence — "why does B differ from A" (fresh vs replay, before/after,
#                       two browsers). Writes <out>/compare.png. --label burns each tile's
#                       timestamp. Needs ffprobe. (Names its own inputs; no --video.)
#   --version           Print the plugin version and exit.
#
# Every run prints a one-line "smoothness:" header (effective vs nominal fps + a dropped-frame
# estimate) — the quickest "is it choppy?" read; --cadence / --motion localize it. A high-refresh
# capture (>=90Hz) of a ~30/60fps app is called out as normal (expected frame duplication), not
# choppy, so a 120Hz recording of a 60fps app doesn't read as a false "52% dropped".
#   -h, --help          Show this help.
#
# ffmpeg is required. It's already on PATH in many environments; if it's missing this tries
# apt -> brew -> a static build from GitHub (BtbN) then johnvansickle. A locked-down sandbox
# may block that or require approval — then give Claude a still screenshot of the bad moment.
#
# Examples:
#   extract-frames.sh --video bug.mov --fps 2 --contact --text       # legible overview
#   extract-frames.sh --video bug.mov --timestamps 0:12,0:34 --fps 8 # zoom + strips
#   extract-frames.sh --video bug.mov --start 0:11 --end 0:14 --fps 8
#   extract-frames.sh --strip .frames/frame_0003.png,.frames/frame_0009.png  # before/after
#   extract-frames.sh --video bug.mov --fps 8 --contact --dry-run    # print cmds, don't run
#   extract-frames.sh --video bug.mov --fps 8 --crop 320:120:40:900  # zoom an FPS/HUD region
#   extract-frames.sh --video bug.mov --blackdetect --crop 600:564:0:0  # find a black-screen bug
#   extract-frames.sh --video bug.mov --ocr-roi 180:40:20:8 --ocr-digits --fps 2  # count timeline
#   extract-frames.sh --video bug.mov --measure 400:400:760:340 --fps 5  # shadow diameter over time
#   extract-frames.sh --video bug.mov --probe                            # aspect/orientation/dpr note
#   extract-frames.sh --video ref.mov --start 4 --end 5.7 --palette      # one phase's colours
#   extract-frames.sh --video safari.mov --ab firefox.mov --fps 10       # where do they diverge?
#   extract-frames.sh --video splash.mov --cadence --window 0.5          # when does it stutter?
#   extract-frames.sh --video splash.mov --motion --fps 12               # when/where is motion?
#   extract-frames.sh --video orbit.mov --flow --fps 8                   # spin-in-place vs suck-inward?
#   extract-frames.sh --video galaxy.mov --occupancy --fps 4             # is the subject too small?
#   extract-frames.sh --video splash.mov --saturation --fps 6            # vivid vs muted, over time
#   extract-frames.sh --compare-videos fresh.mov,replay.mov --label      # A vs B, phase-aligned
#   extract-frames.sh --video app.mov --intro                            # "the intro does X" — t=0
#
set -euo pipefail

ORIG_ARGS=("$@")   # remember the invocation for the end-of-run feedback link
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # locate plugin.json
# ADDED (1.0.3, issues #51/#52/#53): embedded version, used when this script is run standalone
# (e.g. fetched raw with no repo tree, so the adjacent plugin.json isn't present). A test keeps
# this in sync with plugin.json, so the feedback link never reports version=unknown.
VBA_VERSION="1.12.1"

VIDEO=""
START=""
END=""
FPS="4"
SCENE=""
CONTACT=""
COLS="4"
COLS_SET=""        # track whether --cols was passed explicitly
ROWS="4"
PORTRAIT=""        # --portrait (or auto-detected) -> fewer cols for tall captures
TILEW="480"        # was 320 — too small for text/code UIs (per DedTxt dogfood)
TILEW_SET=""       # track whether --tile-width was passed explicitly
TEXT=""            # --text preset (legible tiles for code/transcript UIs)
STRIP=""           # --strip a,b -> hstack two existing frames (no --video needed)
TIMESTAMPS=""
WINDOW="0.5"
FRAMEW="820"
MAXW="1280"   # cap width for dense/scene frames so native 4K doesn't blow tokens
OUT="./.frames"
OUT_SET=""    # track whether --out was passed (else default per-video, see below)
DRY_RUN=""    # --dry-run prints the exact ffmpeg commands instead of running them
DIFF=""       # --diff emits frame-difference images (motion highlight)
LABEL=""      # --label burns the source timestamp onto each frame (best-effort)
LIST_SCENES="" # --list-scenes prints detected scene-cut timestamps, then exits
LABEL_OK=""   # ADDED (1.0.3): set when the --label drawtext probe succeeds
LABEL_FONT="" # ADDED (1.0.3): font file resolved for --label burn-in; segments built by label_seg
CROP=""       # --crop W:H:X:Y (ffmpeg geometry) -> crop a region, then scale = zoom
CROP_VF=""    # computed crop filter segment (empty unless --crop given)
BLACKDETECT="" # --blackdetect finds blacked-out spans, then exits
BLACK_D="0.1"  # --black-min, minimum black-span duration (seconds) to report
BLACK_RATIO="0.98" # --black-ratio, fraction of pixels that must be black (pic_th)
OCR_ROI=""     # --ocr-roi W:H:X:Y -> OCR a region per frame -> t,text CSV
OCR_DIGITS=""  # --ocr-digits restricts OCR to a numeric whitelist (counts/readouts)
MEASURE=""     # --measure W:H:X:Y -> bounding box / diameter of a feature
MEASURE_LIMIT="80"  # --measure-limit, luma threshold (dark<thr / bright>thr) 0..255
MEASURE_BRIGHT=""   # --measure-bright measures a bright feature (else dark, default)
PROBE=""       # --probe prints capture geometry (aspect/orientation), exits
PALETTE=""     # --palette prints dominant colours (hex swatches), then exits
COLORS="8"     # --colors, how many dominant colours --palette extracts
AB=""          # --ab <other> SSIM-diffs two clips over time, then exits
CADENCE=""     # --cadence reports a frame-cadence/jitter timeline, then exits
MOTION=""      # --motion prints a mean inter-frame pixel-delta timeline, exits
STALL=""       # --stall flags a >= --stall-min span of near-identical frames (hang/loop), exits (1.12.0, #102)
STALL_MIN="2.0"  # --stall-min <sec>: minimum near-static span --stall reports as a stall
STALL_THRESH="1.5" # mean inter-frame delta (0-255) below which frames count as near-identical (--stall)
WHITEOUT=""    # --whiteout flags blown-highlight (+ black-dropout) spans by mean luma, exits (1.12.0, #102)
WHITE_MIN="0.2"  # --white-min <sec>: minimum whiteout/dropout span --whiteout reports
WHITE_THRESH="220" # mean luma (0-255) at/above which a frame is a whiteout (--whiteout)
BLACK_LUMA_THRESH="16" # mean luma (0-255) at/below which a frame is a black dropout (--whiteout)
CMP_VIDEOS=""  # --compare-videos a,b -> one stacked phase-aligned contact sheet
INTRO=""       # --intro = load/splash preset (first ~2s, dense contact + labels)
SATURATION=""  # --saturation prints a per-frame colour-saturation timeline, exits
PACING=""      # --pacing prints a per-frame timestamp-interval (jitter) timeline, exits (1.2.0)
STACK=""       # --stack tiles a cropped ROI vertically across time -> stack_*.png (1.3.0, #62)
CHECK_UPDATE="" # --check-update compares installed vs marketplace version, exits (1.3.0, #62)
FLOW=""        # --flow rotational/radial optical-flow decomposition -> t,speed,curl,div (1.4.0, #69)
FLOW_CENTER="0.5:0.5" # --flow-center fx:fy (fraction of frame) the swirl/suck is measured about
OCCUPANCY=""   # --occupancy subject-extent timeline -> t,coverage_pct,bbox (1.4.0, #69)
OCC_THRESH="40" # --occupancy-threshold luma cutoff separating subject from background (0..255)
OCC_DARK=""    # --occupancy-dark measures a dark subject on a light background (else bright-on-dark)
OVER_TIME=""   # --over-time: with --palette, emit a per-window colour arc (t,[hex...]) (1.8.0, #85)
SEGMENTS=""    # --segments N: how many time windows --palette --over-time samples (default 8)
LOOP_CHECK=""  # --loop-check: compare frame@0 vs frame@last (seam diff + strip) for a loop (1.8.0, #85)
FREEZE_MIN="0.1" # --freeze-min <sec>: min frozen span --stutter reports as a freeze gap (1.9.0, #89)
MARKS=""       # --marks <file>: app performance.mark JSON to correlate with freezes (1.10.0, #94)
T0="0"         # --t0 <sec|mm:ss>: session offset added to every reported timestamp (1.11.0, #96)
FPS_SET=""     # track whether --fps was passed (so presets don't override it)

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# Convert a timestamp (SS | MM:SS | HH:MM:SS[.frac]) to seconds, for window arithmetic.
to_seconds() {
  awk -F: '{ s=$NF; if (NF>=2) s+=$(NF-1)*60; if (NF>=3) s+=$(NF-2)*3600; printf "%.3f", s }' <<<"$1"
}

# Display origin for reported timestamps: the --start seek offset PLUS the optional --t0 session
# offset (#96). --t0 relabels every reported time (the --stutter/--cadence verdict, freeze gaps,
# choppiest windows, --pacing hitches, and the --timestamps on-frame label) into a multi-part
# session's own clock, so "freeze @14.7s of part 2" reads as its true session time and lines up with
# the app's perf marks — WITHOUT moving the ffmpeg seek, which stays --start only (built into PRE_ARGS).
disp_base() {
  awk -v s="$(to_seconds "${START:-0}")" -v z="$(to_seconds "${T0:-0}")" 'BEGIN{ printf "%.3f", s+z }'
}

# read this plugin's version from plugin.json (for --version and the feedback link).
_plugin_version() {
  # CHANGED (1.0.3, issues #51/#52/#53): prefer the adjacent plugin.json, but fall back to the
  # embedded VBA_VERSION (not "unknown") so a standalone copy still reports its version.
  local pj="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/.claude-plugin/plugin.json"
  if [[ -f "$pj" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version","'"$VBA_VERSION"'"))' "$pj" 2>/dev/null || echo "$VBA_VERSION"
    else
      grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/' || echo "$VBA_VERSION"
    fi
  else
    echo "$VBA_VERSION"
  fi
}

# at the end of a real run, print a one-click, pre-filled feedback link
# (plugin + ffmpeg version + the exact command already encoded) and a one-line nudge. Goes to
# stderr so it never pollutes output; suppress with VBA_NO_FEEDBACK_HINT=1.
feedback_hint() {
  [[ -z "$DRY_RUN" && -z "${VBA_NO_FEEDBACK_HINT:-}" ]] || return 0
  local ver ffv cmd url
  ver="$(_plugin_version || true)"
  ffv="$(ffmpeg -version 2>/dev/null | head -n1 || true)"
  cmd="extract-frames.sh ${ORIG_ARGS[*]:-}"
  if command -v python3 >/dev/null 2>&1; then
    url="$(FB_V="$ver" FB_F="$ffv" FB_C="$cmd" python3 - <<'PY' 2>/dev/null || true
import os, urllib.parse
base = "https://github.com/cportka/claude-plugins/issues/new"
p = {"template": "plugin-feedback.yml"}
for env, field in [("FB_V", "version"), ("FB_F", "ffmpeg"), ("FB_C", "command")]:
    v = os.environ.get(env, "").strip()
    if v:
        p[field] = v
print(base + "?" + urllib.parse.urlencode(p))
PY
)"
  fi
  [[ -n "${url:-}" ]] || url="https://github.com/cportka/claude-plugins/issues/new?template=plugin-feedback.yml"
  {
    echo ""
    echo "Helpful or buggy? One-click feedback (pre-filled): $url"
    echo "(Say if it helped or broke; you can attach a contact sheet from ${OUT}. Hide with VBA_NO_FEEDBACK_HINT=1.)"
  } >&2
}

# warn (best-effort) when the source's real frame rate is well below the requested
# --fps, so duplicate frames aren't a surprise. Needs ffprobe; silent no-op without it.
warn_if_sparse() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  local raf actual
  raf="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
    -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null)"
  [[ "$raf" == */* ]] || return 0                       # expect a "num/den" rate
  actual="$(awk -F/ '{ if (($2+0)>0) printf "%.1f", $1/$2 }' <<<"$raf")"
  [[ -n "$actual" ]] || return 0
  if awk -v req="$1" -v act="$actual" 'BEGIN{ exit !(act>0 && req > act*1.3) }'; then
    echo "Note: source captures ~${actual} real fps; --fps $1 won't add detail (frames repeat). Lower --fps or accept duplicates." >&2
  fi
  return 0
}

# echo "<width> <height>" of the source via ffprobe, or nothing if unavailable.
probe_wh() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=s=x:p=0 "$VIDEO" 2>/dev/null | tr 'x' ' '
}

# contact-sheet tuning for tall/dense captures (issue #14). Auto-drops --cols to 2 for
# portrait sources (unless --cols was given), and warns when tiles downscale the source so far
# that small UI text will be illegible — suggesting full-res individual frames instead.
tune_contact_for_source() {
  local wh w h
  wh="$(probe_wh || true)"           # never let a probe failure abort the run (set -e)
  read -r w h <<<"${wh:-}" || true   # empty here-string returns non-zero under set -e
  # Portrait: explicit --portrait, or ffprobe says taller-than-wide.
  if [[ -z "$COLS_SET" ]] && { [[ -n "$PORTRAIT" ]] || { [[ -n "${w:-}" && -n "${h:-}" ]] && (( h > w )); }; }; then
    COLS=2
    echo "Portrait capture: using --cols 2 (override with --cols). For dense small text, full-res individual frames (drop --contact) read better than any contact sheet." >&2
  fi
  # Legibility guard: if each tile downscales the source width a lot, small text blurs.
  if [[ -n "${w:-}" ]] && awk -v sw="$w" -v tw="$TILEW" 'BEGIN{ exit !(tw>0 && sw/tw > 2.5) }'; then
    echo "Heads-up: contact tiles downscale this ${w}px-wide source >2.5x; small UI text may be illegible — for dense text prefer full-res individual frames (drop --contact) or raise --tile-width / lower --cols." >&2
  fi
}

# find a usable TrueType font for --label (drawtext). Echoes a path or nothing.
_find_font() {
  local f
  if command -v fc-match >/dev/null 2>&1; then
    f="$(fc-match -f '%{file}' 2>/dev/null || true)"
    [[ -n "$f" && -f "$f" ]] && { printf '%s' "$f"; return 0; }
  fi
  for f in /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
           /usr/share/fonts/dejavu/DejaVuSans.ttf \
           /usr/share/fonts/TTF/DejaVuSans.ttf \
           /System/Library/Fonts/Supplemental/Arial.ttf; do
    [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# build the --label drawtext segment, but only after PROBING that drawtext + the font
# actually work on this ffmpeg build. If anything's off (no drawtext, no font, bad syntax),
# LABEL_VF stays empty and extraction proceeds unlabeled — the label never breaks a run.
build_label_vf() {
  LABEL_OK=""; LABEL_FONT=""
  [[ -n "$LABEL" && -z "$DRY_RUN" ]] || return 0
  command -v ffmpeg >/dev/null 2>&1 || return 0
  local font filt
  font="$(_find_font || true)"
  [[ -n "$font" ]] || { echo "Note: --label found no usable font; skipping timestamp burn-in." >&2; return 0; }
  filt="drawtext=fontfile=${font}:text='%{pts\\:hms}':x=10:y=10:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.5"
  if ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=black:s=64x64:d=0.1" \
       -vf "$filt" -frames:v 1 -f null - >/dev/null 2>&1; then
    LABEL_OK=1; LABEL_FONT="$font"   # label segments are built on demand by label_seg <offset>
  else
    echo "Note: --label isn't supported by this ffmpeg/font; skipping timestamp burn-in." >&2
  fi
}

# label_seg <offset-seconds> — echo a drawtext segment that burns ABSOLUTE source time, by adding
# <offset> (the clip seek point) to the frame pts (issues #51/#52/#53). Empty if --label is off or
# unsupported, so it's safe to splice into any -vf chain.
label_seg() {
  [[ -n "${LABEL_OK:-}" ]] || return 0
  local off="${1:-0}"
  printf '%s' ",drawtext=fontfile=${LABEL_FONT}:text='%{pts\\:hms\\:${off}}':x=10:y=10:fontsize=20:fontcolor=yellow:box=1:boxcolor=black@0.5"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --start) START="${2:-}"; shift 2 ;;
    --end)   END="${2:-}";   shift 2 ;;
    --fps)   FPS="${2:-}";   FPS_SET=1; shift 2 ;;   # mark explicit override (issue #43)
    --scene) SCENE="${2:-}"; shift 2 ;;
    --contact) CONTACT="1"; shift ;;
    --portrait) PORTRAIT="1"; shift ;;                 # tall-capture contact preset
    --cols)  COLS="${2:-}";  COLS_SET=1; shift 2 ;;    # mark explicit override
    --rows)  ROWS="${2:-}";  shift 2 ;;
    --tile-width) TILEW="${2:-}"; TILEW_SET=1; shift 2 ;;   # mark explicit override
    --text) TEXT="1"; shift ;;                              # legible-tiles preset
    --strip|--compare) STRIP="${2:-}"; shift 2 ;;           # hstack two existing frames
    --timestamps) TIMESTAMPS="${2:-}"; shift 2 ;;
    --window) WINDOW="${2:-}"; shift 2 ;;
    --frame-width) FRAMEW="${2:-}"; shift 2 ;;
    --max-width) MAXW="${2:-}"; shift 2 ;;   # cap for dense/scene frame width
    --out)   OUT="${2:-}";   OUT_SET=1; shift 2 ;;   # mark explicit override
    --dry-run) DRY_RUN=1; shift ;;                   # print ffmpeg commands, don't run
    --diff)  DIFF=1; shift ;;                         # frame-difference (motion) frames
    --label) LABEL=1; shift ;;                        # burn source timestamp on frames
    --list-scenes) LIST_SCENES=1; shift ;;            # print scene-cut timestamps, exit
    --crop) CROP="${2:-}"; shift 2 ;;                  # crop region W:H:X:Y, then zoom
    --blackdetect) BLACKDETECT=1; shift ;;            # find black spans, exit
    --black-min) BLACK_D="${2:-}"; shift 2 ;;         # min black-span duration (seconds)
    --black-ratio) BLACK_RATIO="${2:-}"; shift 2 ;;   # black-pixel fraction (pic_th)
    --ocr-roi) OCR_ROI="${2:-}"; shift 2 ;;           # OCR a region -> CSV
    --ocr-digits) OCR_DIGITS=1; shift ;;              # numeric-only OCR whitelist
    --measure) MEASURE="${2:-}"; shift 2 ;;           # feature bbox/diameter
    --measure-limit) MEASURE_LIMIT="${2:-}"; shift 2 ;;  # cropdetect luma cutoff
    --measure-bright) MEASURE_BRIGHT=1; shift ;;      # measure a bright feature (not dark)
    --probe) PROBE=1; shift ;;                        # print capture geometry
    --palette) PALETTE=1; shift ;;                    # dominant colours, exit
    --colors) COLORS="${2:-}"; shift 2 ;;             # number of palette colours
    --over-time) OVER_TIME=1; shift ;;               # ADDED (1.8.0, #85): colour arc over windows
    --segments) SEGMENTS="${2:-}"; shift 2 ;;        # windows for --palette --over-time (default 8)
    --loop-check) LOOP_CHECK=1; shift ;;             # ADDED (1.8.0, #85): first-vs-last seam diff
    --ab) AB="${2:-}"; shift 2 ;;                      # A/B divergence vs <other>
    --cadence) CADENCE=1; shift ;;                    # frame-cadence timeline
    --stutter|--fps-drops) CADENCE=1; shift ;;       # ADDED (1.1.2, #56): aliases for --cadence
    --freeze-min) FREEZE_MIN="${2:-}"; shift 2 ;;    # ADDED (1.9.0, #89): freeze-gap threshold (sec)
    --marks) MARKS="${2:-}"; shift 2 ;;              # ADDED (1.10.0, #94): perf-mark sidecar JSON
    --t0) T0="${2:-}"; shift 2 ;;                    # ADDED (1.11.0, #96): session offset for reported times
    --motion) MOTION=1; shift ;;                      # inter-frame motion timeline
    --stall) STALL=1; shift ;;                        # ADDED (1.12.0, #102): hang/loop (no-change) detector
    --stall-min) STALL_MIN="${2:-}"; shift 2 ;;       # min near-static span (sec) to call a stall
    --stall-thresh) STALL_THRESH="${2:-}"; shift 2 ;; # near-identical delta cutoff (0-255)
    --whiteout) WHITEOUT=1; shift ;;                  # ADDED (1.12.0, #102): blown-highlight + dropout detector
    --white-min) WHITE_MIN="${2:-}"; shift 2 ;;       # min whiteout/dropout span (sec) to report
    --white-thresh) WHITE_THRESH="${2:-}"; shift 2 ;; # mean-luma cutoff for a whiteout (0-255)
    --compare-videos) CMP_VIDEOS="${2:-}"; shift 2 ;; # A/B stacked contact sheet
    --intro) INTRO=1; shift ;;                        # first-seconds load preset
    --saturation) SATURATION=1; shift ;;             # colour-saturation timeline
    --pacing) PACING=1; shift ;;                      # ADDED (1.2.0): frame-pacing/jitter timeline
    --stack) STACK=1; shift ;;                        # ADDED (1.3.0, #62): ROI time-stack
    --check-update) CHECK_UPDATE=1; shift ;;          # ADDED (1.3.0, #62): version check, exit
    --flow) FLOW=1; shift ;;                           # ADDED (1.4.0, #69): swirl/suck flow split
    --flow-center) FLOW_CENTER="${2:-}"; shift 2 ;;   # center (fx:fy fractions) for --flow
    --occupancy) OCCUPANCY=1; shift ;;                # ADDED (1.4.0, #69): subject-extent timeline
    --occupancy-threshold) OCC_THRESH="${2:-}"; shift 2 ;;  # luma cutoff subject vs background
    --occupancy-dark) OCC_DARK=1; shift ;;            # subject is dark-on-light (default bright-on-dark)
    --version) echo "video-bug-analyzer $(_plugin_version)"; exit 0 ;;  # ADDED
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# --intro preset — load/splash bugs live at t=0 and are sub-second, so this
# is shorthand for "the first ~2s, densely, as a labelled contact sheet". Each piece yields to an
# explicit flag (e.g. --end 3 or --fps 8 still win); portrait auto-detection still applies.
if [[ -n "$INTRO" ]]; then
  [[ -z "$START" ]] && START="0"
  [[ -z "$END"   ]] && END="2"
  [[ -z "$FPS_SET" ]] && FPS="12"
  CONTACT="1"; LABEL="1"
fi

# --text preset bumps contact tiles to a code/transcript-legible width unless the
# user set --tile-width explicitly.
[[ -n "$TEXT" && -z "$TILEW_SET" ]] && TILEW="640"

# --stack needs its ROI up front — fail before any ffmpeg install/probe work (1.3.0, #62).
if [[ -n "$STACK" && -z "$CROP" ]]; then
  echo "Error: --stack needs --crop W:H:X:Y (the region to track over time)." >&2
  exit 2
fi

# --occupancy-threshold must be numeric — reject garbage up front with a clear message rather than
# a raw Python traceback + leaked temp dir later (1.4.0, #69 review).
if [[ -n "$OCCUPANCY" && ! "$OCC_THRESH" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Error: --occupancy-threshold must be a number 0..255 (got '$OCC_THRESH')." >&2
  exit 2
fi

# --t0 offsets every reported timestamp into a multi-part session's clock (#96); accept SS | MM:SS |
# HH:MM:SS[.frac] like --start, and reject garbage up front rather than silently offsetting by 0.
if [[ "$T0" != "0" && ! "$T0" =~ ^([0-9]+:)?([0-9]+:)?[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Error: --t0 must be a non-negative offset in seconds or SS/MM:SS/HH:MM:SS (got '$T0')." >&2
  exit 2
fi

# --stall / --whiteout numeric knobs (1.12.0, #102): reject garbage up front rather than a later
# Python traceback + leaked temp dir. Durations are seconds; thresholds are 0-255 luma/delta.
if [[ -n "$STALL" ]]; then
  for _nv in "--stall-min:$STALL_MIN" "--stall-thresh:$STALL_THRESH"; do
    [[ "${_nv#*:}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "Error: ${_nv%%:*} must be a non-negative number (got '${_nv#*:}')." >&2; exit 2; }
  done
fi
if [[ -n "$WHITEOUT" ]]; then
  for _nv in "--white-min:$WHITE_MIN" "--white-thresh:$WHITE_THRESH"; do
    [[ "${_nv#*:}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "Error: ${_nv%%:*} must be a non-negative number (got '${_nv#*:}')." >&2; exit 2; }
  done
fi

# --check-update: compare the installed version against the marketplace's main branch and
# exit. Needs no --video; degrades gracefully offline (#62's "installed-vs-marketplace" ask —
# a stale install is invisible otherwise, since installed copies are pinned by version).
if [[ -n "$CHECK_UPDATE" ]]; then
  _inst="$(_plugin_version)"
  # URL overridable for tests / forks. `|| true` on each pipeline: under set -euo pipefail a
  # failing curl (offline rc 6/7, timeout 28, 404->22) would otherwise kill the script BEFORE
  # the graceful fallback ever ran (review finding on 1.3.0).
  _mf_url="${VBA_UPDATE_URL:-https://raw.githubusercontent.com/cportka/claude-plugins/main/plugins/video-bug-analyzer/.claude-plugin/plugin.json}"
  _remote=""
  if command -v curl >/dev/null 2>&1; then
    _remote="$(curl -fsSL --max-time 8 "$_mf_url" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  elif command -v wget >/dev/null 2>&1; then
    _remote="$(wget -qO- --timeout=8 "$_mf_url" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  fi
  if [[ -z "$_remote" ]]; then
    echo "video-bug-analyzer $_inst installed; could not reach the marketplace to compare (offline or blocked)." >&2
  elif [[ "$_remote" == "$_inst" ]]; then
    echo "video-bug-analyzer $_inst is up to date with the marketplace."
  elif [[ "$(printf '%s\n%s\n' "$_inst" "$_remote" | sort -V | head -n1)" == "$_inst" ]]; then
    # installed sorts LOWER -> genuinely trailing
    echo "video-bug-analyzer $_inst installed; marketplace has $_remote."
    echo "Update with:  claude plugin update video-bug-analyzer@portka-tools  (then /reload-plugins or a new session)"
  else
    # installed sorts HIGHER (a dev checkout / pre-release) — don't advise a downgrade
    echo "video-bug-analyzer $_inst installed; ahead of the marketplace ($_remote) — a dev or pre-release copy."
  fi
  exit 0
fi

# --over-time / --segments only mean something for --palette (the colour arc). Guard so a typo
# (e.g. --over-time alone) doesn't silently run a plain extraction (#85).
if [[ -n "$OVER_TIME$SEGMENTS" && -z "$PALETTE" ]]; then
  echo "Error: --over-time / --segments only apply to --palette (the colour arc). Add --palette." >&2
  exit 2
fi
# ...and --segments without --over-time would be silently ignored by the flat palette — the same
# wrong-mode footgun from the other direction (#85 review). Say so instead of dropping the intent.
if [[ -n "$SEGMENTS" && -n "$PALETTE" && -z "$OVER_TIME" ]]; then
  echo "Error: --segments needs --over-time (did you mean: --palette --over-time --segments $SEGMENTS?)." >&2
  exit 2
fi
# --marks correlates app instrumentation with the stutter timeline — only --stutter/--cadence reads it (#94).
if [[ -n "$MARKS" && -z "$CADENCE" ]]; then
  echo "Error: --marks only applies to --stutter/--cadence (the freeze/jank timeline it annotates)." >&2
  exit 2
fi

# --video is required EXCEPT in --strip and --compare-videos modes (they name their
# own inputs / operate on existing frames).
if [[ -z "$STRIP" && -z "$CMP_VIDEOS" ]]; then
  if [[ -z "$VIDEO" ]]; then
    echo "Error: --video is required." >&2
    echo "Run with --help for usage." >&2
    exit 2
  fi
  if [[ ! -f "$VIDEO" ]]; then
    echo "Error: video file not found: $VIDEO" >&2
    exit 1
  fi
fi

# default output to a per-video dir so a second clip in the same session doesn't
# clobber the first's frames. --out overrides; --strip (no video) keeps the plain default.
[[ -z "$OUT_SET" && -n "$VIDEO" ]] && OUT=".frames/$(basename "${VIDEO%.*}")"

# --- Ensure ffmpeg is available -------------------------------------------------------
# Cache dir for a downloaded static ffmpeg; shared with the SessionStart hook so either
# can populate it and this script will find it.
FFMPEG_CACHE="${HOME:-/tmp}/.cache/portka-video-bug-analyzer/bin"

# Last resort when apt/brew aren't available: download a static ffmpeg build into the cache
# dir and add it to PATH for this run. Tries GitHub release assets first (reachable in many
# sandboxes where apt/other hosts are blocked), then johnvansickle. Override the source with
# $VBA_FFMPEG_URL. Best-effort; returns non-zero if it can't (no network/curl/wget/tar).
install_ffmpeg_static() {
  local gh_a jv_a u tmp found bindir
  command -v tar >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
  case "$(uname -m)" in
    x86_64|amd64)  gh_a=linux64;    jv_a=amd64 ;;
    aarch64|arm64) gh_a=linuxarm64; jv_a=arm64 ;;
    *) return 1 ;;
  esac
  local urls=(
    "${VBA_FFMPEG_URL:-}"
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n7.1-latest-${gh_a}-gpl.tar.xz"
    "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${jv_a}-static.tar.xz"
  )
  tmp="$(mktemp -d)" || return 1
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] || continue
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --max-time 300 "$u" -o "$tmp/ff.tar.xz" 2>/dev/null || continue
    else
      wget -q --timeout=300 -O "$tmp/ff.tar.xz" "$u" 2>/dev/null || continue
    fi
    tar -xJf "$tmp/ff.tar.xz" -C "$tmp" 2>/dev/null || continue
    found="$(find "$tmp" -type f -name ffmpeg -print -quit 2>/dev/null)"
    [[ -n "$found" ]] && break
  done
  [[ -n "${found:-}" ]] || { rm -rf "$tmp"; return 1; }
  bindir="$(dirname "$found")"
  mkdir -p "$FFMPEG_CACHE" || { rm -rf "$tmp"; return 1; }
  cp "$bindir/ffmpeg" "$FFMPEG_CACHE/" 2>/dev/null || true
  if [[ -f "$bindir/ffprobe" ]]; then cp "$bindir/ffprobe" "$FFMPEG_CACHE/" 2>/dev/null || true; fi
  chmod +x "$FFMPEG_CACHE/ffmpeg" 2>/dev/null || true
  rm -rf "$tmp"
  export PATH="$FFMPEG_CACHE:$PATH"
  command -v ffmpeg >/dev/null 2>&1
}

ensure_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1; then
    return 0
  fi
  echo "ffmpeg not found; attempting to install it..." >&2
  if command -v apt-get >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y >/dev/null 2>&1 || true
      sudo apt-get install -y ffmpeg >/dev/null 2>&1 || true
    else
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y ffmpeg >/dev/null 2>&1 || true
    fi
  elif command -v brew >/dev/null 2>&1; then
    brew install ffmpeg >/dev/null 2>&1 || true
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    return 0
  fi
  echo "Package manager unavailable or blocked; trying a static ffmpeg build..." >&2
  install_ffmpeg_static && return 0
  cat >&2 <<'EOF'
Error: ffmpeg is required but could not be installed automatically (apt/brew and the static
builds all failed — outbound network or the command's approval is likely restricted).
Options:
  - Approve / run the install yourself (see docs/INTEGRATE.md for the permission rule), or
  - Install manually:  sudo apt-get install -y ffmpeg   |   brew install ffmpeg
  - Static build (GitHub, often reachable): https://github.com/BtbN/FFmpeg-Builds/releases
  - Or skip the video entirely: give Claude a still screenshot of the exact bad moment.
EOF
  return 1
}

# Reuse a previously cached static build (e.g. installed by the SessionStart hook).
[[ -x "$FFMPEG_CACHE/ffmpeg" ]] && export PATH="$FFMPEG_CACHE:$PATH"

# skip install/diagnostic in --dry-run (no ffmpeg needed just to print commands).
[[ -n "$DRY_RUN" ]] || ensure_ffmpeg

# Diagnostic: which ffmpeg is in use (cite this when reporting extraction problems).
[[ -n "$DRY_RUN" ]] || echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1)" >&2

# cheap mean inter-frame motion (0-255) over a downscaled, low-fps, frame-capped sample — a rough "is
# anything actually moving?" signal used ONLY to disambiguate the smoothness verdict (#105), so most
# runs never pay for it. Echoes a number, or nothing on failure / too-short.
_mean_motion() {
  command -v ffmpeg >/dev/null 2>&1 || return 1
  local mf; mf="$(mktemp)"
  ffmpeg -hide_banner -loglevel error -i "$VIDEO" \
    -vf "fps=3,scale=160:-2,tblend=all_mode=difference,signalstats,metadata=mode=print:file=$mf" \
    -frames:v 48 -an -f null - >/dev/null 2>&1 || { rm -f "$mf"; return 1; }
  awk -F= '/lavfi\.signalstats\.YAVG=/{ s+=$2+0; n++ } END{ if(n>=2) printf "%.2f", s/n }' "$mf"
  rm -f "$mf"
}

# a one-line smoothness header on every run — effective (avg) vs nominal (r) frame rate + a verdict.
# The single best "is it choppy?" number, for (almost) free (one ffprobe call). The one genuinely
# ambiguous case — a low effective rate that could be DROPPED frames (jank) or DUPLICATE frames (a
# mostly-static UI/text screen recording) — is disambiguated with a cheap, GATED motion probe, so a
# static login-screen capture isn't false-alarmed as "choppy" (#105). Best-effort; silent w/o ffprobe.
print_smoothness() {
  command -v ffprobe >/dev/null 2>&1 || return 0
  [[ -n "$VIDEO" && -f "$VIDEO" ]] || return 0
  local rfr afr
  rfr="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate   -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  afr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  [[ -n "$rfr" && -n "$afr" ]] || return 0
  # Classify from the rates alone first (cheap). Branch is one of ok|near60|near30|vfr|generic|minor.
  local cls
  cls="$(awk -v r="$rfr" -v a="$afr" '
    function fr(s,  p){ if(index(s,"/")){split(s,p,"/"); return (p[2]+0)?p[1]/p[2]:0} return s+0 }
    function near(x,c){ return (x >= c-6 && x <= c+6) }   # near a common animation cadence (±6 fps)
    BEGIN{ R=fr(r); A=fr(a); if(R<=0||A<=0) exit;
      b="ok";
      if (A < R) { d=(1-A/R)*100;
        # A high-refresh CAPTURE (>=90 Hz) of a lower-cadence app (~30/60 fps) reads as a big "dropped"
        # %, but that is expected frame *duplication*, not jank (#83). A VFR capture (macOS 240/1, some
        # muxers 600/1000) uses nominal as a TIMEBASE, not a target (#89). Everything else that shortfalls
        # by >=5% is "generic" — the case that needs the motion probe to tell dropped from duplicate.
        if (R >= 90 && (near(A,60) || near(A,30))) b=(near(A,60)?"near60":"near30");
        else if (R >= 200 && A >= 15) b="vfr";
        else if (d>=5) b="generic";
        else b="minor";
      }
      printf "%.4f %.4f %s", R, A, b;
    }')"
  [[ -n "$cls" ]] || return 0
  local R A branch
  read -r R A branch <<<"$cls"
  # Only the generic case is ambiguous (dropped vs duplicate). Probe mean inter-frame motion for it: a
  # mostly-static clip (low motion) whose effective rate lags nominal is just frame duplication — a UI/
  # text recording — NOT choppiness. If the probe can't run (no ffmpeg / unreadable), keep the old verdict.
  local mm="" static=""
  if [[ "$branch" == "generic" ]]; then
    mm="$(_mean_motion || true)"
    [[ -n "$mm" ]] && awk -v m="$mm" 'BEGIN{exit !(m < 2.5)}' && static=1
  fi
  awk -v R="$R" -v A="$A" -v branch="$branch" -v mm="${mm:-0}" -v static="$static" 'BEGIN{
    printf "smoothness: effective %.1f fps vs nominal %.1f fps", A, R;
    if (branch=="near60"||branch=="near30"){ cad=(branch=="near60")?60:30;
      printf "  (~%.0f fps content on a %.0f Hz capture — normal for a %d fps app, not choppy; --motion/--pacing to check for real stutter)", A, R, cad; }
    else if (branch=="vfr"){
      printf "  (VFR/high-refresh capture: nominal %.0f is the container timebase, not a target — effective ~%.0f fps; --stutter/--pacing for real stutter)", R, A; }
    else if (branch=="generic"){ d=(1-A/R)*100;
      if (static!="")
        printf "  (~%.0f%% duplicate frames on a mostly-static capture (inter-frame motion ~%.1f/255) — a UI/text recording; a high duplicate ratio is expected here, not choppy; --motion/--stall to confirm)", d, mm+0;
      else
        printf "  (~%.0f%% frames dropped/duplicated — likely choppy; --cadence/--motion to localize)", d;
    }
    printf "\n";
  }' >&2
}
[[ -n "$DRY_RUN" ]] || print_smoothness

# run an ffmpeg command, or — under --dry-run — print it (copy-pasteable) instead.
# Lets a live agent that can't load the plugin mid-session replicate the workflow by hand.
run_ff() {
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' "$@"; printf '\n'
  else
    ffmpeg "$@"
  fi
}

# Newer ffmpeg (>=5.1) replaced "-vsync vfr" with "-fps_mode vfr". Pick what this build
# supports so variable-rate frame selection works without deprecation warnings; fall back
# to -vsync on older builds (or if the version string can't be parsed).
VFR=()
set_vfr_flag() {
  # no ffmpeg (e.g. --dry-run on a host without it)? assume modern, don't crash.
  command -v ffmpeg >/dev/null 2>&1 || { VFR=(-fps_mode vfr); return 0; }
  local ver major minor
  ver="$(ffmpeg -version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
  major="${ver%%.*}"
  minor="${ver#*.}"
  if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] \
     && { (( major > 5 )) || { (( major == 5 )) && (( minor >= 1 )); }; }; then
    VFR=(-fps_mode vfr)
  else
    VFR=(-vsync vfr)
  fi
}

# blackdetect mode — find blacked-out spans and classify each as transient
# (a flash) or permanent (sustained to end of file). Honors --crop, so a static UI overlay
# (a lil-gui panel, a HUD) can be excluded from the black-ratio test before detection — the
# manual canvas-crop step the dogfood reporter had to do by hand. Uses CROP_VF / PRE_ARGS,
# so it must run after those are built.
run_blackdetect() {
  local vf="${CROP_VF}blackdetect=d=${BLACK_D}:pic_th=${BLACK_RATIO}"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -f null -
    printf '\n'
    echo "(dry run — the command above prints 'black_start:.. black_end:..' lines on stderr)"
    return 0
  fi
  echo "Black-frame detection (min ${BLACK_D}s, pic_th ${BLACK_RATIO}${CROP:+, crop ${CROP}}) in $VIDEO:" >&2
  # blackdetect logs "black_start:.. black_end:.. black_duration:.." to stderr at info level.
  local log
  log="$(ffmpeg -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -f null - 2>&1 || true)"
  # Source duration (for the permanent-vs-transient test); empty if ffprobe is unavailable.
  local dur=""
  if command -v ffprobe >/dev/null 2>&1; then
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null || true)"
  fi
  local _spans found=""
  _spans="$(grep -oE 'black_start:[0-9.]+ black_end:[0-9.]+ black_duration:[0-9.]+' <<<"$log" || true)"
  if [[ -n "$_spans" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      found=1
      local _s _e _d kind
      _s="${line#black_start:}"; _s="${_s%% *}"
      _e="${line#*black_end:}";  _e="${_e%% *}"
      _d="${line##*black_duration:}"
      kind="transient (recovers)"
      if [[ -n "$dur" ]]; then
        # Permanent if the span runs to (within 0.5s of) the end of the file.
        kind="$(awk -v e="$_e" -v d="$dur" 'BEGIN{ print (e >= d - 0.5) ? "PERMANENT (sustained to EOF)" : "transient (recovers)" }')"
      fi
      printf 'black %ss -> %ss (%.3fs) — %s\n' "$_s" "$_e" "$_d" "$kind"
    done <<<"$_spans"
  fi
  if [[ -z "$found" ]]; then
    echo "No black spans >= ${BLACK_D}s at pic_th ${BLACK_RATIO}." >&2
    echo "If a UI overlay keeps some pixels lit, crop to the app canvas (--crop W:H:X:Y) and/or lower --black-ratio (e.g. 0.90)." >&2
  fi
  [[ -z "$dur" ]] && echo "Note: ffprobe not found — can't classify permanent-vs-transient (showing spans only)." >&2
}

# ROI value tracker — sample a small region per frame and OCR it into a
# "t,text" CSV (on stdout). For state/logic bugs the symptom is a panel readout changing
# (a count going 4->5->4), not a render artifact — a value timeline localises it in seconds
# where staring at frames can't. Needs tesseract (the one mode beyond ffmpeg); degrades with a
# clear install hint if it's missing. Uses PRE_ARGS, so it must run after those are built.
run_ocr_roi() {
  local roi="$1"
  local vf="crop=${roi},fps=${FPS}"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "<tmp>/f_%05d.png"; printf '\n'
    echo "# then OCR each f_*.png with tesseract --psm 7 -> rows of: t,\"text\"  (t = start + (frame-1)/${FPS})"
    return 0
  fi
  if ! command -v tesseract >/dev/null 2>&1; then
    echo "Error: --ocr-roi needs tesseract (OCR) — the one mode beyond ffmpeg." >&2
    echo "Install: sudo apt-get install -y tesseract-ocr  |  brew install tesseract  — then re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "$d/f_%05d.png"
  local cfg=()
  # Numeric whitelist for count/speed readouts — cuts OCR noise when --ocr-digits is set.
  [[ -n "$OCR_DIGITS" ]] && cfg=(-c "tessedit_char_whitelist=0123456789.,:/x %-")
  local base; base="$(disp_base)"
  echo "t,text"
  local i=0 f t txt
  for f in "$d"/f_*.png; do
    [[ -e "$f" ]] || break
    i=$((i + 1))
    t="$(awk -v i="$i" -v fps="$FPS" -v b="$base" 'BEGIN{ printf "%.3f", b + (i-1)/fps }')"
    # --psm 7: treat the ROI as a single text line. Collapse whitespace; trim.
    txt="$(tesseract "$f" stdout --psm 7 "${cfg[@]}" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ *$//' || true)"
    printf '%s,"%s"\n' "$t" "${txt//\"/\"\"}"   # CSV-quote (double any embedded quotes)
  done
  rm -rf "$d"
  echo "OCR timeline: $i samples over ROI ${roi} at ${FPS} fps. If values change with no nearby" >&2
  echo "pixel change, the cause is likely logic/state (off-screen) — check logs / a headless repro." >&2
}

# geometry/measurement — measure the bounding box (apparent diameter +
# center) of a dark (or --measure-bright) feature inside an ROI, once per sampled frame, as a
# t,...,diam_px,diam_pct,cx,cy CSV. For visual-tuning/alignment work the question is often "how
# big is this circle, as a % of viewport, over time" — a naive center-row dark-run breaks on a
# photon ring or accretion disk, but a 2-D bounding box is robust. ffmpeg extracts grayscale PGM
# frames (the one bulletproof step); python3 thresholds each and computes the box (so the result
# doesn't depend on a particular ffmpeg's cropdetect log format). Uses PRE_ARGS — run after them.
run_measure() {
  local roi="$1"
  # ROI is W:H:X:Y — only the X,Y offset is needed (to map the bbox back to full-frame center).
  local mx my; IFS=: read -r _ _ mx my <<<"$roi"
  local kind="dark"; [[ -n "$MEASURE_BRIGHT" ]] && kind="bright"
  local vf="crop=${roi},fps=${FPS},format=gray"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "<tmp>/f_%05d.pgm"
    printf '\n'
    echo "# then threshold each PGM (limit ${MEASURE_LIMIT}, ${kind}) -> 2-D bounding box -> CSV"
    echo "# t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --measure needs python3 to compute the bounding box. Install python3 and re-run." >&2
    exit 2
  fi
  # Viewport width AND height for %-of-viewport on both axes (vmin flips by orientation, #31);
  # empty if no ffprobe. diam_pct_w / diam_pct_h let the caller pick the right axis.
  local vw="" vh=""
  if command -v ffprobe >/dev/null 2>&1; then
    vw="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    vh="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "$d/f_%05d.pgm" >/dev/null 2>&1 || true
  local base; base="$(disp_base)"
  # Threshold + bounding box per PGM frame (P5 is trivially parseable with the stdlib).
  python3 - "$d" "$MEASURE_LIMIT" "$kind" "$mx" "$my" "$FPS" "$base" "${vw:-}" "${vh:-}" <<'PY'
import sys, os, glob
d, limit, kind, mx, my, fps, base, vw, vh = sys.argv[1:10]
limit=int(limit); mx=int(mx); my=int(my); fps=float(fps); base=float(base)
vw=float(vw) if vw else None
vh=float(vh) if vh else None
def read_pgm(p):
    try:
        with open(p,'rb') as f: data=f.read()
        if data[:2]!=b'P5': return 0,0,b''
        i=2; vals=[]
        while len(vals)<3:                       # parse width, height, maxval (skip ws/comments)
            while i<len(data) and data[i:i+1].isspace(): i+=1
            if data[i:i+1]==b'#':
                while i<len(data) and data[i:i+1]!=b'\n': i+=1
                continue
            j=i
            while j<len(data) and not data[j:j+1].isspace(): j+=1
            vals.append(int(data[i:j])); i=j
        w,h,_maxv=vals; i+=1                      # one whitespace byte follows maxval
        px=data[i:i+w*h]
        if len(px)!=w*h: return 0,0,b''          # truncated frame -> skip, don't IndexError
        return w,h,px
    except Exception:
        return 0,0,b''
def pct(diam, dim): return ("%.2f" % (diam/dim*100)) if dim else ""
print("t,w_px,h_px,diam_px,diam_pct_w,diam_pct_h,cx,cy")
for n,p in enumerate(sorted(glob.glob(os.path.join(d,"f_*.pgm")))):
    w,h,px=read_pgm(p)
    minx=miny=10**9; maxx=maxy=-1
    for y in range(h):
        row=px[y*w:(y+1)*w]
        for x in range(w):
            v=row[x]
            if (v<limit) if kind=="dark" else (v>limit):
                if x<minx: minx=x
                if x>maxx: maxx=x
                if y<miny: miny=y
                if y>maxy: maxy=y
    t=base+n/fps
    if maxx<0:                               # nothing matched the threshold this frame
        print("%.3f,0,0,0,,,0,0" % t); continue
    bw=maxx-minx+1; bh=maxy-miny+1; diam=bw if bw>bh else bh
    print("%.3f,%d,%d,%d,%s,%s,%d,%d" % (t, bw, bh, diam, pct(diam,vw), pct(diam,vh),
                                         mx+minx+bw//2, my+miny+bh//2))
PY
  local n; n="$(find "$d" -maxdepth 1 -name 'f_*.pgm' | wc -l)"
  rm -rf "$d"
  local orient="" axis=""
  if [[ -n "$vw" && -n "$vh" ]]; then
    if (( vw < vh )); then orient="portrait";  axis="diam_pct_w (= % of width)"
    elif (( vw > vh )); then orient="landscape"; axis="diam_pct_h (= % of height)"
    else orient="square"; axis="either axis"; fi
  fi
  echo "Measured $n frame(s) of the ${kind} feature in ROI ${roi}${vw:+ (${vw}x${vh}${orient:+, $orient})}." >&2
  [[ -n "$orient" ]] && echo "For vmin-authored UI on a ${orient} capture, read ${axis}." >&2
  if [[ "$n" -eq 0 ]]; then
    echo "No frames sampled — check the clip and --start/--end." >&2
  fi
  [[ -z "$vw" ]] && echo "Note: ffprobe not found — diam_pct_* left blank (px only)." >&2
}

# subject-extent / occupancy (#69) — "how much of the frame does the subject actually
# occupy?" Threshold above (bright-on-dark, default) or below (--occupancy-dark) a luma cutoff and
# report, per sampled frame, the coverage fraction plus the subject's bounding box:
# t,coverage_pct,x,y,w,h. The "subject present but small" counterpart to --blackdetect (which
# thresholds for the empty/black case). Frames are downscaled (coverage is scale-invariant; bbox is
# in the sampled px, printed with the sample dims) so the pure-python threshold stays cheap. Honors
# --crop (occupancy within an ROI), --start/--end. ffmpeg -> grayscale PGM; python3 thresholds.
run_occupancy() {
  local kind="bright"; [[ -n "$OCC_DARK" ]] && kind="dark"
  local vf="${CROP_VF}fps=${FPS},scale='min(240,iw)':-1,format=gray"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "<tmp>/f_%05d.pgm"
    printf '\n'
    echo "# then threshold each PGM (${kind} subject, cutoff ${OCC_THRESH}) -> coverage % + bbox"
    echo "# t,coverage_pct,x,y,w,h"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --occupancy needs python3 to threshold the frames. Install python3 and re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" "$d/f_%05d.pgm" >/dev/null 2>&1 || true
  local base; base="$(disp_base)"
  python3 - "$d" "$OCC_THRESH" "$kind" "$FPS" "$base" <<'PY'
import sys, os, glob
d, thr, kind, fps, base = sys.argv[1:6]
thr=int(round(float(thr))); fps=float(fps) or 1.0; base=float(base)   # tolerate a decimal cutoff
def read_pgm(p):
    try:
        with open(p,'rb') as f: data=f.read()
        if data[:2]!=b'P5': return 0,0,b''
        i=2; vals=[]
        while len(vals)<3:                       # width, height, maxval (skip whitespace/comments)
            while i<len(data) and data[i:i+1].isspace(): i+=1
            if data[i:i+1]==b'#':
                while i<len(data) and data[i:i+1]!=b'\n': i+=1
                continue
            j=i
            while j<len(data) and not data[j:j+1].isspace(): j+=1
            vals.append(int(data[i:j])); i=j
        w,h,_=vals; i+=1
        px=data[i:i+w*h]
        if len(px)!=w*h: return 0,0,b''          # truncated frame -> skip, don't IndexError
        return w,h,px
    except Exception:
        return 0,0,b''
print("t,coverage_pct,x,y,w,h")
rows=[]; dims=""
for n,p in enumerate(sorted(glob.glob(os.path.join(d,"f_*.pgm")))):
    w,h,px=read_pgm(p)
    if not w or not h: continue
    dims="%dx%d" % (w,h)
    cnt=0; minx=miny=10**9; maxx=maxy=-1
    for y in range(h):
        row=px[y*w:(y+1)*w]
        for x in range(w):
            v=row[x]
            if (v>thr) if kind=="bright" else (v<thr):
                cnt+=1
                if x<minx: minx=x
                if x>maxx: maxx=x
                if y<miny: miny=y
                if y>maxy: maxy=y
    t=base+n/fps; cov=100.0*cnt/(w*h)
    if maxx<0:
        print("%.3f,0.00,0,0,0,0" % t); rows.append((t,0.0)); continue
    print("%.3f,%.2f,%d,%d,%d,%d" % (t,cov,minx,miny,maxx-minx+1,maxy-miny+1))
    rows.append((t,cov))
e=sys.stderr
if rows:
    cov=[r[1] for r in rows]; avg=sum(cov)/len(cov)
    lo=min(rows,key=lambda r:r[1]); hi=max(rows,key=lambda r:r[1])
    e.write("Occupancy: %s subject fills mean %.1f%% of frame (sampled %s); range %.1f%% @%.2fs .. %.1f%% @%.2fs over %d frames.\n"
            % (kind, avg, dims, lo[1], lo[0], hi[1], hi[0], len(rows)))
    if avg < 5:
        e.write("Very small subject (mean <5%): 'too small to see' is now a number — watch coverage climb if the camera pulls back or auto-frames.\n")
    if hi[1]-lo[1] >= 5:
        e.write("Coverage shifts over the clip (%.1f%% -> %.1f%%) — an intro/zoom is resizing the subject.\n" % (rows[0][1], rows[-1][1]))
    if avg > 95:
        e.write("Near-full coverage (>95%): the threshold may be catching the background — try a higher --occupancy-threshold (or --occupancy-dark).\n")
else:
    e.write("No frames sampled — clip too short or --fps too low.\n")
PY
  rm -rf "$d"
}

# --probe — print the capture's geometry (dimensions, aspect, orientation,
# fps, duration) so measurements aren't reasoned about on the wrong axis. dpr can't be known
# from pixels alone, so we report orientation + which axis vmin maps to instead.
run_probe() {
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffprobe'; printf ' %q' -v error -select_streams v:0 \
      -show_entries stream=width,height,avg_frame_rate -of default=nw=1 "$VIDEO"
    printf '\n'
    echo "# + format=duration; then derive aspect (gcd), orientation, and the vmin axis"
    return 0
  fi
  command -v ffprobe >/dev/null 2>&1 || { echo "Error: --probe needs ffprobe." >&2; exit 2; }
  local w h fr dur
  w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  fr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1)"
  [[ -n "$w" && -n "$h" ]] || { echo "Error: could not read dimensions from $VIDEO." >&2; exit 2; }
  # NOTE: gcd() is a top-level awk function (awk forbids defining it inside BEGIN); params use
  # distinct names from the split() array to avoid a name collision on stricter awks (mawk).
  awk -v w="$w" -v h="$h" -v fr="${fr:-0/0}" -v dur="${dur:-}" '
  function gcd(m,n,   t){ while(n){ t=m%n; m=n; n=t } return m }
  BEGIN{
    g=gcd(w,h); if(g<1)g=1;
    orient = (w<h)?"portrait":((w>h)?"landscape":"square");
    vmin   = (w<h)?"width":((w>h)?"height":"either");
    num=fr; den=1; if (index(fr,"/")){ split(fr,parts,"/"); num=parts[1]; den=(parts[2]==0?1:parts[2]) }
    fps=(den!=0)?num/den:0;
    printf "video: %dx%d\n", w, h;
    printf "aspect: %d:%d (%.3f W/H)\n", w/g, h/g, w/h;
    printf "orientation: %s\n", orient;
    if (fps>0) printf "fps: %.2f\n", fps;
    if (dur!="") printf "duration: %.2fs\n", dur;
    printf "note: on a %s capture, CSS vmin maps to viewport %s; report measurements as %% of that axis.\n", orient, vmin;
    printf "      (devicePixelRatio is not knowable from pixels alone — divide by dpr for CSS px if the capture is retina.)\n";
  }'
}

# --palette — extract the dominant colours of a clip (or a --start/--end
# window, e.g. one phase of a reference) as a hex swatch list. For art-direction reference work
# the palette IS part of the deliverable. ffmpeg's palettegen computes a representative palette
# to a PPM; python3 reads the swatches (so no PNG decoder is needed). Uses PRE_ARGS — run after.
run_palette() {
  local vf="fps=${FPS},palettegen=max_colors=${COLORS}:reserve_transparent=0:stats_mode=full"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v 1 "<tmp>/palette.ppm"
    printf '\n'
    echo "# then read the PPM swatches -> hex colour list (#rrggbb)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --palette needs python3 to read the swatches. Install python3 and re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -y -nostdin -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v 1 "$d/palette.ppm" >/dev/null 2>&1 || true
  # Read swatches via _ppm_hexes (the single hardened parser: 16-bit PPMs, truncated headers — #85
  # review), then expand each hex to the documented `#rrggbb  rgb(r,g,b)` line format here.
  local _hexes _h
  _hexes="$(_ppm_hexes "$d/palette.ppm" "$COLORS")"
  for _h in $_hexes; do
    printf '%s  rgb(%d,%d,%d)\n' "$_h" "$((16#${_h:1:2}))" "$((16#${_h:3:2}))" "$((16#${_h:5:2}))"
  done
  rm -rf "$d"
  echo "Palette: up to ${COLORS} dominant colours${START:+ from ${START}}${END:+ to ${END}} (sampled at ${FPS} fps)." >&2
}

# Duration of the VIDEO stream. NOT format=duration — that's the longest stream, and an audio track
# can outlast the video, sending a tail seek into an audio-only region (no frame -> false errors).
# Falls back to the format duration only when the stream duration is unavailable (#85 review).
_video_duration() {
  local d=""
  if command -v ffprobe >/dev/null 2>&1; then
    d="$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    [[ -z "$d" || "$d" == "N/A" ]] && d="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  [[ "$d" == "N/A" ]] && d=""
  echo "$d"
}

# Read up to k dominant colours from a PPM as space-joined #rrggbb. Tolerant of a malformed/truncated
# header (no crash) and of a 16-bit (rgb48be, maxval>255) PPM — which ffmpeg emits for >8-bit sources
# (#85 review): take the high byte of each 16-bit sample. Empty output if unreadable.
_ppm_hexes() {
  python3 - "$1" "$2" <<'PY'
import sys
p, k = sys.argv[1], int(sys.argv[2])
try:
    data = open(p, 'rb').read()
except OSError:
    sys.exit(0)
if data[:2] != b'P6':
    sys.exit(0)
i = 2; vals = []
try:
    while len(vals) < 3:
        while i < len(data) and data[i:i+1].isspace(): i += 1
        if i < len(data) and data[i:i+1] == b'#':
            while i < len(data) and data[i:i+1] != b'\n': i += 1
            continue
        j = i
        while j < len(data) and not data[j:j+1].isspace(): j += 1
        if j == i:                       # EOF before a complete header
            sys.exit(0)
        vals.append(int(data[i:j])); i = j
except ValueError:
    sys.exit(0)
w, h, mx = vals; i += 1
bpp = 6 if mx > 255 else 3                # rgb48be (16-bit, high byte first) vs rgb24
px = data[i:]
seen = []; s = set()
for o in range(0, len(px) - (bpp - 1), bpp):   # complete pixels only (truncated frame is safe)
    c = (px[o], px[o+2], px[o+4]) if bpp == 6 else (px[o], px[o+1], px[o+2])
    if c not in s:
        s.add(c); seen.append(c)
print(" ".join("#%02x%02x%02x" % c for c in seen[:k]))
PY
}

# --palette --over-time — the colour *arc*. Split [--start,--end] (or the whole clip) into N windows
# and print each window's dominant palette as `t<sec>  #hex #hex ...`, so a loop that sweeps through
# colour states (a datamosh gif, day->night) shows its journey instead of one flattened ramp (#85).
# Reuses palettegen per window + the PPM swatch reader. Honors --colors, --segments (default 8), --start/--end.
run_palette_over_time() {
  local segs="${SEGMENTS:-8}"
  if ! [[ "$segs" =~ ^[0-9]+$ ]] || [[ "$segs" -lt 2 ]]; then
    echo "Error: --segments must be an integer >= 2 (got '$segs')." >&2; exit 2
  fi
  if [[ "$segs" -gt 200 ]]; then
    echo "Error: --segments $segs is too many (max 200 — it's one ffmpeg pass per window)." >&2; exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --palette needs python3 to read the swatches." >&2; exit 2
  fi
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "Error: --palette --over-time needs ffprobe to read the clip duration." >&2; exit 2
  fi
  local dur s0 s1
  dur="$(_video_duration)"
  s0="$(to_seconds "${START:-0}")"
  if [[ -n "$END" ]]; then s1="$(to_seconds "$END")"; else s1="$dur"; fi
  # Clamp the span to the VIDEO duration so windows past the last video frame aren't sampled (they'd
  # decode 0 frames). Combined with the per-window rm below, no window can fabricate a stale palette.
  if [[ -n "$dur" ]] && awk -v a="$s1" -v b="$dur" 'BEGIN{exit !(a+0>b+0)}'; then s1="$dur"; fi
  if [[ -z "$s1" ]] || ! awk -v a="$s0" -v b="$s1" 'BEGIN{exit !(b+0>a+0)}'; then
    echo "Error: --palette --over-time needs a positive span (start=$s0 end=${s1:-?}) — is the file a valid, non-empty video?" >&2; exit 2
  fi
  local vf_palette="palettegen=max_colors=${COLORS}:reserve_transparent=0:stats_mode=full"
  local tdur; tdur="$(awk -v s="$s0" -v e="$s1" -v n="$segs" 'BEGIN{printf "%.3f", (e-s)/n}')"
  if [[ -n "$DRY_RUN" ]]; then
    echo "# --palette --over-time: ${segs} windows of ${tdur}s across [${s0}, ${s1}] s; per window:"
    printf 'ffmpeg'; printf ' %q' -nostdin -hide_banner -loglevel error -ss "<t0>" -t "$tdur" -i "$VIDEO" -vf "fps=${FPS},${vf_palette}" -frames:v 1 "<tmp>/win.ppm"
    printf '\n'
    echo "# then read each PPM -> a line: t<sec>  #hex #hex ..."
    return 0
  fi
  local d; d="$(mktemp -d)"
  echo "Palette over time — ${segs} windows, up to ${COLORS} colours each (t = window start, seconds):" >&2
  local i t0 hexes
  # -ss <t0> -t <window> is unambiguous input windowing (unlike -to, which drifts under input seek).
  for ((i=0; i<segs; i++)); do
    t0="$(awk -v s="$s0" -v e="$s1" -v i="$i" -v n="$segs" 'BEGIN{printf "%.3f", s+(e-s)*i/n}')"
    # rm FIRST: a window that decodes 0 video frames leaves NO file (ffmpeg's image muxer opens lazily,
    # so -y can't help), and _ppm_hexes would otherwise re-read the previous window's stale palette.
    rm -f "$d/win.ppm"
    ffmpeg -y -nostdin -hide_banner -loglevel error -ss "$t0" -t "$tdur" -i "$VIDEO" -vf "fps=${FPS},${vf_palette}" -frames:v 1 "$d/win.ppm" >/dev/null 2>&1 || true
    hexes="$(_ppm_hexes "$d/win.ppm" "$COLORS")"
    printf '%s\t%s\n' "$t0" "${hexes:-(no colours)}"
  done
  rm -rf "$d"
}

# --loop-check — is this a clean *seamless* loop? Extract the first and last frame, report the mean
# absolute pixel difference between them (0 = identical wrap), and stitch them side-by-side so a seam
# is visible. Built on the palette PPM reader + the --strip hstack (#85). Uses ffprobe for the duration.
run_loop_check() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --loop-check needs python3 to compute the frame difference." >&2; exit 2
  fi
  # True LAST frame: decode a short tail and let -update 1 overwrite so the final frame wins (seeking
  # to ~end and taking one frame overshoots to no-output). Tail from the VIDEO duration if ffprobe
  # gives it (format=duration can include a longer audio stream), else -sseof -0.5 (no ffprobe).
  # -pix_fmt rgb24 forces an 8-bit P6 PPM even for a 10-bit/HDR source (#85 review).
  local dur tail_ss=""
  dur="$(_video_duration)"
  awk -v d="${dur:-0}" 'BEGIN{exit !(d+0>0)}' && tail_ss="$(awk -v d="$dur" 'BEGIN{x=d-0.5; if(x<0)x=0; printf "%.3f", x}')"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -nostdin -hide_banner -loglevel error -ss 0 -i "$VIDEO" -pix_fmt rgb24 -frames:v 1 "<tmp>/first.ppm"; printf '\n'
    if [[ -n "$tail_ss" ]]; then
      printf 'ffmpeg'; printf ' %q' -nostdin -hide_banner -loglevel error -ss "$tail_ss" -i "$VIDEO" -pix_fmt rgb24 -update 1 -y "<tmp>/last.ppm"; printf '\n'
    else
      printf 'ffmpeg'; printf ' %q' -nostdin -hide_banner -loglevel error -sseof -0.5 -i "$VIDEO" -pix_fmt rgb24 -update 1 -y "<tmp>/last.ppm"; printf '\n'
    fi
    echo "# then meanAbsDiff(first,last) + hstack -> ${OUT}/loopcheck.png"
    return 0
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -y -nostdin -hide_banner -loglevel error -ss 0 -i "$VIDEO" -pix_fmt rgb24 -frames:v 1 "$d/first.ppm" >/dev/null 2>&1 || true
  if [[ -n "$tail_ss" ]]; then
    ffmpeg -y -nostdin -hide_banner -loglevel error -ss "$tail_ss" -i "$VIDEO" -pix_fmt rgb24 -update 1 "$d/last.ppm" >/dev/null 2>&1 || true
  else
    ffmpeg -y -nostdin -hide_banner -loglevel error -sseof -0.5 -i "$VIDEO" -pix_fmt rgb24 -update 1 "$d/last.ppm" >/dev/null 2>&1 || true
  fi
  if [[ ! -s "$d/first.ppm" || ! -s "$d/last.ppm" ]]; then
    echo "Error: --loop-check could not extract the first and last frame (does the clip decode?)." >&2
    rm -rf "$d"; exit 1
  fi
  local mad
  mad="$(python3 - "$d/first.ppm" "$d/last.ppm" <<'PY'
import sys
def readppm(p):
    try:
        data = open(p, 'rb').read()
    except OSError:
        return None
    if data[:2] != b'P6':
        return None
    i = 2; vals = []
    try:
        while len(vals) < 3:
            while i < len(data) and data[i:i+1].isspace(): i += 1
            if i < len(data) and data[i:i+1] == b'#':
                while i < len(data) and data[i:i+1] != b'\n': i += 1
                continue
            j = i
            while j < len(data) and not data[j:j+1].isspace(): j += 1
            if j == i:
                return None
            vals.append(int(data[i:j])); i = j
    except ValueError:
        return None
    w, h, mx = vals; i += 1
    raw = data[i:]
    if mx > 255:                 # rgb48be -> take the high byte of each 16-bit sample
        raw = raw[0::2]
    return (raw, w, h)
A = readppm(sys.argv[1]); B = readppm(sys.argv[2])
if not A or not B or not A[0] or not B[0]:
    print("NA"); sys.exit(0)
a, aw, ah = A; b, bw, bh = B
if (aw, ah) != (bw, bh):         # a mid-clip resize: min(len) would diff misaligned pixels
    print("DIM\t%dx%d\t%dx%d" % (aw, ah, bw, bh)); sys.exit(0)
n = min(len(a), len(b)); n -= n % 3
if n == 0:
    print("NA"); sys.exit(0)
tot = sum(abs(a[k]-b[k]) for k in range(n))
mad = tot/n
print("%.2f\t%.2f\t%dx%d" % (mad, mad/255*100, aw, ah))
PY
)"
  ffmpeg -y -nostdin -hide_banner -loglevel error -i "$d/first.ppm" -i "$d/last.ppm" \
    -filter_complex "[0:v]scale=-2:480[a];[1:v]scale=-2:480[b];[a][b]hstack=inputs=2" \
    -frames:v 1 "$OUT/loopcheck.png" >/dev/null 2>&1 || true
  rm -rf "$d"
  if [[ -z "$mad" || "$mad" == "NA" ]]; then
    echo "Error: --loop-check could not read the extracted frames." >&2; exit 1
  fi
  if [[ "$mad" == DIM* ]]; then
    local _tag d0 d1; IFS=$'\t' read -r _tag d0 d1 <<<"$mad"
    echo "loop-check: first and last frame differ in SIZE (${d0} -> ${d1}) — not a seamless loop (a mid-clip resize)." >&2
    echo "Wrote $OUT/loopcheck.png (left = first frame, right = last frame)."
    return 0
  fi
  local mad_abs mad_pct dims verdict
  IFS=$'\t' read -r mad_abs mad_pct dims <<<"$mad"
  # Verdict bands are empirical, not principled: <1% absorbs codec/I-vs-P quantization noise on a
  # genuinely identical wrap; >=4% was a clearly visible seam on the #85 test loops. A *localized*
  # seam can hide under a low global mean — read the strip, not just the number. Docs quote these
  # bands (reference.md, CHANGELOG 1.8.0) — change all three together.
  if awk -v p="$mad_pct" 'BEGIN{exit !(p<1.0)}'; then verdict="loops cleanly (first ~= last)"
  elif awk -v p="$mad_pct" 'BEGIN{exit !(p<4.0)}'; then verdict="near-seamless (small first/last drift)"
  else verdict="seam visible — the last frame differs from the first"; fi
  echo "loop-check: mean abs first/last diff = ${mad_abs}/255 (${mad_pct}%) over ${dims} — ${verdict}" >&2
  echo "Wrote $OUT/loopcheck.png (left = first frame, right = last frame)."
}

# A/B divergence — compare two captures of the SAME sequence (e.g. the same
# intro on two browsers) and flag WHERE in time they diverge. Both are sampled at --fps and
# scaled to the primary's dimensions, then ffmpeg's ssim filter scores per-frame similarity to a
# stats file; we emit a t,ssim CSV (lower = more different) and headline the most divergent
# moments. The headline cross-browser-bug tool. Uses PRE_ARGS (applied to both) — run after them.
run_ab() {
  local other="$1"
  [[ -f "$other" ]] || { echo "Error: --ab comparison file not found: $other" >&2; exit 2; }
  local W="" H=""
  if command -v ffprobe >/dev/null 2>&1; then
    W="$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    H="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$W" && -n "$H" ]] || { W=640; H=360; }   # fallback if ffprobe is unavailable
  local fc_pre="[0:v]fps=${FPS},scale=${W}:${H},setsar=1[a];[1:v]fps=${FPS},scale=${W}:${H},setsar=1[b];[a][b]ssim=stats_file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      "${PRE_ARGS[@]}" -i "$other" -filter_complex "${fc_pre}<tmp>/ssim.log" -f null -
    printf '\n'
    echo "# parse the ssim stats (n: / All:) -> CSV t,ssim; lowest SSIM = most divergent moment"
    return 0
  fi
  local sf; sf="$(mktemp)"
  # PRE_ARGS (-ss/-to) go before BOTH inputs so the two clips are aligned to the same window.
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" "${PRE_ARGS[@]}" -i "$other" \
    -filter_complex "${fc_pre}${sf}" -f null - >/dev/null 2>&1 || true
  local base; base="$(disp_base)"
  local csv
  csv="$(awk -v fps="$FPS" -v base="$base" '
    { n=""; s="";
      for(i=1;i<=NF;i++){ if($i ~ /^n:/) n=substr($i,3); if($i ~ /^All:/) s=substr($i,5) }
      if(n!="" && s!=""){ printf "%.3f,%s\n", base+(n-1)/fps, s } }' "$sf")"
  rm -f "$sf"
  echo "t,ssim"
  printf '%s\n' "$csv"
  if [[ -n "$csv" ]]; then
    echo "A/B divergence (1.0 = identical; lower = more different) — most divergent moments:" >&2
    printf '%s\n' "$csv" | sort -t, -k2 -g | head -n 3 | while IFS=, read -r _t _s; do
      printf '  t=%ss  ssim=%s\n' "$_t" "$_s" >&2
    done
  else
    echo "No SSIM samples — check both clips decode and overlap in time." >&2
  fi
  echo "(Both scaled to ${W}x${H} @ ${FPS} fps to compare; differing aspect ratios are stretched.)" >&2
}

# frame-cadence / jitter timeline. The container's nominal rate (r_frame_rate)
# vs its real average (avg_frame_rate) localizes choppiness to dropped/duplicated frames (the
# dogfood MVP); then mpdecimate finds the UNIQUE frames and we bucket them into --window bins so
# you see WHEN the stutter is (e.g. concentrated during an end-of-splash burst), not just an
# average. Emits a t,unique_frames,fps CSV; headlines nominal/effective + the choppiest windows.
run_cadence() {
  local rfr="" afr="" dur=""
  if command -v ffprobe >/dev/null 2>&1; then
    rfr="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate   -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    afr="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
  fi
  # Validate the freeze-gap threshold (1.9.0, #89): 100–113ms gaps are borderline noise on a
  # healthy 40–50fps VFR capture — tune with --freeze-min (seconds).
  if ! awk -v v="$FREEZE_MIN" 'BEGIN{exit !(v+0>0 && v==v+0)}' 2>/dev/null || ! [[ "$FREEZE_MIN" =~ ^[0-9.]+$ ]]; then
    echo "Error: --freeze-min must be a positive number of seconds (got '$FREEZE_MIN')." >&2
    exit 2
  fi
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "mpdecimate,showinfo" -an -f null -
    printf '\n'
    echo "# + ffprobe r_frame_rate/avg_frame_rate; bucket unique-frame pts_time into --window bins"
    echo "# -> CSV t,unique_frames,fps; headline verdict (worst freeze first) + choppiest windows"
    echo "# + ffmpeg -vf freezedetect=d=${FREEZE_MIN} -> longest frozen spans (freeze gaps, #56; --freeze-min tunes)"
    [[ -n "$MARKS" ]] && echo "# + overlay app perf marks from ${MARKS} on the freeze timeline (--marks, #94)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --cadence needs python3 to bucket the timeline. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(disp_base)"
  # --marks sidecar (1.10.0, #94): app performance.mark JSON ([{name,tMs,durMs?},...]) to correlate
  # with the freeze timeline — validate up front so a bad file is a clean exit 2, not broken output.
  if [[ -n "$MARKS" ]]; then
    [[ -f "$MARKS" ]] || { echo "Error: --marks file not found: $MARKS" >&2; exit 2; }
    if ! python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert isinstance(d,list) and all(isinstance(m,dict) and "name" in m and "tMs" in m for m in d)' "$MARKS" 2>/dev/null; then
      echo "Error: --marks must be a JSON array of {name, tMs, durMs?} objects (times in ms): $MARKS" >&2
      exit 2
    fi
  fi
  # Freeze-gap pass FIRST (#89): the worst freeze is the most actionable single number, so it now
  # leads the report as a one-line verdict instead of living at the bottom.
  local fd; fd="$(ffmpeg -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "freezedetect=d=${FREEZE_MIN}" -an -f null - 2>&1 || true)"
  local gaps; gaps="$(printf '%s\n' "$fd" | awk -v base="$base" '
    /freeze_start:/    { s=$NF }
    /freeze_duration:/ { if (s!="") { printf "%.3f\t%.3f\n", s+base, $NF; s="" } }
  ' | sort -t"$(printf '\t')" -k2 -nr)"
  local worst_gs="0" worst_gd="0"
  if [[ -n "$gaps" ]]; then IFS="$(printf '\t')" read -r worst_gs worst_gd <<<"$(head -1 <<<"$gaps")"; fi
  local gf; gf="$(mktemp)"; printf '%s\n' "$gaps" > "$gf"
  # mpdecimate drops near-duplicate frames; showinfo logs the surviving (unique) frames' times.
  # Write them to a temp file and pass its PATH to python — a `python3 - <<'PY'` heredoc already
  # uses stdin for the program, so the frame times can't also come in on stdin.
  local tf; tf="$(mktemp)"
  ffmpeg -hide_banner -nostats "${PRE_ARGS[@]}" -i "$VIDEO" -vf "mpdecimate,showinfo" -an -f null - 2>&1 \
    | sed -n 's/.*pts_time:\([0-9.][0-9.]*\).*/\1/p' > "$tf" || true
  python3 - "${WINDOW}" "$base" "${rfr:-0}" "${afr:-0}" "${dur:-0}" "$tf" "${START:+1}${END:+1}" "$worst_gs" "$worst_gd" "$gf" "$MARKS" "$FREEZE_MIN" <<'PY'
import sys, math
window=float(sys.argv[1]) or 0.5
base=float(sys.argv[2])
scoped=bool(sys.argv[7]) if len(sys.argv) > 7 else False   # --start/--end given? (1.3.0, #64)
def fr(s):
    try:
        if '/' in s:
            a,b=s.split('/'); b=float(b) or 1.0; return float(a)/b
        return float(s)
    except Exception:
        return 0.0
nominal=fr(sys.argv[3]); avg=fr(sys.argv[4])
try: duration=float(sys.argv[5])
except Exception: duration=0.0
times=sorted(base+float(x) for x in open(sys.argv[6]).read().split())
uniq=len(times)
span=(times[-1]-times[0]) if uniq>=2 else (duration or 0.0)
eff=uniq/span if span>0 else 0.0
# windowed unique-frame timeline
print("t,unique_frames,fps")
rows=[]
if times:
    t0=times[0]; tN=times[-1]
    nb=max(1, int(math.ceil((tN-t0)/window)) ) if window>0 else 1
    buckets={}
    for t in times:
        k=int((t-t0)//window)
        buckets[k]=buckets.get(k,0)+1
    for k in range(nb):
        cnt=buckets.get(k,0); ws=t0+k*window; fps=cnt/window
        rows.append((ws,cnt,fps)); print("%.3f,%d,%.2f"%(ws,cnt,fps))
# Leading static/near-black pre-roll (#70): mpdecimate drops duplicate frames, so a recording that
# starts on a black screen / URL bar / static splash reads as a run of 0-unique windows at the top.
# Find where sustained content begins (a window that is active AND followed by an active one) so the
# dead lead-in doesn't dominate the "choppiest windows" ranking — only detected on an unscoped scan.
lead_dead=0; content_start=(rows[0][0] if rows else base)
if not scoped and rows:
    k=0
    while k < len(rows) and not (rows[k][1] > 0 and (k+1 == len(rows) or rows[k+1][1] > 0)):
        k += 1
    if 0 < k < len(rows):
        lead=rows[:k]; content=rows[k:]
        content_med=sorted(r[1] for r in content)[len(content)//2]
        # Pre-roll only if the lead-in is genuinely near-static: it has idle windows AND even its
        # busiest window is far quieter than typical content. Otherwise real content that merely
        # FREEZES early (active -> 0 fps -> active) would be misread as pre-roll and its frozen
        # windows dropped from the ranking - exactly what --cadence must headline (#70 review).
        if any(r[1]==0 for r in lead) and max(r[1] for r in lead) <= max(1.0, 0.5*content_med):
            lead_dead=k; content_start=rows[k][0]
e=sys.stderr
# One-line verdict FIRST (1.9.0, #89): worst freeze + window stability are the actionable reads —
# nominal is a red herring on VFR captures (macOS r_frame_rate=240 is a timebase, not a target).
worst_gs=float(sys.argv[8]) if len(sys.argv)>8 and sys.argv[8] else 0.0
worst_gd=float(sys.argv[9]) if len(sys.argv)>9 and sys.argv[9] else 0.0
worst_ms=worst_gd*1000
# --marks sidecar (1.10.0, #94): app performance.mark entries ({name,tMs,durMs?}, ms -> s). A mark
# "aligns" with a freeze if its span overlaps the freeze span, or it starts within 0.5s before the
# freeze (a compile that kicks off just before the frames stop). Best = most overlap, then nearest.
import json
marks=[]
marks_path=sys.argv[11] if len(sys.argv)>11 else ""
if marks_path:
    for m in json.load(open(marks_path)):
        t=float(m["tMs"])/1000.0; d=float(m.get("durMs") or 0)/1000.0
        marks.append((m["name"], t, d))
def aligned_mark(gs, gd):
    best=None; best_key=(-1.0, float("inf"))
    for (name, t, d) in marks:
        overlap=min(gs+gd, t+d)-max(gs, t)
        near=(t <= gs and gs-(t+d) <= 0.5)          # starts before, ends within 0.5s of the freeze
        if overlap > 0 or near:
            key=(overlap, abs(t-gs))
            if key[0] > best_key[0] or (key[0]==best_key[0] and key[1] < best_key[1]):
                best=(name, t, d); best_key=key
    return best
def mark_note(gs, gd):
    m=aligned_mark(gs, gd)
    if not m: return ""
    name, t, d = m
    return " — aligns with mark '%s' (starts %.2fs, %.0f ms)" % (name, t, d*1000) if d>0 \
        else " — aligns with mark '%s' (@%.2fs)" % (name, t)
content=rows[lead_dead:] if rows else []
cfps=sorted(r[2] for r in content)
med=cfps[len(cfps)//2] if cfps else 0.0
low=cfps[0] if cfps else 0.0
if worst_ms >= 500:
    verdict="%.0f ms freeze @%.2fs%s; ~%.0f fps median otherwise" % (worst_ms, worst_gs, mark_note(worst_gs, worst_gd), med)
elif med>0 and low < 0.5*med:
    verdict="uneven — median ~%.0f fps, dips to ~%.0f fps; worst freeze %.0f ms" % (med, low, worst_ms)
elif worst_ms>0:
    verdict="steady ~%.0f fps, worst freeze %.0f ms" % (med, worst_ms)
else:
    verdict="steady ~%.0f fps, no sustained freezes" % med
e.write("verdict: %s\n" % verdict)
if marks:
    e.write("(%d app marks loaded from %s — freeze gaps below are annotated where one aligns)\n" % (len(marks), marks_path))
vfr_note=" (VFR capture: nominal is the container timebase, not a target — #89)" if nominal>=200 else ""
e.write("Stutter (cadence): nominal %.2f fps (r_frame_rate)%s; container avg %.2f fps; unique %.2f fps over %.2fs (%d unique frames).\n"
        % (nominal, vfr_note, avg, eff, span, uniq))
if nominal>0 and eff>0 and eff < 0.85*nominal:
    if nominal>=120:
        e.write("Unique-content rate is far below the (VFR) timebase — judge by the verdict/window stability, not nominal. Choppiest windows:\n")
    else:
        e.write("Effective cadence is well below nominal -> dropped/duplicated frames (stutter). Choppiest windows:\n")
    content_rows = rows[lead_dead:] if lead_dead else rows
    for ws,cnt,fps in sorted(content_rows, key=lambda r:r[2])[:3]:
        e.write("  @%.2fs: %.1f fps (%d unique in %.2fs)\n" % (ws, fps, cnt, window))
    if lead_dead:    # #70: dead lead-in was excluded from the ranking above
        e.write("(Skipped ~%.2fs of static/near-black lead-in - recording pre-roll or a splash before first paint; content starts ~@%.2fs. A frozen splash in that lead-in shows in the freeze gaps below, not here.)\n"
                % (content_start - rows[0][0], content_start))
    elif not scoped:  # whole-clip scan with no clear pre-roll: pre-roll can still rank (#64)
        e.write("(Whole clip scanned - pre-roll like URL-bar typing can rank here; re-run with --start/--end to scope to the suspect window.)\n")
else:
    e.write("Cadence looks steady (effective near nominal).\n")
# Freeze-gap detail (issue #56; the pass ran up top so the verdict could lead with the worst gap).
# Printed here (1.10.0, #94) so each line can carry its aligned-mark annotation.
fm=sys.argv[12] if len(sys.argv)>12 else "0.1"
gap_rows=[]
if len(sys.argv)>10 and sys.argv[10]:
    for ln in open(sys.argv[10]):
        parts=ln.split()
        if len(parts)>=2:
            try: gap_rows.append((float(parts[0]), float(parts[1])))
            except ValueError: pass
if gap_rows:
    e.write("Freeze gaps (frame unchanged >= %ss — tune with --freeze-min; longest first):\n" % fm)
    for gs, gd in gap_rows[:3]:
        e.write("  @%.2fs frozen for %d ms%s\n" % (gs, gd*1000, mark_note(gs, gd)))
else:
    e.write("No sustained freeze gaps (>= %ss) detected — tune with --freeze-min.\n" % fm)
PY
  rm -f "$tf" "$gf"
}

# frame-PACING timeline (1.2.0) — a from-scratch mode distinct from --cadence. --cadence counts
# UNIQUE CONTENT (mpdecimate); --pacing reads the actual per-frame presentation TIMESTAMPS (ffprobe)
# and reports the interval between consecutive displayed frames. So a clip that updates every frame
# but with UNEVEN timing — jank/jitter, a long-frame hitch, variable-frame-rate — is caught where
# unique-content cadence looks fine. Emits t,interval_ms and headlines median/p95/max + worst hitches.
run_pacing() {
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffprobe'; printf ' %q' -v error -select_streams v:0 -show_entries frame=best_effort_timestamp_time -of csv=p=0 "$VIDEO"
    printf '\n'
    echo "# -> per-frame presentation timestamps; diff consecutive -> t,interval_ms"
    echo "# -> headline median/p95/max interval + the worst long-frame hitches (uneven pacing)"
    return 0
  fi
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "Error: --pacing needs ffprobe (ships with ffmpeg). Install ffmpeg and re-run." >&2
    exit 2
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --pacing needs python3 to compute interval stats. Install python3 and re-run." >&2
    exit 2
  fi
  local tf; tf="$(mktemp)"
  ffprobe -v error -select_streams v:0 -show_entries frame=best_effort_timestamp_time \
    -of csv=p=0 "$VIDEO" 2>/dev/null > "$tf" || true
  # --t0 session offset (1.11.0, #96): --pacing reads the WHOLE file's pts (no seek — --start is
  # ignored here), so the reported times are already whole-file absolute; the only shift into session
  # time is T0 (NOT disp_base, which folds in --start and would double-count it in this un-seeked mode).
  local base; base="$(to_seconds "${T0:-0}")"
  python3 - "$tf" "$base" <<'PY'
import sys
base = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
ts = []
for line in open(sys.argv[1]):
    line = line.strip()
    try:
        ts.append(float(line))
    except ValueError:
        pass
ts.sort()
e = sys.stderr
print("t,interval_ms")
if len(ts) < 2:
    e.write("Pacing: too few timestamped frames to measure (need >= 2).\n")
    raise SystemExit(0)
# Shift the timestamp of each interval into session time; the interval DURATION is a delta, unchanged.
intervals = [(base + ts[i], (ts[i] - ts[i - 1]) * 1000.0) for i in range(1, len(ts))]
for t, d in intervals:
    print("%.3f,%.1f" % (t, d))
vals = sorted(d for _, d in intervals)
n = len(vals)
median = vals[n // 2]
p95 = vals[min(n - 1, int(n * 0.95))]
mx = max(intervals, key=lambda x: x[1])
fps = 1000.0 / median if median > 0 else 0.0
thr = max(1.75 * median, median + 8.0)   # a "hitch" = clearly longer than the typical frame time
hitches = [(t, d) for t, d in intervals if d > thr]
e.write("Pacing: median %.1f ms/frame (~%.1f fps); p95 %.1f ms; max %.1f ms @ %.2fs; "
        "%d hitch(es) > %.0f ms.\n" % (median, fps, p95, mx[1], mx[0], len(hitches), thr))
if hitches:
    e.write("Worst hitches (a frame held far longer than its neighbours -> visible stutter):\n")
    for t, d in sorted(hitches, key=lambda x: -x[1])[:5]:
        e.write("  @%.2fs: %.0f ms (%.1fx the median frame time)\n" % (t, d, d / median if median else 0))
else:
    e.write("Frame pacing is even (no frame held much longer than the median).\n")
PY
  rm -f "$tf"
}

# motion timeline — the mean inter-frame pixel delta over time, so "feels too
# long / choppy / is the dust even moving?" becomes a number and you can see WHERE motion
# concentrates. tblend=difference gives |this - previous|; signalstats' YAVG is that frame's
# average magnitude; metadata=print dumps it. Quantifies what --diff shows visually. Uses
# PRE_ARGS — run after them. Honors --crop (#66): cropping to a region (a spinner, drifting motes,
# a scrub bar) measures motion over just that ROI, lifting a subtle signal above the whole-frame
# downscale noise floor where it would otherwise read ~0 and be indistinguishable from frozen.
run_motion() {
  local vf="fps=${FPS},${CROP_VF}tblend=all_mode=difference,signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.YAVG (mean |frame - prev|) per frame -> CSV t,motion (0..255)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --motion needs python3 to read the per-frame stats. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(disp_base)"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" "${CROP:+1}" <<'PY'
import sys
mfile, base, fps = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]) or 1.0
cropped = len(sys.argv) > 4 and sys.argv[4] == "1"
t=None; n=0; rows=[]
print("t,motion")
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        # frame:N pts:.. pts_time:..
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.YAVG="):
        try: y=float(line.split("=",1)[1])
        except ValueError: continue
        tt = (base+t) if t is not None else (base+n/fps)
        # tblend on modern ffmpeg (5.x/6.x) emits N-1 output frames — its FIRST output is already a real
        # |f1-f0| difference, not a passthrough of frame 0 (verified: static gray reads YAVG=0 here, a raw
        # passthrough would read ~128). So keep every emitted sample; an old `if n>0` skip dropped a
        # genuine first delta and lost a sample (review finding). n still indexes the pts-fallback.
        rows.append((tt,y)); print("%.3f,%.2f" % (tt,y))
        n+=1
e=sys.stderr
if rows:
    peak=max(rows,key=lambda r:r[1]); avg=sum(r[1] for r in rows)/len(rows)
    e.write("Motion: mean inter-frame delta %.2f (0-255 luma); peak %.2f @ %.2fs over %d samples.\n"
            % (avg, peak[1], peak[0], len(rows)))
    e.write("Brightest = most motion; flat-low spans = little/no change (static).\n")
    # Amplitude floor (#66): a whole-frame downscale quantizes subtle motion (drifting motes, a slow
    # spinner) down toward 0, where "a little life" is indistinguishable from "frozen". Below ~3/255
    # peak, say so — and, if not already cropped, point at --crop as the way to lift the signal.
    FLOOR = 3.0
    if peak[1] < FLOOR:
        if cropped:
            e.write("Very low amplitude (peak %.2f < %.0f/255) even over the cropped region — this "
                    "reads as genuinely static/frozen, not just downscale-quantized.\n" % (peak[1], FLOOR))
        else:
            e.write("Very low amplitude (peak %.2f < %.0f/255): at full-frame scale, subtle motion (a "
                    "spinner, drifting motes) is hard to tell from frozen. Re-run with --crop W:H:X:Y on "
                    "that region to measure just it and lift it above the downscale noise floor.\n"
                    % (peak[1], FLOOR))
else:
    e.write("No motion samples — clip too short or --fps too low.\n")
PY
  rm -f "$mfile"
}

# stall / loop / hang detector (1.12.0, #102) — the counterpart to --stutter. --stutter finds frozen
# frames DURING motion; --stall finds the opposite failure: a span where NOTHING changes for
# >= --stall-min seconds (a boot hang, a dead canvas, an infinite splash/CSS-overlay loop). A fully
# static clip reads as "smooth" to a jank detector but is actually hung — this pass names it with a
# one-line verdict. Reuses the --motion machinery (tblend difference -> per-frame inter-frame delta
# YAVG): the longest run of frames whose delta stays below --stall-thresh is the stall. Honors
# --crop/--start/--end/--t0. Needs python3.
run_stall() {
  local vf="fps=${FPS},${CROP_VF}tblend=all_mode=difference,signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.YAVG (mean |frame - prev|) per frame; find the longest run below"
    echo "# the near-identical cutoff (${STALL_THRESH}/255) -> STALL verdict if it lasts >= ${STALL_MIN}s"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --stall needs python3 to scan the motion timeline. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(disp_base)"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" "$STALL_MIN" "$STALL_THRESH" "${CROP:+1}" <<'PY'
import sys
mfile=sys.argv[1]; base=float(sys.argv[2]); fps=float(sys.argv[3]) or 1.0
stall_min=float(sys.argv[4]); thresh=float(sys.argv[5]); cropped=len(sys.argv)>6 and sys.argv[6]=="1"
t=None; n=0; rows=[]
print("t,motion")
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.YAVG="):
        try: y=float(line.split("=",1)[1])
        except ValueError: continue
        tt=(base+t) if t is not None else (base+n/fps)
        # tblend on modern ffmpeg emits N-1 frames — its first output is already a real |f1-f0| delta
        # (static gray reads YAVG=0, not a ~128 passthrough), so keep every sample; an old `if n>0` skip
        # dropped a genuine first delta, starting the stall a frame late and undercounting it (review).
        rows.append((tt,y)); print("%.3f,%.2f"%(tt,y))
        n+=1
e=sys.stderr
if not rows:
    e.write("No motion samples — clip too short or --fps too low.\n"); raise SystemExit(0)
dt=1.0/fps if fps>0 else 0.0            # frame interval, to turn a run of samples into a real duration
# Longest contiguous run of near-identical (delta < thresh) frames.
best_s=best_e=None; best_dur=0.0; cur_s=None; prev_t=None
def close():
    global best_s,best_e,best_dur
    if cur_s is None: return
    dur=(prev_t-cur_s)+dt              # include the last frame's own interval
    if dur>best_dur: best_dur=dur; best_s=cur_s; best_e=prev_t
for tt,y in rows:
    if y<thresh:
        if cur_s is None: cur_s=tt
        prev_t=tt
    else:
        close(); cur_s=None; prev_t=None
close()
static_frac=sum(1 for _,y in rows if y<thresh)/len(rows)
span=(rows[-1][0]-rows[0][0])+dt
if best_dur>=stall_min:
    whole = best_dur>=0.98*span
    where = "the ENTIRE clip is" if whole else ("frames @%.2fs-@%.2fs are"%(best_s,best_e))
    tail = "" if whole else " (%.0f%% of the clip static)"%(100*static_frac)
    e.write("STALL: %s near-identical (mean delta < %.1f/255) for %.1fs%s.\n" % (where, thresh, best_dur, tail))
    e.write("  -> the app may be frozen/hung, a splash or CSS overlay looping with nothing beneath, or a dead canvas.\n")
    if not cropped:
        e.write("  (Whole-frame scan; if only a REGION should animate, --crop W:H:X:Y to it so a busy border can't mask a stalled centre.)\n")
else:
    e.write("No sustained stall: longest near-static span %.1fs < --stall-min %.1fs (%.0f%% of samples were near-static).\n"
            % (best_dur, stall_min, 100*static_frac))
PY
  rm -f "$mfile"
}

# whiteout / blown-highlight (+ black-dropout) detector (1.12.0, #102) — the companion to
# --blackdetect for the OTHER luma extreme. A merge/collision flash can blow a small viewport to full
# white for a beat; a dropout can drop it to black mid-clip. This reads each frame's MEAN LUMA
# (signalstats YAVG, no tblend) and reports contiguous spans at/above --white-thresh (blown) or at/below
# the black cutoff (dropout) lasting >= --white-min, with start/end/duration/peak. --white-min tunes the
# span, --white-thresh the whiteout cutoff. (For pixel-ratio black specifically, --blackdetect is more
# precise; this catches the bright side.) Honors --crop/--start/--end/--t0. Needs python3.
run_whiteout() {
  local vf="fps=${FPS},${CROP_VF}signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.YAVG (mean frame luma 0-255) per frame; report spans >= ${WHITE_THRESH}"
    echo "# (whiteout) or <= ${BLACK_LUMA_THRESH} (dropout) lasting >= ${WHITE_MIN}s, with duration + peak"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --whiteout needs python3 to scan the luma timeline. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(disp_base)"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" "$WHITE_MIN" "$WHITE_THRESH" "$BLACK_LUMA_THRESH" <<'PY'
import sys
mfile=sys.argv[1]; base=float(sys.argv[2]); fps=float(sys.argv[3]) or 1.0
wmin=float(sys.argv[4]); wth=float(sys.argv[5]); bth=float(sys.argv[6])
t=None; n=0; rows=[]
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.YAVG="):
        try: y=float(line.split("=",1)[1])
        except ValueError: continue
        tt=(base+t) if t is not None else (base+n/fps)
        rows.append((tt,y)); n+=1
e=sys.stderr
print("t,luma")
for tt,y in rows: print("%.3f,%.2f"%(tt,y))
if not rows:
    e.write("No luma samples — clip too short or --fps too low.\n"); raise SystemExit(0)
dt=1.0/fps if fps>0 else 0.0
def find_spans(pred, extremum):
    out=[]; s=None; prev=None; ext=None
    for tt,y in rows:
        if pred(y):
            if s is None: s=tt; ext=y
            prev=tt; ext=extremum(ext,y)
        elif s is not None:
            out.append((s,prev,(prev-s)+dt,ext)); s=None
    if s is not None: out.append((s,prev,(prev-s)+dt,ext))
    return out
white=[sp for sp in find_spans(lambda y:y>=wth, max) if sp[2]>=wmin]
black=[sp for sp in find_spans(lambda y:y<=bth, min) if sp[2]>=wmin]
ys=[y for _,y in rows]; lo=min(ys); hi=max(ys)
if white:
    e.write("Whiteout(s) (mean luma >= %.0f/255 for >= %.1fs — blown highlights):\n" % (wth, wmin))
    for s,en,dur,pk in white: e.write("  @%.2fs-@%.2fs: %.0f ms, peak luma %.0f/255\n" % (s,en,dur*1000,pk))
else:
    e.write("No whiteout (mean luma stayed below %.0f/255; brightest frame %.0f).\n" % (wth, hi))
if black:
    e.write("Black dropout(s) (mean luma <= %.0f/255 for >= %.1fs — for pixel-ratio black use --blackdetect):\n" % (bth, wmin))
    for s,en,dur,pk in black: e.write("  @%.2fs-@%.2fs: %.0f ms, darkest luma %.0f/255\n" % (s,en,dur*1000,pk))
else:
    e.write("No black dropout (mean luma stayed above %.0f/255; darkest frame %.0f).\n" % (bth, lo))
PY
  rm -f "$mfile"
}

# rotational/radial flow decomposition (#69) — --motion/--diff give magnitude and *where*,
# but not *character*: "a disk spinning in place" and "a disk spiralling inward" light them up the
# same. This computes a coarse block-matching optical flow between sampled frames and decomposes it
# about a center into its rotational (curl / mean tangential = "swirl") and radial (divergence /
# mean inward-outward = "suck") parts -> CSV t,speed,curl,div. Read: spin-in-place = |curl| high,
# div~0; suck inward = div<0; expansion = div>0. Frames are downscaled to fit 160x160 (both axes,
# so a tall portrait clip can't blow up the block count) and a per-block full search is used —
# reliable on high-frequency texture where a coarse step-search locks onto a spurious minimum.
# Flat (textureless) blocks are skipped so a big black background doesn't dilute the signal. The
# matcher is pure-python, so the number of sampled frames is capped (FLOW_MAX) to bound runtime —
# scope a longer clip with --start/--end or a lower --fps. Honors --crop, --start/--end,
# --flow-center. Needs python3.
run_flow() {
  local vf="${CROP_VF}fps=${FPS},scale='min(160,iw)':'min(160,ih)':force_original_aspect_ratio=decrease,format=gray"
  local flow_max=200                                  # cap sampled frames — full-search matching is O(frames)
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v "$flow_max" "<tmp>/f_%05d.pgm"
    printf '\n'
    echo "# then block-match consecutive PGMs (full search) -> flow field -> decompose about ${FLOW_CENTER} (fx:fy)"
    echo "# t,speed,curl,div   (curl = swirl/tangential; div = radial: <0 inward 'suck', >0 outward)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --flow needs python3 to compute block-matching flow. Install python3 and re-run." >&2
    exit 2
  fi
  local d; d="$(mktemp -d)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "$vf" -frames:v "$flow_max" "$d/f_%05d.pgm" >/dev/null 2>&1 || true
  # If we filled the cap, the clip has more than we analyzed — say so (don't silently truncate).
  if [[ "$(find "$d" -maxdepth 1 -name 'f_*.pgm' | wc -l)" -ge "$flow_max" ]]; then
    echo "Note: --flow analyzed the first ${flow_max} sampled frames (~$(awk "BEGIN{printf \"%.0f\", ${flow_max}/${FPS}}")s at --fps ${FPS}); narrow with --start/--end or lower --fps to cover a different/longer span." >&2
  fi
  local base; base="$(disp_base)"
  python3 - "$d" "$FPS" "$base" "$FLOW_CENTER" <<'PY'
import sys, os, glob
d, fps, base, center = sys.argv[1:5]
fps=float(fps) or 1.0; base=float(base)
try:
    fx, fy = (float(x) for x in center.split(":"))
except Exception:
    fx, fy = 0.5, 0.5
if not (0.0 <= fx <= 1.0 and 0.0 <= fy <= 1.0):   # out-of-range / nan / inf -> frame center
    fx, fy = 0.5, 0.5

def read_pgm(p):
    try:
        with open(p, 'rb') as f: data=f.read()
        if data[:2]!=b'P5': return 0,0,None
        i=2; vals=[]
        while len(vals)<3:
            while i<len(data) and data[i:i+1].isspace(): i+=1
            if data[i:i+1]==b'#':
                while i<len(data) and data[i:i+1]!=b'\n': i+=1
                continue
            j=i
            while j<len(data) and not data[j:j+1].isspace(): j+=1
            vals.append(int(data[i:j])); i=j
        w,h,_=vals; i+=1
        px=data[i:i+w*h]
        if len(px)!=w*h: return 0,0,None            # truncated frame (killed ffmpeg) -> skip, don't IndexError
        return w,h,px
    except Exception:
        return 0,0,None

B=16          # block size (px)
R=8           # search radius (px) — raise --fps if motion exceeds this per frame
STRIDE=2      # subsample the block when scoring (~4x faster; fine for a coarse flow)
VAR=20.0      # min block variance (over the sampled pixels) to trust a vector (skip flat background)

def sad(a, b, w, ax, ay, bx, by):
    s=0; yy=0
    while yy<B:
        ra=(ay+yy)*w+ax; rb=(by+yy)*w+bx; xx=0
        while xx<B:
            dv=a[ra+xx]-b[rb+xx]
            s+= dv if dv>=0 else -dv
            xx+=STRIDE
        yy+=STRIDE
    return s

def block_var(px, w, ax, ay):
    s=0; s2=0; n=0; yy=0
    while yy<B:
        r=(ay+yy)*w+ax; xx=0
        while xx<B:
            v=px[r+xx]; s+=v; s2+=v*v; n+=1
            xx+=STRIDE
        yy+=STRIDE
    m=s/n
    return s2/n - m*m

frames=[fr for fr in (read_pgm(p) for p in sorted(glob.glob(os.path.join(d,"f_*.pgm"))))
        if fr[2] is not None and fr[0]>0]
print("t,speed,curl,div")
rows=[]
for k in range(len(frames)-1):
    w,h,a=frames[k]; w2,h2,b=frames[k+1]
    if (w,h)!=(w2,h2): continue
    cx=fx*w; cy=fy*h
    tang=[]; rad=[]; spd=[]
    # only interior blocks whose FULL +-R search stays in-frame — a clipped search at the edge
    # underestimates motion asymmetrically and injects a spurious radial (inward) bias.
    y=R
    while y+B+R<=h:
        x=R
        while x+B+R<=w:
            if block_var(a,w,x,y) < VAR:            # flat block — no reliable vector
                x+=B; continue
            # full search within +-R for the best-matching displacement. High-frequency texture
            # (a churning disk, noise) has a spiky match surface where a coarse step-search locks
            # onto a spurious minimum — full search finds the true global one.
            bdx=bdy=0; best=None
            dy2=-R
            while dy2<=R:
                ny=y+dy2
                if 0<=ny and ny+B<=h:
                    dx2=-R
                    while dx2<=R:
                        nx=x+dx2
                        if 0<=nx and nx+B<=w:
                            c=sad(a,b,w,x,y,nx,ny)
                            if best is None or c<best: best=c; bdx=dx2; bdy=dy2
                        dx2+=1
                dy2+=1
            rx=(x+B/2.0)-cx; ry=(y+B/2.0)-cy
            r=(rx*rx+ry*ry)**0.5
            if r < B:                               # too close to center — unstable, skip
                x+=B; continue
            rad.append((bdx*rx+bdy*ry)/r)           # radial: + outward, - inward ("suck")
            tang.append((rx*bdy-ry*bdx)/r)          # tangential: signed "swirl"
            spd.append((bdx*bdx+bdy*bdy)**0.5)
            x+=B
        y+=B
    t=base+(k+0.5)/fps
    if spd:
        mv=sum(spd)/len(spd); curl=sum(tang)/len(tang); div=sum(rad)/len(rad)
    else:
        mv=curl=div=0.0
    print("%.3f,%.2f,%.2f,%.2f" % (t,mv,curl,div))
    rows.append((t,mv,curl,div))
e=sys.stderr
if rows:
    mv=sum(r[1] for r in rows)/len(rows)
    curl=sum(r[2] for r in rows)/len(rows)
    div=sum(r[3] for r in rows)/len(rows)
    acurl=abs(curl); adiv=abs(div)
    e.write("Flow: mean speed %.2f px/frame; curl %.2f (swirl), div %.2f (radial) about center "
            "(%.2f,%.2f) over %d pair(s).\n" % (mv, curl, div, fx, fy, len(rows)))
    if mv < 0.4:
        e.write("Near-zero flow — little/no motion, or too textureless to match; try --crop on the "
                "subject or raise --fps.\n")
    elif acurl >= 1.5*adiv and acurl > 0.4:
        e.write("Rotational-dominant: swirl >> radial -> 'spinning in place' (rotating, not moving "
                "toward/away from center).\n")
    elif adiv >= 1.5*acurl and adiv > 0.4:
        e.write(("Radial-inward-dominant: div < 0 -> content pulled toward center ('suck').\n"
                 if div < 0 else
                 "Radial-outward-dominant: div > 0 -> content expanding away from center.\n"))
    elif acurl > 0.4 and adiv > 0.4:
        e.write(("Swirl + inward radial -> 'suck + twirl toward center' (spiralling inward).\n"
                 if div < 0 else
                 "Swirl + outward radial -> spiralling outward.\n"))
    else:
        e.write("Flow present but not clearly rotational or radial about this center — likely "
                "translation; try --flow-center fx:fy or --crop to center the feature.\n")
else:
    e.write("No flow samples — clip too short, textureless, or --fps too low.\n")
PY
  rm -rf "$d"
}

# colour-saturation timeline — signalstats' SATAVG per sampled frame, so "is this
# clownish/over-saturated or muted/elegant?" is a number you can verify after a fix (requested in
# the rc.16/rc.17 dogfeeds). 0 ≈ greyscale; higher ≈ more vivid (SAT maxes ~180). Uses PRE_ARGS.
run_saturation() {
  local vf="fps=${FPS},signalstats,metadata=mode=print:file="
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" \
      -vf "${vf}<tmp>" -an -f null -
    printf '\n'
    echo "# read lavfi.signalstats.SATAVG per frame -> CSV t,saturation (0 grey .. ~180 vivid)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: --saturation needs python3 to read the per-frame stats. Install python3 and re-run." >&2
    exit 2
  fi
  local base; base="$(disp_base)"
  local mfile; mfile="$(mktemp)"
  ffmpeg -hide_banner -loglevel error "${PRE_ARGS[@]}" -i "$VIDEO" -vf "${vf}${mfile}" -an -f null - >/dev/null 2>&1 || true
  python3 - "$mfile" "$base" "$FPS" <<'PY'
import sys
mfile, base, fps = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]) or 1.0
t=None; n=0; rows=[]
print("t,saturation")
for line in open(mfile):
    line=line.strip()
    if line.startswith("frame:"):
        t=None
        for tok in line.split():
            if tok.startswith("pts_time:"):
                try: t=float(tok.split(":",1)[1])
                except ValueError: t=None
    elif line.startswith("lavfi.signalstats.SATAVG="):
        try: s=float(line.split("=",1)[1])
        except ValueError: continue
        tt = (base+t) if t is not None else (base+n/fps)
        rows.append((tt,s)); print("%.3f,%.2f" % (tt,s)); n+=1
e=sys.stderr
if rows:
    peak=max(rows,key=lambda r:r[1]); avg=sum(r[1] for r in rows)/len(rows)
    e.write("Saturation: average %.1f (0 grey .. ~180 vivid); peak %.1f @ %.2fs over %d frames.\n"
            % (avg, peak[1], peak[0], len(rows)))
    e.write("High/sustained = vivid/'clownish'; low = muted/'elegant'. Compare against the look you want.\n")
else:
    e.write("No saturation samples — clip too short or --fps too low.\n")
PY
  rm -f "$mfile"
}

# Never silently overwrite a previous run (#64): the default per-video dir plus sequential
# names (contact_0001.png …) meant a second extraction over a different window clobbered the
# first. If the target dir already holds PNGs, write this run into a mode+window-tagged
# subdirectory (counter-suffixed if THAT collides too) and say so — earlier frames stay
# untouched. Runs in --dry-run as well, so printed commands target the same dir a real run
# would. Skipped for analysis modes (they write no PNGs — no junk dirs, no misleading note).
# `find` (not a glob) so metacharacters in the video name can't bypass the check.
_has_pngs() { [[ -d "$1" ]] && [[ -n "$(find "$1" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null)" ]]; }
_writes_pngs=1
for _flag in "$BLACKDETECT" "$OCR_ROI" "$MEASURE" "$PROBE" "$PALETTE" "$AB" "$CADENCE" \
             "$MOTION" "$STALL" "$WHITEOUT" "$SATURATION" "$PACING" "$FLOW" "$OCCUPANCY" "$LIST_SCENES"; do
  [[ -n "$_flag" ]] && _writes_pngs=""
done
if [[ -n "$_writes_pngs" ]] && _has_pngs "$OUT"; then
  _tag="dense"
  [[ -n "$SCENE"      ]] && _tag="scene"
  [[ -n "$CONTACT"    ]] && _tag="contact"
  [[ -n "$DIFF"       ]] && _tag="diff"
  [[ -n "$STACK"      ]] && _tag="stack"
  [[ -n "$TIMESTAMPS" ]] && _tag="ts"
  [[ -n "$STRIP"      ]] && _tag="strip"
  [[ -n "$CMP_VIDEOS" ]] && _tag="compare"
  _win="${START:-0}-${END:-end}"
  _sub="${_tag}_$(printf '%s' "$_win" | tr ':/' '..')"
  # a rerun with the SAME mode+window would land in the same subdir — bump a counter until free.
  _n=2
  while _has_pngs "$OUT/$_sub"; do
    _sub="${_tag}_$(printf '%s' "$_win" | tr ':/' '..')_${_n}"
    _n=$(( _n + 1 ))
  done
  echo "Note: $OUT already has frames from a previous run — writing into $OUT/$_sub/ instead (nothing overwritten)." >&2
  OUT="$OUT/$_sub"
fi
[[ -n "$DRY_RUN" ]] || mkdir -p "$OUT"   # don't create dirs in --dry-run

# --strip mode — stitch two EXISTING frames into a before/after strip (no --video).
# The single most useful artifact for a UI-state-transition bug (per DedTxt dogfood).
if [[ -n "$STRIP" ]]; then
  IFS=',' read -r _sa _sb <<<"$STRIP"
  if [[ -z "${_sa:-}" || -z "${_sb:-}" ]]; then
    echo "Error: --strip needs two frames: --strip before.png,after.png" >&2
    exit 2
  fi
  if [[ -z "$DRY_RUN" ]]; then   # skip existence check when only printing commands
    for _img in "$_sa" "$_sb"; do
      [[ -f "$_img" ]] || { echo "Error: --strip frame not found: $_img" >&2; exit 1; }
    done
  fi
  echo "Strip mode: $_sa | $_sb -> $OUT/strip.png" >&2
  # normalize both frames to a common height (even width via -2) before hstack, so
  # mismatched resolutions (e.g. a .mov frame vs a .webm frame) still stitch cleanly.
  run_ff -hide_banner -loglevel error -i "$_sa" -i "$_sb" \
    -filter_complex "[0:v]scale=-2:720[a];[1:v]scale=-2:720[b];[a][b]hstack=inputs=2" \
    -frames:v 1 "$OUT/strip.png"
  [[ -n "$DRY_RUN" ]] || echo "Wrote $OUT/strip.png (before/after; left=$_sa right=$_sb)."
  feedback_hint
  exit 0
fi

# --list-scenes — print the timestamps (seconds, one per line) of detected scene cuts,
# then exit. Feed the interesting ones back into --timestamps. Threshold from --scene (def 0.3).
if [[ -n "$LIST_SCENES" ]]; then
  _thr="${SCENE:-0.3}"
  if [[ -n "$DRY_RUN" ]]; then
    run_ff -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" -f null -
    echo "(dry run — the command above prints showinfo lines; their pts_time values are the cuts)"
    exit 0
  fi
  echo "Scene cuts (threshold=$_thr) in $VIDEO — pts_time seconds:" >&2
  # capture, then guide the user if no cuts were found at this threshold.
  _cuts="$(ffmpeg -hide_banner -nostats -i "$VIDEO" -vf "select='gt(scene,${_thr})',showinfo" \
    -f null - 2>&1 | sed -n 's/.*pts_time:\([0-9.][0-9.]*\).*/\1/p' || true)"
  if [[ -n "$_cuts" ]]; then
    printf '%s\n' "$_cuts"
  else
    echo "No scene cuts at threshold ${_thr}. Try a lower --scene (e.g. 0.1), or sample steadily with --fps." >&2
  fi
  feedback_hint
  exit 0
fi

# prepare the optional --label timestamp-burn-in segment (probed; empty if unsupported).
build_label_vf
# ADDED (1.0.3): offset for absolute-time labels in --start-seeked modes (dense/scene/diff/contact).
# --t0 shifts these on-frame labels into session time too (1.11.0, #96) — disp_base folds in both.
LBL_OFF="$(disp_base)"

# --compare-videos a,b — ONE stacked contact sheet, a row per clip on a
# NORMALIZED phase axis (N columns spread across each clip's own duration), so two clips of
# different lengths line up by % through the sequence, not by absolute time. Answers "why does B
# differ from A" (fresh vs replay, before/after a fix, two browsers) in a single image. With
# --label, each tile gets its source timestamp burned in. Uses LABEL_VF — runs after build_label_vf.
run_compare_videos() {
  local a b; IFS=',' read -r a b <<<"$CMP_VIDEOS"
  if [[ -z "$a" || -z "$b" ]]; then
    echo "Error: --compare-videos needs two files: --compare-videos a.mov,b.mov" >&2; exit 2
  fi
  local cols="$COLS"; [[ -z "$COLS_SET" ]] && cols=8   # finer default phase axis for a comparison
  local da db
  da="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$a" 2>/dev/null | head -n1 || true)"
  db="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$b" 2>/dev/null | head -n1 || true)"
  # Frames-per-second to land ~cols frames across each clip's full duration (the phase axis).
  local fa fb
  fa="$(awk -v c="$cols" -v d="${da:-0}" 'BEGIN{ printf "%.6f", (d>0)?c/d:c }')"
  fb="$(awk -v c="$cols" -v d="${db:-0}" 'BEGIN{ printf "%.6f", (d>0)?c/d:c }')"
  local _lbl; _lbl="$(label_seg 0)"   # CHANGED (1.0.3): each clip starts at t=0; absolute = pts
  local fc="[0:v]fps=${fa},scale=${TILEW}:-1${_lbl},tile=${cols}x1[a];[1:v]fps=${fb},scale=${TILEW}:-1${_lbl},tile=${cols}x1[b];[a][b]vstack=inputs=2"
  if [[ -n "$DRY_RUN" ]]; then
    printf 'ffmpeg'; printf ' %q' -hide_banner -loglevel error -i "$a" -i "$b" -filter_complex "$fc" -frames:v 1 "${OUT}/compare.png"
    printf '\n'
    echo "# top row = $a, bottom row = $b; ${cols} columns each = % through that clip (normalized phase axis)"
    return 0
  fi
  for f in "$a" "$b"; do [[ -f "$f" ]] || { echo "Error: --compare-videos file not found: $f" >&2; exit 2; }; done
  if [[ -z "$da" || -z "$db" ]]; then
    echo "Error: --compare-videos needs ffprobe to read each clip's duration." >&2; exit 2
  fi
  if ffmpeg -hide_banner -loglevel error -i "$a" -i "$b" -filter_complex "$fc" -frames:v 1 "$OUT/compare.png"; then
    echo "Wrote $OUT/compare.png — top row $a (${da}s), bottom row $b (${db}s), ${cols} cols across each." >&2
    echo "Columns align by % through each clip (normalized phase axis), NOT absolute time." >&2
  else
    echo "Error: --compare-videos failed (do both files decode?)." >&2; exit 1
  fi
}
if [[ -n "$CMP_VIDEOS" ]]; then
  run_compare_videos
  feedback_hint
  exit 0
fi

# crop a region (e.g. an on-screen FPS/HUD), applied before scale so the
# region is zoomed. Geometry is ffmpeg crop syntax W:H:X:Y (expressions like iw/ih allowed).
[[ -n "$CROP" ]] && CROP_VF="crop=${CROP},"

# heads-up if the clip is sparser than the requested fps (dense/contact/timestamps).
[[ -z "$SCENE" && -z "$DRY_RUN" ]] && warn_if_sparse "$FPS"

# Build the leading seek/duration args (apply -ss/-to before -i for speed/accuracy).
PRE_ARGS=()
[[ -n "$START" ]] && PRE_ARGS+=(-ss "$START")
[[ -n "$END"   ]] && PRE_ARGS+=(-to "$END")

# blackdetect is an analysis mode (no PNGs) — report spans and exit.
if [[ -n "$BLACKDETECT" ]]; then
  run_blackdetect
  feedback_hint
  exit 0
fi

# --ocr-roi is an analysis mode — emit a t,text value timeline and exit.
if [[ -n "$OCR_ROI" ]]; then
  run_ocr_roi "$OCR_ROI"
  feedback_hint
  exit 0
fi

# --measure is an analysis mode — emit a geometry timeline and exit.
if [[ -n "$MEASURE" ]]; then
  run_measure "$MEASURE"
  feedback_hint
  exit 0
fi

# --probe is an analysis mode — print capture geometry and exit.
if [[ -n "$PROBE" ]]; then
  run_probe
  feedback_hint
  exit 0
fi

# --palette is an analysis mode — print dominant colours (or the colour arc with --over-time) and exit.
if [[ -n "$PALETTE" ]]; then
  if [[ -n "$OVER_TIME" ]]; then run_palette_over_time; else run_palette; fi
  feedback_hint
  exit 0
fi

# --loop-check is an analysis mode — seam diff between the first and last frame, then exit.
if [[ -n "$LOOP_CHECK" ]]; then
  run_loop_check
  feedback_hint
  exit 0
fi

# --ab is an analysis mode — print an A/B divergence timeline and exit.
if [[ -n "$AB" ]]; then
  run_ab "$AB"
  feedback_hint
  exit 0
fi

# --cadence is an analysis mode — print a frame-cadence timeline and exit.
if [[ -n "$CADENCE" ]]; then
  run_cadence
  feedback_hint
  exit 0
fi

# --motion is an analysis mode — print an inter-frame motion timeline and exit.
if [[ -n "$MOTION" ]]; then
  run_motion
  feedback_hint
  exit 0
fi

# --stall is an analysis mode — flag a sustained no-change (hang/loop) span and exit (1.12.0, #102).
if [[ -n "$STALL" ]]; then
  run_stall
  feedback_hint
  exit 0
fi

# --whiteout is an analysis mode — flag blown-highlight / black-dropout spans and exit (1.12.0, #102).
if [[ -n "$WHITEOUT" ]]; then
  run_whiteout
  feedback_hint
  exit 0
fi

# --saturation is an analysis mode — print a colour-saturation timeline and exit.
if [[ -n "$SATURATION" ]]; then
  run_saturation
  feedback_hint
  exit 0
fi

# --pacing is an analysis mode — print a frame-pacing (timestamp-jitter) timeline and exit.
if [[ -n "$PACING" ]]; then
  run_pacing
  feedback_hint
  exit 0
fi

# --flow is an analysis mode — print a rotational/radial flow timeline and exit (1.4.0, #69).
if [[ -n "$FLOW" ]]; then
  run_flow
  feedback_hint
  exit 0
fi

# --occupancy is an analysis mode — print a subject-extent timeline and exit (1.4.0, #69).
if [[ -n "$OCCUPANCY" ]]; then
  run_occupancy
  feedback_hint
  exit 0
fi

# Choose how frames are selected: scene-change boundaries or a fixed sample rate.
if [[ -n "$SCENE" ]]; then
  SELECT="select='gt(scene,${SCENE})'"
  set_vfr_flag
  MODE_DESC="scene-change (threshold=$SCENE)"
else
  SELECT="fps=${FPS}"
  MODE_DESC="dense (fps=$FPS)"
fi

if [[ -n "$TIMESTAMPS" ]]; then
  # Timestamp mode: for each moment, a dense burst over a +/-window plus a before/after
  # strip (first & last burst frame side by side) — ideal for showing a transient.
  set_vfr_flag
  # ADDED (1.0.3, issue #53): a window narrower than one frame interval extracts 0 frames —
  # warn instead of silently producing nothing.
  if [[ -z "$DRY_RUN" ]] && awk -v w="$WINDOW" -v f="$FPS" 'BEGIN{ exit !((2*w*f) < 1) }'; then
    echo "Warning: --window ${WINDOW}s @ ${FPS}fps spans <1 frame per burst — likely 0 frames; raise --window or --fps." >&2
  fi
  IFS=',' read -r -a _ts <<<"$TIMESTAMPS"
  i=0
  for t in "${_ts[@]}"; do
    [[ -n "$t" ]] || continue
    i=$((i + 1))
    idx="$(printf '%02d' "$i")"
    tsec="$(to_seconds "$t")"
    bstart="$(awk -v x="$tsec" -v w="$WINDOW" 'BEGIN{ s=x-w; if (s<0) s=0; printf "%.3f", s }')"
    bend="$(awk -v x="$tsec" -v w="$WINDOW" 'BEGIN{ printf "%.3f", x+w }')"
    # On-frame label origin (1.11.0, #96): this burst seeks to its OWN bstart (video-absolute — not
    # --start), so the session-time label is bstart + T0, NOT LBL_OFF/disp_base (which folds in --start).
    blabel="$(awk -v b="$bstart" -v z="$(to_seconds "${T0:-0}")" 'BEGIN{ printf "%.3f", b+z }')"
    echo "Timestamp $t -> burst [$bstart,$bend] @${FPS}fps -> $OUT/ts${idx}_*" >&2
    run_ff -hide_banner -loglevel error \
      -ss "$bstart" -to "$bend" -i "$VIDEO" "${VFR[@]}" \
      -vf "fps=${FPS},${CROP_VF}scale=${FRAMEW}:-1$(label_seg "$blabel")" \
      "$OUT/ts${idx}_%03d.png"
    # Before/after strip from the first and last frame of the burst. (Skipped in --dry-run,
    # since it depends on the frames the burst above would have written.)
    [[ -n "$DRY_RUN" ]] && continue
    # while-read, not mapfile: this script must run on macOS system bash 3.2 (mapfile is bash 4+),
    # and this was its only bash-4 construct (handoff review).
    _f=()
    while IFS= read -r _fp; do _f+=("$_fp"); done < <(find "$OUT" -maxdepth 1 -type f -name "ts${idx}_[0-9]*.png" | sort)
    if (( ${#_f[@]} >= 2 )); then
      run_ff -hide_banner -loglevel error \
        -i "${_f[0]}" -i "${_f[$(( ${#_f[@]} - 1 ))]}" \
        -filter_complex hstack -frames:v 1 \
        "$OUT/ts${idx}_strip.png"
    fi
  done
elif [[ -n "$CONTACT" ]]; then
  # Contact-sheet mode: scale each selected frame down and tile them into a grid, so the
  # whole timeline is one image (or a few). Spills into contact_0002.png, ... if needed.
  [[ -n "$DRY_RUN" ]] || tune_contact_for_source   # portrait auto-cols + illegibility (issue #14)
  # --label now burns the source timestamp into each tile too (drawtext is
  # applied per-frame, before tiling), which is exactly what timing analysis wants.
  echo "Contact-sheet mode [$MODE_DESC], ${COLS}x${ROWS} per sheet -> $OUT" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},${CROP_VF}scale=${TILEW}:-1$(label_seg "$LBL_OFF"),tile=${COLS}x${ROWS}" \
    "$OUT/contact_%04d.png"
elif [[ -n "$STACK" ]]; then
  # ROI time-stack (1.3.0, #62): crop a fixed band (a scrub bar, an HUD, a status row) and tile
  # the samples VERTICALLY, so one image reads that region's evolution top-to-bottom across the
  # clip — the "region-of-interest time-stack" view the scrub-bar dogfood built by hand.
  if [[ -z "$CROP_VF" ]]; then
    echo "Error: --stack needs --crop W:H:X:Y (the region to track over time)." >&2
    exit 2
  fi
  set_vfr_flag
  # rows = samples in the selected span (span * fps), clamped so one sheet stays readable;
  # extra samples spill into stack_0002.png, ... exactly like contact sheets do.
  _sspan=""
  _sstart="$(to_seconds "${START:-0}")"
  if [[ -n "$END" ]]; then
    _sspan="$(awk -v e="$(to_seconds "$END")" -v s="$_sstart" 'BEGIN{ print e-s }')"
  elif command -v ffprobe >/dev/null 2>&1; then
    # `|| true`: an ffprobe failure (corrupt/empty file) must fall back, not kill the script
    # under set -euo pipefail (it even killed --dry-run — review finding on 1.3.0).
    _sdur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null | head -n1 || true)"
    [[ -n "$_sdur" ]] && _sspan="$(awk -v d="$_sdur" -v s="$_sstart" 'BEGIN{ print d-s }')"
  fi
  _srows=48   # unknown-span fallback = the same per-sheet cap the docs state (was 24)
  if [[ -n "$_sspan" ]]; then
    _srows="$(awk -v sp="$_sspan" -v f="$FPS" 'BEGIN{ r=int(sp*f+0.999); if(r<1)r=1; if(r>48)r=48; print r }')"
  fi
  echo "ROI time-stack mode (fps=$FPS, crop=$CROP, 1x${_srows} per sheet) -> $OUT" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "fps=${FPS},${CROP_VF}scale=${TILEW}:-1$(label_seg "$LBL_OFF"),tile=1x${_srows}" \
    "$OUT/stack_%04d.png"
elif [[ -n "$DIFF" ]]; then
  # frame-difference mode — each frame is |this − previous| (tblend), so motion lights
  # up. Scan consecutive diffs to see what moved and infer direction (issue #16).
  set_vfr_flag
  echo "Frame-diff mode (fps=$FPS) -> $OUT (bright = changed pixels between frames)" >&2
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "fps=${FPS},${CROP_VF}tblend=all_mode=difference,scale='min(${MAXW},iw)':-1$(label_seg "$LBL_OFF")" \
    "$OUT/diff_%04d.png"
elif [[ -n "$SCENE" ]]; then
  echo "Scene-change mode (threshold=$SCENE) -> $OUT" >&2
  # cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" "${VFR[@]}" \
    -vf "${SELECT},${CROP_VF}scale='min(${MAXW},iw)':-1$(label_seg "$LBL_OFF")" \
    "$OUT/scene_%04d.png"
else
  echo "Dense mode (fps=$FPS) -> $OUT" >&2
  # cap width (min so small clips aren't upscaled) — was -vf "$SELECT"
  run_ff -hide_banner -loglevel error \
    "${PRE_ARGS[@]}" -i "$VIDEO" \
    -vf "${SELECT},${CROP_VF}scale='min(${MAXW},iw)':-1$(label_seg "$LBL_OFF")" \
    "$OUT/frame_%04d.png"
fi

if [[ -n "$DRY_RUN" ]]; then
  echo "(dry run — the ffmpeg command(s) above were printed, not executed; no files written)"
else
  COUNT=$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
  echo "Extracted ${COUNT} image(s) to: ${OUT}"
  if [[ -n "$CONTACT" ]]; then
    echo "Each contact sheet tiles frames left-to-right, top-to-bottom in time order."
  else
    echo "Read them in filename order to reconstruct the timeline."
  fi
fi

feedback_hint   # one-click pre-filled feedback nudge at end of run
