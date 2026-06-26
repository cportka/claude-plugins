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
#   evaluate-site.sh --url <url> --dry-run     # print what it would fetch, no network
#
# Options:
#   --url <url>    Evaluate a live site (fetches the page, headers, robots.txt, sitemap, llms.txt).
#   --dir <path>   Evaluate a local directory (an index.html / built site, or a repo).
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
DRY_RUN=""
JSON=""

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --dir) DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if [[ -z "$URL" && -z "$DIR" ]]; then
  echo "Error: pass --url <url> or --dir <path>. See --help." >&2
  exit 2
fi
if [[ -n "$URL" && -n "$DIR" ]]; then
  echo "Error: use one of --url or --dir, not both." >&2
  exit 2
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

# Case-insensitive "does the page HTML contain this regex?"  (best-effort; $HTML is the page)
html_has() { grep -qiE "$1" <<<"$HTML"; }

# htest <regex> <good-fn> <good-msg> <bad-fn> <bad-msg> — dispatch on whether the HTML matches.
# (Avoids the `A && B || C` pattern, which isn't if-then-else.)
htest() { if html_has "$1"; then "$2" "$3"; else "$4" "$5"; fi; }
# hdr <header-regex> <good-msg> <bad-fn> <bad-msg> — dispatch on a response header (URL mode).
hdr()   { if grep -qi "$1" <<<"$HEADERS"; then ok "$2"; else "$3" "$4"; fi; }

if [[ -n "$DRY_RUN" ]]; then
  if [[ -n "$URL" ]]; then
    echo "Dry run — would fetch (no network performed):"
    echo "  curl -fsSL $URL                 # page HTML"
    echo "  curl -sSI  $URL                 # response headers (HTTPS, security)"
    echo "  curl -fsS  ${URL%/}/robots.txt"
    echo "  curl -fsS  ${URL%/}/sitemap.xml"
    echo "  curl -fsS  ${URL%/}/llms.txt"
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
fi

say "App / website evaluation — $ROOT_DESC"
if [[ -n "$URL" ]]; then info "URL mode (live fetch)"; else info "directory mode (local files)"; fi

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
  htest 'application/ld\+json' ok "machine-readable JSON-LD present (good for AI extraction)" info "no JSON-LD — add schema.org so assistants can parse your content"
fi

# --- Security (URL mode) --------------------------------------------------------------
sec "Security / hygiene"
if [[ -n "$URL" ]]; then
  if [[ "$URL" == https://* ]]; then ok "served over HTTPS"; else bad "not HTTPS — serve over TLS and redirect http→https"; fi
  if [[ -n "$HEADERS" ]]; then
    hdr '^strict-transport-security:' "HSTS header set" warn "no Strict-Transport-Security header"
    hdr '^content-security-policy:'   "Content-Security-Policy set" warn "no Content-Security-Policy header"
    hdr '^x-content-type-options:'    "X-Content-Type-Options set" warn "no X-Content-Type-Options: nosniff"
    hdr '^referrer-policy:'           "Referrer-Policy set" info "no Referrer-Policy header"
  else
    info "no response headers captured — security-header checks skipped"
  fi
  case "$(root_has .well-known/security.txt)" in
    yes) ok "security.txt present" ;;
    *)   info "no /.well-known/security.txt (a contact for security reports)" ;;
  esac
else
  info "security/header checks need --url (live HTTPS + headers can't be read from a directory)"
fi

# --- Performance hints (heuristic) ----------------------------------------------------
sec "Performance / load (hints)"
if [[ -n "$HTML" ]]; then
  if html_has '<img[^>]+loading=["'"'"']?lazy'; then ok "uses loading=\"lazy\" on images"; else info "no lazy-loaded images found — add loading=\"lazy\" below the fold"; fi
  # Only external <script src=…> is render-blocking; inline / JSON-LD scripts aren't, and a page
  # with no scripts at all has nothing to flag.
  if html_has '<script[^>]+src='; then
    if html_has '<script[^>]+\b(async|defer)\b'; then ok "external scripts use async/defer"; else warn "external <script> without async/defer — render-blocking JS slows first paint"; fi
  else
    info "no external <script> tags (nothing render-blocking here)"
  fi
  info "for real numbers (LCP/CLS/INP, payload size) run Lighthouse/PageSpeed on the live URL"
else
  info "performance hints skipped (no HTML)"
fi

# --- Scorecard ------------------------------------------------------------------------
# Per-dimension score = 100*(pass + 0.5*warn)/(scored checks); overall = weighted average.
printf '\n\033[1mScorecard\033[0m\n' >&"$RFD"
printf '  %-27s %6s  %5s  %s\n' "dimension" "weight" "score" "grade" >&"$RFD"
declare -a OUT_SCORE OUT_GRADE OUT_WEIGHT
tot_w=0; tot_ws=0
for i in "${!SEC_NAME[@]}"; do
  sp=${SEC_P[i]}; sw=${SEC_W[i]}; sf=${SEC_F[i]}
  scored=$(( sp + sw + sf ))
  wt=$(weight_for "${SEC_NAME[i]}")
  OUT_WEIGHT+=("$wt")
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
  fi
done
if [[ "$tot_w" -gt 0 ]]; then overall=$(( (tot_ws + tot_w / 2) / tot_w )); else overall=0; fi
ograde=$(grade_for "$overall")
printf '  %s\n' "-------------------------------------------------" >&"$RFD"
printf '  %-27s %6s  %4s    \033[1m%s\033[0m\n' "Overall (weighted)" "" "$overall" "$ograde" >&"$RFD"
printf '\n\033[1mChecklist:\033[0m %d pass, %d warn, %d fail — overall %d/100 (%s). Weight by the\n' "$P" "$W" "$F" "$overall" "$ograde" >&"$RFD"
printf 'site type/community, then turn the dimension grades into a prioritized report (reference.md).\n' >&"$RFD"

# --- JSON (machine-readable) ----------------------------------------------------------
if [[ -n "$JSON" ]]; then
  REC="$REC" GP="$P" GW="$W" GF="$F" OVERALL="$overall" OGRADE="$ograde" \
  TARGET="$ROOT_DESC" MODE="$([[ -n "$URL" ]] && echo url || echo dir)" \
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
    "overall": {"score": int(os.environ.get("OVERALL","0")), "grade": os.environ.get("OGRADE","")},
    "tally": {"pass": int(os.environ.get("GP","0")), "warn": int(os.environ.get("GW","0")), "fail": int(os.environ.get("GF","0"))},
    "dimensions": dims,
}
print(json.dumps(obj, indent=2))
PY
  [[ -n "$REC" ]] && rm -f "$REC"
fi
exit 0
