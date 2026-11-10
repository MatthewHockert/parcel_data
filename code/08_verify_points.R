## 08_verify_points.R
##
## Verify every partition of the POINTS store (code/07_points_store.R):
## st_read() of the published Points layer (the source in docs/points_sources.csv)
## vs read_parcels(yr, cty, layer = "points", names = "original"), compared
## with compare_reads() in plain EXACT mode (same rows in the same order, same
## names in the same order, identical values, WKB-identical geometry).
## Also checked, and required: every column has the same R class as in the
## source read, and the geometry type and CRS match.
## Run in a fresh R session (not the one that wrote the store).
##
## Run:    Rscript code/08_verify_points.R [years ...]   (default: every written partition)
## Output: docs/points_verification.csv (one row per year x county; a partial
##         run replaces only its own rows)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
})

PD_ROOT <- "/Users/matthewhockert/research/parcel_data"
source(file.path(PD_ROOT, "R", "read_parcels.R"))
source(file.path(PD_ROOT, "R", "verify_read.R"))
COUNTIES <- c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington")
VER_OUT  <- file.path(PD_ROOT, "docs", "points_verification.csv")
DOWNLOAD_TIMEOUT_MIN <- 30

only_years <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)))
only_years <- only_years[!is.na(only_years)]

# iCloud: request a download and wait, so st_read never blocks (as in 07)
is_dataless <- function(f) {
  if (!length(f)) return(logical(0))
  vapply(f, function(z) {
    fl <- suppressWarnings(as.numeric(system2("stat", c("-f", "%f", shQuote(z)), stdout = TRUE, stderr = FALSE)))
    length(fl) == 1 && !is.na(fl) && bitwAnd(fl %/% 2^30, 1L) == 1L
  }, logical(1), USE.NAMES = FALSE)
}
ensure_local <- function(files, timeout_min = DOWNLOAD_TIMEOUT_MIN) {
  files <- files[file.exists(files) & !dir.exists(files)]
  dl <- files[is_dataless(files)]
  for (f in dl) system2("brctl", c("download", shQuote(f)), stdout = FALSE, stderr = FALSE)
  t0 <- Sys.time()
  while (length(dl) && any(is_dataless(dl))) {
    if (difftime(Sys.time(), t0, units = "mins") > timeout_min) return(FALSE)
    Sys.sleep(10)
  }
  TRUE
}

sources <- read_csv(file.path(PD_ROOT, "docs", "points_sources.csv"), show_col_types = FALSE)
written <- list.dirs(PARCEL_STORE_POINTS, recursive = TRUE, full.names = FALSE)
written <- written[grepl("^year=[0-9]{4}/county=", written)]
parts <- tibble(year = as.integer(sub("^year=([0-9]{4}).*", "\\1", written)),
                county = sub(".*county=", "", written)) %>%
  inner_join(sources, by = c("year", "county")) %>%
  mutate(.cty = match(county, COUNTIES)) %>% arrange(year, .cty) %>% select(-.cty)
if (length(only_years)) parts <- parts %>% filter(year %in% only_years)
cat("points partitions to verify:", nrow(parts), "\n")

verify_one <- function(s) {
  label <- paste(s$year, s$county)
  files <- if (grepl("[.]shp$", s$source)) paste0(sub("[.]shp$", "", s$source), c(".shp", ".shx", ".dbf", ".prj", ".cpg")) else s$source
  if (!ensure_local(files)) return(tibble(label = label, ok = FALSE, cols_differ = "source did not download"))
  old <- st_read(s$source, layer = s$layer, quiet = TRUE)
  new <- read_parcels(years = s$year, counties = s$county, layer = "points", names = "original")
  r <- compare_reads(old, new, label = label)   # plain exact mode
  # types: the same R class for every column (compare_reads compares values)
  cls <- function(d) vapply(st_drop_geometry(d), function(v) paste(class(v), collapse = "/"), character(1))
  co <- cls(old); cn <- cls(new)
  r$types_differ <- if (identical(names(co), names(cn))) paste(names(co)[co != cn], collapse = ", ") else "names differ"
  r$geom_type_ok <- identical(as.character(st_geometry_type(old)), as.character(st_geometry_type(new)))
  # CRS: the store carries EPSG 26915 (as the polygon store); the source's
  # own CRS must be that same coordinate system
  r$crs_ok <- isTRUE(st_crs(old) == st_crs(new)) || identical(st_crs(old)$epsg, 26915L)
  r$crs_source <- st_crs(old)$input
  r$ok <- r$ok && r$types_differ == "" && r$geom_type_ok && r$crs_ok
  r$source <- s$source; r$layer <- s$layer
  r
}

verification <- bind_rows(lapply(seq_len(nrow(parts)), function(i) {
  r <- verify_one(parts[i, ])
  cat(format(Sys.time(), "%H:%M"), r$label, if (isTRUE(r$ok)) "OK" else paste("FAIL:", r$cols_differ, r$types_differ), "\n")
  gc()
  r
}))
print(verification %>% select(label, rows_old, rows_new, names_ok, cols_differ, geom_ok, types_differ, ok), n = Inf, width = Inf)
cat("points partitions verified OK:", sum(verification$ok), "of", nrow(verification), "\n")

if (file.exists(VER_OUT)) {
  verification <- bind_rows(read_csv(VER_OUT, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
                              filter(!label %in% verification$label),
                            verification %>% mutate(across(everything(), as.character)))
}
verification <- verification %>%
  mutate(.y = as.integer(substr(label, 1, 4)), .c = match(sub("^[0-9]{4} ", "", label), COUNTIES)) %>%
  arrange(.y, .c) %>% select(-.y, -.c)
tmp <- paste0(VER_OUT, ".tmp"); write_csv(verification, tmp, na = ""); file.rename(tmp, VER_OUT)
