# eu-vetoes Port + Site Go-Live — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `old/tracker.qmd` (the standalone eu-veto-tracker) into `trackers/eu-vetoes.qmd` on the euverse shared infra AND flip the deploy gate so the same commit takes the site live at https://michalovadek.github.io/euverse/.

**Architecture:** Three small shared-infra additions (a 29-entry `mo_palette$ms_flags` named vector in `R/theme.R`, a ~14-line `manual_meta(path)` helper in `R/freshness.R`, an `if: false` → `if: true` flip in `.github/workflows/render.yml`'s deploy job) + one new tracker page (`trackers/eu-vetoes.qmd`) consuming the existing `data-manual/ms-vetoes.csv`. No new R deps. ONE commit covers everything; the same push triggers both render and deploy.

**Tech Stack:** R 4.4.3 (renv 1.2.3, existing lockfile unchanged); Quarto 1.7.17; existing renv pin set (ggplot2, ggiraph, dplyr, DT, htmltools, here, arrow, jsonlite, viridis, RColorBrewer, etc.). No new packages.

**Spec reference:** `docs/specs/2026-05-24-eu-vetoes-port-design.md`

**Conventions for this plan:**
- Working directory throughout: `C:\Users\uctqova\Documents\github\euverse`. Each command re-asserts via `Set-Location`.
- Rscript not on PATH; use `& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe"`.
- "Verify" steps run a command and compare to "Expected". Discrepancy = stop and surface.
- Commits happen only in Task 6 (single-commit plan).
- PowerShell `@"..."@` here-string-into-`Rscript -e` is unreliable on this Windows host. If verification output goes silent, write to a temp `.R` file, `Rscript` it, delete.
- The OWNER has confirmed they've set GitHub Pages Source = "GitHub Actions" before this plan runs. If you discover otherwise mid-plan, surface — the deploy step would fail.

---

## Task 1: Shared-infra additions (`mo_palette$ms_flags` + `manual_meta()` + deploy gate flip)

**Files:**
- Modify: `R/theme.R` (expand `mo_palette` with `ms_flags`)
- Modify: `R/freshness.R` (append `manual_meta()` function)
- Modify: `.github/workflows/render.yml` (replace the `deploy` block + remove obsolete cut-over comment block)

- [ ] **Step 1: Add `mo_palette$ms_flags` to `R/theme.R`**

Use the `Edit` tool. Replace this exact text in `R/theme.R`:

```r
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
```

With:

```r
mo_palette <- list(
  # Okabe-Ito 8-colour categorical palette (colourblind-safe).
  categorical = c(
    "#E69F00", "#56B4E9", "#009E73", "#F0E442",
    "#0072B2", "#D55E00", "#CC79A7", "#999999"
  ),
  # Sequential and diverging are functions of n so callers can request the
  # exact length they need (rather than slicing a fixed vector).
  sequential = function(n) viridis::viridis(n),
  diverging  = RColorBrewer::brewer.pal(11, "BrBG"),
  # EU Member State flag colours, keyed by ISO-2 country code. Used for
  # country-coloured plots where cardinality (28+ states) exceeds the
  # categorical palette. Lifted from the standalone eu-veto-tracker's
  # hand-picked vector with one collision resolved (HU was #DC143C, the
  # same as PL — HU is now a distinguishable green #436F4D drawn from the
  # Hungarian flag's middle stripe). EA is a neutral grey for aggregate
  # reference lines.
  ms_flags = c(
    AT = "#ED2939", BE = "#FAE042", BG = "#00966E", HR = "#FF0000",
    CY = "#DFAF2C", CZ = "#11457E", DK = "#D1001F", EE = "#0072CE",
    FI = "#003580", FR = "#0055A4", DE = "#FFCE00", GR = "#0D5EAF",
    HU = "#436F4D", IE = "#169B62", IT = "#009246", LV = "#990000",
    LT = "#FDB913", LU = "#00A1DE", MT = "#C8102E", NL = "#FF4F00",
    PL = "#DC143C", PT = "#FF0000", RO = "#002B7F", SK = "#0B4EA2",
    SI = "#009B77", ES = "#AA151B", SE = "#FECC00", GB = "#00247D",
    EA = "#666666"
  )
)
```

- [ ] **Step 2: Verify `ms_flags` loaded correctly**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "source('R/theme.R'); stopifnot(length(mo_palette[['ms_flags']]) == 29L); stopifnot(mo_palette[['ms_flags']][['HU']] == '#436F4D'); stopifnot(mo_palette[['ms_flags']][['PL']] == '#DC143C'); stopifnot(length(mo_palette[['categorical']]) == 8L); cat('ms_flags OK\n')"
```

Expected: `ms_flags OK`. Confirms 29 entries (28 MS + EA), HU/PL collision resolved, original Okabe-Ito palette unchanged.

- [ ] **Step 3: Add `manual_meta()` helper to `R/freshness.R`**

Use the `Edit` tool. Append at end of file AFTER the existing `freshness_badge_combined()` function. Begin with a single blank line:

```r

manual_meta <- function(path, source_label = basename(path)) {
  # Build a freshness-badge-shaped meta from a hand-curated file's mtime.
  # Pages that consume manual data use this in place of the
  # read_with_freshness() contract (no fetcher exists for manual files).
  # Caller fills in $rows after counting (since the file might be filtered
  # before plotting).
  if (!file.exists(path)) {
    stop(sprintf("Manual data file not found: %s", path), call. = FALSE)
  }
  mtime <- file.info(path)$mtime
  list(
    source     = source_label,
    fetched_at = format(mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    rows       = NA_integer_
  )
}
```

- [ ] **Step 4: Verify `manual_meta()` works end-to-end**

Save the following to a temp `tmp_check_manual.R`, run, delete:

```r
suppressPackageStartupMessages(library(htmltools))
source("R/freshness.R")

# Real file — ms-vetoes.csv must exist (shipped with the migration commit).
veto_csv <- file.path("data-manual", "ms-vetoes.csv")
stopifnot(file.exists(veto_csv))

m <- manual_meta(veto_csv, source_label = "ms-vetoes")
stopifnot(
  m$source == "ms-vetoes",
  nzchar(m$fetched_at),
  is.na(m$rows)
)
m$rows <- 42L
badge <- freshness_badge(m)
stopifnot(
  grepl("Data as of", as.character(badge)),
  grepl("ms-vetoes", as.character(badge)),
  grepl("42 rows", as.character(badge))
)

# Non-existent file should error.
err <- tryCatch(manual_meta("nonexistent.csv"), error = identity)
stopifnot(inherits(err, "simpleError"),
          grepl("not found", conditionMessage(err)))

cat("manual_meta OK\n")
```

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" tmp_check_manual.R
Remove-Item tmp_check_manual.R
```

Expected: `manual_meta OK`.

- [ ] **Step 5: Remove obsolete cut-over comment block AND flip deploy gate in `render.yml`**

Use the `Edit` tool ONCE to replace the entire 22-line cut-over comment + deploy stub with the new live version. Find this exact block (lines ~103–122):

```yaml
  # ----------------------------------------------------------------------------
  # DEPLOY — currently INERT (`if: false`).
  #
  # Cut-over checklist before flipping `if: false` to `if: true`:
  #   1. GitHub repo Settings → Pages → Source → "GitHub Actions"
  #      (currently set to "Deploy from a branch / main / root").
  #   2. Rename `home.qmd` → `index.qmd` and delete the static
  #      `index.html`, `publications.html`, `tools.html`, `style.css` from
  #      the repo root in the same commit.
  #   3. Verify the artifact from a recent `render` job looks right
  #      (download from Actions UI).
  #   4. Change `if: false` below to `if: true` (or remove the line).
  #
  # Until cut-over, the workflow validates that the render pipeline is healthy
  # but does not change what's served at https://michalovadek.github.io.
  # ----------------------------------------------------------------------------
  deploy:
    needs: render
    if: false
    runs-on: ubuntu-latest
```

Replace with:

```yaml
  # ----------------------------------------------------------------------------
  # DEPLOY — active since 2026-05-24.
  # Precondition (one-time owner action, already done): GitHub repo Settings →
  # Pages → Source = "GitHub Actions" (NOT "Deploy from a branch"). Without
  # that toggle, this job fails with "no Pages deployment configured".
  # See docs/specs/2026-05-24-eu-vetoes-port-design.md §3.2.
  # ----------------------------------------------------------------------------
  deploy:
    needs: render
    runs-on: ubuntu-latest
```

(Removes the `if: false` line entirely — equivalent to `if: true` and cleaner.)

- [ ] **Step 6: Verify the workflow YAML still parses**

```bash
cd "C:/Users/uctqova/Documents/github/euverse" && \
  uv run --with pyyaml python -c "import yaml; d=yaml.safe_load(open('.github/workflows/render.yml')); deploy=d['jobs']['deploy']; print('deploy job keys:', list(deploy.keys())); print('has if:', 'if' in deploy)"
```

Expected:
```
deploy job keys: ['needs', 'runs-on', 'environment', 'steps']
has if: False
```

The `if` key is now ABSENT (which means GitHub Actions defaults to "always run when needs are satisfied" — exactly what we want).

- [ ] **Step 7: Stage all three files**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
git add R/theme.R R/freshness.R .github/workflows/render.yml
git status --short
```

Expected (subset): `M  R/theme.R`, `M  R/freshness.R`, `M  .github/workflows/render.yml`. HEAD unchanged at `9aab257`.

---

## Task 2: Create `trackers/eu-vetoes.qmd`

**Files:**
- Create: `trackers/eu-vetoes.qmd`

- [ ] **Step 1: Confirm `trackers/` directory exists**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
Test-Path trackers
```

Expected: `True` (created during the eufinance port).

- [ ] **Step 2: Create the page**

Use the `Write` tool to create `trackers/eu-vetoes.qmd` with this EXACT content (UTF-8 without BOM). The outer 4-backtick block boundaries are JUST for prompt display — the FILE uses 3-backtick R chunks throughout.

````markdown
---
title: "Tracking EU Member States' Vetoes"
subtitle: "Who and when blocks joint EU action"
toc: true
---

```{r setup, include=FALSE}
suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(ggiraph)
  library(here)
})
source(here::here("R", "theme.R"))
source(here::here("R", "freshness.R"))
source(here::here("R", "table.R"))
register_ggiraph_defaults()

# Load the manual data.
veto_csv <- here::here("data-manual", "ms-vetoes.csv")
veto_data <- read.csv(veto_csv, sep = ";", fileEncoding = "UTF-8-BOM") |>
  # Drop columns that are all-empty (legacy CSV trailing-comma artefact).
  select(where(~ !(all(is.na(.)) | all(. == "")))) |>
  filter(as.Date(date_veto) > as.Date("2011-01-01")) |>
  arrange(date_veto)

# Add IDs (matches old Rmd structure).
veto_data <- veto_data |>
  mutate(id_veto = row_number(), .before = 1) |>
  group_by(date_veto, issue, issue_country, source) |>
  mutate(id_issue = cur_group_id(), .after = 1) |>
  ungroup()

# Freshness meta from CSV mtime, with row count filled in after filter.
veto_meta <- manual_meta(
  veto_csv,
  source_label = "data-manual/ms-vetoes.csv (hand-curated)"
)
veto_meta$rows <- nrow(veto_data)

# Inline-prose stats.
start_date <- format(min(as.Date(veto_data$date_veto)), "%d %B %Y")
n_vetoes   <- nrow(veto_data)
n_states   <- length(unique(veto_data$ms_veto))
n_issues   <- max(veto_data$id_issue)
```

This page tracks all publicly reported instances of European Union Member
States vetoing joint action. A veto is understood as an instance of a
Member State blocking, temporarily or permanently, common EU action by
opposing a measure under a procedure requiring unanimous agreement of all
Member States.^[I count every reported instance of a veto being used, even
if the same or similar issue already attracted a veto in the past.]

Since `r start_date`, there have been `r n_vetoes` vetoes by `r n_states`
Member States across `r n_issues` issues.

```{r freshness, results='asis', echo=FALSE}
freshness_badge(veto_meta)
```

```{r vetoes-table, echo=FALSE}
veto_data |>
  arrange(desc(as.Date(date_veto))) |>
  transmute(
    Date    = as.Date(date_veto),
    Vetoer  = ms_veto,
    Issue   = issue,
    Country = ifelse(issue_country == "", "—", issue_country),
    Source  = sprintf('<a href="%s" target="_blank">link</a>', source)
  ) |>
  dt_mo(escape = FALSE)
```

# Vetoes by Member State

Hungary has been reported to have vetoed EU action more than any other
Member State in recent history. In contrast, quite a few Member States
have not had a single veto attributed to them. However, by relying on
reported vetoes only, this statistic likely underestimates the true
prevalence of vetoes. Another source of underestimation are long-standing
vetoes: certain issues might not even be put on the Council agenda — and
are therefore less likely to be reported — when one or several countries
had vetoed the policy in question in the past.^[An example here is the
opening of accession negotiations between the EU and (North) Macedonia,
which was blocked by Greece for over a decade until a dispute over the
country's name was resolved.]

```{r plot-by-ms, echo=FALSE, fig.height=4.5, fig.width=9}
df_a <- veto_data |>
  count(ms_veto) |>
  mutate(fill_hex = unname(mo_palette$ms_flags[ms_veto]))

p_a <- ggplot(df_a, aes(x = reorder(ms_veto, n), y = n,
                        fill = fill_hex,
                        tooltip = paste0(ms_veto, ": ", n, " vetoes"),
                        data_id = ms_veto)) +
  geom_col_interactive(show.legend = FALSE) +
  scale_fill_identity() +
  scale_y_continuous(n.breaks = 8, expand = c(0, 0.1)) +
  labs(x = NULL, y = "Total number of vetoes",
       title = "Number of vetoes by Member State") +
  theme_mo() +
  theme(panel.grid = element_blank(),
        panel.grid.major.y = element_line(colour = "grey95"),
        axis.text.x = element_text(face = "bold"))

girafe(ggobj = p_a, width_svg = 9, height_svg = 4.5)
```

# Vetoes over time

Reported vetoes have become more common over time.^[The date of the veto
is an approximation of when the negotiation was taking place rather than
when the veto was reported.] Some would argue this is a signal of
increasing polarization in the Council of the EU. But changes to the EU's
institutional system also play a role. Notably, the creation of the office
of the High Representative for Foreign and Security Affairs by the Lisbon
Treaty has generated more opportunities for Member States to veto joint
EU statements on foreign policy issues.

This is also a reminder that not all vetoes are the same — blocking a
legislative measure such as the harmonization of minimum corporate tax is
arguably much more consequential than the wording of a non-binding
declaration.

```{r plot-over-time, echo=FALSE, fig.height=6, fig.width=9}
df_b <- veto_data |>
  mutate(
    hex_color = unname(mo_palette$ms_flags[ms_veto]),
    tooltip   = paste0("By: ", ms_veto, "\n",
                       "On: ", format(as.Date(date_veto), "%d %B %Y"), "\n",
                       "Issue: ", issue)
  )

p_b <- ggplot(df_b, aes(x = as.Date(date_veto), y = id_veto)) +
  geom_vline(xintercept = as.Date(c("2014-12-01", "2019-12-01", "2024-12-01")),
             lty = 2, colour = "grey60") +
  annotate("text", label = "Juncker", angle = 90, size = 3, colour = "grey50",
           x = as.Date("2014-10-01"), y = -Inf, vjust = 0, hjust = 0) +
  annotate("text", label = "von der Leyen I", angle = 90, size = 3, colour = "grey50",
           x = as.Date("2019-10-01"), y = -Inf, vjust = 0, hjust = 0) +
  annotate("text", label = "von der Leyen II", angle = 90, size = 3, colour = "grey50",
           x = as.Date("2024-10-01"), y = -Inf, vjust = 0, hjust = 0) +
  geom_point_interactive(aes(colour = hex_color,
                             tooltip = tooltip,
                             data_id = id_veto),
                         alpha = 0.9) +
  scale_color_identity() +
  scale_x_date(date_breaks = "year", date_labels = "%Y") +
  scale_y_continuous(breaks = seq(0, n_vetoes, by = 5)) +
  theme_mo() +
  theme(axis.text.y = element_text(size = 6)) +
  labs(x = NULL, y = "Veto No",
       title = "Vetoes over time",
       caption = "Hover for more information about the veto")

girafe(ggobj = p_b, width_svg = 9, height_svg = 6)
```

When trying to interpret these data, one should be wary of the
possibility that differences over time and between Member States are to
some extent driven by how vetoes are communicated and reported.

Moreover, whether countries choose to exercise a veto power can also be a
function of other Member States' intentions to do the same. If Member
State A knows for certain that Member State B will veto a measure, it can
reap the 'benefit' of the failed action without contributing to it
(free-riding). The number of reported vetoes therefore understates the
true level of disagreement among Member States.

# Veto issues and third countries

We can also categorize the vetoes by what substantive issue they
concerned and — because vetoes are frequently about foreign affairs —
the third country in question. Multiple vetoes have related to progress
in negotiating the accession of a candidate country outside the EU. Not
all vetoes are directly linked to a third country; this is especially
true when it comes to internal policies such as taxation.

```{r plot-issues, echo=FALSE, fig.height=5, fig.width=9}
df_c <- veto_data |>
  mutate(issue_country = ifelse(issue_country == "", "No third country", issue_country)) |>
  count(issue, issue_country) |>
  mutate(sum = sum(n), .by = issue) |>
  mutate(
    tooltip = ifelse(issue_country == "No third country",
                     paste0(n, " vetoes concerning ", issue),
                     paste0(n, " vetoes concerning ", issue, " and ", issue_country)),
    id = seq_len(dplyr::n())
  )

p_c <- ggplot(df_c, aes(x = n, y = reorder(issue, sum))) +
  geom_col_interactive(aes(fill = issue_country,
                           tooltip = tooltip,
                           data_id = id),
                       show.legend = FALSE) +
  ggiraph::scale_fill_brewer_interactive(palette = "Paired", type = "qual") +
  scale_x_continuous(expand = c(0, 0.15)) +
  theme_mo() +
  theme(axis.text.y = element_text(hjust = 1)) +
  labs(x = NULL, y = NULL,
       title = "Veto issues and third countries",
       subtitle = "Number of times a veto related to an issue",
       caption = "Hover for information about the third country")

girafe(ggobj = p_c, width_svg = 9, height_svg = 5)
```

# Cite

Ovádek, M. *Tracking EU Member States' Vetoes*. Accessed
`r format(Sys.Date(), "%d %B %Y")`. Available at
<https://michalovadek.github.io/euverse/trackers/eu-vetoes.html>.
````

- [ ] **Step 3: Verify the qmd structure**

```powershell
$qmd = Get-Content -Raw trackers/eu-vetoes.qmd
$chunks = ([regex]'(?m)^```\{r ').Matches($qmd).Count
"r chunks: $chunks"
"file size: $((Get-Item trackers/eu-vetoes.qmd).Length) bytes"
```

Expected: `r chunks: 6` (setup, freshness, vetoes-table, plot-by-ms, plot-over-time, plot-issues). File size 7–10 KB.

- [ ] **Step 4: Stage**

```powershell
git add trackers/eu-vetoes.qmd
```

---

## Task 3: Update `_quarto.yml` navbar

**Files:**
- Modify: `_quarto.yml` (add second Trackers menu entry)

- [ ] **Step 1: Append EU Vetoes to the Trackers dropdown**

Use the `Edit` tool on `_quarto.yml`. Replace:

```yaml
      - text: Trackers
        menu:
          - href: trackers/eu-finance.qmd
            text: EU Finance
```

With:

```yaml
      - text: Trackers
        menu:
          - href: trackers/eu-finance.qmd
            text: EU Finance
          - href: trackers/eu-vetoes.qmd
            text: EU Vetoes
```

- [ ] **Step 2: Verify YAML parses with both entries**

```bash
cd "C:/Users/uctqova/Documents/github/euverse" && \
  uv run --with pyyaml python -c "import yaml; d=yaml.safe_load(open('_quarto.yml')); m=d['website']['navbar']['left'][1]['menu']; print('menu length:', len(m)); print('entries:', [(e['text'], e['href']) for e in m])"
```

Expected:
```
menu length: 2
entries: [('EU Finance', 'trackers/eu-finance.qmd'), ('EU Vetoes', 'trackers/eu-vetoes.qmd')]
```

- [ ] **Step 3: Stage**

```powershell
git add _quarto.yml
```

---

## Task 4: Local smoke render + verification

**Files:**
- Generated: `_site/trackers/eu-vetoes.html`, `_site/trackers/eu-finance.html`, `_site/home.html` (all gitignored)

- [ ] **Step 1: Render**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
quarto render 2>&1 | Select-String -Pattern "Output created|Error|ERROR|WARN" | Out-String
```

Expected: `Output created: _site\trackers\eu-vetoes.html` AT MINIMUM (home.html and eu-finance.html may be cached/skipped — Quarto's incremental build). Any `Error`/`ERROR` is stop-the-line. Cleanup error at end (`os error 32`) is the benign Windows quirk.

- [ ] **Step 2: Verify the new tracker page has expected markers**

```powershell
$html = Get-Content -Raw _site/trackers/eu-vetoes.html
$checks = @(
  @{ name = "page title";                pattern = "Tracking EU Member States' Vetoes" },
  @{ name = "freshness badge";           pattern = "Data as of" },
  @{ name = "intro footnote anchor";     pattern = "fnref|footnote-ref" },
  @{ name = "Section: by MS";            pattern = "Vetoes by Member State" },
  @{ name = "Section: over time";        pattern = "Vetoes over time" },
  @{ name = "Section: issues";           pattern = "Veto issues and third countries" },
  @{ name = "DT table wrapper";          pattern = "dataTables_wrapper|datatable" },
  @{ name = "DT external link in Source"; pattern = 'target="_blank"' },
  @{ name = "ggiraph SVG present";       pattern = "<svg" },
  @{ name = "HU flag colour #436F4D";    pattern = "#436F4D" },
  @{ name = "DE flag colour #FFCE00";    pattern = "#FFCE00" },
  @{ name = "PL flag colour #DC143C";    pattern = "#DC143C" },
  @{ name = "Juncker term marker";       pattern = "Juncker" },
  @{ name = "vdL II term marker";        pattern = "von der Leyen II" },
  @{ name = "Citation URL";              pattern = "michalovadek.github.io/euverse/trackers/eu-vetoes.html" }
)
foreach ($c in $checks) {
  if ($html -match $c.pattern) { "PASS: $($c.name)" } else { "FAIL: $($c.name)" }
}
```

Expected: 15 PASS lines, 0 FAIL. If any FAIL, stop and report which marker + 5 surrounding lines of the HTML to diagnose.

- [ ] **Step 3: Verify the eu-finance page still renders (no regression)**

```powershell
if (Test-Path _site/trackers/eu-finance.html) {
  $eufin = Get-Content -Raw _site/trackers/eu-finance.html
  if ($eufin -match "Borrowing and Yields") { "PASS: eu-finance still intact" } else { "FAIL: eu-finance broken" }
} else {
  "INFO: _site/trackers/eu-finance.html not present (cache skip)"
}
```

Expected: `PASS: eu-finance still intact` OR `INFO: ...cache skip` (if Quarto's incremental build skipped re-rendering an unchanged input — fine). If FAIL appears, a regression in the eufinance render needs investigation.

- [ ] **Step 4: Verify the home.html navbar shows both tracker links**

```powershell
if (Test-Path _site/home.html) {
  $home = Get-Content -Raw _site/home.html
  if ($home -match 'href="\.?\/?trackers/eu-finance\.html"') { "PASS: navbar -> EU Finance" } else { "FAIL: navbar -> EU Finance" }
  if ($home -match 'href="\.?\/?trackers/eu-vetoes\.html"') { "PASS: navbar -> EU Vetoes" } else { "FAIL: navbar -> EU Vetoes" }
} else {
  # Force a re-render if home.html was cache-skipped — the navbar update
  # needs to land for the live site to show both entries.
  quarto render home.qmd 2>&1 | Select-String -Pattern "Output created|Error" | Out-String
  $home = Get-Content -Raw _site/home.html
  if ($home -match 'href="\.?\/?trackers/eu-vetoes\.html"') { "PASS: navbar -> EU Vetoes (after re-render)" } else { "FAIL: navbar still missing EU Vetoes link" }
}
```

Expected: both PASS (with or without the re-render).

- [ ] **Step 5: No build artifacts in git**

```powershell
git status --short | Select-String -Pattern "_site|\.quarto|_freeze"
```

Expected: no output.

---

## Task 5: Update AGENTS.md migration map

**Files:**
- Modify: `AGENTS.md` (mark eu-vetoes row done)

- [ ] **Step 1: Edit the migration-map row**

Use the `Edit` tool on `AGENTS.md`. Find:

```
| `old/tracker.qmd`                                  | Quarto + Action    | `trackers/eu-vetoes.qmd`  | `data-manual/ms-vetoes.csv` (already here) |
```

Replace with:

```
| `old/tracker.qmd` ✅ ported 2026-05-24             | Quarto + Action    | `trackers/eu-vetoes.qmd`  | `data-manual/ms-vetoes.csv` (already here) |
```

(`✅` is U+2705.)

- [ ] **Step 2: Verify**

```powershell
Select-String -Path AGENTS.md -Pattern "tracker\.qmd.*ported 2026-05-24" | Out-String
```

Expected: one matching line.

- [ ] **Step 3: Stage**

```powershell
git add AGENTS.md
```

---

## Task 6: Final pre-commit sanity + commit + push

**Files:**
- Commit: 1
- Push: 1

- [ ] **Step 1: Inventory of what will be in the commit**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
git status
```

Expected `Changes to be committed` includes ALL OF:
- `modified:   .github/workflows/render.yml`
- `modified:   AGENTS.md`
- `modified:   R/freshness.R`
- `modified:   R/theme.R`
- `modified:   _quarto.yml`
- `new file:   trackers/eu-vetoes.qmd`

PLUS untracked spec/plan docs (stage them next).

- [ ] **Step 2: Stage the spec + plan docs**

```powershell
git add docs/specs/2026-05-24-eu-vetoes-port-design.md docs/plans/2026-05-24-eu-vetoes-port.md
git status --short
```

Expected: those two `A` entries appear. Working tree otherwise clean.

- [ ] **Step 3: Largest-files check**

```powershell
git diff --cached --name-only | ForEach-Object { if (Test-Path $_) { $i = Get-Item $_; [pscustomobject]@{ File = $_; KB = [math]::Round($i.Length/1KB, 1) } } } | Sort-Object KB -Descending | Select-Object -First 8
```

Expected: largest staged file is the plan doc (~30 KB) or the spec (~20 KB). Nothing > 100 KB.

- [ ] **Step 4: Write commit message to temp file**

Use the `Write` tool to create `.git_commit_msg.tmp` at the repo root with this exact content:

```
Port eu-vetoes tracker and go live with site

Second tracker port: data-manual/ms-vetoes.csv (already in the repo from
the migration commit) gets a tracker page at trackers/eu-vetoes.qmd.
This commit also flips the deploy gate so the next workflow run
publishes the site at https://michalovadek.github.io/euverse/.

Shared-infra additions:
- R/theme.R: mo_palette gains a 29-entry ms_flags named vector keyed by
  ISO-2 country code (lifted from the old standalone tracker, with the
  HU/PL #DC143C collision resolved by giving HU a distinguishable green).
  Reusable for any future country-coloured page.
- R/freshness.R: new manual_meta(path, source_label) helper builds a
  freshness-badge-shaped meta from a hand-curated file's mtime. Pages
  that consume manual data use this in place of read_with_freshness().
- .github/workflows/render.yml: deploy job no longer gated `if: false`.
  Precondition met by owner: GitHub repo Settings → Pages → Source =
  "GitHub Actions" (one-time toggle).

trackers/eu-vetoes.qmd:
- Reads data-manual/ms-vetoes.csv (semicolon-delimited, UTF-8 BOM),
  filters to date_veto > 2011-01-01, adds id_veto and id_issue.
- Combined: freshness badge (from CSV mtime) + interactive DT table
  (sorted desc by date, default pagination, search, CSV/Excel export,
  link column rendered as <a> with target=_blank) + 3 ggiraph plots:
  vetoes-by-MS bar (flag-coloured), vetoes-over-time scatter with three
  Commission-term markers (Juncker, von der Leyen I & II) and per-veto
  tooltips, and an issues × third-country horizontal stacked bar using
  ColorBrewer "Paired" (a documented exception to the Okabe-Ito palette
  because third_country cardinality can exceed 8).
- Inline prose preserved from the old Rmd (long intro footnote on
  veto-counting methodology, Macedonia footnote, three interpretive
  paragraphs between plots).
- Citation links to the canonical site URL.

_quarto.yml: navbar Trackers dropdown now has both EU Finance and EU
Vetoes entries.

AGENTS.md migration map: ✅ marked for eu-vetoes row. Two of four
tracker ports now done (eufinance + eu-vetoes); next: eu-court and
eu-law (both heavier eurlex SPARQL).

Local smoke render verified: 15 page markers pass on
_site/trackers/eu-vetoes.html, both navbar links present in home.html,
eufinance render unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

- [ ] **Step 5: Commit and delete the temp file**

```powershell
git commit -F .git_commit_msg.tmp 2>&1 | Out-String
Remove-Item .git_commit_msg.tmp
git log --oneline -3
```

Expected: commit succeeds; `git log --oneline -3` shows the new commit at HEAD, then `9aab257` (eufinance), then `50aeb80` (migration).

- [ ] **Step 6: Push**

```powershell
git push origin main 2>&1 | Out-String
```

Expected: `9aab257..<new-sha>  main -> main`. If REJECTED, do NOT `--force`; report BLOCKED.

---

## Task 7: Watch first deploy + verify live site

This task is observation-only — no code changes. Report findings back so the controller can decide whether the phase is complete or needs follow-up fixes.

**Files:** (none)

- [ ] **Step 1: Note the CI URL for the owner**

Report (verbatim, on its own line, no quotes):

```
https://github.com/michalovadek/euverse/actions
```

Look at the most recent "Render and deploy" run triggered by the push from Task 6.

- [ ] **Step 2: Observe the `render` job**

Expected: passes in 2–4 minutes (warm renv cache from the eufinance commit). The 4 existing fetchers (`fetch_ecb_*`, `fetch_eurostat_teimf050`) re-run; any individual fetcher failure emits `::warning::` but the build still succeeds because the previous snapshots are committed.

- [ ] **Step 3: Observe the `deploy` job**

This is the new behaviour — previously skipped, now runs. Expected: passes in ~30 s, using `actions/deploy-pages@v4` against the artifact uploaded by `render`. Output includes a deployment URL like `https://michalovadek.github.io/euverse/` (case-sensitive; will be the canonical site URL).

If `deploy` FAILS with "no GitHub Pages site found" or "Pages must be enabled": the owner missed the one-time browser action. Surface back with the recommendation: GitHub repo Settings → Pages → Source = "GitHub Actions".

If `deploy` FAILS with permission/`id-token` errors: re-check that `permissions:` in `render.yml` includes `pages: write` and `id-token: write` (they should, per the migration commit).

- [ ] **Step 4: Visit the live site**

Open in browser: https://michalovadek.github.io/euverse/

Expected:
- Home page renders (the plumbing-test `home.qmd` content for now — real landing content is a separate later task).
- Navbar shows: Home | Trackers ▾ (EU Finance, EU Vetoes).
- Click "EU Finance" — page loads with 3 sections + combined freshness badge.
- Click "EU Vetoes" — page loads with intro, freshness badge, DT table (paginated), 3 ggiraph plots, citation footer.

If the URL gives a 404 immediately after the workflow succeeds: GitHub Pages can take a minute or two to propagate after first publish. Re-check in 2–3 minutes.

- [ ] **Step 5: Report findings**

Status:
- `render` job: success / failure (with reason if failure)
- `deploy` job: success / failure (with reason if failure)
- Live home page: loads / 404 / other
- Live eu-finance page: loads with 3 sections / loads broken / 404
- Live eu-vetoes page: loads with all elements / loads broken / 404
- Any unexpected warnings or issues

---

## Done criteria

This phase is complete when ALL of:
- Single new commit on local `main` and `origin/main`.
- GH Actions: most recent run shows both `render` AND `deploy` as success.
- https://michalovadek.github.io/euverse/ resolves (no 404).
- https://michalovadek.github.io/euverse/trackers/eu-vetoes.html shows 3 plots + DT table.
- https://michalovadek.github.io/euverse/trackers/eu-finance.html still works.
- AGENTS.md migration map shows ✅ for eu-vetoes.
- `_site/`, `.quarto/`, `_freeze/`, `renv/library/`, `.venv/` are absent from `git ls-files`.

When all six bullets are true, two of four tracker ports are done. Next phase: port `eu-court` (heavier — uses the `eurlex` R package's SPARQL queries against Eur-Lex).
