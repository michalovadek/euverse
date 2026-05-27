# fetch_eurlex_cases.R
# Source: EUR-Lex SPARQL, sector 6, case-existence list (one row per
# distinct CJEU case = court + year + case_number).
#
# Why this exists: Curia's static c1/c2/t2/f1_juris.htm pages stopped
# being refreshed by Curia on or around 2025-10-20 (last-Modified header
# fixed at that date, no /26 entries, latest /25 case is C-670 even
# though Wayback shows the file briefly contained up to C-709/25 before
# regressing). See R/fetch_curia_cases.R for the legacy fetcher and
# upstream notes.
#
# EUR-Lex covers cases via several document types in sector 6:
#   CN / TN / FN -> Notice published in OJ C series when a case is
#                   lodged (key signal for pending cases not yet decided)
#   CJ / TJ / FJ -> Judgment
#   CO / CB / TO / TB / FO / FB -> Order
#   CV / CX      -> Opinion / Avis
#   CA / TA / FA -> Application
#   CC, CD, CU   -> AG conclusions, declarations, other
# Taking the UNION of (court, year, case_number) over all sector-6
# celexes gives the broadest case-existence list available from the
# SPARQL endpoint. Notices (CN/TN/FN) are the most important addition
# vs the legacy decisions-only fetch in fetch_eurlex_court_decisions.R.

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr); library(stringr)
  library(httr); library(jsonlite)
})
source(here::here("R", "freshness.R"))
source(here::here("R", "celex.R"))

src <- "eurlex_cases"

# Years to backfill English-language case titles for. CJEU cases
# typically need a recent (last ~3 years) title because Curia's
# case_info is only stale for cases lodged after its freeze; older
# cases are well covered by Curia. We pull a couple of pre-freeze
# years too as a buffer (= 4 calendar years total) to keep the
# title coverage smoothly transitioning between sources.
TITLE_BACKFILL_YEARS <- 4L

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  raw <- elx_make_query(
    "any", sector = 6,
    include_date = TRUE
  ) |> elx_run_query()

  # ---- 2. reduce to case-existence tuples ---------------------------------
  # CELEX layout for sector 6: 6 YYYY TT NNNN [_RES/_SUM/_INF suffix].
  # Position 6 is the court letter (C/T/F); positions 8-11 are the
  # 4-digit case number padded with leading zeros.
  raw |>
    mutate(
      court_letter = celex_court(celex),
      case_year    = celex_year(celex),
      case_number  = as.integer(str_sub(celex, 8, 11)),
      doc_date     = suppressWarnings(as.Date(date))
    ) |>
    filter(court_letter %in% c("C", "T", "F"),
           !is.na(case_year), !is.na(case_number), case_number > 0) |>
    group_by(court_letter, case_year, case_number) |>
    summarise(
      first_celex    = celex[which.min(doc_date)][1L],
      first_doc_date = suppressWarnings(min(doc_date, na.rm = TRUE)),
      n_docs         = dplyr::n_distinct(celex),
      .groups        = "drop"
    ) |>
    mutate(
      first_doc_date = dplyr::if_else(is.infinite(first_doc_date),
                                      as.Date(NA), first_doc_date),
      court = dplyr::case_when(
        court_letter == "C" ~ "CJ",
        court_letter == "T" ~ "GC",
        court_letter == "F" ~ "CST",
        TRUE                ~ NA_character_
      ),
      # Two-digit year suffix for the human-readable id, matching Curia's
      # "C-100/24" convention. case_year %% 100 collapses 2024 -> 24 and
      # 1989 -> 89; the era is unambiguous within case-law context.
      case_id = paste0(
        court_letter, "-", case_number, "/",
        sprintf("%02d", case_year %% 100)
      )
    ) |>
    select(case_id, court, case_year, case_number,
           first_celex, first_doc_date, n_docs) |>
    as.data.frame()
}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 2b. backfill English titles for recent years --------------------------
# Hits the EUR-Lex SPARQL endpoint directly because the eurlex package
# wrapper doesn't expose `cdm:expression_title`. The query joins works
# to their English-language expression and pulls the title literal.
# Returns ~6,500 rows for a 3-year window in ~20s; scales roughly
# linearly with the year span.
year_now <- as.integer(format(Sys.Date(), "%Y"))
year_lo  <- year_now - (TITLE_BACKFILL_YEARS - 1L)
year_re  <- paste0("^6", "[0-9]{4}[CTF]")
# Build a digit-set regex like [4-9] to constrain the year suffix
# without relying on numeric inequalities (cdm:resource_legal_id_celex
# is a literal string, not an int).
year_digits <- as.character(year_lo:year_now)
year_alt    <- paste(year_digits, collapse = "|")
clx_filter  <- paste0("^6(", year_alt, ")[CTF]")

title_sparql <- sprintf('
PREFIX cdm: <http://publications.europa.eu/ontology/cdm#>
PREFIX lang: <http://publications.europa.eu/resource/authority/language/>
SELECT DISTINCT ?celex ?title
WHERE {
  ?w cdm:resource_legal_id_celex ?celex.
  FILTER(REGEX(str(?celex), "%s"))
  ?expr cdm:expression_belongs_to_work ?w.
  ?expr cdm:expression_uses_language lang:ENG.
  ?expr cdm:expression_title ?title.
}', clx_filter)

titles_df <- tryCatch({
  endpoint <- "http://publications.europa.eu/webapi/rdf/sparql"
  message("Fetching titles for years ", year_lo, "-", year_now, "...")
  r <- httr::POST(endpoint,
                  body = list(query = title_sparql,
                              format = "application/sparql-results+json"),
                  encode = "form", httr::timeout(600))
  if (httr::status_code(r) != 200L) {
    message("Title SPARQL HTTP ", httr::status_code(r), "; skipping title backfill")
    return(NULL)
  }
  parsed <- jsonlite::fromJSON(
    httr::content(r, "text", encoding = "UTF-8"), simplifyVector = FALSE
  )
  bindings <- parsed$results$bindings
  message("Title SPARQL returned ", length(bindings), " bindings.")
  if (length(bindings) == 0L) return(NULL)
  data.frame(
    celex = vapply(bindings, function(b) b$celex$value, character(1L)),
    title = vapply(bindings, function(b) b$title$value, character(1L)),
    stringsAsFactors = FALSE
  )
}, error = function(e) {
  message("Title backfill failed: ", conditionMessage(e),
          "; cases parquet will have title=NA")
  NULL
})

# Pick one title per case (court x year x case_number). Prefer titles
# from the case's first_celex when available so the chosen title
# matches the establishment notice ("Case C-N/YY: ..."); otherwise
# fall back to any celex's English title for that case.
df$title <- NA_character_
if (!is.null(titles_df) && nrow(titles_df) > 0L) {
  titles_df <- titles_df |>
    mutate(court_letter = celex_court(celex),
           case_year    = celex_year(celex),
           case_number  = suppressWarnings(as.integer(str_sub(celex, 8, 11))),
           court = dplyr::case_when(court_letter == "C" ~ "CJ",
                                    court_letter == "T" ~ "GC",
                                    court_letter == "F" ~ "CST",
                                    TRUE                ~ NA_character_)) |>
    filter(!is.na(court), !is.na(case_year), !is.na(case_number))

  # First-celex match (preferred)
  fc_titles <- titles_df |>
    select(first_celex = celex, title_fc = title)
  df <- df |> left_join(fc_titles, by = "first_celex")

  # Fallback: any English title for the case
  any_titles <- titles_df |>
    distinct(court, case_year, case_number, .keep_all = TRUE) |>
    select(court, case_year, case_number, title_any = title)
  df <- df |> left_join(any_titles, by = c("court", "case_year", "case_number"))

  df$title <- dplyr::coalesce(df$title_fc, df$title_any)
  df$title_fc  <- NULL
  df$title_any <- NULL
}

# ---- 3. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) < 10000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
required_cols <- c("case_id", "court", "case_year", "case_number")
if (!all(required_cols %in% names(df))) {
  message("Validation failed: missing columns ",
          paste(setdiff(required_cols, names(df)), collapse = ", "))
  quit(status = 1L)
}
if (sum(df$court == "CJ", na.rm = TRUE) < 1000L) {
  message("Validation failed: too few CJ cases (",
          sum(df$court == "CJ", na.rm = TRUE), ")")
  quit(status = 1L)
}

# ---- 4. write atomically ----------------------------------------------------
write_snapshot(df, src)
