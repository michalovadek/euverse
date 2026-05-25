# fetch_ecb_hicp.R
# ECB Harmonised Index of Consumer Prices, Euro Area, year-on-year annual
# rate of change. Monthly. Goes back to 1998.

suppressPackageStartupMessages({
  library(here); library(lubridate)
})
source(here::here("R", "freshness.R"))

src <- "ecb_hicp"

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  ecb_api <- "https://data-api.ecb.europa.eu/service/data/"
  date_today <- format(Sys.Date(), "%Y-%m-%d")
  url <- paste0(
    ecb_api,
    "ICP/M.U2.N.000000.4.ANR",
    "?startPeriod=1998-01-01",
    "&endPeriod=", date_today,
    "&format=csvdata"
  )
  raw <- read.csv(url)
  # TIME_PERIOD is "YYYY-MM"; convert to a Date at first of month.
  data.frame(
    date    = as.Date(lubridate::ym(raw$TIME_PERIOD)),
    yoy_pct = as.numeric(raw$OBS_VALUE)
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
if (!all(c("date", "yoy_pct") %in% names(df))) {
  message("Validation failed: missing columns")
  quit(status = 1L)
}

# ---- 3. write atomically ----------------------------------------------------
write_snapshot(df, src)
