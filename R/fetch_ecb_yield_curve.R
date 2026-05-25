# fetch_ecb_yield_curve.R
# Euro Area government bond yield curve spot rates from the ECB SDMX API,
# 1-year, 5-year, 10-year maturities, AAA issuers only. Daily frequency.
# Written as a single tidy long-form parquet.

suppressPackageStartupMessages({
  library(here)
})
source(here::here("R", "freshness.R"))

src <- "ecb_yield_curve"

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  ecb_api <- "https://data-api.ecb.europa.eu/service/data/"
  date_today <- format(Sys.Date(), "%Y-%m-%d")
  maturities <- c(`1` = 1L, `5` = 5L, `10` = 10L)

  parts <- lapply(names(maturities), function(y_chr) {
    url <- paste0(
      ecb_api,
      "YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_", y_chr, "Y",
      "?startPeriod=2004-09-06",
      "&endPeriod=", date_today,
      "&format=csvdata"
    )
    raw <- read.csv(url)
    data.frame(
      date           = as.Date(raw$TIME_PERIOD),
      maturity_years = maturities[[y_chr]],
      yield_pct      = as.numeric(raw$OBS_VALUE)
    )
  })
  do.call(rbind, parts)
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
required_cols <- c("date", "maturity_years", "yield_pct")
if (!all(required_cols %in% names(df))) {
  message("Validation failed: missing columns ",
          paste(setdiff(required_cols, names(df)), collapse = ", "))
  quit(status = 1L)
}
if (!all(df$maturity_years %in% c(1L, 5L, 10L))) {
  message("Validation failed: unexpected maturity values")
  quit(status = 1L)
}

# ---- 3. write atomically ----------------------------------------------------
write_snapshot(df, src)
