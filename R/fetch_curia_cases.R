# fetch_curia_cases.R
# Source: Curia case list scraper via eurlex::elx_curia_list().
# Returns ~50-80K cases (all CJEU cases since 1953).
#
# STATUS (as of 2026-05-27): LEGACY SUPPLEMENTAL DATA.
#   Curia's static c1/c2/t2/f1_juris.htm pages stopped being refreshed
#   by curia.europa.eu around 2025-10-20 and the live response has even
#   regressed - Wayback Machine snapshots show the file briefly held
#   cases through C-709/25 in November 2025 but the live response today
#   ends at C-670/25. We keep running this fetcher because Curia still
#   ships information EUR-Lex doesn't (case_status, case_info, ECLI
#   mappings) and may resume publishing at some point, but the page
#   no longer DEPENDS on this fetcher succeeding. See trackers/eu-court.qmd
#   and docs/eurlex-issue-draft.md for details and EUR-Lex fallback logic.
#
# IMPORTANT: We use parse = FALSE to bypass a known bug in
# eurlex::elx_curia_parse() (extract_first helper drops the
# 'match.length' attribute when subsetting, breaking regmatches with
# "invalid substring arguments"). When the upstream eurlex bug is fixed,
# this fetcher can be simplified to parse = TRUE again.
# Until then we parse ECLI ourselves from case_info; see_case and
# appeal columns are set to NA (the eu-court page does not depend on
# them for any of its current charts).

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr); library(stringr)
})
source(here::here("R", "freshness.R"))

src <- "curia_cases"

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  raw <- elx_curia_list("all", parse = FALSE)

  cleaned <- raw |>
    mutate(case_id = str_replace(case_id, "(?<=[:digit:])-(?=[:digit:])", "/")) |>
    filter(nchar(case_id) > 3) |>
    # ECLI extracted directly from case_info ("ECLI:EU:C:2024:797" etc.)
    mutate(ecli = str_extract(case_info, "ECLI:EU:[CTF]:\\d{4}:\\d+")) |>
    # see_case / appeal not parseable without the upstream fix - leave NA.
    mutate(see_case       = NA_character_,
           see_case_court = NA_character_,
           appeal         = NA_character_,
           appeal_court   = NA_character_) |>
    mutate(court = case_when(
      str_detect(case_id, "OPIN|C-|^[:digit:]|RULING") ~ "CJ",
      str_detect(case_id, "T-") ~ "GC",
      str_detect(case_id, "F-") ~ "CST",
      TRUE ~ NA_character_
    )) |>
    mutate(case_status = case_when(
      str_detect(case_id, "OPIN|RULING") ~ "Opinion",
      str_detect(case_info, "^Judge?ment") ~ "Judgment",
      str_detect(case_info, "^Order") ~ "Order",
      str_detect(case_info, "^Removed") ~ "Removal",
      str_detect(case_info, "^Pending") & is.na(ecli) ~ "Pending",
      str_detect(case_info, "^Seizure order") ~ "Seizure order",
      str_detect(case_info, "^Decision") & str_detect(case_id, "RX") ~ "Re-examination",
      str_detect(case_info, "^Third-party proce") ~ "Third-party proceedings",
      # NOTE: Transferred/Joined branches removed - they required see_case.
      TRUE ~ NA_character_
    )) |>
    mutate(case_year_raw = str_extract(case_id, "/[:digit:]{2}"),
           case_year_raw = str_remove(case_year_raw, "/"),
           case_year = case_when(
             str_detect(case_year_raw, "^0|^1|^2|^3") ~ as.integer(str_c("20", case_year_raw)),
             str_detect(case_year_raw, "^5|^6|^7|^8|^9") ~ as.integer(str_c("19", case_year_raw)),
             TRUE ~ NA_integer_
           ),
           case_number = as.integer(str_extract(case_id, "[:digit:]+(?=/)")),
           decision_year = as.integer(str_extract(ecli, "[:digit:]{4}")),
           decision_date_str = str_extract(
             case_info,
             "[:digit:]{1,2} (January|February|March|April|May|June|July|August|September|October|November|December) (19|20)[:digit:]{2}"
           )) |>
    select(case_id, ecli, court, see_case, see_case_court, appeal, appeal_court,
           case_status, case_year, case_number, decision_year, decision_date_str, case_info)

  as.data.frame(cleaned)
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) == 0L) {
  message("Validation failed: empty or non-data.frame result")
  quit(status = 1L)
}
if (!all(c("case_id", "case_status", "court", "case_year") %in% names(df))) {
  message("Validation failed: missing required columns")
  quit(status = 1L)
}
if (!any(df$court == "CJ", na.rm = TRUE)) {
  message("Validation failed: no CJ cases in result")
  quit(status = 1L)
}

# ---- 3. write atomically ----------------------------------------------------
write_snapshot(df, src)
