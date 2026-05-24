# build_data_external_parquets.R
#
# Idempotent preprocessing of bulky data-external/ raw files into parquet so
# they fit within the project's <5 MB soft target / GitHub's 100 MB hard limit
# and can be committed to the repo. Raw upstream files (.dta, large .csv,
# .db) stay gitignored — they're regenerable from upstream and developers
# obtain them per each subfolder's _SOURCE.md.
#
# Usage: Rscript R/build_data_external_parquets.R
# Re-running is safe: any existing parquet at the target path is overwritten.

suppressPackageStartupMessages({
  library(arrow)
  library(haven)
})

dest_log <- list()
write_pq <- function(df, path, label) {
  arrow::write_parquet(df, path, compression = "zstd")
  size_kb <- round(file.info(path)$size / 1024, 1)
  dest_log[[label]] <<- list(path = path, size_kb = size_kb, rows = nrow(df), cols = ncol(df))
  message(sprintf("  -> %s : %s KB, %d rows x %d cols", path, size_kb, nrow(df), ncol(df)))
}

# ---- 1. EUPROPS .dta (342 MB) -> parquet -----------------------------------
src_dta <- "data-external/euprops/EUPROPS_v2_0.dta"
if (file.exists(src_dta)) {
  message("Reading EUPROPS .dta (this takes a minute) ...")
  df <- haven::read_dta(src_dta)
  write_pq(df, "data-external/euprops/euprops_v2_0.parquet", "euprops")
} else {
  message("SKIP: ", src_dta, " not present locally")
}

# ---- 2. euplex.csv (32 MB) -> parquet --------------------------------------
src_csv <- "data-external/euplex/euplex.csv"
if (file.exists(src_csv)) {
  message("Reading euplex.csv ...")
  df <- arrow::read_csv_arrow(src_csv)
  write_pq(df, "data-external/euplex/euplex.parquet", "euplex")
} else {
  message("SKIP: ", src_csv, " not present locally")
}

# ---- 3. parlgov view_cabinet.csv + view_election.csv -> parquet ------------
for (name in c("view_cabinet", "view_election")) {
  src <- file.path("data-external/parlgov", paste0(name, ".csv"))
  if (file.exists(src)) {
    message("Reading parlgov ", name, " ...")
    df <- arrow::read_csv_arrow(src)
    write_pq(df, file.path("data-external/parlgov", paste0(name, ".parquet")), paste0("parlgov_", name))
  } else {
    message("SKIP: ", src, " not present locally")
  }
}

# Summary
message("")
message("Wrote ", length(dest_log), " parquet files:")
for (k in names(dest_log)) {
  d <- dest_log[[k]]
  message(sprintf("  %-25s %s KB", k, d$size_kb))
}
