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

  htmltools::HTML(sprintf(
    '<div class="callout %s" style="margin:0 0 1em 0;padding:8px 12px;border-left:4px solid;border-radius:3px;">Data as of <strong>%s</strong></div>',
    cls, fetched_label
  ))
}

oldest_meta <- function(metas) {
  # The single meta with the OLDEST fetched_at — worst-case staleness, the
  # honest signal when a page joins data from several sources. Falls back to
  # an NA-dated stub when no input carries a parseable timestamp.
  fetched_times <- vapply(metas, function(m) {
    t <- suppressWarnings(
      as.POSIXct(m$fetched_at, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
    )
    if (length(t) == 1L && !is.na(t)) as.numeric(t) else NA_real_
  }, numeric(1))
  if (all(is.na(fetched_times))) return(list(fetched_at = NA))
  metas[[which.min(fetched_times)]]
}

# Render one badge for a multi-source page based on the oldest fetched_at.
freshness_badge_combined <- function(metas) freshness_badge(oldest_meta(metas))

# Date helpers — let a page's prose "as of <date>" track the same date the
# badge shows, instead of drifting to the render date.
freshness_date <- function(meta) {
  # Calendar date (UTC) the badge reports for a single source; NA if unknown.
  t <- suppressWarnings(
    as.POSIXct(meta$fetched_at, tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
  )
  if (length(t) != 1L || is.na(t)) return(as.Date(NA))
  as.Date(t, tz = "UTC")
}

freshness_date_combined <- function(metas) freshness_date(oldest_meta(metas))

fmt_date_nice <- function(d) {
  # Human date with no leading zero on the day: "1 June 2026".
  d <- as.Date(d)
  if (length(d) != 1L || is.na(d)) return("unknown")
  paste(as.integer(format(d, "%d")), format(d, "%B %Y"))
}

write_snapshot <- function(df, src,
                           out_dir = here::here("data-apis")) {
  # Atomic counterpart to read_with_freshness(). Every R/fetch_*.R ends with
  # this: write parquet + meta sidecar to a tempfile, then file.rename into
  # place so a half-written run never leaves the live snapshot in an
  # inconsistent state. Returns the path to the data file (for tests).
  data_tmp  <- tempfile(tmpdir = out_dir, fileext = ".parquet")
  meta_tmp  <- tempfile(tmpdir = out_dir, fileext = ".json")
  data_path <- file.path(out_dir, paste0(src, "_latest.parquet"))
  meta_path <- file.path(out_dir, paste0(src, "_latest.meta.json"))

  arrow::write_parquet(df, data_tmp, compression = "zstd")
  jsonlite::write_json(
    list(
      source      = src,
      fetched_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      rows        = nrow(df),
      schema_hash = digest::digest(names(df), algo = "sha256")
    ),
    meta_tmp, auto_unbox = TRUE, pretty = TRUE
  )
  file.rename(data_tmp, data_path)
  file.rename(meta_tmp, meta_path)
  message("Wrote ", src, " latest snapshot: ", nrow(df), " rows.")
  invisible(data_path)
}

manual_meta <- function(path, source_label = basename(path)) {
  # Build a freshness-badge-shaped meta from a hand-curated file's mtime.
  # Pages that consume manual data use this in place of the
  # read_with_freshness() contract (no fetcher exists for manual files).
  # Caller fills in $rows after counting (since the file might be filtered
  # before plotting).
  if (!file.exists(path)) {
    stop(sprintf("Manual data file not found: %s", path), call. = FALSE)
  }
  mtime <- file.info(path)$mtime
  list(
    source     = source_label,
    fetched_at = format(mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    # rows is NULL by default so the badge renders "?" if the caller
    # forgets to override after counting. Callers SHOULD override:
    #   meta <- manual_meta(path); meta$rows <- nrow(filtered_df)
    rows       = NULL
  )
}
