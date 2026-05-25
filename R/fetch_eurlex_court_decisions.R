# fetch_eurlex_court_decisions.R
# Source: Eur-Lex SPARQL, sector 6 (court decisions). Plus title fetches
# for celexes with missing procedure metadata to infer procedure class.
# Cleaning derived from old/eucourtstats.Rmd lines 482-664.

suppressPackageStartupMessages({
  library(here); library(eurlex); library(dplyr); library(tidyr); library(stringr); library(purrr)
})
source(here::here("R", "freshness.R"))
source(here::here("R", "celex.R"))

src     <- "eurlex_court_decisions"
out_dir <- here::here("data-apis")

# ---- 1. fetch ---------------------------------------------------------------
df <- tryCatch({
  raw <- elx_make_query(
    "any", sector = 6,
    include_date = TRUE,
    include_court_procedure = TRUE,
    include_court_origin = TRUE,
    include_original_language = TRUE,
    include_court_formation = TRUE,
    include_judge_rapporteur = TRUE,
    include_ecli = TRUE
  ) |> elx_run_query()

  # ---- 2a. bring data to celex level --------------------------------------
  decisions <- raw |>
    mutate(clx_type  = str_sub(celex, 6, 7),
           clx_num   = as.integer(str_sub(celex, 8, 11)),
           clx_year  = celex_year(celex),
           clx_court = celex_court(celex),
           dec_type  = case_when(
             clx_type %in% c("CJ", "TJ", "FJ")             ~ "Judgment",
             clx_type %in% c("CO", "CB", "TO", "TB", "FO", "FB") ~ "Order",
             clx_type %in% c("CV", "CX")                   ~ "Opinion",
             TRUE ~ NA_character_
           )) |>
    filter(!is.na(dec_type), !str_detect(celex, "_INF|_SUM")) |>
    separate_wider_delim(cols = courtprocedure,
                         delim = " - ",
                         too_few = "align_start",
                         too_many = "merge",
                         cols_remove = TRUE,
                         names = c("procedure", "procedure_outcome")) |>
    mutate(procedure = ifelse(clx_type %in% c("FB", "FJ", "FO") & is.na(procedure),
                              "Staff case", procedure)) |>
    filter(!procedure %in% c("Rectification")) |>
    group_by(celex) |>
    reframe(
      decision          = str_c(unique(dec_type), collapse = "~~~"),
      ecli              = str_c(unique(ecli),     collapse = "~~~"),
      date              = str_c(unique(date),     collapse = "~~~"),
      procedure         = str_c(unique(procedure), collapse = "~~~"),
      procedure_outcome = str_c(unique(procedure_outcome), collapse = "~~~"),
      rapporteur        = str_c(unique(jr),       collapse = "~~~"),
      formation         = str_c(unique(cf),       collapse = "~~~"),
      language          = str_c(unique(origlang), collapse = "~~~"),
      origin            = str_c(unique(courtorigin), collapse = "~~~")
    ) |>
    mutate(across(everything(), ~str_squish(.)))

  # ---- 2b. dedupe CO/CB pairs (keep CO) -----------------------------------
  decisions <- decisions |>
    mutate(clx_type  = str_sub(celex, 6, 7),
           clx_num   = as.integer(str_sub(celex, 8, 11)),
           clx_year  = celex_year(celex),
           clx_court = celex_court(celex),
           clx_dec   = str_sub(celex, 7, 7)) |>
    group_by(clx_court, clx_year, clx_num) |>
    mutate(dupl = any(clx_dec %in% "B") & any(clx_dec %in% "O")) |>
    ungroup() |>
    filter(!(dupl == TRUE & clx_dec == "B")) |>
    select(-dupl)

  # ---- 2c. title fetches for missing procedures ---------------------------
  # CAP at 300 most-recent missing-procedure cases. The current eu-court
  # decisions data has ~5700 missing-procedure rows (mostly very old
  # cases); fetching titles for all would take ~3 hours per nightly CI
  # run. Capping at 300 most-recent covers the cases readers actually
  # care about (current jurisprudence) while keeping the fetcher fast.
  # Older missing-procedure cases get procedure_class = "Other" and
  # NA origin, which is acceptable for the page's historical aggregates.
  MAX_TITLE_FETCHES <- 300L
  missing_procs <- decisions |>
    filter(is.na(procedure) | procedure == "" | procedure == "NA") |>
    arrange(desc(date)) |>
    slice(1:min(MAX_TITLE_FETCHES, dplyr::n()))
  message("Fetching titles for ", nrow(missing_procs),
          " missing-procedure cases (capped at ", MAX_TITLE_FETCHES, ")...")

  safe_fetch_title <- possibly(function(url) {
    out <- eurlex::elx_fetch_data(url, "title")
    if (length(out) == 0L || is.null(out)) return(NA_character_)
    as.character(out)[[1L]]
  }, otherwise = NA_character_)

  missing_procs_titles <- missing_procs |>
    mutate(title = map_chr(
      str_c("http://publications.europa.eu/resource/celex/", celex),
      safe_fetch_title
    )) |>
    mutate(title = str_squish(title)) |>
    mutate(
      procedure = case_when(
        str_detect(title, "Rectification")                                   ~ "Rectification",
        str_detect(title, "Opinion of the Court|Request for an Opinion")     ~ "Request for an Opinion",
        str_detect(title, "DEP ")                                            ~ "Other",
        str_detect(celex, "FB") | str_detect(title, "[Ss]taff|[Cc]ivil [Ss]ervice") ~ "Staff case",
        str_detect(title, "reliminary referen|for a prelim|reliminary ruli") ~ "Preliminary reference",
        str_detect(title, "Commission( of the European Communities)? v (?!(Parliament|Council|European))") ~ "Failure to fulfil obligations",
        str_detect(celex, "FB") | str_detect(title, "[Aa]nnulment|Trademark|Trade Mark") ~ "Action for annulment",
        str_detect(celex, "FB") | str_detect(title, "damages")               ~ "Action for damages",
        str_detect(title, " (v|contre) (European Commission|Commission|Council|European Parliament|Parliament|EUIPO|OHIM|OHMI|ECB|Office for Har|European Union|Office de l'|EASO|EMA)") ~ "Action for annulment",
        TRUE ~ NA_character_
      ),
      origin = case_when(
        str_detect(title, "Czech Republic|Nejvyšš|Czechia") ~ "Czechia",
        str_detect(title, "Slovak Republic|Najvyšš|Prešov|Slovakia") ~ "Slovakia",
        str_detect(title, "Polish|Poland") ~ "Poland",
        str_detect(title, "Belgiqu|Hof van Cass|Brussel|Belgium") ~ "Belgium",
        str_detect(title, "Finland") ~ "Finland",
        str_detect(title, "Salzburg|Wien|Austria") ~ "Austria",
        str_detect(title, "Veliko Tarn|Varna|Bulgaria|Sofiys") ~ "Bulgaria",
        str_detect(title, "Juzgado|Audiencia Provincial|Tribunal Superior de Justicia|Spain") ~ "Spain",
        str_detect(title, "România|Romania") ~ "Romania",
        str_detect(title, "Rijeci|Croati|lučice") ~ "Croatia",
        str_detect(title, "Slovenia") ~ "Slovenia",
        str_detect(title, "Cyprus") ~ "Cyprus",
        str_detect(title, "Estonia") ~ "Estonia",
        str_detect(title, "Sweden") ~ "Sweden",
        str_detect(title, "Luxembourg") ~ "Luxembourg",
        str_detect(title, "Denmark|Dane?mark") ~ "Denmark",
        str_detect(title, "Hellenic|Greece|Simvoulio|Simboulio") ~ "Greece",
        str_detect(title, "Portugese|Tribunal da Relação|(?<!TAP )Portugal") ~ "Portugal",
        str_detect(title, "Lietuv|Vilniaus|Lithuania") ~ "Lithuania",
        str_detect(title, "Latvijas|Augstākās|Latvia") ~ "Latvia",
        str_detect(title, "Italia|Italy|Tribunale Amministrativ|Tribunale di|Consiglio di|Corte Su") ~ "Italy",
        str_detect(title, "Bíróság|Magyar|Budapest|Szeged|Hungary|Hongri") ~ "Hungary",
        str_detect(title, "Conseil d|(?<!Air )France") ~ "France",
        str_detect(title, "Irland|(?<!Northern )Ireland") ~ "Ireland",
        str_detect(title, "Netherlands|Den Haag|Raad van Ber|College van|Rechtbank Am|Raad [Vv]an St|Hoge Raad") ~ "Netherlands",
        str_detect(title, "England \\& Wales|England and Wales|Her Majest|United Kingdom") ~ "United Kingdom",
        str_detect(title, "Deutschland|Regensburg|Germany|Landgericht K|Amtsgericht") ~ "Germany",
        TRUE ~ NA_character_
      )
    )

  decisions <- decisions |>
    filter(!celex %in% missing_procs$celex) |>
    bind_rows(missing_procs_titles |> select(-title)) |>
    filter(!procedure %in% c("Rectification"))

  # ---- 2d. derive procedure_class, court_long, formation_simple ----------
  decisions |>
    mutate(procedure_class = case_when(
      str_detect(procedure, "eference.*preliminary|Preliminary reference") ~ "Preliminary rulings",
      str_detect(procedure, "Action for annulm")                           ~ "Annulment procedures",
      str_detect(procedure, "[Ff]ailure to fulf")                          ~ "Infringement proceedings",
      str_detect(procedure, "[Ss]taff")                                    ~ "Staff cases",
      TRUE                                                                 ~ "Other"
    )) |>
    mutate(court_long = case_when(
      clx_court == "C" ~ "Court of Justice",
      clx_court == "T" ~ "General Court",
      clx_court == "F" ~ "Civil Service Tribunal",
      TRUE             ~ NA_character_
    )) |>
    mutate(formation_simple = case_when(
      str_detect(formation, "Grand Chamber")                       ~ "Grand Chamber",
      str_detect(formation, "[Ff]ull [Cc]ourt")                    ~ "Full Court",
      str_detect(formation, "Single|Vice-President|President|Judge hearing") ~ "Single Judge",
      TRUE                                                         ~ "Panel"
    )) |>
    mutate(rapporteur = case_when(
      str_detect(rapporteur, "O.Higgins") ~ "OHiggins",
      str_detect(rapporteur, "O'Keeffe")  ~ "OKeeffe",
      str_detect(rapporteur, "Cz.cz")     ~ "Czucz",
      str_detect(rapporteur, ".an .er Woude") ~ "van der Woude",
      TRUE                                ~ rapporteur
    )) |>
    # static celex-specific corrections (from old Rmd lines 642-664)
    filter(!celex %in% c("62019CO0519")) |>
    mutate(
      origin = case_when(
        celex == "62019CJ0550" ~ "Spain",
        celex == "62020CJ0339" ~ "France",
        celex == "62014CB0196" ~ "Germany",
        celex == "62022CB0578" ~ "Germany",
        celex == "62023CB0052" ~ "Germany",
        TRUE                   ~ origin
      ),
      language = case_when(
        celex == "62017CO0707" ~ "Bulgarian",
        celex == "62020CJ0306" ~ "Latvian",
        celex == "62017CJ0122" ~ "English",
        celex == "62018CJ0276" ~ "Hungarian",
        celex == "62013CJ0512" ~ "Dutch",
        celex == "62022CJ0142" ~ "English",
        celex == "61987CJ0245" ~ "German",
        celex == "62000CJ0167" ~ "German",
        celex == "62012CJ0293" ~ "English~~~German",
        TRUE                   ~ language
      )
    ) |>
    select(celex, clx_court, clx_year, date, decision, procedure, procedure_class,
           procedure_outcome, formation_simple, rapporteur, language, origin, ecli) |>
    as.data.frame()

}, error = function(e) {
  message("Fetch failed: ", conditionMessage(e))
  quit(status = 1L)
})

# ---- 3. validate ------------------------------------------------------------
if (!is.data.frame(df) || nrow(df) < 10000L) {
  message("Validation failed: too few rows (", nrow(df), ")")
  quit(status = 1L)
}
required_cols <- c("celex", "clx_court", "decision", "procedure_class", "date")
if (!all(required_cols %in% names(df))) {
  message("Validation failed: missing columns ",
          paste(setdiff(required_cols, names(df)), collapse = ", "))
  quit(status = 1L)
}

# ---- 4. write atomically ----------------------------------------------------
write_snapshot(df, src, out_dir)
