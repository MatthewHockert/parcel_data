## 04_fix_points.R
##
## Recompute the stored pt_x / pt_y in every partition. The first write
## (02_standardize.R before 2026-11-07 fix) misaligned them after any parcel
## whose repaired polygon gave more than one interior point (e.g. Ramsey 2011:
## 45.6% of points > 5 km from their parcel). Only pt_x / pt_y change; every
## other column and the row order are rewritten as read. Polygons, attributes
## and the original view were never affected (verified separately).
## Check after: every non-empty parcel's point lies inside its own polygon.

suppressPackageStartupMessages({ library(dplyr); library(arrow); library(sf); library(readr) })
PD_ROOT <- "/Users/matthewhockert/research/parcel_data"
source(file.path(PD_ROOT, "R", "read_parcels.R"))

files <- list.files(file.path(PD_ROOT, "data", "standardized"), pattern = "part-0[.]parquet$",
                    recursive = TRUE, full.names = TRUE)
only <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE))); only <- only[!is.na(only)]
if (length(only)) files <- files[grepl(paste0("year=(", paste(only, collapse = "|"), ")/"), files)]

log <- bind_rows(lapply(files, function(f) {
  tb <- read_parquet(f, as_data_frame = FALSE)
  d  <- as.data.frame(tb)
  g  <- st_as_sfc(structure(lapply(d$geometry, as.raw), class = "WKB"), crs = 26915)
  old_x <- d$pt_x
  xy <- parcel_interior_xy(g)
  d$pt_x <- xy[, "X"]; d$pt_y <- xy[, "Y"]
  # inside-own-polygon check
  pts <- st_as_sf(data.frame(i = seq_len(nrow(d)), x = d$pt_x, y = d$pt_y)[!is.na(d$pt_x), ],
                  coords = c("x", "y"), crs = 26915)
  gl  <- st_make_valid(parcel_linearize(g))
  hits <- st_intersects(pts, gl)
  inside <- vapply(seq_len(nrow(pts)), function(k) pts$i[k] %in% hits[[k]], logical(1))
  d$geometry <- blob::as_blob(lapply(d$geometry, as.raw))
  write_parquet(d, f)
  part <- sub(".*standardized/", "", dirname(f))
  r <- tibble(partition = part, rows = nrow(d), changed = sum(abs(old_x - d$pt_x) > 0.01, na.rm = TRUE),
              pt_missing = sum(is.na(d$pt_x)), inside_own = mean(inside))
  cat(format(Sys.time(), "%H:%M"), part, "changed", r$changed, "inside", round(r$inside_own, 5), "\n")
  r
}))
write_csv(log, file.path(PD_ROOT, "docs", "fix_points_log.csv"))
cat("partitions:", nrow(log), " any point outside its parcel:", sum(log$inside_own < 1), "\n")
print(log %>% filter(inside_own < 1))
