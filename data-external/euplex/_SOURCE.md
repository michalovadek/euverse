# EUPlex

EUPlex dataset — EU legislation tracker output (the `eurlex` R package's
maintainer's research dataset).

**Committed:**
- `euplex.parquet` — zstd-compressed parquet conversion of the upstream
  CSV. Built by `R/build_data_external_parquets.R`.
- `euplex_codebook.pdf` — codebook.

**Gitignored:**
- `euplex.csv` — original CSV (32 MB). Above the project's <5 MB soft
  target; the parquet conversion is the committed form trackers consume.

To regenerate the parquet:

1. Place `euplex.csv` in this folder (re-pull via the `eurlex` package's
   data-export utilities, or copy from a local cache).
2. From the repo root: `Rscript R/build_data_external_parquets.R`.

source-repo: eurlex project (external; owner is also the maintainer)
pulled-at: pre-2026-05-24 (predates this convention)
