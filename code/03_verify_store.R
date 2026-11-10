## 03_verify_store.R
##
## Verify each written partition round-trips: st_read() of the original file
## vs read_parcels(names = "original") from the store. Run in a fresh R
## session (separate from 02_standardize.R).
## Output: docs/store_verification.csv, one row per year x county.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

PD_ROOT <- "/Users/matthewhockert/research/parcel_data"
source(file.path(PD_ROOT, "R", "read_parcels.R"))
source(file.path(PD_ROOT, "R", "verify_read.R"))

# partitions present in the store
written <- list.dirs(file.path(PD_ROOT, "data", "standardized"), recursive = TRUE, full.names = FALSE)
written <- written[grepl("^year=[0-9]{4}/county=", written)]
parts <- tibble(year = as.integer(sub("^year=([0-9]{4}).*", "\\1", written)),
                county = sub(".*county=", "", written))

# Optional: Rscript code/03_verify_store.R 2025  -> verify only those years
# (results are merged into docs/store_verification.csv)
only_years <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)))
only_years <- only_years[!is.na(only_years)]
if (length(only_years)) parts <- parts %>% filter(year %in% only_years)

raw_source <- function(yr, cty) {
  if (yr == 2025) {
    return(list(dsn = file.path(PD_ROOT, "data", "raw", "2025", sprintf("Parcels%s.shp", cty)),
                layer = sprintf("Parcels%s", cty)))
  }
  if (yr == 2021) {               # GeoPackage year (see 02_standardize.R)
    return(list(dsn = file.path(PD_ROOT, "data", "raw", "2021", "plan_regonal_parcels_2021.gpkg"),
                layer = sprintf("Parcels2021%s", cty)))
  }
  if (yr %in% c(2023, 2024)) {   # geodatabase years (see 02_standardize.R)
    list(dsn = file.path(PD_ROOT, "data", "raw", yr, sprintf("plan_regonal_parcels_%d.gdb", yr)),
         layer = sprintf("Parcels%d%s", yr, cty))
  } else {
    list(dsn = file.path(PD_ROOT, "data", "raw", yr, sprintf("Parcels%d%s.shp", yr, cty)),
         layer = sprintf("Parcels%d%s", yr, cty))
  }
}

verification <- bind_rows(lapply(seq_len(nrow(parts)), function(i) {
  yr <- parts$year[i]; cty <- parts$county[i]; s <- raw_source(yr, cty)
  old <- st_read(s$dsn, layer = s$layer, quiet = TRUE)
  new <- read_parcels(years = yr, counties = cty, names = "original")
  r <- compare_reads(old, new, label = paste(yr, cty))
  # stored pt_x / pt_y must lie inside their own parcel (guards the
  # misalignment fixed by 04_fix_points.R)
  pq <- arrow::read_parquet(file.path(PD_ROOT, "data", "standardized", paste0("year=", yr),
                                      paste0("county=", cty), "part-0.parquet"),
                            col_select = c("row_in_file", "pt_x", "pt_y"))
  pq <- pq[order(pq$row_in_file), ]
  has <- !is.na(pq$pt_x)
  pts <- st_as_sf(data.frame(i = which(has), x = pq$pt_x[has], y = pq$pt_y[has]), coords = c("x", "y"), crs = 26915)
  gl  <- st_make_valid(parcel_linearize(st_geometry(old)))
  hits <- st_intersects(pts, gl)
  r$pts_inside_own <- mean(vapply(seq_len(nrow(pts)), function(k) pts$i[k] %in% hits[[k]], logical(1)))
  r$ok <- r$ok && r$pts_inside_own == 1
  r
}))

print(verification, n = Inf, width = Inf)
cat("partitions verified OK:", sum(verification$ok), "of", nrow(verification), "\n")
ver_path <- file.path(PD_ROOT, "docs", "store_verification.csv")
if (length(only_years) && file.exists(ver_path)) {
  verification <- bind_rows(read_csv(ver_path, show_col_types = FALSE) %>%
                              filter(!label %in% verification$label), verification)
}
write_csv(verification, ver_path)
