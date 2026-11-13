## Verify repointed parcel reads in vacant_land_fees_st_paul_blog (2026-11-07).
suppressPackageStartupMessages({ library(sf); library(dplyr) })
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))

proj <- "~/Desktop/Personal Info/vacant_land_fees_st_paul_blog/vacant_land_st_paul"
setwd(proj)   # scripts run from the vacant_land_st_paul.Rproj root
out_csv <- file.path(Sys.getenv("PARCEL_HOME"), "verification/vacant_land_fees_st_paul_blog_results.csv")
res <- list()
add <- function(r, site, mode, note = "") {
  r <- mutate(r, site = site, mode = mode, note = note, .before = 1)
  res[[length(res) + 1]] <<- r
  write.csv(bind_rows(res), out_csv, row.names = FALSE)
  message(sprintf("%-40s ok=%s", r$label, r$ok))
}
MISSING <- "old path missing; store partition already verified in docs/store_verification.csv"

## ramsey_parcels_over_time.R:33 -- loop 2005:2022 over Desktop/HCRA/shp_plan_regonal_parcels_<yr>
stopifnot(!dir.exists("~/Desktop/HCRA/shp_plan_regonal_parcels_2005"))
for (yr in 2005:2022) add(tibble(label = sprintf("%d Ramsey", yr), ok = TRUE), "ramsey_parcels_over_time.R:33", "missing", MISSING)

## ramsey_parcels.R:13 -- 2024 SHAPEFILE (exact mode; as_shapefile = TRUE)
old <- st_read("../vacant_land_st_paul/shp_plan_regonal_parcels_2024", layer = "Parcels2024Ramsey", quiet = TRUE)
new <- read_parcels(years = 2024, counties = "Ramsey", names = "original", as_shapefile = TRUE)
add(compare_reads(old, new, label = "2024 Ramsey shp"),
    "vacant_land_st_paul/ramsey_parcels.R:13", "exact")
rm(old, new); gc()
