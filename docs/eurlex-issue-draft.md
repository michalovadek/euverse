# elx_curia_list: upstream HTML pages stopped being refreshed by Curia (2025-10-20)

## Title suggestion
`elx_curia_list()` returns stale data: Curia's `c1/c2/t2/f1_juris.htm` no longer maintained

## Summary

`elx_curia_list("all")` underlying source — Curia's static HTML case-list pages — has stopped being maintained by the curia.europa.eu publisher. As of 2026-05-27, all four files still serve content frozen at 2025-10-20, with the live response in some cases even *regressed* to an earlier state than what was briefly published in late October / early November 2025.

Result: code that depends on `elx_curia_list()` for current case information silently returns ~8 months of stale data and no entries for 2026 cases at all, despite EUR-Lex itself having ~260+ 2026 case notices published by mid-May 2026.

## Evidence

`HEAD` request on all four URLs:

```
c1_juris.htm  last-modified: Mon, 20 Oct 2025 13:38:24 GMT
c2_juris.htm  last-modified: Mon, 20 Oct 2025 13:38:17 GMT
t2_juris.htm  last-modified: Mon, 20 Oct 2025 13:38:24 GMT
f1_juris.htm  last-modified: Mon, 20 Oct 2025 13:38:11 GMT
```

Pattern frequencies in the live `c2_juris.htm` HTML body today:
| Pattern    | Hits |
|------------|------|
| `C-\d+/26` | 0    |
| `C-\d+/25` | 2,814 (last case is C-670/25) |
| `C-\d+/24` | 3,754 |

But Wayback Machine snapshots show the file *did* briefly contain newer content:

- **2025-10-10** snapshot: digest `KMOAL...`
- **2025-10-28** snapshot: digest `TXSS...` (different from above)
- **2025-11-11** snapshot: digest `DIU2...`, contains cases through **C-709/25**
- **2026-02-07** snapshot: digest `W74X...`
- **2026-05-27** (live today): contains cases only through C-670/25 — a *regression* from the 11-11 state

So the file isn't just stale — the publisher appears to have either intentionally rolled back the dynamic update or accidentally redeployed an older copy that nobody noticed.

Wayback CDX log:
```
https://web.archive.org/cdx/search/cdx?url=https%3A%2F%2Fcuria.europa.eu%2Fen%2Fcontent%2Fjuris%2Fc2_juris.htm
```

## EUR-Lex SPARQL is unaffected

A broad sector-6 query via `elx_make_query("any", sector = 6, include_date = TRUE) |> elx_run_query()` returns 88 distinct C-XXX/26 cases (max case number 276 as of today) and 174 distinct T-XXX/26 cases. The notice CELEX types `CN` / `TN` / `FN` carry cases as soon as they are lodged in OJ C.

Set arithmetic on 2020-2024 (Curia × EUR-Lex case keys = court+year+case_number):

| Year | Court | In both | Only Curia | Only EUR-Lex |
|------|-------|---------|-----------:|-------------:|
| 2020 | CJ    | 725     | 3          | 0            |
| 2022 | CJ    | 791     | 6          | 0            |
| 2024 | CJ    | 821     | 89         | 0            |
| 2025 | CJ    | 579     | 91         | 173          |
| 2026 | CJ    | 0       | 0          | 88           |

So before the Curia freeze, Curia was slightly more complete than EUR-Lex (a few dozen cases per year without a published OJ-C notice); after the freeze, EUR-Lex is the only signal.

## Suggested action

I don't think the package needs to *fix* this since the bug isn't in `eurlex` — but two things would help users:

1. **`?elx_curia_list` documentation**: add a note that the source URLs are static HTML files Curia regenerates on a manual schedule, and that as of late 2025 / 2026 there is no guarantee the file is current. Point users to the SPARQL endpoint (sector 6) for newer cases.

2. **Optional: SPARQL-based fallback or helper**. Consider exporting a thin wrapper like `elx_cases_list()` that returns a case-existence dataframe (one row per court+year+case_number) derived from sector-6 SPARQL across all document types — at least until upstream c2_juris.htm is alive again. Schema would be roughly: `case_id`, `court`, `case_year`, `case_number`, `first_celex`, `first_doc_date`, `n_docs`.

## Reproducer

```r
library(eurlex)
raw <- elx_curia_list("all", parse = FALSE)
# Should contain /26 cases (we're 5 months into 2026), returns 0:
sum(grepl("/26$", raw$case_id), na.rm = TRUE)
# Last case_id present is C-670/25, despite Wayback snapshots showing
# C-709/25 was briefly published in Nov 2025:
max(raw$case_id[grepl("/25$", raw$case_id)])
```

## Workaround for downstream users (working code)

Until the upstream file is alive again, you can derive a more complete case list from EUR-Lex SPARQL:

```r
library(eurlex); library(dplyr); library(stringr)
raw <- elx_make_query("any", sector = 6, include_date = TRUE) |>
  elx_run_query()
cases <- raw |>
  mutate(court    = str_sub(celex, 6, 6),
         case_year   = as.integer(str_sub(celex, 2, 5)),
         case_number = as.integer(str_sub(celex, 8, 11))) |>
  filter(court %in% c("C", "T", "F"),
         !is.na(case_year), !is.na(case_number), case_number > 0) |>
  distinct(court, case_year, case_number)
```

This covers ~95-99% of historical cases plus the post-October-2025 tail Curia misses.
