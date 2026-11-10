# parcel_data

One store for the MetroGIS / Metropolitan Council regional parcel releases
(Twin Cities 7-county area: Anoka, Carver, Dakota, Hennepin, Ramsey, Scott,
Washington), file years 2005-2025, as Hive-partitioned GeoParquet
(`year=YYYY/county=Name/`), so every project reads one verified copy instead
of keeping its own shapefiles.

**The data are not in this repository** (about 75 GB). The source releases are
the public "Regional Parcel Dataset" files published on the Minnesota
Geospatial Commons; `code/01_collect_raw.R` and `code/01b_collect_2025.sh`
record which release file each year/county came from.

## Layout
- `code/` – build pipeline, run in order: collect raw files (01), standardize
  to GeoParquet (02), verify every partition against its source (03), fix
  label points (04), shapefile schema (05), published Points layers (07, 08).
  06 and 09 are local disk-cleanup tools.
- `R/read_parcels.R` – the reader. `names = "standardized"` gives one column
  per concept across years; `names = "original"` returns exactly what
  `st_read()` of that year's file returned (drop-in for older scripts).
  `layer = "points"` reads the published Points layers.
- `python/read_parcels.py` – Python reader with the same views.
- `verification/` – per-project checks that repointed scripts read identical data.
- `docs/` – column crosswalks, schema inventory, verification and write logs,
  `STATUS.md` (running build log and decisions), `REPOINTING.md`.

## Use
```r
source("R/read_parcels.R")   # set PARCEL_HOME if the store lives elsewhere
ramsey_2016 <- read_parcels(years = 2016, counties = "Ramsey",
                            cols = c("pin", "emv_land", "emv_total"))
```
