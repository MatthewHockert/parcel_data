## parcel_columns(): list the columns read_parcels() can return, without reading any data.
##   parcel_columns()                                   # every standardized column, all years
##   parcel_columns(2014:2016, "Ramsey")                # columns recorded in those years
##   parcel_columns(2016, "Ramsey", names = "original") # that file's own field names, in order
##   parcel_columns(2021, "Ramsey", layer = "points")
## Reads the crosswalks in docs/, so it works before download_parcels().
## Standardized view: one row per column (year and county first), its type,
## the years it was recorded and the original field names it came from. A
## column not recorded in a year is NA there. Original view: one row per field
## of one year x county file, in file order.

parcel_columns <- function(years    = NULL,
                           counties = NULL,
                           layer    = c("polygons", "points"),
                           names    = c("standardized", "original"),
                           as_shapefile = FALSE) {   # with names = "original": the 2021 / 2024 shapefile fields
  layer <- match.arg(layer)
  names <- match.arg(names)
  if (names == "original" && (length(years) != 1 || length(counties) != 1))
    stop('names = "original" needs exactly one year and one county')

  if (names == "original" && isTRUE(as_shapefile)) {
    sx <- utils::read.csv(PARCEL_SHP_SCHEMA, stringsAsFactors = FALSE)
    sx <- sx[sx$year == years & sx$county == counties, ]
    if (!nrow(sx)) stop("as_shapefile = TRUE is only for 2021 and 2024")
    sx <- sx[order(sx$position), ]
    return(data.frame(column = sx$shp_name, std_name = sx$std_name, type = sx$r_type,
                      stringsAsFactors = FALSE))
  }

  xw <- utils::read.csv(if (layer == "points") PARCEL_XWALK_POINTS else PARCEL_XWALK,
                        stringsAsFactors = FALSE)
  if (!is.null(years))    xw <- xw[xw$year %in% years, ]
  if (!is.null(counties)) xw <- xw[xw$county %in% counties, ]
  if (!nrow(xw)) stop("no columns for those years / counties (years are 2005-2025)")

  if (names == "original") {
    return(data.frame(column = xw$original_name, std_name = xw$std_name, type = xw$r_type,
                      stringsAsFactors = FALSE))
  }

  # compress a set of years to "2005-2017, 2019"
  year_ranges <- function(y) {
    y <- sort(unique(y)); brk <- c(0, which(diff(y) != 1), length(y))
    paste(vapply(seq_len(length(brk) - 1), function(i) {
      a <- y[brk[i] + 1]; b <- y[brk[i + 1]]
      if (a == b) as.character(a) else paste0(a, "-", b)
    }, character(1)), collapse = ", ")
  }
  # the type read_parcels() returns, from every year's types: text only -> character,
  # dates -> POSIXct (stored as UTC timestamps), anything numeric -> numeric
  all_xw <- utils::read.csv(if (layer == "points") PARCEL_XWALK_POINTS else PARCEL_XWALK, stringsAsFactors = FALSE)
  store_type <- vapply(split(all_xw$r_type, all_xw$std_name), function(ty) {
    if (all(ty == "character")) "character" else if (all(ty %in% c("Date", "POSIXct"))) "POSIXct" else "numeric"
  }, character(1))
  mixed_all <- names(store_type)[vapply(split(all_xw$r_type, all_xw$std_name), function(ty)
    any(ty == "character") && any(ty %in% c("numeric", "integer")), logical(1))]
  out <- do.call(rbind, lapply(split(xw, xw$std_name), function(d) {
    data.frame(column = d$std_name[1], type = store_type[[d$std_name[1]]],
               years = year_ranges(d$year),
               original_names = paste(unique(d$original_name), collapse = ", "),
               stringsAsFactors = FALSE)
  }))
  # columns stored as numbers in some years and text in others keep a <col>_raw text copy
  mixed <- out[out$column %in% mixed_all, ]
  raw <- if (nrow(mixed)) data.frame(column = paste0(mixed$column, "_raw"), type = "character",
                                     years = mixed$years, original_names = mixed$original_names,
                                     stringsAsFactors = FALSE)
  out <- rbind(out, raw)
  out <- out[order(out$column), ]
  ids <- data.frame(column = c("year", "county"), type = c("integer", "character"),
                    years = year_ranges(xw$year), original_names = "(added by read_parcels)",
                    stringsAsFactors = FALSE)
  out <- rbind(ids, out)
  rownames(out) <- NULL
  out
}
