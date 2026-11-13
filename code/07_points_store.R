## 07_points_store.R
##
## Build the POINTS layer of the parcel store: the county-published Points
## layers (Parcels<yr><County>Points), stored AS PUBLISHED in
## data/standardized_points/year=YYYY/county=Name/part-0.parquet and read with
## read_parcels(..., layer = "points").
##
## Why store them (Matt, 2026-11-08): older Points layers carry condo-unit
## records whose PINs are in no polygon file (e.g. Ramsey 2005-2017 ~11-18k a
## year, Hennepin 2005-2007 ~49-66k), so they cannot be derived from polygons.
## No raw Points copies are kept in parcel_data: the Parquet, verified exact
## against each source by code/08_verify_points.R, is the archive.
##
## Same standardized names and type rules as the polygon store
## (code/02_standardize.R): names from the polygon column crosswalk, values
## never rewritten, one type per standardized column (numbers -> double,
## text -> string, dates -> UTC timestamp, mixed -> double + <col>_raw text),
## geometry as WKB, row_in_file for the file's row order, pt_x / pt_y for
## bbox filtering (here simply the point's own coordinates).
##
## Sources (one copy per year x county; see docs/points_sources.csv):
##   2005-2020, 2022  Parcels<yr><County>Points.shp in shp_plan_regonal_parcels_<yr>
##                    folders (every copy listed in docs/deletion_candidates.csv,
##                    category points_shp); a local (not iCloud-only) copy preferred
##   2021             Parcels2021<County>Points in data/raw/2021/plan_regonal_parcels_2021.gpkg.
##                    The GeoPackage has OWNER_NAME / OWNER_MORE / TAX_NAME stripped
##                    (as for the polygons); the 2021 Points SHAPEFILE's names are
##                    kept in <col>_shp sidecars where the GeoPackage is blank.
##   2023, 2024       Parcels<yr><County>Points in data/raw/<yr>/plan_regonal_parcels_<yr>.gdb
##   2025             shp_plan_regional_parcels/Parcels<County>Points.shp in
##                    ~/Desktop/Personal Info/st_paul_rc_affordable_housing (files dated Jan 2026)
##   All7Points is skipped (union of the seven counties).
##
## Outputs: data/standardized_points/..., inst/extdata/points_column_crosswalk.csv
##          (year, county, original_name, std_name, r_type),
##          docs/points_sources.csv (year, county, source, layer, bytes, rows, ...),
##          docs/points_write_log.csv
## Run:     Rscript code/07_points_store.R [years ...]   (default: all years)
##          Existing partitions are skipped unless REWRITE is TRUE.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(arrow)
})

PD_ROOT    <- Sys.getenv("PARCEL_HOME")
POINTS_DIR <- file.path(PD_ROOT, "data", "standardized_points")
XWALK_OUT  <- file.path(PD_ROOT, "inst", "extdata", "points_column_crosswalk.csv")
SOURCES_OUT <- file.path(PD_ROOT, "docs", "points_sources.csv")
LOG_OUT    <- file.path(PD_ROOT, "docs", "points_write_log.csv")
COUNTIES   <- c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington")
DIR_2025   <- "~/Desktop/Personal Info/st_paul_rc_affordable_housing/shp_plan_regional_parcels"
REWRITE    <- FALSE
DOWNLOAD_TIMEOUT_MIN <- 8    # per copy: give up on an iCloud placeholder after this long and try the
                             # next copy of the same file; if no copy downloads, listed and the run continues

only_years <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)))
only_years <- only_years[!is.na(only_years)]

# iCloud helpers ----
# macOS marks evicted (iCloud-only) files with the SF_DATALESS flag (0x40000000).
is_dataless <- function(f) {
  if (!length(f)) return(logical(0))
  fl <- suppressWarnings(as.numeric(system2("stat", c("-f", "%f", shQuote(f)), stdout = TRUE, stderr = FALSE)))
  if (length(fl) != length(f)) return(vapply(f, is_dataless, logical(1), USE.NAMES = FALSE))
  bitwAnd(fl %/% 2^30, 1L) == 1L
}
# Request a download (brctl) and wait until every file is local, so st_read
# never blocks on iCloud. FALSE if still a placeholder after the timeout.
ensure_local <- function(files, timeout_min = DOWNLOAD_TIMEOUT_MIN) {
  files <- files[file.exists(files)]
  dl <- files[is_dataless(files)]
  if (!length(dl)) return(TRUE)
  for (f in dl) system2("brctl", c("download", shQuote(f)), stdout = FALSE, stderr = FALSE)
  t0 <- Sys.time()
  while (any(is_dataless(dl))) {
    if (difftime(Sys.time(), t0, units = "mins") > timeout_min) return(FALSE)
    Sys.sleep(10)
  }
  TRUE
}
shp_parts <- function(stem) paste0(stem, c(".shp", ".shx", ".dbf", ".prj", ".cpg"))

# Shapefile copies ----
# Every copy of every Points shapefile, from the deletion inventory. One copy
# per year x county is used; all copies of a component must have the same
# byte size (checked; mismatches are reported and the year x county is not
# written until resolved).
cand <- read_csv(file.path(PD_ROOT, "docs", "deletion_candidates.csv"), show_col_types = FALSE) %>%
  filter(category == "points_shp") %>%
  mutate(file = basename(path),
         m = regmatches(file, regexec("^Parcels(20[0-9]{2})([A-Za-z]+?)Points[.](shp|shx|dbf|prj|cpg)$", file))) %>%
  filter(lengths(m) == 4) %>%
  mutate(year = as.integer(vapply(m, `[`, "", 2)), county = vapply(m, `[`, "", 3),
         ext = vapply(m, `[`, "", 4), dir = dirname(path)) %>%
  filter(county %in% COUNTIES, year != 2024) %>%            # 2024 is read from the geodatabase
  select(year, county, dir, ext, path, bytes) %>%
  filter(file.exists(path)) %>%
  mutate(bytes = file.size(path), dataless = is_dataless(path))

size_check <- cand %>% group_by(year, county, ext) %>%
  summarise(n_copies = n(), n_sizes = n_distinct(bytes), .groups = "drop")
bad_sizes <- size_check %>% filter(n_sizes > 1)
cat("Points shapefile copies:", n_distinct(cand$year, cand$county, cand$dir), "folders;",
    "components with unequal sizes across copies:", nrow(bad_sizes), "\n")
if (nrow(bad_sizes)) print(cand %>% semi_join(bad_sizes, by = c("year", "county", "ext")), n = Inf, width = Inf)

# Rank the copies: complete (.shp .shx .dbf .prj), then fewest iCloud-only
# bytes. The first is used; the others are fallbacks when it will not
# download (all copies have equal sizes, checked above).
ranked_copies <- cand %>%
  group_by(year, county, dir) %>%
  filter(all(c("shp", "shx", "dbf", "prj") %in% ext)) %>%
  summarise(icloud_bytes = sum(bytes[dataless]), comps = paste(sort(ext), collapse = "/"),
            .groups = "drop") %>%
  group_by(year, county) %>% arrange(icloud_bytes, .by_group = TRUE) %>%
  mutate(alternates = paste(file.path(dir, sprintf("Parcels%d%sPoints.shp", year, county)), collapse = "|")) %>% ungroup()
choose_copy <- ranked_copies %>% group_by(year, county) %>% slice(1) %>% ungroup()

# Sources ----
gdb_src <- function(yr) {
  if (yr == 2021) return(file.path(PD_ROOT, "data", "raw", "2021", "plan_regonal_parcels_2021.gpkg"))
  file.path(PD_ROOT, "data", "raw", yr, sprintf("plan_regonal_parcels_%d.gdb", yr))
}
src_shp <- choose_copy %>%
  filter(year != 2021) %>%
  transmute(year, county, layer = sprintf("Parcels%d%sPoints", year, county),
            source = file.path(dir, paste0(layer, ".shp")), names_shp = NA_character_, alternates)
src_gdb <- tidyr::expand_grid(year = c(2021L, 2023L, 2024L), county = COUNTIES) %>%
  mutate(layer = sprintf("Parcels%d%sPoints", year, county),
         source = vapply(year, gdb_src, ""), names_shp = NA_character_)
# 2021: the Points shapefile copy supplies the owner / taxpayer names
s21 <- choose_copy %>% filter(year == 2021)
src_gdb$names_shp[src_gdb$year == 2021] <-
  file.path(s21$dir, sprintf("Parcels2021%sPoints.shp", s21$county))[match(src_gdb$county[src_gdb$year == 2021], s21$county)]
src_gdb$alternates <- NA_character_
src_gdb$alternates[src_gdb$year == 2021] <- s21$alternates[match(src_gdb$county[src_gdb$year == 2021], s21$county)]   # for names_shp
src_2025 <- tibble(year = 2025L, county = COUNTIES, layer = sprintf("Parcels%sPoints", COUNTIES),
                   source = file.path(DIR_2025, sprintf("Parcels%sPoints.shp", COUNTIES)), names_shp = NA_character_,
                   alternates = NA_character_)   # the only copy
sources <- bind_rows(src_shp, src_gdb, src_2025) %>% arrange(year, county)

# Keep the copy chosen on an earlier run (iCloud states change between runs)
if (file.exists(SOURCES_OUT)) {
  prev <- read_csv(SOURCES_OUT, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    mutate(year = as.integer(year))
  sources <- sources %>% rows_update(prev %>% select(year, county, source, names_shp) %>%
                                       semi_join(sources, by = c("year", "county")),
                                     by = c("year", "county"), unmatched = "ignore")
}
# layers present in the containers (2021 GeoPackage, 2023 / 2024 gdb)
for (yr in c(2021L, 2023L, 2024L)) {
  lyrs <- st_layers(gdb_src(yr))$name
  miss <- setdiff(sources$layer[sources$year == yr], lyrs)
  if (length(miss)) stop("missing layers in ", gdb_src(yr), ": ", paste(miss, collapse = ", "))
}
cat("sources:", nrow(sources), "year x county Points layers (expect 21 x 7 = 147)\n")
print(count(sources, year), n = Inf)

# Column names and types ----
# Standardized names come from the POLYGON crosswalk: a Points layer has the
# polygon file's fields (minus Shape_Leng / Shape_Area), so each field takes
# the std_name its polygon twin has in the same year x county. A field with
# no polygon twin (ORIG_FID in some years, e.g. Washington 2015-2017) takes
# the name any year gives it, else its lower-case name (the 02 rule).
poly_xw <- read_csv(file.path(PD_ROOT, "inst", "extdata", "column_crosswalk.csv"), show_col_types = FALSE)
any_year_name <- poly_xw %>% mutate(u = toupper(original_name)) %>% distinct(u, std_name) %>%
  group_by(u) %>% filter(n() == 1) %>% ungroup()

# Target types: the polygon store's rule applied to the polygon crosswalk, so
# a standardized column has the same type in both layers. Points-only
# columns (orig_fid) are numbers. A Points field whose type does not fit its
# target stops the run (never coerced silently).
std_types <- poly_xw %>%
  group_by(std_name) %>%
  summarise(types = paste(sort(unique(r_type)), collapse = "/"), .groups = "drop") %>%
  mutate(target = case_when(types %in% c("Date", "POSIXct", "Date/POSIXct") ~ "date",
                            types == "character" ~ "string",
                            grepl("character", types) ~ "double_with_raw",
                            TRUE ~ "double")) %>%
  filter(!std_name %in% c("shape_leng", "shape_area")) %>%   # polygon size fields: not in Points layers
  bind_rows(tibble(std_name = "orig_fid", types = "integer", target = "double"))

points_xwalk <- function(yr, cty, a) {
  ty <- vapply(a, function(v) class(v)[1], character(1))
  p  <- poly_xw %>% filter(year == yr, county == cty)
  std <- p$std_name[match(names(a), p$original_name)]
  std[is.na(std)] <- any_year_name$std_name[match(toupper(names(a)[is.na(std)]), any_year_name$u)]
  std[is.na(std)] <- tolower(names(a)[is.na(std)])
  tibble(year = yr, county = cty, original_name = names(a), std_name = std, r_type = unname(ty))
}

# One Points layer -> one partition ----
write_partition <- function(s) {
  yr <- s$year; cty <- s$county
  # the shapefile that must be local: the source itself, or (2021) the names shapefile
  shp_field <- if (!is.na(s$names_shp)) "names_shp" else if (grepl("[.]shp$", s$source)) "source" else NA
  copies <- if (is.na(shp_field)) NA_character_ else unique(c(s[[shp_field]], if (!is.na(s$alternates)) strsplit(s$alternates, "|", fixed = TRUE)[[1]]))
  got <- FALSE; tried <- character(0)
  for (cp in copies) {
    if (!is.na(cp)) s[[shp_field]] <- cp
    files <- if (grepl("[.]shp$", s$source)) shp_parts(sub("[.]shp$", "", s$source)) else s$source
    if (!is.na(s$names_shp)) files <- c(files, shp_parts(sub("[.]shp$", "", s$names_shp)))
    ex <- files[file.exists(files) & !dir.exists(files)]
    was_icloud <- ex[is_dataless(ex)]
    if (ensure_local(files)) { got <- TRUE; break }
    tried <- c(tried, paste0(dirname(cp), ": ", paste(basename(ex[is_dataless(ex)]), collapse = " ")))
    cat("   ", yr, cty, "copy did not download in", DOWNLOAD_TIMEOUT_MIN, "min; trying next copy\n")
  }
  if (!got) return(list(status = "not downloaded", detail = paste(tried, collapse = " | ")))
  x <- st_read(s$source, layer = s$layer, quiet = TRUE)
  n_in <- nrow(x)
  g <- st_geometry(x)
  a <- st_drop_geometry(x)
  xw <- points_xwalk(yr, cty, a)
  stopifnot(!anyDuplicated(xw$std_name))
  unknown <- setdiff(xw$std_name, std_types$std_name)
  if (length(unknown)) stop(yr, " ", cty, ": Points fields with no standardized type: ", paste(unknown, collapse = ", "))
  names(a) <- xw$std_name

  out <- tibble(.rows = n_in)
  for (k in seq_len(nrow(std_types))) {
    col <- std_types$std_name[k]; tgt <- std_types$target[k]
    v <- if (col %in% names(a)) a[[col]] else NULL
    bad <- !is.null(v) && switch(tgt,
      date   = !inherits(v, c("Date", "POSIXct")),
      string = !is.character(v),
      double = !is.numeric(v),
      double_with_raw = !(is.numeric(v) || is.character(v)))
    if (bad) stop(yr, " ", cty, ": ", col, " is ", class(v)[1], " but its standardized type is ", tgt)
    if (tgt == "date") {
      # dates stored as UTC timestamps (02 rule: gdb date-times keep their time)
      out[[col]] <- if (is.null(v)) as.POSIXct(NA, tz = "UTC") else as.POSIXct(v, tz = "UTC")
    } else if (tgt == "string") {
      out[[col]] <- if (is.null(v)) NA_character_ else v
    } else {
      out[[col]] <- if (is.null(v)) NA_real_ else suppressWarnings(as.numeric(v))
      if (tgt == "double_with_raw") {
        out[[paste0(col, "_raw")]] <- if (!is.null(v) && is.character(v)) v else NA_character_
      }
    }
  }

  # pt_x / pt_y: the point itself (NA for empty points), for bbox filtering
  emp <- st_is_empty(g)
  xy <- matrix(NA_real_, n_in, 2)
  if (any(!emp)) xy[!emp, ] <- st_coordinates(g[!emp])[, 1:2, drop = FALSE]
  stopifnot(all(as.character(st_geometry_type(g[!emp])) == "POINT"))   # one coordinate row per feature
  out$pt_x <- xy[, 1]; out$pt_y <- xy[, 2]
  out$row_in_file <- seq_len(n_in)

  # 2021: owner / taxpayer names from the Points shapefile where the
  # GeoPackage is blank (same rows, same order: checked by PIN)
  if (!is.na(s$names_shp)) {
    name_fields <- c(owner_name = "OWNER_NAME", owner_more = "OWNER_MORE", tax_name = "TAX_NAME")
    lyr_shp <- sub("[.]shp$", "", basename(s$names_shp))
    sn <- st_drop_geometry(st_read(s$names_shp, query = sprintf('SELECT PIN, %s FROM "%s"',
                                   paste(name_fields, collapse = ", "), lyr_shp), quiet = TRUE))
    stopifnot(nrow(sn) == n_in, identical(sn$PIN, as.character(a$pin)))
    blank <- function(z) is.na(z) | trimws(z) == ""
    for (std in names(name_fields)) {
      fill <- blank(out[[std]]) & !blank(sn[[name_fields[[std]]]])
      out[[paste0(std, "_shp")]] <- ifelse(fill, sn[[name_fields[[std]]]], NA_character_)
    }
  }
  out$geometry <- blob::as_blob(lapply(st_as_binary(g, EWKB = FALSE), as.raw))

  dir_out <- file.path(POINTS_DIR, paste0("year=", yr), paste0("county=", cty))
  dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)
  write_parquet(out, file.path(dir_out, "part-0.parquet"))

  comp <- files[file.exists(files)]
  list(status = "written", xwalk = xw,
       source = tibble(year = yr, county = cty, source = s$source, layer = s$layer,
                       bytes = if (grepl("[.]shp$", s$source)) sum(file.size(shp_parts(sub("[.]shp$", "", s$source))), na.rm = TRUE)
                               else sum(file.size(list.files(s$source, full.names = TRUE, recursive = TRUE)), file.size(s$source)[!dir.exists(s$source)]),
                       rows = n_in, names_shp = s$names_shp,
                       n_copies = sum(cand$year == yr & cand$county == cty & cand$ext == "shp"),
                       icloud_at_read = paste(basename(was_icloud), collapse = " ")),
       log = tibble(year = yr, county = cty, rows_in = n_in, rows_out = nrow(out),
                    empty_points = sum(emp), crs_epsg = st_crs(x)$epsg))
}

# Merge-update a CSV keyed by year x county (a partial run replaces its rows)
upsert_csv <- function(new, path) {
  if (file.exists(path)) {
    old <- read_csv(path, show_col_types = FALSE, col_types = cols(.default = "c")) %>%
      mutate(year = as.integer(year))
    new <- bind_rows(old %>% anti_join(new, by = c("year", "county")),
                     new %>% mutate(across(everything(), as.character), year = as.integer(year)))
  }
  new <- new %>% mutate(.cty = match(county, COUNTIES)) %>% arrange(year, .cty) %>% select(-.cty)
  tmp <- paste0(path, ".tmp"); write_csv(new, tmp, na = "NA"); file.rename(tmp, path)
}

# Write ----
todo <- sources
if (length(only_years)) todo <- todo %>% filter(year %in% only_years)
todo <- todo %>% mutate(done = file.exists(file.path(POINTS_DIR, paste0("year=", year), paste0("county=", county), "part-0.parquet")))
cat("partitions requested:", nrow(todo), " already written:", sum(todo$done), "\n")

not_read <- list()
for (i in which(!todo$done | REWRITE)) {
  t0 <- Sys.time()
  r <- write_partition(todo[i, ])
  if (r$status != "written") {
    cat(todo$year[i], todo$county[i], "SKIPPED:", r$status, r$detail, "\n")
    not_read[[length(not_read) + 1]] <- tibble(year = todo$year[i], county = todo$county[i], source = todo$source[i], detail = r$detail)
    next
  }
  # crosswalk rows: replace this year x county's (kept in file order)
  xw_all <- if (file.exists(XWALK_OUT)) read_csv(XWALK_OUT, show_col_types = FALSE) %>%
    anti_join(r$xwalk, by = c("year", "county")) else NULL
  xw_all <- bind_rows(xw_all, r$xwalk) %>% mutate(.cty = match(county, COUNTIES)) %>%
    arrange(year, .cty) %>% select(-.cty)
  tmp <- paste0(XWALK_OUT, ".tmp"); write_csv(xw_all, tmp); file.rename(tmp, XWALK_OUT)
  upsert_csv(r$source, SOURCES_OUT)
  upsert_csv(r$log %>% mutate(seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))),
                              written_at = format(Sys.time(), "%Y-%m-%d %H:%M")), LOG_OUT)
  cat(format(Sys.time(), "%H:%M"), todo$year[i], todo$county[i], "rows", r$log$rows_in,
      " empty", r$log$empty_points, " fields", nrow(r$xwalk), "\n")
}
if (length(not_read)) {
  cat("\nNOT READ (iCloud placeholder did not download in", DOWNLOAD_TIMEOUT_MIN, "min):\n")
  print(bind_rows(not_read), n = Inf, width = Inf)
}

# Verification runs in code/08_verify_points.R (fresh R session).
