## hennepin_conservation_easements_verify.R (2026-11-07)
##  hcra_paper/02_build_exposure.R:231  read_hennepin_polygons(yr), GEOM_YEARS 2005:2023:
##     old st_read(dsn, layer = "Parcels{yr}Hennepin", quiet = TRUE), dsn = data/fgdb...2023.gdb (2023) or
##     data/shp_plan_regonal_parcels_{yr}; relative to hcra_paper/. Exact mode.
##  hcra_paper/02_build_exposure.R:861  attribute loop, 2005:2022: old foreign::read.dbf(...Parcels{yr}Hennepin.dbf,
##     as.is = TRUE) vs read_parcels(geometry = "none"). Exact mode.
##  ag_preserve_analysis/parcel_analysis.R:19-30, :68 (2005:2022): old paths under Desktop/HCRA are gone.
suppressMessages({library(sf); library(dplyr)})
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))
root <- "/Users/matthewhockert/research/hennepin_conservation_easements/hcra_paper"
out  <- "/Users/matthewhockert/research/parcel_data/verification/hennepin_conservation_easements_results.csv"
if (file.exists(out)) file.remove(out)
emit <- function(r) {
  write.table(r, out, sep = ",", row.names = FALSE, col.names = !file.exists(out), append = file.exists(out), qmethod = "double")
  print(as.data.frame(r[, c("label", "rows_old", "rows_new", "cols_differ", "geom_ok", "ok")]))
}
tmpl <- function(label, old_path, mode) tibble::tibble(label = label, rows_old = NA_integer_, rows_new = NA_integer_,
  rows_ok = NA, names_ok = NA, cols_differ = "", geom_ok = NA, geom_detail = "", ok = NA, old_path = old_path, mode = mode, note = "")

# ag_preserve_analysis/parcel_analysis.R: old paths missing
sv <- read.csv("/Users/matthewhockert/research/parcel_data/docs/store_verification.csv", stringsAsFactors = FALSE)
H <- "/Users/matthewhockert/Desktop/HCRA"
ag <- rbind(data.frame(site = "19", year = 2023, old = file.path(H, "fgdb_plan_regonal_parcels_2023/plan_regonal_parcels_2023.gdb")),
            data.frame(site = c("24", "26", "28", "30"), year = c(2022, 2021, 2020, 2006), old = NA),
            data.frame(site = "68", year = 2005:2022, old = NA))
ag$old[is.na(ag$old)] <- file.path(H, sprintf("shp_plan_regonal_parcels_%d", ag$year[is.na(ag$old)]))
for (i in seq_len(nrow(ag))) {
  stopifnot(!file.exists(ag$old[i]))
  key <- paste(ag$year[i], "Hennepin")
  r <- tmpl(sprintf("ag_preserve_analysis/parcel_analysis.R:%s %d Hennepin", ag$site[i], ag$year[i]), ag$old[i], "old path missing")
  r$rows_new <- sv$rows_new[sv$label == key]; r$ok <- isTRUE(as.logical(sv$ok[sv$label == key]))
  r$note <- "old path missing; store partition already verified in docs/store_verification.csv"; r$via_raw <- NA
  emit(r)
}

# 02_build_exposure.R:861 (.dbf attributes), fast
for (yr in 2005:2022) {
  shp <- resolve_old(file.path(root, sprintf("data/shp_plan_regonal_parcels_%d/Parcels%dHennepin.shp", yr, yr)))
  via_raw <- isTRUE(attr(shp, "via_raw")); p <- sub("\\.shp$", ".dbf", shp)
  old <- foreign::read.dbf(p, as.is = TRUE)
  new <- read_parcels(years = yr, counties = "Hennepin", names = "original", geometry = "none", as_shapefile = (yr %in% c(2021, 2024)))
  r <- compare_reads(old, new, label = sprintf("hcra_paper/02_build_exposure.R:861 %d Hennepin", yr))
  r$old_path <- p; r$via_raw <- via_raw; r$mode <- "exact (read.dbf vs geometry = none)"; r$note <- ""
  emit(r); rm(old, new, r); invisible(gc())
}

# 02_build_exposure.R:231 (polygons)
for (yr in 2005:2023) {
  dsn <- resolve_old(if (yr == 2023) file.path(root, "data/fgdb_plan_regonal_parcels_2023/plan_regonal_parcels_2023.gdb") else
         file.path(root, sprintf("data/shp_plan_regonal_parcels_%d/Parcels%dHennepin.shp", yr, yr)))
  via_raw <- isTRUE(attr(dsn, "via_raw"))
  old <- st_read(dsn, layer = sprintf("Parcels%dHennepin", yr), quiet = TRUE)
  new <- read_parcels(years = yr, counties = "Hennepin", names = "original", as_shapefile = (yr %in% c(2021, 2024)))
  r <- compare_reads(old, new, label = sprintf("hcra_paper/02_build_exposure.R:231 %d Hennepin", yr))
  r$old_path <- as.character(dsn); r$via_raw <- via_raw; r$mode <- "exact"; r$note <- ""
  emit(r); rm(old, new, r); invisible(gc())
}
