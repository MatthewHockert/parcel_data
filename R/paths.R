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
