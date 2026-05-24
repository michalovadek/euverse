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
  diverging  = RColorBrewer::brewer.pal(11, "BrBG"),
  # EU Member State flag colours, keyed by ISO-2 country code. Used for
  # country-coloured plots where cardinality (28+ states) exceeds the
  # categorical palette. Lifted from the standalone eu-veto-tracker's
  # hand-picked vector with one collision resolved (HU was #DC143C, the
  # same as PL — HU is now a distinguishable green #436F4D drawn from the
  # Hungarian flag's middle stripe). EA is a neutral grey for aggregate
  # reference lines.
  ms_flags = c(
    AT = "#ED2939", BE = "#FAE042", BG = "#00966E", HR = "#FF0000",
    CY = "#DFAF2C", CZ = "#11457E", DK = "#D1001F", EE = "#0072CE",
    FI = "#003580", FR = "#0055A4", DE = "#FFCE00", GR = "#0D5EAF",
    HU = "#436F4D", IE = "#169B62", IT = "#009246", LV = "#990000",
    LT = "#FDB913", LU = "#00A1DE", MT = "#C8102E", NL = "#FF4F00",
    PL = "#DC143C", PT = "#FF0000", RO = "#002B7F", SK = "#0B4EA2",
    SI = "#009B77", ES = "#AA151B", SE = "#FECC00", GB = "#00247D",
    EA = "#666666"
  )
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
