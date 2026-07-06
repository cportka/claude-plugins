# App / Website Evaluation — Reference

Detailed checklists, the by-type community/submission directory, AI-readiness notes, and the
scoring rubric for the `app-evaluation` skill. Weight everything by the target's **type and
community** (see SKILL.md §1) — these are defaults, not a one-size checklist.

## Per-dimension checklists

### Crawlability / indexing
- `robots.txt` present, not accidentally `Disallow: /`; references the sitemap.
- XML **sitemap** present, listed in robots.txt and Search Console; URLs canonical and 200.
- One **canonical** URL per page (`<link rel="canonical">`); no duplicate http/https/www variants.
- No accidental `<meta name="robots" content="noindex">` on pages meant to rank.
- **SPA/JS sites:** content must be server-rendered or pre-rendered, or crawlers/LLMs see an empty
  shell. Confirm the *rendered* HTML contains the content (view source, not just devtools).
- Clean, stable, human-readable URLs; 301 (not 302) for permanent moves; a real 404.

### SEO
- Unique, descriptive `<title>` (~50–60 chars) and `meta description` (~150–160) per page.
- One `<h1>`; logical heading hierarchy; semantic landmarks (`<header>/<nav>/<main>/<footer>`).
- **Structured data** (JSON-LD schema.org) appropriate to type: `Organization`/`WebSite`,
  `Article`/`BlogPosting`, `Product`+`Offer`, `SoftwareApplication`, `BreadcrumbList`, `FAQPage`.
- Descriptive image `alt`; internal linking; readable content (not all in images/canvas).
- `hreflang` if multilingual.

### AI-readiness (increasingly its own discoverability channel)
- **`llms.txt`** at the root (emerging convention) — a plain-text map of the site's key pages/docs
  for LLMs; and/or `llms-full.txt` with the content. High-leverage for docs/dev tools.
- Machine-readable data: **JSON-LD**, RSS/Atom feed, a public API or OpenAPI spec where it fits.
- Semantic HTML + clean text extraction (content not locked behind JS) so assistants can quote it.
- Don't block legitimate AI crawlers in `robots.txt` unless that's a deliberate choice; decide
  consciously (GPTBot, ClaudeBot, Google-Extended, PerplexityBot).

### Social / sharing
- Open Graph: `og:title`, `og:description`, `og:image` (≈1200×630, absolute URL, <5MB), `og:url`,
  `og:type`. Twitter: `twitter:card` (`summary_large_image`), title/description/image.
- The share image actually renders (test in a debugger); fallbacks per key page.
- Canonical **social handles** linked from the site, and the site linked from the profiles.

### Brand assets / standards
- Full **favicon** set + `apple-touch-icon` + `manifest.webmanifest` (name, theme color, icons).
- A **logo** (incl. an SVG and a dark/light variant) and a clear, memorable **tagline** above the
  fold that states what it is and who it's for.
- A `<meta name="theme-color">` for browser/PWA chrome; a social share image (`og:image`).
- Consistent product naming/capitalization; a branded, helpful **404**; print/OG variants of the logo.

### Security / hygiene
- HTTPS everywhere + HSTS; HTTP → HTTPS redirect.
- Headers: `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`,
  `X-Frame-Options`/frame-ancestors, `Permissions-Policy`.
- No leaked secrets, `.env`, `.git/`, source maps, or stack traces in production.
- Dependencies current (no known CVEs); a `/.well-known/security.txt` for contact.
- Cookie consent / privacy policy where required; forms validated server-side.
- **Source-visible controls (scored off the network too).** Live HTTP headers + HTTPS need `--url`
  (or `--html --headers`), but a static host can't set headers and instead ships controls visible in
  the build — the script credits these in `--dir` / `--html` mode so Security isn't a blanket `n/a`:
  a `<meta http-equiv="Content-Security-Policy">` (a header CSP still wins when present), a shipped
  `/.well-known/security.txt`, and its **third-party `<script>` posture** — zero off-origin script
  origins (everything same-origin/relative) is credited as minimal supply-chain surface; off-origin
  origins are listed with a "pin with Subresource Integrity" nudge. A dependency-free static runtime
  scores well here even with no server headers.

### Performance / load
- Total transfer and request count reasonable for type; a CDN for static assets.
- Images in AVIF/WebP, correctly sized, with width/height and `loading="lazy"` below the fold.
- Defer/async non-critical JS; minify/compress (gzip/brotli); avoid render-blocking CSS.
- Cache headers/immutable hashed assets; preconnect/preload critical resources.
- Check **Core Web Vitals** (LCP, CLS, INP); a slow first load hurts SEO, reach, and conversion.

### Accessibility (also reach + SEO)
- `<html lang>`, responsive `viewport`, sufficient contrast, labels for inputs, `alt` for images,
  visible focus, keyboard operability, ARIA only where needed, reduced-motion respected.

## By-type community / submission directory

Pick channels by **type and audience** — submitting a B2B SaaS to a gaming subreddit wastes the shot.

- **Dev tool / library / OSS:** GitHub topics + a strong README, Hacker News (Show HN), relevant
  subreddits (e.g. r/programming, r/<language>), dev.to / Hashnode, Lobsters, awesome-lists PRs,
  language package registries, Discord/Slack communities for the ecosystem, a launch on Product Hunt.
- **SaaS / startup:** Product Hunt, Indie Hackers, BetaList, relevant subreddits, LinkedIn, niche
  newsletters, G2/Capterra listings, founder communities (e.g. WIP, MegaMaker).
- **Consumer app:** App Store / Play Store ASO, Product Hunt, TikTok/Reddit/Discord where the
  audience is, influencer/press outreach, app-review sites.
- **Content / blog / media:** RSS, newsletter, SEO topical clusters, syndication (Medium/dev.to
  canonical), relevant aggregators and subreddits, social repurposing.
- **E-commerce:** Google Merchant Center + Shopping, Pinterest, Instagram/TikTok shopping,
  marketplaces, reviews/UGC, comparison/deal sites.
- **Portfolio / personal:** designer/dev communities (Awwwards, Bēhance, Dribbble, Read.cv),
  personal newsletter, conference/CFP talks.

**Easy PR / advertising wins (tailor to audience):** a clear one-line pitch + press kit (logos,
screenshots, founder bio); a launch-day plan (PH/HN/newsletter aligned); helpful content that
ranks (comparison pages, guides) instead of pure ads; testimonials/social proof above the fold;
a referral/share loop; getting listed in the obvious directories for the category; partnering with
adjacent tools; lightweight retargeting only once the funnel converts. Spend where the audience
already is, not everywhere.

## Scoring system — the standardized scorecard

`evaluate-site.sh` produces a consistent, comparable scorecard so "how good is my site?" has a
repeatable answer. Each check is **PASS (1.0) / WARN (0.5) / FAIL (0.0)**; **INFO** is not scored.

- **Dimension score** = `100 × (pass + 0.5·warn) / (scored checks)`, as a **letter grade**:
  **A ≥ 90, B ≥ 80, C ≥ 70, D ≥ 60, F < 60**. A dimension with no scored checks shows `n/a`.
- **Overall** = the **weight-averaged** dimension score. Default weights (sum 100):
  SEO 20 · Security/hygiene 18 · Crawlability 15 · Brand assets 13 · Social 12 · Performance 12 ·
  AI-readiness 10.
- **Coverage-honest star.** When a dimension can't be assessed it shows `n/a` and is **excluded** from
  the overall, which is then **starred** (`B*`) with the % of weight it was computed over and the
  unscored dimensions named — so a partial-coverage grade never reads like a full one. Live-only
  signals need the origin: `--url` (or `--html --headers`) scores HTTPS + response headers and richer
  Performance; `--dir` / `--html` still score **source-visible Security** (a `<meta>` CSP,
  `security.txt`, third-party-script posture) — only the live transport checks and real perf numbers
  are left `n/a` off the network.
- **Input source.** One of `--url` (live), `--dir` (a local **built/deployed** tree — not `src/`; the
  tool warns if it looks like source), or `--html <file|->` (pre-fetched HTML for sandboxes whose
  egress proxy blocks `--url`), optionally with `--headers <file|->` to score the live security
  headers without curl.
- **`--json`** emits the same scorecard machine-readably (overall + `coverage_weight_pct` + `mode` +
  per-dimension score/grade + every check) for diffing runs or wiring into CI.

The grade is the **shape at a glance**; the *report* is still judgment. Re-grade a dimension only
with evidence the heuristic was wrong (e.g. a JS-rendered SPA hid content from the fetch), and say
so. Weight the grades by the target's **type and community** — a C on Social may not matter for an
internal API, while a C on Security is urgent for a store.

### Then prioritize fixes by impact × effort

- **Impact:** how much it moves the primary goal (signups/sales/stars/reads/installs).
- **Effort:** rough time/complexity to ship.

Lead with **high-impact / low-effort** (the meta description, `og:image`, `robots.txt`+sitemap,
HTTPS/headers, a tagline) — minutes of work for outsized SEO/share/trust gains. Then high-impact /
higher-effort (perf overhaul, SSR for a SPA, a content/SEO program). Note but de-prioritize
low-impact items. Give each a one-line "why it matters **for this type**."

## Limits & honesty
A URL scan is a black box: it can't see server config, the codebase, analytics, or conversion
data, and a JS-heavy site may hide content from a simple fetch. State what you checked, what you
inferred, and what you'd need (repo, build dir, CMS, analytics access) to go deeper — and verify
each finding against real output before reporting it.
