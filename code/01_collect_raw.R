## 01_collect_raw.R
##
## Collect the MetroGIS regional parcel archives (7 metro counties, files
## 2005-2024) from the project folders they were scattered across into
## data/raw/<year>/ here.
##
## Source data: MetroGIS Regional Parcel Dataset, annual releases, originally
## downloaded from the Minnesota Geospatial Commons as
## shp_plan_regonal_parcels_<year>.zip (2023: fgdb_plan_regonal_parcels_2023).
## Those archive URLs return 404 as of Nov 2026; Met Council GIS holds the
## archive if a third party needs to regenerate.
##
## Decisions (Matt, 2026-11-07):
##   - Centralize, then delete elsewhere (2026-11-07): files are COPIED here
##     first; scripts in other projects are repointed to read from this
##     dataset; each parcel read is verified identical (old vs new); only then
##     are the originals and all duplicate copies deleted. Archive and
##     worktree copies of scripts are not repointed. The manifest records
##     old -> new for every file.
##   - Polygons only. Parcel-point files are left in place; points are
##     derived from polygons in the standardized dataset.
##   - When a file exists in several folders, ONE copy is moved (a local copy
##     preferred over an iCloud placeholder); the other copies are left in
##     place and listed in the manifest. Deleting them is a separate decision.
##
## Step 1 (this chunk): DRY RUN. Build the manifest, move nothing.
## Step 2: copy the chosen files (originals untouched).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})

PD_ROOT  <- "/Users/matthewhockert/research/parcel_data"
RAW_DIR  <- file.path(PD_ROOT, "data", "raw")
SEARCH_ROOTS <- c("/Users/matthewhockert/Desktop",
                  "/Users/matthewhockert/Downloads",
                  "/Users/matthewhockert/research")

# Find every polygon component ----
# File names follow Parcels<year><County>.<ext>; points are Parcels<year><County>Points.*
# and are excluded. All7 exists only as a points layer, so it drops out too.
counties <- c("Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington")
name_re  <- sprintf("^Parcels(20[0-9]{2})(%s)\\.(shp|shx|dbf|prj|cpg|sbn|sbx|shp\\.xml)$",
                    paste(counties, collapse = "|"))

all_files <- unlist(lapply(SEARCH_ROOTS, list.files, pattern = "^Parcels20.*",
                           recursive = TRUE, full.names = TRUE))
# brownfield_stpaul/data/raw/parcels holds size-verified local Ramsey copies
# (made 2026-11-05); included as a source so evicted Ramsey files need no
# iCloud download. That project is repointed and verified like the others.
all_files <- all_files[!grepl("/Library/|/\\.Trash/|/parcel_data/data/raw/", all_files)]

comp <- tibble(path = all_files, file = basename(all_files)) %>%
  filter(grepl(name_re, file)) %>%
  mutate(year   = as.integer(sub(name_re, "\\1", file)),
         county = sub(name_re, "\\2", file),
         ext    = sub(name_re, "\\3", file))

# iCloud state: macOS marks evicted files with the "dataless" flag
# (st_flags bit 0x40000000). `stat -f %f` prints st_flags in decimal.
flags <- as.numeric(system2("stat", c("-f", "%f", shQuote(comp$path)), stdout = TRUE))
comp <- comp %>%
  mutate(bytes    = file.size(path),
         dataless = bitwAnd(flags %/% 2^30, 1L) == 1L)   # bit 30

cat("polygon component files found:", nrow(comp),
    " distinct year-county-ext:", nrow(distinct(comp, year, county, ext)), "\n")

# 2023 is a 7-county geodatabase, not shapefiles; handled as its own row.
gdb_2023 <- unlist(lapply(SEARCH_ROOTS, function(r)
  list.files(r, pattern = "^plan_regonal_parcels_2023\\.gdb$", recursive = TRUE,
             include.dirs = TRUE, full.names = TRUE)))
gdb_2023 <- gdb_2023[!grepl("/Library/|/\\.Trash/|/brownfield_stpaul/data/raw/", gdb_2023)]
cat("2023 geodatabase copies:", length(gdb_2023), "\n"); print(gdb_2023)

# Choose one copy per component ----
# Sizes must agree across copies (same release); flag any that don't.
# Preference: local over dataless, then shortest path (arbitrary tie-break).
manifest <- comp %>%
  group_by(year, county, ext) %>%
  mutate(n_copies     = n(),
         sizes_agree  = n_distinct(bytes) == 1) %>%
  arrange(dataless, nchar(path), .by_group = TRUE) %>%
  mutate(chosen = row_number() == 1) %>%
  ungroup() %>%
  mutate(dest = ifelse(chosen, file.path(RAW_DIR, year, file), NA_character_),
         action = case_when(chosen & !dataless ~ "copy",
                            chosen &  dataless ~ "download_then_copy",
                            TRUE               ~ "duplicate"))

# Checks ----
# 1. every year x county has the four required components
required <- c("shp", "shx", "dbf", "prj")
coverage <- manifest %>% filter(chosen, ext %in% required) %>%
  count(year, county, name = "n_required") %>%
  complete(year = 2005:2024, county = counties, fill = list(n_required = 0L))
cat("year-county combos missing a required component:\n")
print(coverage %>% filter(n_required < 4, year != 2023), n = Inf)

# 2. copies that disagree in size (would mean different releases)
cat("components whose copies differ in size:", sum(!distinct(manifest, year, county, ext, sizes_agree)$sizes_agree), "\n")

# 3. what will happen, in GB
manifest %>%
  group_by(action) %>%
  summarise(files = n(), gb = round(sum(bytes) / 1e9, 1), .groups = "drop") %>%
  print()

# 4. which project folders lose files (so their scripts can be repointed)
manifest %>% filter(chosen) %>%
  mutate(project = sub("^/Users/matthewhockert/", "", sub("/shp_plan_regonal_parcels_.*$", "", path))) %>%
  group_by(project) %>% summarise(files = n(), gb = round(sum(bytes) / 1e9, 1), .groups = "drop") %>%
  arrange(desc(gb)) %>% print(n = Inf)

write_csv(manifest, file.path(PD_ROOT, "docs", "move_manifest.csv"))
cat("wrote docs/move_manifest.csv\n")

# Copy ----
# Year by year, so a disk-space pause loses at most one year of progress.
# Idempotent: a destination that already exists with the right size is skipped.
free_gb <- function() {
  # free bytes on the volume holding RAW_DIR, from `df -k` (1K blocks)
  out <- system2("df", c("-k", shQuote(RAW_DIR)), stdout = TRUE)
  as.numeric(strsplit(trimws(out[2]), "\\s+")[[1]][4]) / 1e6
}
# DECISION: pause only below 5 GB. `df` reports space that is free right now;
# macOS frees its purgeable space (iCloud local copies, caches) only when a
# write needs it, so a higher threshold stalls forever (it did at 15 GB:
# df showed 13.5 GB while ~250 GB was purgeable).
MIN_FREE_GB <- 5

wait_local <- function(path, timeout_min = 60) {
  # request the iCloud download and poll until the dataless flag clears
  system2("brctl", c("download", shQuote(path)), stdout = FALSE, stderr = FALSE)
  t0 <- Sys.time()
  repeat {
    fl <- as.numeric(system2("stat", c("-f", "%f", shQuote(path)), stdout = TRUE))
    if (bitwAnd(fl %/% 2^30, 1L) == 0L) return(TRUE)
    if (difftime(Sys.time(), t0, units = "mins") > timeout_min) return(FALSE)
    Sys.sleep(15)
  }
}

to_copy <- manifest %>% filter(chosen) %>% arrange(year, county, ext)
copy_log <- vector("list", nrow(to_copy))

for (yr in sort(unique(to_copy$year))) {
  while (free_gb() < MIN_FREE_GB) {
    cat(format(Sys.time(), "%H:%M"), "free", round(free_gb(), 1), "GB <", MIN_FREE_GB, "- waiting\n")
    Sys.sleep(120)
  }
  dir.create(file.path(RAW_DIR, yr), recursive = TRUE, showWarnings = FALSE)
  idx <- which(to_copy$year == yr)
  for (i in idx) {
    src <- to_copy$path[i]; dst <- to_copy$dest[i]
    status <- "skipped_exists"
    if (!(file.exists(dst) && file.size(dst) == to_copy$bytes[i])) {
      # DECISION (2026-11-07): never block on iCloud. A file still evicted
      # right now gets a non-blocking download request and is marked
      # deferred; a later pass (rerun this script) picks it up once local.
      # Blocking cost ~1 hour on one 2008 file in the first run.
      fl_now <- as.numeric(system2("stat", c("-f", "%f", shQuote(src)), stdout = TRUE))
      if (bitwAnd(fl_now %/% 2^30, 1L) == 1L) {
        system2("brctl", c("download", shQuote(src)), stdout = FALSE, stderr = FALSE, wait = FALSE)
        status <- "deferred_icloud"
      } else {
        status <- if (file.copy(src, dst, overwrite = TRUE, copy.date = TRUE)) "copied" else "copy_failed"
      }
    }
    copy_log[[i]] <- tibble(year = yr, file = to_copy$file[i], status = status,
                            size_ok = file.exists(dst) && file.size(dst) == to_copy$bytes[i])
  }
  cat(format(Sys.time(), "%H:%M"), yr, "done; free", round(free_gb(), 1), "GB\n")
}

## 2023 geodatabase ----
# One copy of the 7-county gdb; prefer a copy outside iCloud-synced folders.
gdb_src  <- gdb_2023[grepl("^/Users/matthewhockert/research/", gdb_2023)][1]
gdb_dest <- file.path(RAW_DIR, "2023", "plan_regonal_parcels_2023.gdb")
if (!dir.exists(gdb_dest)) {
  dir.create(file.path(RAW_DIR, "2023"), showWarnings = FALSE)
  system2("cp", c("-R", shQuote(gdb_src), shQuote(dirname(gdb_dest))))
}
cat("2023 gdb copied from", gdb_src, " size (GB):",
    round(sum(file.size(list.files(gdb_dest, full.names = TRUE))) / 1e9, 2), "\n")

## Checks ----
copy_log <- bind_rows(copy_log)
print(count(copy_log, status, size_ok))
copy_log %>% filter(!size_ok) %>% print(n = Inf)
write_csv(copy_log, file.path(PD_ROOT, "docs", "copy_log.csv"))
