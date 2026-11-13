# Repointing scripts to the central parcel store

Brief for repointing every script that reads MetroGIS regional parcel files
(`shp_plan_regonal_parcels_*`, `fgdb_plan_regonal_parcels_*`,
`shp_plan_regional_parcels/Parcels{County}.shp`) to the central store at
`<PARCEL_HOME>`, and verifying each read returns
the same data. Decisions are Matt's (2026-11-07). Deletion of the old files is
a later, separate step that Matt confirms; never delete anything while repointing.

## The store and the helper

```r
source("<PARCEL_HOME>/R/read_parcels.R")
read_parcels(years, counties, cols = NULL, filter = NULL, bbox = NULL,
             geometry = c("polygon", "point", "none"),
             point_method = c("surface", "centroid", "metrogis"),
             names = c("standardized", "original"))
```

- Years 2005-2025, all 7 counties. Year = the release's FILE year
  (`Parcels2016Ramsey.shp` is `years = 2016`). The 2025 release is the
  `shp_plan_regional_parcels/Parcels{County}.shp` set (files dated Jan 2026).
- `names = "original"` (one year, one county) returns exactly what `st_read()`
  of that file returns: same column names and order, types, values, row order,
  and geometry. Use this for repointing so downstream code does not change.
- 2023 and 2024 are stored from the geodatabases. For 2023 the original view
  matches the gdb read exactly. For 2024 it also matches the gdb read exactly;
  scripts that read the 2024 SHAPEFILES are verified in "shapefile mode" below.
- Points: published `*Points.shp` / gdb `Parcels{yr}{County}Points` layers are
  NOT stored. Use `geometry = "point", point_method = "metrogis"` (one point per
  PIN, centroid, nudged inside the parcel when the centroid falls outside).
- `cols` takes original names when `names = "original"`.

## How to repoint a read

Replace the `st_read(...)` (or path construction + `st_read`) with an
equivalent `read_parcels(...)` call, keeping the object name and everything
downstream unchanged. Add the `source(...)` line once near the top of the
script (after its library calls). Examples:

```r
# before
r <- st_read(glue("data/Archive/shp_plan_regonal_parcels_{yr}/Parcels{yr}Ramsey.shp"), quiet = TRUE)
# after
r <- read_parcels(years = yr, counties = "Ramsey", names = "original")

# before: SQL with aliases, no geometry needed downstream
d <- st_read(gdb, query = 'SELECT CTU_NAME AS c, USECLASS1 AS u, EMV_TOTAL FROM "Parcels2024Ramsey"', quiet = TRUE)
# after
d <- read_parcels(2024, "Ramsey", cols = c("CTU_NAME", "USECLASS1", "EMV_TOTAL"),
                  names = "original", geometry = "none") %>%
  dplyr::rename(c = CTU_NAME, u = USECLASS1)
#   (only drop geometry if the original query returned none / it is unused;
#    check what st_read returned)

# before: published points
p <- st_read(".../Parcels2014RamseyPoints.shp")
# after
p <- read_parcels(2014, "Ramsey", names = "original", geometry = "point", point_method = "metrogis")
```

Leave a one-line comment at each changed read:
`# parcel_data store (repointed 2026-11-07; was: <old path>)`.

Keep edits minimal: change only the read lines (and the one `source` line).
Do not reformat, restyle, or touch unrelated code. Do not commit, stash,
switch branches, or run `git` commands that change state. Many of these repos
have uncommitted work in progress.

Prose that merely mentions old paths (e.g. tables in `paper_proposal.qmd`) is
not code: do not edit it; list it in your report.

## How to verify (required for every changed read)

For each project, write ONE verification script at
`<PARCEL_HOME>/verification/<project>_verify.R`
that, for every changed read site and every year/county that site reads,
runs the OLD read exactly as the script did before (old path, same
arguments) and the NEW `read_parcels()` call, then compares:

```r
source("<PARCEL_HOME>/R/read_parcels.R")
source("<PARCEL_HOME>/R/verify_read.R")
compare_reads(old, new, label = "<script>:<line> <year> <county>")          # exact (default)
compare_reads(old, new, label, key = "PIN", geom_tol = 1, shp_losses = TRUE) # old read = 2024 SHAPEFILE
compare_point_reads(old, new, polygons, label = ...)                          # old read = published Points
#   polygons <- read_parcels(yr, cty, cols = "PIN", names = "original", geometry = "polygon")
```

Rules:
- Exact mode must pass for every read of 2005-2023 and 2025 files, and for
  2024 gdb reads.
- Shapefile mode is only for reads of 2024 `.shp` files.
- Points mode for reads of published Points layers (rows + attributes
  identical except VIEWID; each point within 1 m or inside the same parcel).
- If the old read applied a `query`/`wkt_filter`/column subset, apply the same
  subset to both sides before comparing.
- If an old path no longer exists (e.g. `Desktop/HCRA/shp_plan_regonal_parcels_*`),
  the script was already broken: repoint it anyway and record
  "old path missing; store partition already verified in
  docs/store_verification.csv" instead of a comparison.
- Old files that are iCloud placeholders will download when read; that is
  expected and can be slow.
- Write all results to
  `<PARCEL_HOME>/verification/<project>_results.csv`
  (one row per comparison, including `ok`).
- Run the verification script with `Rscript` and report the results.
- Do not edit anything under `parcel_data/R/` or `parcel_data/code/`. If the
  helper cannot express a read, or a comparison fails for a reason that looks
  like a store or helper problem, stop on that site and report it with the
  exact old call and the failing output.

## Report back

For each project: scripts changed (path, line numbers, old -> new call),
scripts skipped and why, verification results (pass/fail counts and every
failure with its detail), prose mentions left unchanged, and any old files
the scripts read that are NOT covered by the store.
