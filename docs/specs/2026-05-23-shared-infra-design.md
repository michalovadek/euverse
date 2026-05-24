# Shared infra phase — design

**Date:** 2026-05-23 (migrated to euverse 2026-05-24)
**Repo:** `euverse` (formerly mis-targeted at `michalovadek.github.io` — see note)
**Site URL:** `https://michalovadek.github.io/euverse/`
**Phase:** Foundations beyond step (a). After this phase: tracker ports.

> **Migration note (2026-05-24):** This spec was originally written against
> the `michalovadek.github.io` repo before the owner clarified that the site
> belongs in a separate `euverse` repo served at the `/euverse/` subpath of
> the user's GitHub Pages. The body below still refers to
> `michalovadek.github.io` in a few places (the original implementation
> target); the actual location after migration is `euverse`. The design
> decisions are unchanged; only the deployment target moved. The "Cut-over
> from static HTML" considerations in §6 no longer apply — `euverse` is
> greenfield, so there is no static HTML to coexist with. See
> `euverse/AGENTS.md` for the live conventions.

## 1. Context & goal

Step (a) built the bare Quarto project + uv + renv + a CI workflow that's wired
but inert. This phase fills in the **shared infrastructure** every future page
will use: visual theme, R helpers, data folder conventions, and the dev/CI
ergonomics that keep iteration cheap. Goal is one-and-done: when this phase
ships, porting each of the four trackers becomes mostly mechanical.

Owner-stated principles this phase serves:

- Sustainable, less wasteful: build shared layers once, not per-tracker.
- Simple code: flat scripts, no R-package ceremony for internal helpers.
- Graceful degradation: site renders with stale data when fetchers fail.
- Transparent freshness: every page shows a "data as of <date>" badge.
- One unified look: shared ggplot theme + table style + bootswatch base.

## 2. Decisions (recap of brainstorming)

| Decision | Choice | Alternatives considered |
|---|---|---|
| Phase shape | Shared infra first | Vertical slice (one tracker top-to-bottom); presentation slice (theme + landing); hybrid |
| Visual identity | Refresh — modern Quarto-native | Continue old site aesthetic; bespoke SCSS |
| Theme package | "Clean canvas" | "Scholarly journal"; "Modern characterful"; visual mockups |
| Snapshot retention | Latest only | Latest + monthly archive; latest + daily window; full history |
| R/ structure | Flat scripts, file per concern | R-package style; single utils.R; Quarto includes |
| Dark mode for plots | Light-only plots, dark theme just restyles chrome | Per-mode plot rendering |
| Categorical palette | Okabe-Ito (colourblind-safe) | Tableau 10; hand-curated |
| Commit granularity | Two commits (foundation + shared infra) | One big initial commit; many small commits |
| Baseline R packages | Bundled now (8 packages) | Just-in-time as each tracker needs them |
| Arrow system deps in CI | React if it fails (don't add preemptively) | Add `setup-r-dependencies@v2` proactively |

## 3. Architecture

### 3.1 Visual theme

- **Bootswatch pair**: `zephyr` (light) + `darkly` (dark). Quarto config:
  ```yaml
  format:
    html:
      theme:
        light: zephyr
        dark: darkly
  ```
  Quarto auto-injects a navbar toggle.
- **Typography**: Inter, weights 400 / 700. Loaded via a single Google Fonts
  `<link>` in a header partial.
- **`assets/style.scss`** — ~30 lines:
  - `@import` for Inter
  - navbar spacing tweaks
  - plot/table container backgrounds match page bg in both light and dark
    modes (so plot whitespace doesn't show as a visible rectangle on dark)
- **Plot palette** (in `R/theme.R` as a list `mo_palette`):
  - `$categorical` = Okabe-Ito 8 colours (`#E69F00 #56B4E9 #009E73 #F0E442
    #0072B2 #D55E00 #CC79A7 #999999`)
  - `$sequential` = `viridis::viridis(N)` wrapper
  - `$diverging` = `RColorBrewer::brewer.pal(11, "BrBG")`
- **`theme_mo()` ggplot theme**: Inter base family, white panel bg, subtle
  light-gray gridlines, left-aligned bold title at base+2, no top/right
  panel border. Plots render in light mode only; dark site mode restyles the
  page chrome, not the plot images.
- **ggiraph defaults**: `register_ggiraph_defaults()` sets hover stroke `#666`,
  same-colour fill darkened ~15%, tooltip uses Inter font.

### 3.2 R helpers — `R/` layout

Flat scripts, file per concern. Pages source what they need with
`source(here::here("R", "<file>.R"))`. No DESCRIPTION, no NAMESPACE.

```
R/
├── theme.R              # theme_mo(), mo_palette, register_ggiraph_defaults()
├── freshness.R          # freshness_badge(meta), read_with_freshness(stem)
├── table.R              # dt_mo(df, ...), gt_mo(df, ...)
└── _fetch_template.R    # copy-paste starting point. Leading underscore so
                         # the CI workflow's `R/fetch_*.R` glob skips it
                         # (the template alone would fail validation nightly).
                         # Real fetchers drop the underscore: fetch_<src>.R.
```

#### 3.2.1 `R/theme.R`

```r
mo_palette <- list(
  categorical = c("#E69F00","#56B4E9","#009E73","#F0E442",
                  "#0072B2","#D55E00","#CC79A7","#999999"),
  sequential  = function(n) viridis::viridis(n),
  diverging   = RColorBrewer::brewer.pal(11, "BrBG")
)

theme_mo <- function(base_size = 12) {
  ggplot2::theme_minimal(base_family = "Inter", base_size = base_size) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title.position = "plot",
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "#eaeaea"),
      panel.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.background  = ggplot2::element_rect(fill = "white", colour = NA),
      strip.text       = ggplot2::element_text(face = "bold")
    )
}

register_ggiraph_defaults <- function() {
  ggiraph::set_girafe_defaults(
    opts_hover = ggiraph::opts_hover(css = "stroke:#666;stroke-width:1px;"),
    opts_tooltip = ggiraph::opts_tooltip(
      css = "font-family:Inter,sans-serif; padding:6px 8px; background:#fff;
             border:1px solid #ddd; border-radius:4px; font-size:13px;"
    )
  )
}
```

#### 3.2.2 `R/freshness.R`

```r
read_with_freshness <- function(stem,
                                dir = here::here("data-apis")) {
  data_path <- file.path(dir, paste0(stem, "_latest.parquet"))
  meta_path <- file.path(dir, paste0(stem, "_latest.meta.json"))
  if (!file.exists(data_path)) {
    stop("No latest snapshot for '", stem, "'. ",
         "Has the fetcher ever succeeded?")
  }
  list(
    data       = arrow::read_parquet(data_path),
    meta       = jsonlite::fromJSON(meta_path),
    meta_path  = meta_path
  )
}

freshness_badge <- function(meta) {
  fetched <- as.POSIXct(meta$fetched_at, tz = "UTC")
  age_h   <- as.numeric(difftime(Sys.time(), fetched, units = "hours"))
  cls <- if (age_h <  36) "callout-tip"
         else if (age_h < 72) "callout-warning"
         else "callout-important"
  htmltools::HTML(sprintf(
    '<div class="%s" style="margin:0 0 1em 0;">Data as of <strong>%s UTC</strong> (source: %s, %s rows).</div>',
    cls,
    format(fetched, "%Y-%m-%d %H:%M"),
    meta$source,
    format(meta$rows, big.mark = ",")
  ))
}
```

Note: returned HTML uses Quarto's callout classes; in the qmd it goes inside
a raw HTML block (`` ```{=html} ``) rather than markdown callout fences.

#### 3.2.3 `R/table.R`

```r
dt_mo <- function(df, ..., page_length = 15) {
  DT::datatable(
    df,
    rownames   = FALSE,
    extensions = c("Buttons"),
    options    = list(
      pageLength = page_length,
      dom        = "Bfrtip",
      buttons    = c("csv","excel"),
      ...
    ),
    class = "compact stripe hover"
  )
}

gt_mo <- function(df, ...) {
  gt::gt(df, ...) |>
    gt::opt_table_font(font = list(gt::default_fonts(), "Inter")) |>
    gt::tab_options(
      table.border.top.style    = "none",
      table.border.bottom.style = "none",
      heading.title.font.weight = "bold"
    )
}
```

#### 3.2.4 `R/fetch_template.R`

Documented copy-paste template. Encodes the graceful-degradation contract:
"validate THEN write" — if validation fails the previous `latest` files are
preserved so the next render falls back to them.

```r
# ============================================================================
# _fetch_template.R  —  COPY this file to fetch_<src>.R (drop the leading
# underscore) and replace <src> with your source name. The underscore on the
# template stops the CI workflow's R/fetch_*.R glob from running it nightly.
#
# Contract:
#   - On success: writes data-apis/<src>_latest.parquet and
#                 data-apis/<src>_latest.meta.json (atomically — temp then rename).
#   - On any failure: exits non-zero WITHOUT modifying the *_latest.* files,
#                     so the next quarto render falls back to the previous
#                     snapshot and shows an older freshness badge.
#   - Stdout/stderr is captured by the CI workflow. Use message() for progress.
# ============================================================================

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here)
})

src    <- "REPLACE_ME"                       # e.g. "ecb_yields"
out_dir <- here::here("data-apis")

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  # ... actual fetch logic ...
  data.frame()                                # placeholder
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1)
})

# ---- 2. validate ------------------------------------------------------------
stopifnot(
  is.data.frame(df),
  nrow(df) > 0,
  # ... domain-specific schema checks ...
  TRUE
)

# ---- 3. write atomically ----------------------------------------------------
data_tmp <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")

arrow::write_parquet(df, data_tmp, compression = "zstd")
jsonlite::write_json(
  list(
    source      = src,
    fetched_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    rows        = nrow(df),
    schema_hash = digest::digest(names(df), algo = "sha256")
  ),
  meta_tmp,
  auto_unbox = TRUE,
  pretty     = TRUE
)

file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
```

### 3.3 Data folder layout

```
data-manual/
└── _README.md          Hand-curated CSVs. Read-only from R scripts.
                        Example: vetoes.csv (copied from eu-veto-tracker
                        when that tracker is ported).

data-apis/
├── _README.md          Latest nightly snapshots ONLY. Format:
                        <src>_latest.parquet + <src>_latest.meta.json.
                        Historical data is rebuilt by re-fetching the
                        source — we do NOT keep archived snapshots in git.
├── <src>_latest.parquet           (written by R/fetch_<src>.R)
└── <src>_latest.meta.json         (written by R/fetch_<src>.R)

data-external/
└── _README.md          Mirrors from sibling repos under
                        C:\Users\uctqova\Documents\github\. Each file MUST
                        have a <file>.source.txt sidecar recording source
                        repo + commit hash + date pulled.
```

In this phase we create the three folders and their `_README.md` files. We
also ship one *stub* `<src>_latest.parquet` + `.meta.json` under `data-apis/`
so `home.qmd` can demo the freshness-badge plumbing before any real fetcher
exists. The stub is a single-row data frame; the meta has `source: "stub"`.

### 3.4 `home.qmd` becomes a plumbing test

Replaces the current placeholder. New content:

- Brief intro paragraph (one sentence, since the site cut-over is later).
- A `freshness_badge()` rendered from the stub meta — proves the helper
  imports work in the qmd context.
- A 4-bar dummy ggplot via `theme_mo()` + ggiraph — proves theme + interactive
  plot path renders.
- A 5-row dummy DT via `dt_mo()` — proves table styling.

Once the real trackers exist, `home.qmd` will either become the actual
landing (renamed to `index.qmd`) or stay as a dev/debug page. Decision
deferred to the cut-over.

## 4. Sequencing — work order in this phase

1. `.Renviron` with `RENV_CONFIG_SANDBOX_ENABLED = FALSE`.
2. In a single R session: `renv::install(c("yaml","ggplot2","ggiraph","DT","gt","here","jsonlite","arrow","viridis","RColorBrewer","digest","htmltools"))` then `renv::snapshot()`.
3. Create `R/theme.R`, `R/freshness.R`, `R/table.R`, `R/_fetch_template.R` (note leading underscore on the template).
4. Create `data-manual/_README.md`, `data-apis/_README.md`, `data-external/_README.md`.
5. Create stub `data-apis/stub_latest.parquet` + `stub_latest.meta.json` (one-row dummy).
6. Create `assets/style.scss` and `assets/header.html`. Wire them into `_quarto.yml` via:
   ```yaml
   format:
     html:
       theme:
         light: [zephyr, assets/style.scss]
         dark:  [darkly, assets/style.scss]
       include-in-header: assets/header.html
   ```
   `assets/header.html` contains the single Google Fonts link
   (`<link rel="preconnect" href="https://fonts.googleapis.com">` +
   `<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap">`).
   `assets/style.scss` sets `$font-family-sans-serif: "Inter", sans-serif;`
   plus navbar/container tweaks.
7. Rewrite `home.qmd` to exercise theme + freshness + plot + table.
8. Local `quarto render`. Fix issues.
9. **Commit 1**: `Initialize Quarto project: foundation, CI workflow, AGENTS.md` (all of step (a)'s files).
10. **Commit 2**: `Add shared R helpers, theme, and data folder skeleton` (everything from this phase).
11. Push both commits to `main` on the GitHub remote.
12. Observe first CI run in the Actions tab. Iterate if anything fails (most likely culprit: `arrow` system deps on Linux).

## 5. Commit plan

Two commits, in the order above. Commit messages give the why, not just the what.

## 6. CI expectations on first push

- `on: push` fires `render` job.
- Cold cache: ~5–10 min wall time. Subsequent runs <2 min thanks to renv +
  uv cache.
- Deploy job stays inert (`if: false`); live site at
  https://michalovadek.github.io is unchanged.
- If `arrow` install fails for missing `libarrow-dev`, insert before
  `setup-renv@v2` in `.github/workflows/render.yml`:
  ```yaml
  - uses: r-lib/actions/setup-r-dependencies@v2
    with:
      packages: any::renv
  ```
  Push again. Don't add this preemptively — depends on the ubuntu-latest
  image of the week.
- The `Fetch nightly data` step should be a no-op on first push: no
  `R/fetch_*.R` files exist yet (the template ships as `_fetch_template.R`
  with a leading underscore, which the `fetch_*.R` glob does not match).
  The step prints "No R/fetch_*.R scripts yet — skipping fetch stage."

## 7. Success criteria

This phase is **done** when ALL of:

- `quarto render` succeeds locally and `_site/home.html` shows: intro
  paragraph, freshness badge with the stub date, a dummy bar plot styled
  with `theme_mo()`, a dummy DT styled with `dt_mo()`.
- Switching the navbar dark-mode toggle visibly restyles chrome without
  breaking the plot or table.
- Two commits exist in the local repo; both push to GitHub.
- The first GH Actions `render` job completes successfully (deploy stays
  inert).
- AGENTS.md has been edited to remove the "TBD bootswatch + colour
  palette" item from §10 Open questions, replacing it with "Decided
  2026-05-23: zephyr+darkly, Inter, Okabe-Ito categorical, viridis
  sequential, BrBG diverging."

## 8. Out of scope / deferred

- Porting any of the four trackers (separate phases).
- Real data fetchers (each tracker brings its own).
- Page renames (`home.qmd` → `index.qmd`) and deletion of static HTML —
  reserved for the cut-over phase.
- Switching GH Pages source from "branch" to "GitHub Actions" — reserved
  for cut-over.
- A `publications.qmd` / `tools.qmd` port — landing-page-content phase,
  separate from this infra phase.
- Pinning a CRAN snapshot date or RSPM URL beyond what `use-public-rspm:
  true` already does.
- A CONTRIBUTING.md or human-facing developer guide (single-author project
  for now; AGENTS.md is sufficient).
- A `.gitattributes` file for line-ending control (Quarto's default
  behaviour is fine on this single-Windows-author project).

## 9. Open questions

None. All decisions are locked above. If something surfaces during
implementation that needs a call, surface it back to the owner before
shipping a workaround.
