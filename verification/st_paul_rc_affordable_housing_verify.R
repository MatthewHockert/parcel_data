## Verify repointed parcel reads in st_paul_rc_affordable_housing (2026-11-07).
## Each distinct OLD read (file + arguments) is run once and compared once with
## its NEW read_parcels() call; the result is then recorded for every site/year
## that issues that identical old/new pair (column `site`). Line numbers are
## those of the read in the scripts BEFORE repointing.
## data/Archive is a symlink to Desktop/Personal Info/matthew_maps_saint_paul/Archive
## (the real old files); shp_plan_regional_parcels/ is a real folder in the project.
suppressPackageStartupMessages({ library(sf); library(dplyr); library(glue) })
source("/Users/matthewhockert/research/parcel_data/R/read_parcels.R")
source("/Users/matthewhockert/research/parcel_data/R/verify_read.R")

proj <- "/Users/matthewhockert/Desktop/Personal Info/st_paul_rc_affordable_housing"
setwd(proj)
out_csv <- "/Users/matthewhockert/research/parcel_data/verification/st_paul_rc_affordable_housing_results.csv"
res <- list()
## resumable: keep comparisons that already passed in an earlier run, redo the rest
prev <- if (file.exists(out_csv)) read.csv(out_csv, stringsAsFactors = FALSE) else NULL
done_ok <- if (is.null(prev)) character(0) else unique(prev$label[prev$ok %in% TRUE])
## failures already diagnosed (2024 gdb: project copy is a different download than the store's; owner-name fields differ) are kept, not re-read
## (Matt, 2026-11-08: 2024 reads keep owner names blank, as in this project's redacted
##  Dec-2025 gdb -> drop_owner_names = (yr == 2024); the earlier 2024 failures are re-run)
if (length(done_ok)) res[[1]] <- as_tibble(prev[prev$label %in% done_ok, ])
skip <- function(label) { if (label %in% c(done_ok, vapply(res, function(r) as.character(r$label[1]), ""))) { message(sprintf("%-28s (passed earlier run, kept)", label)); TRUE } else FALSE }
## old files may be iCloud placeholders (dataless) and GDAL does not always
## trigger the download; read every sidecar file once so it is materialized
## Matt approved (2026-11-08): if the original is an iCloud placeholder that
## will not download, the old read runs on the parcel_data/data/raw copy of the
## same file, used only when every component has the same byte size
## (resolve_old() in verify_read.R). Recorded per comparison in via_raw / note.
LAST_VIA <- FALSE
VIA_NOTE <- "old read via raw copy (same size)"
hydrate <- function(path) {
  p <- resolve_old(path)
  if (isTRUE(attr(p, "via_raw"))) { LAST_VIA <<- TRUE; return(as.character(p)) }
  fs <- if (grepl("[.]gdb$", path)) list.files(path, full.names = TRUE, recursive = TRUE)
        else list.files(dirname(path), pattern = paste0("^", sub("[.]shp$", "", basename(path)), "[.]"), full.names = TRUE)
  for (x in fs) { con <- file(x, "rb"); while (length(readBin(con, "raw", 2^24)) > 0) NULL; close(con) }
  invisible(path)
}
add <- function(r, sites, mode, note = "") {
  if (LAST_VIA) note <- paste(c(if (nzchar(note)) note, VIA_NOTE), collapse = "; ")
  r <- mutate(r, via_raw = LAST_VIA)
  LAST_VIA <<- FALSE
  for (s in sites) res[[length(res) + 1]] <<- mutate(r, site = s, mode = mode, note = note, .before = 1)
  write.csv(bind_rows(res), out_csv, row.names = FALSE)
  message(sprintf("%-28s ok=%s  (%d sites)", r$label, r$ok, length(sites)))
}
shp <- function(yr, cty) glue("data/Archive/shp_plan_regonal_parcels_{yr}/Parcels{yr}{cty}.shp")
gdb <- function(yr) glue("data/Archive/fgdb_plan_regonal_parcels_{yr}/plan_regonal_parcels_{yr}.gdb")
drop_g <- function(d) if (inherits(d, "sf")) st_drop_geometry(d) else d

## ---- 2021 SHAPEFILE reads (coordinator, 2026-11-08) ----------------------
## The store's 2021 partitions are rewritten (coordinator, 2026-11-08) so that
## as_shapefile = TRUE returns the 2021 shapefile exactly (geometry, row order,
## Shape_Leng / Shape_Area); verified in plain exact mode, no key or tolerances.
cmp21 <- function(old, new, label) compare_reads(old, new, label = label)
ICLOUD <- "skipped: iCloud placeholder"
ONLY21 <- Sys.getenv("ONLY2021") == "1"   # first pass: only the 2021 shapefile comparisons
skip_row <- function(label, sites) add(tibble(label = label, ok = NA), sites, "skipped", ICLOUD)

## ---- 1. full shapefile reads, 2005-2022 ------------------------------------
full_sites <- function(yr, cty) {
  s <- character(0)
  if (cty == "Ramsey") {
    if (yr == 2020) s <- c(s, "R/01:162", "R/04:201(p20 via loader)", "analysis.qmd:1449", "development_effects.qmd:138",
                           "shift_share.qmd:98", "shift_share.qmd:166", "shift_share.qmd:1144", "shift_share.qmd:1839",
                           paste0("parcel_rci.qmd:", c(275, 351, 430, 696, 941, 2025, 2177, 2635)))
    s <- c(s, "R/01:189", "R/03:47", "analysis.qmd:365")
    if (yr == 2022) s <- c(s, "R/03b:32")
    if (yr >= 2006) s <- c(s, "R/04:47")
    if (yr >= 2010 && yr <= 2017) s <- c(s, "shift_share.qmd:1186", "shift_share.qmd:1428")
    if (yr >= 2018) s <- c(s, "shift_share.qmd:1193", "shift_share.qmd:1435")
    if (yr >= 2015 && yr <= 2017) s <- c(s, "analysis.qmd:1496", "development_effects.qmd:255", "parcel_rci.qmd:396")
    if (yr >= 2018) s <- c(s, "analysis.qmd:1503", "development_effects.qmd:262", "parcel_rci.qmd:403")
  } else {
    s <- c("R/05:37", "analysis.qmd:366")
  }
  s
}
full_order <- rbind(data.frame(cty = c("Ramsey", "Hennepin"), yr = 2021),   # 2021 first
                    expand.grid(yr = 2005:2022, cty = c("Ramsey", "Hennepin"), stringsAsFactors = FALSE)[, c("cty", "yr")])
full_order <- full_order[!duplicated(full_order), ]
if (ONLY21) full_order <- full_order[full_order$yr == 2021, ]
for (i in seq_len(nrow(full_order))) {
  cty <- full_order$cty[i]; yr <- full_order$yr[i]
  if (skip(glue("{yr} {cty} shp full"))) next
  old <- st_read(hydrate(shp(yr, cty)), quiet = TRUE)
  if (yr == 2021) {
    new <- read_parcels(years = yr, counties = cty, names = "original", as_shapefile = TRUE)
    add(cmp21(old, new, glue("{yr} {cty} shp full")), full_sites(yr, cty), "exact(as_shapefile 2021)")
    rm(old, new); gc(verbose = FALSE); next
  }
  new <- read_parcels(years = yr, counties = cty, names = "original")
  add(compare_reads(old, new, label = glue("{yr} {cty} shp full")), full_sites(yr, cty), "exact")
  rm(old, new); gc(verbose = FALSE)
}

if (!ONLY21) {
## ---- 2. full gdb polygon layers, 2023-2024 ---------------------------------
for (cty in c("Ramsey", "Hennepin")) for (yr in 2023:2024) {
  if (skip(glue("{yr} {cty} gdb full"))) next
  old <- st_read(hydrate(gdb(yr)), layer = glue("Parcels{yr}{cty}"), quiet = TRUE)
  new <- read_parcels(years = yr, counties = cty, names = "original", drop_owner_names = (yr == 2024))
  sites <- if (cty == "Ramsey") c("R/01:193", "analysis.qmd:371", "shift_share.qmd:1201", "shift_share.qmd:1443") else "analysis.qmd:374"
  add(compare_reads(old, new, label = glue("{yr} {cty} gdb full")), sites, "exact")
  rm(old, new); gc(verbose = FALSE)
}

## ---- 3. published Points layers, 2023-2024 -> metrogis points --------------
for (cty in c("Ramsey", "Hennepin")) for (yr in 2023:2024) {
  lyr <- glue("Parcels{yr}{cty}Points")
  if (skip(glue("{yr} {cty} Points"))) next
  g <- hydrate(gdb(yr))
  stopifnot(lyr %in% st_layers(g)$name)   # R/05's polygon-layer fallback never ran
  old <- st_read(g, layer = lyr, quiet = TRUE)
  new <- read_parcels(years = yr, counties = cty, names = "original", geometry = "point", point_method = "metrogis",
                      drop_owner_names = (yr == 2024))
  polys <- read_parcels(yr, cty, cols = "PIN", names = "original", geometry = "polygon")
  # 2023/2024 gdb polygons hold true arcs that GEOS (st_make_valid in
  # compare_point_reads) rejects; linearize the reference polygons only
  st_geometry(polys) <- parcel_linearize(polys)
  sites <- if (cty == "Ramsey") c("R/03:53", "R/03b:36", "R/04:51", "analysis.qmd:1510", "development_effects.qmd:269", "parcel_rci.qmd:411") else "R/05:45"
  add(compare_point_reads(old, new, polys, label = glue("{yr} {cty} Points")), sites, "points")
  rm(old, new, polys); gc(verbose = FALSE)
}

## ---- 4. 2025 release (shp_plan_regional_parcels/) --------------------------
for (cty in c("Ramsey", "Hennepin")) {
  if (skip(glue("2025 {cty} shp full"))) next
  old <- st_read(hydrate(glue("shp_plan_regional_parcels/Parcels{cty}.shp")), quiet = TRUE)
  new <- read_parcels(years = 2025, counties = cty, names = "original")
  sites <- if (cty == "Ramsey") c("R/03:56", "R/03b:38", "R/04:53", "analysis.qmd:1518", "development_effects.qmd:277",
                                  "shift_share.qmd:1208", "shift_share.qmd:1450", "parcel_rci.qmd:418") else "R/05:50 (2025 branch; loop is 2005:2024)"
  add(compare_reads(old, new, label = glue("2025 {cty} shp full")), sites, "exact")
  rm(old, new); gc(verbose = FALSE)
}

}  # end !ONLY21 (sections 2-4)

## ---- 5. SQL column-subset reads --------------------------------------------
src_of <- function(yr, cty) if (yr <= 2022) shp(yr, cty) else gdb(yr)
cc_of  <- function(yr) if (yr <= 2017) "CITY" else "CTU_NAME"
uc_of  <- function(yr) if (yr <= 2017) "USE1_DESC" else "USECLASS1"
sql_cmp <- function(yr, cty, sel, new_fun, label, sites) {
  if (skip(label)) return(invisible())
  old <- drop_g(st_read(hydrate(src_of(yr, cty)), query = sprintf('SELECT %s FROM "Parcels%d%s"', sel, yr, cty), quiet = TRUE))
  new <- drop_g(new_fun(yr, cty))
  if (yr == 2021) return(add(cmp21(old, new, label), sites, "exact(as_shapefile 2021)", note = paste("query: SELECT", sel)))
  add(compare_reads(old, new, label = label), sites, "exact", note = paste("query: SELECT", sel))
}
for (yr in if (ONLY21) 2021 else c(2021, setdiff(2016:2024, 2021))) for (cty in c("Ramsey", "Hennepin")) {
  cc <- cc_of(yr); uc <- uc_of(yr)
  # R/06:56
  sql_cmp(yr, cty, glue("{cc} AS city_raw, {uc} AS useclass, EMV_LAND, EMV_BLDG, EMV_TOTAL, TAX_CAPAC, TOTAL_TAX, NUM_UNITS"),
          function(yr, county) read_parcels(years = yr, counties = county, names = "original", geometry = "none", as_shapefile = (yr == 2021),
                    cols = c(cc, uc, "EMV_LAND", "EMV_BLDG", "EMV_TOTAL", "TAX_CAPAC", "TOTAL_TAX", "NUM_UNITS")) %>%
            dplyr::select(city_raw = all_of(cc), useclass = all_of(uc), EMV_LAND, EMV_BLDG, EMV_TOTAL, TAX_CAPAC, TOTAL_TAX, NUM_UNITS),
          glue("{yr} {cty} sql06"), "R/06:56")
  # R/12:33
  sql_cmp(yr, cty, glue("PIN, {cc} AS city_raw, {uc} AS useclass, EMV_TOTAL, EMV_BLDG"),
          function(yr, county) read_parcels(years = yr, counties = county, names = "original", geometry = "none", as_shapefile = (yr == 2021),
                    cols = c("PIN", cc, uc, "EMV_TOTAL", "EMV_BLDG")) %>%
            dplyr::select(PIN, city_raw = all_of(cc), useclass = all_of(uc), EMV_TOTAL, EMV_BLDG),
          glue("{yr} {cty} sql12"), "R/12:33")
  # R/08:26 (Ramsey 2017/2023/2024; Hennepin 2017, 2019-2023)
  if ((cty == "Ramsey" && yr %in% c(2017, 2023, 2024)) || (cty == "Hennepin" && yr %in% c(2017, 2019:2023)))
    sql_cmp(yr, cty, glue("{cc} AS city_raw, {uc} AS useclass, EMV_TOTAL, TAX_CAPAC, TOTAL_TAX"),
            function(yr, county) read_parcels(years = yr, counties = county, names = "original", geometry = "none", as_shapefile = (yr == 2021),
                      cols = c(cc, uc, "EMV_TOTAL", "TAX_CAPAC", "TOTAL_TAX")) %>%
              dplyr::select(city_raw = all_of(cc), useclass = all_of(uc), EMV_TOTAL, TAX_CAPAC, TOTAL_TAX),
            glue("{yr} {cty} sql08"), "R/08:26")
  if (cty == "Ramsey") {
    # R/18:25
    sql_cmp(yr, cty, glue("PIN, {cc} AS c"),
            function(yr, county) read_parcels(years=yr,counties="Ramsey",names="original",geometry="none",cols=c("PIN",cc),as_shapefile=(yr==2021)) %>% dplyr::select(PIN, c=all_of(cc)),
            glue("{yr} Ramsey sql18"), "R/18:25")
    # R/21:30
    sql_cmp(yr, cty, glue("PIN, {cc} AS c, EMV_TOTAL"),
            function(yr, county) read_parcels(years=yr, counties="Ramsey", names="original", geometry="none", cols=c("PIN", cc, "EMV_TOTAL"), as_shapefile=(yr==2021)) %>%
              dplyr::select(PIN, c=all_of(cc), EMV_TOTAL),
            glue("{yr} Ramsey sql21"), "R/21:30")
  }
  gc(verbose = FALSE)
}
if (!ONLY21) {
# R/19:18 and R/28:27 (identical query), R/22:23 -- 2024 Ramsey gdb
sql_cmp(2024, "Ramsey", "CTU_NAME AS c, USECLASS1 AS u, EMV_TOTAL, TAX_CAPAC",
        function(yr, county) read_parcels(years=2024, counties="Ramsey", names="original", geometry="none",
                  cols=c("CTU_NAME", "USECLASS1", "EMV_TOTAL", "TAX_CAPAC")) %>% dplyr::select(c=CTU_NAME, u=USECLASS1, EMV_TOTAL, TAX_CAPAC),
        "2024 Ramsey sql19/28", c("R/19:18", "R/28:27"))
sql_cmp(2024, "Ramsey", "PIN, CTU_NAME AS c, USECLASS1 AS u, EMV_TOTAL, TAX_CAPAC",
        function(yr, county) read_parcels(years=2024, counties="Ramsey", names="original", geometry="none",
                  cols=c("PIN", "CTU_NAME", "USECLASS1", "EMV_TOTAL", "TAX_CAPAC")) %>% dplyr::select(PIN, c=CTU_NAME, u=USECLASS1, EMV_TOTAL, TAX_CAPAC),
        "2024 Ramsey sql22", "R/22:23")
# R/20:31 -- 2022 shapefiles, SQL subset WITH geometry, then st_transform(26915)
for (cty in c("Ramsey", "Hennepin")) {
  if (skip(glue("2022 {cty} sql20 +geom"))) next
  old <- st_read(hydrate(shp(2022, cty)), query = sprintf('SELECT PIN, CTU_NAME FROM "Parcels2022%s"', cty), quiet = TRUE) %>% st_transform(26915)
  new <- read_parcels(years=2022, counties=cty, names="original", cols=c("PIN", "CTU_NAME")) %>% dplyr::select(PIN, CTU_NAME) %>% st_transform(26915)
  add(compare_reads(old, new, label = glue("2022 {cty} sql20 +geom")), "R/20:31", "exact", "query: SELECT PIN, CTU_NAME (geometry kept)")
  rm(old, new); gc(verbose = FALSE)
}

}  # end !ONLY21 (2024 SQL, R/20)

out <- bind_rows(res)
write.csv(out, out_csv, row.names = FALSE)
cat(sprintf("\n%d site-rows, %d distinct comparisons; ok: %d, failed: %d\n",
            nrow(out), n_distinct(out$label), sum(out$ok %in% TRUE), sum(!out$ok %in% TRUE)))
print(as.data.frame(distinct(filter(out, !ok %in% TRUE), label, .keep_all = TRUE)))
