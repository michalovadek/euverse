# fetch_ecb_mrr.R
# ECB key interest rate on Main Refinancing Operations (MRR_FR.LEV).
# Event-driven series — one observation per rate change. Goes back to 1998.

suppressPackageStartupMessages({
  library(here)
})
source(here::here("R", "freshness.R"))

src <- "ecb_mrr"

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  ecb_api <- "https://data-api.ecb.europa.eu/service/data/"
  date_today <- format(Sys.Date(), "%Y-%m-%d")
  url <- paste0(
    ecb_api,
    "FM/B.U2.EUR.4F.KR.MRR_FR.LEV",
    "?startPeriod=1998-01-01",
    "&endPeriod=", date_today,
    "&format=csvdata"
  )
  raw <- read.csv(url)
  data.frame(
    date     = as.Date(raw$TIME_PERIOD),
    rate_pct = as.numeric(raw$OBS_VALUE)
  )
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
if (!all(c("date", "rate_pct") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

# ---- 3. write atomically ----------------------------------------------------
write_snapshot(df, src)
