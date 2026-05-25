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
