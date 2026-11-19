## paths.R: where the lookup tables and the downloaded parcel files live.
##
## Lookup tables (crosswalks, known gaps, class rates, checksums) ship with the
## package in inst/extdata. When the R files are sourced from a clone instead of
## loaded with library(parceldata), they are read from <PARCEL_HOME>/inst/extdata.
##
## Parcel files (what download_parcels() saves and read_parcels() reads) go to the
## first of:
##   1. the folder set with parcel_data_dir("F:/parcels") in this session
##   2. <PARCEL_HOME>/data, if the PARCEL_HOME environment variable is set
##   3. R's standard per-user data folder, tools::R_user_dir("parceldata", "data"),
##      which works the same on Windows, Mac and Linux (Python uses the same folder)

.parcel_env <- new.env(parent = emptyenv())

# TRUE when loaded as the installed package, FALSE when sourced from a clone
.parcel_in_pkg <- function() isNamespace(topenv(environment(.parcel_in_pkg)))

.parcel_table <- function(name) {
  dir <- if (.parcel_in_pkg()) system.file("extdata", package = "parceldata") else
    file.path(Sys.getenv("PARCEL_HOME"), "inst", "extdata")
  f <- file.path(dir, name)
  if (!file.exists(f)) stop("lookup table not found: ", f)
  f
}

parcel_data_dir <- function(dir = NULL) {
  if (!is.null(dir)) {
    .parcel_env$dir <- normalizePath(dir, winslash = "/", mustWork = FALSE)
    return(invisible(.parcel_env$dir))
  }
  if (!is.null(.parcel_env$dir)) return(.parcel_env$dir)
  home <- Sys.getenv("PARCEL_HOME")
  if (nzchar(home)) return(file.path(home, "data"))
  tools::R_user_dir("parceldata", "data")
}

## Store folder for a layer: <data dir>/standardized_polygons or standardized_points.
## The polygon store was first named "standardized", and the Zenodo zips still
## unzip to that name, so year folders found under the old name are moved across
## here. Called by read_parcels() and download_parcels().
.parcel_store <- function(layer = c("polygons", "points"), quiet = FALSE) {
  layer <- match.arg(layer)
  data_dir <- parcel_data_dir()
  if (layer == "points") return(file.path(data_dir, "standardized_points"))
  old <- file.path(data_dir, "standardized")
  new <- file.path(data_dir, "standardized_polygons")
  if (!dir.exists(old)) return(new)

  if (!dir.exists(new)) {
    moved <- file.rename(old, new)               # whole folder in one step
  } else {
    yrs   <- list.files(old, pattern = "^year=")
    yrs   <- yrs[!dir.exists(file.path(new, yrs))]   # a year already in the new folder is left alone
    moved <- length(yrs) > 0 && all(file.rename(file.path(old, yrs), file.path(new, yrs)))
    if (length(setdiff(list.files(old, all.files = TRUE, no.. = TRUE), ".DS_Store")) == 0)
      unlink(old, recursive = TRUE)
  }
  if (moved && !quiet) message("polygon files moved from ", old, " to ", new)
  if (dir.exists(old)) warning(old, " still holds files that were not moved to ", new,
                               "; move or delete them by hand", call. = FALSE)
  if (dir.exists(new)) new else old              # rename failed (e.g. files open): keep reading the old folder
}
