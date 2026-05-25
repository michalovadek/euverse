# build_eu_member_states.R
# Build the canonical EU Member States master table for the euverse site.
# Reads the hand-curated CSV at data-manual/eu-member-states.csv, validates,
# writes the parquet to data-final/eu_member_states.parquet + meta sidecar.
# Idempotent: re-running produces a byte-identical parquet.

suppressPackageStartupMessages({
  library(arrow)
  library(jsonlite)
  library(here)
})

src      <- "eu-member-states"
csv_path <- here::here("data-manual", "eu-member-states.csv")
out_pq   <- here::here("data-final", "eu_member_states.parquet")
out_meta <- here::here("data-final", "eu_member_states.meta.json")

# ---- 1. read + parse --------------------------------------------------------
if (!file.exists(csv_path)) {
  stop("Source CSV not found: ", csv_path, call. = FALSE)
}
df <- read.csv(csv_path, stringsAsFactors = FALSE, na.strings = "")
df$accession_year <- as.integer(df$accession_year)
df$exit_year      <- suppressWarnings(as.integer(df$exit_year))

# ---- 2. validate ------------------------------------------------------------
stopifnot(
  identical(names(df), c("country", "iso2", "accession_year", "exit_year")),
  nrow(df) >= 27L && nrow(df) <= 30L,
  !any(duplicated(df$iso2)),
  !any(duplicated(df$country)),
  all(nchar(df$iso2) == 2L),
  all(df$accession_year >= 1952L & df$accession_year <= 2050L),
  all(is.na(df$exit_year) | df$exit_year >= df$accession_year)
)

# ---- 3. write atomically ----------------------------------------------------
pq_tmp   <- tempfile(tmpdir = dirname(out_pq),   fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = dirname(out_meta), fileext = ".json")

arrow::write_parquet(df, pq_tmp, compression = "zstd")
jsonlite::write_json(
  list(
    source          = src,
    built_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    inputs          = "data-manual/eu-member-states.csv",
    builder_script  = "R/build_eu_member_states.R",
    rows            = nrow(df)
  ),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE
)

file.rename(pq_tmp,   out_pq)
file.rename(meta_tmp, out_meta)
message("Built ", src, ": ", nrow(df), " rows -> ", out_pq)
