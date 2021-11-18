#' @param ind_file str, output path for the indicator file
#' @param ... `targets` to be included in the indicator file. Added as unquoted names
summarize_targets <- function(ind_file, nms) {
  ind_tbl <- tar_meta(all_of(nms)) %>%
    select(tar_name = name, filepath = path, hash = data) %>%
    mutate(filepath = unlist(filepath))

  readr::write_csv(ind_tbl, ind_file)
  return(ind_file)
}
