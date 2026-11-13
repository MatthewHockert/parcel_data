`%||%` <- function(a, b) if (is.null(a)) b else a

## verify_read.R
##
## compare_reads(old, new): is `new` (from read_parcels(names = "original"))
## the same data as `old` (from st_read() on the original file)?
## Used to verify the store and every repointed script before deletion.
##
## Checks, each reported (not just pass/fail):
##   rows     same number of rows
##   names    same column names in the same order
##   values   per column: identical, or (numbers) equal within 1e-9 relative
##   geometry identical WKB, per row
## Returns a one-row tibble; `ok` is TRUE only if every check passes.

## gdb mode (key = "PIN", geom_tol = 1): for scripts that read a year from a
## geodatabase while the store holds that year's shapefile release (2024).
## Same parcels and values, but rows come in a different order, the length
## field is Shape_Length, and some boundaries are true curves. Rows are
## aligned by `key`; geometry passes if the Hausdorff distance after
## linearizing curves is <= geom_tol meters; Shape_Length vs Shape_Leng and
## the geometry column name are ignored.
## shp_losses = TRUE (with key and geom_tol): for scripts that read the 2024
## SHAPEFILES while the store holds the 2024 geodatabase (Matt, 2026-11-07).
## Allows exactly the shapefile format's known losses: a missing number in
## the store may be 0 in the shapefile, and date-times compare at day
## precision (shapefiles keep dates only). Everything else must match.
## rel_tol: named relative tolerances for specific numeric columns, e.g.
## c(Shape_Leng = 1e-3, Shape_Area = 1e-3) when they are recomputed.
compare_reads <- function(old, new, label = "", key = NULL, geom_tol = NULL, shp_losses = FALSE, rel_tol = NULL) {
  if (!is.null(key)) {
    # rows sharing a key (placeholder PINs like 123-Water) are tie-broken by
    # their bounding-box corner rounded to 1 m, which is the same for a curve
    # and its straight-line version (Shape_Area is not)
    corner <- function(d) {
      if (!inherits(d, "sf")) return(list(seq_len(nrow(d)), seq_len(nrow(d))))
      bb <- vapply(sf::st_geometry(d), function(g) if (sf::st_is_empty(g)) c(NA, NA) else as.numeric(sf::st_bbox(g))[1:2], numeric(2))
      list(round(bb[1, ]), round(bb[2, ]))
    }
    co <- corner(old); cn <- corner(new)
    old <- old[order(old[[key]], co[[1]], co[[2]]), ]
    new <- new[order(new[[key]], cn[[1]], cn[[2]]), ]
    if ("Shape_Length" %in% names(old) && "Shape_Leng" %in% names(new)) names(old)[names(old) == "Shape_Length"] <- "Shape_Leng"
    if ("Shape_Leng" %in% names(old) && "Shape_Length" %in% names(new)) names(new)[names(new) == "Shape_Length"] <- "Shape_Leng"
  }
  g_old <- if (inherits(old, "sf")) sf::st_geometry(old) else NULL
  g_new <- if (inherits(new, "sf")) sf::st_geometry(new) else NULL
  a <- if (inherits(old, "sf")) sf::st_drop_geometry(old) else old
  b <- if (inherits(new, "sf")) sf::st_drop_geometry(new) else new
  if (!is.null(key)) b <- b[, intersect(names(a), names(b)), drop = FALSE]

  rows_ok  <- nrow(a) == nrow(b)
  names_ok <- identical(names(a), names(b))

  col_diff <- character(0)
  if (rows_ok) {
    for (nm in intersect(names(a), names(b))) {
      x <- a[[nm]]; y <- b[[nm]]
      if (shp_losses) {
        if (inherits(y, "POSIXt")) y <- as.Date(y, tz = "UTC")   # store instants are midnight UTC for dates
        if (inherits(x, "POSIXt")) x <- as.Date(x, tz = "UTC")
        if (is.numeric(x) && is.numeric(y)) y[is.na(y) & !is.na(x) & x == 0] <- 0
        if (inherits(x, "Date") && inherits(y, "Date")) { x <- as.numeric(x); y <- as.numeric(y) }
        if (is.character(x) && is.character(y)) {   # shapefile reader trims spaces and reads "" as NA
          x <- trimws(x); y <- trimws(y); y[!is.na(y) & y == "" & is.na(x)] <- NA_character_ }
      }
      is_time <- function(z) inherits(z, c("Date", "POSIXt"))
      same <- if (is_time(x) && is_time(y)) {
        # compare instants, not printed text (time zones change the print)
        tx <- if (inherits(x, "Date")) as.numeric(x) * 86400 else as.numeric(x)
        ty <- if (inherits(y, "Date")) as.numeric(y) * 86400 else as.numeric(y)
        identical(is.na(tx), is.na(ty)) && all(tx == ty, na.rm = TRUE) && inherits(x, "Date") == inherits(y, "Date")
      } else if (is.numeric(x) && is.numeric(y)) {
        tol <- if (!is.null(rel_tol) && nm %in% names(rel_tol)) rel_tol[[nm]] else 1e-9
        isTRUE(all.equal(as.numeric(x), as.numeric(y), tolerance = tol, check.attributes = FALSE))
      } else {
        identical(as.character(x), as.character(y))
      }
      if (!same) col_diff <- c(col_diff, nm)
    }
  }

  geom_ok <- NA
  if (!is.null(g_old) && !is.null(g_new) && rows_ok) {
    if (is.null(geom_tol)) {
      geom_ok <- identical(lapply(sf::st_as_binary(g_old), as.raw),
                           lapply(sf::st_as_binary(g_new), as.raw))
    } else {
      # Only rows whose WKB differs are measured. Curved boundaries (2023/2024
      # geodatabases) are converted to straight segments by GDAL itself
      # (written to a temp GeoPackage and read back with type = 6), the same
      # conversion the shapefile export used; R-side casting overstates gaps.
      lin_gdal <- function(g) {
        cv <- which(!as.character(sf::st_geometry_type(g)) %in% c("POLYGON", "MULTIPOLYGON") & !sf::st_is_empty(g))
        if (!length(cv)) return(g)
        tmp <- tempfile(fileext = ".gpkg")
        sf::st_write(sf::st_sf(id = cv, geometry = g[cv]), tmp, quiet = TRUE)
        back <- sf::st_read(tmp, type = 6, quiet = TRUE)
        unlink(tmp)
        g[back$id] <- sf::st_geometry(back)
        g
      }
      wo <- lapply(sf::st_as_binary(g_old), as.raw); wn <- lapply(sf::st_as_binary(g_new), as.raw)
      diff_rows <- which(!mapply(identical, wo, wn))
      go <- lin_gdal(g_old[diff_rows]); gn <- lin_gdal(g_new[diff_rows])
      empty_mismatch <- sf::st_is_empty(go) != sf::st_is_empty(gn)
      both <- which(!sf::st_is_empty(go) & !sf::st_is_empty(gn))
      hd <- vapply(both, function(i) as.numeric(sf::st_distance(go[i], gn[i], which = "Hausdorff")), numeric(1))
      bad <- sum(empty_mismatch) + sum(hd > geom_tol)
      geom_ok <- bad == 0L
      attr(geom_ok, "detail") <- sprintf("%d rows differ in WKB; %d beyond %g m (max %.2f m)",
                                         length(diff_rows), bad, geom_tol, if (length(hd)) max(hd) else 0)
    }
  }

  # (detail extracted first: inside tibble() the new geom_ok column would mask it)
  geom_detail <- if (is.null(attr(geom_ok, "detail"))) "" else attr(geom_ok, "detail")
  geom_flag   <- as.logical(geom_ok)
  tibble::tibble(label = label, rows_old = nrow(a), rows_new = nrow(b),
                 rows_ok = rows_ok, names_ok = names_ok,
                 cols_differ = paste(col_diff, collapse = ", "),
                 geom_ok = geom_flag, geom_detail = geom_detail,
                 ok = rows_ok && names_ok && length(col_diff) == 0 && !isFALSE(geom_flag))
}


## compare_point_reads(old, new, polygons): for scripts that read the county-
## published Points layers, repointed to read_parcels(point_method = "metrogis").
## Rule (Matt, 2026-11-07): rows and attributes identical (except VIEWID, an
## id the Points layer assigns to its own features), and every point either
## within 1 m of the published point or inside the same parcel polygon.
## ArcGIS places points for parcels whose centroid falls outside the polygon
## with an unpublished routine, so those ~3% cannot match exactly.
compare_point_reads <- function(old, new, polygons, pin = "PIN", label = "") {
  o <- old[order(old[[pin]]), ]; n <- new[match(o[[pin]], new[[pin]]), ]
  rows_ok <- nrow(old) == nrow(new) && !anyNA(n[[pin]])
  drop <- c("VIEWID")
  attr_cmp <- compare_reads(sf::st_drop_geometry(o)[setdiff(names(o), c(drop, attr(o, "sf_column")))],
                            sf::st_drop_geometry(n)[setdiff(names(n), c(drop, attr(n, "sf_column")))])
  d <- as.numeric(sf::st_distance(sf::st_geometry(o), sf::st_geometry(n), by_element = TRUE))
  far <- which(d >= 1)
  same_parcel <- rep(TRUE, length(d))
  if (length(far)) {
    poly <- sf::st_make_valid(sf::st_geometry(polygons)[match(o[[pin]][far], polygons[[pin]])])
    hits <- sf::st_intersects(sf::st_geometry(o)[far], poly)   # element i: polygons point i falls in
    same_parcel[far] <- vapply(seq_along(hits), function(i) i %in% hits[[i]], logical(1))
  }
  tibble::tibble(label = label, rows_ok = rows_ok, attrs_ok = attr_cmp$ok, cols_differ = attr_cmp$cols_differ,
                 share_exact = round(mean(d < 0.01), 4), share_within_1m = round(mean(d < 1), 4),
                 share_ok_points = round(mean(d < 1 | same_parcel), 4), max_dist_m = round(max(d), 1),
                 ok = rows_ok && attr_cmp$ok && all(d < 1 | same_parcel))
}

## resolve_old(path): for verification only. If the ORIGINAL parcel file at
## `path` (a .shp, or a .gdb / .gpkg) is an iCloud placeholder that won't
## download, return the parcel_data/data/raw copy of the same file -- but
## only if every component file has the same byte size (a different download
## of the same name, e.g. a later redacted gdb, never matches). Otherwise
## returns `path` unchanged. Matt approved this substitution 2026-11-08.
## attr(result, "via_raw") is TRUE when the raw copy is used; record it.
resolve_old <- function(path) {
  is_dataless <- function(f) {
    fl <- suppressWarnings(as.numeric(system2("stat", c("-f", "%f", shQuote(f)), stdout = TRUE, stderr = FALSE)))
    length(fl) == 1 && !is.na(fl) && bitwAnd(fl %/% 2^30, 1L) == 1L
  }
  raw_root <- file.path(Sys.getenv("PARCEL_HOME"), "data/raw")
  bn <- basename(sub("[.](shp|gdb|gpkg)$", "", path))
  yr <- regmatches(bn, regexpr("20[0-9]{2}", bn))
  if (!length(yr)) { pd <- basename(dirname(path)); yr <- regmatches(pd, regexpr("20[0-9]{2}", pd)) }
  out <- path; attr(out, "via_raw") <- FALSE
  if (!length(yr)) return(out)
  if (grepl("[.]shp$", path)) {
    stem <- sub("[.]shp$", "", path)
    comps <- paste0(stem, c(".shp", ".shx", ".dbf", ".prj"))
    if (!any(vapply(comps[file.exists(comps)], is_dataless, logical(1)))) return(out)
    raw_stem <- file.path(raw_root, yr, basename(stem))
    rc <- paste0(raw_stem, c(".shp", ".shx", ".dbf", ".prj"))
    if (all(file.exists(rc)) && all(file.size(rc) == file.size(comps))) {
      out <- paste0(raw_stem, ".shp"); attr(out, "via_raw") <- TRUE
    }
  } else if (grepl("[.](gdb|gpkg)$", path)) {
    files <- if (dir.exists(path)) list.files(path, full.names = TRUE) else path
    if (!any(vapply(files, is_dataless, logical(1)))) return(out)
    rp <- file.path(raw_root, yr, basename(path))
    rf <- if (dir.exists(rp)) list.files(rp, full.names = TRUE) else rp
    if (length(rf) == length(files) && all(sort(basename(rf)) == sort(basename(files))) &&
        all(file.size(rf[order(basename(rf))]) == file.size(files[order(basename(files))]))) {
      out <- rp; attr(out, "via_raw") <- TRUE
    }
  }
  out
}
