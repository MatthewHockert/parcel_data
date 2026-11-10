# Twin Cities Regional Parcels, 2005–2025: Standardized GeoParquet Store

DOI: 10.5281/zenodo.24116899
Code and readers: https://github.com/MatthewHockert/parcel_data

## What this is
The annual MetroGIS / Metropolitan Council Regional Parcel Dataset releases
for the seven Twin Cities metro counties (Anoka, Carver, Dakota, Hennepin,
Ramsey, Scott, Washington), file years 2005–2025, stored as Hive-partitioned
GeoParquet (`year=YYYY/county=Name/part-0.parquet`), 147 county-years per
layer.

- **Polygons** (`parcels_polygons_YYYY.zip`): the parcel polygon layers.
- **Points** (`parcels_points_YYYY.zip`): the published parcel Points layers,
  which include condo-unit records whose PINs appear in no polygon file.

Values are kept as published. Column names are merged by concept across years
(one net-tax-capacity column, etc.); concepts a year did not record are NA.
No rows are added or removed. `column_crosswalk.csv` and
`points_column_crosswalk.csv` map each year's original field names to the
standardized names.

## Use
1. Clone or install the readers from the GitHub repository above.
2. Set `PARCEL_HOME` to the repository folder.
3. Unzip the years you need into `$PARCEL_HOME/data/`
   (each zip starts at `standardized/` or `standardized_points/`).
4. Read:
   ```r
   source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
   r16 <- read_parcels(years = 2016, counties = "Ramsey")
   ```
   `names = "original"` returns each file's own field names;
   `layer = "points"` reads the Points layers. A Python reader with the same
   options is in `python/read_parcels.py`.
5. Points need that year's polygons too: with the default
   `names = "standardized"`, each point is placed on its parcel polygon, so
   unzip `parcels_polygons_YYYY.zip` alongside `parcels_points_YYYY.zip`
   (or read with `point_location = "published"` to skip that step).

## Sources
MetroGIS Regional Parcel Dataset, annual releases, originally downloaded from
the Minnesota Geospatial Commons (`shp_plan_regonal_parcels_<year>.zip`;
2021 GeoPackage, 2023 and 2024 file geodatabases). Year 2025 is the
January 2026 release. The Geospatial Commons archive links for past years no
longer resolve; Metropolitan Council GIS holds the archive.

The source data are public domain under the Minnesota Government Data
Practices Act (Minnesota Statutes Chapter 13). They were developed by the
seven counties and the Metropolitan Council and are provided as is, without
warranty.

## Verification and provenance
- Every polygon partition was checked against its source file: same rows,
  attributes and geometry (`docs/store_verification.csv` in the repository).
- Every Points partition was checked against its published shapefile
  (`docs/points_verification.csv`). The original Points files were deleted
  after that check, so this deposit is the only remaining copy of the Points
  layers as processed here; the originals can only be re-obtained from
  Metropolitan Council GIS.
- The raw polygon release files are kept by the author and the build scripts
  are in `code/` of the repository.

## Files
- `parcels_polygons_YYYY.zip`, `parcels_points_YYYY.zip` – 2005–2025
- `column_crosswalk.csv`, `points_column_crosswalk.csv`
- `SHA256SUMS.txt` – checksums for every file in the deposit
