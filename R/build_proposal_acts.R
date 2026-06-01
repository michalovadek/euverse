# build_proposal_acts.R
#
# Build the proposal -> adopted-act linkage table. EUPROPS's `adoptedlaws`
# column carries the CELEX(es) of the act(s) that a proposal eventually led
# to — usually one, sometimes several (670 multi-value rows in EUPROPS v2).
# This script explodes that one-to-many relationship into a long table so
# downstream pages can model it cleanly.
#
# The relationship matters because some proposals fail to produce a single
# act (rejected/withdrawn) and some yield multiple (split during the
# legislative procedure). Treating it as 1:1 would silently lose info.
#
# Schema:
#   proposal_celex  — the proposing document's CELEX (NA where EUPROPID source
#                     uses an irregular id format like COUNCIL ref codes)
#   euprop_id       — EUPROPID for join with proposals_master
#   act_celex       — the adopted act's CELEX (one row per adopted act)
#   is_first        — TRUE if this matches EUPROPS's `firstlaw` (i.e. the
#                     first act produced from the proposal)
#   source_data     — always "euprops" (this table only carries EUPROPS-known
#                     linkages; post-cutoff proposal->act links are not
#                     currently tracked)

suppressPackageStartupMessages({
  library(here); library(dplyr); library(tidyr); library(stringr)
  library(arrow); library(jsonlite)
})

src     <- "proposal_acts"
out_dir <- here::here("data-final")

# Read the master so we get the already-sanity-filtered proposal set with
# constructed proposal_celex and stable euprop_id. Building on the master
# rather than re-reading raw EUPROPS keeps the filters in one place.
master <- arrow::read_parquet(
  here::here("data-final", "proposals_master.parquet")
)

# Explode adoptedlaws (";"-separated) into one row per (proposal, act).
linkages <- master |>
  filter(source_data == "euprops",
         !is.na(adoptedlaws),
         adoptedlaws != "") |>
  select(proposal_celex, euprop_id, firstlaw, adoptedlaws) |>
  separate_rows(adoptedlaws, sep = ";") |>
  mutate(act_celex = str_squish(adoptedlaws)) |>
  filter(act_celex != "") |>
  mutate(
    is_first    = act_celex == firstlaw,
    source_data = "euprops"
  ) |>
  select(proposal_celex, euprop_id, act_celex, is_first, source_data) |>
  distinct()

stopifnot(nrow(linkages) > 24000L)
stopifnot(all(c("proposal_celex", "euprop_id", "act_celex", "is_first") %in% names(linkages)))

pq_tmp   <- tempfile(tmpdir = out_dir, fileext = ".parquet")
meta_tmp <- tempfile(tmpdir = out_dir, fileext = ".json")
arrow::write_parquet(linkages, pq_tmp, compression = "zstd")
jsonlite::write_json(
  list(
    source         = src,
    built_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    inputs         = c("data-final/proposals_master.parquet"),
    builder_script = "R/build_proposal_acts.R",
    rows           = nrow(linkages),
    distinct_proposals = length(unique(linkages$euprop_id)),
    distinct_acts      = length(unique(linkages$act_celex)),
    multi_act_proposals = linkages |> count(euprop_id) |> filter(n > 1) |> nrow()
  ),
  meta_tmp, auto_unbox = TRUE, pretty = TRUE
)
file.rename(pq_tmp,   file.path(out_dir, paste0(src, ".parquet")))
file.rename(meta_tmp, file.path(out_dir, paste0(src, ".meta.json")))

message(sprintf(
  "Built %s: %d (proposal,act) linkages from %d distinct proposals producing %d distinct acts (%d proposals produced >1 act).",
  src, nrow(linkages),
  length(unique(linkages$euprop_id)),
  length(unique(linkages$act_celex)),
  linkages |> count(euprop_id) |> filter(n > 1) |> nrow()
))
