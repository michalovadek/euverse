# test_helpers.R
# Smoke tests for the shared helpers in R/. Plain base R (stopifnot +
# expect_equal-shaped wrappers) so no extra dependency on testthat —
# `Rscript tests/test_helpers.R` is all CI needs.
#
# Exit 0 = all pass; exit 1 = first failure halts execution.

# ---------------------------------------------------------------------------
# Resolve repo root so `Rscript tests/test_helpers.R` works regardless of cwd.
# ---------------------------------------------------------------------------
repo <- tryCatch(here::here(), error = function(e) getwd())
setwd(repo)

source("R/celex.R")
source("R/freshness.R")

n_pass <- 0L
expect <- function(actual, expected, label) {
  if (!isTRUE(all.equal(actual, expected))) {
    message("FAIL: ", label)
    message("  expected: ", paste(deparse(expected), collapse = " "))
    message("  actual:   ", paste(deparse(actual),   collapse = " "))
    quit(status = 1L)
  }
  n_pass <<- n_pass + 1L
}

# ---------------------------------------------------------------------------
# celex.R
# ---------------------------------------------------------------------------
expect(celex_year("32024R1234"),                 2024L,                   "celex_year single")
expect(celex_year(c("32024R1234", "31999L0005")), c(2024L, 1999L),         "celex_year vec")

expect(celex_act_type("32024R1234"),     "Regulation",     "act_type R")
expect(celex_act_type("32024L0001"),     "Directive",      "act_type L")
expect(celex_act_type("32024D0001"),     "Decision",       "act_type D")
expect(celex_act_type("32024H0001"),     "Recommendation", "act_type H")
expect(celex_act_type("32024A0001"),     "Other",          "act_type A (int. agreement) -> Other")
expect(celex_act_type(c("32024R1", "32024L1", "32024D1")),
       c("Regulation", "Directive", "Decision"),
       "act_type vec")

expect(celex_court("62020CJ0001"),     "C",     "court C")
expect(celex_court("62020TJ0001"),     "T",     "court T")
expect(celex_court("62020FB0001"),     "F",     "court F (CST)")

# ---------------------------------------------------------------------------
# freshness.R — write_snapshot round-trip + meta sidecar shape
# ---------------------------------------------------------------------------
td <- tempfile()
dir.create(td)
on.exit(unlink(td, recursive = TRUE), add = TRUE)

df <- data.frame(x = 1:3, y = letters[1:3], stringsAsFactors = FALSE)
write_snapshot(df, "smoke", out_dir = td)

data_path <- file.path(td, "smoke_latest.parquet")
meta_path <- file.path(td, "smoke_latest.meta.json")
expect(file.exists(data_path), TRUE, "write_snapshot wrote parquet")
expect(file.exists(meta_path), TRUE, "write_snapshot wrote meta")

round_trip <- arrow::read_parquet(data_path)
expect(nrow(round_trip),         3L,                       "round trip rows")
expect(names(round_trip),        c("x", "y"),              "round trip cols")
expect(as.character(round_trip$y), c("a", "b", "c"),       "round trip values")

meta <- jsonlite::fromJSON(meta_path)
expect(meta$source,                  "smoke",                 "meta source")
expect(meta$rows,                    3L,                      "meta rows")
expect(grepl("^\\d{4}-\\d{2}-\\d{2}T", meta$fetched_at), TRUE, "meta fetched_at ISO")
expect(nchar(meta$schema_hash),      64L,                     "meta schema hash sha256 length")

# ---------------------------------------------------------------------------
# freshness.R — badge severity escalates with age
# ---------------------------------------------------------------------------
fresh <- list(source = "x", fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), rows = 5)
stale <- list(source = "x", fetched_at = format(Sys.time() - 60 * 60 * 80, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), rows = 5)
unknown_age <- list(source = "x", fetched_at = NA, rows = 5)

expect(grepl("callout-tip",       as.character(freshness_badge(fresh))),       TRUE, "fresh -> tip class")
expect(grepl("callout-important", as.character(freshness_badge(stale))),       TRUE, "80h stale -> important class")
expect(grepl("callout-important", as.character(freshness_badge(unknown_age))), TRUE, "unknown age -> important class (worst-case)")

# ---------------------------------------------------------------------------
# freshness.R — combined picks the oldest input
# ---------------------------------------------------------------------------
old_meta <- list(source = "old", fetched_at = "2025-01-01T00:00:00Z", rows = 1)
new_meta <- list(source = "new", fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), rows = 2)
combined_html <- as.character(freshness_badge_combined(list(new_meta, old_meta)))
expect(grepl("2025-01-01", combined_html), TRUE, "combined picks oldest date")

# ---------------------------------------------------------------------------
# freshness.R — date helpers (keep prose "as of" in sync with the badge)
# ---------------------------------------------------------------------------
expect(fmt_date_nice(as.Date("2026-06-01")),  "1 June 2026",      "fmt_date_nice strips leading zero")
expect(fmt_date_nice(as.Date("2026-12-25")),  "25 December 2026", "fmt_date_nice two-digit day")
expect(fmt_date_nice(as.Date(NA)),            "unknown",          "fmt_date_nice NA -> unknown")
expect(as.character(freshness_date_combined(list(new_meta, old_meta))), "2025-01-01",
       "freshness_date_combined picks oldest date")

# ---------------------------------------------------------------------------
# freshness.R — check_rowcount (absolute floor + relative-drop guard).
# The `smoke` snapshot written above has rows = 3 in tempdir `td`.
# ---------------------------------------------------------------------------
expect(check_rowcount(100, "absent", dir = td, min_rows = 50), TRUE,  "rowcount: above floor, no prev")
expect(check_rowcount(10,  "absent", dir = td, min_rows = 50), FALSE, "rowcount: below absolute floor")
expect(check_rowcount(3,   "smoke",  dir = td, min_rows = 0),  TRUE,  "rowcount: equals prev is ok")
expect(check_rowcount(1,   "smoke",  dir = td, min_rows = 0, max_drop = 0.4), FALSE, "rowcount: >40% drop vs prev")

# ---------------------------------------------------------------------------
cat("All ", n_pass, " tests passed.\n", sep = "")
