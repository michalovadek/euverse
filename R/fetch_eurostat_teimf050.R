# fetch_eurostat_teimf050.R
# Eurostat "teimf050": long-term gov bond yields, 10-year maturity, monthly,
# by country (incl. EA + EU27_2020 aggregates which the page filters as needed).
# Written as a single tidy parquet with English country names joined.

suppressPackageStartupMessages({
  library(here); library(eurostat); library(dplyr); library(tibble)
})
source(here::here("R", "freshness.R"))

src <- "eurostat_teimf050"

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  raw <- eurostat::get_eurostat("teimf050")
  country_map <- dplyr::bind_rows(
    eurostat::eu_countries,
    tibble::tibble(
      code = c("UK", "EA", "EU27_2020"),
      name = c("United Kingdom", "Euro Area", "EU27 (2020)")
    )
  )
  raw |>
    dplyr::left_join(country_map, by = c("geo" = "code")) |>
    dplyr::transmute(
      date         = as.Date(TIME_PERIOD),
      geo          = as.character(geo),
      country_name = as.character(name),
      yield_pct    = as.numeric(values)
    ) |>
    as.data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
required_cols <- c("date", "geo", "country_name", "yield_pct")
if (!all(required_cols %in% names(df))) {
  message("Validation failed: missing columns ",
          paste(setdiff(required_cols, names(df)), collapse = ", "))
  quit(status = 1L)
}
if (!"EA" %in% df$geo) {
  message("Validation failed: EA aggregate missing from snapshot")
  quit(status = 1L)
}

# ---- 3. write atomically ----------------------------------------------------
write_snapshot(df, src)
