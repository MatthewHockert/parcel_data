## 05_shapefile_schema.R
##
## For the years stored from a richer container but ALSO published as
## shapefiles (2021: GeoPackage; 2024: geodatabase), record each shapefile's
## field list: name, OGR type, width, precision, R type, and the standardized
## column it maps to. read_parcels(..., names = "original", as_shapefile = TRUE)
## uses this to return what st_read() of the shapefile returned, so scripts
## that read those shapefiles keep working unchanged (Matt, 2026-11-08).
##
## Source: the shapefiles kept in data/raw/2021 and data/raw/2024.
## Output: inst/extdata/shapefile_schema.csv

suppressPackageStartupMessages({ library(dplyr); library(readr); library(sf); library(purrr) })
PD_ROOT <- "/Users/matthewhockert/research/parcel_data"

xwalk <- read_csv(file.path(PD_ROOT, "inst", "extdata", "column_crosswalk.csv"), show_col_types = FALSE)
# std_name for any original name, by upper-case name (same rules as the crosswalk)
name_map <- xwalk %>% transmute(u = toupper(original_name), std_name) %>% distinct()
extra <- tribble(~u, ~std_name,
                 "RANGE",      "range",        # GeoPackage calls it RANGE_
                 "SHAPE_LENG", "shape_leng",
                 "SHAPE_AREA", "shape_area")
name_map <- bind_rows(extra, name_map %>% filter(!u %in% extra$u)) %>% distinct(u, .keep_all = TRUE)

parse_fields <- function(shp) {
  info <- strsplit(gdal_utils("vectorinfo", shp, options = c("-so", "-al"), quiet = TRUE), "\n")[[1]]
  # "NAME: Type (width.precision)"; Date fields print without a width
  f <- regmatches(info, regexec("^([A-Za-z0-9_]+): ([A-Za-z0-9]+)(?: \\(([0-9]+)\\.([0-9]+)\\))?$", info, perl = TRUE))
  f <- do.call(rbind, lapply(f[lengths(f) == 5], function(m) m[2:5]))
  f <- f[!f[, 1] %in% c("Geometry", "Layer", "Driver", "Extent", "Data"), , drop = FALSE]
  tibble(shp_name = f[, 1], ogr_type = f[, 2], width = suppressWarnings(as.integer(f[, 3])),
         precision = suppressWarnings(as.integer(f[, 4])))
}

schema <- map_dfr(c(2021L, 2024L), function(yr) {
  map_dfr(c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington"), function(cty) {
    shp <- file.path(PD_ROOT, "data", "raw", yr, sprintf("Parcels%d%s.shp", yr, cty))
    z <- st_drop_geometry(st_read(shp, query = sprintf('SELECT * FROM "Parcels%d%s" LIMIT 0', yr, cty), quiet = TRUE))
    parse_fields(shp) %>%
      mutate(year = yr, county = cty, position = row_number(),
             r_type = vapply(shp_name, function(n) class(z[[n]])[1], character(1))) %>%
      left_join(name_map, by = c("shp_name" = "u")) %>%
      mutate(std_name = coalesce(std_name, tolower(shp_name)))
  })
})

# checks: every field mapped; R column order matches GDAL's field order
cat("fields:", nrow(schema), " unmapped:", sum(is.na(schema$std_name)), "\n")
schema %>% count(year, county) %>% print()
schema %>% count(ogr_type, r_type) %>% print()
write_csv(schema %>% select(year, county, position, shp_name, ogr_type, width, precision, r_type, std_name),
          file.path(PD_ROOT, "inst", "extdata", "shapefile_schema.csv"))
