# data-manual/

Hand-curated CSVs entered or edited directly by the owner. Authoritative.

- Read-only from R scripts (fetchers never write here).
- Committed to git; small files only (<5 MB each).
- Name files `<topic>.csv` (snake_case, no dates — git history is the date record).

Current contents:
- `ms-vetoes.csv` — manually curated record of EU Member State vetoes (the
  data behind the eu-vetoes tracker, ported from the standalone
  eu-veto-tracker repo).
- `contested-competences/` — supporting material for the contested-competences
  research project.

See AGENTS.md §4 for the data-folder conventions.
