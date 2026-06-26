#!/usr/bin/env python3
"""format-tab.py — normalize and render a guitar/chord tab, chord sheet, or multi-song songbook.

Two output modes:
  * screen (default): deterministic, mechanical text cleanup — the readable monospace layout.
  * print:  a clean, CONSISTENT monospace PDF (or print-ready HTML), one song per page by default
            (--songs-per-page N to pack more). Everything is rendered in a single font + size, which
            is the usual "make it consistent" fix for a songbook assembled from mixed sources.

Screen cleanup (always applied first):
  * decode HTML entities and strip stray HTML tags (safe to paste a copied web tab straight in)
  * CRLF -> LF, tabs -> spaces, strip trailing whitespace
    (it NEVER touches a line's *internal* spacing — that spacing is the chord/lyric/tab alignment)
  * standardize section labels (Intro / Verse 1 / Pre-Chorus / Chorus / Bridge / Solo / Outro / …)
    to `[Title Case]`, with exactly one blank line before and after
  * collapse runs of blank lines to a single blank line; emit a single trailing newline

The judgment-heavy parts — re-aligning chords back over the right lyric syllables when a paste lost
its spacing, inferring section boundaries, correcting chord spellings — are the `tab-formatting`
skill's job (see SKILL.md). This script never guesses those.

Usage:
  format-tab.py [FILE]                       # screen mode: formatted text on stdout (default)
  format-tab.py --mode screen [FILE]         # explicit screen mode
  format-tab.py --print --pdf OUT.pdf [FILE] # print mode: render a PDF (Courier 10pt, 1 song/page)
  format-tab.py --print --pdf OUT.pdf --songs-per-page 2 [FILE]
  format-tab.py --print --html OUT.html [FILE]   # print-ready HTML (no Chromium needed)
  format-tab.py --help

Print options:
  --pdf PATH            Render the songbook to a PDF at PATH (needs Chromium/Chrome; auto-detected).
  --html PATH           Write the print-ready HTML to PATH (browser-printable; no Chromium needed).
  --songs-per-page N    Songs per printed page (default 1 = one song per page).
  --font NAME           Monospace font family (default "Courier New").
  --size PT             Body font size in points (default 10).
  --dedent / --no-dedent  Strip the common leading indentation from each song (tidies a songbook
                        whose songs were pasted with different left margins, and avoids overflow).
                        On by default in print mode; --no-dedent keeps the source indentation.

Songs are split on a title line ("Artist – Title", un-indented, preceded by a blank line) or an
explicit form-feed (\\f). A single tab with no such title is treated as one song.
"""
import sys
import re
import html
import os
import glob
import shutil
import subprocess
import tempfile

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


# --- print/render layer (1.2.0) -------------------------------------------------------------------

# A title line: text, spaced dash (en/em/hyphen), text — e.g. "Animals – House of the Rising Sun".
_TITLE_RE = re.compile(r"^\S.*\S\s+[–—-]\s+\S.*$")


def split_songs(text):
    """Split a cleaned songbook into [(title, body_text), ...].

    A new song begins at an un-indented title line ("Artist – Title") preceded by a blank line (or
    the start of input), or right after an explicit form-feed (\\f). Input with no such title is a
    single song titled by its first non-blank line (or "Untitled").
    """
    lines = text.replace("\f", "\n\f\n").split("\n")
    songs = []
    title = None
    body = []
    prev_blank = True

    def flush():
        if title is not None or any(b.strip() for b in body):
            t = title if title is not None else (next((b.strip() for b in body if b.strip()), "Untitled"))
            songs.append((t, "\n".join(body).strip("\n")))

    force_next_title = False
    for i, ln in enumerate(lines):
        if ln == "\f":
            force_next_title = True
            continue
        is_title = ln and not ln[:1].isspace() and _TITLE_RE.match(ln) and (prev_blank or force_next_title)
        if force_next_title and ln.strip() and not is_title:
            # the line after a form-feed is the title even without a dash
            is_title = True
        if is_title:
            flush()
            title = ln.strip()
            body = []
            force_next_title = False
        else:
            body.append(ln)
        prev_blank = (ln.strip() == "")
    flush()
    if not songs:
        songs = [("Untitled", text.strip("\n"))]
    return songs


def dedent_body(body):
    """Remove the common leading whitespace shared by every non-blank, non-label line of a song.

    Section labels like `[Solo]` sit at column 0 after cleanup; counting them would zero the common
    indent and defeat the dedent, so they're excluded from the measurement (but still re-aligned).
    """
    lines = body.split("\n")
    measured = [ln for ln in lines if ln.strip() and not re.match(r"\s*\[.+\]\s*$", ln)]
    if not measured:
        return body
    indent = min(len(ln) - len(ln.lstrip(" ")) for ln in measured)
    if indent <= 0:
        return body
    pad = " " * indent
    return "\n".join(ln[indent:] if ln.startswith(pad) else ln for ln in lines)


def render_html(songs, font="Courier New", size=10, per_page=1, dedent=False):
    """Build a print-ready HTML document: monospace, consistent font/size, paginated by song."""
    esc = html.escape
    title_pt = size + 1
    css = f"""
  @page {{ size: letter; margin: 0.6in; }}
  html, body {{ margin: 0; padding: 0; }}
  .page {{ page-break-after: always; }}
  .page:last-child {{ page-break-after: auto; }}
  .song {{ break-inside: avoid; }}
  .song + .song {{ margin-top: 1.6em; }}
  .title {{ font-family: "{font}", "Courier New", monospace; font-size: {title_pt}pt;
            font-weight: bold; margin: 0 0 0.35em; }}
  .body {{ font-family: "{font}", "Courier New", Courier, monospace; font-size: {size}pt;
           white-space: pre; margin: 0; line-height: 1.15; }}
""".rstrip()
    pages = [songs[i:i + max(1, per_page)] for i in range(0, len(songs), max(1, per_page))]
    parts = ['<!doctype html><html><head><meta charset="utf-8"><style>', css, "</style></head><body>"]
    for page in pages:
        parts.append('<div class="page">')
        for title, body in page:
            b = dedent_body(body) if dedent else body
            parts.append('<div class="song">')
            parts.append(f'<div class="title">{esc(title)}</div>')
            parts.append(f'<pre class="body">{esc(b)}</pre>')
            parts.append("</div>")
        parts.append("</div>")
    parts.append("</body></html>\n")
    return "\n".join(parts)


def find_chromium():
    """Locate a Chromium/Chrome binary (PATH names, then a Playwright browsers dir)."""
    for n in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "chrome"):
        p = shutil.which(n)
        if p:
            return p
    base = os.environ.get("PLAYWRIGHT_BROWSERS_PATH")
    if base and os.path.isdir(base):
        for pat in ("chromium-*/chrome-linux/chrome",
                    "chromium_headless_shell-*/chrome-linux/headless_shell"):
            hits = sorted(glob.glob(os.path.join(base, pat)))
            if hits:
                return hits[-1]
    return None


def html_to_pdf(html_str, out_path):
    chrome = find_chromium()
    if not chrome:
        raise RuntimeError(
            "no Chromium/Chrome found for PDF rendering. Install chromium (or set "
            "PLAYWRIGHT_BROWSERS_PATH), or use --html to emit print-ready HTML and print it "
            "from your browser (File → Print → Save as PDF).")
    tmp_html = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8")
    tmp_html.write(html_str)
    tmp_html.close()
    profile = tempfile.mkdtemp(prefix="tabpdf-")
    try:
        # --disable-dev-shm-usage avoids Chromium hanging/crashing on the small /dev/shm of CI
        # containers; a hard timeout means a misbehaving browser can never wedge the caller.
        subprocess.run(
            [chrome, "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
             "--no-first-run", f"--user-data-dir={profile}", "--no-pdf-header-footer",
             f"--print-to-pdf={os.path.abspath(out_path)}", f"file://{os.path.abspath(tmp_html.name)}"],
            check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired as e:
        raise RuntimeError("Chromium timed out rendering the PDF (120s) — try --html and print "
                           "from a browser instead.") from e
    finally:
        try:
            os.unlink(tmp_html.name)
        except OSError:
            pass
        shutil.rmtree(profile, ignore_errors=True)


def _parse_args(argv):
    opts = {"mode": "screen", "pdf": None, "html": None, "songs_per_page": 1,
            "font": "Courier New", "size": 10, "dedent": True, "file": None}
    it = iter(argv)
    for a in it:
        if a in ("--print",):
            opts["mode"] = "print"
        elif a == "--mode":
            opts["mode"] = next(it, "screen")
        elif a == "--pdf":
            opts["pdf"] = next(it, None); opts["mode"] = "print"
        elif a == "--html":
            opts["html"] = next(it, None); opts["mode"] = "print"
        elif a == "--songs-per-page":
            opts["songs_per_page"] = max(1, int(next(it, "1") or "1"))
        elif a == "--font":
            opts["font"] = next(it, "Courier New")
        elif a == "--size":
            opts["size"] = float(next(it, "10") or "10")
        elif a == "--dedent":
            opts["dedent"] = True
        elif a == "--no-dedent":
            opts["dedent"] = False
        elif a.startswith("-"):
            raise ValueError(f"unknown option: {a}")
        else:
            opts["file"] = a
    return opts


def main(argv):
    if any(a in ("-h", "--help") for a in argv):
        sys.stdout.write(__doc__)
        return 0
    try:
        opts = _parse_args(argv)
    except ValueError as e:
        sys.stderr.write(f"Error: {e}\nRun with --help for usage.\n")
        return 2
    try:
        text = (open(opts["file"], encoding="utf-8", errors="replace").read()
                if opts["file"] else sys.stdin.read())
    except OSError as e:
        sys.stderr.write(f"Error: {e}\n")
        return 2

    cleaned = format_tab(text)

    if opts["mode"] == "screen":
        sys.stdout.write(cleaned)
        return 0

    # print mode
    songs = split_songs(cleaned)
    html_doc = render_html(songs, font=opts["font"], size=opts["size"],
                           per_page=opts["songs_per_page"], dedent=opts["dedent"])
    if opts["html"]:
        with open(opts["html"], "w", encoding="utf-8") as fh:
            fh.write(html_doc)
        sys.stderr.write(f"Wrote {opts['html']} ({len(songs)} song(s)).\n")
    if opts["pdf"]:
        try:
            html_to_pdf(html_doc, opts["pdf"])
        except (RuntimeError, subprocess.CalledProcessError) as e:
            sys.stderr.write(f"Error: PDF render failed: {e}\n")
            return 1
        sys.stderr.write(f"Wrote {opts['pdf']} ({len(songs)} song(s), "
                         f"{opts['songs_per_page']}/page, {opts['font']} {opts['size']}pt).\n")
    if not opts["pdf"] and not opts["html"]:
        # print mode with no target: emit the HTML to stdout so it can be piped/redirected.
        sys.stdout.write(html_doc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
