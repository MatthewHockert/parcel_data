## download_parcels(): fetch store years from the Zenodo deposit into parcel_data_dir().
##   download_parcels(2014:2016)                     # polygons
##   download_parcels(2021, layer = "points")         # points + that year's polygons
## Zips are one per year and layer (all 7 counties); each is checked against
## inst/extdata/zenodo_md5.txt, unzipped into parcel_data_dir() (see R/paths.R) and deleted.
## Years already on disk are skipped unless overwrite = TRUE.
## Each zip is fetched as `connections` pieces at once (see .download_parallel()).

ZENODO_RECORD <- "24116899"   # DOI 10.5281/zenodo.24116899

download_parcels <- function(years,
                             layer     = c("polygons", "points"),
                             base_url  = sprintf("https://zenodo.org/records/%s/files", ZENODO_RECORD),
                             overwrite = FALSE,
                             connections = 8) {   # pieces of each zip fetched at once; 1 = one plain download
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
    # PROGRESS BAR: drawn inside .download_parallel() (below), 0% to 100%.
    # It only appears in a version installed after this was added, so
    # reinstall the package if no bar shows.
    .download_parallel(url, zip_path, connections)
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

## Fetch src as `connections` byte ranges at once, then join them into dest.
## Zenodo limits the speed of each connection, not of each user, so 8 ranges
## arrive about 6 times faster than one download. The md5 check in
## download_parcels() confirms the joined file is the published one.
## PROGRESS BAR: txtProgressBar() here; the percent is the bytes on disk across
## all pieces over the file size, refreshed every half second.
## Falls back to .download_with_bar() (one connection) when the size is unknown,
## the file is small, the server does not serve ranges, or a piece keeps failing.
.download_parallel <- function(src, dest, connections = 8) {
  total <- .remote_size(src)
  if (connections < 2 || is.na(total) || total < connections * 2^20 || !.serves_ranges(src))
    return(.download_with_bar(src, dest))

  edges <- floor(seq(0, total, length.out = connections + 1))   # byte offsets that cut the file into equal pieces
  from  <- edges[-length(edges)]
  to    <- edges[-1] - 1
  want  <- to - from + 1
  parts <- sprintf("%s.part%02d", dest, seq_along(from))
  on.exit(unlink(parts), add = TRUE)
  got <- function() { s <- file.size(parts); s[is.na(s)] <- 0; s }

  bar <- utils::txtProgressBar(min = 0, max = 100, style = 3)
  for (attempt in 1:3) {                         # a piece that came back short is fetched again, up to 3 rounds
    todo <- which(got() != want)
    if (length(todo) == 0) break
    unlink(parts[todo])
    # multiplex = FALSE: one connection per piece (HTTP/2 would share a single one)
    pool <- curl::new_pool(total_con = connections, host_con = connections, multiplex = FALSE)
    for (i in todo) {
      h <- curl::new_handle(url = src, range = sprintf("%.0f-%.0f", from[i], to[i]), failonerror = TRUE,
                            low_speed_limit = 1000, low_speed_time = 60)   # give up on a piece stalled for 60 s
      curl::multi_add(h, data = parts[i], pool = pool, fail = function(msg) NULL)
    }
    repeat {
      pending <- curl::multi_run(timeout = 0.5, pool = pool)$pending
      utils::setTxtProgressBar(bar, 100 * sum(got()) / total)
      if (pending == 0) break
    }
  }
  close(bar)
  if (any(got() != want)) {
    message("some pieces did not arrive; downloading again on one connection")
    return(.download_with_bar(src, dest))
  }
  unlink(dest)
  for (p in parts) { file.append(dest, p); unlink(p) }   # join in byte order
  invisible(dest)
}

## TRUE if the server returns just the first byte when asked for bytes 0-0
.serves_ranges <- function(src) {
  r <- tryCatch(curl::curl_fetch_memory(src, handle = curl::new_handle(range = "0-0")), error = function(e) NULL)
  !is.null(r) && length(r$content) == 1
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
