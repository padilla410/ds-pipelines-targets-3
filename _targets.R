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
states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')

parameter <- c('00060')

# Static branching set-up
mapped_by_state_targets <- tar_map(
  values = tibble(state_abb = states) %>%
    mutate(state_plot_files = sprintf("3_visualize/out/timeseries_%s.png", state_abb)),

  # pull site data - inventory by state and then data
  tar_target(nwis_inventory,
             get_state_inventory(sites_info = oldest_active_sites, state_abb)),

  tar_target(nwis_data,
             retry::retry(
               get_site_data(site_info = nwis_inventory, state_abb, parameter),
               when = "Ugh, the internet data transfer failed!",
               max_tries = 30
             )
  ),

  # tally data
  tar_target(tally, tally_site_obs(site_data = nwis_data)),

  # plot data
  tar_target(timeseries_png,
             plot_site_data(out_file = state_plot_files,
                            site_data = nwis_data, parameter = parameter),
             format = "file"),

  # additional arguments to `tar_map`
  names = state_abb,
  unlist = FALSE
)

# Targets
list(
  # Identify oldest sites
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  # Combine static branches - calling the mapped targets and combining with custom fctn
  mapped_by_state_targets,
  tar_combine(obs_tallies,
              mapped_by_state_targets$tally,
              command = combine_obs_tallies(!!!.x)),

  # Generate indicator file
  tar_combine(
    summary_state_timeseries_csv,
    mapped_by_state_targets$timeseries_png,
    command = summarize_targets(ind_file = "3_visualize/log/summary_state_timeseries.csv", !!!.x),
    format = "file"
    ),

  # plot summary
  tar_target(
    data_coverage_png,
    plot_data_coverage(oldest_site_tallies = obs_tallies,
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
