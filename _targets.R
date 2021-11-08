suppressPackageStartupMessages(library(dplyr))
library(retry)
library(targets)
library(tarchetypes)
library(tibble)
library(tidyr)


options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("cowplot", "dataRetrieval", "htmlwidgets",
                            "rnaturalearth","leaflet", "leafpop",
                            "lubridate","tidyverse", "urbnmapr"))

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/map_sites.R")
source("3_visualize/src/map_timeseries.R")
source("3_visualize/src/plot_data_coverage.R")
source("3_visualize/src/plot_site_data.R")

# Configuration
# states <- c('WI', 'MN', 'MI')

states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')

parameter <- c('00060')

# Targets
list(
  # Identify oldest sites
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  # pull site data - inventory by state
  tar_target(nwis_inventory,
             oldest_active_sites %>%
               group_by(state_cd) %>%
               tar_group(),
             iteration = "group"),

  # pull site data - grab data
  tar_target(
    nwis_data,
    retry::retry(
      get_site_data(site_info = nwis_inventory, nwis_inventory$state_cd, parameter),
      when = "Ugh, the internet data transfer failed!",
      max_tries = 30
      ),
    pattern = map(nwis_inventory)
  ),

  # tally data
  tar_target(
    tally,
    tally_site_obs(site_data = nwis_data),
    pattern = map(nwis_data)
    ),

  # plot data
  tar_target(timeseries_png,
             plot_site_data(out_file = sprintf("3_visualize/out/timeseries_%s.png", unique(nwis_data$State)),
                            site_data = nwis_data, parameter = parameter),
             format = "file",
             pattern = map(nwis_data)),

  # Generate indicator file
  tar_target(
    summary_state_timeseries_csv,
    summarize_targets(ind_file = "3_visualize/log/summary_state_timeseries.csv",
                      nms = names(timeseries_png)),
    format = "file"
    ),

  # plot data coverage summary
  tar_target(
    data_coverage_png,
    plot_data_coverage(oldest_site_tallies = tally,
                                out_file = "3_visualize/out/site_map.png",
                                parameter = parameter)
    ),

  # Map oldest sites
  tar_target(
    site_map_png,
    map_sites("3_visualize/out/site_map.png", oldest_active_sites),
    format = "file"
    ),

  # Plot timeseries map
  tar_target(
    timeseries_map_html,
    map_timeseries(site_info = oldest_active_sites,
                   plot_info_csv = summary_state_timeseries_csv,
                   out_file = "3_visualize/out/timeseries_map.html"),
    format = "file"
  )
)
