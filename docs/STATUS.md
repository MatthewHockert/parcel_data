# Status — paused 2026-11-07 night

## Done
- Store: 147 partitions (2005-2025 x 7 counties) in `data/standardized/`, every one
  verified exact against its source file (`docs/store_verification.csv`), and every
  stored pt_x/pt_y inside its own parcel (`docs/fix_points_log.csv`).
- Sources: shapefiles for 2005-2020, 2022, 2025; GeoPackage for 2021; geodatabases
  for 2023-2024 (Matt chose the richer containers: missing numbers stay NA, times kept).
- Helpers: `R/read_parcels.R` (standardized/original views, bbox, points incl.
  `metrogis`, `parcel_linearize`, `parcel_interior_xy`), `R/verify_read.R`
  (exact / gdb key mode / `shp_losses` mode / `compare_point_reads`),
  `python/read_parcels.py` (+ manifest, verify_read.py).
- brownfield_stpaul `code/02_clean/02_parcels.R` repointed; rebuilt panel identical to
  the pre-repoint panel for 18/20 years; 2021/2024 differ only by shapefile 0 -> NA
  (expected). The UTC date fix also exposed that the ORIGINAL brownfield panel had 2023
  sale_date one day early (gdb date-time printed in Central time); the rebuilt panel is correct.
  2024 x/y differ for ~2,900 curved parcels (point from GDAL-linearized curve; up to 59 m, same parcel).
  Old panel kept as `data/interim/parcels_stp_panel_pre_repoint.parquet`.

## In flight at pause (agents; they never delete or commit)
- st_paul_rc_affordable_housing, matthew_maps + housing_reform + vacant_land blog,
  HCRA + hwy-36 + hc_easement_simulations + hennepin_conservation_easements +
  hennepin_sprawl: repointing + verification (`verification/<project>_results.csv`).
- scenic-quality: DONE overnight. clean_parcels.py repointed (sys.path + import lines 61-62,
  SRC_CACHE_VERSION 1 -> 2 at line 110, read at lines 881-882, zip-missing exit -> note at
  1303-1306; zip not deleted). Exact match vs gd.read_file of the 2021 GeoPackage in all 7
  counties (verification/scenic-quality_results.csv, 9/9 pass). Python bbox prefilter restored.

## Open items to check tomorrow
1. hwy-36 Washington 2015: values/PIN differ from the store (own downloaded copy? different release?).
2. matthew_maps 2024 gdb: OWNER_NAME/OWNER_MORE/TAX_NAME differ from the store's 2024 gdb
   (taken from the housing_reform copy) — possibly two different 2024 gdb downloads.
3. Several "old path missing" rows are being counted as failures (bookkeeping).
4. Scripts reading gdb/gpkg dates must use `as.Date(x, tz = "UTC")` before converting
   to text/dates, or dates print one day early (found in brownfield; check others).
5. Re-verify any script that read 2021 shapefiles (store 2021 is now the GeoPackage).
6. Final step: rerun every verification script against the final store, then show Matt
   exactly what would be deleted (originals + ~236 GB duplicates) before deleting anything.

## Overnight: st_paul_rc agent report (2026-11-08)
- All reads in 18 files repointed (R/01-28, analysis/development_effects/shift_share/parcel_rci.qmd);
  every edited file parses; no bbox used. paper_proposal.qmd prose untouched.
  Unchecked by its grep: mn_city_finances.qmd, tariff_ai_employment.qmd (grep hung on iCloud).
- Verified exact: Ramsey shapefile reads 2005-2020 (16 of 17 comparisons run).
- 2021 Ramsey "failure" is NOT a store bug: the store's 2021 is now the GeoPackage (by decision),
  and these scripts read the 2021 SHAPEFILE. Besides shapefile value losses, the GeoPackage
  names one field RANGE_ (shapefile: RANGE) and has no Shape_Leng / Shape_Area fields.
  => DECISION NEEDED: give the original view a shapefile flavor for 2021/2024
  (shapefile column names, 0-for-missing, Date not date-time, trimmed text, Shape_Leng/Area
  recomputed from geometry) so shapefile-reading scripts keep working unchanged, and verify
  them in shapefile mode; or edit those scripts to use the GeoPackage names.
- Blocked: 2022 Ramsey .dbf/.shx in matthew_maps_saint_paul/Archive are iCloud placeholders
  that won't download (brctl stalled; ls/git status hang). Pending: 2022 Ramsey, Hennepin
  2005-2022, 2023/2024 gdb polygons, Points, 2025, and the SQL-subset reads. Verify script
  resumes from its CSV.

## 2026-11-08 morning
- Matt: keep IDENTICAL output for scripts that read the 2021/2024 shapefiles ->
  read_parcels(..., names = "original", as_shapefile = TRUE) (shapefile names/types,
  0-for-missing, blank text -> NA, text cut to field width then trimmed, dates without
  times, Shape_Leng/Area recomputed for 2021). docs/shapefile_schema.csv from
  code/05_shapefile_schema.R. 2024 Ramsey: identical to the shapefile.
- Crosswalk fix: 2021 GeoPackage RANGE_ -> range (2021 rewritten; other partitions keep an
  empty range_ column until the final full rewrite).
- FOUND: the public 2021 GeoPackage has OWNER_NAME / OWNER_MORE / TAX_NAME stripped (~97% of
  parcels, all 7 counties); the 2021 shapefile has them. No numeric field affected; 2023/2024
  gdb and 2025 shp have names. Store keeps GeoPackage values + <col>_shp sidecars with the
  shapefile's names where the GeoPackage is blank: original view = GeoPackage, as_shapefile =
  shapefile, standardized view = complete.
- Matt asked to use subagents (checked by me) and up to 3 cores for R jobs.
- as_shapefile is now EXACT for 2021/2024 (geometry, row order, Shape fields): store keeps
  row_in_shp, geometry_shp (only where the shapefile polygon differs), shape_leng_shp /
  shape_area_shp for those years. Verified exact: 2021 Ramsey, 2024 Ramsey, 2024 Hennepin.
  brownfield panel rebuilt with as_shapefile: identical to the original panel except 2023
  sale_date (a correction) and the 2024 x/y now match too once rerun.
- New point_method = "metrogis_rows" (+ orig_fid): Washington's published Points layer is one
  point per polygon at the plain centroid with ORIG_FID = row - 1; exact on Washington 2015.
  (Ramsey/Hennepin Points use "metrogis": one point per PIN, nudged inside.)
- HCRA_R/intersection.R:210 reads the 2023 gdb with no layer => silently Parcels2023Anoka;
  likely meant Hennepin. Repoint preserved the behavior; flag for Matt.
- Not in the store (left in place, not to be deleted): plan_parcels_open gdb/gpkg reads in
  hc_easement_simulations (county_analysis.R:19, city_reports.R:892,
  dayton_easement_app/data_prep.R:113, build_offset_benchmarks.R:131) and HCRA intersection.R:11.
- Diagnosis (verification/diagnosis_hwy36_mm2024.md): hwy-36 Washington files are byte-identical
  to the store (point rule was the only issue; fixed by metrogis_rows). matthew_maps' 2024 gdb is a
  later (Dec 2025) public download with OWNER_NAME/OWNER_MORE/TAX_NAME stripped in every layer;
  otherwise identical. The store's Jan 2025 copy is more complete. index.qmd doesn't use those
  columns, so it is verified on all other columns.

## Paused again 2026-11-08 (Matt left)
Agents may still be finishing (they never delete or commit): st_paul_rc (exact rechecks +
Hennepin/gdb/Points/2025/SQL subsets), Hennepin group (re-apply hc_easement + hcra_paper
02_build_exposure with as_shapefile; then hwy-36 with metrogis_rows + orig_fid), matthew_maps
group (2024 shapefile reads with as_shapefile; index.qmd 2024 gdb re-apply).
Remaining after they report:
1. Check each agent's results CSV myself.
2. Final full rewrite of all partitions (drops the empty range_ column), then rerun every
   verification script against the final store (3 R processes max).
3. Rebuild brownfield panel once more (2024 x/y should now match via as_shapefile geometry).
4. Deletion review with Matt: exact list of originals + duplicates and GB freed; delete only
   on his approval. Never delete: plan_parcels_open files, iCloud-stuck 2022 Ramsey originals
   unless verified, AOData duplicate repo is NOT repointed (its parcel files are duplicates).
- st_paul_rc (final report while paused): as_shapefile = (yr == 2021) added at 16 reads; 36/36
  comparisons run so far pass exactly (Ramsey shp 2005-2022, Hennepin shp 2005-2014, all 2021
  incl. SQL subsets). No 2024 .shp reads in this project. Blocked on iCloud: Hennepin shp
  2015-2020/2022, 2023/2024 gdb (4), Points (4), 2025 (2), non-2021 SQL subsets. R process
  PID 64806 still waiting; rerunning the verify script resumes.
  PROPOSAL for Matt: where an old file is an iCloud placeholder that won't download, run the
  "old" read on the parcel_data/data/raw copy of the same file (same name and byte size per
  docs/move_manifest.csv; downloaded copies were confirmed byte-identical with cmp). That
  unblocks verification without waiting on iCloud.
- Hennepin-group final: hc_easement_simulations 18/18 exact; hcra_paper 02_build_exposure 19/19 +
  18/18 exact (as_shapefile for 2021/2024). HCRA, ag_preserve, hennepin_sprawl unchanged (pass).
- hwy-36 NOT repointed (scripts byte-identical to originals; edits saved in scratchpad
  hwy36_*.R.new). Washington Points: 2015-2019 within 2.2 mm (float rounding); 2020: 71% within
  1 cm, rest up to 1.41 m regardless of polygon repair (Points file built from slightly different
  geometry); 2017: 264 rows where published points read NA but polygons have the text "NULL"
  (residential flag unaffected). DECISION FOR MATT at deletion review: repoint under the Points
  rule (within 1 m or same parcel) or keep hwy-36 on its own Washington Points files.
- metrogis CORRECTED: one point per polygon row after dropping placeholders (no PIN collapse);
  Shape_Length also dropped. Verified rows + attributes on Ramsey 2020/2023, Hennepin 2020.
- st_paul_rc reads 2024 from the redacted Dec-2025 gdb and analysis.qmd uses OWNER_NAME.
  Matt chose identical output: read_parcels(..., drop_owner_names = TRUE); verified exact vs
  that gdb (2024 Ramsey). Agent applying it at the 2024 reads.
- st_paul_rc FINAL: 113 comparisons / 275 site-rows; all pass except 2023/2024 Ramsey Points, where
  the only mismatch is the checker aligning a two-polygon PIN (123-132923440001) by PIN (data match).
  drop_owner_names = (yr == 2024) applied at its 12 reads of the redacted 2024 gdb.
- matthew_maps / housing_reform / vacant_land FINAL: 12/12, 12/12, 19/19. Three green_line Points
  reads reverted (published Points carry condo-unit PINs not in any polygon file).
- Matt decided: STORE the published Points layers too (data/standardized_points, as published,
  read via read_parcels(..., layer = "points")); no raw Points copies kept (Parquet verified exact
  is the archive). Subagent building code/07_points_store.R + 08_verify_points.R.
  After it: repoint all Points reads (st_paul_rc, green_line x3, hwy-36) to layer = "points", exact.
- BUG FIXED (2026-11-08): standardized reads WITHOUT `cols` returned only year/county (arrow got an
  unevaluated col_select expression). All prior verifications named columns, so unaffected.
- NEW: read_parcels(..., layer = "points", collapse_condos = TRUE) -> one row per polygon
  (R/collapse_condos.R): additive fields summed, other fields = most common value (+ <col>_n_distinct
  where units disagree), n_units, unit_pins, building PIN, one interior point; unmatched points kept
  and flagged. Ramsey 2010: 166,919 points -> 148,653 rows, all units counted once, EMV/tax totals
  identical, 1,037 multi-unit buildings, 4 unmatched.

## Paused 2026-11-08 evening (Matt)
- Points store in progress: 115 partitions written so far (agent may keep going; it never deletes).
Remaining after it reports:
1. Check docs/points_verification.csv (all exact?).
2. Repoint all Points reads to layer = "points" (st_paul_rc x8, green_line x3, hwy-36 x2) and verify exact.
3. Final full rewrite of polygon partitions (drop empty range_), rerun every verification script
   (3 R processes max), rebuild brownfield panel.
4. Deletion review with Matt (docs/deletion_candidates.csv; re-run code/06_deletion_candidates.py).
   Open: delete Desktop/AOData hwy-36 parcel files (repo not repointed)?
- 2026-11-09 Matt: in the STANDARDIZED view, Points rows (condo units included) share the
  centroid of the polygon they fall in (moved inside if outside); points in no polygon keep
  the published location. read_parcels(..., layer = "points", point_location = "polygon"|
  "published"); default polygon for standardized, published for original. Ramsey 2010:
  166,919 points at 148,653 shared locations. Matt is downloading the remaining year folders
  from iCloud; wrap up once the Points store completes.

## 2026-11-09 — Final full rewrite done; warnings explained
- The 06:37 final rewrite was killed at 07:03 after 118/147 partitions (memory exhausted by
  concurrent verification subagents; it also corrupted the Claude desktop app's state).
  Log kept as docs/final_rewrite_run_interrupted_20261109.log.
- Re-ran ALL 147 partitions alone, 12:23-13:00 (docs/final_rewrite_run.log): 147/147 written,
  rows_in = rows_out everywhere, range_ dropped (range kept), 109 columns, 22,318,270 rows.
  Same code as the interrupted run (02_standardize.R unchanged since 06:37:11).
- code/02_standardize.R line 427: REWRITE set back to FALSE (setup-only rerun writes nothing;
  checked: docs CSVs byte-identical, all 147 parquet mtimes unchanged).
- The run ended with "There were 21 warnings". Diagnosed by re-running write_partition() for all
  147 partitions into a scratch store with each warning tagged (store never touched): exactly 21,
  ALL raised by GDAL while reading source files (CPL_read_ogr), none by our code; no data changed.
    14  malformed polygon rings ("organizePolygons() received an unexpected geometry", "cannot be
        translated to Simple Geometry ... contained in a multipolygon", one >100-part polygon):
        Anoka 2018-2025 (13), Dakota 2023 (1). Source-data defect; GDAL reads these parcels as
        multipolygons on ANY st_read, so every original script saw the same geometry.
     7  2021 GeoPackage dates ("Non-conformant content ... EXP_DATE/EDIT_DATE ... successfully
        parsed"), one per county: ISO text with trailing Z, parsed correctly as UTC.
  Ramsey: no geometry warnings in any year (only the shared 2021 date note).
- Caution for reruns: 02_standardize.R's setup REWRITES docs/schema_inventory.csv and
  docs/column_crosswalk.csv (lines 92, 121, 291). Never source it from several R processes at
  once: concurrent readers crash with a bus error in read_csv (vroom mmap of a file being rewritten).
- 03_verify_store.R on the final store (docs/verify_store_run.log, docs/store_verification.csv):
  147/147 OK (rows, names, geometry exact vs source; every stored point inside its own parcel);
  no partition changed status vs the 2026-11-07 verification. Run printed "17 warnings": not
  individually checked; presumed the same GDAL source-read messages (verification reads each
  source once; the rewrite also read the 2021/2024 shapefiles for sidecars).
- Points store gap closed (2026-11-09 15:01-15:04): `Rscript code/07_points_store.R 2022 2025`
  wrote the 11 missing partitions (REWRITE FALSE; the other 136 untouched). 2022 read from
  ~/Downloads/shp_plan_regonal_parcels_2022 (fully local; byte sizes equal to all 4 other copies);
  2025 Hennepin/Ramsey/Scott/Washington pulled from iCloud (only copy). Cause of the gap: the
  11-08 points run was interrupted at 2025 Dakota and never reached/read these; no code bug.
  docs CSVs: pre-existing rows unchanged, rows only added (write log is kept sorted, so new 2022
  rows sit above 2023). Logs: docs/points_store_2022_2025_run.log, points_verify_*_run.log.
- Points verification: 2020 had NEVER been verified (no rows in points_verification.csv);
  ran 08_verify_points.R 2020 -> 7/7 OK. Now 147/147 Points partitions verified OK.
- BOTH STORES COMPLETE AND VERIFIED: polygons 147/147, points 147/147.
- Next: brownfield panel rebuild (code-along with Matt), deletion review with Matt.

## 2026-11-09 — Deletion review with Matt: Tiers 1 and 2 moved to the Trash
- docs/deletion_candidates.csv regenerated (06): 10,184 files, 598.4 GB, of which 226.5 GB on
  local disk and 372.0 GB iCloud-only (deleting iCloud-only frees iCloud, not disk).
- Live-read check: a filename scan MISSES dynamically built paths (hwy-36 builds
  paste0("Parcels", year, "WashingtonPoints") inside a literal folder), so every candidate folder
  was checked against its project's code by folder name, then each hit read line by line.
- code/09_trash_candidates.py (tier1 | tier2, dry run by default): moves only files FULLY ON DISK
  (moving iCloud-only files out of synced folders would download them) to
  ~/.Trash/parcel_cleanup_<tier>_20261109/, manifest docs/trash_manifest_<tier>_20261109.csv for an
  exact restore. Nothing permanently deleted; space returns when Matt empties the Trash.
- Tier 1 (no code reads them): 974 files, 46.24 GB. ~/Desktop/UMN/hennepin_conservation_easements
  parcel files (the folder's other data stays: housing_reform main.R reads it), ~/Downloads MetroGIS
  folders (incl. the 2022 Points copy; a parcel_data/verification script's "old" read of the 2023
  gdb there can no longer be rerun), st_paul_rc shp_plan_regional_parcels (the ONLY raw 2025 Points:
  the verified Parquet is now the archive, per Matt 11-08), brownfield 2023 gdb.
- Tier 2 (named only by dead code): 1,785 files, 107.16 GB. research/hennepin_conservation_easements
  (only reader: hcra_paper/archive/2024-2025_original/parcel_analysis.R, an archived original),
  matthew_maps except Points, hc_easement_simulations, brownfield data/raw/parcels except 2024,
  housing_reform, vacant_land (their base_file_path leftovers point at ~/Desktop/HCRA).
- KEPT, still read live (delete after a verified repoint):
    matthew_maps Points shapefiles, 38.4 GB: green_line_access/R/build_green_line_panel.R:50,
      build_stpaul_origins.R:58/79, build_stpaul_value_panel.R:98 st_read
      Archive/shp_plan_regonal_parcels_<yr>/Parcels<yr><County>Points.shp -> repoint to
      read_parcels(..., layer = "points") and verify exact.
    brownfield data/raw/parcels/2024, 0.67 GB: brownfield_spillovers.qmd chunk load-brownfields
      (#| eval: true) st_reads Parcels2024Ramsey.shp (PIN only) -> repoint with Matt (code-along).
    Tier 3, 34.0 GB: AO/hwy-36 and AOData/hwy-36, never repointed (open decision).
- brownfield_stpaul/data/external/parcel_file_provenance.csv still lists the local copies now in
  the Trash; update it when the brownfield repoint is done.

## 2026-11-09 — green_line Points reads repointed; matthew_maps Points to the Trash
- Repointed the three live Points reads in matthew_maps_saint_paul/green_line_access/R
  (build_green_line_panel.R read_county_year, build_stpaul_value_panel.R read_year,
  build_stpaul_origins.R read_points) to read_parcels(..., layer = "points", names = "original").
  Originals backed up in the session scratchpad before editing; old calls kept in comments.
- verification/green_line_points_verify.R (results green_line_points_results.csv): what each reader
  uses, old Archive shapefile vs store, Ramsey + Hennepin 2005-2022, full and study-area-filtered.
  Two bugs in my own check, both fixed and the earlier runs kept with suffixes:
    run1: filtered with the exact study polygon, but the script hands GDAL st_as_text(study_area),
          rounded to 7 significant digits (~5 cm) -> 1-2 edge points differed. Now filters on that WKT.
    run2: mismatch test sum(!(a == b | both NA), na.rm = TRUE) silently DROPPED value-vs-NA cells.
  Final run: 35/36 identical. Ramsey 2021 differs: store (GeoPackage) NA where the 2021 shapefile
  wrote 0, in YEAR_BUILT, NUM_UNITS, EMV_LAND/BLDG/TOTAL, TAX_CAPAC, TOTAL_TAX, SPEC_ASSES, SALE_VALUE;
  every mismatch is exactly store NA vs shapefile 0. Hennepin 2021 identical.
- DECISION (Matt): option A, keep 2021 output identical: in the panel (Ramsey only) and value_panel
  readers, for 2021 those 9 fields NA -> 0. End-to-end (edited vs original functions, zero tolerance,
  NA-aware): identical for 2012 and 2021, all readers.
- Pre-existing bug, flagged in a comment, NOT fixed (changes results): build_stpaul_origins.R filters
  on raw$CITY, absent from 2018 on (CTU_NAME), so 2018-2022 contribute no PINs.
- Moved matthew_maps Points shapefiles to the Trash: 621 files, 44.95 GB (38.4 GB at review time; the
  verification reads hydrated ~6.5 GB from iCloud). Manifest docs/trash_manifest_green_line_points_20261109.csv.
- Trash total so far: 3,380 files, 198.35 GB (tier1 46.24, tier2 107.16, green_line_points 44.95).
  Still kept: brownfield data/raw/parcels/2024 (qmd chunk), hwy-36 AO + AOData (34.0 GB, open decision).

## 2026-11-09 — brownfield: last local reads repointed, copies trashed
- brownfield_spillovers.qmd load-brownfields -> read_parcels(2024, "Ramsey", names = "original",
  as_shapefile = TRUE, cols = "PIN", bbox = brownfields); same 88,732 polygons, same PINs, 1,302 sites.
- Panel rebuilt on the final store: identical to the pre-repoint build except 2023 sale_date +1 day
  (67,457 rows; the known correction). x/y identical, incl. 2021/2024 curved parcels.
- data/raw/parcels/2024 to the Trash (5 files, 0.67 GB; trash_manifest_brownfield_2024_20261109.csv).
  brownfield now reads NO local parcel files. Its decision_log.md and parcel_file_provenance.csv updated.
- Trash total: 3,385 files, 199.02 GB. Remaining on disk and still read: hwy-36 AO + AOData (34.0 GB).

## 2026-11-10 — iCloud-only duplicates deleted
- code/10_delete_icloud_duplicates.py --delete (Matt approved): 3,599 iCloud-only files, 197.59 GB,
  removed from iCloud (recoverable at iCloud.com Recently Deleted until ~2026-12-10).
  Rule: folder cleared in the live-read review, and a same-name same-size copy exists in data/raw
  or among the verified Points source copies. Manifest: docs/icloud_delete_manifest_20261110.csv (local only).
- Kept: 1,110 files with no name+size match (incl. 42.7 GB of Points); AO + AOData hwy-36
  (decide with the hwy-36 paper); scenic-quality (data for McWay).
- hwy-36 load_parcel_data.R repointed in AO, AO/paper_replication, AOData (uncommitted, not pushed);
  store Points match exactly 2015-2020 (verification/hwy36_points_results.csv).

## 2026-11-10: Zenodo deposit, Points copies deleted, Python reader matches R
- Zenodo deposit published: DOI 10.5281/zenodo.24116899 (record 24116899), version 1.0.0, CC-BY 4.0.
  42 zips (polygons and Points, one per year, 2005-2025) plus README, crosswalks and SHA256SUMS,
  built by code/11_zenodo_package.sh. Every uploaded file's MD5 matched the local copy
  (docs/zenodo_md5.txt). Round trip: zips unzipped into a fresh PARCEL_HOME read back identical.
- download_parcels() in R and Python fetches year zips, checks the MD5 and unzips into PARCEL_HOME.
  Tested against the published record: R 2006 Points + polygons (Hennepin identical), Python 2005
  Points (Anoka equal). Zenodo serves about 1 MB/s.
- Repo made usable by others: no hard-coded home paths in the readers, Setup section, CITATION.cff,
  MIT LICENSE, python/requirements.txt, README in the standard project layout.
- code/12_delete_points_copies.py --delete (Matt approved): every Parcels<yr><County>Points.* and
  All7Points.* copy outside AO / AOData, 1,020 iCloud-only files, 60.25 GB, from hc_easement_simulations,
  hennepin_conservation_easements, matthew_maps_saint_paul, vacant_land_fees_st_paul_blog and
  minneapolis_st_paul_housing_reform_paper. No code read them (Points come from
  read_parcels(layer = "points")). Manifest docs/points_copies_delete_manifest_20261110.csv (local only).
  The earlier rule (10) had kept these because their verified source copies sit in AO / AOData,
  which were never trashed, so no size was on record. Original Points files survive only in AO / AOData.
- hc_easement_simulations: leftover release folders (metadata, previews, attribute PDFs, .lyr; 6 MB)
  moved to the Trash.
- scenic-quality: clean_parcels.py (reads the store via PARCEL_HOME) committed locally, not pushed
  (McWay's repo). Its two MetroGIS zips (2021 and 2024 GeoPackages, 0.98 GB, iCloud-only) deleted.
  McWay gets the data from Zenodo.
- Python reader brought to parity with R (Matt: "there shouldn't be a difference"):
  - point_location ("polygon" default for standardized Points, as in R). Python Points read
    download_parcels(layer = "points") now also fetches that year's polygons.
  - polygons repaired with GEOS "structure" (sf's default). shapely's default "linework" moved
    3 of 167,533 Ramsey 2024 points by up to 125 m. Needs shapely >= 2.1.
  - point_method = "metrogis": one point per polygon row (R since 2026-11-08). Python still
    unioned by PIN, one row short in Ramsey 2024.
  - standardized view fills 2021 owner_name / owner_more / tax_name from the shapefile sidecars.
    Python had left them blank (about 167,000 Ramsey rows). R skipped this fill when cols was
    given. Both now fill in every case.
  - ported as_shapefile, drop_owner_names, collapse_condos (python/collapse_condos.py),
    metrogis_rows and orig_fid. names = "original" works under pandas 3.
  - Checks: R vs Python identical for every standardized column (Ramsey 2016, 2021, 2024), Points
    and polygon-point placement (within 1e-8 m), collapse_condos (Ramsey 2021, 149,235 rows) and
    metrogis_rows + orig_fid (Washington 2015). as_shapefile equals read_file() of the 2021 and
    2024 shapefiles (Ramsey 2021, Ramsey 2024, Carver 2021: columns, rows, geometry).
  - Known: names = "original" reproduces the dtypes of pyogrio 0.10, which built the manifests.
    Under pyogrio 0.13 read_file() parses shapefile dates such as "0000/00/00" that 0.10
    returned as text, so those columns differ in type, not in value.

## 2026-11-11: known gaps, parcel_columns() empty flags, estimate_tax_cap()
- A session using the store found Ramsey 2005 emv_land / emv_bldg are 0 county-wide. Confirmed
  in the published shapefile (the store keeps values as published). code/13_known_gaps.py now
  lists every published column that is entirely blank or zero in a year x county, for both
  layers: docs/known_gaps.csv, 6,526 cells. Notable: Ramsey tax_capac 0 for 2005-2020 and
  blank 2021, Hennepin fin_sq_ft and num_units 0 for 2018-2025, Scott tax_capac 0 most years.
- parcel_columns() gained empty_in (standardized view) and empty (original view), R and Python
  identical.
- estimate_tax_cap() (R and Python, identical output): net tax capacity from emv_total,
  property type and homestead status, with Hennepin's 2025-assessment class rate table
  (docs/class_rates_hennepin_2025.csv, hand-transcribed from Report T99SS01, payable 2026) and
  the 2025 homestead market value exclusion. Matt asked for it with a warning that the rates
  are 2025 for every year. County labels mapped to property types by keyword rules in
  code/14_use_class_map.py (docs/use_class_map.csv, a judgment call, review per county).
  Check: Hennepin 2025 file 94.7% of parcels within 1% of published tax_capac, total 0.993.
  Earlier years and other counties drift (docs/tax_capacity.md).
- Follow-up (Matt asked why Carver and Dakota were off): estimate_tax_cap() fixed in R and
  Python. Homestead exclusion now by payable year (none through 2011, 76k / 413.8k for
  2012-2024, 95k / 517.2k from 2025). Value timing by county (file year for Hennepin and Ramsey,
  file year + 1 elsewhere, fitted to published tax_capac; tax_year field not used because
  Anoka 2024's is off by one). Farms no longer get the homestead exclusion, only the farm house.
  code/15_check_tax_cap.R checks every county-year with published tax_capac
  (docs/tax_capacity_check.csv): median 86-93% of parcels within 1%. Remaining gaps are in the
  published data: Dakota, Carver, Anoka 2018-2020 publish C/I tax capacity net of fiscal
  disparities (about 1/1.55), Dakota publishes tax_capac for exempt parcels, Ramsey 2022-2025
  and Carver 2018 / 2020 / 2021 published values fit no pairing. Details in docs/tax_capacity.md.
