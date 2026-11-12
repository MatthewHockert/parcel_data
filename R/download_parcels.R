## download_parcels(): fetch store years from the Zenodo deposit into parcel_data_dir().
##   download_parcels(2014:2016)                     # polygons
##   download_parcels(2021, layer = "points")         # points + that year's polygons
## Zips are one per year and layer (all 7 counties); each is checked against
## inst/extdata/zenodo_md5.txt, unzipped into parcel_data_dir() (see R/paths.R) and deleted.
## Years already on disk are skipped unless overwrite = TRUE.

ZENODO_RECORD <- "24116899"   # DOI 10.5281/zenodo.24116899

download_parcels <- function(years,
                             layer     = c("polygons", "points"),
                             base_url  = sprintf("https://zenodo.org/records/%s/files", ZENODO_RECORD),
                             overwrite = FALSE) {
  layer <- match.arg(layer)
  data_dir <- parcel_data_dir()
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
  message("parcel files are saved in ", data_dir)

  md5 <- utils::read.table(.parcel_table("zenodo_md5.txt"),
                           col.names = c("md5", "file"), stringsAsFactors = FALSE)

  # standardized Points reads place each point on its polygon, so points need polygons too
  layers <- if (layer == "points") c("polygons", "points") else "polygons"
  old_timeout <- options(timeout = max(3600, getOption("timeout")))   # zips are 100-600 MB
  on.exit(options(old_timeout))

  for (yr in years) for (ly in layers) {
    store  <- if (ly == "points") "standardized_points" else "standardized"
    target <- file.path(data_dir, store, sprintf("year=%d", yr))
    if (dir.exists(target) && !overwrite) {
      message(sprintf("%d %s: already on disk, skipped", yr, ly)); next
    }
    zip_name <- sprintf("parcels_%s_%d.zip", ly, yr)
    expected <- md5$md5[md5$file == zip_name]
    if (length(expected) != 1) stop(zip_name, " is not in the deposit (years are 2005-2025)")

    zip_path <- file.path(tempdir(), zip_name)
    message(sprintf("%d %s: downloading", yr, ly))
    url <- file.path(base_url, zip_name)
    if (startsWith(base_url, "http")) url <- paste0(url, "?download=1")
    utils::download.file(url, zip_path,
                         mode = "wb", quiet = TRUE)
    if (unname(tools::md5sum(zip_path)) != expected) {
      unlink(zip_path); stop(zip_name, ": checksum does not match, download again")
    }
    if (overwrite) unlink(target, recursive = TRUE)
    utils::unzip(zip_path, exdir = data_dir)
    unlink(zip_path)
  }
  invisible(data_dir)
}
