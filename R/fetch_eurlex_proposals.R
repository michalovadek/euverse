# fetch_eurlex_proposals.R
# Source: Eur-Lex SPARQL "proposal" type query.

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr)
})
source(here::here("R", "freshness.R"))

src <- "eurlex_proposals"

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

write_snapshot(df, src)
