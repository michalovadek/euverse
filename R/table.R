# table.R  —  shared wrappers for DT and gt that apply unified styling.
# Sourced from .qmd pages via:  source(here::here("R", "table.R"))
# Owner: see AGENTS.md §6.

dt_mo <- function(df, ..., page_length = 15) {
  DT::datatable(
    df,
    rownames   = FALSE,
    extensions = c("Buttons"),
    options    = list(
      pageLength = page_length,
      dom        = "Bfrtip",
      buttons    = c("csv", "excel")
    ),
    class = "compact stripe hover",
    ...
  )
}

gt_mo <- function(df, ...) {
  out <- gt::gt(df, ...)
  out <- gt::opt_table_font(out, font = list(gt::default_fonts(), "Inter"))
  gt::tab_options(
    out,
    table.border.top.style    = "none",
    table.border.bottom.style = "none",
    heading.title.font.weight = "bold"
  )
}
