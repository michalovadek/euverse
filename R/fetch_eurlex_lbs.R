# fetch_eurlex_lbs.R
# Source: Eur-Lex SPARQL sector 3 with legal-basis pairs.
# Outputs ~700K-1M rows of (celex, lbcelex) pairs (raw - enrichment
# happens at render time since it's display-specific).

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr)
})
source(here::here("R", "freshness.R"))

src <- "eurlex_lbs"

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

write_snapshot(df, src)
