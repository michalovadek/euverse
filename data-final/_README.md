# data-final/

Cross-cutting **derived / joined** data shared across multiple tracker pages.
Lives outside the three input folders because it's neither raw upstream
(`data-apis/`) nor hand-curated (`data-manual/`) nor mirrored from elsewhere
(`data-external/`) — it's a *processed* artifact, typically the result of
joining or normalising several of those inputs.

When to put something here:

- A single `eu_member_states_master.parquet` that every tracker joins against
  (member-state codes, accession dates, EA membership flag, country names in
  multiple languages, …) — built once from `data-manual/` country lists +
  external lookups, then reused.
- A `judges_master.parquet` joining IUROPA + external CV data so multiple
  judicial-politics trackers don't re-derive it.
- Any reference table that's expensive to build but cheap to read.

Convention:

- File names describe the JOINED CONCEPT, not the inputs:
  `eu_member_states_master.parquet`, not `manual_countries_x_external_iso.parquet`.
- A sibling `<name>.build.R` (or `R/build_<name>.R`) builds the file from
  inputs. The build script is idempotent: re-running it from the same inputs
  produces a byte-identical output.
- A sibling `<name>.meta.json` records `{built_at, inputs, builder_script,
  rows}` so consumers know the provenance.
- These files ARE committed to git — they're small, stable, and rebuilding
  on every page render would be wasteful.

Not for: nightly snapshots of upstream APIs (→ `data-apis/`), one-page
intermediate computations (do those inside the .qmd chunk), or raw mirrors
(→ `data-external/`).

See AGENTS.md §4.
