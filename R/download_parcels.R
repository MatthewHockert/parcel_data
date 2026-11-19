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
    target <- file.path(.parcel_store(ly), sprintf("year=%d", yr))
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
    # PROGRESS BAR: drawn inside .download_with_bar() (below), 0% to 100%.
    # It only appears in a version installed after this was added, so
    # reinstall the package if no bar shows.
    .download_with_bar(url, zip_path)
    if (unname(tools::md5sum(zip_path)) != expected) {
      unlink(zip_path); stop(zip_name, ": checksum does not match, download again")
    }
    if (overwrite) unlink(target, recursive = TRUE)
    utils::unzip(zip_path, exdir = data_dir)
    .parcel_store(ly, quiet = TRUE)   # polygon zips unzip to standardized/; this moves the year into standardized_polygons/
    unlink(zip_path)
  }
  invisible(data_dir)
}

## Copy src (an http or file:// URL) to dest in 1 MB pieces and draw the bar.
## PROGRESS BAR: txtProgressBar(style = 3) prints |=====     |  45%, and
## setTxtProgressBar() moves it after each piece. The percent is bytes so far
## over the file size the server reports; with no size reported there is no bar.
.download_with_bar <- function(src, dest, piece = 2^20) {
  total <- .remote_size(src)
  con <- url(src, "rb"); on.exit(close(con), add = TRUE)
  out <- file(dest, "wb"); on.exit(close(out), add = TRUE)
  bar <- if (!is.na(total)) utils::txtProgressBar(min = 0, max = 100, style = 3)
  done <- 0
  repeat {
    buf <- readBin(con, "raw", piece)
    if (length(buf) == 0) break
    writeBin(buf, out)
    done <- done + length(buf)
    if (!is.null(bar)) utils::setTxtProgressBar(bar, 100 * done / total)
  }
  if (!is.null(bar)) close(bar)
  invisible(dest)
}

## File size in bytes: from disk for file:// URLs, else the last Content-Length
## header (the last one because Zenodo redirects first). NA if unknown.
.remote_size <- function(src) {
  if (startsWith(src, "file://")) return(file.size(sub("^file://", "", src)))
  h <- tryCatch(curlGetHeaders(src), error = function(e) character())
  len <- grep("^content-length:", h, ignore.case = TRUE, value = TRUE)
  if (length(len) == 0) return(NA_real_)
  as.numeric(trimws(sub("^[^:]*:", "", len[length(len)])))
}
