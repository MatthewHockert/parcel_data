## Verify repointed parcel reads in matthew_maps_saint_paul (2026-11-07).
## For each changed read site and each year/county it reads: OLD read exactly as
## the script did it, NEW read_parcels() call, compared per REPOINTING.md.
suppressPackageStartupMessages({ library(sf); library(dplyr) })
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
source(file.path(Sys.getenv("PARCEL_HOME"), "R/verify_read.R"))

proj <- "/Users/matthewhockert/Desktop/Personal Info/matthew_maps_saint_paul"
setwd(proj)   # the scripts setwd() here and use paths relative to it
out_csv <- "/Users/matthewhockert/research/parcel_data/verification/matthew_maps_saint_paul_results.csv"
res <- list()
add <- function(r, site, mode, note = "", via_raw = NA) {
  r <- mutate(r, site = site, mode = mode, note = note, via_raw = via_raw, .before = 1)
  res[[length(res) + 1]] <<- r
  write.csv(bind_rows(res), out_csv, row.names = FALSE)
  message(sprintf("%-55s ok=%s", r$label, r$ok))
}
MISSING <- "old path missing; store partition already verified in docs/store_verification.csv"

## Study area exactly as build_green_line_panel.R builds it
stations_sf <- read.csv("data/green_line_stations.csv") %>% filter(new_station == 1) %>%
  st_as_sf(coords = c("lon", "lat"), crs = 4326) %>% st_transform(26915)
study_area <- stations_sf %>% st_buffer(2 * 1609.34) %>% st_union()
study_wkt  <- st_as_text(study_area)

## 1. build_stpaul_origins.R:64 and 3d_dose_map.R:53 -- Parcels2014Ramsey.shp (exact).
##    Same file, same arguments (the dose map's absolute path is the same file),
##    so one comparison, recorded for both sites.
op <- resolve_old("Archive/shp_plan_regonal_parcels_2014/Parcels2014Ramsey.shp")   # raw copy if iCloud placeholder (Matt, 2026-11-08)
old <- st_read(op, quiet = TRUE)
new <- read_parcels(years = 2014, counties = "Ramsey", names = "original")
r <- compare_reads(old, new, label = "2014 Ramsey polygons")
add(r, "green_line_access/R/build_stpaul_origins.R:64", "exact", via_raw = attr(op, "via_raw"))
add(r, "green_line_access/R/3d_dose_map.R:53", "exact", "same file/args as build_stpaul_origins.R:64", via_raw = attr(op, "via_raw"))
rm(old, new); gc()

## 2. posts/05-urban-wealth-fund/index.qmd:123 -- 2024 gdb layer Parcels2024Ramsey (exact).
##    The Archive gdb here is a later (Dec 2025) public download with OWNER_NAME,
##    OWNER_MORE, TAX_NAME stripped (all NA); the store holds the Jan 2025 copy.
##    The post never uses those columns, so they are dropped from both sides.
op <- resolve_old("Archive/fgdb_plan_regonal_parcels_2024/plan_regonal_parcels_2024.gdb")
old <- st_read(op,
               layer = "Parcels2024Ramsey", quiet = TRUE)
new <- read_parcels(years = 2024, counties = "Ramsey", names = "original")
redacted <- c("OWNER_NAME", "OWNER_MORE", "TAX_NAME")
stopifnot(all(is.na(old[[redacted[1]]])), all(is.na(old[[redacted[2]]])), all(is.na(old[[redacted[3]]])))
old <- old[, setdiff(names(old), redacted)]; new <- new[, setdiff(names(new), redacted)]
add(compare_reads(old, new, label = "2024 Ramsey gdb (excl. OWNER_NAME, OWNER_MORE, TAX_NAME)"),
    "posts/05-urban-wealth-fund/index.qmd:123", "exact",
    "old copy is a later redacted download; columns unused by the script", via_raw = attr(op, "via_raw"))
rm(old, new); gc()

## 3. load_data.R:22 -- st_read("/Archive/<year>", query = ...) : path never existed
for (yr in 2014:2022) add(tibble(label = sprintf("%d Ramsey", yr), ok = TRUE), "load_data.R:22", "missing", MISSING)

## 4. Published Points sites (build_green_line_panel.R:54, build_stpaul_value_panel.R:102,
##    build_stpaul_origins.R:79). The first full points comparison (2005 Ramsey)
##    failed on rows: the published Points layer carries PINs (condo units etc.)
##    that are not in the polygon file, so metrogis points cannot reproduce them.
##    All three edits REVERTED. Diagnostic only: PIN coverage per year/county
##    (attributes only, no geometry), published Points vs read_parcels(metrogis).
real_pin <- function(p) nchar(gsub("[^0-9]", "", sub("^[0-9]{3}-", "", p))) >= 6
for (yr in 2005:2022) {
  for (cty in c("Ramsey", "Hennepin")) {
    pts_path <- file.path("Archive", sprintf("shp_plan_regonal_parcels_%d", yr), sprintf("Parcels%d%sPoints.shp", yr, cty))
    lyr <- sprintf("Parcels%d%sPoints", yr, cty)
    pts_path <- resolve_old(pts_path); vr <- attr(pts_path, "via_raw")   # store keeps no raw Points copies, so normally FALSE
    fld <- tryCatch(names(st_read(pts_path, query = sprintf('SELECT * FROM "%s" WHERE FID < 1', lyr), quiet = TRUE)),
                    error = function(e) NULL)
    if (is.null(fld) || !any(toupper(fld) == "PIN")) {   # iCloud placeholder (dbf unreadable) that did not download during the run
      add(tibble(label = sprintf("%d %s Points PIN coverage", yr, cty), ok = NA),
          "Points sites (build_green_line_panel.R:54, build_stpaul_value_panel.R:102, build_stpaul_origins.R:79)",
          "points-coverage", "NOT repointed (reverted); old Points file unreadable (iCloud placeholder, no raw copy), coverage not measured", via_raw = vr)
      next
    }
    pin_fld <- fld[toupper(fld) == "PIN"][1]   # field-name case varies by vintage
    old_pin <- st_read(pts_path, query = sprintf('SELECT %s FROM "%s"', pin_fld, lyr), quiet = TRUE)[[pin_fld]]
    poly_pin <- read_parcels(yr, cty, cols = "PIN", names = "original", geometry = "none")$PIN
    new_pin <- unique(poly_pin[real_pin(poly_pin)])   # what point_method = "metrogis" keeps
    add(tibble(label = sprintf("%d %s Points PIN coverage", yr, cty),
               rows_old = length(old_pin), rows_new = length(new_pin),
               rows_ok = length(old_pin) == length(new_pin),
               pins_old_not_in_store = sum(!unique(old_pin) %in% new_pin),
               pins_store_not_in_old = sum(!new_pin %in% old_pin),
               ok = setequal(old_pin, new_pin) && length(old_pin) == length(new_pin)),
        "Points sites (build_green_line_panel.R:54, build_stpaul_value_panel.R:102, build_stpaul_origins.R:79)",
        "points-coverage", "NOT repointed (reverted): store lacks Points-only PINs", via_raw = vr)
    rm(old_pin, poly_pin, new_pin); gc()
  }
}
message("done: ", nrow(bind_rows(res)), " rows")
