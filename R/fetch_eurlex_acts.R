# fetch_eurlex_acts.R
# Source: Eur-Lex SPARQL sector 3 (legal acts).
# Includes recent-title fetches for the top-50 newest acts so the
# eu-law page's "most recent legislation" table works from the snapshot.
#
# We deliberately do NOT request include_proposal. That proposal-link join
# is the heaviest part of the sector-3 query and was timing out in CI: the
# fetcher succeeded locally but failed every nightly run, leaving the page
# on a stale fallback snapshot. The column was unused downstream (the
# proposals analysis builds on EUPROPS via data-final, not on this
# snapshot), so dropping it costs nothing.

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr); library(stringr); library(purrr)
})
source(here::here("R", "freshness.R"))
source(here::here("R", "celex.R"))

src <- "eurlex_acts"

df <- tryCatch({
  raw <- elx_make_query("any", sector = 3,
                        include_date = TRUE) |>
    elx_run_query() |>
    select(-any_of("work"))

  # Acts only: drop bogus dates, dedup by celex.
  acts <- raw |>
    filter(!is.na(celex), !date %in% c("1003-03-03")) |>
    distinct(celex, .keep_all = TRUE) |>
    mutate(
      type = celex_act_type(celex),
      year = celex_year(celex)
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

if (!is.data.frame(df) || !check_rowcount(nrow(df), src, min_rows = 50000L)) {
  message("Validation failed: ", nrow(df), " rows (below floor or >40% drop vs last snapshot)")
  quit(status = 1L)
}
if (!all(c("celex", "date", "type", "year", "recent_title") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

write_snapshot(df, src)
