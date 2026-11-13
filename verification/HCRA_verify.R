## HCRA_verify.R: repointed reads in ~/Desktop/HCRA/HCRA_R (2026-11-07).
## Every old path under Desktop/HCRA is gone (the script was already broken), so no
## old-vs-new comparison is possible; each site/year is recorded against the store's
## own partition check in docs/store_verification.csv.
suppressMessages({library(sf); library(dplyr)})
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))
sv <- read.csv(file.path(Sys.getenv("PARCEL_HOME"), "docs/store_verification.csv"), stringsAsFactors = FALSE)
H <- "~/Desktop/HCRA"
gdb23 <- file.path(H, "fgdb_plan_regonal_parcels_2023/plan_regonal_parcels_2023.gdb")
shp <- function(y) file.path(H, sprintf("shp_plan_regonal_parcels_%d", y))
sites <- rbind(
  data.frame(site = "parcel_analysis.R:19", year = 2023, county = "Hennepin", old = gdb23),
  data.frame(site = "parcel_analysis.R:24", year = 2022, county = "Hennepin", old = shp(2022)),
  data.frame(site = "parcel_analysis.R:26", year = 2021, county = "Hennepin", old = shp(2021)),
  data.frame(site = "parcel_analysis.R:28", year = 2020, county = "Hennepin", old = shp(2020)),
  data.frame(site = "parcel_analysis.R:30", year = 2006, county = "Hennepin", old = shp(2006)),
  data.frame(site = "parcel_analysis.R:67", year = 2006:2022, county = "Hennepin", old = shp(2006:2022)),
  data.frame(site = "intersection.R:210", year = 2023, county = "Anoka", old = gdb23))
res <- do.call(rbind, lapply(seq_len(nrow(sites)), function(i) {
  s <- sites[i, ]; key <- paste(s$year, s$county)
  stopifnot(!file.exists(s$old))                       # still missing: nothing to compare
  sv_ok <- sv$ok[sv$label == key]
  data.frame(label = paste(s$site, s$year, s$county), old_path = s$old, mode = "old path missing",
             rows_old = NA, rows_new = sv$rows_new[sv$label == key], cols_differ = "", geom_ok = NA,
             ok = isTRUE(as.logical(sv_ok)),
             note = "old path missing; store partition already verified in docs/store_verification.csv")
}))
write.csv(res, file.path(Sys.getenv("PARCEL_HOME"), "verification/HCRA_results.csv"), row.names = FALSE)
print(res[, c("label", "rows_new", "ok")])
