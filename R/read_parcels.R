## read_parcels.R
##
## One entry point to the MetroGIS 7-county parcel archive (2005-2024 files),
## stored once at /Users/matthewhockert/research/parcel_data as GeoParquet,
## partitioned year=YYYY/county=Name/. Built by code/02_standardize.R.
##
## Use from ANY project, inside or outside ~/research:
##   source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
##   ramsey_2016 <- read_parcels(years = 2016, counties = "Ramsey",
##                               cols = c("pin", "emv_land", "emv_total"))
##
## Two views of the same stored table:
##   names = "standardized"  one column per concept across all years; a
##                           concept a year did not record is NA that year.
##                           Values are as published (e.g. st_post_type is
##                           "ST" through 2017 and "Street" from 2018).
##   names = "original"      exactly what st_read() on that year's file gave:
##                           its column names, order, types, values, row order.
##                           The drop-in for repointed scripts. One year and
##                           one county at a time.
## Rows are never added or removed: parcels enter and exit as in the files.
## Stored geometry is the published polygon (WKB, EPSG 26915); pt_x / pt_y
## are a point on each polygon's surface, used for fast bbox filtering.
##
## layer = "points" reads the county-published Points layers instead
## (Parcels<yr><County>Points, stored as published in data/standardized_points
## by code/07_points_store.R; Matt, 2026-11-08). Same standardized names and
## types as the polygons (docs/points_column_crosswalk.csv); names = "original"
## returns exactly what st_read() of that Points layer returned. Older Points
## layers include condo-unit records whose PINs are in no polygon file.
##   p14 <- read_parcels(2014, "Ramsey", layer = "points", names = "original")
## The geometry is the published point (geometry = "polygon" or "point" both
## return it; "none" drops it); point_method / orig_fid / as_shapefile do not
## apply.

PARCEL_HOME  <- Sys.getenv("PARCEL_HOME")   # the repo folder; set in ~/.Renviron
if (PARCEL_HOME == "") stop("Set PARCEL_HOME to the parcel_data folder, e.g. PARCEL_HOME=${HOME}/parcel_data in ~/.Renviron")
PARCEL_STORE <- file.path(PARCEL_HOME, "data", "standardized")
PARCEL_XWALK <- file.path(PARCEL_HOME, "docs", "column_crosswalk.csv")
PARCEL_STORE_POINTS <- file.path(PARCEL_HOME, "data", "standardized_points")   # layer = "points"
PARCEL_XWALK_POINTS <- file.path(PARCEL_HOME, "docs", "points_column_crosswalk.csv")
PARCEL_CRS   <- 26915
source(file.path(PARCEL_HOME, "R", "download_parcels.R"))   # download_parcels(): get years from Zenodo
PARCEL_SHP_SCHEMA <- file.path(PARCEL_HOME, "docs", "shapefile_schema.csv")
## as_shapefile = TRUE (names = "original", years 2021 or 2024): the store
## holds those years from the GeoPackage / geodatabase, which keep more than
## the shapefiles of the same release. Scripts written against the
## SHAPEFILES get what st_read() of the shapefile returned: its field names
## and order (RANGE not RANGE_, Shape_Leng not Shape_Length), missing numbers
## as 0, empty or blank text as NA, text trimmed and cut to the field width,
## dates without times. Shape_Leng / Shape_Area missing from the 2021
## GeoPackage are recomputed from the polygon (close, not bit-identical).
## Row order is the container's (2024's differs from its shapefile's).
`%||%` <- function(a, b) if (is.null(a)) b else a

# parcel_linearize(g): straight-line copy of any curved boundaries (2023/2024
# geodatabases store true arcs), made by GDAL itself (temp GeoPackage read
# back with type = 6) -- the same conversion GDAL applies when it writes a
# shapefile. GEOS (st_intersects, st_make_valid, ...) rejects curves, so use
# this for spatial TESTS; keep the original geometry for what you return.
parcel_linearize <- function(g) {
  g <- sf::st_geometry(g)
  cv <- which(!as.character(sf::st_geometry_type(g)) %in% c("POLYGON", "MULTIPOLYGON") & !sf::st_is_empty(g))
  if (!length(cv)) return(g)
  tmp <- tempfile(fileext = ".gpkg")
  on.exit(unlink(tmp))
  sf::st_write(sf::st_sf(id = cv, geometry = g[cv]), tmp, quiet = TRUE)
  back <- sf::st_read(tmp, type = 6, quiet = TRUE)
  g[back$id] <- sf::st_geometry(back)
  g
}

# parcel_interior_xy(g): exactly ONE interior point per geometry, as an
# n x 2 matrix (NA for empty). st_point_on_surface on a repaired polygon can
# return a multi-point or collection for a multi-piece parcel, and
# st_coordinates() then yields extra rows -- that misaligned the first stored
# pt_x/pt_y (fixed 2026-11-07 by code/04_fix_points.R). Here the first point of
# each feature is taken explicitly.
parcel_interior_xy <- function(g) {
  g   <- sf::st_make_valid(parcel_linearize(g))
  pts <- suppressWarnings(sf::st_point_on_surface(g))
  out <- matrix(NA_real_, nrow = length(pts), ncol = 2, dimnames = list(NULL, c("X", "Y")))
  typ <- as.character(sf::st_geometry_type(pts))
  emp <- sf::st_is_empty(pts)
  one <- which(typ == "POINT" & !emp)
  if (length(one)) out[one, ] <- sf::st_coordinates(pts[one])[, 1:2, drop = FALSE]
  other <- which(typ != "POINT" & !emp)
  for (i in other) out[i, ] <- sf::st_coordinates(pts[i])[1, 1:2]
  out
}

read_parcels <- function(years    = NULL,           # e.g. 2016 or 2005:2024; NULL = all
                         counties = NULL,           # e.g. "Ramsey"; NULL = all 7
                         cols     = NULL,           # columns to return, in the chosen naming; NULL = all
                         filter   = NULL,           # optional expression, e.g. quote(emv_total > 0) (standardized names)
                         bbox     = NULL,           # optional sf / sfc / bbox; keeps parcels intersecting it
                         geometry = c("polygon", "point", "none"),
                         point_method = c("surface", "centroid", "metrogis", "metrogis_rows"),  # how polygons become points (geometry = "point")
                         orig_fid = FALSE,          # with "metrogis_rows": add ORIG_FID (polygon row - 1), as some published Points layers have
                         names    = c("standardized", "original"),
                         as_shapefile = FALSE,     # with names = "original": the year's SHAPEFILE version (2021, 2024)
                         drop_owner_names = FALSE, # blank OWNER_NAME / OWNER_MORE / TAX_NAME, reproducing the
                                                   # redacted public downloads (e.g. the Dec 2025 2024 gdb) for
                                                   # scripts that read those (Matt, 2026-11-08)
                         layer = c("polygons", "points"),
                         collapse_condos = FALSE,  # layer = "points": one row per polygon (see R/collapse_condos.R)
                         point_location = NULL) {  # layer = "points": "polygon" = the containing polygon's centroid
                                                   # (shared by condo units in one building), "published" = as published.
                                                   # Default: "polygon" for names = "standardized", "published" for "original".  # "points": the published Points layers
  pm_given <- !missing(point_method)   # (missing() must be asked before the argument is reassigned)
  geometry <- match.arg(geometry)
  point_method <- match.arg(point_method)
  names    <- match.arg(names)
  layer    <- match.arg(layer)
  is_points <- layer == "points"
  store_dir <- if (is_points) PARCEL_STORE_POINTS else PARCEL_STORE
  if (is_points && (isTRUE(as_shapefile) || isTRUE(orig_fid) || pm_given)) {
    stop('layer = "points" returns the published points: as_shapefile, orig_fid and point_method do not apply')
  }
  stopifnot(dir.exists(store_dir))
  if (names == "original" && (length(years) != 1 || length(counties) != 1)) {
    stop('names = "original" needs exactly one year and one county')
  }

  # Partition pruning by hand: list year=/county= folders and keep the
  # requested ones, so one county-year reads only that file.
  # (arrow::open_dataset is NOT used: when sf is loaded first, GDAL's own
  # bundled Arrow has already registered the local filesystem and
  # open_dataset errors. Single-file read_parquet is unaffected.)
  part_dirs <- list.dirs(store_dir, recursive = TRUE, full.names = FALSE)
  part_dirs <- part_dirs[grepl("^year=[0-9]{4}/county=[^/]+$", part_dirs)]
  parts <- data.frame(dir = part_dirs,
                      year = as.integer(sub("^year=([0-9]{4}).*", "\\1", part_dirs)),
                      county = sub(".*county=", "", part_dirs), stringsAsFactors = FALSE)
  if (!is.null(years))    parts <- parts[parts$year %in% years, ]
  if (!is.null(counties)) parts <- parts[parts$county %in% counties, ]
  if (nrow(parts) == 0) stop("no stored partitions match years/counties")

  # bbox: cheap pre-filter on the stored points (on the Arrow table, before
  # conversion to R), then an exact polygon intersection afterwards
  bb_sfc <- NULL
  if (!is.null(bbox)) {
    bb_sfc <- sf::st_transform(sf::st_as_sfc(sf::st_bbox(bbox)), PARCEL_CRS)
    bb  <- sf::st_bbox(bb_sfc)
    pad <- 2000  # meters: a parcel can intersect the box while its interior point lies outside
  }

  xwalk <- NULL
  if (isTRUE(as_shapefile) && !(names == "original" && length(years) == 1 && years %in% c(2021, 2024))) {
    stop('as_shapefile = TRUE needs names = "original" and years = 2021 or 2024')
  }
  if (names == "original" && isTRUE(as_shapefile)) {
    sx <- utils::read.csv(PARCEL_SHP_SCHEMA, stringsAsFactors = FALSE)
    sx <- sx[sx$year == years & sx$county == counties, ]
    sx <- sx[order(sx$position), ]
    xwalk <- data.frame(original_name = sx$shp_name, std_name = sx$std_name, r_type = sx$r_type,
                        ogr_type = sx$ogr_type, width = sx$width, stringsAsFactors = FALSE)
    if (!is.null(cols)) xwalk <- xwalk[xwalk$original_name %in% cols, ]
    cols_std <- unique(c(xwalk$std_name, paste0(xwalk$std_name, "_raw"), paste0(xwalk$std_name, "_shp"),
                         "row_in_shp", if (geometry != "none") "geometry_shp"))
  } else if (names == "original") {
    xwalk <- utils::read.csv(if (is_points) PARCEL_XWALK_POINTS else PARCEL_XWALK, stringsAsFactors = FALSE)
    xwalk <- xwalk[xwalk$year == years & xwalk$county == counties, ]
    if (!is.null(cols)) xwalk <- xwalk[xwalk$original_name %in% cols, ]
    cols_std <- unique(c(xwalk$std_name, paste0(xwalk$std_name, "_raw")))
  } else {
    cols_std <- cols
  }

  keep <- NULL
  if (!is.null(cols_std)) {
    keep <- c("row_in_file", cols_std,
              if (geometry != "none" || !is.null(bbox)) "geometry",
              if (!is.null(bbox)) c("pt_x", "pt_y"))
  }

  read_one <- function(i) {
    f <- file.path(store_dir, parts$dir[i], "part-0.parquet")
    avail <- names(arrow::read_parquet(f, as_data_frame = FALSE)$schema)
    # NOTE: branch explicitly. Passing `col_select = if (...) NULL else ...`
    # hands arrow an unevaluated expression, and tidyselect then selects NO
    # columns (fixed 2026-11-08; standardized reads without `cols` returned only
    # year/county).
    tb <- if (is.null(keep)) arrow::read_parquet(f, as_data_frame = FALSE) else
      arrow::read_parquet(f, col_select = dplyr::any_of(intersect(keep, avail)), as_data_frame = FALSE)
    if (!is.null(filter)) tb <- dplyr::filter(tb, !!filter)
    if (!is.null(bbox)) {
      tb <- dplyr::filter(tb, pt_x >= !!(bb[["xmin"]] - pad), pt_x <= !!(bb[["xmax"]] + pad),
                              pt_y >= !!(bb[["ymin"]] - pad), pt_y <= !!(bb[["ymax"]] + pad))
    }
    d <- as.data.frame(dplyr::collect(tb))
    # Arrow's binary type does not row-bind; use a plain list of raw vectors
    if ("geometry" %in% names(d)) d$geometry <- lapply(d$geometry, as.raw)
    if ("geometry_shp" %in% names(d)) d$geometry_shp <- lapply(d$geometry_shp, function(z) if (is.null(z)) NULL else as.raw(z))
    cbind(data.frame(year = rep(parts$year[i], nrow(d)), county = rep(parts$county[i], nrow(d)),
                     stringsAsFactors = FALSE), d)
  }
  out <- as.data.frame(dplyr::bind_rows(lapply(seq_len(nrow(parts)), read_one)))

  # geometry
  if ("geometry" %in% names(out)) {
    geom <- sf::st_as_sfc(structure(out$geometry, class = "WKB"), crs = PARCEL_CRS)
    out$geometry <- NULL
    if (!is.null(bb_sfc)) {
      hit <- lengths(sf::st_intersects(if (is_points) geom else parcel_linearize(geom), bb_sfc)) > 0
      out <- out[hit, , drop = FALSE]; geom <- geom[hit]
    }
  }

  if (names == "original") {
    if (isTRUE(as_shapefile) && "geometry_shp" %in% names(out) && exists("geom", inherits = FALSE)) {
      sg <- !vapply(out$geometry_shp, is.null, logical(1))
      if (any(sg)) geom[sg] <- sf::st_as_sfc(structure(out$geometry_shp[sg], class = "WKB"), crs = PARCEL_CRS)
    }
    out$geometry_shp <- NULL
    o   <- if (isTRUE(as_shapefile) && "row_in_shp" %in% names(out)) order(out$row_in_shp) else
           order(out$row_in_file)            # back to the file's row order
    out <- out[o, , drop = FALSE]
    rif <- out$row_in_file                    # kept for ORIG_FID
    if (exists("geom", inherits = FALSE)) geom <- geom[o]
    res <- list()
    shp_geom_lin <- NULL
    for (k in seq_len(nrow(xwalk))) {
      std <- xwalk$std_name[k]; typ <- xwalk$r_type[k]; raw <- paste0(std, "_raw")
      v <- if (typ == "character" && raw %in% names(out)) out[[raw]] else out[[std]]
      if (isTRUE(as_shapefile)) {
        if (std %in% c("shape_leng", "shape_area") && paste0(std, "_shp") %in% names(out)) {
          v <- out[[paste0(std, "_shp")]]   # the shapefile's own stored values
        } else if (is.null(v) || all(is.na(v))) {
          if (std %in% c("shape_leng", "shape_area") && exists("geom", inherits = FALSE)) {
            # not in the 2021 GeoPackage: recompute from the (linearized) polygon
            if (is.null(shp_geom_lin)) shp_geom_lin <- sf::st_make_valid(parcel_linearize(geom))
            v <- if (std == "shape_area") as.numeric(sf::st_area(shp_geom_lin)) else
              as.numeric(sf::st_length(sf::st_cast(sf::st_boundary(shp_geom_lin), "MULTILINESTRING")))
          }
        }
        if (typ == "character") {
          shp_side <- paste0(std, "_shp")   # 2021 owner names kept from the shapefile
          if (shp_side %in% names(out)) v <- ifelse(is.na(out[[shp_side]]), v, out[[shp_side]])
          v <- trimws(as.character(v))
          w <- xwalk$width[k]
          if (!is.na(w)) { long <- !is.na(v) & nchar(v, type = "bytes") > w
                           v[long] <- vapply(v[long], function(z) { while (nchar(z, type = "bytes") > w) z <- substr(z, 1, nchar(z) - 1); z }, character(1))
                           v <- trimws(v) }   # cut to width, then trim (as the shapefile reader does)
          v[!is.na(v) & v == ""] <- NA_character_
        } else if (typ %in% c("integer", "numeric")) {
          v <- as.numeric(v); v[is.na(v)] <- 0   # shapefiles store missing numbers as 0
        } else if (typ == "Date" && inherits(v, "POSIXt")) {
          v <- as.Date(v, tz = "UTC")
        }
      }
      v <- switch(typ,
                  integer   = as.integer(v),
                  numeric   = as.numeric(v),
                  character = as.character(v),
                  Date      = as.Date(v, tz = "UTC"),
                  POSIXct   = { attr(v, "tzone") <- ""; v },   # st_read returns local time
                  v)
      res[[xwalk$original_name[k]]] <- v
    }
    out <- as.data.frame(res, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    out$row_in_file <- NULL
    # standardized view: fill 2021 owner names from the shapefile sidecars
    out$row_in_shp <- NULL; out$geometry_shp <- NULL
    out$shape_leng_shp <- NULL; out$shape_area_shp <- NULL   # shapefile-only; standardized keeps the container values
    for (sc in grep("_shp$", names(out), value = TRUE)) {
      base <- sub("_shp$", "", sc)
      if (base %in% names(out)) out[[base]] <- ifelse(is.na(out[[sc]]), out[[base]], out[[sc]])
      out[[sc]] <- NULL
    }
  }

  # Points are computed from the stored polygons at read time; no point
  # layer is stored. "surface" = st_point_on_surface (always inside the
  # parcel); "centroid" = st_centroid (can fall outside L-shaped parcels).
  # Polygons are repaired (st_make_valid) and curves linearized first, only
  # for this calculation. Empty polygons give empty points (rows kept).
  # NOTE: these are not the county-published Points layers, which can have
  # more than one point per parcel; see docs/README for the comparison.
  #
  # "metrogis" emulates the Ramsey / Hennepin published Points layers (checked
  # on Ramsey 2020 and 2023, Hennepin 2020): placeholder polygons dropped, then
  # one point per polygon row at the centroid, moved to a point on the surface
  # when the centroid falls outside the parcel. Row count changes only by the
  # dropped placeholders.
  if (exists("geom", inherits = FALSE) && geometry == "point" && !is_points) {
    g <- geom
    g <- sf::st_make_valid(parcel_linearize(g))
    if (point_method == "metrogis_rows") {
      # Emulates Points layers with ONE point per polygon row (checked on
      # Washington 2015: same rows and order as the polygons, placeholders
      # kept, ORIG_FID = polygon row - 1). The point is the plain polygon
      # centroid, even when it falls outside the parcel: 100% exact to 1 cm.
      out$Shape_Leng <- NULL; out$Shape_Length <- NULL; out$Shape_Area <- NULL; out$shape_leng <- NULL; out$shape_area <- NULL
      geom <- suppressWarnings(sf::st_centroid(g))
      if (isTRUE(orig_fid)) {
        if (!exists("rif", inherits = FALSE)) stop('orig_fid = TRUE needs names = "original"')
        out$ORIG_FID <- as.integer(rif - 1L)
      }
    } else if (point_method == "metrogis") {
      pin_col <- if ("pin" %in% names(out)) "pin" else if ("PIN" %in% names(out)) "PIN" else
        stop('point_method = "metrogis" needs the PIN column (include "pin"/"PIN" in cols)')
      # the published Points layers omit placeholder polygons: words (Water,
      # State RoW, Park) and short codes (condo common areas like 123-C94).
      # Real PINs have 9+ digits, some with a letter (Ramsey 123-1789M98756),
      # so the rule is: at least 6 digits after the county prefix.
      # Checked against the published Ramsey and Hennepin 2020 Points layers.
      real <- nchar(gsub("[^0-9]", "", sub("^[0-9]{3}-", "", out[[pin_col]]))) >= 6
      out <- out[real, , drop = FALSE]; g <- g[real]
      # and carry no polygon size fields
      out$Shape_Leng <- NULL; out$Shape_Length <- NULL; out$Shape_Area <- NULL; out$shape_leng <- NULL; out$shape_area <- NULL
      # One point per remaining polygon ROW: multi-polygon parcels are NOT
      # collapsed (2023 Ramsey: a two-polygon PIN gets two points, each with its
      # own ACRES_POLY). Corrected 2026-11-08; the earlier per-PIN collapse only
      # matched 2020 because its repeated PINs were all placeholders.
      g_pin <- g
      cen <- suppressWarnings(sf::st_centroid(g_pin))
      # centroid inside its OWN parcel? (one indexed intersection; element i
      # of the result lists the parcels point i falls in)
      hits <- sf::st_intersects(cen, g_pin)
      inside <- vapply(seq_along(hits), function(i) i %in% hits[[i]], logical(1))
      pos <- suppressWarnings(sf::st_point_on_surface(g_pin[!inside]))
      cen[!inside] <- pos
      geom <- cen
    } else {
      geom <- suppressWarnings(if (point_method == "surface") sf::st_point_on_surface(g) else sf::st_centroid(g))
    }
  }
  if (exists("geom", inherits = FALSE) && geometry != "none") {
    out <- sf::st_sf(out, geometry = geom)
  }
  out$pt_x <- NULL; out$pt_y <- NULL
  if (isTRUE(drop_owner_names)) {
    for (v in intersect(c("OWNER_NAME", "OWNER_MORE", "TAX_NAME", "owner_name", "owner_more", "tax_name"), names(out)))
      out[[v]] <- NA_character_
  }
  # Points placed at their polygon's centroid (Matt, 2026-11-09): every unit
  # point in a building shares the building polygon's centroid, moved inside
  # the parcel when the centroid falls outside. Points in no polygon keep the
  # published location.
  if (layer == "points" && inherits(out, "sf")) {
    if (is.null(point_location)) point_location <- if (names == "standardized") "polygon" else "published"
    if (point_location == "polygon" && !isTRUE(collapse_condos)) {
      key <- paste(out$year, out$county)
      newg <- sf::st_geometry(out)
      for (k in unique(key)) {
        ix <- which(key == k)
        pg <- read_parcels(years = out$year[ix[1]], counties = out$county[ix[1]], cols = "pin", geometry = "polygon")
        pgl <- sf::st_make_valid(parcel_linearize(sf::st_geometry(pg)))
        cen <- suppressWarnings(sf::st_centroid(pgl))
        h <- sf::st_intersects(cen, pgl); inside <- vapply(seq_along(h), function(i) i %in% h[[i]], logical(1))
        if (any(!inside)) cen[!inside] <- suppressWarnings(sf::st_point_on_surface(pgl[!inside]))
        hit <- sf::st_intersects(newg[ix], pgl)
        poly_of <- vapply(hit, function(z) if (length(z)) z[1] else NA_integer_, integer(1))
        ok <- !is.na(poly_of)
        newg[ix[ok]] <- cen[poly_of[ok]]
      }
      sf::st_geometry(out) <- newg
    }
  }
  if (isTRUE(collapse_condos)) {
    if (layer != "points" || names != "standardized" || geometry == "none")
      stop('collapse_condos = TRUE needs layer = "points", names = "standardized" and geometry')
    source(file.path(PARCEL_HOME, "R", "collapse_condos.R"), local = TRUE)
    out <- do.call(rbind, lapply(split(seq_len(nrow(out)), paste(out$year, out$county)), function(ix) {
      p  <- out[ix, ]
      pg <- read_parcels(years = p$year[1], counties = p$county[1], cols = "pin", geometry = "polygon")
      parcel_collapse_condos(p, pg)
    }))
  }
  out
}
