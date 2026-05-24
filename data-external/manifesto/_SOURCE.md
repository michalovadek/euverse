# Manifesto Project

Comparative Manifesto Project / MARPOR — coded manifestos of political
parties. The committed file `MPDataset_MPDS2024a.csv` (~3 MB) sits just
under the project's <5 MB soft target so is kept tracked.

source-repo: Manifesto Project, https://manifesto-project.wzb.eu/
source-version: MPDS 2024a
pulled-at: pre-2026-05-24 (predates this convention)

When a tracker needs only a subset, prefer writing a parquet to
`data-final/manifesto_<subset>.parquet` rather than re-reading the full CSV
each render.
