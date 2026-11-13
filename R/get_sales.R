## get_sales.R: one row per recorded sale, built from the yearly assessor files.
##
## Each yearly file lists only a parcel's most recent sale (sale_date,
## sale_value), and that sale repeats in every later file until the parcel
## sells again. get_sales() stacks the files, keeps one row per county, pin and
## sale date, and attaches the assessor values from the FIRST file that lists
## the sale (the assessment closest to the sale). The files record no sale or
## deed type, so none is returned.
##
## What it drops, and why:
##   - rows with no sale_date
##   - rows with no pin (some Washington 2007-2009 rows carry only the county
##     prefix, e.g. "163-"), since they cannot be told apart
##   - sale dates after the end of the file's year (they cannot have happened
##     yet, e.g. 8200 in Ramsey 2010); counted in a message
## What it keeps: sale_value of 0 or missing (filter them yourself), and sales
## older than 2005, whose values come from the 2005 file (see value_lag_years).
## Two sales of one parcel between two files show up as the later one only.
##
##   s <- get_sales(2014:2024, "Ramsey")
##   s <- get_sales(2020, "Hennepin", cols = c("emv_total", "city"))

get_sales <- function(years    = NULL,          # file years to search; NULL = all
                      counties = NULL,          # NULL = all 7
                      cols     = c("emv_land", "emv_bldg", "emv_total", "tax_capac",
                                   "use_class1", "homestead", "year_built",
                                   "fin_sq_ft", "num_units"),   # values attached to each sale
                      sale_years = NULL,        # keep only sales in these calendar years
                      geometry = c("none", "polygon", "point")) {
  geometry <- match.arg(geometry)
  keys <- c("pin", "sale_date", "sale_value")
  p <- read_parcels(years, counties, cols = unique(c(keys, cols)), geometry = geometry,
                    filter = quote(!is.na(sale_date)))
  is_sf <- inherits(p, "sf")
  p$sale_date <- as.Date(format(p$sale_date, "%Y-%m-%d"))   # stored as date-time at midnight

  # drop rows with no pin, or only the county prefix
  no_pin <- is.na(p$pin) | grepl("^[0-9]{3}-?$", trimws(p$pin))
  if (any(no_pin)) message(sum(no_pin), " rows dropped: no pin")
  p <- p[!no_pin, , drop = FALSE]

  # drop sale dates later than the file's own year
  bad <- as.integer(format(p$sale_date, "%Y")) > p$year
  if (any(bad)) message(sum(bad), " rows dropped: sale date after the file's year (",
                        length(unique(paste(p$county[bad], p$pin[bad]))), " parcels)")
  p <- p[!bad, , drop = FALSE]

  # first file that lists each sale
  p <- p[order(p$county, p$pin, p$sale_date, p$year), , drop = FALSE]
  key <- paste(p$county, p$pin, p$sale_date)
  id <- match(key, unique(key))
  n_files <- tabulate(id)[id]
  first <- !duplicated(key)
  p$n_files <- n_files
  p <- p[first, , drop = FALSE]

  names(p)[names(p) == "year"] <- "file_year"
  p$sale_year <- as.integer(format(p$sale_date, "%Y"))
  p$value_lag_years <- p$file_year - p$sale_year
  if (!is.null(sale_years)) p <- p[p$sale_year %in% sale_years, , drop = FALSE]
  p$row_in_file <- NULL

  front <- c("county", "pin", "sale_date", "sale_year", "sale_value",
             "file_year", "value_lag_years", "n_files")
  p <- p[, c(front, setdiff(names(p), front)), drop = FALSE]
  rownames(p) <- NULL
  if (is_sf) p else dplyr::as_tibble(p)
}
