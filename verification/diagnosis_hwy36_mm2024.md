# Diagnosis: hwy-36 Washington 2015 and matthew_maps 2024 gdb (2026-11-08)

This was a read-only diagnosis. Scripts: `verification/diagnosis_hwy36_2015.R` and
`verification/diagnosis_mm2024.R`. Per-layer table: `verification/diagnosis_mm2024_results.csv`.

## Case 1: hwy-36 Washington 2015

**Cause: the files are the same. The failure comes from the point emulation and the comparator, not from the data.**

- The project's `Parcels2015Washington.{shp,shx,dbf,prj,cpg,sbn,sbx,shp.xml}` are byte-identical
  (`cmp`) to `data/raw/2015/`. All are dated 2024-03-22.
- The script does not read the polygon layer. It reads `Parcels2015WashingtonPoints`, the
  county-published Points layer, so the verify compared it with
  `read_parcels(..., geometry = "point", point_method = "metrogis")`.
- The published Points layer's attributes match the store's 2015 Washington polygons in every
  column. This holds both in file order and after sorting by PIN. The Points layer has the same
  106,045 rows as the polygons, plus `ORIG_FID`, which means one point per polygon.
- The "metrogis" rule was tuned on Ramsey and Hennepin 2020. It keeps one point per PIN and drops
  placeholder PINs. For Washington 2015 that gives 105,983 rows (62 fewer):
  - 39 rows have PIN `-`, a placeholder. All of them are dropped.
  - 46 rows share 23 duplicated real PINs. These are collapsed to one row per PIN.
- `compare_point_reads()` aligns rows with `match(old PIN, new PIN)`:
  - The 39 `-` rows become NA. That is why PIN itself is listed as differing.
  - Each duplicated PIN maps every old row to the same new row.
- On the 105,960 unique PINs that both sides share, old and new agree in every column. The listed
  `cols_differ` come only from those 85 rows.
- Washington 2019 and 2020 fail the same way (44/20 and 45/21 duplicate/placeholder rows).

**The more complete copy:** neither. They are identical.

## Case 2: matthew_maps 2024 geodatabase

**Cause: these are two different downloads. The later one has owner and taxpayer names stripped.**

| | matthew_maps copy | store (= housing_reform copy) |
|---|---|---|
| gdb file dates | 2025-12-16/17 | 2025-01-24 (store copy made 2026-11-07) |
| logical size | 1.38 GB (90 of 111 files were iCloud placeholders) | 2.14 GB |
| `metadata/metadata.xml` | byte-identical | byte-identical |

In all 14 layers (7 counties, polygons and Points), the two copies agree on:

- row counts
- PIN sets (0 PINs unique to either copy)
- `TAX_ADD_L1` and `OWN_ADD_L1` blank shares

The difference is the name fields. In the matthew_maps copy, `OWNER_NAME`, `OWNER_MORE` and
`TAX_NAME` are 100% NA in every layer. The store has them populated wherever the county publishes
them:

- Ramsey polygons: `OWNER_NAME`/`TAX_NAME` blank 2.5% in the store vs 100% in matthew_maps.
  167,447 shared PINs differ, and every one is NA in matthew_maps while named in the store
  (e.g. 123-122922340241, "FLEX HOLDING LLC"). `OWNER_MORE`: 74,140 differ.
- Stored names were stripped in every county:
  - `OWNER_NAME` in Anoka, Dakota, Hennepin, Ramsey and Washington. Carver and Scott never
    publish it.
  - `TAX_NAME` in all 7 counties.
- There are no cases where the store is blank and matthew_maps has a value.

This is the same pattern as the public 2021 GeoPackage. The December 2025 re-download appears to
be a later, redacted public release of the 2024 data. Other attribute columns were not compared in
this pass.

**The more complete copy:** the store / housing_reform copy (Jan 2025). Repointing matthew_maps to
the store would add names it never had. matthew_maps' own outputs could only have used NA names.
