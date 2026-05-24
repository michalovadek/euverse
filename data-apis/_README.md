# data-apis/

**Latest snapshots only.** Written nightly by `R/fetch_<src>.R` scripts via the
CI workflow.

Naming:
- `<src>_latest.parquet` — the data (parquet, zstd-compressed). Source-named,
  NOT page-named, so multiple tracker pages can reuse the same snapshot:
  `ecb_hicp_latest.parquet`, `eurostat_teimf050_latest.parquet`, etc.
- `<src>_latest.meta.json` — sidecar: `{source, fetched_at, rows, schema_hash}`.

Historical snapshots are NOT kept here. If a fetcher needs older data it
re-queries the live source. (We opted against accumulating monthly archives
because the API can always reconstruct history; see
docs/specs/2026-05-23-shared-infra-design.md §2.)

If you want a CLEANED join / derived view across multiple raw snapshots (e.g.
an "eu_member_states_master" table built from several of these + manual data),
that belongs in `data-final/`, not here.

Writes must be atomic per file (tempfile + rename). The `R/_fetch_template.R`
template encodes the contract.

See AGENTS.md §4.
