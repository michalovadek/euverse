# fetch_eurostat_teimf050.R
# Eurostat "teimf050": long-term gov bond yields, 10-year maturity, monthly,
# by country (incl. EA + EU27_2020 aggregates which the page filters as needed).
# Written as a single tidy parquet with English country names joined.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurostat); library(dplyr); library(tibble)
})

src     <- "eurostat_teimf050"
out_dir <- here::here("data-apis")

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
  meta_tmp, auto_unbox = TRUE, pretty = TRUE
)
file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
