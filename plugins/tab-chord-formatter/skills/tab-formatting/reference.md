# Tab / Chord Formatter — reference

The canonical format this skill produces, and the rules for getting there. Everything is plain,
monospace-friendly text — no markdown styling inside the tab itself; alignment is by literal
character columns.

## The canonical layout

```
Title: Starry Eyes
Artist: Roky Erickson
Capo: 2
Key: G
Tuning: Standard (EADGBe)

[Intro]
G  C  G  C

[Verse 1]
G                 C
Well I met you at the deli
G                  C
You were buying a soda
Am                 D
And I knew right then

[Chorus]
        C          G
Starry eyes, starry eyes
```

Order: **metadata header → blank line → sections**, each section a `[Label]` followed by its
lines, with exactly one blank line between sections.

## Metadata header

One `Field: value` per line at the very top, only for facts you actually have. Recognized fields,
in this order: **Title, Artist, Composer, Album, Capo, Key, Tuning, Tabbed by**. Omit unknown
fields — never invent them. If the source has no metadata and none is inferable, skip the header
entirely and start with the first section.

- **Capo:** a number (fret), e.g. `Capo: 2`. "No capo" → omit.
- **Tuning:** name it; default `Standard (EADGBe)`. Note alternates explicitly (`Drop D (DADGBe)`).

## Section labels

A whole line naming a structural part becomes `[Title Case]`, with one blank line before and
after. The normalizer script handles the common vocabulary automatically:

Intro · Verse (numbered: `[Verse 1]`, `[Verse 2]`) · Pre-Chorus · Chorus · Refrain · Hook ·
Bridge · Interlude · Instrumental · Solo · Breakdown · Outro · Coda · Ending · Tag · Vamp.

Number repeated sections in order of appearance (`[Verse 1]`, `[Verse 2]`, …). Roman numerals in
the source are upper-cased (`[Verse II]`). When a section repeats identically, you may write the
label and `(repeat [Chorus])` rather than duplicating the body — but only if it's truly identical.

## Chords over lyrics — alignment is everything

A chord line sits **directly above** its lyric line, each chord starting at the column of the
syllable where the chord changes. This only works in monospace and only if the columns are right.

- **Inline chords → lifted out.** Convert `[G]Somewhere [D]over the rainbow` to:
  ```
  G         D
  Somewhere over the rainbow
  ```
  The `G` is above `Some`, the `D` above `o` of `over`. Count characters literally.
- **Repair collapsed spacing.** A plaintext paste often crushes the spaces that positioned the
  chords (or merges the chord line into the lyric). Rebuild the spacing so each chord lands on its
  syllable. Use the lyric line as the ruler.
- **Chord-only lines** (intros, turnarounds) are just the chords separated by two+ spaces:
  `G  C  G  D`.
- Don't pad lines to equal length or add trailing spaces.

## Chord naming

Keep the song's actual chords; standardize only the spelling:

- Root uses `#`/`b` as written; quality is lowercase where conventional: `Am`, `F#m7`, `Cadd9`,
  `Bbmaj7`, `Dsus4`, `G7`, `Em9`.
- Slash chords show the bass after a slash: `D/F#`, `C/G`.
- No-chord passages: `N.C.`
- Don't reharmonize, simplify, or "correct" the harmony — only normalize how it's written.

## ASCII tablature blocks

Six lines, high-to-low, each prefixed by its string letter and a bar:

```
e|---------------------------|
B|---------------------------|
G|-------0-------0-----------|
D|---0-------0-------0-------|
A|---------------------------|
E|-3-------3-------3---------|
```

- Always six strings, ordered `e B G D A E` (high to low). Use lowercase `e` for the high string.
- Keep fret numbers and technique markers (`h` hammer-on, `p` pull-off, `/` slide up, `\` slide
  down, `b` bend, `~` vibrato, `x` mute) exactly as in the source.
- Align bar lines `|` and keep the `-` runs consistent so the grid reads cleanly. Don't change the
  notes; only fix spacing/alignment and missing string rows.

## What the script does vs. what you do

| Deterministic — `format-tab.py` | Judgment — the skill (you) |
| :-- | :-- |
| Strip HTML tags, decode entities | Re-align chords over the right syllables |
| CRLF→LF, tabs→spaces, trim trailing ws | Lift inline `[G]` chords onto a chord line |
| `[Section]` label standardization | Infer/number missing sections |
| Collapse blank lines; idempotent | Standardize chord spelling; build the header |
| Never touches internal alignment | Tidy ASCII tab grids; resolve ambiguity |

## Faithfulness

Fix **layout**, not **content**. Preserve the song's words, chords, and structure. If a chord is
illegible or a section boundary is genuinely uncertain, format your best reading and note the
uncertainty in a short line below the tab — don't silently invent.
