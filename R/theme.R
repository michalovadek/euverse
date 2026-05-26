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
  # Hand-picked per ISO-2. The flag of Slovenia is white-blue-red
  # horizontal stripes, so we use the middle-stripe blue rather than
  # the previous teal-green (which was confusingly close to the Italian
  # / Bulgarian / Irish greens and matched no actual element of the
  # Slovenian flag).
  ms_flags = c(
    AT = "#ED2939", BE = "#FAE042", BG = "#00966E", HR = "#FF0000",
    CY = "#DFAF2C", CZ = "#11457E", DK = "#D1001F", EE = "#0072CE",
    FI = "#003580", FR = "#0055A4", DE = "#FFCE00", GR = "#0D5EAF",
    HU = "#436F4D", IE = "#169B62", IT = "#009246", LV = "#990000",
    LT = "#FDB913", LU = "#00A1DE", MT = "#C8102E", NL = "#FF4F00",
    PL = "#DC143C", PT = "#FF0000", RO = "#002B7F", SK = "#0B4EA2",
    SI = "#2376B3", ES = "#AA151B", SE = "#FECC00", GB = "#00247D",
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
      legend.title         = ggplot2::element_blank(),
      # Axis tick + text spacing: 4 pt ticks plus an explicit 6-pt right
      # margin on y-axis text keeps categorical labels (rapporteurs,
      # veto issues, country names) from sitting flush against the panel
      # edge. Same idea for x-axis date ticks.
      axis.ticks.length    = ggplot2::unit(4, "pt"),
      axis.text.y          = ggplot2::element_text(margin = ggplot2::margin(r = 6)),
      axis.text.x          = ggplot2::element_text(margin = ggplot2::margin(t = 4)),
      # Outer chart margin: room on the right so x-axis terminal tick
      # labels (e.g. final year "2026") don't get cut off when the chart
      # is rendered at the page's right edge.
      plot.margin          = ggplot2::margin(t = 6, r = 16, b = 6, l = 6)
    )
}

mono <- function(x) {
  # Wrap a computed value in <code> so inline R expressions render in
  # backtick style. Use in qmd as:  `r mono(format(n_acts, big.mark = ','))`
  # to get the value styled like Markdown inline code (monospace, slight
  # background tint, more distinct from prose than plain <strong>).
  htmltools::HTML(paste0("<code>", as.character(x), "</code>"))
}

int_breaks <- function(n = 5) {
  # ggplot2 break function that forces INTEGER ticks. Use on any axis
  # whose underlying variable is a count (there's no such thing as half
  # a veto, half a case, half a Member State). Falls back to pretty()
  # which already gives integer ticks for small ranges, then de-dupes
  # to handle the small-range case where pretty(0:3) would yield
  # c(0, 0.5, 1.0, 1.5, ...) and we want c(0, 1, 2, 3).
  function(x) {
    breaks <- pretty(x, n = n)
    unique(as.integer(round(breaks)))
  }
}

date_breaks_min3 <- function(n = 6) {
  # Break function for date axes that ALWAYS returns at least 3 ticks
  # regardless of the data range. Default scales::breaks_pretty drops
  # to 1 tick (e.g. just "2026") for ranges shorter than ~18 months,
  # which leaves the reader without context. This function tries
  # pretty_breaks(n) first and, if it returns <3 ticks, falls back to
  # an explicit width-based break: 2 months for very narrow ranges,
  # 6 months / year / 5-year for progressively wider ones. Pair with
  # scales::label_date_short so the format adapts (year-only when
  # year-level, YYYY-MM when month-level).
  function(x) {
    breaks <- scales::breaks_pretty(n = n)(x)
    if (length(breaks) >= 3) return(breaks)
    range_d <- as.numeric(diff(range(x)))
    width <- if (range_d <= 400)  "2 months"
             else if (range_d <= 1500) "6 months"
             else if (range_d <= 4000) "1 year"
             else                       "5 years"
    scales::breaks_width(width)(x)
  }
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
