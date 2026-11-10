## 02_standardize.R
##
## Build the standardized, cross-year parcel store read by R/read_parcels.R.
##
## Steps (built incrementally, code-along):
##   1. Schema inventory: every year x county file's column names and types,
##      read from headers only (no rows), to see how the schema changed.
##   2. (next) Column crosswalk: original name -> one standardized name per
##      concept; documented in docs/column_crosswalk.csv.
##   3. (next) Write GeoParquet partitioned year=/county=, with point-on-surface
##      x/y; verify row counts per file are unchanged.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(sf)
})

PD_ROOT <- "/Users/matthewhockert/research/parcel_data"

# Schema inventory ----
# Source files: the copy chosen for each year x county in the move manifest.
# While the copy (01_collect_raw.R) is still running, read the local source
# path; afterwards these are identical to data/raw/<year>/.
manifest <- read_csv(file.path(PD_ROOT, "docs", "move_manifest.csv"), show_col_types = FALSE)

shp_files <- manifest %>%
  filter(chosen, ext == "shp") %>%
  mutate(layer = sub("\\.shp$", "", file),
         src   = ifelse(file.exists(dest) & file.size(dest) == bytes, dest, path)) %>%
  select(year, county, layer, src, dataless)

# Geodatabase years. 2023 exists only as a 7-county geodatabase. 2024 exists
# as both shapefiles and a geodatabase (same release, identical values by
# PIN); the geodatabase is used (Matt, 2026-11-07) because shapefiles turn
# missing numbers into 0 and drop the time from date-times. The 2024
# shapefiles stay in data/raw/2024 as a backup.
# 2021 likewise exists as shapefiles and a GeoPackage (same release); the
# GeoPackage is used (Matt, 2026-11-07) for the same reason. Source:
# resources.gisdata.mn.gov/.../us_mn_state_metrogis/plan_regonal_parcels_2021/
# gpkg_plan_regonal_parcels_2021.zip (retrieved 2026-06-10 for scenic-quality;
# provenance json kept in data/raw/2021). Archive URLs 404 as of 2026-11-07.
GDB_YEARS <- c(2021L, 2023L, 2024L)   # years read from a container (gpkg / gdb), not shapefiles
gdb_path <- function(yr) {
  if (yr == 2021) return(file.path(PD_ROOT, "data", "raw", "2021", "plan_regonal_parcels_2021.gpkg"))
  file.path(PD_ROOT, "data", "raw", yr, sprintf("plan_regonal_parcels_%d.gdb", yr))
}
gdb_files <- bind_rows(lapply(GDB_YEARS, function(yr) {
  lyr <- grep(sprintf("^Parcels%d[A-Za-z]+$", yr), st_layers(gdb_path(yr))$name, value = TRUE)
  tibble(year = yr, county = sub(sprintf("^Parcels%d", yr), "", lyr), layer = lyr,
         src = gdb_path(yr), dataless = FALSE)
})) %>%
  filter(county != "All7", !grepl("Points$", county))   # polygons only
shp_files <- shp_files %>% filter(!year %in% GDB_YEARS)
gdb_2023 <- gdb_path(2023)

# 2025 release (files dated Jan 2026, no year in the name: ParcelsAnoka.shp),
# copied by code/01b_collect_2025.sh. Added once all four required files of
# a county are present in data/raw/2025.
raw_2025 <- file.path(PD_ROOT, "data", "raw", "2025")
files_2025 <- tibble(year = 2025L,
                     county = c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington")) %>%
  mutate(layer = paste0("Parcels", county),
         src = file.path(raw_2025, paste0(layer, ".shp")),
         dataless = FALSE) %>%
  filter(vapply(layer, function(l) all(file.exists(file.path(raw_2025, paste0(l, c(".shp", ".shx", ".dbf", ".prj"))))), logical(1)))

sources <- bind_rows(shp_files, gdb_files, files_2025) %>% arrange(year, county)
cat("files to inventory:", nrow(sources), " (expect 7 counties x 20 years = 140)\n")
cat("still iCloud-only (header read will trigger a download):", sum(sources$dataless & !sources$year %in% GDB_YEARS), "\n")

# Read zero rows: GDAL parses the header (field names + types) only.
# st_read on an empty result returns a 0-row data frame with typed columns.
read_schema <- function(src, layer) {
  z <- st_read(src, query = sprintf('SELECT * FROM "%s" LIMIT 0', layer), quiet = TRUE)
  z <- st_drop_geometry(z)
  tibble(field = names(z), r_type = vapply(z, function(v) class(v)[1], character(1)))
}

# Cached: header reads of iCloud placeholders force full downloads, so the
# inventory is built once and reused. Delete the CSV to rebuild it.
schema_path <- file.path(PD_ROOT, "docs", "schema_inventory.csv")
if (file.exists(schema_path)) {
  schema <- read_csv(schema_path, show_col_types = FALSE)
  # append headers for any source not yet in the cache (e.g. 2025)
  missing_src <- sources %>% anti_join(distinct(schema, year, county), by = c("year", "county"))
  if (nrow(missing_src) > 0) {
    schema <- bind_rows(schema, missing_src %>% rowwise() %>%
                          mutate(fields = list(read_schema(src, layer))) %>% ungroup() %>%
                          select(year, county, fields) %>% unnest(fields))
    write_csv(schema, schema_path)
    cat("schema cache: added", nrow(missing_src), "file(s)\n")
  }
} else {
  schema <- sources %>%
    rowwise() %>%
    mutate(fields = list(read_schema(src, layer))) %>%
    ungroup() %>%
    select(year, county, fields) %>%
    unnest(fields)
}

# Checks ----
# 1. columns per file, by year (does every county share the year's schema?)
schema %>% count(year, county, name = "n_fields") %>%
  group_by(year) %>% summarise(min_fields = min(n_fields), max_fields = max(n_fields), .groups = "drop") %>%
  print(n = Inf)

# 2. each field: which years it appears in, in how many counties, and whether
#    its type ever changes (a type change is a silent-coercion risk later)
field_span <- schema %>%
  group_by(field) %>%
  summarise(first = min(year), last = max(year), n_years = n_distinct(year),
            n_county_years = n(), types = paste(sort(unique(r_type)), collapse = "/"),
            .groups = "drop") %>%
  arrange(first, field)
cat("distinct field names:", nrow(field_span), "\n")
print(field_span, n = Inf)

write_csv(schema, file.path(PD_ROOT, "docs", "schema_inventory.csv"))

# Seam test for proposed renames ----
# Slow (reads 2017 + 2018 attributes for every county). Set RUN_SEAM <- TRUE
# to rerun; results are saved to docs/seam_test_2017_2018.csv either way.
RUN_SEAM <- FALSE
if (RUN_SEAM) {
# Proposed: old (2005-2017) name -> new (2018-2024) name, same concept.
# Test: for parcels in both the 2017 and 2018 files (same county, same PIN),
# share whose 2017 old-column value equals the 2018 new-column value, after
# trimming and upper-casing (house numbers compared as numbers). A true
# rename should agree for nearly all parcels; a parcel can genuinely change
# between years, so 100% is not expected.
proposed <- tribble(
  ~old,         ~new,         ~compare,
  "CITY",       "CTU_NAME",   "text",
  "CITY_USPS",  "POSTCOMM",   "text",
  "COUNTY_ID",  "CO_CODE",    "text",
  "BLDG_NUM",   "ANUMBER",    "number",
  "PREFIX_DIR", "ST_PRE_DIR", "text",
  "PREFIXTYPE", "ST_PRE_TYP", "text",
  "STREETNAME", "ST_NAME",    "text",
  "STREETTYPE", "ST_POS_TYP", "text",
  "SUFFIX_DIR", "ST_POS_DIR", "text",
  "USE1_DESC",  "USECLASS1",  "text",
  "USE2_DESC",  "USECLASS2",  "text",
  "XUSE1_DESC", "XUSECLASS1", "text",
  "WSHD_DIST",  "WSHD_DST",   "text",
  "UNIT_INFO",  "SUB_ID1",    "text",      # expected to FAIL (split field); tested to confirm
  "PARC_CODE",  "POLYPTREL",  "number"     # expected to FAIL (different concept); tested to confirm
)

# Attribute-only read: GDAL vectortranslate to a temp CSV with just the
# needed columns, no geometry. sf::gdal_utils uses sf's bundled GDAL.
read_attrs <- function(src, layer, cols) {
  tmp <- tempfile(fileext = ".csv")
  gdal_utils("vectortranslate", src, tmp,
             options = c("-f", "CSV", "-select", paste(cols, collapse = ","), layer),
             quiet = TRUE)
  out <- read_csv(tmp, col_types = cols(.default = col_character()), progress = FALSE)
  unlink(tmp)
  out
}

norm_text <- function(x) toupper(trimws(x))

# Only counties whose 2017 and 2018 files are fully copied into data/raw are
# tested (reading an iCloud placeholder blocks on a download). Skipped
# counties are listed and tested on a rerun once the copy completes.
copied_complete <- function(yr, cty) {
  f <- file.path(PD_ROOT, "data", "raw", yr, sprintf("Parcels%d%s.%s", yr, cty, c("shp", "shx", "dbf", "prj")))
  m <- manifest %>% filter(chosen, year == yr, county == cty, ext %in% c("shp", "shx", "dbf", "prj"))
  all(file.exists(f)) && all(file.size(m$dest) == m$bytes)
}
seam_counties <- Filter(function(cty) copied_complete(2017, cty) && copied_complete(2018, cty),
                        sort(unique(sources$county)))
cat("seam test counties:", paste(seam_counties, collapse = ", "),
    " | skipped (not yet copied):", paste(setdiff(sort(unique(sources$county)), seam_counties), collapse = ", "), "\n")

seam <- lapply(seam_counties, function(cty) {
  s17 <- sources %>% filter(year == 2017, county == cty) %>% mutate(src = file.path(PD_ROOT, "data", "raw", 2017, paste0(layer, ".shp")))
  s18 <- sources %>% filter(year == 2018, county == cty) %>% mutate(src = file.path(PD_ROOT, "data", "raw", 2018, paste0(layer, ".shp")))
  a <- read_attrs(s17$src, s17$layer, c("PIN", proposed$old))
  b <- read_attrs(s18$src, s18$layer, c("PIN", proposed$new))
  # PIN must be unique within each file for a clean 1:1 join; placeholder
  # PINs (right-of-way etc.) repeat, so keep only PINs that occur once
  a <- a %>% group_by(PIN) %>% filter(n() == 1) %>% ungroup()
  b <- b %>% group_by(PIN) %>% filter(n() == 1) %>% ungroup()
  j <- inner_join(a, b, by = "PIN")

  res <- lapply(seq_len(nrow(proposed)), function(k) {
    x <- j[[proposed$old[k]]]; y <- j[[proposed$new[k]]]
    both <- !is.na(x) & !is.na(y) & trimws(x) != "" & trimws(y) != ""
    agree <- if (proposed$compare[k] == "number") {
      suppressWarnings(as.numeric(x[both]) == as.numeric(y[both]))
    } else norm_text(x[both]) == norm_text(y[both])
    tibble(county = cty, old = proposed$old[k], new = proposed$new[k],
           n_matched = nrow(j), n_both_present = sum(both),
           share_agree = round(mean(agree, na.rm = TRUE), 3),
           example_old = x[both][which(!agree)[1]], example_new = y[both][which(!agree)[1]])
  })
  cat(cty, ": 2017 PINs", nrow(a), " 2018 PINs", nrow(b), " matched", nrow(j), "\n")
  bind_rows(res)
})
seam <- bind_rows(seam)

# summary across counties: weighted agreement, and the weakest county
seam %>%
  group_by(old, new) %>%
  summarise(parcels = sum(n_both_present),
            share_agree = round(weighted.mean(share_agree, n_both_present, na.rm = TRUE), 3),
            worst_county = county[which.min(share_agree)],
            worst_share = min(share_agree, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(share_agree)) %>%
  print(n = Inf, width = Inf)

# one disagreeing example per pair (first county with a disagreement)
seam %>% filter(!is.na(example_old)) %>% group_by(old) %>% slice(1) %>%
  select(old, new, county, example_old, example_new) %>% print(n = Inf, width = Inf)

write_csv(seam, file.path(PD_ROOT, "docs", "seam_test_2017_2018.csv"))
}

# Column crosswalk ----
# RULE (Matt, 2026-11-07): merge column NAMES for the same concept across
# years; never rewrite VALUES in the store. Values stay as published, so the
# names = "original" view reproduces each file exactly. Normalized versions
# (e.g. USPS street suffix, 3-digit county FIPS) are added later as separate
# derived columns.
#
# Renames below come from the 2017/2018 seam test (docs/seam_test_2017_2018.csv).
# confirmed = TRUE once the test covers all 7 counties; Anoka-only for now.
renames <- tribble(
  ~std_name,            ~old,         ~new,         ~seam_note,
  "city",               "CITY",       "CTU_NAME",   "same values (Anoka 100%)",
  "city_postal",        "CITY_USPS",  "POSTCOMM",   "same values (Anoka 100%)",
  "parcel_code",        "PARC_CODE",  "POLYPTREL",  "same values (Anoka 100%)",
  "addr_number",        "BLDG_NUM",   "ANUMBER",    "same values (Anoka 99.9%); text -> number",
  "st_name",            "STREETNAME", "ST_NAME",    "same values (Anoka 99.9%)",
  "st_post_type",       "STREETTYPE", "ST_POS_TYP", "recoded: ST -> Street",
  "st_pre_dir",         "PREFIX_DIR", "ST_PRE_DIR", "recoded: E -> East",
  "st_post_dir",        "SUFFIX_DIR", "ST_POS_DIR", "recoded: NW -> Northwest",
  "st_pre_type",        "PREFIXTYPE", "ST_PRE_TYP", "untested: no Anoka parcel had both",
  "county_code",        "COUNTY_ID",  "CO_CODE",    "recoded: 003 -> 27003",
  "watershed_district", "WSHD_DIST",  "WSHD_DST",   "recoded: full name -> abbreviation",
  "use_class1",         "USE1_DESC",  "USECLASS1",  "mostly same labels (Anoka 92.6%)",
  "use_class2",         "USE2_DESC",  "USECLASS2",  "assumed same as use_class1",
  "use_class3",         "USE3_DESC",  "USECLASS3",  "assumed same as use_class1",
  "use_class4",         "USE4_DESC",  "USECLASS4",  "assumed same as use_class1",
  "exempt_use1",        "XUSE1_DESC", "XUSECLASS1", "recoded: 'EXEMPT - ' prefix dropped",
  "exempt_use2",        "XUSE2_DESC", "XUSECLASS2", "assumed same as exempt_use1",
  "exempt_use3",        "XUSE3_DESC", "XUSECLASS3", "assumed same as exempt_use1",
  "exempt_use4",        "XUSE4_DESC", "XUSECLASS4", "assumed same as exempt_use1"
) %>% mutate(confirmed = FALSE)

rename_long <- bind_rows(
  renames %>% transmute(original_upper = toupper(old), std_name, seam_note, confirmed),
  renames %>% transmute(original_upper = toupper(new), std_name, seam_note, confirmed))

# Everything not renamed keeps its own concept: std_name = lower-case name.
# Matching is case-insensitive, so "Garage" (one county, 2007-2010) and
# "GARAGE" both map to garage. Shape_Length (2023 gdb) is the same quantity
# as Shape_Leng elsewhere.
column_crosswalk <- schema %>%
  mutate(original_upper = toupper(field)) %>%
  left_join(rename_long, by = "original_upper") %>%
  mutate(std_name = case_when(!is.na(std_name) ~ std_name,
                              original_upper == "SHAPE_LENGTH" ~ "shape_leng",
                              original_upper == "RANGE_" ~ "range",   # 2021 GeoPackage name for RANGE
                              TRUE ~ tolower(field)),
         seam_note = coalesce(seam_note, "same name all years"),
         confirmed = coalesce(confirmed, TRUE)) %>%
  select(year, county, original_name = field, std_name, r_type, seam_note, confirmed)

# Checks ----
# 1. every original column mapped exactly once
stopifnot(!any(duplicated(column_crosswalk[c("year", "county", "original_name")])))
# 2. no two columns in the same file share a std_name (would lose data)
collisions <- column_crosswalk %>% count(year, county, std_name) %>% filter(n > 1)
cat("std_name collisions within a file:", nrow(collisions), "\n"); print(collisions)
# 3. the standardized schema: columns, years present, and type mix
std_schema <- column_crosswalk %>%
  group_by(std_name) %>%
  summarise(years = paste0(min(year), "-", max(year)), n_years = n_distinct(year),
            originals = paste(sort(unique(original_name)), collapse = "/"),
            types = paste(sort(unique(r_type)), collapse = "/"), .groups = "drop") %>%
  arrange(desc(n_years), std_name)
cat("standardized columns:", nrow(std_schema), " (from", n_distinct(column_crosswalk$original_name), "original names)\n")
print(std_schema, n = Inf, width = Inf)

write_csv(column_crosswalk, file.path(PD_ROOT, "docs", "column_crosswalk.csv"))

# Write the store ----
source(file.path(PD_ROOT, "R", "read_parcels.R"))   # parcel_linearize, parcel_interior_xy
suppressPackageStartupMessages(library(arrow))
STORE_DIR <- file.path(PD_ROOT, "data", "standardized")

## Target types ----
# One type per standardized column:
#   numbers only            -> double
#   text only               -> string
#   dates (Date or POSIXct) -> timestamp (UTC)
#   mixed text and numbers  -> double, plus <col>_raw (string) holding the
#                              file's exact text in every file that published
#                              the column as text (Matt, 2026-11-07)
std_types <- column_crosswalk %>%
  group_by(std_name) %>%
  summarise(types = paste(sort(unique(r_type)), collapse = "/"), .groups = "drop") %>%
  mutate(target = case_when(types %in% c("Date", "POSIXct", "Date/POSIXct") ~ "date",
                            types == "character" ~ "string",
                            grepl("character", types) ~ "double_with_raw",
                            TRUE ~ "double"))
cat("target types:\n"); print(count(std_types, target))
cat("mixed columns (get a _raw sidecar):", paste(std_types$std_name[std_types$target == "double_with_raw"], collapse = ", "), "\n")

store_cols <- c(std_types$std_name, paste0(std_types$std_name[std_types$target == "double_with_raw"], "_raw"))

## One file -> one partition ----
write_partition <- function(yr, cty) {
  src <- sources %>% filter(year == yr, county == cty)
  raw_path <- if (yr %in% GDB_YEARS) src$src else file.path(PD_ROOT, "data", "raw", yr, paste0(src$layer, ".shp"))
  x <- st_read(raw_path, layer = src$layer, quiet = TRUE)
  n_in <- nrow(x)

  xw <- column_crosswalk %>% filter(year == yr, county == cty)
  g  <- st_geometry(x)
  a  <- st_drop_geometry(x)
  stopifnot(setequal(names(a), xw$original_name))
  names(a) <- xw$std_name[match(names(a), xw$original_name)]

  out <- tibble(.rows = n_in)
  for (k in seq_len(nrow(std_types))) {
    col <- std_types$std_name[k]; tgt <- std_types$target[k]
    v <- if (col %in% names(a)) a[[col]] else NULL
    if (tgt == "date") {
      # DECISION: dates are stored as UTC timestamps, not dates. The 2023 gdb
      # publishes date-times (EDIT_DATE has real times of day); a date type
      # would drop them. Shapefile Dates become midnight UTC (same day).
      out[[col]] <- if (is.null(v)) as.POSIXct(NA, tz = "UTC") else as.POSIXct(v, tz = "UTC")
    } else if (tgt == "string") {
      out[[col]] <- if (is.null(v)) NA_character_ else as.character(v)
    } else {
      out[[col]] <- if (is.null(v)) NA_real_ else suppressWarnings(as.numeric(v))
      if (tgt == "double_with_raw") {
        out[[paste0(col, "_raw")]] <- if (!is.null(v) && is.character(v)) v else NA_character_
      }
    }
  }

  # point on surface for cheap spatial filtering; computed on a repaired
  # copy so invalid polygons do not error. The stored polygon is untouched.
  # one interior point per parcel (see parcel_interior_xy in R/read_parcels.R;
  # the first version here misaligned rows when a repaired parcel had several
  # pieces -- fixed 2026-11-07)
  xy <- parcel_interior_xy(g)
  out$pt_x <- xy[, "X"]; out$pt_y <- xy[, "Y"]; ok <- !is.na(xy[, "X"])
  out$row_in_file <- seq_len(n_in)   # original file order, for exact round trips

  # 2021: the public GeoPackage has owner / taxpayer names stripped
  # (OWNER_NAME, OWNER_MORE, TAX_NAME blank for ~97% of parcels in every
  # county) while the 2021 shapefile of the same release has them; no other
  # field is affected (checked 2026-11-08). Keep the GeoPackage values as
  # published and store the shapefile's text in <col>_shp sidecars where the
  # GeoPackage is blank, so the original view still equals the GeoPackage,
  # as_shapefile equals the shapefile, and the standardized view is complete.
  # 2021 and 2024: also keep what the SHAPEFILE of the same release has that
  # the container does not reproduce exactly, so as_shapefile = TRUE returns
  # the shapefile exactly (Matt, 2026-11-08: identical output for scripts
  # that read those shapefiles):
  #   row_in_shp    the row's position in the shapefile (2024's order differs)
  #   geometry_shp  the shapefile polygon, only where it differs from the
  #                 container's (curved boundaries); NULL elsewhere
  #   shape_leng_shp / shape_area_shp  the shapefile's own values
  if (yr %in% c(2021L, 2024L)) {
    shp_all <- st_read(file.path(PD_ROOT, "data", "raw", yr, sprintf("Parcels%d%s.shp", yr, cty)), quiet = TRUE)
    stopifnot(nrow(shp_all) == n_in)
    pin_c <- as.character(a$pin); pin_s <- as.character(shp_all$PIN)
    if (identical(pin_c, pin_s)) {
      idx <- seq_len(n_in)
    } else {
      # align: unique PINs directly; repeated PINs (placeholders) by the
      # bounding-box corner rounded to 1 m, which curves and segments share
      corner <- function(gg) { bb <- vapply(gg, function(z) if (st_is_empty(z)) c(NA, NA) else as.numeric(st_bbox(z))[1:2], numeric(2)); paste(round(bb[1, ]), round(bb[2, ])) }
      kc <- paste(pin_c, ifelse(duplicated(pin_c) | duplicated(pin_c, fromLast = TRUE), corner(g), ""))
      ks <- paste(pin_s, ifelse(duplicated(pin_s) | duplicated(pin_s, fromLast = TRUE), corner(st_geometry(shp_all)), ""))
      kc <- make.unique(kc); ks <- make.unique(ks)
      idx <- match(kc, ks)
    }
    stopifnot(!anyNA(idx), !anyDuplicated(idx))
    out$row_in_shp <- idx
    w_c <- lapply(st_as_binary(g, EWKB = FALSE), as.raw)
    w_s <- lapply(st_as_binary(st_geometry(shp_all)[idx], EWKB = FALSE), as.raw)
    differs <- !mapply(identical, w_c, w_s)
    out$geometry_shp <- blob::as_blob(ifelse(differs, w_s, list(NULL)))
    out$shape_leng_shp <- shp_all$Shape_Leng[idx]
    out$shape_area_shp <- shp_all$Shape_Area[idx]
    cat("   shapefile sidecars:", yr, cty, "rows aligned", sum(!is.na(idx)), " geometry differs", sum(differs), "\n")
  }

  if (yr == 2021) {
    shp_path <- file.path(PD_ROOT, "data", "raw", 2021, sprintf("Parcels2021%s.shp", cty))
    name_fields <- c(owner_name = "OWNER_NAME", owner_more = "OWNER_MORE", tax_name = "TAX_NAME")
    s21 <- st_drop_geometry(st_read(shp_path, query = sprintf('SELECT PIN, %s FROM "Parcels2021%s"',
                                    paste(name_fields, collapse = ", "), cty), quiet = TRUE))
    stopifnot(nrow(s21) == n_in, identical(s21$PIN, as.character(a$pin)))   # same rows, same order
    blank <- function(z) is.na(z) | trimws(z) == ""
    for (std in names(name_fields)) {
      fill <- blank(out[[std]]) & !blank(s21[[name_fields[[std]]]])
      out[[paste0(std, "_shp")]] <- ifelse(fill, s21[[name_fields[[std]]]], NA_character_)
    }
  }
  # blob = list of raw vectors; arrow writes it as Parquet binary (WKB)
  out$geometry <- blob::as_blob(lapply(st_as_binary(g, EWKB = FALSE), as.raw))

  dir_out <- file.path(STORE_DIR, paste0("year=", yr), paste0("county=", cty))
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)
  write_parquet(out, file.path(dir_out, "part-0.parquet"))
  tibble(year = yr, county = cty, rows_in = n_in, rows_out = nrow(out),
         crs = st_crs(x)$epsg, empty_geom = sum(st_is_empty(g)), pt_missing = sum(!ok))
}

## Write all partitions ----
# Tested first on Ramsey 2017 and 2018 (exact round trip, 2026-11-07).
# A partition is written only when its raw files are fully copied (all four
# required components present at the manifest size); the rest are listed
# and picked up by a rerun. Existing partitions are skipped unless REWRITE.
REWRITE <- FALSE  # 2026-11-09: FINAL full rewrite done 12:23-13:00 (147/147, range_ dropped). Was TRUE for that run. Set TRUE to rewrite every partition (last full rewrite 2026-11-07: dates -> timestamps)

raw_complete <- function(yr, cty) {
  if (yr == 2025) return(cty %in% files_2025$county)
  if (yr %in% GDB_YEARS) return(file.exists(gdb_path(yr)))   # file.exists: gdb is a folder, gpkg a file
  m <- manifest %>% filter(chosen, year == yr, county == cty, ext %in% c("shp", "shx", "dbf", "prj"))
  nrow(m) == 4 && all(file.exists(m$dest)) && all(file.size(m$dest) == m$bytes)
}

todo <- sources %>% distinct(year, county) %>%
  mutate(done  = file.exists(file.path(STORE_DIR, paste0("year=", year), paste0("county=", county), "part-0.parquet")),
         ready = mapply(raw_complete, year, county))
cat("partitions:", nrow(todo), " already written:", sum(todo$done),
    " ready to write:", sum(todo$ready & (!todo$done | REWRITE)),
    " waiting on copy:", sum(!todo$ready), "\n")
todo %>% filter(!ready) %>% print(n = Inf)

write_log_path <- file.path(PD_ROOT, "docs", "store_write_log.csv")
for (i in which(todo$ready & (!todo$done | REWRITE))) {
  t0 <- Sys.time()
  res <- write_partition(todo$year[i], todo$county[i]) %>%
    mutate(seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))),
           written_at = format(Sys.time(), "%Y-%m-%d %H:%M"))
  write_csv(res, write_log_path, append = file.exists(write_log_path))
  cat(format(Sys.time(), "%H:%M"), todo$year[i], todo$county[i], "rows", res$rows_in, "->", res$rows_out, "\n")
}

# Verification runs in code/03_verify_store.R (a fresh R session: arrow's
# dataset reader errors if opened in the session that ran GDAL + the writer).
