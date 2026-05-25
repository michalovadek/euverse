# fetch_eurlex_lbs.R
# Source: Eur-Lex SPARQL sector 3 with legal-basis pairs.
# Outputs ~700K-1M rows of (celex, lbcelex) pairs (raw - enrichment
# happens at render time since it's display-specific).

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr)
})

src     <- "eurlex_lbs"
out_dir <- here::here("data-apis")

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
