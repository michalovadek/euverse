# fetch_eurlex_acts.R
# Source: Eur-Lex SPARQL sector 3 (legal acts) with proposal link.
# Includes recent-title fetches for the top-50 newest acts so the
# eu-law page's "most recent legislation" table works from the snapshot.

suppressPackageStartupMessages({
  library(arrow); library(jsonlite); library(here); library(digest)
  library(eurlex); library(dplyr); library(stringr); library(purrr)
})

src     <- "eurlex_acts"
out_dir <- here::here("data-apis")

df <- tryCatch({
  raw <- elx_make_query("any", sector = 3,
                        include_date = TRUE,
                        include_proposal = TRUE) |>
    elx_run_query() |>
    select(-any_of("work"))

  # Acts only: drop bogus dates, dedup by celex.
  acts <- raw |>
    filter(!is.na(celex), !date %in% c("1003-03-03")) |>
    distinct(celex, .keep_all = TRUE) |>
    mutate(
      type = case_when(
        str_sub(celex, 6, 6) == "R" ~ "Regulation",
        str_sub(celex, 6, 6) == "L" ~ "Directive",
        str_sub(celex, 6, 6) == "D" ~ "Decision",
        str_sub(celex, 6, 6) == "H" ~ "Recommendation",
        TRUE                        ~ "Other"
      ),
      year = as.integer(str_sub(celex, 2, 5))
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

if (!is.data.frame(df) || nrow(df) < 50000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
if (!all(c("celex", "date", "type", "year", "recent_title") %in% names(df))) {
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
