# EUPROPS

European Political Parties dataset (EUPROPS), version 2.0.

**Committed (the form trackers use):**
- `euprops_v2_0.parquet` — zstd-compressed parquet conversion of the
  upstream Stata file, identical data, dramatically smaller. Built by
  `R/build_data_external_parquets.R`.
- `EUPROPS codebook 2.0.docx` — variable codebook.

**Gitignored (regenerable raw upstream):**
- `EUPROPS_v2_0.dta` — original Stata file (342 MB). Exceeds GitHub's
  100 MB per-file hard limit so cannot be committed.

To regenerate the parquet from a fresh upstream pull:

1. Place `EUPROPS_v2_0.dta` in this folder (copy from your local copy, or
   re-download from the EUPROPS project's official distribution).
2. From the repo root: `Rscript R/build_data_external_parquets.R`. The
   script is idempotent; it overwrites the existing parquet.

Tracker pages consume `euprops_v2_0.parquet` via
`arrow::read_parquet("data-external/euprops/euprops_v2_0.parquet")`. If a
page needs only a subset, write the trimmed view to
`data-final/euprops_<subset>.parquet` once (idempotent build) rather than
re-trimming on every render.

source-repo: EUPROPS project (external, academic)
source-version: 2.0
pulled-at: pre-2026-05-24 (predates this convention)
