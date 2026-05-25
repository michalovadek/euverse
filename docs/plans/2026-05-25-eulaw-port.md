# eu-law Port — Implementation Plan (Plan B of the combined spec)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the eu-law tracker (`old/eulawstats.Rmd`) onto the euverse shared infra. Reuses `data-final/eu_member_states.parquet` from Plan A; adds 4 new sector-3 SPARQL fetchers + one new page. Completes the four-tracker consolidation.

**Architecture:** Four per-upstream-dataset fetchers (`fetch_eurlex_acts`, `fetch_eurlex_acts_force`, `fetch_eurlex_proposals`, `fetch_eurlex_lbs`) writing source-named tidy parquets to `data-apis/`. One new page (`trackers/eu-law.qmd`) joining the 4 snapshots + the shared `eu_member_states` master. No new R packages (all already pinned by Plan A). All charts use `theme_mo()` + `register_ggiraph_defaults()`; tables use `dt_mo()`; act-type fills use `mo_palette$categorical[1:4]` (R/L/D/H — Regulations / Directives / Decisions / Recommendations).

**Tech Stack:** Same as Plan A (R 4.4.3, renv pin set already includes `eurlex`, `modelsummary`, `purrr`, `tidyr`, `forcats`). No additions.

**Spec reference:** `docs/specs/2026-05-25-eucourt-eulaw-port-design.md` (this is Plan B).

**Plan A status precondition:** Plan A must have shipped (`data-final/eu_member_states.parquet` exists in the working tree and is committed). This plan reads from it.

**Conventions:**
- Working dir: `C:\Users\uctqova\Documents\github\euverse`.
- Rscript at `& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe"`.
- Commits happen only in Task 6 (single-commit plan).
- For PowerShell here-string → Rscript -e flakiness, use temp `.R` files.
- SPARQL queries can be slow (especially `lbs` — ~1M rows). Allow 5-15 min per heavy fetcher.

---

## Task 1: `fetch_eurlex_acts` (sector 3 acts + proposals link + top-50 titles)

**Files:**
- Create: `R/fetch_eurlex_acts.R`
- Generated: `data-apis/eurlex_acts_latest.parquet` + meta

- [ ] **Step 1: Write fetcher**

Use the `Write` tool. EXACT content:

```r
# fetch_eurlex_acts.R
# Source: Eur-Lex SPARQL sector 3 (legal acts) with proposal link.
# Includes recent-title fetches for the top-50 newest acts so the
# eu-law page's "most recent legislation" table works from the snapshot.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr); library(stringr); library(purrr)
})

src     <- "eurlex_acts"
out_dir <- here::here("data-apis")

df <- tryCatch({
  raw <- elx_make_query("any", sector = 3,
                        include_date = TRUE,
                        include_proposal = TRUE) |>
    elx_run_query() |>
    select(-any_of("work"))

  # Acts only: drop bogus dates, dedup by celex.
  acts <- raw |>
    filter(!is.na(celex), !date %in% c("1003-03-03")) |>
    distinct(celex, .keep_all = TRUE) |>
    mutate(
      type = case_when(
        str_sub(celex, 6, 6) == "R" ~ "Regulation",
        str_sub(celex, 6, 6) == "L" ~ "Directive",
        str_sub(celex, 6, 6) == "D" ~ "Decision",
        str_sub(celex, 6, 6) == "H" ~ "Recommendation",
        TRUE                        ~ "Other"
      ),
      year = as.integer(str_sub(celex, 2, 5))
    )

  # Title-fetch for top-50 newest acts of the 4 main types.
  top50 <- acts |>
    filter(type %in% c("Regulation", "Directive", "Decision", "Recommendation")) |>
    arrange(desc(as.Date(date)), desc(celex)) |>
    slice(1:50) |>
    mutate(recent_title = map_chr(
      str_c("http://publications.europa.eu/resource/celex/", celex),
      possibly(eurlex::elx_fetch_data, otherwise = NA_character_),
      "title"
    )) |>
    mutate(recent_title = str_squish(recent_title)) |>
    select(celex, recent_title)

  acts |>
    left_join(top50, by = "celex") |>
    as.data.frame()

}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

if (!is.data.frame(df) || nrow(df) < 50000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
if (!all(c("celex", "date", "type", "year", "recent_title") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

data_tmp <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(df, data_tmp, compression = "zstd")
jsonlite::write_json(
  list(source = src,
       fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       rows = nrow(df),
       schema_hash = digest::digest(names(df), algo = "sha256")),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE)
file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
```

- [ ] **Step 2: Run** (3–8 min)

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" R/fetch_eurlex_acts.R
```

Expected: final line `Wrote eurlex_acts latest snapshot: <N> rows.` (N ~300K-400K).

- [ ] **Step 3: Verify**

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "df <- arrow::read_parquet('data-apis/eurlex_acts_latest.parquet'); cat('rows:', nrow(df), 'cols:', paste(names(df), collapse=','), '\n'); print(sort(table(df$type), decreasing=TRUE)); cat('top50 with titles:', sum(!is.na(df$recent_title)), '\n')"
```

Expected: rows ~300K+, type table with R/L/D/H, ≥45 titles filled.

- [ ] **Step 4: Stage**: `git add R/fetch_eurlex_acts.R data-apis/eurlex_acts_latest.parquet data-apis/eurlex_acts_latest.meta.json`

---

## Task 2: `fetch_eurlex_acts_force` (in-force status)

**Files:** Create `R/fetch_eurlex_acts_force.R`; generated `data-apis/eurlex_acts_force_latest.{parquet,meta.json}`

- [ ] **Step 1: Write fetcher**

```r
# fetch_eurlex_acts_force.R
# Source: Eur-Lex SPARQL sector 3 with force status + date_force.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr); library(stringr)
})

src     <- "eurlex_acts_force"
out_dir <- here::here("data-apis")

df <- tryCatch({
  raw <- elx_make_query("any", sector = 3,
                        include_force = TRUE,
                        include_date_force = TRUE) |>
    elx_run_query() |>
    select(-any_of("work")) |>
    rename(date_force = dateforce) |>
    arrange(celex, date_force) |>
    distinct(celex, .keep_all = TRUE) |>
    tidyr::drop_na()

  raw |>
    filter(date_force >= "1952-01-01" & date_force <= as.character(Sys.Date())) |>
    as.data.frame()

}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

if (!is.data.frame(df) || nrow(df) < 50000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
if (!all(c("celex", "force", "date_force") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

data_tmp <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(df, data_tmp, compression = "zstd")
jsonlite::write_json(
  list(source = src,
       fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       rows = nrow(df),
       schema_hash = digest::digest(names(df), algo = "sha256")),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE)
file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
```

- [ ] **Step 2: Run** (2–5 min)

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" R/fetch_eurlex_acts_force.R
```

- [ ] **Step 3: Verify**

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "df <- arrow::read_parquet('data-apis/eurlex_acts_force_latest.parquet'); cat('rows:', nrow(df), 'cols:', paste(names(df), collapse=','), '\n'); print(table(df$force))"
```

Expected: rows 100K+, force = "true"/"false" both present.

- [ ] **Step 4: Stage**

---

## Task 3: `fetch_eurlex_proposals` (Commission proposals)

**Files:** Create `R/fetch_eurlex_proposals.R`; generated `data-apis/eurlex_proposals_latest.{parquet,meta.json}`

- [ ] **Step 1: Write fetcher**

```r
# fetch_eurlex_proposals.R
# Source: Eur-Lex SPARQL "proposal" type query.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr)
})

src     <- "eurlex_proposals"
out_dir <- here::here("data-apis")

df <- tryCatch({
  elx_make_query("proposal", include_date = TRUE) |>
    elx_run_query() |>
    select(-any_of(c("work", "type"))) |>
    rename(date_proposal = date) |>
    filter(!is.na(celex), !is.na(date_proposal)) |>
    distinct(celex, .keep_all = TRUE) |>
    as.data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

if (!is.data.frame(df) || nrow(df) < 5000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
if (!all(c("celex", "date_proposal") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

data_tmp <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(df, data_tmp, compression = "zstd")
jsonlite::write_json(
  list(source = src,
       fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       rows = nrow(df),
       schema_hash = digest::digest(names(df), algo = "sha256")),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE)
file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
```

- [ ] **Step 2: Run** (1–3 min)

- [ ] **Step 3: Verify**

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "df <- arrow::read_parquet('data-apis/eurlex_proposals_latest.parquet'); cat('rows:', nrow(df), 'cols:', paste(names(df), collapse=','), '\ndate range:', min(df$date_proposal), 'to', max(df$date_proposal), '\n')"
```

Expected: rows 20K+; cols `celex,date_proposal`.

- [ ] **Step 4: Stage**

---

## Task 4: `fetch_eurlex_lbs` (legal bases — the heaviest, ~1M rows)

**Files:** Create `R/fetch_eurlex_lbs.R`; generated `data-apis/eurlex_lbs_latest.{parquet,meta.json}`

- [ ] **Step 1: Write fetcher**

```r
# fetch_eurlex_lbs.R
# Source: Eur-Lex SPARQL sector 3 with legal-basis pairs.
# Outputs ~700K-1M rows of (celex, lbcelex) pairs (raw - enrichment
# happens at render time since it's display-specific).

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr)
})

src     <- "eurlex_lbs"
out_dir <- here::here("data-apis")

df <- tryCatch({
  elx_make_query("any", sector = 3, include_lbs = TRUE) |>
    elx_run_query() |>
    select(-any_of(c("work", "lbs"))) |>
    filter(!is.na(celex), !is.na(lbcelex)) |>
    distinct(celex, lbcelex) |>
    as.data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

if (!is.data.frame(df) || nrow(df) < 100000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
if (!all(c("celex", "lbcelex") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

data_tmp <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(df, data_tmp, compression = "zstd")
jsonlite::write_json(
  list(source = src,
       fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
       rows = nrow(df),
       schema_hash = digest::digest(names(df), algo = "sha256")),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE)
file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
```

- [ ] **Step 2: Run** (5–10 min — heaviest)

If snapshot exceeds 50 MB, modify fetcher to keep only LBs cited ≥2 times (aggregation before writing). Report DONE_WITH_CONCERNS and we'll adjust.

- [ ] **Step 3: Verify**

```powershell
& "C:\Program Files\R\R-4.4.3\bin\Rscript.exe" -e "df <- arrow::read_parquet('data-apis/eurlex_lbs_latest.parquet'); cat('rows:', nrow(df), 'cols:', paste(names(df), collapse=','), '\ndistinct celex:', length(unique(df$celex)), '\ndistinct lbcelex:', length(unique(df$lbcelex)), '\n'); cat('size MB:', round(file.info('data-apis/eurlex_lbs_latest.parquet')$size / 1024^2, 1), '\n')"
```

Expected: rows 500K+; size under 50 MB.

- [ ] **Step 4: Stage**

---

## Task 5: Create `trackers/eu-law.qmd`

**Files:** Create `trackers/eu-law.qmd`

- [ ] **Step 1: Write the page**

Use `Write`. EXACT content:

````markdown
---
title: "Legislative Output of the European Union"
subtitle: "An automatically updated overview of the EU's legislative activity"
toc: true
---

```{r setup, include=FALSE}
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(forcats)
  library(ggplot2)
  library(ggiraph)
  library(here)
})
source(here::here("R", "theme.R"))
source(here::here("R", "freshness.R"))
source(here::here("R", "table.R"))
register_ggiraph_defaults()

# Load 4 snapshots + shared eu_member_states.
acts_meta       <- read_with_freshness("eurlex_acts")
force_meta      <- read_with_freshness("eurlex_acts_force")
proposals_meta  <- read_with_freshness("eurlex_proposals")
lbs_meta        <- read_with_freshness("eurlex_lbs")
ms              <- arrow::read_parquet(here::here("data-final", "eu_member_states.parquet"))

acts      <- acts_meta$data
acts_force<- force_meta$data
proposals <- proposals_meta$data
lbs       <- lbs_meta$data

today_d  <- Sys.Date()
year_now <- as.integer(format(today_d, "%Y"))

# Year x n_ms panel from shared master.
ms_count <- tibble(year = 1952:year_now) |>
  tidyr::crossing(ms) |>
  filter(year >= accession_year,
         is.na(exit_year) | year < exit_year) |>
  count(year, name = "n_ms")

# 4 main types.
acts_main <- acts |>
  filter(type %in% c("Regulation", "Directive", "Decision", "Recommendation"))

# Counts
n_regs <- sum(acts$type == "Regulation")
n_dirs <- sum(acts$type == "Directive")
n_decs <- sum(acts$type == "Decision")
n_recs <- sum(acts$type == "Recommendation")
```

The European Union is often criticised for having a heavy regulatory touch.
What is the reality? This page provides an automatically updated overview
of the EU's legislative output and efficiency, sourced from
[Eur-Lex](https://eur-lex.europa.eu/) via the
[eurlex](https://github.com/michalovadek/eurlex) R package.^[Any omissions
or mistakes in Eur-Lex carry through to the output shown here.]

As of `r format(today_d, "%d %B %Y")`, the EU and its predecessors have
produced **`r format(n_regs, big.mark = ',')`** regulations,
**`r format(n_dirs, big.mark = ',')`** directives,
**`r format(n_decs, big.mark = ',')`** decisions, and
**`r format(n_recs, big.mark = ',')`** recommendations.

```{r freshness, results='asis', echo=FALSE}
freshness_badge_combined(list(acts_meta$meta, force_meta$meta, proposals_meta$meta, lbs_meta$meta))
```

The following table shows the most recent legislation:

```{r recent-acts, echo=FALSE}
acts |>
  filter(!is.na(recent_title)) |>
  arrange(desc(as.Date(date)), desc(celex)) |>
  transmute(
    Date  = as.Date(date),
    Type  = type,
    CELEX = celex,
    Title = recent_title
  ) |>
  dt_mo()
```

# Number of acts over time

We start by looking at how the number of the four main legal acts changed
over the lifespan of the EU. The number adopted yearly is a parsimonious
proxy for the EU's regulatory tendencies.

```{r n-acts-time, echo=FALSE, fig.height=5, fig.width=9}
n_relevant <- acts_main |>
  count(year, type)

p_n_acts <- ggplot(n_relevant,
                   aes(x = year, y = n, fill = type,
                       tooltip = paste0(type, "s = ", n, " (", year, ")"),
                       data_id = paste0(type, year))) +
  geom_col_interactive(show.legend = FALSE) +
  scale_fill_manual(values = mo_palette$categorical[1:4]) +
  facet_wrap(~ type, scales = "free_y") +
  labs(x = NULL, y = "Number of acts",
       title = "Number of legal acts produced by the EU",
       subtitle = "Aggregated by year and type, by date of publication") +
  theme_mo() +
  theme(strip.text = element_text(hjust = 0, face = "bold"))

girafe(ggobj = p_n_acts, width_svg = 9, height_svg = 5)
```

# Proportion of act types

Some types of acts, notably regulations, have been historically more common
than others. We can visualise the evolution of proportions directly.

```{r prop-time, echo=FALSE, fig.height=4, fig.width=9}
proptime <- expand.grid(year = min(n_relevant$year):max(n_relevant$year),
                        type = unique(n_relevant$type)) |>
  left_join(n_relevant, by = c("year", "type")) |>
  mutate(n = ifelse(is.na(n), 0L, n)) |>
  group_by(year) |>
  mutate(proportion = n / sum(n)) |>
  ungroup()

p_prop <- ggplot(proptime, aes(x = year, y = proportion, fill = type)) +
  geom_area() +
  geom_vline(xintercept = c(1960, 1980, 2000, 2020), lty = 2, colour = "grey70") +
  geom_hline(yintercept = 0.50, colour = "grey50", lty = 3) +
  scale_fill_manual(values = mo_palette$categorical[1:4]) +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0), labels = scales::percent) +
  labs(x = NULL, y = NULL,
       title = "Relative prevalence of legal acts",
       subtitle = "Proportion of each type of legal act in a given year",
       fill = NULL) +
  theme_mo()

p_prop
```

Although regulations used to dominate the EU's legislative output,
decisions — typically associated with administrative actions — are nowadays
almost equally prevalent.

# Year-on-year comparison

We can look at the extent to which monthly adoption rates this year differ
from last year.

```{r yoy, echo=FALSE, fig.height=4, fig.width=9}
last_two_years <- acts_main |>
  mutate(month_year = as.Date(str_replace(date, "[:digit:][:digit:]$", "01"))) |>
  mutate(year = as.integer(str_sub(date, 1, 4))) |>
  filter(year %in% c(year_now, year_now - 1)) |>
  count(month_year, type)

last_two_full <- expand.grid(month_year = unique(last_two_years$month_year),
                             type = unique(last_two_years$type)) |>
  left_join(last_two_years, by = c("month_year", "type")) |>
  mutate(n = ifelse(is.na(n), 0L, n))

yoy_diff <- last_two_full |>
  arrange(month_year) |>
  mutate(month = str_sub(month_year, 6, 7)) |>
  group_by(month, type) |>
  reframe(yoy_diff = diff(n))

p_yoy <- ggplot(yoy_diff,
                aes(x = month, y = yoy_diff, fill = type,
                    tooltip = paste0(type, ": ", yoy_diff, " (month ", month, ")"),
                    data_id = paste0(type, month))) +
  geom_col_interactive(show.legend = FALSE) +
  geom_hline(yintercept = 0, colour = "grey83") +
  facet_wrap(~ type, scales = "free_y") +
  scale_fill_manual(values = mo_palette$categorical[1:4]) +
  labs(x = "Month", y = "Year-on-year difference",
       title = "Monthly year-on-year comparison",
       subtitle = "Difference in acts adopted this year vs last year") +
  theme_mo() +
  theme(strip.text = element_text(hjust = 0, face = "bold"))

girafe(ggobj = p_yoy, width_svg = 9, height_svg = 4)
```

# Acts in force

Not all legal acts remain in force indefinitely. According to Eur-Lex, the
EU has **`r format(sum(acts_force$force == 'true'), big.mark = ',')`** acts
in force at the moment.

```{r in-force, echo=FALSE, fig.height=4, fig.width=9}
in_force_clean <- acts_force |>
  filter(force == "true") |>
  mutate(days_in_force = as.integer(as.Date(today_d) - as.Date(date_force)),
         type = case_when(
           str_sub(celex, 6, 6) == "R" ~ "Regulation",
           str_sub(celex, 6, 6) == "L" ~ "Directive",
           str_sub(celex, 6, 6) == "D" ~ "Decision",
           str_sub(celex, 6, 6) == "H" ~ "Recommendation",
           TRUE                        ~ NA_character_
         )) |>
  filter(!is.na(type))

p_inforce <- ggplot(in_force_clean,
                    aes(x = days_in_force, fill = type)) +
  geom_histogram(bins = 100, show.legend = FALSE) +
  scale_fill_manual(values = mo_palette$categorical[1:4]) +
  facet_wrap(~ type, scales = "free") +
  labs(x = NULL, y = NULL,
       title = "How old are currently applicable legal acts?",
       subtitle = "Histogram of days since currently-applicable acts entered into force") +
  theme_mo() +
  theme(strip.text = element_text(hjust = 0, face = "bold"))

p_inforce
```

# Legislative efficiency

The image of the EU as an unwieldy bureaucracy is widespread. Let's use
Eur-Lex data to find out how long it normally takes to pass legislation.

```{r efficiency, echo=FALSE}
acts_days <- acts |>
  filter(!is.na(date), !is.na(proposal)) |>
  left_join(proposals, by = c("proposal" = "celex")) |>
  mutate(days = as.integer(as.Date(date) - as.Date(date_proposal))) |>
  filter(days > -1) |>
  group_by(celex) |>
  filter(days == max(days)) |>
  ungroup() |>
  distinct(celex, .keep_all = TRUE) |>
  arrange(date) |>
  mutate(year_adopted = as.integer(str_sub(date, 1, 4))) |>
  filter(year_adopted > 1985,
         type %in% c("Regulation", "Directive", "Decision"))

outliers <- acts_days |>
  group_by(type) |>
  mutate(mean = mean(days), coef = days / mean) |>
  filter(coef > 2.9) |>
  ungroup()
```

```{r outlier-scatter, echo=FALSE, fig.height=5, fig.width=9}
outliers_top <- outliers |>
  arrange(desc(days)) |>
  slice(1:50) |>
  left_join(acts |> select(celex, recent_title), by = "celex") |>
  mutate(tooltip = ifelse(is.na(recent_title),
                          paste0(celex, ": ", days, " days"),
                          str_squish(str_remove(recent_title, "\\(?Text with EEA relevance\\)?"))),
         data_id = celex)

p_outliers <- ggplot(outliers_top, aes(x = as.Date(date), y = days, fill = type, colour = type,
                                       tooltip = tooltip, data_id = data_id)) +
  geom_point_interactive(alpha = 0.6, size = 2.5, show.legend = TRUE) +
  geom_hline(yintercept = c(3650, 7300), lty = 2, colour = "grey75") +
  annotate("text", y = c(3650 + 110, 7300 + 110), x = as.Date("2012-01-01"),
           label = c("10 years", "20 years"),
           colour = "grey50", fontface = "italic") +
  scale_fill_manual(values = mo_palette$categorical[1:3]) +
  scale_colour_manual(values = mo_palette$categorical[1:3]) +
  labs(x = "Date of adoption", y = "Days to adoption",
       title = "The most slowly adopted acts in EU history",
       subtitle = "Number of days between initial Commission proposal and adoption",
       caption = "Hover over points for title",
       fill = NULL, colour = NULL) +
  theme_mo()

girafe(ggobj = p_outliers, width_svg = 9, height_svg = 5)
```

```{r efficiency-regression, echo=FALSE}
days_ms <- acts_days |>
  filter(!celex %in% outliers$celex) |>
  left_join(ms_count, by = c("year_adopted" = "year")) |>
  mutate(type = relevel(as.factor(type), ref = "Decision"))

m_ms      <- lm(days ~ n_ms, data = days_ms)
m_full    <- lm(days ~ n_ms + type, data = days_ms)

suppressPackageStartupMessages(library(modelsummary))
modelsummary::modelsummary(
  list("Baseline" = m_ms, "With type controls" = m_full),
  statistic  = "conf.int",
  conf_level = 0.95,
  stars      = TRUE,
  title      = "Linear model of legislative efficiency (days to adoption)"
)
```

Controlling for type, the model suggests that for every additional Member
State, the EU takes on average a few days longer to adopt a legal act.

# Legal bases

Each EU legal act has a _legal basis_ in the Treaties or in pre-existing
EU law. Looking at the most-invoked legal bases gives insight into EU
legislative activity.

```{r lbs-data, echo=FALSE}
lbs_clean <- lbs |>
  filter(!is.na(celex), !is.na(lbcelex)) |>
  mutate(
    delegated = ifelse(str_detect(lbcelex, "^1.*([:digit:]|[:punct:])$"), "primary", "delegated"),
    act_year  = as.integer(str_sub(celex, 2, 5)),
    lb_year   = as.integer(str_sub(lbcelex, 2, 5))
  )

most_common_lbs <- lbs_clean |>
  distinct(celex, lbcelex) |>
  count(lbcelex, sort = TRUE) |>
  slice(1:10) |>
  mutate(title = purrr::map_chr(
    str_c("http://publications.europa.eu/resource/celex/", lbcelex),
    purrr::possibly(eurlex::elx_fetch_data, otherwise = NA_character_),
    "title"
  )) |>
  mutate(title = str_squish(str_remove(title, "\\(?Text with EEA relevance\\)?")))

top_lb_name <- most_common_lbs$title[1]
top_lb_n    <- most_common_lbs$n[1]
```

The most-invoked legal basis historically is *`r if (is.na(top_lb_name)) most_common_lbs$lbcelex[1] else top_lb_name`*, used as a legal basis on **`r format(top_lb_n, big.mark = ',')`** occasions.

```{r lbs-table, echo=FALSE}
most_common_lbs |>
  transmute(
    Rank = row_number(),
    `Legal basis (CELEX)` = lbcelex,
    `Times invoked` = n,
    Title = ifelse(is.na(title), "(title unavailable)", title)
  ) |>
  dt_mo()
```

```{r lbs-deleg-time, echo=FALSE, fig.height=4, fig.width=9}
deleg_prop_time <- lbs_clean |>
  distinct(celex, .keep_all = TRUE) |>
  count(act_year, delegated) |>
  complete(act_year, delegated, fill = list(n = 0L)) |>
  group_by(act_year) |>
  mutate(prop = n / sum(n)) |>
  ungroup()

p_deleg <- ggplot(deleg_prop_time, aes(x = act_year, y = prop, fill = delegated)) +
  geom_area() +
  scale_fill_manual(values = mo_palette$categorical[c(1, 5)]) +
  geom_vline(xintercept = c(1960, 1980, 2000, 2020), lty = 2, colour = "grey70") +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(expand = c(0, 0), labels = scales::percent) +
  labs(x = NULL, y = NULL,
       title = "Relative prevalence of delegated and primary acts",
       subtitle = "Proportion of delegated vs primary acts in a given year",
       fill = NULL) +
  theme_mo()

p_deleg
```

Most legal acts adopted by the EU are delegated and implementing acts —
based on another piece of legislation rather than directly on a Treaty.

# About this page

Source data: 4 nightly snapshots of Eur-Lex sector 3 (acts, force,
proposals, legal bases) in
[`data-apis/`](https://github.com/michalovadek/euverse/tree/main/data-apis),
each produced by a fetcher under
[`R/`](https://github.com/michalovadek/euverse/tree/main/R) using the
[`eurlex`](https://github.com/michalovadek/eurlex) package. Member-State
counts come from
[`data-final/eu_member_states.parquet`](https://github.com/michalovadek/euverse/blob/main/data-final/eu_member_states.parquet).

The most recent act in the snapshot is from
**`r format(max(as.Date(acts$date), na.rm = TRUE), "%d %B %Y")`**.

Cite as: Ovádek, M. *Legislative Output of the European Union*. Accessed
`r format(Sys.Date(), "%d %B %Y")`. Available at
<https://michalovadek.github.io/euverse/trackers/eu-law.html>.
````

- [ ] **Step 2: Stage**: `git add trackers/eu-law.qmd`

---

## Task 6: Navbar + AGENTS.md + smoke render + commit + push

**Files:**
- Modify: `_quarto.yml` (add EU Law entry)
- Modify: `AGENTS.md` (mark eu-law row)
- Commit + push

- [ ] **Step 1: Add EU Law to navbar**

Use `Edit` on `_quarto.yml`. After the EU Court entry, add:

```yaml
          - href: trackers/eu-law.qmd
            text: EU Law
```

(The full Trackers menu should now have 4 entries: EU Finance, EU Vetoes, EU Court, EU Law.)

- [ ] **Step 2: Update AGENTS.md migration map**

Find:
```
| `old/eulawstats.Rmd`                               | Rmd + nightly cron | `trackers/eu-law.qmd`     | `data-apis/eurlex_*`         |
```

Replace with:
```
| `old/eulawstats.Rmd` ✅ ported 2026-05-25          | Rmd + nightly cron | `trackers/eu-law.qmd`     | `data-apis/eurlex_*`         |
```

- [ ] **Step 3: Local smoke render**

```powershell
Set-Location "C:\Users\uctqova\Documents\github\euverse"
quarto render 2>&1 | Select-String -Pattern "Output created|Error" | Out-String
```

Expected: `Output created: _site\trackers\eu-law.html`. Stop on Error.

- [ ] **Step 4: Verify rendered page**

```powershell
$html = Get-Content -Raw _site/trackers/eu-law.html
foreach ($p in @("Legislative Output", "Number of acts over time", "Acts in force", "Legal bases", "michalovadek.github.io/euverse/trackers/eu-law.html")) {
  if ($html -match [regex]::Escape($p)) { "PASS: $p" } else { "FAIL: $p" }
}
```

Expected: 5 PASS.

- [ ] **Step 5: Stage + commit + push**

```powershell
git add _quarto.yml AGENTS.md docs/specs/2026-05-25-eucourt-eulaw-port-design.md docs/plans/2026-05-25-eulaw-port.md trackers/eu-law.qmd
```

Write commit message to `.git_commit_msg.tmp`:

```
Port eu-law tracker (final of 4)

Final tracker port: legislative output of the EU. 4 new fetchers
(eurlex_acts with top-50 titles, eurlex_acts_force, eurlex_proposals,
eurlex_lbs) wrap distinct sector-3 SPARQL queries. Page consumes all
4 + the shared data-final/eu_member_states.parquet introduced by the
eu-court port (one master, three tracker consumers now).

trackers/eu-law.qmd: 6 sections — number-of-acts-over-time,
proportion-area-chart, YoY monthly diff, in-force histogram,
legislative-efficiency regression with outlier scatter, legal-bases
table + delegated-vs-primary area chart. All charts use theme_mo() and
the shared Okabe-Ito categorical palette[1:4]. modelsummary table for
the regression. LaTeX-equation block and modelplot dropped per spec.

_quarto.yml: navbar Trackers dropdown now has all 4 tracker pages.

AGENTS.md migration map: 4 of 4 tracker rows ✅ ported. Consolidation
complete; old standalone repos can now be archived.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Commit + push:

```powershell
git commit -F .git_commit_msg.tmp 2>&1 | Out-String
Remove-Item .git_commit_msg.tmp
git push origin main 2>&1 | Out-String
```

---

## Task 7: CI watch + live verify

- [ ] Poll CI for the new commit, verify live URLs return 200 with expected content (Legislative Output title, sections, citation URL).

```bash
for i in $(seq 1 25); do
  STATE=$(curl -s 'https://api.github.com/repos/michalovadek/euverse/actions/runs?per_page=1' | python -c "
import json,sys
r = json.load(sys.stdin)['workflow_runs'][0]
print(f\"{r['head_sha'][:7]}|{r['status']}|{r['conclusion']}\")")
  echo "[$(date +%H:%M:%S)] $STATE"
  STATUS=$(echo "$STATE" | cut -d'|' -f2)
  if [ "$STATUS" = "completed" ]; then break; fi
  sleep 30
done
curl -sI https://michalovadek.github.io/euverse/trackers/eu-law.html | head -1
```

---

## Done criteria

- One new commit pushed; CI render+deploy success.
- https://michalovadek.github.io/euverse/trackers/eu-law.html returns 200 with all 6 sections + tables.
- All 4 prior URLs (home, eu-finance, eu-vetoes, eu-court) still 200.
- AGENTS.md migration map fully ✅ for all 4 tracker rows.
- Navbar shows 4 tracker entries.
