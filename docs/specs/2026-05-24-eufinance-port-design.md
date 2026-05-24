# eufinance port — design

**Date:** 2026-05-24
**Repo:** `euverse`
**Phase:** First tracker port (validates the shared-infra phase end-to-end).

## 1. Context & goal

Port the existing standalone `eufinancestats.Rmd` (now archived at
`old/eufinancestats.Rmd`) into a tracker page on the new shared infra. This
is the first of four tracker ports planned per
`docs/specs/2026-05-23-shared-infra-design.md`. Chosen first because it's
the smallest (13 KB Rmd) and exercises the riskier API-driven pipeline
(fetchers → snapshots → freshness badge → graceful degradation) without
the heavier eurlex SPARQL machinery the other three need.

The port serves two simultaneous goals:

1. **Reproduce the existing eufinance tracker's content** under the new
   theme and infrastructure (zephyr+darkly, Inter, Okabe-Ito, shared
   `theme_mo`/`freshness_badge`, ggiraph defaults).
2. **Validate the shared-infra design** end-to-end with real data,
   surfacing any gaps before the heavier eurlex ports.

Owner-stated principles this phase reinforces (from the migration message
and prior brainstorming):

- API responses are stored once per source and **reused across pages** —
  fetchers are per-upstream-dataset, snapshots are source-named (not
  page-named).
- **Don't unnecessarily query APIs** — local dev iterates against
  on-disk snapshots; only CI's nightly cron and manual fetcher invocation
  cause network traffic.

## 2. Decisions (recap of brainstorming)

| Decision | Choice | Alternatives considered |
|---|---|---|
| Fetcher granularity | **Per upstream dataset** (4 fetchers for eufinance) | Per source (2 fetchers, multi-output); per page (1 fetcher) |
| Snapshot naming | `<source>_<dataset>_latest.{parquet,meta.json}` | `<page>_<topic>`; hierarchical via folder |
| Snapshot shape | **Tidy** (cleaned at fetch time; named cols) | Raw upstream columns + separate parse step |
| Local dev re-query | **Manual** (fetcher only runs when invoked) | Smart fetcher (skip-if-recent); wrapper helper |
| Page scope | Port the 3 old sections as-is on new theme | Port subset; port + add tables; restructure |
| Freshness badge | **One combined** per page (oldest of N metas) | Per-section badges |
| Initial snapshots | **Committed alongside the fetchers** | Rely on first CI cron run |
| Commit granularity | **One commit** for the whole port | Split data layer + page commits |
| Bundled vs JIT renv adds | **Bundled now** (5 packages in one snapshot) | Add as each tracker needs them |
| Domain helper layer (`R/yields.R`) | **No — keep plotting page-local** until 2nd consumer | Extract reusable plot helpers up front |

## 3. Architecture

### 3.1 Data layer — 4 fetchers, 4 snapshots

Each fetcher is a self-contained `R/fetch_<src>.R` script that follows the
`R/_fetch_template.R` contract: fetch → tidy → validate → atomic write.

| File | Upstream | Output (tidy schema) |
|---|---|---|
| `R/fetch_ecb_yield_curve.R` | ECB API, 3 SDMX series `YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_{1,5,10}Y` | `data-apis/ecb_yield_curve_latest.parquet` with columns `date (Date), maturity_years (int: 1/5/10), yield_pct (double)` |
| `R/fetch_eurostat_teimf050.R` | `eurostat::get_eurostat("teimf050")` | `data-apis/eurostat_teimf050_latest.parquet` with `date (Date, monthly), geo (chr), country_name (chr), yield_pct (double)` |
| `R/fetch_ecb_mrr.R` | ECB API, `FM/B.U2.EUR.4F.KR.MRR_FR.LEV` | `data-apis/ecb_mrr_latest.parquet` with `date (Date), rate_pct (double)` |
| `R/fetch_ecb_hicp.R` | ECB API, `ICP/M.U2.N.000000.4.ANR` | `data-apis/ecb_hicp_latest.parquet` with `date (Date, monthly), yoy_pct (double)` |

Each `*_latest.meta.json` carries `{source, fetched_at, rows, schema_hash}`
per the existing contract.

The ECB API is direct HTTP `read.csv(url)` — no special wrapper needed.
The URLs are built in R using the same pattern as the old Rmd, but the
date range argument always ends at `Sys.Date()`. Eurostat uses the
`eurostat` package's `get_eurostat()`.

Failure modes per fetcher (all already handled by `_fetch_template.R`):
- Network error → `tryCatch` catches, `message()` logs, `quit(status=1L)`.
- Validation failure (empty/missing cols) → `quit(status=1L)`.
- Either failure leaves `*_latest.*` files unchanged so the next render
  reads the previous snapshot and shows the freshness badge with the
  staleness escalation (tip → warning → important).

### 3.2 Page — `trackers/eu-finance.qmd`

Single page with YAML front matter:

```yaml
---
title: "Borrowing and Yields in the European Union"
subtitle: "An automatically updated overview of the EU's finances"
toc: true
---
```

Setup chunk (`include=FALSE`) sources `R/theme.R`, `R/freshness.R`,
loads `ggplot2`, `ggiraph`, `ggforce`, `dplyr`, `lubridate`, `stringr`,
`here`, and calls `register_ggiraph_defaults()`. Does NOT load `eurostat`,
`gdtools`, `gfonts` — those are fetch-time concerns only.

Body structure:

- **Intro paragraph** (≤4 sentences, trimmed from the old Rmd): the EU is
  a monetary union, ECB + Eurostat are the data sources, this page
  auto-updates nightly.
- **Combined freshness badge** from the oldest of 4 snapshots, via a new
  helper `freshness_badge_combined(list_of_metas)` (see §3.3).
- **Section A — Euro Area Government Bond Yields**: line plot with
  `ggforce::facet_zoom` (last-365-day inset), 3 maturities, `geom_line_interactive`,
  Okabe-Ito 3-colour palette `mo_palette$categorical[1:3]`. One paragraph
  prose explaining bonds + inverted yield curves.
- **Section B — Government Bond Yields by Country**: point+line plot
  faceted by `country_name`, EA average as dashed reference line.
  Inline computed prose with current max/min country, EA avg, non-EA
  EU avg (same patterns as old Rmd, all computed from the snapshot).
- **Section C — Euro Area Key Interest Rates and Inflation**: joined
  MRR + HICP plot, `geom_step_interactive`, `geom_hline(yintercept=2,
  lty=2)` for the inflation target, `ggforce::facet_zoom` on last year.
  Closing prose ("In times of rising inflation, the ECB's main
  countervailing instrument is …").
- **Closing**: a "Sources" line listing the 4 upstream APIs + a Citation
  block similar to the old Rmd's `# Cite` section, with the page URL
  hard-coded as `https://michalovadek.github.io/euverse/trackers/eu-finance.html`.

No DT or gt tables. No domain-helper layer (`R/yields.R` etc.). No
per-section freshness badges. No dark-mode plot variants.

### 3.3 Shared helper addition — `freshness_badge_combined`

Add to `R/freshness.R`:

```r
freshness_badge_combined <- function(metas) {
  # Pick the oldest fetched_at across the input list, render one badge
  # via the existing single-meta freshness_badge(). Users see worst-case
  # staleness, which is the honest answer for a multi-source page.
  fetched_times <- vapply(metas, function(m) {
    t <- suppressWarnings(as.POSIXct(m$fetched_at, tz = "UTC",
                                     format = "%Y-%m-%dT%H:%M:%SZ"))
    if (length(t) == 1L && !is.na(t)) as.numeric(t) else NA_real_
  }, numeric(1))
  if (all(is.na(fetched_times))) {
    return(freshness_badge(list(source = "(multiple)", fetched_at = NA, rows = NA)))
  }
  oldest_idx <- which.min(fetched_times)
  oldest_meta <- metas[[oldest_idx]]
  # Tweak the source field to reflect the combined view.
  oldest_meta$source <- paste0(oldest_meta$source, " (oldest of ", length(metas), " sources)")
  freshness_badge(oldest_meta)
}
```

~12 lines. Tested by the eufinance page render (and any future
multi-source tracker).

### 3.4 New R package deps to pin in renv

`eurostat`, `ggforce`, plus explicit pins for `dplyr`, `lubridate`,
`stringr` (currently transitive — making them explicit so the lockfile
makes intent visible). Total ~5 new explicit top-level pins; transitive
closure adds maybe 10 more.

CI cold-cache impact: ~1 min extra on the first nightly run after merge.

System deps: none beyond what's already in the ubuntu-latest image
(`httr`/`curl` are already pulled by other packages).

### 3.5 `_quarto.yml` navbar update

Add a `Trackers` dropdown so the new page is discoverable:

```yaml
navbar:
  left:
    - href: home.qmd
      text: Home
    - text: Trackers
      menu:
        - href: trackers/eu-finance.qmd
          text: EU Finance
```

Dropdown shape now, even with one entry — the next three tracker ports
slot in as additional `menu:` items.

### 3.6 Workflow

`.github/workflows/render.yml` needs **no changes**. The existing
`R/fetch_*.R` glob auto-picks up the 4 new fetchers; the new page is
just another `*.qmd` Quarto discovers.

## 4. Sequencing — work order in this phase

1. **Add R packages**: in one R session,
   `renv::install(c("eurostat","ggforce","dplyr","lubridate","stringr"), prompt=FALSE)`
   then `renv::snapshot(type='all', library=renv::paths$library(), prompt=FALSE)`.
2. **Write the 4 fetchers** from the template. Each ~40–60 lines.
3. **Run each fetcher locally** to populate `data-apis/`. Verify each
   parquet's shape + meta JSON via `arrow::read_parquet` /
   `jsonlite::fromJSON`. This is the fetcher smoke test.
4. **Add `freshness_badge_combined()`** to `R/freshness.R` (~12 lines).
5. **Create `trackers/eu-finance.qmd`** per §3.2. Single file.
6. **Update `_quarto.yml`** with the navbar dropdown.
7. **`quarto render` locally**. Verify all 3 sections show output (the
   3 ggiraph plots, combined freshness badge, no console errors).
8. **Commit and push**: one commit covering renv.lock + new R files +
   new qmd + 4 initial parquet snapshots + `_quarto.yml` nav change.

## 5. Commit plan

ONE commit. Subject line summarises the port; body lists the upstream
APIs, the new fetchers, and notes that initial snapshots are bundled so
the first CI render has data to read.

## 6. CI expectations on push

- Cold renv cache installs the 5 new R packages + ~10 transitive deps
  (~1 min added).
- Each `R/fetch_*.R` runs sequentially via the existing workflow loop
  (~10–30 s for 4 fetchers). All run successfully because the upstream
  APIs are stable and well-known.
- `quarto render` produces `_site/trackers/eu-finance.html` (~30–80 KB).
- Deploy stays `if: false`; live site unchanged.

Most-likely failure modes:
- `eurostat::get_eurostat()` rate-limited (transient). Emits a workflow
  `::warning::`; site still renders because we shipped initial snapshots.
- `ggforce` missing system deps on Linux (unlikely with current
  ubuntu-latest; if so, insert `setup-r-dependencies@v2` per the
  workflow's documented fallback).

## 7. Success criteria

This phase is **done** when ALL of:

- `quarto render` locally produces `_site/trackers/eu-finance.html` with
  the 3 sections showing real data (not error placeholders).
- The combined freshness badge shows a fresh `callout-tip` variant (all
  4 snapshots fetched today).
- The 4 `data-apis/<src>_latest.parquet` files are committed and pass a
  schema/row sanity check against the expected shapes in §3.1.
- After push, the CI workflow's `render` job completes successfully.
- The page is discoverable from the navbar (`Trackers > EU Finance`).
- `AGENTS.md` §9 (migration map) gets a `[x]` next to the `eu-finance`
  row.

## 8. Out of scope / deferred

- DT or gt tables on `eu-finance.qmd` (port is plot-heavy already;
  tables are a follow-up if Section B's country-snapshot data warrants
  a sortable view).
- Per-section freshness badges (one combined badge approved).
- `R/yields.R` / `R/finance_plots.R` domain helpers (plotting stays
  page-local until a 2nd tracker reuses a plot).
- Dark-mode-aware plot rendering (light plots only; dark theme restyles
  chrome).
- New chart styles beyond what the old Rmd had.
- Restructuring or expanding the 3 sections.
- Removing the old `old/eufinancestats.Rmd` (kept as reference until
  the port is verified equivalent and the old standalone repo is
  archived on GitHub).
- Switching GH Pages source to "GitHub Actions" or flipping the deploy
  job's `if: false` (separate go-live phase).

## 9. Open questions

None. All decisions locked above. If something surfaces during
implementation that needs a call, surface it back to the owner before
shipping a workaround.
