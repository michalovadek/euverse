# celex.R  —  helpers for the CELEX identifier format used across Eur-Lex.
# A CELEX looks like "32024R1234" (sector + year + type + number) or
# "62019CJ0550" (court decisions). All trackers that touch Eur-Lex data
# decode the same positions; this file is the single source of truth.
# Sourced from .qmd / fetcher scripts via: source(here::here("R", "celex.R"))

celex_year <- function(celex) {
  as.integer(stringr::str_sub(celex, 2, 5))
}

celex_act_type <- function(celex) {
  # Position 6 of an act CELEX encodes the act type. The four main types
  # below cover ~98% of sector 3 (legal acts); the rest ("Other") includes
  # international agreements (A), opinions (O/Q), summaries (X), etc.
  letter <- stringr::str_sub(celex, 6, 6)
  dplyr::case_when(
    letter == "R" ~ "Regulation",
    letter == "L" ~ "Directive",
    letter == "D" ~ "Decision",
    letter == "H" ~ "Recommendation",
    TRUE          ~ "Other"
  )
}

celex_court <- function(celex) {
  # Sector 6 (court decisions): position 6 is C (Court of Justice),
  # T (General Court), or F (Civil Service Tribunal, abolished 2016).
  stringr::str_sub(celex, 6, 6)
}
