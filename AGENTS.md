# AGENTS.md — euverse

Working notes for any agent (human or AI) touching this repo. This file is the
single source of truth for conventions; if the code disagrees with this file,
update one or the other so they match.

## 1. What this repo is

A **Quarto** website served at `https://michalovadek.github.io/euverse/`
(GitHub Pages, repo = `euverse`, served at the `<user>.github.io/<repo>/`
subpath). It consolidates what used to live as four standalone R Markdown
sites — `eu-veto-tracker`, `eucourt`, `eulaw`, `eufinance` — plus any future
EU-related mini-projects, under one roof. Most pages re-render **nightly via
GitHub Actions** from live data sources.

Repo tagline (from `README.md`): "bringing all my EU-related mini projects
under one roof".

Design principles (set by owner, do not silently violate):

1. **Sustainable, not wasteful** — one nightly render covers all pages; we
   don't duplicate fetch/render logic per page. API responses are stored once
   per source, reused across pages.
2. **Graceful degradation** — if an upstream API fails, the page must still
   render using the last good cached snapshot, with a visible "data as of
   <date>" stamp. Never show silently stale content.
3. **Prefer simple code** — small composable R scripts in `R/`, qmd pages
   call them. Avoid clever metaprogramming.
4. **One unified look** — shared SCSS theme + shared ggplot theme + shared
   table style. Per-page custom CSS is a smell.
5. **Respect GitHub limits** — see §8.

## 2. Toolchain (verified on this laptop, 2026-05-24)

| Tool   | Version           | Notes                                                       |
|--------|-------------------|-------------------------------------------------------------|
| R      | 4.4.3 (2025-02-28)| `C:\Program Files\R\R-4.4.3\bin\Rscript.exe` (not on PATH)  |
| Quarto | 1.7.17            | `quarto` on PATH                                            |
| uv     | 0.10.7            | Python is **only** used through uv in this repo             |
| git    | 2.40.0.windows.1  |                                                             |

R is the **primary** language. Use Python only when there's no good R option,
and always via uv (`uv run python ...`, `uv add <pkg>`). Never `pip install`
into a system Python.

R packages are pinned via **renv** (currently pinned to renv 1.2.3 itself).
After adding a `library()` call, run `renv::snapshot()` so the CI install
matches local.

## 3. Repo layout (target)

```
euverse/
├── _quarto.yml               # site config (nav, theme, output, freeze)
├── home.qmd                  # transitional plumbing-test landing; will become
│                             # a real landing page (or get renamed index.qmd)
│                             # when content is designed.
├── trackers/
│   ├── eu-vetoes.qmd         # from old/tracker.qmd          (data-manual)
│   ├── eu-court.qmd          # from old/eucourtstats.Rmd     (data-apis)
│   ├── eu-law.qmd            # from old/eulawstats.Rmd       (data-apis)
│   └── eu-finance.qmd        # from old/eufinancestats.Rmd   (data-apis)
├── R/                        # shared R helpers (flat scripts, file per concern)
│   ├── theme.R               # ggplot theme + ggiraph defaults + colour palette
│   ├── table.R               # shared DT / gt wrappers
│   ├── freshness.R           # "as of <date>" badge helpers
│   ├── fetch_<src>.R         # one per upstream source; reusable across pages
│   └── _fetch_template.R     # copy-paste template (leading underscore: CI glob skips)
├── data-manual/              # owner-curated CSVs (committed)
├── data-apis/                # nightly snapshots of API pulls (committed)
├── data-external/            # mirrored from sibling repos under github/
├── data-final/               # cross-cutting derived/joined data (committed)
├── old/                      # historical reference: source Rmds + old workflow
│                             # of the four standalone trackers being consolidated
├── _site/                    # rendered HTML (GITIGNORED)
├── _freeze/                  # Quarto freeze cache (GITIGNORED)
├── .quarto/                  # Quarto cache (GITIGNORED)
├── assets/
│   ├── header.html           # Google Fonts Inter <link>
│   └── style.scss            # site-wide style (~30 lines)
├── pyproject.toml            # uv-managed (name = "euverse", zero deps yet)
├── uv.lock                   # committed
├── renv.lock                 # committed
├── renv/                     # only .gitignore, activate.R, settings.json committed
└── .github/workflows/
    └── render.yml            # nightly cron + push + manual dispatch
```

## 4. Data conventions

**Four folders, distinct roles:**

- **`data-manual/`** — entered/edited by hand by the owner. Authoritative.
  Read-only from R scripts. Currently has `ms-vetoes.csv` (EU member-state
  veto data) and `contested-competences/` supporting material.
- **`data-apis/`** — written by `R/fetch_<src>.R` scripts during the nightly
  CI run. **Source-named** snapshots (NOT page-named) so multiple tracker
  pages reuse the same data without re-fetching:
  - `<src>_latest.parquet` — the data, parquet, zstd-compressed.
  - `<src>_latest.meta.json` — sidecar: `{source, fetched_at, rows, schema_hash}`.
  - Atomic per-file rename. If a fetcher errors, `*_latest.*` are unchanged
    and the next render falls back to the previous snapshot.
  - No historical archive — re-query the source if you need older data.
- **`data-external/`** — copies/mirrors of data from sibling repos under
  `C:\Users\uctqova\Documents\github\<other>\`. Each file (or folder)
  carries a `.source.txt` / `_SOURCE.md` sidecar with source repo + commit
  hash + pulled-at date. Existing subfolders (`euplex/`, `euprops/`,
  `manifesto/`, `parlgov/`) pre-date the sidecar convention — add a
  `_SOURCE.md` when a tracker first consumes one.
- **`data-final/`** — cross-cutting **derived / joined** data shared across
  trackers (e.g., an `eu_member_states_master.parquet` built once from
  manual + external + API inputs, reused by every tracker). Each file has a
  `<name>.build.R` (or `R/build_<name>.R`) that's idempotent + a
  `<name>.meta.json` recording `{built_at, inputs, builder_script, rows}`.
  Committed because they're small, stable, and rebuilding on every render
  would be wasteful.

**Storage format default: parquet** (via `arrow`). CSV only for files
humans edit (i.e. `data-manual/`). Parquet is ~5× smaller than CSV for
typical tracker data and avoids the >50 MB warnings.

## 5. Code conventions

- R style: tidyverse-ish, no `magrittr` (use base `|>`). Snake_case names.
  No side effects at the top of source files.
- Every R helper in `R/` must be **idempotent and pure** (input args → return
  value or file path); printing, plotting, and table rendering happens in
  the .qmd file.
- No `setwd()`. Paths resolve from project root via `here::here()`.
- Python (when needed): uv project; scripts live in `py/`; called from R
  via `processx::run("uv", c("run", "python", "py/foo.py", ...))`.
- Comments are rare and explain *why*, never *what*. Names do the explaining.

## 6. Plotting & theming

- **All charts: `ggplot2` + `ggiraph`** (interactive on hover/click). No
  plotly, highcharter, or echarts4r unless we have a documented reason.
- **All tables: `DT`** for long sortable/filterable; **`gt`** for short
  presentation tables. Wrap both in `R/table.R` so styling stays unified.
- Shared theme function `theme_mo()` in `R/theme.R`. Inter font, white
  panel bg, subtle gridlines; pair `register_ggiraph_defaults()` to
  standardise hover/tooltip styling.
- Colour palette (defined in `R/theme.R` as `mo_palette$categorical /
  $sequential / $diverging`; never inlined): **Okabe-Ito** categorical (8
  colours, colourblind-safe), **viridis** sequential, **BrBG** diverging.
- Site theme: bootswatch **zephyr** (light) + **darkly** (dark), with
  manual navbar toggle, layered with `assets/style.scss` for the ~30
  custom lines (font override, navbar tightening, callout styling).

## 7. Build & CI

- **Local:** `quarto preview` for live reload during development.
- **CI:** `.github/workflows/render.yml`. Read the file for the canonical
  definition; this section summarises and explains the choices.
  - Triggers: nightly cron `17 3 * * *` (03:17 UTC — after overnight EU
    API refresh windows; do **not** use `59 23 * * *` like the old
    standalone trackers did, that races with Eurostat's update and yields
    stale numbers); plus `push` to `main` for layout/code changes
    (docs-only paths skipped); plus `workflow_dispatch` for manual reruns.
  - Pipeline: `setup-r@v2 (4.4.3)` → `setup-renv@v2` (cached on hash of
    renv.lock) → `setup-uv@v5 (0.10.7, cached)` → `uv sync --frozen
    --no-install-project` → `setup-quarto@v2 (1.7.17)` → run every
    `R/fetch_*.R` with graceful failure → `quarto render` →
    `upload-pages-artifact@v3` → `deploy-pages@v4` (currently inert).
  - **Graceful degradation is enforced in the workflow itself** (not in
    R): each fetcher runs in its own `Rscript` invocation; a non-zero
    exit emits a GitHub Actions `::warning::` annotation but does NOT
    fail the job.
  - When we add R packages needing system libs (cairo, poppler, freetype,
    libudunits, …), insert `r-lib/actions/setup-r-dependencies@v2` BEFORE
    `setup-renv` and it will install them from DESCRIPTION/renv.lock.

### Going live (greenfield — no cut-over dance)

The deploy job in `render.yml` is gated `if: false` until the owner is
ready to publish. To go live:

1. GitHub repo Settings → **Pages → Source → "GitHub Actions"** (one-time).
2. Change `if: false` → `if: true` (or remove the line) in
   `.github/workflows/render.yml`.
3. Push. The next workflow run deploys to
   `https://michalovadek.github.io/euverse/`.

Unlike the original (mistaken) attempt in `michalovadek.github.io`, this
repo is greenfield — there is no existing static HTML to coexist with or
rename around. The first deployed render IS the site.

## 8. Git, gitignore, and GitHub size limits

GitHub enforces:
- **100 MB** hard per-file limit (push rejected).
- **50 MB** soft warning per file.
- **~1 GB** recommended max repo size; **5 GB** absolute.
- Pages-served sites: any single file < 100 MB, total site < 1 GB.

Therefore:
- **Always gitignored:** `_site/`, `_freeze/`, `.quarto/`, `renv/library/`,
  `renv/python/`, `renv/staging/`, `.Rproj.user/`, `.Rhistory`, `.RData`,
  `.Ruserdata`, `__pycache__/`, `.venv/`, `*.pyc`.
- **Committed when small** (<5 MB): everything in `data-manual/`,
  `data-final/`, and parquet snapshots in `data-apis/`.
- **Compress or partition** when a single snapshot approaches 10 MB.
  Order of preference: parquet → parquet with row-group filtering →
  split by year → drop columns we don't plot.
- **Git LFS** is allowed but is a last resort (GH free tier = 1 GB
  storage + 1 GB/month bandwidth; easy to blow with a nightly cron).
- **Never commit** rendered HTML to `main`.

`.gitignore` ships with the repo and covers the above.

## 9. Migration map (old → new)

| Old artifact (under `old/` or sibling repo)        | Original build     | New location              | Data path                    |
|----------------------------------------------------|--------------------|---------------------------|------------------------------|
| `old/tracker.qmd`                                  | Quarto + Action    | `trackers/eu-vetoes.qmd`  | `data-manual/ms-vetoes.csv` (already here) |
| `old/eucourtstats.Rmd`                             | Rmd + nightly cron | `trackers/eu-court.qmd`   | `data-apis/eurlex_*`         |
| `old/eulawstats.Rmd`                               | Rmd + nightly cron | `trackers/eu-law.qmd`     | `data-apis/eurlex_*`         |
| `old/eufinancestats.Rmd`                           | Rmd + nightly cron | `trackers/eu-finance.qmd` | `data-apis/ecb_*, eurostat_*`|

Old standalone repos (`eu-veto-tracker`, `eucourt`, `eulaw`, `eufinance`)
stay live (their `gh-pages` branches keep serving) until each new tracker
is verified equivalent. Then archive them on GitHub (don't delete —
incoming links from publications shouldn't 404).

Shared R-package dependencies seen across old trackers (consolidate in
single `renv.lock`): `eurlex`, `eurostat`, `ggplot2`, `ggiraph`, `dplyr`,
`tidyr`, `purrr`, `stringr`, `forcats`, `lubridate`, `DT`, `gt`,
`gdtools`, `gfonts`, `httr2`, `rvest`, `xml2`, `arrow`, `here`,
`countrycode`, `ISOweek`, `modelsummary`, `ggforce`. The shared-infra
phase already pinned: `ggplot2`, `ggiraph`, `DT`, `gt`, `here`,
`jsonlite`, `arrow`, `viridis`, `RColorBrewer`, `digest`, `htmltools`,
`yaml`. The rest get pinned as tracker ports need them.

## 10. Open questions / TODOs

- [x] Bootswatch base + colour palette decided 2026-05-23: zephyr (light) /
      darkly (dark), Inter font, Okabe-Ito categorical, viridis sequential,
      BrBG diverging. See `docs/specs/2026-05-23-shared-infra-design.md` §3.1.
- [ ] Real landing page content for `home.qmd` (or rename to `index.qmd`
      and design a proper landing). Currently it's a plumbing test only.
- [ ] Backfill `_SOURCE.md` sidecars in `data-external/euplex/`, `euprops/`,
      `manifesto/`, `parlgov/` when each is first consumed by a tracker.
- [ ] CNAME? (owner has no custom domain at time of writing — site URL
      remains `https://michalovadek.github.io/euverse/`.)
- [ ] Long-term: extract `R/fetch_eurlex.R` into the `eurlex` package
      itself (owner already maintains it) so other projects benefit.
