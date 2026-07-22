---
name: tab-formatting
description: Format a guitar tab or chord sheet into a clean, readable layout, or render a monospace PDF songbook. Use when the user pastes or links chords/tab (chords over lyrics, ASCII tablature, a Capo/Key/Tuning header) and asks to clean it up, align the chords, "make this readable," or print/PDF a songbook.
---

# Tab / Chord Formatter

Turn a messy tab or chord sheet into a **clean, standard, readable** one and output it as plain
text. The input is usually copied from somewhere — a web page, a forum, an email — so it arrives
with broken alignment, HTML entities, stray tags, inconsistent section labels, and random blank
lines. Your job is to produce the canonical layout described in **`reference.md`**.

There are two halves to this, and keeping them separate is the whole method:

1. **Mechanical cleanup is deterministic — run the script.** It never guesses.
2. **Alignment and structure need judgment — that is you.** A monospace chord line only means
   anything if each chord sits above the right syllable, and a paste often destroys that spacing.
   Restoring it, inferring sections, and standardizing chord names is the model's job.

## 1. Run the normalizer first

```
${CLAUDE_PLUGIN_ROOT}/skills/tab-formatting/scripts/format-tab.py < input.txt
# or pass a path:
${CLAUDE_PLUGIN_ROOT}/skills/tab-formatting/scripts/format-tab.py input.txt
```

It does only the safe, reversible things (strip tags/entities, normalize endings, standardize
`[Section]` labels, collapse blank runs — full list in `--help`), never a line's **internal**
spacing (that spacing IS the chord/lyric alignment), and is idempotent. It deliberately does
**not** touch alignment — pass its output to step 2.

If the user pasted the tab inline rather than as a file, you can still reason over it directly;
the script is most useful for a copied-from-web blob with entities/tags.

## 2. Apply judgment — the part the script can't

Read `reference.md` for the full target format. The work that needs a human/model eye:

- **Re-align chords over lyrics.** This is the most common breakage: a plaintext paste collapses
  the multiple spaces that positioned each chord, so the chord line and lyric line merge or
  drift. Rebuild a monospace chord line where **each chord starts directly above the syllable it
  changes on**. When the source has the chords inline (e.g. `[G]Somewhere over the [D]rainbow`),
  lift them onto a separate line above. Count characters — alignment is literal column position.
- **Identify and label sections.** Infer Intro / Verse N / Pre-Chorus / Chorus / Bridge / Solo /
  Outro etc. from repetition and context when they're missing or inconsistent, as `[Section]`.
- **Standardize chord spelling.** Consistent root + quality (`F#m7`, `Cadd9`, `Bbmaj7`, `D/F#`);
  `N.C.` for no-chord; keep the source's actual chords — don't reharmonize.
- **Build/keep a metadata header.** Title, Artist, and any of Album / Capo / Key / Tuning /
  Tabbed by that are known. Don't invent facts you don't have.
- **Tidy ASCII tab blocks** (the 6-line `e|B|G|D|A|E` grids): align the bar `|` and `-` runs,
  keep all six strings, don't alter the actual fret numbers.

## 3. Output

Print the finished tab as **plain text** (in a fenced code block so the monospace alignment
survives). Preserve the song faithfully — fix layout, not content. If something is genuinely
ambiguous (an unreadable chord, an uncertain section boundary), format your best reading and note
the uncertainty briefly below the tab rather than silently guessing.

See `reference.md` for the canonical format spec: the metadata header, section vocabulary,
chord-over-lyric alignment rules, ASCII-tab conventions, and chord-naming standards.

## Print mode — a PDF songbook

`format-tab.py` has two modes. **Screen** (the default, above) emits clean plain text. **Print**
renders a **PDF** (or print-ready HTML) in a single consistent monospace font + size — the usual
fix for a songbook assembled from mixed sources — paginated by song.

```
# one song per page (default), Courier New 10pt:
${CLAUDE_PLUGIN_ROOT}/skills/tab-formatting/scripts/format-tab.py --print --pdf songbook.pdf book.txt
# pack two songs per page; shrink the font for wide ASCII-tab blocks:
… --print --pdf songbook.pdf --songs-per-page 2 --size 9 book.txt
# no Chromium? emit print-ready HTML and print it from a browser:
… --print --html songbook.html book.txt
```

Flags, defaults, and the song-split rule are in `--help` (PDF needs Chromium/Chrome; `--html`
is the no-Chromium fallback). Clean each song's alignment (steps 1–2) **before** rendering —
the PDF is a faithful monospace snapshot, so the alignment must already be right in the text.
