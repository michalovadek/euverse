# ParlGov

ParlGov — Parliaments and Governments Database, comprehensive coverage of
European parliamentary democracies (elections, parties, governments).

**Committed:**
- `view_cabinet.parquet` — parquet conversion of view_cabinet.csv (smaller).
- `view_election.parquet` — parquet conversion of view_election.csv.
- `view_party.csv` — small enough to keep as CSV (~0.25 MB).
- `view_variable.csv` — small.
- `codebook.md`, `readme.txt`.

Built by `R/build_data_external_parquets.R`.

**Gitignored (regenerable):**
- `parlgov-experimental.db`, `parlgov-stable.db` — SQLite source databases
  (~7 MB + ~5 MB; above the <5 MB soft target). The committed parquet
  views above cover the needs of all current trackers.
- `parlgov-stable.xlsx` — human-readable Excel mirror of the db.
- `view_cabinet.csv`, `view_election.csv` — raw CSVs the parquets are
  derived from.

To regenerate the parquet views:

1. Place `view_cabinet.csv` and `view_election.csv` in this folder. They
   come from running the ParlGov web export, or `sqlite3 parlgov-stable.db
   ".header on" ".mode csv" "SELECT * FROM view_cabinet;" > view_cabinet.csv`
   (etc.) against either of the .db files.
2. From the repo root: `Rscript R/build_data_external_parquets.R`.

If a tracker needs a different ParlGov view, query the .db directly via
`DBI::dbConnect(RSQLite::SQLite(), "data-external/parlgov/parlgov-stable.db")`
in a build script under `data-final/`, then write the result to
`data-final/parlgov_<subset>.parquet` (committed).

source-repo: ParlGov project, https://www.parlgov.org/
pulled-at: pre-2026-05-24 (predates this convention)
