# fetch_eurlex_acts_force.R
# Source: Eur-Lex SPARQL sector 3 with force status + date_force.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr); library(tidyr); library(stringr)
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
