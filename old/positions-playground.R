library(tidyverse)

# create date vector
dates <- tibble(
  date = seq.Date(from=as.Date("1951-01-01"), to=Sys.Date(), by="days")
)

# load data
input_cmp <- read.csv("data-input/MPDataset_MPDS2024a.csv")
input_parlgov <- read.csv("data-input/view_cabinet.csv")
input_pg_party <- read.csv("data-input/view_party.csv")

# prepare data general
input_cmp <- input_cmp |> 
  mutate(date = lubridate::dmy(edate),
         edate = as.character(date),
         seatshare = absseat / totseats,
         seatshare = ifelse(is.na(seatshare), 0, seatshare),
         proeu = per108 - per110,
         proeu = ifelse(is.na(proeu), 0, proeu),
         rile = ifelse(is.na(rile), 0, rile),
)

# if caretaker gov, consider all parties governing? different from ParlGov coding
input_parlgov <- input_parlgov |> 
  mutate(date = as.Date(start_date))
  # mutate(cabinet_party = ifelse(caretaker == 1, 1, cabinet_party))

# eu country names
eu_countries <- c(
  "Austria", "Belgium", "Bulgaria", "Czech Republic", "Cyprus", "Malta", "Poland", "Romania",
  "Slovakia", "Slovenia", "United Kingdom", "Hungary", "Ireland", "Italy", "Lithuania", "Latvia",
  "Luxembourg", "Netherlands", "Portugal", "Finland", "Sweden", "Spain", "Estonia", "France", 
  "Germany", "Greece", "Croatia", "Denmark"
)

# subset to EU countries and after 1945
input_cmp <- input_cmp |>
  filter(countryname %in% eu_countries) |> 
    filter(date > as.Date("1945-01-01"))

input_parlgov <- input_parlgov |> 
  filter(country_name %in% eu_countries) |> 
  filter(date > as.Date("1945-01-01"))

# merge parlgov party and cabinet to add CMP id
input_parlgov <- input_parlgov |> 
  left_join(input_pg_party |> select(party_id, cmp)) 

# daily party in gov
day_party_ingov <- input_parlgov |> 
  select(country_name, cmp, date, cabinet_party, cabinet_name) |> 
  arrange(country_name, date, cabinet_name, cmp) |> 
  mutate(
    tmp = match(cabinet_name, unique(cabinet_name)),
    date_end = as.Date(date[match(tmp, tmp - 1)])-1,
    tmp = NULL, 
    .by = country_name
  ) |> 
  as_tibble() |> 
  mutate(date_end = case_when(
    is.na(date_end) ~ as.Date("2024-01-01"),
    T ~ date_end
  )) |> 
  rowwise() |> 
  mutate(day = list(seq(date, date_end, by = "day"))) |> 
  unnest(cols = c(day)) |> 
  select(day, country_name, cmp, cabinet_party)

# missing cmp codes would need to be added manually here

# merge cmp to daily ingov
day_cmp_ingov <- day_party_ingov |> 
  filter(!is.na(cmp)) |> 
  left_join(
    select(input_cmp, date, party, partyname, seatshare, rile, proeu),
    by = c("cmp"="party", "day" = "date")
  ) |> 
  group_by(cmp) |> 
  fill(partyname, rile, proeu, seatshare) |> 
  ungroup() |> 
  filter(!is.na(cmp))  |>
  filter(!is.na(partyname))

# plot all parties RILE
day_cmp_ingov |> 
  ggplot(aes(x = day)) +
  geom_line(aes(y = rile, colour = partyname), alpha = 0.3, show.legend = FALSE) +
  theme_minimal() +
  facet_wrap(~countryname)
ggsave("eu_party_cmp_rile.png", width = 9, height = 7, bg = "white")

# government seat-weighted RILE average
mean_day_eugov <- day_cmp_ingov |> 
  filter(cabinet_party == 1) |> 
  summarize(
    n_parties = length(unique(cmp)),
    rile_weighted = sum(rile * seatshare) / sum(seatshare),
    proeu_weighted = sum(proeu * seatshare) / sum(seatshare),
    .by = c(day, country_name)
  )

# plot government RILE
mean_day_eugov |> 
  ggplot(aes(x = day)) +
  geom_line(aes(y = rile_weighted), color = "red") +
  theme_minimal() +
  facet_wrap(~country_name)
ggsave("eu_gov_cmp_rile.png", width = 9, height = 7, bg = "white")

# plot government proEU
mean_day_eugov |> 
  ggplot(aes(x = day)) +
  geom_line(aes(y = proeu_weighted), color = "blue") +
  theme_minimal() +
  facet_wrap(~country_name)
ggsave("eu_gov_cmp_proeu.png", width = 9, height = 7, bg = "white")

# number of parties in gov
mean_day_eugov |> 
  ggplot(aes(x = day)) +
  geom_line(aes(y = n_parties), color = "black") +
  theme_minimal() +
  scale_y_continuous(breaks = c(0:13)) +
  facet_wrap(~country_name, scales = "free_y") 
ggsave("eu_gov_cmp_nparties.png", width = 9, height = 7, bg = "white")

# number of missing CMP codes from ParlGov
day_party_ingov |> 
  filter(is.na(cmp), cabinet_party == 1) |> 
  count(day, country_name) |> 
  ggplot(aes(x = day, y = n)) +
  geom_bin_2d() +
  theme_minimal() +
  scale_y_continuous(breaks = c(0:13)) +
  facet_wrap(~country_name, scales = "free_y") +
  labs(y = "Number of missing link party ids")
ggsave("eu_gov_cmp_missing.png", width = 9, height = 7, bg = "white")

# party splits during term
# caretaker governments

# save
write_csv(mean_day_eugov, file = "data-output/cmp_parlgov_daily.csv")
haven::write_dta(mean_day_eugov, path = "data-output/cmp_parlgov_daily.dta")
save(mean_day_eugov, file = "data-output/cmp_parlgov_daily.RData")

### Jonathan's data ###
jondat <- haven::read_dta("data-input/euhetero.dta") |> 
  left_join(mean_day_eugov, by = c("country_name", "date"="day"))

jondat |> 
  ggplot(aes(x = date)) +
  geom_line(aes(y = govteu), color = "red") +
  geom_line(aes(y = proeu_weighted), color = "blue") +
  facet_wrap(~country_name) +
  theme_minimal()

# wildly different RILE sd
jondat |> 
  summarise(
    mean_govteu = mean(govteu, na.rm  = TRUE),
    mean_proeu_weighted = mean(proeu_weighted, na.rm  = TRUE),
    mean_govtlr = mean(govtlr, na.rm   = TRUE),
    mean_rile_weighted = mean(rile_weighted, na.rm  = TRUE),
    govteu_sd = sd(govteu, na.rm  = TRUE),
    proeu_weighted_sd = sd(proeu_weighted, na.rm   = TRUE),
    govtlr_sd = sd(govtlr, na.rm     = TRUE),
    rile_weighted_sd = sd(rile_weighted, na.rm   = TRUE)
  )

  jondat |> 
    #filter(country_name == "Luxembourg") |> 
    summarise(govt_eu_sd = sd(govteu), .by = country_name)

jondat |> 
  count(govteu) |> 
  mutate(prop = prop.table(n))

input_cmp |> 
  filter(countryname == "Germany") |> 
  ggplot(aes(x = date, y = proeu)) +
  geom_point() +
  geom_line() +
  facet_wrap(~party)
