---
name: app-evaluation
description: Evaluate an app or website and produce a prioritized, evidence-backed report — SEO and crawlability, AI-readiness, social/sharing assets, security and standards, performance/load-time, accessibility, and growth (which communities to join or submit to, PR/advertising wins). Use when the user asks to audit/review/evaluate/grade a website or app, improve its SEO/reach/discoverability, get it ready to launch or submit, or asks "how good is my site and what should I fix?"
---

# App / Website Evaluation

Audit an app or website and hand back a **prioritized, evidence-backed** report: what's good,
what's missing, and the highest-impact fixes — ranked by impact × effort, each tied to concrete
evidence (a missing tag, a failing header, an absent file), never vague advice.

**Be self-referential.** There is no universal "good site." Judge each property against what's
best **for its type and its community**: a marketing site, a SaaS app, a docs site, a blog, an
open-source project, an e-commerce store, a portfolio, an API, or a mobile-app landing page each
have different priorities, standards, and growth channels. So **classify first**, then evaluate
against that class's norms. Apply the same lens to your own recommendations — the *best* PR and
software-design move for a niche dev tool is not the same as for a consumer app.

## 1. Classify the target (do this first)

Determine, from the URL/repo/screens and by asking if unclear:
- **Type** (marketing / SaaS / docs / blog / OSS project / e-commerce / portfolio / API / app
  landing) and **primary goal** (signups, sales, stars, leads, reads, installs).
- **Audience & community** (developers, designers, consumers, a specific niche) — this drives
  which channels, tone, and standards matter.
- **Stage** (pre-launch, launched, scaling) and **stack** (static, SSR, SPA, CMS) — a SPA has
  different crawlability/perf concerns than a static site.

Everything below is weighted by these answers. State the classification at the top of the report.

## 2. Gather evidence

Run the bundled checker, then read the source if you have it:

```
${CLAUDE_PLUGIN_ROOT}/skills/app-evaluation/scripts/evaluate-site.sh --url https://example.com
# or, for a local build / repo you can read:
${CLAUDE_PLUGIN_ROOT}/skills/app-evaluation/scripts/evaluate-site.sh --dir ./dist
```

It prints a PASS/WARN/FAIL/INFO checklist over crawlability, SEO, social, assets, AI-readiness,
security (URL mode), and performance hints, then a **standardized Scorecard**: each dimension scores
**0–100** (PASS=1, WARN=0.5, FAIL=0; INFO unscored) with a **letter grade** (A ≥90, B ≥80, C ≥70,
D ≥60, F <60), and a **weight-averaged overall** grade. Add **`--json`** for a machine-readable
scorecard (stdout; human report → stderr). It needs `curl` for `--url` (degrades to base checks if
absent) and only `grep`/`sed`/`python3` for `--dir`. Don't stop at the script: read `robots.txt`,
the sitemap, the page `<head>`, and (if available) the repo — the score is the evidence base, your
judgment (weighted by type/community) is the report.

## 3. Evaluate across dimensions

Start from the script's **per-dimension letter grade + score**, then adjust with judgment and the
evidence you read (the script is heuristic; a JS-rendered SPA can hide content from a fetch, so a
weak score may be a false negative — note it). Full checklists, the community directory, and the
scoring rubric are in **`reference.md`** — the dimensions:

| Dimension | Look for (see reference.md for the full list) |
| :-- | :-- |
| **Crawlability / indexing** | `robots.txt`, XML `sitemap`, canonical URLs, no accidental `noindex`, clean URLs, SPA pre-render/SSR |
| **SEO** | unique `<title>` + meta description, heading hierarchy, semantic HTML, structured data (JSON-LD), internal links, image `alt` |
| **AI-readiness** | `llms.txt`, machine-readable data (JSON-LD/schema.org), semantic markup, clean content extraction, an API or feed where it fits |
| **Social / sharing** | Open Graph (`og:title/description/image`), Twitter card, a share image that renders, canonical social handles linked |
| **Brand assets / standards** | favicon set + `apple-touch-icon`, logo (incl. SVG), a clear **tagline**, consistent naming, `manifest.webmanifest`, 404 page |
| **Security / hygiene** | HTTPS + HSTS, security headers (CSP, X-Content-Type-Options, Referrer-Policy), no secrets/source maps leaked, deps current, `security.txt` |
| **Performance / load** | payload size, render-blocking JS/CSS, image format/sizing (AVIF/WebP, dimensions), caching/CDN, lazy-loading, Core Web Vitals |
| **Accessibility** | `lang`, `viewport`, contrast, labels/alt, focus order, keyboard nav (a11y is also SEO + reach) |
| **Growth / community / PR** | analytics present, where this *type* is discovered, communities to join or submit to, easy PR/advertising wins (see reference.md) |

## 4. Report — standardized format (consistent every time)

Lead with the scorecard, then prioritize. Use this exact order so reports are comparable run-to-run:

1. **Classification** (type, audience, goal) in one line, so every recommendation is anchored.
2. **Scorecard** — the **overall grade + score**, then the per-dimension grades (reuse the script's
   table; re-grade a dimension only when you have evidence the heuristic was wrong, and say why).
3. **Top fixes**, ranked by **impact × effort** — lead with high-impact/low-effort (e.g. "add a
   `meta description` and an `og:image`: 10 min, big SEO + share-CTR win"). Each cites evidence.
4. **By dimension**, the per-dimension grade + the specifics behind it (what passed / what to fix).
5. **Growth plan** for *this* type & community: concrete places to submit/join (Product Hunt, HN,
   relevant subreddits/Discords, dev.to, Indie Hackers, awesome-lists, app stores, directories —
   pick by type; reference.md has the directory), plus PR/advertising wins that suit the audience.
6. **What's already good** — affirm it; don't only list problems.

Be honest about confidence and limits: a black-box URL scan can't see the codebase, server config,
or analytics; say what you'd need (repo access, the build dir, the CMS) to go deeper. Verify claims
against real output — don't assert a tag is missing without checking, and prefer fixing root causes
(a layout/template) over per-page patches.

See `reference.md` for the full per-dimension checklists, the by-type community/submission
directory, the AI-readiness and `llms.txt` guidance, and the impact×effort scoring rubric.
