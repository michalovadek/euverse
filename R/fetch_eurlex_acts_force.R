# fetch_eurlex_acts_force.R
# Source: Eur-Lex SPARQL sector 3 with force status + date_force.

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr); library(tidyr); library(stringr)
})
source(here::here("R", "freshness.R"))

src <- "eurlex_acts_force"

df <- tryCatch({
  raw <- elx_make_query("any", sector = 3,
                        include_force = TRUE,
                        include_date_force = TRUE) |>
    elx_run_query() |>
    select(-any_of("work")) |>
    rename(date_force = dateforce) |>
    arrange(celex, date_force) |>
    distinct(celex, .keep_all = TRUE) |>
    tidyr::drop_na(celex, force, date_force)

  raw |>
    filter(date_force >= "1952-01-01" & date_force <= as.character(Sys.Date())) |>
    as.data.frame()

}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

if (!is.data.frame(df) || !check_rowcount(nrow(df), src, min_rows = 50000L)) {
  message("Validation failed: ", nrow(df), " rows (below floor or >40% drop vs last snapshot)")
  quit(status = 1L)
}
if (!all(c("celex", "force", "date_force") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

write_snapshot(df, src)
