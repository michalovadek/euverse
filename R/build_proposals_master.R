# build_proposals_master.R
#
# Build the canonical EU legislative-proposal dataset by combining two sources:
#   1. EUPROPS (data-external/euprops/euprops_v2_0.parquet) — static, hand-
#      curated, covers 1958-2022. This is the SOURCE OF TRUTH for everything
#      it covers; we trust its corrected legal-base / adopted-act linkages
#      and proposal-type taxonomy over the raw Eur-Lex API output.
#   2. Eur-Lex proposals snapshot (data-apis/eurlex_proposals_latest.parquet)
#      — nightly. Used ONLY to extend the dataset past EUPROPS's cutoff
#      (max(proposed) ≈ 2022-05-06). Carries minimal metadata (just
#      celex + date_proposal), so EUPROPS-only enrichment columns are NA
#      for these post-cutoff rows.
#
# Sanity filters applied to EUPROPS (drops ~2.7%):
#   - myerror == "1"               (curator-confirmed errors)
#   - type in erroneouspdec/preg/drop
#   - adopted date < proposed date (impossible chronology)
#   - is.na(proposed)              (can't be used without a proposal date)
# Kept on purpose despite imperfect data (60+ years of history, see
# user note "allow for the underlying data to not be perfect"):
#   - withdrawn / not adopted / rejected / replaced — valid proposal records
#   - NA adopted (pending or never adopted) — valid
#   - Eurlexerror / Prelexerror flags — EUPROPS proposal is still trusted;
#     the flag annotates a discrepancy with Eur-Lex, not a data error in EUPROPS

suppressPackageStartupMessages({
  library(here); library(dplyr); library(stringr); library(arrow); library(jsonlite); library(digest)
})

src     <- "proposals_master"
out_dir <- here::here("data-final")

parse_d <- function(x) suppressWarnings(as.Date(x))

# ---- 1. Load EUPROPS --------------------------------------------------------
euprops_raw <- arrow::read_parquet(
  here::here("data-external", "euprops", "euprops_v2_0.parquet")
)
n_raw <- nrow(euprops_raw)

# ---- 2. Sanity filters ------------------------------------------------------
euprops <- euprops_raw |>
  mutate(prop_d = parse_d(proposed),
         adop_d = parse_d(adopted)) |>
  filter(is.na(myerror) | myerror != "1") |>
  filter(!type %in% c("erroneouspdec", "erroneouspreg", "drop")) |>
  filter(is.na(adop_d) | is.na(prop_d) | adop_d >= prop_d) |>
  filter(!is.na(prop_d))

n_after_filter <- nrow(euprops)

# ---- 3. Construct proposal_celex from source + sourceid --------------------
# Eur-Lex sector-5 letter pairs per source. COUNCIL/BCE/C/LET use ad-hoc
# id formats that don't map cleanly — they keep euprop_id but proposal_celex
# stays NA, so any join with Eur-Lex acts on proposal_celex will simply
# miss them (which is correct: they're a small share and don't have a
# reliable single celex anyway).
source_letter <- c(COM = "PC", SEC = "SC", JC = "JC", JAI = "JC")

euprops <- euprops |>
  mutate(
    yr  = str_extract(sourceid, "(?<=\\()[0-9]{4}"),
    num = str_pad(str_extract(sourceid, "[0-9]+$"), 4, pad = "0"),
    proposal_celex = case_when(
      source %in% names(source_letter) & !is.na(yr) & !is.na(num) ~
        paste0("5", yr, source_letter[source], num),
      TRUE ~ NA_character_
    )
  )

# ---- 4. Normalise amending flag --------------------------------------------
# Explicit "y"/"n" flag is blank ~46% of the time. Fall back to the type
# prefix: anything starting with "mod" (modreg, modpdec, modpdir) is an
# amending proposal by EUPROPS's own typology.
euprops <- euprops |>
  mutate(
    is_amending = case_when(
      str_to_lower(amending) %in% c("y")  ~ TRUE,
      str_to_lower(amending) %in% c("n")  ~ FALSE,
      str_starts(type, "mod")              ~ TRUE,
      TRUE                                 ~ NA
    )
  )

# ---- 5. Compact schema (12 cols, semantically grouped) ----------------------
euprops_clean <- euprops |>
  transmute(
    proposal_celex,
    euprop_id   = EUPROPID,
    source_org  = source,           # COM / SEC / JC / JAI / COUNCIL / BCE / C / LET
    type,                           # EUPROPS taxonomy (preg, pdec, modpreg, ...)
    is_amending,
    proposed    = prop_d,
    adopted     = adop_d,
    withdrawn,                      # "" / "withdrawn" / "rejected" / "not adopted" / ...
    title,
    legalbase,                      # legal base as proposed
    adoptedlb,                      # legal base as adopted (often differs)
    firstlaw,                       # first adopted-act CELEX (may be NA)
    adoptedlaws,                    # ;-separated full list of adopted acts
    source_data = "euprops"
  )

# ---- 6. Append Eur-Lex tail for proposals after EUPROPS cutoff --------------
euprops_cutoff <- max(euprops_clean$proposed, na.rm = TRUE)

celex_type_letter <- function(celex) str_sub(celex, 6, 7)
celex_source_org <- function(celex) {
  case_when(
    celex_type_letter(celex) == "PC" ~ "COM",
    celex_type_letter(celex) == "SC" ~ "SEC",
    celex_type_letter(celex) == "JC" ~ "JC",
    celex_type_letter(celex) == "DC" ~ "COUNCIL",
    TRUE                             ~ NA_character_
  )
}

eurlex_raw <- arrow::read_parquet(
  here::here("data-apis", "eurlex_proposals_latest.parquet")
) |>
  mutate(date_proposal = parse_d(date_proposal)) |>
  filter(!is.na(date_proposal),
         date_proposal >  euprops_cutoff,
         date_proposal <= Sys.Date())

eurlex_clean <- eurlex_raw |>
  transmute(
    proposal_celex = celex,
    euprop_id      = NA_character_,
    source_org     = celex_source_org(celex),
    type           = NA_character_,   # Eur-Lex doesn't carry EUPROPS taxonomy
    is_amending    = NA,
    proposed       = date_proposal,
    adopted        = as.Date(NA),
    withdrawn      = NA_character_,
    title          = NA_character_,
    legalbase      = NA_character_,
    adoptedlb      = NA_character_,
    firstlaw       = NA_character_,
    adoptedlaws    = NA_character_,
    source_data    = "eurlex"
  ) |>
  # Defensive: drop any eurlex row whose celex already exists in EUPROPS
  # (shouldn't happen given the date cutoff, but if it does the EUPROPS
  # row is authoritative).
  filter(!proposal_celex %in% euprops_clean$proposal_celex)

# ---- 7. Combine + write atomically ------------------------------------------
master <- bind_rows(euprops_clean, eurlex_clean) |>
  arrange(proposed)

stopifnot(nrow(master) > 25000L)
stopifnot(all(c("proposal_celex", "euprop_id", "source_data", "proposed") %in% names(master)))

pq_tmp   <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(master, pq_tmp, compression = "zstd")
jsonlite::write_json(
  list(
    source         = src,
    built_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    inputs         = c("data-external/euprops/euprops_v2_0.parquet",
                       "data-apis/eurlex_proposals_latest.parquet"),
    builder_script = "R/build_proposals_master.R",
    rows           = nrow(master),
    euprops_kept   = nrow(euprops_clean),
    euprops_dropped = n_raw - n_after_filter,
    eurlex_tail    = nrow(eurlex_clean),
    euprops_cutoff = format(euprops_cutoff, "%Y-%m-%d")
  ),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE
)
file.rename(pq_tmp,   file.path(out_dir, paste0(src, ".parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, ".meta.json")))

message(sprintf(
  "Built %s: %d EUPROPS rows kept (%d dropped), + %d Eur-Lex rows past %s. Total: %d.",
  src, nrow(euprops_clean), n_raw - n_after_filter, nrow(eurlex_clean),
  format(euprops_cutoff, "%Y-%m-%d"), nrow(master)
))
