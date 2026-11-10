# hwy-36-job-access: load_parcel_data.R (and paper_replication/ copy) read
# data/washington_county_parcels/shp_plan_regonal_parcels_<yr>/Parcels<yr>WashingtonPoints.shp
# for 2015-2020. Check read_parcels(yr, "Washington", layer = "points", names = "original")
# returns the same table: names, rows, every attribute (NA-aware), geometry. 2026-11-10.
suppressPackageStartupMessages(library(sf))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
base <- "/Users/matthewhockert/Desktop/AO/hwy-36-job-access/hwy-36/data/washington_county_parcels"
mism <- function(x, y) xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & x != y)
out <- list()
for (yr in 2015:2020) {
  ln  <- paste0("Parcels", yr, "WashingtonPoints")
  old <- st_read(file.path(base, paste0("shp_plan_regonal_parcels_", yr), paste0(ln, ".shp")), layer = ln, quiet = TRUE)
  new <- read_parcels(years = yr, counties = "Washington", layer = "points", names = "original")
  a <- st_drop_geometry(old); b <- st_drop_geometry(new)
  names_ok <- identical(names(a), names(b)); rows_ok <- nrow(a) == nrow(b)
  diff_cols <- if (names_ok && rows_ok) names(a)[vapply(names(a), function(k)
    !identical(class(a[[k]]), class(b[[k]])) || any(mism(as.character(a[[k]]), as.character(b[[k]]))), logical(1))] else NA
  geom_ok <- rows_ok && identical(st_as_binary(st_geometry(old)), st_as_binary(st_geometry(new)))
  max_d <- if (rows_ok) max(sqrt(rowSums((st_coordinates(old)[, 1:2] - st_coordinates(new)[, 1:2])^2))) else NA
  crs_ok <- st_crs(old) == st_crs(new)
  out[[length(out) + 1]] <- data.frame(year = yr, rows_old = nrow(a), rows_new = nrow(b), names_ok, crs_ok,
    cols_differ = paste(diff_cols, collapse = ";"), geom_identical = geom_ok, max_point_move_m = max_d)
  print(tail(out, 1)[[1]])
}
res <- do.call(rbind, out)
write.csv(res, "/Users/matthewhockert/research/parcel_data/verification/hwy36_points_results.csv", row.names = FALSE)
