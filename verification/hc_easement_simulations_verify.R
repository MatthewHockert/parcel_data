## hc_easement_simulations_verify.R: ~/Desktop/UMN/hc_easement_simulations/parcel_analysis.R:32
## (process_shapefile loop, years 2005:2022). Old read: st_read("data/shp_plan_regonal_parcels_{yr}",
## layer = "Parcels{yr}Hennepin"), relative to the project root. Exact mode, one year at a time.
suppressMessages({library(sf); library(dplyr)})
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))
root <- "~/Desktop/UMN/hc_easement_simulations"
out  <- file.path(Sys.getenv("PARCEL_HOME"), "verification/hc_easement_simulations_results.csv")
## YEARS env var (e.g. YEARS="2016:2019") reruns only those years and replaces their rows in the CSV.
yrs <- if (nzchar(Sys.getenv("YEARS"))) eval(parse(text = Sys.getenv("YEARS"))) else 2005:2022
if (file.exists(out)) {
  keep <- read.csv(out, stringsAsFactors = FALSE)
  keep <- keep[!keep$label %in% sprintf("parcel_analysis.R:32 %d Hennepin", yrs), ]
  file.remove(out)
  if (length(yrs) < 18 && nrow(keep)) write.csv(keep, out, row.names = FALSE)
}
for (yr in yrs) {
  # same layer as st_read(folder, layer = "Parcels{yr}Hennepin"); resolve_old() swaps in the raw copy only for a stuck iCloud placeholder
  old_path <- resolve_old(file.path(root, sprintf("data/shp_plan_regonal_parcels_%d/Parcels%dHennepin.shp", yr, yr)))
  via_raw <- isTRUE(attr(old_path, "via_raw"))
  old <- st_read(old_path, quiet = TRUE)
  lab <- sprintf("parcel_analysis.R:32 %d Hennepin", yr)
  new <- tryCatch(read_parcels(years = yr, counties = "Hennepin", names = "original", as_shapefile = (yr %in% c(2021, 2024))), error = function(e) conditionMessage(e))
  r <- if (is.character(new)) tibble::tibble(label = lab, rows_old = nrow(old), rows_new = NA_integer_, rows_ok = NA, names_ok = NA,
         cols_differ = paste("read_parcels error:", new), geom_ok = NA, geom_detail = "", ok = FALSE) else compare_reads(old, new, label = lab)
  r$old_path <- as.character(old_path); r$via_raw <- via_raw; r$mode <- "exact"
  write.table(r, out, sep = ",", row.names = FALSE, col.names = !file.exists(out), append = file.exists(out), qmethod = "double")
  print(as.data.frame(r[, c("label", "rows_old", "rows_new", "cols_differ", "geom_ok", "ok")]))
  rm(old, new, r); invisible(gc())
}
