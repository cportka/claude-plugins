#!/usr/bin/env python3
"""format-tab.py — normalize a guitar/chord tab or chord sheet into a standard, readable layout.

Deterministic, mechanical cleanup ONLY. The judgment-heavy parts — re-aligning chords back over
the right lyric syllables when a paste lost its spacing, inferring section boundaries, correcting
chord spellings — are the `tab-formatting` skill's job (see SKILL.md). This script never guesses.

What it does:
  * decode HTML entities and strip stray HTML tags (safe to paste a copied web tab straight in)
  * CRLF -> LF, tabs -> spaces, strip trailing whitespace
    (it NEVER touches a line's *internal* spacing — that spacing is the chord/lyric/tab alignment)
  * standardize section labels (Intro / Verse 1 / Pre-Chorus / Chorus / Bridge / Solo / Outro / …)
    to `[Title Case]`, with exactly one blank line before and after
  * collapse runs of blank lines to a single blank line; emit a single trailing newline

Usage:
  format-tab.py [FILE]      # read FILE (or stdin if omitted) -> formatted tab on stdout
  format-tab.py --help
"""
import sys
import re
import html

# Section words recognized as structural labels (whole-line only).
_SECTION_WORDS = (
    "intro", "verse", "pre-chorus", "pre chorus", "prechorus", "chorus", "refrain", "hook",
    "bridge", "interlude", "instrumental", "solo", "breakdown", "outro", "coda", "ending",
    "tag", "vamp",
)
# A whole line that is just a section word (optionally bracketed, numbered, or colon-suffixed).
_SEC_RE = re.compile(
    r"^\s*\[?\s*(?P<name>" + "|".join(w.replace(" ", r"\s*") for w in _SECTION_WORDS) +
    r")\s*(?P<num>\d+|[ivx]+)?\s*\]?\s*:?\s*$",
    re.IGNORECASE,
)


def _norm_section(m):
    name = re.sub(r"\s+", "", m.group("name")).lower()
    if name in ("prechorus", "prechorus"):
        name = "pre-chorus"
    if name == "pre-chorus":
        label = "Pre-Chorus"
    else:
        label = name.title()
    num = m.group("num")
    if num:
        num = num.upper() if re.fullmatch(r"[ivx]+", num, re.IGNORECASE) else num
        return f"[{label} {num}]"
    return f"[{label}]"


def format_tab(text):
    # Paste-from-web safety: drop HTML tags, then decode entities (&#39; -> ', &amp; -> & …).
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    raw = [ln.replace("\t", "    ").rstrip() for ln in text.split("\n")]

    out = []
    for ln in raw:
        m = _SEC_RE.match(ln) if ln.strip() else None
        if m:
            if out and out[-1] != "":
                out.append("")          # one blank line before a section header
            out.append(_norm_section(m))
            out.append("")              # tentative blank after (deduped below)
        else:
            out.append(ln)

    # Collapse runs of blank lines to a single blank line.
    collapsed = []
    for ln in out:
        if ln == "" and (not collapsed or collapsed[-1] == ""):
            continue
        collapsed.append(ln)
    while collapsed and collapsed[-1] == "":
        collapsed.pop()
    return "\n".join(collapsed) + "\n"


def main(argv):
    if any(a in ("-h", "--help") for a in argv):
        sys.stdout.write(__doc__)
        return 0
    files = [a for a in argv if not a.startswith("-")]
    try:
        text = open(files[0], encoding="utf-8", errors="replace").read() if files else sys.stdin.read()
    except OSError as e:
        sys.stderr.write(f"Error: {e}\n")
        return 2
    sys.stdout.write(format_tab(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
