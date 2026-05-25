# eu-court + eu-law port — design (combined spec, two plans)

**Date:** 2026-05-25
**Repo:** `euverse`
**Phase:** Final two tracker ports (eu-court from `old/eucourtstats.Rmd`,
eu-law from `old/eulawstats.Rmd`) + a shared `data-final/eu_member_states`
master table that both pages join against. Completes the four-tracker
consolidation (eu-finance + eu-vetoes already shipped).

## 1. Context & goal

Port the last two standalone Rmds onto the shared euverse infra. Both
were heavyweight, ~1000-line research-oriented documents using the
`eurlex` R package (owner-maintained) against Eur-Lex's SPARQL endpoint
+ the Curia case-list scraper.

The owner's "**pay attention to shared data resources**" instruction is
the load-bearing design input. The two pages don't share any *upstream*
queries (eu-court hits sector 6 / court decisions; eu-law hits sector 3
/ legal acts) but both need a year × Member-States panel for inline
stats and ms-aware regression. Rather than duplicate the hardcoded
`enlargements` / `accessions` / `ms_years` tables that the old Rmds
each carry, this phase introduces the canonical
`data-final/eu_member_states.parquet` master table — the textbook
example of the `data-final/` convention. Both pages consume it.

Owner-stated principles this phase reinforces:

1. **Shared cross-cutting data is `data-final/`** — not duplicated per
   page.
2. **One fetcher per upstream dataset** — six new fetchers across both
   pages (2 for eu-court, 4 for eu-law), each tied to one specific
   `elx_*` call. No bundling.
3. **Tidy at fetch time, present at render time** — fetchers do all
   the messy enrichment (procedure-class classification, missing-title
   fetches, court-code normalisation) so consuming pages stay clean.
4. **Free hand to adjust** beyond a pure port where doing so improves
   the output, while keeping the old code as the substantive basis.

## 2. Decisions (recap of brainstorming)

| Decision | Choice | Alternatives considered |
|---|---|---|
| Scope | One combined spec, two plans (eu-court first, then eu-law) | Two fully separate cycles; one combined plan |
| Shared resource | `data-final/eu_member_states.parquet`, built from `data-manual/eu-member-states.csv` | Hardcode in build script; pull from `eurostat::eu_countries` |
| Sequencing | eu-court FIRST (it builds the shared resource as part of its port), eu-law SECOND (reuses) | eu-law first; build resource as separate pre-commit |
| Tabsets (old `## Plot / ## Dataframe / ## Code`) | **Dropped entirely** | Keep all; keep on regression sections only |
| LaTeX equation block (`equatiomatic::extract_eq`) | Dropped on both regression sections | Keep |
| `modelplot` coefficient plots | Dropped on both regression sections | Keep |
| `modelsummary` regression tables | Kept (the meaningful output) | Drop both |
| Court palette (eu-court CJ/GC/CST) | 3 colours from `mo_palette$categorical` | Original `#fd014d/#122771/#3dcbb8` trio |
| Choropleth fill (eu-court prelim refs) | `mo_palette$sequential` (viridis) | Original `#8993b8 → #fe6794` pink gradient |
| eu-law act-type palette (R/L/D/H) | `mo_palette$categorical[1:4]` | Original `scale_fill_brewer("Spectral")` |
| Top-legal-basis prose (eu-law) | Simplified template (top LB + count) | Original conditional-text if-soup |
| Title-fetching strategy | Happens in fetcher (writes top-50 titles to snapshot) | At render time per page render |
| Per-plot `opts_*` ggiraph blocks | Removed — rely on `register_ggiraph_defaults()` | Keep |
| Choropleth dependency | `maps::map_data("world")` (already standard, no new deps) | `rnaturalearth` (nicer EU maps, extra dep) |

## 3. Architecture

### 3.1 Shared resource — `data-final/eu_member_states.{parquet,meta.json}`

**Source of truth**: `data-manual/eu-member-states.csv` — owner-editable,
one row per Member State (28 rows: EU27 + UK; the founding-6 each get
their own row with `accession_year = 1952` — the ECSC start year, which
matches both old Rmds' `enlargements` count panels).

Schema (4 columns):

| col | type | example |
|---|---|---|
| `country` | chr | "France", "United Kingdom" |
| `iso2` | chr (matches `mo_palette$ms_flags` keys) | "FR", "GB" |
| `accession_year` | int | 1958, 1973, 2004 |
| `exit_year` | int or NA | NA for current members, 2020 for UK |

**Build script**: `R/build_eu_member_states.R`. Reads the CSV, validates
(distinct ISO-2 codes, accession_year ≤ exit_year where both present,
all values plausible 1952–current), writes `data-final/eu_member_states.parquet`
(zstd-compressed) + `data-final/eu_member_states.meta.json` recording
`{built_at, source, builder_script, rows}` per the `data-final/`
convention. Idempotent.

**Consumption pattern** (both pages):
```r
ms <- arrow::read_parquet(here::here("data-final/eu_member_states.parquet"))
# year × country panel for years 1952..year_now where each country was a member
ms_panel <- tibble(year = 1952:year_now) |>
  cross_join(ms) |>
  filter(year >= accession_year, is.na(exit_year) | year < exit_year) |>
  arrange(year, country)
# year × n_ms summary (for eu-law's regression)
ms_count <- ms_panel |> count(year, name = "n_ms")
```

This single source replaces:
- `enlargements` + `accessions` hardcoded tables in `old/eucourtstats.Rmd`
- `ms_years` hardcoded data.frame in `old/eulawstats.Rmd`
- `ms_years_panel` derivation in eu-court

### 3.2 eu-court fetchers (2)

**`R/fetch_curia_cases.R`** → `data-apis/curia_cases_latest.parquet`

Source: `eurlex::elx_curia_list("all", parse = TRUE)` (Curia
scrape, NOT SPARQL).

Cleaning logic (lifted from `old/eucourtstats.Rmd` lines 169–222):
- Normalise `see_case` (insert hyphens in court codes), `case_id`
  (replace `-` with `/` in case-number/year separator).
- Filter `nchar(case_id) > 3` to drop short noise rows.
- Derive `court` from `case_id` pattern (CJ if `OPIN|C-|^[:digit:]|RULING`,
  GC if `T-`, CST if `F-`).
- Derive `see_case_court` and `appeal_court` same way for the
  cross-reference fields.
- Derive `case_status` from `case_info` patterns (Judgment / Order /
  Removal / Pending / Seizure order / Re-examination / Third-party
  proceedings / Transferred / Joined / Opinion).
- Extract `case_year` (4-digit from the `/YY` suffix, using `^[01234]
  → 20YY`, `^[56789] → 19YY`) and `case_number` (int).
- Extract `decision_year` (from ECLI) and `decision_date_str` (raw
  "DD Month YYYY" from case_info).

Output schema (10 columns):
```
case_id (chr), ecli (chr|NA), court (chr: CJ|GC|CST|NA),
see_case (chr|NA), see_case_court (chr|NA), appeal (chr|NA),
appeal_court (chr|NA), case_status (chr), case_year (int|NA),
case_number (int|NA), decision_year (int|NA),
decision_date_str (chr|NA), case_info (chr)
```

Expected rows: ~60–80K (all CJEU cases since 1953).

**`R/fetch_eurlex_court_decisions.R`** → `data-apis/eurlex_court_decisions_latest.parquet`

Source: `eurlex::elx_make_query(sector=6, include_date,
include_court_procedure, include_court_origin, include_original_language,
include_court_formation, include_judge_rapporteur, include_ecli)` +
`elx_run_query()`.

Cleaning logic (lifted from `old/eucourtstats.Rmd` lines 482–663):
- Parse CELEX into `clx_type` (2-char), `clx_num` (int), `clx_year`
  (int), `clx_court` (1-char: C/T/F).
- Derive `dec_type` from `clx_type` (Judgment / Order / Opinion).
- Drop rows where `dec_type` is NA OR celex contains `_INF`/`_SUM`.
- Split `courtprocedure` on " - " into `procedure` + `procedure_outcome`.
- Group by celex, aggregate multi-row joins via `str_c(unique(...), collapse="~~~")`
  for: decision, ecli, date, procedure, procedure_outcome, rapporteur,
  formation, language, origin.
- Resolve CO/CB duplicates (keep CO, drop CB where both present).
- **Missing-procedure title fetches**: for celexes with `is.na(procedure)`,
  `map_chr` over `eurlex::elx_fetch_data(...)` to get titles, then
  pattern-match titles to infer procedure (the big regex block from old
  Rmd lines 558–603). Same for `origin` field. Wrapped in `possibly()`
  so individual fetch failures return NA, not crash.
- Derive `procedure_class` (Preliminary rulings / Annulment procedures /
  Infringement proceedings / Staff cases / Other).
- Derive `court_long` from `clx_court`.
- Derive `formation_simple` (Grand Chamber / Full Court / Single Judge /
  Panel).
- Derive `decision_year` from `date`.
- Apply rapporteur typo corrections (the small fix block from old Rmd
  lines 632–638).
- Apply ~10 manual celex-specific corrections for origin + language
  (the block from old Rmd lines 641–664). These are static lookups; the
  fetcher hardcodes them.

Output schema (~13 cols):
```
celex (chr), clx_court (chr: C|T|F), clx_year (int), date (chr ISO),
decision (chr), procedure (chr|NA), procedure_class (chr),
procedure_outcome (chr|NA), formation_simple (chr|NA),
rapporteur (chr|NA), language (chr|NA), origin (chr|NA), ecli (chr|NA)
```

Expected rows: ~40–60K decisions. Plus ~50–200 title fetches
(takes 30–90 s).

### 3.3 eu-court page structure (`trackers/eu-court.qmd`)

YAML: `title: "Judicial Proceedings in the European Union"`,
`subtitle: "An automatically updated overview of the EU's judicial
activity"`, `toc: true`.

**Setup chunk** (`include=FALSE`): loads ggplot2 + ggiraph + dplyr +
forcats + tidyr + stringr + purrr + here; sources `R/theme.R`,
`R/freshness.R`, `R/table.R`; calls `register_ggiraph_defaults()`;
loads the 3 snapshots (`curia_cases`, `eurlex_court_decisions`, plus
`data-final/eu_member_states.parquet`).

**Body structure**:
1. **Intro paragraph** (preserved from old Rmd, lightly trimmed):
   one paragraph on the CJEU + its CJ/GC structure, one on the data
   source + caveats (eurlex package, Eur-Lex/Curia, IUROPA mention).
2. **Inline-stats sentence**: "As of `r format(today_d, ...)`, EU
   courts have delivered `r n_decisions` decisions in about `r n_cases`
   cases submitted since 1953. `r n_pending_cj` cases are pending
   before the Court of Justice and `r n_pending_gc` before the General
   Court."
3. **`dt_mo()` of 50 most recent CJ cases** (case_id + case_info,
   sorted desc by year+number).
4. **# Number of cases** — caseload bar chart by court_long, faceted
   vertically; mean line per facet; 3-colour court palette from
   `mo_palette$categorical[1:3]` mapped to CJ/GC/CST in fixed order;
   tooltip `N = {n} ({case_year})`. Prose between this section and the
   next preserves the old version's commentary.
5. **# Forecasting** — same OLS + Poisson regression on CJ caseload
   (lags 1/2/3 of CJ + lag 3 of GC, since 2001); plot the next year's
   prediction as a dashed-outline bar; `modelsummary` table after the
   plot. **No LaTeX equation, no modelplot**. Brief prose preserved.
6. **# Decisions** — 3 charts:
   (a) decisions-by-type-and-procedure faceted by procedure_class
       (Judgment vs Order fill, 2 Okabe-Ito colours);
   (b) formations stacked-percentage bar (Grand Chamber / Full Court /
       Panel / Single Judge, 4 Okabe-Ito colours);
   (c) top rapporteurs (top 20 by court) as horizontal stacked bars
       coloured by procedure_class.
7. **# Preliminary references** — 2 charts:
   (a) choropleth via `geom_map_interactive` against `maps::map_data("world")`,
       fill = n_refs per country, `scale_fill_gradientn(colours = mo_palette$sequential(9))`
       (viridis sequential);
   (b) per-country time series faceted small-multiples, points + smooth
       line, x = year, y = annual refs.
8. **# About this page** — source links (to GitHub + Eur-Lex + Curia),
   "Most recent case received: `r ...`" derived from the snapshot,
   citation prose with `Sys.Date()`.

**Inline-stat computations** (all from snapshots, no extra HTTP):
```r
n_cases     <- curia_cases |> filter(case_status != "Transferred") |> summarise(n = n_distinct(case_id)) |> pull(n)
n_decisions <- curia_cases |> summarise(n = n_distinct(ecli)) |> pull(n)
n_pending_cj <- curia_cases |> filter(case_status == "Pending", court == "CJ") |> n_distinct("case_id") # approx
n_pending_gc <- curia_cases |> filter(case_status == "Pending", court == "GC") |> n_distinct("case_id")
```

### 3.4 eu-law fetchers (4)

**`R/fetch_eurlex_acts.R`** → `data-apis/eurlex_acts_latest.parquet`

Source: `elx_make_query("any", sector=3, include_date=TRUE,
include_proposal=TRUE) |> elx_run_query()` + drop bogus date rows
(`!date %in% c("1003-03-03")`) + dedup by celex.

Plus: take the top-50 most recent acts (sorted desc by date), fetch
titles via `eurlex::elx_fetch_data(...)`, attach as `recent_title`
column (only populated for top-50; NA for others).

Output schema (~5 cols):
```
celex (chr), date (chr ISO), proposal (chr|NA),
type (chr: R|L|D|H|other, derived from celex[6]),
year (int from celex[2:5]),
recent_title (chr|NA, only top-50 newest)
```

Expected rows: ~300–400K. Size estimate: ~10–25 MB parquet (well under
GH limits; on the larger end of our existing snapshots).

**`R/fetch_eurlex_acts_force.R`** → `data-apis/eurlex_acts_force_latest.parquet`

Source: `elx_make_query("any", sector=3, include_force=TRUE,
include_date_force=TRUE)`. Rename `dateforce` → `date_force`, dedup by
celex, drop NA, filter `date_force` between 1952-01-01 and today.

Schema (3 cols): `celex (chr), force (chr: "true"/"false"), date_force (chr ISO)`.

Expected rows: ~150–250K.

**`R/fetch_eurlex_proposals.R`** → `data-apis/eurlex_proposals_latest.parquet`

Source: `elx_make_query("proposal", include_date=TRUE)`. Drop type/work
columns, rename date → date_proposal, dedup.

Schema (2 cols): `celex (chr), date_proposal (chr ISO)`.

Expected rows: ~30–50K.

**`R/fetch_eurlex_lbs.R`** → `data-apis/eurlex_lbs_latest.parquet`

Source: `elx_make_query("any", sector=3, include_lbs=TRUE)`. Drop
work/lbs columns; keep raw `celex` + `lbcelex` pairs (no enrichment —
that happens at render time since it's display-specific).

Schema (2 cols): `celex (chr), lbcelex (chr)`.

Expected rows: ~700K–1M. Size estimate: ~10–25 MB parquet.

### 3.5 eu-law page structure (`trackers/eu-law.qmd`)

YAML: `title: "Legislative Output of the European Union"`, subtitle,
`toc: true`.

Setup: loads the 4 acts snapshots + `data-final/eu_member_states.parquet`.

Body:
1. **Intro** (preserved from old Rmd) + inline counts of regs/dirs/decs/recs.
2. **`dt_mo()` of recent 50 acts** with titles (use the `recent_title`
   column from `eurlex_acts_latest`).
3. **# Number of acts over time** — bar chart faceted by type
   (R/L/D/H, 4 Okabe-Ito colours).
4. **# Proportion of act types** — stacked area chart over time.
5. **# Year-on-year comparison** — last 2 years monthly diffs, faceted
   by type.
6. **# Acts in force** — histogram of days-in-force by type, faceted.
7. **# Legislative efficiency** —
   (a) interactive scatter of all slow-act outliers with title tooltip,
       date on x, days-to-adoption on y, type as fill;
   (b) `modelsummary` table of the linear model: `days ~ n_ms + type`
       (n_ms joined in from `eu_member_states` via year_adopted).
   **No LaTeX equation, no modelplot.**
8. **# Legal bases** —
   (a) most-common-LBs table: top 10 with titles fetched at render time
       (rare top-10 fetches, ~10 HTTP calls per render);
   (b) delegated-vs-primary area chart over time.
9. **# About this page**.

**Top-LB prose simplification**: instead of the old code's
conditional-if soup (with `if str_detect(title, "Merger")...`),
just: "The most-invoked legal basis historically is _[r top_lb_name]_,
used as a legal basis on `r top_lb_n` occasions." One sentence,
template-driven, no brittle text branches.

### 3.6 Renv additions

New top-level packages required for both pages combined:
- `eurlex` (owner-maintained — all 6 new fetchers)
- `modelsummary` (regression tables on both pages)
- `maps` (choropleth on eu-court only)
- `forcats` (factor ordering)
- `purrr` (`map_chr` for title-fetches)
- `tidyr` (already transitive; making explicit)

NOT adding: `equatiomatic` (LaTeX — dropped), `gdtools` / `gfonts`
(replaced by Inter via SCSS), `rmarkdown` (Quarto handles directly),
`maps`-only deps like `mapproj` (only if `geom_map` complains —
unlikely with the world basemap).

### 3.7 Implementation principles for both pages

- Every chart uses `theme_mo()`.
- All tables use `dt_mo(...)`.
- All ggiraph interactivity (tooltip/data_id) but no per-plot `opts_*` —
  `register_ggiraph_defaults()` handles them site-wide.
- Combined-freshness badge (`freshness_badge_combined(list_of_metas)`)
  near top of each page reading the relevant snapshots.
- About-this-page section at the bottom with source links + a "most
  recent X recorded" prose line (per the eu-vetoes pattern, after the
  earlier UX feedback).

## 4. Sequencing — two plans

### Plan A — eu-court port + shared eu_member_states resource

Spec & plan headers: "Port eu-court tracker + build eu_member_states shared resource".

1. Renv: `renv::install(c("eurlex","modelsummary","maps","forcats","purrr","tidyr"))` + snapshot.
2. Author `data-manual/eu-member-states.csv` (29 rows, hand-curated).
3. Author + run `R/build_eu_member_states.R` → `data-final/eu_member_states.parquet` + meta.
4. Author + run `R/fetch_curia_cases.R` → snapshot.
5. Author + run `R/fetch_eurlex_court_decisions.R` → snapshot.
6. Author `trackers/eu-court.qmd` per §3.3.
7. Update `_quarto.yml` navbar (add EU Court entry).
8. Update AGENTS.md migration map (mark eu-court row done).
9. Local smoke render.
10. Commit + push.

### Plan B — eu-law port (reuses eu_member_states from Plan A)

Spec & plan headers: "Port eu-law tracker (reuses eu_member_states)".

1. Author + run 4 fetchers (`fetch_eurlex_acts`, `_acts_force`,
   `_proposals`, `_lbs`) → 4 snapshots.
2. Author `trackers/eu-law.qmd` per §3.5.
3. Update `_quarto.yml` navbar (add EU Law entry).
4. Update AGENTS.md migration map (mark eu-law row done).
5. Local smoke render.
6. Commit + push.

## 5. Commit plan

Two commits total, one per plan. Each is a single conceptual unit. CI
runs after each — both render and deploy live to the existing site.

## 6. CI expectations

After Plan A's commit:
- Renv install adds ~6 packages (cold ~1–2 min).
- 2 fetchers run sequentially in CI (~1 min for curia, ~3–5 min for
  the sector-6 SPARQL + missing-procedure title fetches).
- Quarto render produces `_site/trackers/eu-court.html` (~1–3 MB given
  the choropleth + many ggiraph SVGs).
- Deploy adds eu-court to the live navbar.

After Plan B's commit:
- No new renv packages (all already pinned by Plan A).
- 4 fetchers run sequentially (~30 s to 2 min each).
- Render produces `_site/trackers/eu-law.html`.

Most-likely failure modes:
- **`eurlex` SPARQL timeout** on one of the larger queries (sector 3
  acts can be slow). Mitigation: snapshots committed alongside fetchers
  in each commit, so first CI render reads from committed snapshots
  even if the fetcher emits `::warning::`.
- **`maps::map_data("world")` Linux-only quirk** with country-name
  normalisation (Czech Republic vs Czechia, UK vs United Kingdom).
  Already handled in old Rmd; fetcher (or page setup) replicates the
  same normalisation.
- **lbs snapshot size**: legal-bases data is ~1M rows. Parquet should
  compress to 10–25 MB. If it exceeds 50 MB, fetcher will need to
  aggregate (e.g., keep only LBs cited ≥2 times) before writing.

## 7. Success criteria

This phase is **done** when ALL of:
- Two commits on local `main` and `origin/main`.
- Both render + deploy CI jobs succeed for each commit.
- https://michalovadek.github.io/euverse/trackers/eu-court.html shows
  all 7 charts + DT + forecast model table + most-recent-cases table.
- https://michalovadek.github.io/euverse/trackers/eu-law.html shows all
  6 charts + 2 DT tables + regression model table.
- Existing pages (home, eu-finance, eu-vetoes) still load with
  no regressions.
- AGENTS.md migration map shows ✅ for both eu-court AND eu-law rows
  (final two rows of the 4-tracker map).
- All 4 tracker pages now appear in the Trackers navbar dropdown.

## 8. Out of scope / deferred

- A real landing page replacing the plumbing-test `home.qmd`.
- Removing `old/` historical Rmds (still kept as reference until all
  4 tracker pages have been "live for a week" with no regressions).
- Archiving the 4 standalone repos on GitHub (owner action, post-phase).
- Cross-tracker analytics (e.g., correlating CJEU caseload with
  regulatory output). Future phase if interesting.
- Citation network / EuroVoc enrichment on eu-court (the old Rmd had
  these as commented-out TODOs).
- A "Download data" button on each page leading to the underlying
  parquets. Future polish.

## 9. Open questions

None. All decisions locked. Implementation discretion (per owner) is
limited to (a) the specific Okabe-Ito indices for the court palette
[1:3], (b) prose flow + paragraph breaks (preserve intent, not exact
wording), (c) chunk options/sizing for legibility.
