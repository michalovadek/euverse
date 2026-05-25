# Future Content Suggestions

> Working notes from the long-horizon improvement pass on 2026-05-25,
> after all four standalone trackers were ported and the shared
> helpers (`R/freshness.R::write_snapshot`, `R/celex.R`) were extracted.
> Each suggestion is sized so it could be brainstormed → spec'd →
> implemented in a single session, reusing the existing infra. Listed
> in rough order of expected payoff.

## 1. EU Enlargement tracker

**What:** A single page visualising the EU's accession history and
candidate pipeline. Three or four chunks:

- Stacked area showing Member State count over time, coloured by
  accession wave (Founding Six → 1973 expansion → 1981/1986 southern
  → 1995 EFTA → 2004 Eastern → 2007 Bulgaria/Romania → 2013 Croatia
  → Brexit subtraction → future candidates).
- A timeline strip with bars per country showing accession year and,
  for the UK, exit year.
- A "candidate countries" table (Albania, Bosnia, Moldova, etc.) with
  status as of the latest snapshot.
- Map of current members vs candidate status.

**Data:** Already have `data-final/eu_member_states.parquet`. Only the
candidate-country list is new — small CSV in `data-manual/`. No
upstream API.

**Effort:** Half a day. Reuses every shared helper. Would showcase
the `data-final/` consolidation we already built for eu-court and
eu-law.

**Why it earns a spot:** the eu_member_states master is currently
joined into two pages but never visualised on its own — readers
don't see what it *is*, only that the trackers use it.

## 2. EU Commission composition tracker

**What:** A page showing all College compositions since 1958 — who
held which portfolio, country, gender, party family, total tenure.

- Stacked bar of women's representation per College over time.
- Heatmap of "which countries got which portfolio" — e.g. Trade has
  rotated through DE, UK, NL, IE; Competition through NL, ES.
- Tenure-length histogram (how often Commissioners serve their full
  term vs resign mid-mandate).

**Data:** No clean API. Hand-curated CSV in `data-manual/` —
relatively bounded (~150 Commissioners total). Could draw from
European Parliament's official Commissioner list and Wikipedia for
party affiliation.

**Effort:** 1-2 days, mostly the data-gathering. Page itself is
straightforward.

## 3. EU Budget tracker

**What:** Net contributions vs receipts per Member State per year,
plus MFF (multi-annual financial framework) totals over time. The
classic "who pays, who receives" UK-style debate, depoliticised.

**Data:** Eurostat `gov_10a_main` or directly from DG BUDGET's
annual financial reports (PDF — would need scraping). Could reuse
the `R/fetch_eurostat_*.R` pattern.

**Effort:** 2-3 days. The scraping is the hard part if going via
DG BUDGET; Eurostat alone gives "in/out" but not detailed receipts
breakdown.

## 4. EU Elections tracker

**What:** European Parliament composition over time — seats by
country, party family, gender, age. Latest election as headline,
historical context as supporting charts.

**Data:** `data-external/parlgov/` already mirrors ParlGov's
election results. Sidecar `_SOURCE.md` is the TODO already on the
AGENTS.md backlog.

**Effort:** Half a day for a v1, more if drilling into roll-call
voting (which would need a separate VoteWatch-style scraper).

## 5. EU Migration / Asylum tracker

**What:** Asylum applications, first-time vs repeat, recognition
rates, by destination country and country of origin. Highly
topical, well-documented Eurostat data, charts already well-tested
elsewhere in the academic literature.

**Data:** Eurostat `migr_asyappctzm` (asylum applicants), `migr_asydcfsta`
(decisions). Both have an existing R package pattern (we already use
`eurostat::get_eurostat` in `fetch_eurostat_teimf050.R`).

**Effort:** 1 day per indicator. Politically sensitive — needs
careful "data, not narrative" framing.

---

# Infrastructure improvements (lower visibility, high leverage)

## A. Per-page OG image generation

The `_quarto.yml` already sets `open-graph: true` but there's no
`og:image` for any page. When a tracker URL is shared on
Twitter/Mastodon/LinkedIn, it shows the bare URL.

**Approach:** Add a `R/build_og_images.R` that renders a 1200×630 PNG
per tracker page using a stripped-down `theme_mo()` ggplot — title,
subtitle, one signature chart. Write to `assets/og/<page>.png`,
reference from page YAML.

**Effort:** 2-3 hours.

## B. Schema.org Dataset structured data per tracker

Add a `<script type="application/ld+json">` block to each tracker's
header.html injection with `Dataset`, `creator`, `dateModified`,
`distribution` (the parquet URL). Lets Google Dataset Search and
academic indexers pick the trackers up.

**Effort:** 2-3 hours. The trickiest part is keeping the
`dateModified` synced to the freshness sidecar.

## C. Unit tests for `R/celex.R` and `R/freshness.R`

The unification refactor on 2026-05-25 was eyeballed via a smoke
render. A `tests/testthat/` directory with `test_celex_parsing()`
and `test_write_snapshot_round_trip()` would catch regressions
*before* they propagate to all 9 fetchers.

**Approach:** Add `testthat` to `renv.lock`; one short test file
per helper; wire into CI as a pre-render step.

**Effort:** 3-4 hours. Highest value for the curia ECLI workaround
in `fetch_curia_cases.R` — that bypass should have a regression test.

## D. Pre-render smoke test for each fetcher's parquet

The current CI runs fetchers with `continue-on-error`, which means
a broken fetcher silently writes a previous-snapshot-fallback page.
Adding a `R/validate_snapshot.R` that checks every `data-apis/*_latest.parquet`
against an expected min-row count would catch silent staleness.

**Effort:** Half a day.

## E. CNAME / custom domain

The site currently lives at `<user>.github.io/euverse/`. If Michal
wants `euverse.ovadek.com` or similar, it's a 10-minute change:
add `CNAME` file with the domain, configure DNS A records to point
at GitHub Pages IPs.

**Effort:** Trivial once a domain is decided.

---

# Speculative / "if we have a quiet week"

- **Voting power index calculator** — Shapley-Shubik / Banzhaf for
  Council QMV. Static R computation, would showcase how voting
  weights have shifted with each enlargement.
- **Council presidency tracker** — chronological list with
  highlights per presidency. Mostly hand-curated.
- **Comitology tracker** — Eur-Lex sector 3 also includes
  implementing/delegated acts; could break out comitology committee
  activity over time. Probably better as a section *within* eu-law
  rather than its own page.
- **MEP turnover heatmap** — for each EP term, fraction of MEPs
  who served the full term vs resigned, by country and group.
