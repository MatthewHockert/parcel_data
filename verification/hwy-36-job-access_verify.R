## hwy-36-job-access_verify.R (2026-11-08)
## Sites: hwy-36/load_parcel_data.R:102 and hwy-36/paper_replication/load_parcel_data.R:101, read_parcels_layer().
##   Old: st_read(<folder>/Parcels{yr}WashingtonPoints.shp, layer = "Parcels{yr}WashingtonPoints", quiet = TRUE)
##        for folders data/washington_county_parcels/shp_plan_regonal_parcels_{2015..2020}.
##   New: read_parcels(yr, "Washington", names = "original", geometry = "point", point_method = "metrogis_rows",
##        orig_fid = yr %in% 2015:2017).
## Both scripts read the same files (paper_replication/data has no washington_county_parcels; the hwy-36/data
## copy is the one read). Plain exact mode (WKB geometry compare, no tolerances).
suppressMessages({library(sf); library(dplyr)})
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))
root <- "/Users/matthewhockert/Desktop/AO/hwy-36-job-access/hwy-36/data/washington_county_parcels"
out  <- "/Users/matthewhockert/research/parcel_data/verification/hwy-36-job-access_results.csv"
if (file.exists(out)) file.remove(out)
for (yr in 2015:2020) {
  p <- resolve_old(file.path(root, sprintf("shp_plan_regonal_parcels_%d/Parcels%dWashingtonPoints.shp", yr, yr)))
  via_raw <- isTRUE(attr(p, "via_raw"))
  old <- st_read(p, layer = sprintf("Parcels%dWashingtonPoints", yr), quiet = TRUE)
  new <- read_parcels(years = yr, counties = "Washington", names = "original", geometry = "point",
                      point_method = "metrogis_rows", orig_fid = yr %in% 2015:2017)
  r <- compare_reads(old, new, label = sprintf("load_parcel_data.R:102 + paper_replication/load_parcel_data.R:101 %d Washington", yr))
  r$has_orig_fid_old <- "ORIG_FID" %in% names(old); r$old_path <- as.character(p); r$via_raw <- via_raw; r$mode <- "exact"
  write.table(r, out, sep = ",", row.names = FALSE, col.names = !file.exists(out), append = file.exists(out), qmethod = "double")
  print(as.data.frame(r))
  rm(old, new, r); invisible(gc())
}
