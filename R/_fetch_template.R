# ============================================================================
# _fetch_template.R
#
# COPY this file to `fetch_<src>.R` (drop the leading underscore) and replace
# every <src> below with your source name. The underscore on this template
# keeps the CI workflow's R/fetch_*.R glob from running it; once renamed,
# the new fetcher runs nightly.
#
# Contract:
#   - On success: writes data-apis/<src>_latest.parquet and
#                 data-apis/<src>_latest.meta.json. The parquet is renamed
#                 first, the meta sidecar second. Each individual rename is
#                 atomic, but a crash BETWEEN them can leave fresh data with
#                 a stale meta sidecar (the next nightly run repairs this).
#                 Readers should treat the meta as "best-effort current".
#   - On failure: exits non-zero WITHOUT modifying the *_latest.* files,
#                 so the next quarto render falls back to the previous
#                 snapshot and shows an older freshness badge.
#   - Stdout / stderr is captured by the CI workflow. Use message() for
#     progress lines (visible in Actions logs).
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(jsonlite)
  library(here)
  library(digest)
})

src     <- "REPLACE_ME"                       # e.g. "ecb_yields"
out_dir <- here::here("data-apis")

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  # ... real fetch logic goes here ...
  stop("fetcher not yet implemented")        # remove once the body is written
  data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate (cheap schema/shape checks) --------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
# ... domain-specific schema checks here; quit(1L) on any failure ...

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
  meta_tmp,
  auto_unbox = TRUE,
  pretty     = TRUE
)

file.rename(data_tmp, file.path(out_dir, paste0(src, "_latest.parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, "_latest.meta.json")))
message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
