# parcel_data

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24116899.svg)](https://doi.org/10.5281/zenodo.24116899)

This repository builds and reads one store of the MetroGIS / Metropolitan Council regional parcel releases for the Twin Cities 7-county area (Anoka, Carver, Dakota, Hennepin, Ramsey, Scott, Washington), file years 2005-2025, so every project reads one verified copy instead of keeping its own shapefiles. Each year's county files are standardized into Hive-partitioned GeoParquet (`year=YYYY/county=Name/`), with values kept as published and column names merged by concept across years, and the county-published Points layers are stored alongside the polygons. The goal of this dataset is to make it easier for researchers to pull parcel data across space and time that is unified and standardized making it easy to compare and store the data. It offers the ability to open multiple projects without having to copy the data into each project, freeing up storage, and increasing efficiency. Every one of the 147 polygon partitions and 147 Points partitions reads back identical to its source file (same rows, attributes and geometry). The built store is on Zenodo, and `download_parcels()` fetches the years a project needs.

The readers are `R/read_parcels.R` and `python/read_parcels.py`.

## Setup

1. Clone this repository.
2. Set `PARCEL_HOME` to the clone: `PARCEL_HOME=${HOME}/parcel_data` in `~/.Renviron` for R, `export PARCEL_HOME="$HOME/parcel_data"` in your shell profile for Python.
3. Install the dependencies: R `sf`, `arrow`, `dplyr`, `tibble`. Python `pip install -r python/requirements.txt`.
4. Download the years you need. Each zip has all 7 counties, is checked against `docs/zenodo_md5.txt`, and is unzipped into `$PARCEL_HOME/data`.
   ```r
   source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
   download_parcels(2014:2016)                 # polygons
   download_parcels(2021, layer = "points")    # points, plus that year's polygons
   ```
   ```python
   import os, sys
   sys.path.insert(0, os.path.join(os.environ["PARCEL_HOME"], "python"))
   from read_parcels import read_parcels, download_parcels
   download_parcels([2014, 2015, 2016])
   download_parcels(2021, layer="points")      # points, plus that year's polygons
   ```
   Downloads from Zenodo run slowly. For example, one year's polygons (300-600 MB) take about 5-10 minutes, and all 21 years of both layers (10 GB) may take several hours, so fetch only the years you need. Standardized Points reads place each point on its parcel polygon, so a Points download also fetches that year's polygons. `point_location = "published"` keeps the points where the county published them.
5. Map one county and year to check it works. This colors Ramsey County's 2016 parcels by estimated market value, on a log scale because a few large parcels are worth far more than the rest. Parcels with no value are left out.
   ```r
   p <- read_parcels(2016, "Ramsey", cols = "emv_total", filter = quote(emv_total > 0))
   plot(p["emv_total"], logz = TRUE, border = NA, main = "Ramsey County 2016, estimated market value")
   ```
   ```python
   import numpy as np
   import pyarrow.compute as pc
   p = read_parcels(2016, "Ramsey", cols=["emv_total"], filter=pc.field("emv_total") > 0)
   ax = p.plot(column=np.log10(p["emv_total"]), legend=True, linewidth=0, figsize=(9, 9))
   ax.set_title("Ramsey County 2016, estimated market value (log10 $)")
   ```

## Use

To see which columns exist before downloading anything, use `parcel_columns()`. It reads the crosswalks in `docs/`, so no data is needed.

```r
parcel_columns()                                    # every standardized column: type, years recorded, original names
parcel_columns(2014:2016, "Ramsey")                 # columns recorded in those years
parcel_columns(2016, "Ramsey", names = "original")  # that file's own field names, in order
```

Python takes the same arguments: `from read_parcels import parcel_columns`. Its `empty_in` column lists where a column was published but entirely blank or zero (for example `emv_land` in Ramsey 2005). The full list is `docs/known_gaps.csv`, made by `code/13_known_gaps.py`.

### Estimating net tax capacity

Some counties did not publish tax capacity for many years (Ramsey `tax_capac` is 0 for 2005-2020). `estimate_tax_cap()` fills it in from market value, property type and homestead status, using Hennepin County's 2025-assessment class rates.

```r
p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
p <- estimate_tax_cap(p)   # adds prop_type, homestead_status, tmv_est, tax_capac_est
```

**Warning:** the 2025 class rates are applied to every year, so earlier years are priced at 2025 rates. The homestead exclusion and each county's value timing do follow the year. Across every county-year with published values, a median 86-93% of parcels are within 1%, except Ramsey, whose published values look wrong. Dakota and Carver publish commercial-industrial tax capacity after the fiscal disparities contribution, and the estimate is before it. Prefer a county's published `tax_capac` where it exists. Method, rate table and checks: `docs/tax_capacity.md`.

```r
source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))
ramsey_2016 <- read_parcels(years = 2016, counties = "Ramsey",
                            cols = c("pin", "emv_land", "emv_total"))
```

```python
import os, sys
sys.path.insert(0, os.path.join(os.environ["PARCEL_HOME"], "python"))
from read_parcels import read_parcels
ramsey_2016 = read_parcels(years=2016, counties="Ramsey",
                           cols=["pin", "emv_land", "emv_total"])
```

`names = "standardized"` (the default) gives one column per concept across years, and `names = "original"` returns exactly what `st_read()` of that year's file returned, a drop-in for older scripts. `layer = "points"` reads the published Points layers. The R and Python readers take the same options and return the same data.

## Run order (building the store)

Users of the data only need Setup. These scripts built the store from the raw release files and are kept as the record of how it was made. Several still carry my  machine's original paths.

| Step | Script | What it does |
|---|---|---|
| 1 | `code/01_collect_raw.R`, `code/01b_collect_2025.sh` | Collect the raw release files (polygons, 2005-2025) into `data/raw/<year>/` and record which release file each year/county came from. |
| 2 | `code/02_standardize.R` | Build the standardized polygon store read by `read_parcels()`. |
| 3 | `code/03_verify_store.R` | Check every polygon partition against its source file (`docs/store_verification.csv`). |
| 4 | `code/04_fix_points.R` | Recompute the stored label points (`pt_x`, `pt_y`) in every partition. |
| 5 | `code/05_shapefile_schema.R` | Record the shapefile field lists for 2021 and 2024, which are stored from a GeoPackage and a geodatabase, so `as_shapefile = TRUE` can match the shapefiles. |
| 6 | `code/07_points_store.R` | Build the Points store from the county-published Points layers. |
| 7 | `code/08_verify_points.R` | Check every Points partition against its source (`docs/points_verification.csv`). |
| 8 | `code/11_zenodo_package.sh` | Package the store into the Zenodo zips and checksums. |
| 9 | `code/13_known_gaps.py` | List every column that is entirely blank or zero in a year and county (`docs/known_gaps.csv`). |
| 10 | `code/14_use_class_map.py` | Map each county's `use_class1` labels to a property type for `estimate_tax_cap()` (`docs/use_class_map.csv`). |
| 11 | `code/15_check_tax_cap.R` | Compare `estimate_tax_cap()` with every county-year's published tax capacity (`docs/tax_capacity_check.csv`). |

`code/06`, `09`, `10` and `12` are local disk-cleanup tools that removed duplicate copies of the parcel files from other projects once they read the store.

## Data

The data are not in this repository. They go in `data/` (not tracked).

| Data | Source | Files |
|---|---|---|
| Standardized store, polygons and Points, 2005-2025 | Zenodo, DOI [10.5281/zenodo.24116899](https://doi.org/10.5281/zenodo.24116899) (10 GB, one zip per year and layer) | `data/standardized/`, `data/standardized_points/` |
| Raw release files (build input only) | MetroGIS Regional Parcel Dataset, once published on the Minnesota Geospatial Commons. Those archive links no longer resolve, and Metropolitan Council GIS holds the archive. | `data/raw/<year>/` |
| Column crosswalks | Built by `code/02_standardize.R` and `code/07_points_store.R` | `docs/column_crosswalk.csv`, `docs/points_column_crosswalk.csv` |

The source data are public domain under the Minnesota Government Data Practices Act (Minn. Stat. Ch. 13).

## Folders

- `R/` the R reader (`read_parcels.R`), the downloader (`download_parcels.R`), the column lister (`parcel_columns.R`), the tax capacity estimator (`estimate_tax_cap.R`), `collapse_condos.R` and `verify_read.R`.
- `python/` the Python reader and downloader with the same options, plus the dtype manifests the `names = "original"` view needs.
- `code/` the build and cleanup scripts above.
- `verification/` per-project checks that each repointed script reads identical data from the store.
- `docs/` column crosswalks, schema inventory, verification and write logs, `STATUS.md` (running build log and decisions), `REPOINTING.md`, and the Zenodo deposit README and checksums.

## Versions

| Version | What it is |
|---|---|
| Zenodo 1.0.0 | First deposit: polygons and Points, 2005-2025 (DOI 10.5281/zenodo.24116899) |

## Citation

Cite the Zenodo deposit (see `CITATION.cff`) and the MetroGIS Regional Parcel Dataset, developed by the seven metro counties and the Metropolitan Council.
