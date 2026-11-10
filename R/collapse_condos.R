## collapse_condos.R
##
## parcel_collapse_condos(points, polygons): roll the county-published unit
## points (condo units stacked on one building) up to ONE row per polygon,
## like the polygon layer everywhere else. Used by
## read_parcels(..., layer = "points", collapse_condos = TRUE).
## Rules (Matt, 2026-11-08):
##   - each point is assigned to the polygon it falls in (same year / county);
##     if it falls in several (stacked condo polygons, 2018+), the first;
##   - additive fields are SUMMED: emv_land, emv_bldg, emv_total, tax_capac,
##     total_tax, spec_asses, fin_sq_ft, num_units, sale_value;
##   - n_units = number of points combined;
##   - every other field takes the MOST COMMON non-missing value among the
##     units; where units disagree a <col>_n_distinct column says how many
##     distinct values there were (only added for columns where that happens);
##   - pin = the polygon's PIN; unit_pins = the unit PINs, ";"-separated;
##   - geometry = one point per polygon (centroid, moved inside if outside);
##   - points inside no polygon are kept as their own rows, unmatched = TRUE.
## Works on the STANDARDIZED view (lower-case names).

parcel_collapse_condos <- function(points, polygons) {
  stopifnot(inherits(points, "sf"), inherits(polygons, "sf"), "pin" %in% names(points), "pin" %in% names(polygons))
  additive <- c("emv_land", "emv_bldg", "emv_total", "tax_capac", "total_tax",
                "spec_asses", "fin_sq_ft", "num_units", "sale_value")

  # assign each point to a polygon (straight-line copy for curved boundaries)
  pg <- sf::st_make_valid(parcel_linearize(sf::st_geometry(polygons)))
  hits <- sf::st_intersects(sf::st_geometry(points), pg)
  poly_of <- vapply(hits, function(h) if (length(h)) h[1] else NA_integer_, integer(1))

  pts <- sf::st_drop_geometry(points)
  pts$.poly <- poly_of
  matched   <- pts[!is.na(pts$.poly), , drop = FALSE]
  unmatched <- pts[is.na(pts$.poly), , drop = FALSE]

  mode_of <- function(v) {
    v <- v[!is.na(v)]
    if (!length(v)) return(v[NA_integer_][1])
    u <- unique(v); u[which.max(tabulate(match(v, u)))]
  }
  attr_cols <- setdiff(names(matched), c(".poly", "pin", "year", "county"))
  grp <- split(seq_len(nrow(matched)), matched$.poly)
  multi <- vapply(grp, length, integer(1)) > 1

  # single-unit polygons pass through unchanged
  single <- matched[unlist(grp[!multi]), , drop = FALSE]
  single$n_units <- 1L
  single$unit_pins <- single$pin

  # multi-unit polygons: sum additive, mode the rest, count disagreements
  multi_rows <- lapply(grp[multi], function(ix) {
    d <- matched[ix, , drop = FALSE]
    r <- d[1, , drop = FALSE]
    for (cl in attr_cols) {
      v <- d[[cl]]
      if (cl %in% additive && is.numeric(v)) {
        r[[cl]] <- if (all(is.na(v))) NA else sum(v, na.rm = TRUE)
      } else {
        r[[cl]] <- mode_of(v)
        nd <- length(unique(v[!is.na(v)]))
        if (nd > 1) r[[paste0(cl, "_n_distinct")]] <- nd
      }
    }
    r$n_units <- length(ix)
    r$unit_pins <- paste(d$pin, collapse = ";")
    r
  })
  multi_df <- if (length(multi_rows)) dplyr::bind_rows(multi_rows) else NULL

  out <- dplyr::bind_rows(single, multi_df)
  out$pin <- polygons$pin[out$.poly]        # the building's PIN
  out$unmatched <- FALSE
  geom <- pg[out$.poly]

  if (nrow(unmatched)) {
    unmatched$n_units <- 1L; unmatched$unit_pins <- unmatched$pin; unmatched$unmatched <- TRUE
    out  <- dplyr::bind_rows(out, unmatched)
    geom <- c(geom, sf::st_geometry(points)[is.na(poly_of)])
  }

  # one point per polygon: centroid, moved inside when it falls outside
  is_poly <- !out$unmatched
  pt <- geom
  if (any(is_poly)) {
    cen <- suppressWarnings(sf::st_centroid(geom[is_poly]))
    h2 <- sf::st_intersects(cen, geom[is_poly])
    inside <- vapply(seq_along(h2), function(i) i %in% h2[[i]], logical(1))
    if (any(!inside)) cen[!inside] <- suppressWarnings(sf::st_point_on_surface(geom[is_poly][!inside]))
    pt[is_poly] <- cen
  }
  out$.poly <- NULL
  nd_cols <- grep("_n_distinct$", names(out), value = TRUE)
  for (cl in nd_cols) out[[cl]][is.na(out[[cl]])] <- 1L
  sf::st_sf(out, geometry = sf::st_sfc(pt, crs = sf::st_crs(points)))
}
