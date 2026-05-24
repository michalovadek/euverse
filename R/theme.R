# theme.R  —  shared ggplot theme, palette, and ggiraph defaults.
# Sourced from .qmd pages via:  source(here::here("R", "theme.R"))
# Owner: see AGENTS.md §6.

mo_palette <- list(
  # Okabe-Ito 8-colour categorical palette (colourblind-safe).
  categorical = c(
    "#E69F00", "#56B4E9", "#009E73", "#F0E442",
    "#0072B2", "#D55E00", "#CC79A7", "#999999"
  ),
  # Sequential and diverging are functions of n so callers can request the
  # exact length they need (rather than slicing a fixed vector).
  sequential = function(n) viridis::viridis(n),
  diverging  = RColorBrewer::brewer.pal(11, "BrBG")
)

theme_mo <- function(base_size = 12) {
  ggplot2::theme_minimal(base_family = "Inter", base_size = base_size) +
    ggplot2::theme(
      plot.title           = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title.position  = "plot",
      panel.grid.minor     = ggplot2::element_blank(),
      panel.grid.major     = ggplot2::element_line(colour = "#eaeaea"),
      panel.background     = ggplot2::element_rect(fill = "white", colour = NA),
      plot.background      = ggplot2::element_rect(fill = "white", colour = NA),
      strip.text           = ggplot2::element_text(face = "bold"),
      legend.position      = "bottom",
      legend.title         = ggplot2::element_blank()
    )
}

register_ggiraph_defaults <- function() {
  ggiraph::set_girafe_defaults(
    opts_hover = ggiraph::opts_hover(
      css = "stroke:#666;stroke-width:1px;"
    ),
    opts_tooltip = ggiraph::opts_tooltip(
      css = paste0(
        "font-family:Inter,sans-serif;",
        "padding:6px 8px;",
        "background:#fff;",
        "border:1px solid #ddd;",
        "border-radius:4px;",
        "font-size:13px;"
      )
    )
  )
}
