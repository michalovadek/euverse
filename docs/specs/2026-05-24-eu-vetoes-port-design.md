# eu-vetoes port + site go-live — design

**Date:** 2026-05-24
**Repo:** `euverse`
**Phase:** Second tracker port (eu-vetoes from manual CSV). Also flips the
deploy gate so this commit takes the site LIVE at
https://michalovadek.github.io/euverse/.

## 1. Context & goal

Port the existing standalone `tracker.qmd` (now archived at
`old/tracker.qmd` from the eu-veto-tracker repo) into a tracker page on the
shared euverse infra. This is the second of four planned tracker ports;
the first (eufinance) shipped on 2026-05-24 (`9aab257`) and validated the
API-driven path. This port validates the **manual-data path**
(`data-manual/ms-vetoes.csv` already exists in the repo) and the
**shared-palette pattern** (extracting hand-picked colours from a tracker
into reusable `mo_palette` entries).

Additionally, this commit **takes the site live**: it flips `if: false`
→ `if: true` in `.github/workflows/render.yml`'s deploy job. The site
goes live at https://michalovadek.github.io/euverse/ on the first
successful workflow run after push. (Owner has already set GitHub Pages
Source → "GitHub Actions" in repo Settings, which is the precondition.)

Owner-stated principles this phase reinforces:

- **Manually-curated data is first-class** — `data-manual/` has its own
  freshness model (file mtime) rather than being shoehorned into the API
  fetcher pattern.
- **Country-flag colours are a SHARED palette** — not page-private — so
  every future country-coloured viz reuses the same mapping.
- **One commit = one tracker port + any infrastructure additions it
  requires** — same pattern as the eufinance commit.

## 2. Decisions (recap of brainstorming)

| Decision | Choice | Alternatives considered |
|---|---|---|
| Freshness signal for manual data | **File mtime via new `manual_meta(path)` helper** | Latest date_veto; both side-by-side; static prose |
| Country colour scheme | **Keep flag colours, extract to shared `mo_palette$ms_flags`** | Replace with qualitative 28-palette (Glasbey/Set3); drop colour entirely |
| Most-recent-vetoes table | **Single `dt_mo()` with default pagination (~10–15 visible), sorted desc by date** | Static 5-row `gt_mo`; static + full sortable; full sortable only |
| Cut-over | **Flip deploy gate in this commit; Pages source already set by owner** | Render-only push (defer cut-over); reversed sequence |
| Plot C palette exception | **ColorBrewer `Paired` for issue stacked bar** (12+ third-country categories exceeds Okabe-Ito's 8) | Force Okabe-Ito with recycling |
| Plot A enhancement | **Colour bars individually by flag colour** (uses the new shared palette) | Preserve old uniform-grey bars |

## 3. Architecture

### 3.1 Shared-infra additions

Two small additions, both in existing files:

**`R/theme.R` — `mo_palette$ms_flags`**

A named character vector with one ISO2 country code per entry, value =
hex colour drawn from each country's national flag. 28 entries (EU27 +
UK + the Euro Area aggregate code "EA" mapping to a neutral grey for
reference lines that need a label). Lifted verbatim from
`old/tracker.qmd:65-76` with one addition (a neutral entry for EA).

Sketch:

```r
mo_palette$ms_flags <- c(
  AT = "#ED2939", BE = "#FAE042", BG = "#00966E", HR = "#FF0000",
  CY = "#DFAF2C", CZ = "#11457E", DK = "#D1001F", EE = "#0072CE",
  FI = "#003580", FR = "#0055A4", DE = "#FFCE00", GR = "#0D5EAF",
  HU = "#436F4D", IE = "#169B62", IT = "#009246", LV = "#990000",
  LT = "#FDB913", LU = "#00A1DE", MT = "#C8102E", NL = "#FF4F00",
  PL = "#DC143C", PT = "#FF0000", RO = "#002B7F", SK = "#0B4EA2",
  SI = "#009B77", ES = "#AA151B", SE = "#FECC00", GB = "#00247D",
  EA = "#666666"
)
```

(Note: the old vector had HU = `#DC143C` and PL = `#DC143C` collide — the
real Hungarian flag has stripes including green; I'm using `#436F4D` for
HU to give a distinguishable colour and freeing `#DC143C` for PL. This is
the only material change from the original.)

**`R/freshness.R` — `manual_meta(path, source_label)`**

```r
manual_meta <- function(path, source_label = basename(path)) {
  # Build a freshness-badge-shaped meta from a hand-curated file's mtime.
  # Pages that consume manual data use this in place of the read_with_freshness()
  # contract (no fetcher exists for manual files).
  if (!file.exists(path)) {
    stop(sprintf("Manual data file not found: %s", path), call. = FALSE)
  }
  mtime <- file.info(path)$mtime
  list(
    source     = source_label,
    fetched_at = format(mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    rows       = NA_integer_  # caller overrides via veto_meta$rows <- nrow(...) after counting
  )
}
```

Returns a list shaped like the existing `read_with_freshness()$meta` so
the existing `freshness_badge()` consumes it without modification.
Caller pattern in the page:

```r
veto_meta <- manual_meta(
  here::here("data-manual","ms-vetoes.csv"),
  source_label = "data-manual/ms-vetoes.csv (hand-curated)"
)
veto_meta$rows <- nrow(veto_data)  # after filtering
```

### 3.2 Deploy gate flip

In `.github/workflows/render.yml`, the `deploy` job currently has:

```yaml
deploy:
  needs: render
  if: false
  ...
```

Change to:

```yaml
deploy:
  needs: render
  if: true   # (or remove the line entirely)
  ...
```

The "cut-over checklist" comment block above the job can be reduced to a
one-line "deploy active since 2026-05-24" historical note.

Preconditions for the deploy to actually publish (owner action, already
done before push per session message):

- GitHub repo Settings → Pages → Source = "GitHub Actions" (not "Deploy
  from a branch").

### 3.3 Page — `trackers/eu-vetoes.qmd`

YAML front matter:

```yaml
---
title: "Tracking EU Member States' Vetoes"
subtitle: "Who and when blocks joint EU action"
toc: true
---
```

Setup chunk (`include=FALSE`):

- Loads `dplyr`, `ggplot2`, `ggiraph`, `here` (no other libs needed —
  DT/gt come via the shared helpers' `pkg::` references).
- Sources `R/theme.R`, `R/freshness.R`, `R/table.R`.
- Calls `register_ggiraph_defaults()`.
- Reads `data-manual/ms-vetoes.csv` with `read.csv(..., sep=";",
  fileEncoding="UTF-8-BOM")` (the file has a BOM — visible as `0xEF 0xBB
  0xBF` at the head).
- Filters to `as.Date(date_veto) > as.Date("2011-01-01")` (matches old
  Rmd's data cutoff).
- Strips all-empty columns (matches old Rmd) and trims trailing-comma
  artefacts.
- Adds `id_veto` (sequential) and `id_issue` (group_by date_veto + issue +
  issue_country + source) — matches old Rmd.
- Builds `veto_meta` via `manual_meta(...)` + `nrow` override.
- Computes inline-prose variables: `start_date`, `n_vetoes`, `n_states`,
  `n_issues`.

Body, in order:

1. **Intro paragraph** (1–2 sentences from the old Rmd, lightly trimmed):
   "This page tracks all publicly reported instances of European Union
   Member States vetoing joint action. A veto is understood as an
   instance of a Member State blocking, temporarily or permanently,
   common EU action by opposing a measure under a procedure requiring
   unanimous agreement of all Member States."
2. **Inline-stats sentence** with the 4 computed variables: "Since
   `r start_date`, there have been `r n_vetoes` vetoes by `r n_states`
   Member States across `r n_issues` issues."
3. **Freshness badge chunk** (`results='asis', echo=FALSE`):
   `freshness_badge(veto_meta)`.
4. **Vetoes table chunk** (`echo=FALSE`):
   ```r
   veto_data |>
     arrange(desc(as.Date(date_veto))) |>
     transmute(
       Date    = as.Date(date_veto),
       Vetoer  = ms_veto,
       Issue   = issue,
       Country = ifelse(issue_country == "", "—", issue_country),
       Source  = sprintf('<a href="%s" target="_blank">link</a>', source)
     ) |>
     dt_mo(escape = FALSE)   # need escape=FALSE for the rendered <a> tag
   ```
   Sorted desc by date. Default `dt_mo()` page length 15. DT's pagination
   + search + CSV/Excel export buttons give the "browse all via clicks"
   UX the owner described.
5. **`# Vetoes by Member State` section** with one short prose paragraph
   (preserved from old Rmd) + Plot A:
   ```r
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
6. **`# Vetoes over time` section** with prose (~2 short paragraphs from
   old Rmd) + Plot B:
   ```r
   df_b <- veto_data |>
     mutate(
       hex_color = unname(mo_palette$ms_flags[ms_veto]),
       tooltip   = paste0("By: ", ms_veto, "\n",
                          "On: ", format(as.Date(date_veto), "%d %B %Y"), "\n",
                          "Issue: ", issue)
     )

   p_b <- ggplot(df_b, aes(x = as.Date(date_veto), y = id_veto)) +
     geom_vline(xintercept = as.Date(c("2014-12-01","2019-12-01","2024-12-01")),
                lty = 2, colour = "grey60") +
     annotate("text", label = "Juncker", angle = 90, size = 3, colour = "grey50",
              x = as.Date("2014-10-01"), y = -Inf, vjust = 0, hjust = 0) +
     annotate("text", label = "von der Leyen I", angle = 90, size = 3, colour = "grey50",
              x = as.Date("2019-10-01"), y = -Inf, vjust = 0, hjust = 0) +
     annotate("text", label = "von der Leyen II", angle = 90, size = 3, colour = "grey50",
              x = as.Date("2024-10-01"), y = -Inf, vjust = 0, hjust = 0) +
     geom_point_interactive(aes(colour = hex_color, tooltip = tooltip, data_id = id_veto),
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
7. **`# Veto issues and third countries` section** with prose
   (~2 sentences from old Rmd) + Plot C:
   ```r
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
     geom_col_interactive(aes(fill = issue_country, tooltip = tooltip, data_id = id),
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
   Note the documented exception to Okabe-Ito: Plot C uses ColorBrewer
   `Paired` because issue_country can have 12+ distinct values (Russia,
   Ukraine, Belarus, North Macedonia, Israel, China, Turkey, Cuba, …)
   which Okabe-Ito's 8 colours can't disambiguate without recycling.
8. **# Cite section** with an inline-R date:
   ```
   Ovádek, M. *Tracking EU Member States' Vetoes*. Accessed
   `r format(Sys.Date(), "%d %B %Y")`. Available at
   <https://michalovadek.github.io/euverse/trackers/eu-vetoes.html>.
   ```

### 3.4 `_quarto.yml` navbar

Append a second menu entry to the existing Trackers dropdown:

```yaml
- text: Trackers
  menu:
    - href: trackers/eu-finance.qmd
      text: EU Finance
    - href: trackers/eu-vetoes.qmd     # NEW
      text: EU Vetoes
```

### 3.5 AGENTS.md migration map

Mark the eu-vetoes row done:

```
| `old/tracker.qmd` ✅ ported 2026-05-24             | Quarto + Action    | `trackers/eu-vetoes.qmd`  | `data-manual/ms-vetoes.csv` (already here) |
```

## 4. Sequencing — work order in this phase

1. Add `mo_palette$ms_flags` (28-element named vector + EA entry) to `R/theme.R`.
2. Add `manual_meta(path, source_label)` helper to `R/freshness.R`.
3. Flip `if: false` → `if: true` in `.github/workflows/render.yml`'s deploy job + tidy the surrounding comment block.
4. Create `trackers/eu-vetoes.qmd` per §3.3.
5. Update `_quarto.yml` navbar to add EU Vetoes entry under Trackers.
6. Update AGENTS.md migration map row for eu-vetoes.
7. Local `quarto render`; verify the new page renders + the table paginates + the 3 plots show + the freshness badge shows a recent mtime.
8. ONE commit covering everything above.
9. Push to `origin/main`.
10. Watch the workflow at https://github.com/michalovadek/euverse/actions — both `render` and `deploy` jobs should run; deploy publishes to GitHub Pages.
11. Verify the live site at https://michalovadek.github.io/euverse/ shows the new tracker.

## 5. Commit plan

ONE commit. Subject names both halves: "Port eu-vetoes tracker and go live with site". Body lists the new file, the helper additions, the gate flip, the navbar entry, and the AGENTS.md mark.

## 6. CI expectations

- `render` job: warm renv cache from the eufinance commit (~2 min). No
  new R packages needed (all deps already pinned). The 4 existing
  fetchers re-run as part of the workflow; they should all succeed
  (already verified yesterday). `quarto render` produces a `_site/` with
  the home page + 2 tracker pages.
- `deploy` job: now runs. Takes the `_site/` artifact, calls
  `actions/deploy-pages@v4`. Takes ~30 s. Publishes to
  https://michalovadek.github.io/euverse/.

Most-likely failure modes:
- **Pages source still on "Deploy from a branch"**: deploy step fails
  with "no Pages deployment configured". Owner has confirmed Pages source
  was switched before push — should not trigger.
- **One of the 4 fetchers fails** (e.g., Eurostat API hiccup): emits
  `::warning::`, build continues, page reads from the committed
  snapshot. Site still publishes.

## 7. Success criteria

This phase is **done** when ALL of:

- `quarto render` locally produces `_site/trackers/eu-vetoes.html` with
  the 3 plots + DT table + freshness badge.
- Single commit pushed to `origin/main`.
- CI `render` AND `deploy` jobs both succeed.
- https://michalovadek.github.io/euverse/ resolves to the new home page
  (no GitHub default 404 page).
- https://michalovadek.github.io/euverse/trackers/eu-vetoes.html shows
  the 3 plots + DT table.
- https://michalovadek.github.io/euverse/trackers/eu-finance.html still
  works (didn't regress the eufinance port).
- AGENTS.md migration map has `✅` next to eu-vetoes row.

## 8. Out of scope / deferred

- The eu-court and eu-law tracker ports (heavier eurlex SPARQL — separate phases).
- A real landing page replacing the plumbing-test `home.qmd` (separate task once content is decided).
- Removing the `old/` reference Rmds (kept as historical reference until all 4 trackers are ported AND verified).
- Archiving the standalone `eu-veto-tracker` GitHub repo (owner action once the new tracker is verified equivalent).

## 9. Open questions

None. All decisions locked above.
