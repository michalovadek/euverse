# Shared Infra Phase — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-05-24):** EXECUTED in the `michalovadek.github.io` repo on
> 2026-05-23/24 (commits `1fdeea2` + `dd67ad5` after rebase). Then migrated
> to the `euverse` repo on 2026-05-24 because the owner clarified the site
> belongs there, not in their personal landing-page repo. This document is
> retained as historical record of the shared-infra phase; the actual files
> it produced now live in `euverse/`. See the migration note at the top of
> the corresponding spec.

**Goal:** Build the shared visual theme, R helper layer, and data folder skeleton so that subsequent tracker ports become mechanical, then push for a first CI dry-run.

**Architecture:** Flat R script helpers under `R/` (no R-package ceremony), three data folders (`data-manual/`, `data-apis/`, `data-external/`) with README sidecars and a stub snapshot so `home.qmd` can demo the freshness-badge wiring. Quarto themed with `zephyr` (light) + `darkly` (dark), Inter font via Google Fonts, Okabe-Ito plot palette. Two commits total: one for step (a) foundation, one for everything from this phase. First push exercises the CI workflow's render job (deploy stays inert).

**Tech Stack:** R 4.4.3 (with renv 1.1.4), Quarto 1.7.17, uv 0.10.7, ggplot2 + ggiraph + DT + gt + arrow + here + jsonlite + htmltools + viridis + RColorBrewer + digest + yaml.

**Spec reference:** `docs/specs/2026-05-23-shared-infra-design.md`

**Conventions for this plan:**
- Working directory throughout: `C:\Users\uctqova\Documents\github\michalovadek.github.io`. Every R one-liner and `quarto` command assumes this is `Set-Location`'d to that path. The `cd` is shown once per command block so each task is self-contained.
- Rscript path: `& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe"` — R is not on PATH. Quoted variant for PowerShell, unquoted `Rscript` for Bash inside the project shell (depends on environment; use whichever shell the executor prefers).
- The phrase "verify" in a step means: run the command, read its output, compare to the "Expected" line. If the output disagrees, stop and surface the discrepancy.
- "Commit" steps appear only in Task 0 and Task 14 (the two-commit plan). Other tasks end with staging the new files via `git add` so the final commit picks them up.

---

## Task 0: Commit step (a) foundation

**Files:**
- Stage: every currently-untracked file at repo root (see Step 1 listing)
- Commit: 1

- [ ] **Step 1: Stage the foundation files**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
git add `
  .Rprofile `
  .github `
  .gitignore `
  AGENTS.md `
  _quarto.yml `
  home.qmd `
  pyproject.toml `
  renv `
  renv.lock `
  uv.lock `
  docs
git status --short
```

Expected: every line starts with `A ` (added), nothing starts with `??` (untracked) or ` D` (deleted). `_site/`, `.venv/`, `renv/library/`, `.quarto/` must NOT appear.

- [ ] **Step 2: Make the foundation commit**

Run (PowerShell):
```powershell
git commit -m @'
Initialize Quarto project: foundation, CI workflow, AGENTS.md

Adds the minimum Quarto project (_quarto.yml + transitional home.qmd),
gitignore, renv 1.1.4 baseline (R 4.4.3 with recommended packages),
uv 0.10.7 bare init (zero deps), and a render+deploy workflow with the
deploy job gated `if: false` until cut-over. AGENTS.md captures all
conventions; docs/specs/2026-05-23-shared-infra-design.md captures the
plan for the next phase.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
git log --oneline -1
```

Expected: commit succeeds; `git log --oneline -1` shows the new commit hash and the summary line "Initialize Quarto project: foundation, CI workflow, AGENTS.md".

---

## Task 1: Disable renv sandbox on Windows

**Files:**
- Create: `.Renviron`

- [ ] **Step 1: Write `.Renviron`**

Create `C:\Users\uctqova\Documents\github\michalovadek.github.io\.Renviron` with this exact content:

```
# Disable the renv sandbox on Windows to skip the ~16s per-Rscript activation
# tax. Sandbox is a defence against package leakage from the system library;
# we're already inside renv so the risk is low and the time cost is real.
RENV_CONFIG_SANDBOX_ENABLED = FALSE
```

- [ ] **Step 2: Verify the file is read by R**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "cat('sandbox env =', Sys.getenv('RENV_CONFIG_SANDBOX_ENABLED'), '\n')"
```

Expected: output `sandbox env = FALSE`. The "renv took longer than expected (16 seconds) to activate the sandbox" warning we saw earlier should NOT appear.

- [ ] **Step 3: Stage**

Run (PowerShell):
```powershell
git add .Renviron
```

---

## Task 2: Install baseline R packages and snapshot

**Files:**
- Modify: `renv.lock` (regenerated by snapshot)

- [ ] **Step 1: Install the baseline bundle**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "renv::install(c('yaml','ggplot2','ggiraph','DT','gt','here','jsonlite','arrow','viridis','RColorBrewer','digest','htmltools'), prompt = FALSE)"
```

Expected: installation log shows each package successfully installed (may take 5–10 min cold on Windows). Final line approximately: "The following package(s) have been updated: ...". No "FAILED" / "non-zero exit status" lines.

- [ ] **Step 2: Snapshot to update renv.lock**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "renv::snapshot(type = 'all', library = renv::paths$library(), prompt = FALSE)"
```

Note both flags:
- `type = 'all'`: at this point in the sequence the project has no
  `library()` calls yet (those land in Tasks 3–6 and 10), so the default
  `type = 'implicit'` would record almost nothing. `type = 'all'` snapshots
  everything actually installed in the named library.
- `library = renv::paths$library()`: scopes the snapshot to the PROJECT
  library only (`renv/library/...`). Without this constraint, `type = 'all'`
  also scans the system R library and pins whatever packages happen to be
  installed globally on this workstation (potentially hundreds — tidyverse,
  brms, stan, sf, terra, etc.), making the lockfile huge and CI installs
  unbearable. Always pass both together.

From Task 10 onward, normal implicit snapshots will work because library()
calls exist in the .qmd / .R files; this two-flag combo is only for the
initial seeding.

If the snapshot aborts with "pre-flight validation failure" pointing at a
package in the system library missing a dep (e.g., `websocket` needs
`AsioHeaders`), the `library = ...` constraint above should prevent it
because the system library isn't scanned. If it still happens, install the
missing dep into the project library (`renv::install("AsioHeaders")`) and
retry — the missing-dep package then becomes part of the project library
and the validation passes.

Expected: output begins "The following package(s) will be updated in the lockfile:" listing the 12 packages plus their transitive deps (realistically ~80 total — `gt` and `arrow` each pull a fairly heavy stack: bslib, V8, juicyjuice, reactable, fontawesome, sass, cpp11, bit64, etc.). Ends "Lockfile written to ..." pointing at our `renv.lock`. Resulting `renv.lock` should be roughly 100–300 KB, NOT 1 MB+ (the 1 MB+ outcome happens when `library = ...` is omitted and the system R library gets scanned).

Side effect: renv may need to install some transitive deps into the project library before the snapshot can be self-contained. This is normal — let it proceed. `library(<pkg>)` calls succeed before snapshot because `.libPaths()` includes both the project and system libraries; snapshot requires the project library alone be self-contained.

- [ ] **Step 3: Verify the packages load**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "for (p in c('yaml','ggplot2','ggiraph','DT','gt','here','jsonlite','arrow','viridis','RColorBrewer','digest','htmltools')) { suppressPackageStartupMessages(library(p, character.only = TRUE)); cat(p, packageVersion(p) |> as.character(), '\n') }"
```

Expected: 12 lines, one per package, each `<pkgname> <version>`. No errors.

- [ ] **Step 4: Stage**

Run (PowerShell):
```powershell
git add renv.lock
```

---

## Task 3: Build `R/theme.R`

**Files:**
- Create: `R/theme.R`

- [ ] **Step 1: Create `R/` directory**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
New-Item -ItemType Directory -Force -Path R | Out-Null
Test-Path R
```

Expected: `True`.

- [ ] **Step 2: Write `R/theme.R`**

Create `R/theme.R` with this exact content:

```r
# theme.R  —  shared ggplot theme, palette, and ggiraph defaults.
# Sourced from .qmd pages via:  source(here::here("R", "theme.R"))
# Owner: see AGENTS.md §6.

mo_palette <- list(
  # Okabe-Ito 8-colour categorical palette (colourblind-safe).
  categorical = c(
    "#E69F00", "#56B4E9", "#009E73", "#F0E442",
    "#0072B2", "#D55E00", "#CC79A7", "#999999"
  ),
  # Sequential and diverging are functions of n so callers can request the
  # exact length they need (rather than slicing a fixed vector).
  sequential = function(n) viridis::viridis(n),
  diverging  = RColorBrewer::brewer.pal(11, "BrBG")
)

theme_mo <- function(base_size = 12) {
  ggplot2::theme_minimal(base_family = "Inter", base_size = base_size) +
    ggplot2::theme(
      plot.title           = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title.position  = "plot",
      panel.grid.minor     = ggplot2::element_blank(),
      panel.grid.major     = ggplot2::element_line(colour = "#eaeaea"),
      panel.background     = ggplot2::element_rect(fill = "white", colour = NA),
      plot.background      = ggplot2::element_rect(fill = "white", colour = NA),
      strip.text           = ggplot2::element_text(face = "bold"),
      legend.position      = "bottom",
      legend.title         = ggplot2::element_blank()
    )
}

register_ggiraph_defaults <- function() {
  ggiraph::set_girafe_defaults(
    opts_hover = ggiraph::opts_hover(
      css = "stroke:#666;stroke-width:1px;"
    ),
    opts_tooltip = ggiraph::opts_tooltip(
      css = paste0(
        "font-family:Inter,sans-serif;",
        "padding:6px 8px;",
        "background:#fff;",
        "border:1px solid #ddd;",
        "border-radius:4px;",
        "font-size:13px;"
      )
    )
  )
}
```

- [ ] **Step 3: Verify the file sources without error and exposes the expected symbols**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "source('R/theme.R'); stopifnot(length(mo_palette[['categorical']]) == 8L); stopifnot(is.function(mo_palette[['sequential']])); stopifnot(length(mo_palette[['diverging']]) == 11L); t <- theme_mo(); stopifnot(inherits(t, 'theme')); register_ggiraph_defaults(); cat('theme.R OK\n')"
```

Expected: `theme.R OK`. No errors. If `mo_palette[['diverging']]` triggers a "minimal value for n is 3" message from RColorBrewer — that's normal, not an error.

- [ ] **Step 4: Stage**

Run (PowerShell):
```powershell
git add R/theme.R
```

---

## Task 4: Build `R/freshness.R`

**Files:**
- Create: `R/freshness.R`

- [ ] **Step 1: Write `R/freshness.R`**

Create `R/freshness.R` with this exact content:

```r
# freshness.R  —  reads "latest" snapshots written by R/fetch_<src>.R and
# produces an HTML badge users see on every tracker page.
# Sourced from .qmd pages via:  source(here::here("R", "freshness.R"))
# Owner: see AGENTS.md §4.

read_with_freshness <- function(stem,
                                dir = here::here("data-apis")) {
  data_path <- file.path(dir, paste0(stem, "_latest.parquet"))
  meta_path <- file.path(dir, paste0(stem, "_latest.meta.json"))
  if (!file.exists(data_path)) {
    stop(sprintf(
      "No latest snapshot for '%s' at '%s'. Has R/fetch_%s.R ever succeeded?",
      stem, data_path, stem
    ), call. = FALSE)
  }
  if (!file.exists(meta_path)) {
    stop(sprintf(
      "Missing meta sidecar for '%s' at '%s'.", stem, meta_path
    ), call. = FALSE)
  }
  list(
    data      = arrow::read_parquet(data_path),
    meta      = jsonlite::fromJSON(meta_path),
    meta_path = meta_path
  )
}

freshness_badge <- function(meta) {
  fetched <- as.POSIXct(meta$fetched_at, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  age_h   <- as.numeric(difftime(Sys.time(), fetched, units = "hours"))
  # Severity escalates with age: tip (<36h) -> warning (<72h) -> important.
  cls <- if (age_h < 36)      "callout-tip"
         else if (age_h < 72) "callout-warning"
         else                 "callout-important"
  rows_label <- if (is.numeric(meta$rows)) format(meta$rows, big.mark = ",") else as.character(meta$rows)
  htmltools::HTML(sprintf(
    '<div class="callout %s" style="margin:0 0 1em 0;padding:8px 12px;border-left:4px solid;border-radius:3px;">Data as of <strong>%s UTC</strong> &middot; source: %s &middot; %s rows</div>',
    cls,
    format(fetched, "%Y-%m-%d %H:%M"),
    meta$source,
    rows_label
  ))
}
```

- [ ] **Step 2: Verify the functions work end-to-end with a temp fake snapshot**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e @"
suppressPackageStartupMessages({ library(arrow); library(jsonlite); library(here); library(htmltools) })
source('R/freshness.R')
# Create a tiny fake snapshot in a temp dir.
tmp <- tempfile('frtest_'); dir.create(tmp)
arrow::write_parquet(data.frame(x = 1:3, y = letters[1:3]), file.path(tmp, 'demo_latest.parquet'))
jsonlite::write_json(list(source='unit-test', fetched_at=format(Sys.time(), '%Y-%m-%dT%H:%M:%SZ', tz='UTC'), rows=3L), file.path(tmp, 'demo_latest.meta.json'), auto_unbox=TRUE)
fd <- read_with_freshness('demo', dir = tmp)
stopifnot(nrow(fd[['data']]) == 3L, fd[['meta']][['rows']] == 3L)
b <- freshness_badge(fd[['meta']])
stopifnot(grepl('Data as of', as.character(b)), grepl('unit-test', as.character(b)))
cat('freshness.R OK\n')
"@
```

Expected: `freshness.R OK`. No errors.

- [ ] **Step 3: Stage**

Run (PowerShell):
```powershell
git add R/freshness.R
```

---

## Task 5: Build `R/table.R`

**Files:**
- Create: `R/table.R`

- [ ] **Step 1: Write `R/table.R`**

Create `R/table.R` with this exact content:

```r
# table.R  —  shared wrappers for DT and gt that apply unified styling.
# Sourced from .qmd pages via:  source(here::here("R", "table.R"))
# Owner: see AGENTS.md §6.

dt_mo <- function(df, ..., page_length = 15) {
  DT::datatable(
    df,
    rownames   = FALSE,
    extensions = c("Buttons"),
    options    = list(
      pageLength = page_length,
      dom        = "Bfrtip",
      buttons    = c("csv", "excel")
    ),
    class = "compact stripe hover",
    ...
  )
}

gt_mo <- function(df, ...) {
  out <- gt::gt(df, ...)
  out <- gt::opt_table_font(out, font = list(gt::default_fonts(), "Inter"))
  gt::tab_options(
    out,
    table.border.top.style    = "none",
    table.border.bottom.style = "none",
    heading.title.font.weight = "bold"
  )
}
```

- [ ] **Step 2: Verify both wrappers return the right object types**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "suppressPackageStartupMessages({ library(DT); library(gt) }); source('R/table.R'); df <- data.frame(a = 1:3, b = c('x','y','z')); d <- dt_mo(df); g <- gt_mo(df); stopifnot(inherits(d, 'datatables')); stopifnot(inherits(g, 'gt_tbl')); cat('table.R OK\n')"
```

Expected: `table.R OK`. No errors.

- [ ] **Step 3: Stage**

Run (PowerShell):
```powershell
git add R/table.R
```

---

## Task 6: Build `R/_fetch_template.R`

**Files:**
- Create: `R/_fetch_template.R`

- [ ] **Step 1: Write `R/_fetch_template.R`**

Create `R/_fetch_template.R` with this exact content (note the leading underscore on the filename — this stops the CI workflow's `R/fetch_*.R` glob from running it nightly):

```r
# ============================================================================
# _fetch_template.R
#
# COPY this file to `fetch_<src>.R` (drop the leading underscore) and replace
# every <src> below with your source name. The underscore on this template
# keeps the CI workflow's R/fetch_*.R glob from running it; once renamed,
# the new fetcher runs nightly.
#
# Contract:
#   - On success: writes data-apis/<src>_latest.parquet and
#                 data-apis/<src>_latest.meta.json atomically (temp then
#                 rename), so a reader never sees half-written files.
#   - On failure: exits non-zero WITHOUT modifying the *_latest.* files,
#                 so the next quarto render falls back to the previous
#                 snapshot and shows an older freshness badge.
#   - Stdout / stderr is captured by the CI workflow. Use message() for
#     progress lines (visible in Actions logs).
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(jsonlite)
  library(here)
  library(digest)
})

src     <- "REPLACE_ME"                       # e.g. "ecb_yields"
out_dir <- here::here("data-apis")

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  # ... real fetch logic goes here ...
  stop("fetcher not yet implemented")        # remove once the body is written
  data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate (cheap schema/shape checks) --------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
# ... domain-specific schema checks here; quit(1L) on any failure ...

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

- [ ] **Step 2: Verify the file is parseable R (template is intentionally not runnable)**

Run (PowerShell):
```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "parsed <- parse('R/_fetch_template.R'); cat('parsed', length(parsed), 'top-level expressions\n')"
```

Expected: `parsed 6 top-level expressions` (suppressPackageStartupMessages call, src assignment, out_dir assignment, tryCatch assignment, validate block, write block + helpers). The exact number is OK as long as `parse()` does not error.

- [ ] **Step 3: Verify the workflow glob ignores the underscore-prefixed name**

Run (Bash, since `shopt` is bash-only):
```bash
cd "C:/Users/uctqova/Documents/github/michalovadek.github.io" && \
  bash -c 'shopt -s nullglob; for f in R/fetch_*.R; do echo "matched: $f"; done; echo done'
```

Expected: only `done` is printed. `R/_fetch_template.R` must NOT appear as a match.

- [ ] **Step 4: Stage**

Run (PowerShell):
```powershell
git add R/_fetch_template.R
```

---

## Task 7: Create data folder skeleton with README sidecars

**Files:**
- Create: `data-manual/_README.md`
- Create: `data-apis/_README.md`
- Create: `data-external/_README.md`

- [ ] **Step 1: Create the three folders**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
foreach ($d in @("data-manual", "data-apis", "data-external")) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Get-ChildItem -Directory -Filter "data-*" | Select-Object Name
```

Expected: three lines: `data-apis`, `data-external`, `data-manual`.

- [ ] **Step 2: Write `data-manual/_README.md`**

Create `data-manual/_README.md`:

```markdown
# data-manual/

Hand-curated CSVs entered or edited directly by the owner. Authoritative.

- Read-only from R scripts (fetchers never write here).
- Committed to git; small files only (<5 MB each).
- Name files `<topic>.csv` (snake_case, no dates in the filename — git history is the date record).

Example (added when the tracker is ported): `vetoes.csv`.

See AGENTS.md §4 for the data-folder conventions.
```

- [ ] **Step 3: Write `data-apis/_README.md`**

Create `data-apis/_README.md`:

```markdown
# data-apis/

**Latest snapshots only.** Written nightly by `R/fetch_<src>.R` scripts via the
CI workflow.

Naming:
- `<src>_latest.parquet` — the data (parquet, zstd-compressed).
- `<src>_latest.meta.json` — sidecar: `{source, fetched_at, rows, schema_hash}`.

Historical snapshots are NOT kept here. If a fetcher needs older data it
re-queries the live source. (We opted against accumulating monthly archives
because the API can always reconstruct history; see
docs/specs/2026-05-23-shared-infra-design.md §2.)

Writes must be atomic (tempfile + rename) so a reader never sees a
half-written snapshot. The `R/_fetch_template.R` template enforces this.

See AGENTS.md §4.
```

- [ ] **Step 4: Write `data-external/_README.md`**

Create `data-external/_README.md`:

```markdown
# data-external/

Mirrors of data files produced by sibling projects under
`C:\Users\uctqova\Documents\github\<other-repo>\`.

Every file in here MUST have a sibling `<filename>.source.txt` recording:

```
source-repo: <repo-name>
source-path: <path/inside/repo>
source-commit: <git-sha>
pulled-at: YYYY-MM-DD
```

This makes the provenance reproducible without depending on the other repo's
state at a future point in time.

See AGENTS.md §4.
```

- [ ] **Step 5: Stage**

Run (PowerShell):
```powershell
git add data-manual data-apis data-external
```

---

## Task 8: Create stub snapshot so `home.qmd` can demo freshness wiring

**Files:**
- Create: `data-apis/stub_latest.parquet`
- Create: `data-apis/stub_latest.meta.json`

- [ ] **Step 1: Write a one-row stub snapshot and its meta**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e @"
suppressPackageStartupMessages({ library(arrow); library(jsonlite) })
df <- data.frame(metric = 'plumbing test', value = 1L)
arrow::write_parquet(df, 'data-apis/stub_latest.parquet', compression = 'zstd')
jsonlite::write_json(
  list(
    source      = 'stub (no real fetcher yet)',
    fetched_at  = format(Sys.time(), '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC'),
    rows        = 1L,
    schema_hash = 'sha256:stub'
  ),
  'data-apis/stub_latest.meta.json',
  auto_unbox = TRUE,
  pretty     = TRUE
)
cat('wrote stub\n')
"@
Get-Item data-apis\stub_latest.parquet, data-apis\stub_latest.meta.json | Select-Object Name, Length
```

Expected: `wrote stub` then a two-row table showing both files exist with non-zero size (parquet ~1–2 KB, json ~150 B).

- [ ] **Step 2: Stage**

Run (PowerShell):
```powershell
git add data-apis/stub_latest.parquet data-apis/stub_latest.meta.json
```

---

## Task 9: Create theme assets and wire into `_quarto.yml`

**Files:**
- Create: `assets/style.scss`
- Create: `assets/header.html`
- Modify: `_quarto.yml`

- [ ] **Step 1: Create `assets/` directory**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
New-Item -ItemType Directory -Force -Path assets | Out-Null
```

- [ ] **Step 2: Write `assets/header.html`**

Create `assets/header.html`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap">
```

- [ ] **Step 3: Write `assets/style.scss`**

Create `assets/style.scss`:

```scss
/*-- scss:defaults --*/
// Override bootswatch font with Inter.
$font-family-sans-serif: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !default;
$font-family-base: $font-family-sans-serif !default;
$headings-font-weight: 700 !default;

/*-- scss:rules --*/
// Plot/table containers blend with page bg in both light and dark modes
// (avoids a white rectangle on the dark theme around ggiraph SVGs).
.cell-output-display > img,
.cell-output-display > .girafe,
.cell-output-display > .dataTables_wrapper {
  background: transparent;
}

// Tighter navbar — Quarto's default has more vertical air than we need.
.navbar {
  padding-top: 0.25rem;
  padding-bottom: 0.25rem;
}

// Make freshness callouts slightly less loud than Quarto's defaults.
.callout.callout-tip       { border-left-color: #1a7f37 !important; background: #f0fdf4; }
.callout.callout-warning   { border-left-color: #bf8700 !important; background: #fffaeb; }
.callout.callout-important { border-left-color: #cf222e !important; background: #fef2f2; }
```

- [ ] **Step 4: Replace `_quarto.yml` with the themed version**

Replace the entire contents of `_quarto.yml` with:

```yaml
project:
  type: website
  output-dir: _site
  render:
    - "*.qmd"
    - "trackers/*.qmd"
  resources:
    - "assets/**"
    - "pic.png"

website:
  title: "Michal Ovádek"
  site-url: "https://michalovadek.github.io"
  open-graph: true
  navbar:
    left:
      - href: home.qmd
        text: Home

format:
  html:
    theme:
      light: [zephyr, assets/style.scss]
      dark:  [darkly, assets/style.scss]
    include-in-header: assets/header.html
    toc: false
    smooth-scroll: true

execute:
  freeze: auto
```

- [ ] **Step 5: Verify the YAML parses**

Run (Bash, uses uv for PyYAML):
```bash
cd "C:/Users/uctqova/Documents/github/michalovadek.github.io" && \
  uv run --with pyyaml python -c "import yaml; d=yaml.safe_load(open('_quarto.yml')); print('theme.light:', d['format']['html']['theme']['light']); print('include-in-header:', d['format']['html']['include-in-header'])"
```

Expected:
```
theme.light: ['zephyr', 'assets/style.scss']
include-in-header: assets/header.html
```

- [ ] **Step 6: Stage**

Run (PowerShell):
```powershell
git add assets _quarto.yml
```

---

## Task 10: Rewrite `home.qmd` to exercise the full plumbing

**Files:**
- Modify: `home.qmd`

- [ ] **Step 1: Replace `home.qmd` with the plumbing-test version**

Replace the entire contents of `home.qmd` with:

````markdown
---
title: "Michal Ovádek"
---

```{r setup, include=FALSE}
suppressPackageStartupMessages({
  library(ggplot2)
  library(ggiraph)
  library(here)
})
source(here::here("R", "theme.R"))
source(here::here("R", "freshness.R"))
source(here::here("R", "table.R"))
register_ggiraph_defaults()
```

Quarto site under construction (see `AGENTS.md`). The static landing page
at `index.html` is still the live site at https://michalovadek.github.io.

This `home.qmd` exists as a plumbing test: it exercises every shared helper
end-to-end so we catch wiring breakage in CI before any real tracker page
depends on the same layers.

## Freshness badge

```{r freshness-demo, results='asis', echo=FALSE}
fd <- read_with_freshness("stub")
freshness_badge(fd$meta)
```

## ggplot + ggiraph

```{r plot-demo, echo=FALSE, fig.height=3.2, fig.width=7}
df <- data.frame(
  category = factor(c("alpha","beta","gamma","delta"), levels = c("alpha","beta","gamma","delta")),
  value    = c(12, 19, 7, 23)
)
p <- ggplot(df, aes(x = category, y = value, fill = category,
                    tooltip = paste0(category, ": ", value),
                    data_id = category)) +
  geom_col_interactive() +
  scale_fill_manual(values = mo_palette$categorical[1:4], guide = "none") +
  labs(title = "Theme + ggiraph smoke test", x = NULL, y = "value") +
  theme_mo()
girafe(ggobj = p, width_svg = 7, height_svg = 3.2)
```

## DT table

```{r table-demo, echo=FALSE}
dt_mo(head(mtcars, 8))
```

## gt table

```{r gt-demo, echo=FALSE}
gt_mo(head(iris, 5))
```
````

- [ ] **Step 2: Stage**

Run (PowerShell):
```powershell
git add home.qmd
```

---

## Task 11: Local smoke render

**Files:**
- Generated: `_site/home.html` (gitignored)

- [ ] **Step 1: Render**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
quarto render 2>&1 | Select-String -Pattern "Output created|Error|ERROR|WARN" | Out-String
```

Expected: at minimum `Output created: _site\home.html`. Any line containing `Error` or `ERROR` is a stop-the-line: surface it to the owner, do not proceed. A line containing `WARN` is informational (Quarto warnings about cache or fonts are tolerated).

- [ ] **Step 2: Verify the rendered HTML contains the expected markers**

Run (PowerShell):
```powershell
$html = Get-Content -Raw _site/home.html
$checks = @(
  @{ name = "freshness badge"; pattern = "Data as of" },
  @{ name = "Inter font link"; pattern = "fonts.googleapis.com/css2\?family=Inter" },
  @{ name = "ggiraph svg"; pattern = "girafe|<svg" },
  @{ name = "DT table"; pattern = "dataTables_wrapper|datatable" },
  @{ name = "gt table"; pattern = "gt_table|<table[^>]*class=" }
)
foreach ($c in $checks) {
  if ($html -match $c.pattern) { "PASS: $($c.name)" } else { "FAIL: $($c.name) (pattern '$($c.pattern)' not found)" }
}
```

Expected: 5 PASS lines, 0 FAIL lines. If any FAIL, stop and report — likely the helper file failed to source.

- [ ] **Step 3: Verify static HTML at repo root is still intact**

Run (PowerShell):
```powershell
Get-Item index.html, publications.html, tools.html, style.css | Select-Object Name, Length
```

Expected: all four files present, exact sizes `index.html 2590`, `publications.html 9751`, `tools.html 2033`, `style.css 2414`. Any mismatch means Quarto clobbered something — restore from git (`git checkout -- <file>`) and investigate why.

- [ ] **Step 4: Verify `_site/` is still gitignored**

Run (PowerShell):
```powershell
git status --short | Select-String -Pattern "_site|\.quarto|_freeze"
```

Expected: no output. If anything matches, update `.gitignore` before proceeding.

---

## Task 12: Update AGENTS.md (resolve TBD theme/palette item)

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Replace the "Pick bootswatch base + final colour palette" open question**

Find this line in `AGENTS.md` §10 (Open questions / TODOs):

```
- [ ] Pick bootswatch base + final colour palette (currently undecided).
```

Replace it with:

```
- [x] Bootswatch base + colour palette decided 2026-05-23: zephyr (light) /
      darkly (dark), Inter font, Okabe-Ito categorical, viridis sequential,
      BrBG diverging. See `docs/specs/2026-05-23-shared-infra-design.md` §3.1.
```

- [ ] **Step 2: Stage**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
git add AGENTS.md
```

---

## Task 13: Final pre-commit sanity check

**Files:** (no changes — verification only)

- [ ] **Step 1: Inventory of what will be in commit 2**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
git status
```

Expected: staged changes (Changes to be committed) include AT LEAST:
- `new file: .Renviron`
- `modified: AGENTS.md`
- `modified: _quarto.yml`
- `modified: home.qmd`
- `new file: R/_fetch_template.R`
- `new file: R/freshness.R`
- `new file: R/table.R`
- `new file: R/theme.R`
- `new file: assets/header.html`
- `new file: assets/style.scss`
- `new file: data-apis/_README.md`
- `new file: data-apis/stub_latest.meta.json`
- `new file: data-apis/stub_latest.parquet`
- `new file: data-external/_README.md`
- `new file: data-manual/_README.md`
- `modified: renv.lock`
- `modified: renv/activate.R` (auto-updated by `renv::install("renv")` so the bootloader matches the new pinned renv version in the lockfile — they MUST be committed together)
- `modified: docs/plans/2026-05-23-shared-infra-phase.md` (mid-execution amendments to Tasks 2 + 13 — see commit message; this entry is meta but harmless)

No untracked files. No deleted files. No `_site/`, `.venv/`, `renv/library/`, `.quarto/` anywhere.

- [ ] **Step 2: Make sure no large files are accidentally staged**

Run (PowerShell):
```powershell
git diff --cached --name-only | ForEach-Object { if (Test-Path $_) { $i = Get-Item $_; [pscustomobject]@{ File = $_; KB = [math]::Round($i.Length/1KB, 1) } } } | Sort-Object KB -Descending | Select-Object -First 10
```

Expected: largest staged file is `renv.lock` (probably <500 KB). If any file is >5000 KB (5 MB) something is wrong; stop and investigate.

---

## Task 14: Make commit 2 and push to GitHub

**Files:**
- Commit: 1
- Push: 1

- [ ] **Step 1: Make commit 2**

Run (PowerShell):
```powershell
cd "C:\Users\uctqova\Documents\github\michalovadek.github.io"
git commit -m @'
Add shared R helpers, theme, and data folder skeleton

Builds the shared infrastructure that every future tracker page will use:

- R/ helpers (flat scripts, file-per-concern):
  - theme.R: theme_mo(), mo_palette (Okabe-Ito + viridis + BrBG),
    register_ggiraph_defaults()
  - freshness.R: read_with_freshness(stem), freshness_badge(meta)
  - table.R: dt_mo(), gt_mo()
  - _fetch_template.R: copy-paste starting point. Underscore-prefixed so
    the CI workflow's R/fetch_*.R glob skips it.

- Visual theme: zephyr (light) + darkly (dark) with manual navbar toggle,
  Inter font via Google Fonts, assets/style.scss for the ~25 lines of
  custom rules (font override, navbar tightening, callout styling).

- Data folder skeleton: data-manual/, data-apis/, data-external/ each
  with a _README.md locking the convention in code. Includes a one-row
  stub snapshot in data-apis/ so home.qmd can demo the freshness badge
  end-to-end without depending on a real fetcher.

- .Renviron disables the renv sandbox to kill the 16s-per-Rscript tax
  on Windows.

- renv.lock expanded with the baseline bundle every tracker needs
  (ggplot2, ggiraph, DT, gt, here, jsonlite, arrow, viridis,
  RColorBrewer, digest, htmltools, yaml).

home.qmd rewritten as a plumbing test: it sources every helper and
renders a freshness badge, ggiraph plot, DT, and gt — so the first CI
push catches any wiring breakage before tracker ports start.

Spec: docs/specs/2026-05-23-shared-infra-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
git log --oneline -2
```

Expected: commit succeeds; `git log --oneline -2` shows both commits in order (commit 2 newest).

- [ ] **Step 2: Confirm remote and current branch**

Run (PowerShell):
```powershell
git remote -v
git branch --show-current
```

Expected: `origin` points at `https://github.com/michalovadek/michalovadek.github.io` (fetch + push); current branch is `main`.

- [ ] **Step 3: Push (this is the moment CI first sees the new workflow)**

Run (PowerShell):
```powershell
git push origin main
```

Expected: push succeeds, ends with `main -> main`. If push rejected because remote has commits we don't have locally (the original repo history), do NOT `--force`; surface to the owner.

- [ ] **Step 4: Observe the first CI run**

Open in browser: `https://github.com/michalovadek/michalovadek.github.io/actions`

Watch the most recent "Render and deploy" run. Expected outcome:
- `render` job: succeeds in 5–10 min (cold renv cache means installing the baseline R packages from RSPM).
- `deploy` job: SKIPPED (the `if: false` gate).
- Live site at https://michalovadek.github.io is UNCHANGED (still the static HTML).

If the `render` job fails:
- Most likely culprit: `arrow` needs `libarrow-dev` system lib on Linux. Fix is to insert before `Restore renv` in `.github/workflows/render.yml`:
  ```yaml
  - uses: r-lib/actions/setup-r-dependencies@v2
    with:
      packages: any::renv
  ```
  Commit and push that one change separately.
- Second-likeliest: a Quarto warning escalates to error for a missing extension or font. Look at the failed step's log, identify the file, fix locally, re-push.
- Do NOT modify the cron schedule or the `if: false` gate as a "fix" — these are intentional.

---

## Done criteria

The phase is complete when ALL of:
- Two commits exist on local `main` and on `origin/main`.
- The most recent GH Actions "Render and deploy" run shows `render: success`, `deploy: skipped`.
- The live site at https://michalovadek.github.io is unchanged (still the static HTML).
- `home.qmd` rendered locally shows: intro, freshness badge with "Data as of …", a ggiraph bar plot (Okabe-Ito colours), a DT table, a gt table.
- AGENTS.md §10 no longer has the bootswatch/palette open question.
- `_site/`, `.quarto/`, `_freeze/`, `renv/library/`, `.venv/` are absent from `git ls-files` output.

When all six bullets above are true, hand back to the owner for the next phase (tracker ports — likely `eufinance` first per the spec's updated recommendation).
