# build_eu_politics.R
#
# Build two derived datasets for the eu-politics tracker, joining the
# hand-curated EU Member States master with ParlGov (cabinets + party
# ideology scores) and the Manifesto Project (party-position time series).
#
# Outputs:
#   1. data-final/eu_government_composition.parquet
#        One row per (country, year), 1990 onwards. Carries the
#        seat-share-weighted mean ParlGov left_right and eu_anti_pro
#        scores of the cabinet active on 30 June of that year, plus a
#        boolean has_eurosceptic flag (any cabinet party with
#        eu_anti_pro <= 4) and the cabinet_name for tooltips.
#
#   2. data-final/eu_manifesto_eu_stance.parquet
#        One row per year-of-EU-election. Carries (a) per-country mean
#        of per108 (EU positive) and per110 (EU negative) categories from
#        the Manifesto Project, weighted by pervote (vote share); plus
#        (b) the year-level EU-wide unweighted average. EU positive minus
#        EU negative is the net "salience-weighted EU stance".
#
# Both files filter to current and historical EU Member States via the
# eu-member-states.csv master (so the UK is included up to its exit).

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(arrow); library(jsonlite)
})

out_dir <- here::here("data-final")

# ---- 1. EU Member States master --------------------------------------------
ms <- read.csv(here::here("data-manual", "eu-member-states.csv"),
               stringsAsFactors = FALSE, na.strings = "")
ms$accession_year <- as.integer(ms$accession_year)
ms$exit_year      <- suppressWarnings(as.integer(ms$exit_year))

# parlgov uses "Czech Republic", manifesto uses both "Czech Republic" and
# (post-2017) "Czechia". The MS master uses "Czechia". Normalise on the
# ParlGov/Manifesto side to match.
eu_names_master <- ms$country
eu_names_pg <- ifelse(eu_names_master == "Czechia", "Czech Republic", eu_names_master)

# ---- 2. ParlGov: per-cabinet weighted scores ------------------------------
pg_cabinet <- arrow::read_parquet(
  here::here("data-external", "parlgov", "view_cabinet.parquet")
)
pg_party <- read.csv(
  here::here("data-external", "parlgov", "view_party.csv"),
  stringsAsFactors = FALSE
)

party_scores <- pg_party |>
  select(party_id,
         party_left_right = left_right,
         party_eu_anti_pro = eu_anti_pro)

cabinet_party <- pg_cabinet |>
  filter(country_name %in% eu_names_pg,
         cabinet_party == 1L,        # exclude opposition parties listed in the view
         caretaker == 0L) |>          # exclude caretaker cabinets
  left_join(party_scores, by = "party_id")

# Per-cabinet aggregation: seats-weighted scores + has-eurosceptic flag.
cabinet_summ <- cabinet_party |>
  group_by(country_name, cabinet_id, cabinet_name, start_date) |>
  summarise(
    mean_left_right  = weighted.mean(party_left_right,
                                     w = seats,
                                     na.rm = TRUE),
    mean_eu_anti_pro = weighted.mean(party_eu_anti_pro,
                                     w = seats,
                                     na.rm = TRUE),
    has_eurosceptic  = any(party_eu_anti_pro <= 4, na.rm = TRUE),
    n_parties        = n_distinct(party_id),
    .groups          = "drop"
  ) |>
  arrange(country_name, start_date) |>
  group_by(country_name) |>
  mutate(end_date = dplyr::lead(start_date,
                                default = as.Date("9999-12-31")) - 1L) |>
  ungroup()

# Year x country panel. Pick the cabinet active on 30 June (avoids the
# edge case where multiple cabinets started in the same year - the
# midyear sample picks the dominant one).
year_lo <- 1990L
year_hi <- as.integer(format(Sys.Date(), "%Y"))

cy_grid <- tidyr::crossing(country_name = eu_names_pg,
                           year         = year_lo:year_hi) |>
  mutate(midyear = as.Date(paste0(year, "-06-30")))

# Re-restrict to years the country was actually an EU member (so e.g.
# Croatia only appears from 2013, UK ends 2019). This trims the heatmap
# to honest membership coverage.
ms_match <- tibble::tibble(country_name = eu_names_pg,
                           accession_year = ms$accession_year,
                           exit_year      = ms$exit_year)

cy_grid <- cy_grid |>
  inner_join(ms_match, by = "country_name") |>
  filter(year >= accession_year,
         is.na(exit_year) | year < exit_year) |>
  select(country_name, year, midyear)

eu_government <- cy_grid |>
  left_join(cabinet_summ, by = "country_name",
            relationship = "many-to-many") |>
  filter(midyear >= start_date, midyear <= end_date) |>
  select(country_name, year, cabinet_name,
         mean_left_right, mean_eu_anti_pro, has_eurosceptic, n_parties) |>
  arrange(country_name, year)

# Reattach ISO-2 from the MS master (using the master's display name,
# not the ParlGov spelling).
iso_lookup <- tibble::tibble(country_name = eu_names_pg,
                             country      = eu_names_master,
                             iso2         = ms$iso2)
eu_government <- eu_government |>
  left_join(iso_lookup, by = "country_name") |>
  select(country, iso2, year, cabinet_name,
         mean_left_right, mean_eu_anti_pro, has_eurosceptic, n_parties)

# ---- 3. Manifesto: EU-position salience over time -------------------------
mp <- read.csv(
  here::here("data-external", "manifesto", "MPDataset_MPDS2024a.csv"),
  stringsAsFactors = FALSE
)

# The Manifesto date is YYYYMM. Strip to year.
mp_eu <- mp |>
  filter(countryname %in% c(eu_names_master, "Czech Republic")) |>
  mutate(year = as.integer(substr(as.character(date), 1, 4)),
         country = ifelse(countryname == "Czech Republic",
                          "Czechia", countryname)) |>
  filter(!is.na(per108), !is.na(per110))

# Vote-weighted per-country annual EU mention shares.
country_year <- mp_eu |>
  group_by(country, year) |>
  summarise(
    eu_positive = weighted.mean(per108, w = pmax(pervote, 0.001), na.rm = TRUE),
    eu_negative = weighted.mean(per110, w = pmax(pervote, 0.001), na.rm = TRUE),
    n_parties   = dplyr::n_distinct(party),
    .groups     = "drop"
  ) |>
  mutate(net_pro_eu = eu_positive - eu_negative)

# EU-wide unweighted mean per year - lets the manifesto chart show a
# single trend line that's not dominated by big-MS election cycles.
eu_year <- mp_eu |>
  group_by(year) |>
  summarise(
    eu_positive_mean = mean(per108, na.rm = TRUE),
    eu_negative_mean = mean(per110, na.rm = TRUE),
    n_manifestos     = dplyr::n(),
    .groups          = "drop"
  ) |>
  mutate(net_pro_eu = eu_positive_mean - eu_negative_mean)

# Join back ISO-2 so downstream charts can colour by flag without re-keying.
iso_for_manifesto <- tibble::tibble(country = eu_names_master, iso2 = ms$iso2)
country_year <- country_year |>
  left_join(iso_for_manifesto, by = "country") |>
  select(country, iso2, year, eu_positive, eu_negative, net_pro_eu, n_parties)

eu_manifesto <- list(country_year = country_year, eu_year = eu_year)

# ---- 4. Write atomically ---------------------------------------------------
write_with_meta <- function(df, stem, n_inputs_label) {
  pq_path   <- file.path(out_dir, paste0(stem, ".parquet"))
  meta_path <- file.path(out_dir, paste0(stem, ".meta.json"))
  pq_tmp    <- tempfile(tmpdir = out_dir, fileext = ".parquet")
  meta_tmp  <- tempfile(tmpdir = out_dir, fileext = ".json")

  arrow::write_parquet(df, pq_tmp, compression = "zstd")
  jsonlite::write_json(
    list(source         = stem,
         built_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
         inputs         = n_inputs_label,
         builder_script = "R/build_eu_politics.R",
         rows           = nrow(df)),
    meta_tmp, auto_unbox = TRUE, pretty = TRUE
  )
  file.rename(pq_tmp,   pq_path)
  file.rename(meta_tmp, meta_path)
  message("Built ", stem, ": ", nrow(df), " rows -> ", pq_path)
}

write_with_meta(
  eu_government,
  "eu_government_composition",
  "data-external/parlgov/{view_cabinet,view_party} + data-manual/eu-member-states.csv"
)
write_with_meta(
  country_year,
  "eu_manifesto_eu_stance_country",
  "data-external/manifesto/MPDataset_MPDS2024a.csv + data-manual/eu-member-states.csv"
)
write_with_meta(
  eu_year,
  "eu_manifesto_eu_stance_eu",
  "data-external/manifesto/MPDataset_MPDS2024a.csv + data-manual/eu-member-states.csv"
)
