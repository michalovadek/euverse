# freshness.R  —  reads "latest" snapshots written by R/fetch_<src>.R and
# produces an HTML badge users see on every tracker page.
# Sourced from .qmd pages via:  source(here::here("R", "freshness.R"))
# Owner: see AGENTS.md §4.

read_with_freshness <- function(stem,
                                dir = here::here("data-apis")) {
  data_path <- file.path(dir, paste0(stem, "_latest.parquet"))
  meta_path <- file.path(dir, paste0(stem, "_latest.meta.json"))
  if (!file.exists(data_path)) {
    stop(sprintf(
      "No latest snapshot for '%s' at '%s'. Has R/fetch_%s.R ever succeeded?",
      stem, data_path, stem
    ), call. = FALSE)
  }
  if (!file.exists(meta_path)) {
    stop(sprintf(
      "Missing meta sidecar for '%s' at '%s'.", stem, meta_path
    ), call. = FALSE)
  }
  list(
    data      = arrow::read_parquet(data_path),
    meta      = jsonlite::fromJSON(meta_path),
    meta_path = meta_path
  )
}

freshness_badge <- function(meta) {
  fetched <- suppressWarnings(
    as.POSIXct(meta$fetched_at, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  )
  age_h <- if (length(fetched) == 1L && !is.na(fetched)) {
    as.numeric(difftime(Sys.time(), fetched, units = "hours"))
  } else {
    NA_real_
  }

  # Severity escalates with age. Unknown freshness defaults to "important"
  # (worst case shown) so pages never silently mislead about staleness.
  cls <- if (is.na(age_h))     "callout-important"
         else if (age_h < 36)  "callout-tip"
         else if (age_h < 72)  "callout-warning"
         else                  "callout-important"

  fetched_label <- if (is.na(age_h)) "unknown" else paste0(format(fetched, "%Y-%m-%d %H:%M"), " UTC")
  source_label  <- if (is.null(meta$source) || !nzchar(as.character(meta$source))) "(source unknown)" else as.character(meta$source)
  rows_label    <- if (is.null(meta$rows)) "?"
                   else if (is.numeric(meta$rows)) format(meta$rows, big.mark = ",")
                   else as.character(meta$rows)

  htmltools::HTML(sprintf(
    '<div class="callout %s" style="margin:0 0 1em 0;padding:8px 12px;border-left:4px solid;border-radius:3px;">Data as of <strong>%s</strong> &middot; source: %s &middot; %s rows</div>',
    cls, fetched_label, source_label, rows_label
  ))
}
