## diagnosis_hwy36_2015.R (2026-11-08): read-only diagnosis of why the
## hwy-36 Washington 2015 Points read failed compare_point_reads().
suppressMessages({library(sf); library(dplyr)})
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
p <- "/Users/matthewhockert/Desktop/AO/hwy-36-job-access/hwy-36/data/washington_county_parcels/shp_plan_regonal_parcels_2015/Parcels2015WashingtonPoints.shp"
old <- st_drop_geometry(st_read(p, quiet = TRUE))
pol <- st_drop_geometry(read_parcels(2015, "Washington", names = "original", geometry = "polygon"))
new <- st_drop_geometry(read_parcels(2015, "Washington", names = "original", geometry = "point", point_method = "metrogis"))
cat("rows: old points", nrow(old), " store polygons", nrow(pol), " store metrogis points", nrow(new), "\n")
cat("unique PIN: old", n_distinct(old$PIN), " pol", n_distinct(pol$PIN), " new", n_distinct(new$PIN), "\n")
cat("PIN sets equal old vs pol:", setequal(old$PIN, pol$PIN), "\n")
cat("old PINs not in new:", sum(!old$PIN %in% new$PIN), " examples:", head(unique(old$PIN[!old$PIN %in% new$PIN]), 8), "\n")
cat("old rows whose PIN is duplicated in old:", sum(old$PIN %in% old$PIN[duplicated(old$PIN)]), "\n")
cat("old cols not in pol:", setdiff(names(old), names(pol)), " | pol cols not in old:", setdiff(names(pol), names(old)), "\n")

# 1) Points layer vs polygons, row by row in file order (ORIG_FID = polygon row?)
common <- setdiff(intersect(names(old), names(pol)), c("Shape_Leng", "Shape_Area", "VIEWID"))
if ("ORIG_FID" %in% names(old)) cat("ORIG_FID == 1..n:", identical(as.integer(old$ORIG_FID), seq_len(nrow(old))), "\n")
cmp_cols <- function(a, b) vapply(common, function(nm) {
  x <- a[[nm]]; y <- b[[nm]]
  if (is.numeric(x) && is.numeric(y)) isTRUE(all.equal(as.numeric(x), as.numeric(y), tolerance = 1e-9, check.attributes = FALSE))
  else identical(as.character(x), as.character(y))
}, logical(1))
if (nrow(old) == nrow(pol)) { r <- cmp_cols(old, pol); cat("points vs polygons, file order: differing cols:", names(r)[!r], "\n") }
o2 <- old[order(old$PIN, old$ORIG_FID %||% seq_len(nrow(old))), ]; p2 <- pol[order(pol$PIN, seq_len(nrow(pol))), ]
r2 <- cmp_cols(o2, p2); cat("points vs polygons, sorted by PIN: differing cols:", names(r2)[!r2], "\n")

# 2) points vs metrogis points on unique, shared PINs only
u <- old$PIN[!old$PIN %in% old$PIN[duplicated(old$PIN)]]
u <- intersect(u, new$PIN)
a <- old[match(u, old$PIN), ]; b <- new[match(u, new$PIN), ]
r3 <- cmp_cols(a, b); cat("on", length(u), "unique shared PINs, old vs new differing cols:", names(r3)[!r3], "\n")
for (nm in names(r3)[!r3]) cat("  ", nm, "rows differing:", sum(!mapply(identical, as.character(a[[nm]]), as.character(b[[nm]]))), "\n")
