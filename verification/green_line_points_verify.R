## green_line_points_verify.R  (2026-11-09)
##
## Before repointing the three green_line Points reads in
## matthew_maps_saint_paul/green_line_access/R to the parcel_data Points store,
## check that what each READER FUNCTION returns is identical, old vs new:
##   old: st_read(Archive/shp_plan_regonal_parcels_<yr>/Parcels<yr><County>Points.shp)
##   new: read_parcels(yr, cty, layer = "points", names = "original")
## Compared on exactly the fields the readers use (build_green_line_panel.R
## read_county_year, build_stpaul_value_panel.R read_year,
## build_stpaul_origins.R read_points), and for the panel also after its
## study-area filter (GDAL wkt_filter vs st_filter on the same polygon).
## 2021 is the year to watch: Archive has the 2021 SHAPEFILE, the store holds
## the 2021 GeoPackage (shapefiles write missing numbers as 0, cut text to width).
## Output: verification/green_line_points_results.csv

suppressPackageStartupMessages({ library(sf); library(dplyr) })
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
MM <- "/Users/matthewhockert/Desktop/Personal Info/matthew_maps_saint_paul"
utm15 <- 26915

# study area exactly as build_green_line_panel.R builds it
stations_sf <- read.csv(file.path(MM, "data/green_line_stations.csv")) %>%
  filter(new_station == 1) %>%                                     # 17 new stops, as in the script
  st_as_sf(coords = c("lon", "lat"), crs = 4326) %>% st_transform(utm15)
gl_src <- readLines(file.path(MM, "green_line_access/R/build_green_line_panel.R"))
stopifnot(any(grepl("filter\\(new_station == 1\\)", gl_src)),      # guard: script still defines
          any(grepl("st_buffer\\(2 \\* 1609.34\\)", gl_src)))       # the study area this way
study_area <- stations_sf %>% st_buffer(2 * 1609.34) %>% st_union()
study_wkt  <- st_as_text(study_area)

is_saint_paul <- function(x) {
  norm <- toupper(trimws(gsub("\\.", "", x))); norm <- gsub("\\s+", " ", norm)
  norm %in% c("ST PAUL", "SAINT PAUL")
}
col <- function(raw, nme) if (nme %in% names(raw)) raw[[nme]] else NA

used <- function(raw) {            # union of the fields the three readers take
  nm <- names(raw)
  city_col <- if ("CITY" %in% nm) "CITY" else "CTU_NAME"
  use_col  <- if ("USE1_DESC" %in% nm) "USE1_DESC" else "USECLASS1"
  xy <- st_coordinates(raw)
  tibble(pin = as.character(raw$PIN), city = as.character(raw[[city_col]]),
         use_desc = as.character(raw[[use_col]]),
         year_built = suppressWarnings(as.integer(raw$YEAR_BUILT)),
         acres = suppressWarnings(as.numeric(raw$ACRES_POLY)),
         num_units = suppressWarnings(as.numeric(as.character(raw$NUM_UNITS))),
         emv_land = suppressWarnings(as.numeric(raw$EMV_LAND)),
         emv_bldg = suppressWarnings(as.numeric(raw$EMV_BLDG)),
         emv_total = suppressWarnings(as.numeric(raw$EMV_TOTAL)),
         tax_capac = suppressWarnings(as.numeric(col(raw, "TAX_CAPAC"))),
         total_tax = suppressWarnings(as.numeric(col(raw, "TOTAL_TAX"))),
         spec_asses = suppressWarnings(as.numeric(col(raw, "SPEC_ASSES"))),
         homestead = as.character(col(raw, "HOMESTEAD")),
         tax_exempt = as.character(col(raw, "TAX_EXEMPT")),
         sale_date = suppressWarnings(as.Date(raw$SALE_DATE)),
         sale_value = suppressWarnings(as.numeric(raw$SALE_VALUE)),
         x = xy[, 1], y = xy[, 2],
         origins_city = if ("CITY" %in% nm) as.character(raw$CITY) else NA_character_)
}
diff_cols <- function(a, b) {
  if (nrow(a) != nrow(b)) return(paste0("ROWS ", nrow(a), " vs ", nrow(b)))
  # mismatch = exactly one side NA, or both present and unequal. (The first version
  # used sum(!(a == b | both NA), na.rm = TRUE), which silently DROPPED value-vs-NA
  # mismatches -- e.g. shapefile 0 vs GeoPackage NA in 2021. Fixed 2026-11-09.)
  mism <- function(x, y) xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & x != y)
  d <- vapply(names(a), function(k) sum(mism(a[[k]], b[[k]])), numeric(1))
  d <- d[d > 0]
  if (!length(d)) "" else paste(sprintf("%s:%d", names(d), d), collapse = " ")
}

res <- list()
for (cty in c("Ramsey", "Hennepin")) for (yr in 2005:2022) {
  path <- file.path(MM, "Archive", sprintf("shp_plan_regonal_parcels_%d", yr), sprintf("Parcels%d%sPoints.shp", yr, cty))
  old <- st_read(path, quiet = TRUE)
  new <- read_parcels(years = yr, counties = cty, layer = "points", names = "original")
  u_old <- used(old); u_new <- used(new)
  full_diff <- diff_cols(u_old, u_new)
  # panel: study-area filter, GDAL at read vs st_filter after
  old_f <- st_read(path, wkt_filter = study_wkt, quiet = TRUE)
  # filter with the SAME polygon GDAL gets: the script passes st_as_text(study_area),
  # which rounds to 7 significant digits (~5 cm at UTM scale)
  study_rounded <- st_as_sfc(study_wkt, crs = st_crs(new))
  new_f <- new[lengths(st_intersects(new, study_rounded)) > 0, ]
  filt_diff <- diff_cols(used(old_f), used(new_f))
  # origins: rows kept by its CITY filter (NULL when the column is absent)
  orig_keep <- if ("CITY" %in% names(old)) sum(is_saint_paul(old$CITY)) else 0L
  res[[length(res) + 1]] <- tibble(county = cty, year = yr, rows_old = nrow(old), rows_new = nrow(new),
    full_identical = full_diff == "", full_diff = full_diff,
    filtered_rows = nrow(old_f), filtered_identical = filt_diff == "", filtered_diff = filt_diff,
    crs_same = st_crs(old) == st_crs(new), origins_rows_kept = orig_keep)
  cat(cty, yr, if (full_diff == "" && filt_diff == "") "IDENTICAL" else paste("DIFF |", full_diff, "|", filt_diff), "\n")
}
out <- bind_rows(res)
write.csv(out, "/Users/matthewhockert/research/parcel_data/verification/green_line_points_results.csv", row.names = FALSE)
cat("\nidentical (full and filtered):", sum(out$full_identical & out$filtered_identical), "of", nrow(out), "\n")
