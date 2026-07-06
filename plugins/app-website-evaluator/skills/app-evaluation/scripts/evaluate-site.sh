#!/usr/bin/env bash
#
# evaluate-site.sh — quick, evidence-gathering checklist for an app/website evaluation.
#
# Scans either a live URL (needs curl) or a local built site / repo directory, and prints a
# PASS/WARN/FAIL/INFO checklist across crawlability, SEO, social/sharing, brand assets,
# AI-readiness, security (URL mode), and performance hints. It is a *starting point* for the
# app-evaluation skill — heuristic and best-effort, not a verdict. Read robots.txt, the sitemap,
# the page <head>, and the source for the real story.
#
# Usage:
#   evaluate-site.sh --url <https://example.com>
#   evaluate-site.sh --dir <path-to-built-site-or-repo>
#   evaluate-site.sh --html page.html [--headers resp-headers.txt]   # analyze already-fetched HTML
#   curl -sSL <url> | evaluate-site.sh --html -                      # ...or from stdin
#   evaluate-site.sh --url <url> --dry-run     # print what it would fetch, no network
#
# Options:
#   --url <url>    Evaluate a live site (fetches the page, headers, robots.txt, sitemap, llms.txt).
#   --dir <path>   Evaluate a local directory (an index.html / built site, or a repo).
#   --html <f|->   Score HTML you already fetched (a file, or - for stdin) WITHOUT curl reaching the
#                  origin — for sandboxes whose egress proxy blocks arbitrary hosts. Pair with
#                  --headers to also run the live security-header checks (#79).
#   --headers <f|-> Response headers (e.g. `curl -sSI` output, or an MCP fetch's headers) to feed the
#                  Security header checks in --html mode. Optional; only meaningful with --html.
#   --dry-run      Print the requests/files that would be checked, without doing network I/O.
#   --json         Emit a machine-readable JSON scorecard on stdout (human report -> stderr).
#   -h, --help     Show this help.
#
# Scoring: every check is PASS (1.0), WARN (0.5), or FAIL (0.0); INFO is not scored. Each dimension
# scores 0-100 = 100*(pass + 0.5*warn)/(scored checks), with a letter grade (A>=90, B>=80, C>=70,
# D>=60, F<60). The overall is the weight-averaged dimension score. It's still advisory, not a gate.
#
# Exit: 0 always (this is an advisory report, not a gate); findings are in the output.
#
set -uo pipefail

URL=""
DIR=""
HTMLIN=""
HEADIN=""
DRY_RUN=""
JSON=""

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --html) HTMLIN="${2:-}"; shift 2 ;;
    --headers) HEADIN="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

# Exactly one input source.
_n_src=0
[[ -n "$URL" ]] && _n_src=$((_n_src+1))
[[ -n "$DIR" ]] && _n_src=$((_n_src+1))
[[ -n "$HTMLIN" ]] && _n_src=$((_n_src+1))
if [[ "$_n_src" -eq 0 ]]; then
  echo "Error: pass one of --url <url>, --dir <path>, or --html <file|->. See --help." >&2
  exit 2
fi
if [[ "$_n_src" -gt 1 ]]; then
  echo "Error: use exactly one of --url / --dir / --html, not several." >&2
  exit 2
fi
if [[ -n "$HEADIN" && -z "$HTMLIN" ]]; then
  echo "Error: --headers is only meaningful with --html (--url fetches its own headers)." >&2
  exit 2
fi
if [[ "$HTMLIN" == "-" && "$HEADIN" == "-" ]]; then
  echo "Error: --html - and --headers - can't both read stdin; put one in a file." >&2
  exit 2
fi

# Input mode: url (live fetch) | dir (local build/repo) | html (pre-fetched HTML, optional headers).
if   [[ -n "$URL" ]];    then MODE=url
elif [[ -n "$HTMLIN" ]]; then MODE=html
else                          MODE=dir
fi

# --- output helpers + per-dimension scoring -------------------------------------------
# Each check is PASS (1.0) / WARN (0.5) / FAIL (0.0); INFO is unscored. sec() opens a dimension;
# ok/warn/bad/info tally it. With --json the human report goes to stderr so stdout is pure JSON.
P=0; W=0; F=0                                  # global tally (kept for the summary line)
declare -a SEC_NAME SEC_P SEC_W SEC_F          # per-dimension tallies, parallel arrays
CUR=-1
RFD=1; [[ -n "$JSON" ]] && RFD=2               # report file descriptor (stderr under --json)
REC=""; [[ -n "$JSON" ]] && REC="$(mktemp)"    # per-check records for the JSON output

_rec() { [[ -n "$REC" ]] && printf '%s\t%s\t%s\n' "$CUR" "$1" "$2" >>"$REC"; return 0; }
say()  { printf '%s\n' "$1" >&"$RFD"; }
sec()  { SEC_NAME+=("$1"); SEC_P+=(0); SEC_W+=(0); SEC_F+=(0); CUR=$(( ${#SEC_NAME[@]} - 1 ))
         printf '\n\033[1m%s\033[0m\n' "$1" >&"$RFD"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1" >&"$RFD"; P=$((P+1)); [[ $CUR -ge 0 ]] && SEC_P[CUR]=$(( SEC_P[CUR] + 1 )); _rec pass "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1" >&"$RFD"; W=$((W+1)); [[ $CUR -ge 0 ]] && SEC_W[CUR]=$(( SEC_W[CUR] + 1 )); _rec warn "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1" >&"$RFD"; F=$((F+1)); [[ $CUR -ge 0 ]] && SEC_F[CUR]=$(( SEC_F[CUR] + 1 )); _rec fail "$1"; }
info() { printf '  \033[36mINFO\033[0m  %s\n' "$1" >&"$RFD"; _rec info "$1"; }

# weight per dimension (sums to 100); grade band for a 0-100 score.
weight_for() {
  case "$1" in
    "Crawlability / indexing")  echo 15 ;;
    "SEO")                      echo 20 ;;
    "Social / sharing")         echo 12 ;;
    "Brand assets / standards") echo 13 ;;
    "AI-readiness")             echo 10 ;;
    "Security / hygiene")       echo 18 ;;
    "Performance / load (hints)") echo 12 ;;
    *)                          echo 10 ;;
  esac
}
grade_for() {
  if   [[ "$1" -ge 90 ]]; then echo A
  elif [[ "$1" -ge 80 ]]; then echo B
  elif [[ "$1" -ge 70 ]]; then echo C
  elif [[ "$1" -ge 60 ]]; then echo D
  else echo F; fi
}

# Case-insensitive "does the page HTML contain this regex?"  (best-effort). Matches against a
# whitespace-collapsed copy ($HTML_FLAT, set once the page is loaded) so a tag whose attributes are
# split across lines — Prettier's default for long tags — still matches; grep is line-oriented, so
# matching the raw $HTML read multi-line <meta …>/<script …> as "missing" (issue #67). Falls back
# to raw $HTML until HTML_FLAT is computed.
html_has() { grep -qiE "$1" <<<"${HTML_FLAT:-$HTML}"; }

# htest <regex> <good-fn> <good-msg> <bad-fn> <bad-msg> — dispatch on whether the HTML matches.
# (Avoids the `A && B || C` pattern, which isn't if-then-else.)
htest() { if html_has "$1"; then "$2" "$3"; else "$4" "$5"; fi; }
# hdr <header-regex> <good-msg> <bad-fn> <bad-msg> — dispatch on a response header (URL mode).
hdr()   { if grep -qi "$1" <<<"$HEADERS"; then ok "$2"; else "$3" "$4"; fi; }

if [[ -n "$DRY_RUN" ]]; then
  if [[ "$MODE" == url ]]; then
    echo "Dry run — would fetch (no network performed):"
    echo "  curl -fsSL $URL                 # page HTML"
    echo "  curl -sSI  $URL                 # response headers (HTTPS, security)"
    echo "  curl -fsS  ${URL%/}/robots.txt"
    echo "  curl -fsS  ${URL%/}/sitemap.xml"
    echo "  curl -fsS  ${URL%/}/llms.txt"
  elif [[ "$MODE" == html ]]; then
    echo "Dry run — would read HTML from: ${HTMLIN} ${HEADIN:+(+ response headers from $HEADIN)}"
    echo "  (no network; robots.txt/sitemap.xml/llms.txt/security.txt can't be probed from HTML alone)"
  else
    echo "Dry run — would read from: $DIR (index.html, robots.txt, sitemap.xml, llms.txt, manifest, icons)"
  fi
  exit 0
fi

# --- acquire the page HTML + a way to test root files ---------------------------------
HTML=""
ROOT_DESC=""
# root_has <relpath>: is this site-root file present/reachable? Echoes "yes"/"no" (and "unknown"
# from the URL branch when a request can't be made). Defined per-mode just below; one of the two
# branches always runs (we already errored if neither --url nor --dir was given).

if [[ -n "$URL" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: --url needs curl (not found). Use --dir on a local build, or install curl." >&2
    exit 2
  fi
  ROOT_DESC="$URL"
  base="${URL%/}"
  UA="Mozilla/5.0 (compatible; portka-app-evaluator/1.0)"
  HTML="$(curl -fsSL --max-time 20 -A "$UA" "$URL" 2>/dev/null || true)"
  if [[ -z "$HTML" ]]; then
    warn "could not fetch page HTML from $URL (network blocked, redirect, or non-200) — header/file checks still attempted"
  fi
  HEADERS="$(curl -sSI --max-time 20 -A "$UA" "$URL" 2>/dev/null || true)"
  root_has() {
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -A "$UA" "${base}/$1" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then echo "yes"; else echo "no"; fi
  }
elif [[ -n "$HTMLIN" ]]; then
  # Pre-fetched HTML (a file, or - for stdin) — for sandboxes whose egress proxy blocks arbitrary
  # hosts, so an agent that fetched the page another way (MCP tool, headless browser, web_fetch)
  # can still get the standardized scorecard, incl. the Security header checks via --headers (#79).
  if [[ "$HTMLIN" == "-" ]]; then
    HTML="$(cat 2>/dev/null || true)"; ROOT_DESC="(HTML from stdin)"
  else
    [[ -f "$HTMLIN" ]] || { echo "Error: --html file not found: $HTMLIN" >&2; exit 2; }
    HTML="$(cat "$HTMLIN" 2>/dev/null || true)"; ROOT_DESC="$HTMLIN"
  fi
  [[ -z "$HTML" ]] && warn "--html input is empty — nothing to score (check the file / the fetch that produced it)"
  if [[ -n "$HEADIN" ]]; then
    if [[ "$HEADIN" == "-" ]]; then
      HEADERS="$(cat 2>/dev/null || true)"
    else
      [[ -f "$HEADIN" ]] || { echo "Error: --headers file not found: $HEADIN" >&2; exit 2; }
      HEADERS="$(cat "$HEADIN" 2>/dev/null || true)"
    fi
  else
    HEADERS=""
  fi
  # We have only the HTML (+ maybe headers), not the site root — root files are indeterminate.
  root_has() { echo "unknown"; }
else
  [[ -d "$DIR" ]] || { echo "Error: directory not found: $DIR" >&2; exit 2; }
  ROOT_DESC="$DIR"
  # Pick the main HTML: prefer ./index.html, then any top-level *.html, then the first found.
  main_html=""
  for cand in "$DIR/index.html" "$DIR/public/index.html" "$DIR/dist/index.html"; do
    [[ -f "$cand" ]] && { main_html="$cand"; break; }
  done
  if [[ -z "$main_html" ]]; then
    main_html="$(find "$DIR" -maxdepth 2 -iname '*.html' -print 2>/dev/null | head -n1 || true)"
  fi
  if [[ -n "$main_html" && -f "$main_html" ]]; then
    HTML="$(cat "$main_html" 2>/dev/null || true)"
    info "analyzing HTML: ${main_html#"$DIR"/}"
  else
    warn "no .html file found under $DIR — HTML checks skipped (point --dir at the built site)"
  fi
  HEADERS=""
  # For a local dir, look for the file at the dir root (or common build subdirs).
  root_has() {
    local rel="$1" d
    for d in "$DIR" "$DIR/public" "$DIR/dist" "$DIR/static" "$DIR/.well-known"; do
      [[ -f "$d/$rel" ]] && { echo "yes"; return; }
    done
    # .well-known/security.txt special-case
    [[ "$rel" == "security.txt" && -f "$DIR/.well-known/security.txt" ]] && { echo "yes"; return; }
    echo "no"
  }
  # Foot-gun guard (#79): --dir should point at the BUILT/deployed output, not a source tree. Many
  # sites generate robots.txt / sitemap.xml / .well-known/security.txt at build time, so scanning
  # source false-negatives Crawlability *and* Security. Flag the two tell-tale source-tree shapes:
  # a package.json with a build script, or a src/ dir with no robots.txt & no sitemap at the root.
  DIR_SRC_NOTE=""
  if [[ -f "$DIR/package.json" ]] && grep -qE '"build[^"]*"[[:space:]]*:' "$DIR/package.json" 2>/dev/null; then
    DIR_SRC_NOTE="a package.json build script"
  elif [[ -d "$DIR/src" && "$(root_has robots.txt)" == "no" && "$(root_has sitemap.xml)" == "no" ]]; then
    DIR_SRC_NOTE="a src/ directory but no root robots.txt or sitemap.xml"
  fi
fi

# Whitespace-collapsed copy for the tag-presence checks (see html_has). Every run of whitespace —
# including the newlines Prettier inserts when it splits a long tag across lines — becomes a single
# space, so `<meta[^>]+name=…>` matches a multi-line tag identically to a single-line one (#67).
# Content extraction (e.g. the <title> length) still reads the raw $HTML.
HTML_FLAT="$(tr -s '[:space:]' ' ' <<<"$HTML")"

say "App / website evaluation — $ROOT_DESC"
case "$MODE" in
  url)  info "URL mode (live fetch)" ;;
  html) info "HTML mode (pre-fetched HTML${HEADERS:+ + response headers}; no origin fetch)" ;;
  dir)  info "directory mode (local files)" ;;
esac
if [[ -n "${DIR_SRC_NOTE:-}" ]]; then
  say "  NOTE: $DIR looks like a source tree ($DIR_SRC_NOTE). Point --dir at the BUILT/deployed"
  say "        output (e.g. dist/, build/, out/) instead — robots.txt, sitemap.xml and"
  say "        .well-known/security.txt are often generated at build time, so scanning source"
  say "        false-negatives Crawlability and Security."
fi

# --- Crawlability / indexing ----------------------------------------------------------
sec "Crawlability / indexing"
case "$(root_has robots.txt)" in
  yes) ok "robots.txt present" ;;
  no)  bad "robots.txt missing — add one (and point it at your sitemap)" ;;
  *)   info "robots.txt: could not determine" ;;
esac
case "$(root_has sitemap.xml)" in
  yes) ok "sitemap.xml present" ;;
  no)  warn "sitemap.xml not found at root — add one and list it in robots.txt" ;;
  *)   info "sitemap.xml: could not determine" ;;
esac
if [[ -n "$HTML" ]]; then
  if html_has '<meta[^>]+name=["'"'"']?robots["'"'"']?[^>]*noindex'; then
    warn "page has meta robots 'noindex' — intended? it will be kept out of search"
  else
    ok "no accidental meta robots noindex on the main page"
  fi
  htest '<link[^>]+rel=["'"'"']?canonical' ok "canonical link present" warn "no <link rel=canonical> — add one to avoid duplicate-URL dilution"
fi

# --- SEO ------------------------------------------------------------------------------
sec "SEO"
if [[ -n "$HTML" ]]; then
  if html_has '<title>[^<]'; then
    tlen="$(sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/Ip' <<<"$(tr -d '\n' <<<"$HTML")" | head -n1 | wc -c)"
    ok "<title> present (~$((tlen-1)) chars)"
    [[ "$tlen" -gt 70 ]] && warn "title is long (>70 chars) — search may truncate it"
  else
    bad "<title> missing — the single most important on-page SEO tag"
  fi
  htest '<meta[^>]+name=["'"'"']?description' ok "meta description present" bad "meta description missing — add ~150 chars; drives search snippet + CTR"
  htest '<h1' ok "<h1> present" warn "no <h1> — give each page one clear top heading"
  htest 'application/ld\+json' ok "structured data (JSON-LD) present" warn "no JSON-LD structured data — add schema.org for your content type"
else
  info "SEO tag checks skipped (no HTML)"
fi

# --- Social / sharing -----------------------------------------------------------------
sec "Social / sharing"
if [[ -n "$HTML" ]]; then
  htest '<meta[^>]+property=["'"'"']?og:title'      ok "og:title present"       warn "no og:title — links won't share with a rich title"
  htest '<meta[^>]+property=["'"'"']?og:description' ok "og:description present" warn "no og:description"
  htest '<meta[^>]+property=["'"'"']?og:image'       ok "og:image present"       bad  "no og:image — shared links show no preview image (big CTR loss)"
  htest '<meta[^>]+name=["'"'"']?twitter:card'       ok "twitter:card present"   warn "no twitter:card — add summary_large_image"
else
  info "social tag checks skipped (no HTML)"
fi

# --- Brand assets / standards ---------------------------------------------------------
sec "Brand assets / standards"
if [[ -n "$HTML" ]]; then
  htest '<link[^>]+rel=["'"'"']?[^"'"'"'>]*icon' ok "favicon link present"     warn "no favicon <link> — add a favicon set"
  htest 'apple-touch-icon'                        ok "apple-touch-icon present" warn "no apple-touch-icon — iOS home-screen icon"
  htest '<link[^>]+rel=["'"'"']?manifest'         ok "web app manifest linked"  info "no web app manifest (fine for simple sites; needed for installable PWAs)"
  htest '<html[^>]+lang='                         ok "html lang set"            warn "no <html lang> — hurts a11y and SEO"
  htest '<meta[^>]+name=["'"'"']?viewport'        ok "viewport meta present"    bad  "no viewport meta — not mobile-friendly"
  htest '<meta[^>]+name=["'"'"']?theme-color'      ok "theme-color set"          info "no theme-color meta — sets the browser/PWA chrome colour"
fi

# --- AI-readiness ---------------------------------------------------------------------
sec "AI-readiness"
case "$(root_has llms.txt)" in
  yes) ok "llms.txt present (LLM-friendly site map)" ;;
  no)  info "no llms.txt — an emerging convention; high-leverage for docs/dev tools" ;;
  *)   info "llms.txt: could not determine" ;;
esac
if [[ -n "$HTML" ]]; then
  # 1.3.0 (#63): don't just detect JSON-LD — parse-validate it (an invalid block is silently
  # ignored by assistants/search, worse than none) and credit RICH schema types (FAQPage/Review/…),
  # which are the actual AEO wins. Falls back to the old presence check without python3.
  if command -v python3 >/dev/null 2>&1; then
    _ld_tmp="$(mktemp)"; printf '%s' "$HTML" > "$_ld_tmp"
    _ld="$(python3 - "$_ld_tmp" <<'PY'
import json, re, sys
html = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# quotes optional: <script type=application/ld+json> is valid HTML and parsed by crawlers
blocks = re.findall(r'<script[^>]*type=["\']?application/ld\+json["\']?[^>]*>(.*?)</script>',
                    html, re.S | re.I)
ok = bad = 0
types = set()
RICH = {"FAQPage", "HowTo", "Review", "AggregateRating", "Product", "Article", "NewsArticle",
        "BreadcrumbList", "Recipe", "Event", "VideoObject", "SoftwareApplication"}
def collect(o):
    if isinstance(o, dict):
        t = o.get("@type")
        if isinstance(t, str):
            types.add(t)
        elif isinstance(t, list):
            types.update(x for x in t if isinstance(x, str))
        for v in o.values():
            collect(v)
    elif isinstance(o, list):
        for v in o:
            collect(v)
for b in blocks:
    try:
        collect(json.loads(b.strip()))
        ok += 1
    except Exception:
        bad += 1
print("%d\t%d\t%d\t%s" % (len(blocks), ok, bad, ",".join(sorted(types & RICH))))
PY
)"
    rm -f "$_ld_tmp"
    IFS=$'\t' read -r _ld_n _ld_ok _ld_bad _ld_rich <<<"$_ld"
    if [[ "${_ld_n:-0}" -eq 0 ]]; then
      info "no JSON-LD — add schema.org so assistants can parse your content"
    elif [[ "${_ld_bad:-0}" -gt 0 ]]; then
      bad "JSON-LD present but ${_ld_bad} block(s) fail to parse — invalid JSON-LD is silently ignored by assistants/search"
    else
      ok "JSON-LD parses cleanly (${_ld_ok} block(s))"
      if [[ -n "${_ld_rich:-}" ]]; then
        ok "rich schema types present (${_ld_rich}) — strong AEO signal"
      else
        info "only basic JSON-LD types — add FAQPage/Review/Article/HowTo where they fit for AEO"
      fi
    fi
  else
    htest 'application/ld\+json' ok "machine-readable JSON-LD present (good for AI extraction)" info "no JSON-LD — add schema.org so assistants can parse your content"
  fi
fi

# --- Security / hygiene ---------------------------------------------------------------
sec "Security / hygiene"
# Live transport checks need the origin: HTTPS (URL mode) and response headers (URL mode, or
# --html paired with --headers). A static host can't set HTTP headers, so we ALSO score the
# *source-visible* controls a static site can ship — a <meta> CSP, its third-party <script>
# posture, a shipped security.txt — so Security isn't a blanket n/a in --dir / --html mode (#79).
if [[ "$MODE" == url ]]; then
  if [[ "$URL" == https://* ]]; then ok "served over HTTPS"; else bad "not HTTPS — serve over TLS and redirect http→https"; fi
fi
if [[ -n "$HEADERS" ]]; then
  hdr '^strict-transport-security:' "HSTS header set" warn "no Strict-Transport-Security header"
  hdr '^content-security-policy:'   "Content-Security-Policy header set" warn "no Content-Security-Policy response header (a <meta> CSP is a weaker fallback)"
  hdr '^x-content-type-options:'    "X-Content-Type-Options set" warn "no X-Content-Type-Options: nosniff"
  hdr '^referrer-policy:'           "Referrer-Policy set" info "no Referrer-Policy header"
elif [[ "$MODE" == html ]]; then
  info "no response headers captured — pass --headers <file|-> alongside --html to score HSTS/CSP/nosniff"
fi
# Source-visible controls — checkable from the HTML/build alone, so they score in every mode.
if [[ -n "$HTML" ]]; then
  # A <meta http-equiv="Content-Security-Policy"> is a real (if weaker) CSP a static host CAN ship.
  # Only credit/flag it when there's no response-header CSP (which is the stronger mechanism).
  _has_hdr_csp=""
  [[ -n "$HEADERS" ]] && grep -qi '^content-security-policy:' <<<"$HEADERS" && _has_hdr_csp=1
  if [[ -z "$_has_hdr_csp" ]]; then
    htest '<meta[^>]+http-equiv=["'"'"']?content-security-policy' \
      ok "CSP declared via <meta http-equiv> (source-visible; a response header is stronger)" \
      info "no Content-Security-Policy (no response-header CSP and no <meta http-equiv> CSP)"
  fi
  # Third-party <script src> origins widen the supply-chain/exfil surface. Absolute-URL scripts only
  # (relative srcs are same-origin); exclude the site's own host in URL mode. Zero third-party
  # origins is a genuine, source-visible security posture a static site earns.
  _script_tags="$(grep -oiE '<script[^>]*>' <<<"$HTML_FLAT" || true)"
  if grep -qiE 'src=' <<<"$_script_tags"; then
    # Lowercase first (so the src= strip and host compare need no case-insensitive sed 'I' flag,
    # which isn't portable to BSD sed), then peel to the bare host[:port].
    _ext_hosts="$(grep -oiE 'src=["'"'"']?(https?:)?//[^"'"'"' >]+' <<<"$_script_tags" \
                  | tr '[:upper:]' '[:lower:]' \
                  | sed -E 's#^src=["'"'"']?##; s#^https?:##; s#^//##; s#[/?#].*$##' \
                  | grep -v '^$' | sort -u || true)"
    if [[ "$MODE" == url ]]; then
      _own_host="$(sed -E 's#^https?://##; s#[/?#].*$##' <<<"$URL" | tr '[:upper:]' '[:lower:]')"
      [[ -n "$_own_host" && -n "$_ext_hosts" ]] && _ext_hosts="$(grep -vixF "$_own_host" <<<"$_ext_hosts" || true)"
    fi
    _ext_hosts="$(grep -v '^$' <<<"$_ext_hosts" || true)"
    if [[ -z "$_ext_hosts" ]]; then
      ok "no third-party <script> origins (scripts are same-origin/relative) — minimal supply-chain surface"
    else
      _nhosts="$(grep -c . <<<"$_ext_hosts")"
      _hlist="$(tr '\n' ' ' <<<"$_ext_hosts" | sed 's/ *$//; s/ /, /g')"
      warn "$_nhosts third-party <script> origin(s) ($_hlist) — each adds supply-chain/exfil surface; pin with SRI"
    fi
  fi
fi
# security.txt — a machine-readable security contact (RFC 9116). root_has finds it in --dir mode
# (./.well-known/), probes it live in --url mode, and is "unknown" in --html mode.
case "$(root_has .well-known/security.txt)" in
  yes) ok "security.txt present (a contact for security reports)" ;;
  no)  info "no /.well-known/security.txt (add a security contact — RFC 9116)" ;;
  *)   info "security.txt: could not determine (need --url or --dir)" ;;
esac

# --- Performance hints (heuristic) ----------------------------------------------------
sec "Performance / load (hints)"
if [[ -n "$HTML" ]]; then
  if html_has '<img[^>]+loading=["'"'"']?lazy'; then ok "uses loading=\"lazy\" on images"; else info "no lazy-loaded images found — add loading=\"lazy\" below the fold"; fi
  # Render-blocking = an external <script src> that is NOT async/defer AND NOT type="module".
  # Module scripts defer by spec (Vite emits `<script type="module" src=…>`), so flagging them was a
  # false positive (#67). Enumerate each opening <script …> tag and classify per-tag, so a page that
  # mixes a blocking classic script with deferred modules is judged on the classic one.
  _scripts="$(grep -oiE '<script[^>]*>' <<<"$HTML_FLAT" || true)"
  if [[ -z "$_scripts" ]] || ! grep -qiE 'src=' <<<"$_scripts"; then
    info "no external <script> tags (nothing render-blocking here)"
  else
    # keep only external scripts (src=), then drop the genuinely deferred ones. Match async/defer and
    # type="module" only as real *attributes* — a token led by whitespace and closed by whitespace,
    # `/`, `>`, or `=` — NOT the same letters sitting inside a src URL (e.g. `/js/defer.min.js` or
    # `/async/app.js`) or a data-* attribute, which would otherwise hide a real render-blocking script.
    _blocking="$(grep -iE 'src=' <<<"$_scripts" \
                 | grep -ivE '[[:space:]](async|defer)([[:space:]/>=]|$)' \
                 | grep -ivE '[[:space:]]type=["'"'"']?module' || true)"
    if [[ -z "$_blocking" ]]; then
      ok "external scripts are deferred (async/defer or type=\"module\") — non-blocking"
    else
      _nblk="$(grep -c . <<<"$_blocking")"
      warn "$_nblk render-blocking external <script> (no async/defer/module) — slows first paint"
    fi
  fi
  info "for real numbers (LCP/CLS/INP, payload size) run Lighthouse/PageSpeed on the live URL"
else
  info "performance hints skipped (no HTML)"
fi

# --- Scorecard ------------------------------------------------------------------------
# Per-dimension score = 100*(pass + 0.5*warn)/(scored checks); overall = weighted average.
printf '\n\033[1mScorecard\033[0m\n' >&"$RFD"
printf '  %-27s %6s  %5s  %s\n' "dimension" "weight" "score" "grade" >&"$RFD"
declare -a OUT_SCORE OUT_GRADE OUT_WEIGHT UNSCORED
tot_w=0; tot_ws=0; all_w=0
for i in "${!SEC_NAME[@]}"; do
  sp=${SEC_P[i]}; sw=${SEC_W[i]}; sf=${SEC_F[i]}
  scored=$(( sp + sw + sf ))
  wt=$(weight_for "${SEC_NAME[i]}")
  OUT_WEIGHT+=("$wt")
  all_w=$(( all_w + wt ))
  if [[ "$scored" -gt 0 ]]; then
    den=$(( 2 * scored ))
    score=$(( (200 * sp + 100 * sw + den / 2) / den ))   # rounded 100*(p+0.5w)/scored
    g=$(grade_for "$score")
    printf '  %-27s %5s%%  %4s    %s\n' "${SEC_NAME[i]}" "$wt" "$score" "$g" >&"$RFD"
    tot_w=$(( tot_w + wt )); tot_ws=$(( tot_ws + score * wt ))
    OUT_SCORE+=("$score"); OUT_GRADE+=("$g")
  else
    printf '  %-27s %5s%%  %4s    %s\n' "${SEC_NAME[i]}" "$wt" "n/a" "-" >&"$RFD"
    OUT_SCORE+=("null"); OUT_GRADE+=("-")
    UNSCORED+=("${SEC_NAME[i]}")
  fi
done
if [[ "$tot_w" -gt 0 ]]; then overall=$(( (tot_ws + tot_w / 2) / tot_w )); else overall=0; fi
ograde=$(grade_for "$overall")
# 1.3.0 (#63): a dir-mode "A" was computed over only ~82% of weight (Security n/a) but the
# headline read like a full-coverage grade. Star the grade and say what wasn't assessed.
STAR=""
COVERAGE=100
if [[ ${#UNSCORED[@]} -gt 0 && "$all_w" -gt 0 ]]; then
  STAR="*"
  COVERAGE=$(( (100 * tot_w + all_w / 2) / all_w ))
fi
printf '  %s\n' "-------------------------------------------------" >&"$RFD"
printf '  %-27s %6s  %4s    \033[1m%s%s\033[0m\n' "Overall (weighted)" "" "$overall" "$ograde" "$STAR" >&"$RFD"
if [[ -n "$STAR" ]]; then
  printf '  * computed over %d%% of weight; unscored: %s\n' "$COVERAGE" "$(printf '%s; ' "${UNSCORED[@]}" | sed 's/; $//')" >&"$RFD"
  if [[ "$MODE" != url ]]; then
    printf '    (no live signals here — source-visible Security is scored, but HTTPS/response-header checks and\n' >&"$RFD"
    printf '     real perf numbers need the origin: run --url from a network-enabled shell, feed --html --headers, or Lighthouse)\n' >&"$RFD"
  fi
fi
printf '\n\033[1mChecklist:\033[0m %d pass, %d warn, %d fail — overall %d/100 (%s%s). Weight by the\n' "$P" "$W" "$F" "$overall" "$ograde" "$STAR" >&"$RFD"
printf 'site type/community, then turn the dimension grades into a prioritized report (reference.md).\n' >&"$RFD"

# --- JSON (machine-readable) ----------------------------------------------------------
if [[ -n "$JSON" ]]; then
  REC="$REC" GP="$P" GW="$W" GF="$F" OVERALL="$overall" OGRADE="$ograde" \
  COVERAGE="$COVERAGE" UNSCORED_NAMES="$(printf '%s\n' "${UNSCORED[@]:-}")" \
  TARGET="$ROOT_DESC" MODE="$MODE" \
  NAMES="$(printf '%s\n' "${SEC_NAME[@]:-}")" \
  SCORES="$(printf '%s\n' "${OUT_SCORE[@]:-}")" \
  GRADES="$(printf '%s\n' "${OUT_GRADE[@]:-}")" \
  WEIGHTS="$(printf '%s\n' "${OUT_WEIGHT[@]:-}")" \
  python3 <<'PY' 2>/dev/null || echo '{"error":"--json needs python3"}'
import json, os
def lines(k):
    v = os.environ.get(k, "")
    return v.split("\n")[:-1] if v.endswith("\n") else ([x for x in v.split("\n") if x != ""] if v else [])
names = [n for n in os.environ.get("NAMES","").split("\n") if n != ""]
scores = os.environ.get("SCORES","").split("\n")
grades = os.environ.get("GRADES","").split("\n")
weights = os.environ.get("WEIGHTS","").split("\n")
# per-section checks from the records file (section_index \t status \t message)
checks = {}
rec = os.environ.get("REC","")
if rec and os.path.exists(rec):
    for ln in open(rec):
        parts = ln.rstrip("\n").split("\t", 2)
        if len(parts) == 3:
            checks.setdefault(parts[0], []).append({"status": parts[1], "message": parts[2]})
dims = []
for idx, name in enumerate(names):
    sc = scores[idx] if idx < len(scores) else "null"
    dims.append({
        "name": name,
        "weight": int(weights[idx]) if idx < len(weights) and weights[idx] else None,
        "score": (None if sc == "null" else int(sc)),
        "grade": grades[idx] if idx < len(grades) else "-",
        "checks": checks.get(str(idx), []),
    })
obj = {
    "target": os.environ.get("TARGET",""),
    "mode": os.environ.get("MODE",""),
    "overall": {"score": int(os.environ.get("OVERALL","0")), "grade": os.environ.get("OGRADE",""),
                "coverage_weight_pct": int(os.environ.get("COVERAGE","100")),
                "unscored": [n for n in os.environ.get("UNSCORED_NAMES","").split("\n") if n]},
    "tally": {"pass": int(os.environ.get("GP","0")), "warn": int(os.environ.get("GW","0")), "fail": int(os.environ.get("GF","0"))},
    "dimensions": dims,
}
print(json.dumps(obj, indent=2))
PY
  [[ -n "$REC" ]] && rm -f "$REC"
fi
exit 0
