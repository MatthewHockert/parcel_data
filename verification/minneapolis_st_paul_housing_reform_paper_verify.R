## Verify repointed parcel reads in minneapolis_st_paul_housing_reform_paper (2026-11-07).
suppressPackageStartupMessages({ library(sf); library(dplyr) })
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))

proj <- "/Users/matthewhockert/Desktop/Personal Info/minneapolis_st_paul_housing_reform_paper"
setwd(proj)   # no setwd in the script; relative paths resolve from the .Rproj root
out_csv <- "/Users/matthewhockert/research/parcel_data/verification/minneapolis_st_paul_housing_reform_paper_results.csv"
res <- list()
add <- function(r, site, mode, note = "") {
  r <- mutate(r, site = site, mode = mode, note = note, .before = 1)
  res[[length(res) + 1]] <<- r
  write.csv(bind_rows(res), out_csv, row.names = FALSE)
  message(sprintf("%-40s ok=%s", r$label, r$ok))
}
MISSING <- "old path missing; store partition already verified in docs/store_verification.csv"

## ramsey_parcels.R:33 -- loop 2014:2022 over /Users/matthewhockert/Desktop/HCRA/shp_plan_regonal_parcels_<yr>
stopifnot(!dir.exists("/Users/matthewhockert/Desktop/HCRA/shp_plan_regonal_parcels_2014"))
for (yr in 2014:2022) add(tibble(label = sprintf("%d Ramsey", yr), ok = TRUE), "ramsey_parcels.R:33", "missing", MISSING)

## ramsey_parcels.R:137 -- 2023 gdb (exact)
old <- st_read("/Users/matthewhockert/Downloads/fgdb_plan_regonal_parcels_2023/plan_regonal_parcels_2023.gdb",
               layer = "Parcels2023Ramsey", quiet = TRUE)
new <- read_parcels(years = 2023, counties = "Ramsey", names = "original")
add(compare_reads(old, new, label = "2023 Ramsey gdb"), "ramsey_parcels.R:137", "exact")
rm(old, new); gc()

## ramsey_parcels.R:207 and :406 -- 2024 SHAPEFILE (exact mode; as_shapefile = TRUE); identical calls, one comparison
old <- st_read("shp_plan_regonal_parcels_2024", layer = "Parcels2024Ramsey", quiet = TRUE)
new <- read_parcels(years = 2024, counties = "Ramsey", names = "original", as_shapefile = TRUE)
r <- compare_reads(old, new, label = "2024 Ramsey shp")
add(r, "ramsey_parcels.R:207", "exact")
add(r, "ramsey_parcels.R:406", "exact", "same file/args as ramsey_parcels.R:207")
rm(old, new); gc()
