# parcel_data

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24116899.svg)](https://doi.org/10.5281/zenodo.24116899)

This repository builds and reads one store of the MetroGIS / Metropolitan Council regional parcel releases for the Twin Cities 7-county area (Anoka, Carver, Dakota, Hennepin, Ramsey, Scott, Washington), file years 2005-2025, so every project reads one verified copy instead of keeping its own shapefiles. Each year's county files are standardized into Hive-partitioned GeoParquet (`year=YYYY/county=Name/`), with values kept as published and column names merged by concept across years, and the county-published Points layers are stored alongside the polygons. 

The goal of this dataset is to make it easier for researchers to pull parcel data across space and time that is unified and standardized making it easy to compare and store the data. It offers the ability to open multiple projects without having to copy the data into each project, freeing up storage, and increasing efficiency. Every one of the 147 polygon partitions and 147 Points partitions reads back identical to its source file (same rows, attributes and geometry). The data is stored on Zenodo, and `download_parcels()` fetches the years a project needs.

The readers are the R package and the Python package `parceldata`, built from `R/` and `python/parceldata/`. Both take the same options and return the same data.

## Setup

These steps are the same on Windows, Mac and Linux. The R steps are all pasted into R. In Python, the install runs in a terminal, and everything after it is pasted into Python.

1. **Install the package.** Do this once.

   R, paste into the R console:
   ```r
   install.packages("remotes")
   remotes::install_github("MatthewHockert/parcel_data", upgrade = "never")
   ```
   Python, run in a terminal (Terminal on Mac, PowerShell on Windows):
   ```
   pip install git+https://github.com/MatthewHockert/parcel_data
   ```
   In a Jupyter notebook, put `%pip install git+https://github.com/MatthewHockert/parcel_data` in a cell instead. This needs Git. If pip says it cannot find `git`, install Git from [git-scm.com](https://git-scm.com), or install from the zip, which needs no Git: `pip install https://github.com/MatthewHockert/parcel_data/archive/refs/heads/main.zip`.

   Both install everything the package uses. In R, `library(parceldata)` also loads sf, dplyr and ggplot2, so they are ready to use. In Python, matplotlib, geopandas and pandas are installed, and you import them as usual.
2. **Download the years you need.** Each zip has all 7 counties and is checked against its published checksum before it is unzipped.

   R:
   ```r
   library(parceldata)
   download_parcels(2014:2016)                 # polygons
   download_parcels(2021, layer = "points")    # points, plus that year's polygons
   ```
   Python:
   ```python
   from parceldata import read_parcels, download_parcels
   download_parcels([2014, 2015, 2016])
   download_parcels(2021, layer="points")      # points, plus that year's polygons
   ```
   The files go in a standard folder for your account, which `download_parcels()` prints and `parcel_data_dir()` returns. R and Python use the same folder, so a year downloaded in one is there for the other. Years already downloaded are skipped.

   Downloads from Zenodo run slowly. For example, one year's polygons (300-600 MB) take about 5-10 minutes, and all 21 years of both layers (10 GB) may take several hours, so fetch only the years you need. Standardized Points reads place each point on its parcel polygon, so a Points download also fetches that year's polygons. `point_location = "published"` keeps the points where the county published them.
3. **Map one county and year to check it works.** This colors Ramsey County's 2016 parcels by estimated market value, on a log scale because a few large parcels are worth far more than the rest. Parcels with no value are left out.

   R:
   ```r
   p <- read_parcels(2016, "Ramsey", cols = "emv_total", filter = quote(emv_total > 0))
   ggplot(p) +
     geom_sf(aes(fill = emv_total), color = NA) +
     scale_fill_viridis_c(trans = "log10", labels = scales::label_dollar()) +
     labs(title = "Ramsey County 2016, estimated market value", fill = NULL) +
     theme_void()
   ```
   Python:
   ```python
   import numpy as np
   import pyarrow.compute as pc
   p = read_parcels(2016, "Ramsey", cols=["emv_total"], filter=pc.field("emv_total") > 0)
   ax = p.plot(column=np.log10(p["emv_total"]), legend=True, linewidth=0, figsize=(9, 9))
   ax.set_title("Ramsey County 2016, estimated market value (log10 $)")
   ```

**Keeping the files somewhere else.** To use another drive or folder, put this at the top of your script, before downloading or reading. It lasts for that session.
```r
parcel_data_dir("F:/parcels")      # R
```
```python
from parceldata import parcel_data_dir
parcel_data_dir("F:/parcels")      # Python
```

**Updating.** Run the install line in step 1 again.

## Functions and examples

R and Python have the same functions with the same arguments, and return the same data. The examples show R code, the Python version, and the first rows R prints.

| Function | What it does |
|---|---|
| `download_parcels()` | Downloads years from Zenodo into the data folder, checking each file's checksum. |
| `parcel_data_dir()` | Shows, or sets for this session, the folder the parcel files are kept in. |
| `parcel_columns()` | Lists the columns, their types and the years they are recorded, with no data needed. |
| `read_parcels()` | Reads any years, counties and columns as polygons, points or a plain table. |
| `get_sales()` | Builds a sales history: one row per parcel sale, with the assessor values at the time. |
| `estimate_tax_cap()` | Estimates net tax capacity from market value, property type and homestead status. |
| `parcel_collapse_condos()` | Rolls stacked condo unit points up to one row per building polygon. |
| `parcel_linearize()`, `parcel_interior_xy()` | R helpers for geometry: turn curved polygons into straight edges, and find a point inside each polygon. |

### download_parcels()

Downloads one zip per year and layer, checks it against its published checksum, and unzips it into the data folder. Years already there are skipped.

```r
download_parcels(2014:2016)                 # polygons
download_parcels(2021, layer = "points")    # points, plus that year's polygons
```
```python
download_parcels([2014, 2015, 2016])
```
On Windows it prints something like:
```
parcel files are saved in C:/Users/you/AppData/Roaming/R/data/R/parceldata
2014 polygons: downloading
2015 polygons: downloading
2016 polygons: already on disk, skipped
```

### parcel_data_dir()

With no argument, returns the folder the parcel files are read from and saved to. With a folder, uses that folder for the rest of the session. See Setup for the order it checks.

```r
parcel_data_dir()                  # where the files are now
parcel_data_dir("F:/parcels")      # keep them on another drive this session
```
On Windows, `parcel_data_dir()` returns something like:
```
[1] "C:/Users/you/AppData/Roaming/R/data/R/parceldata"
```

### parcel_columns()

Lists every column before anything is downloaded. It reads the crosswalks that come with the package. `empty_in` lists where a column was published but entirely blank or zero (for example `emv_land` in Ramsey 2005). The full list is `inst/extdata/known_gaps.csv`, made by `code/13_known_gaps.py`.

```r
parcel_columns()                                    # every standardized column: type, years recorded, original names
parcel_columns(2014:2016, "Ramsey")                 # columns recorded in those years
parcel_columns(2016, "Ramsey", names = "original")  # that file's own field names, in order
```
```python
from parceldata import parcel_columns
parcel_columns()
```
```
  column     type      years     original_names          empty_in
1 year       integer   2005-2025 (added by read_parcels) ""
2 county     character 2005-2025 (added by read_parcels) ""
3 abb_legal  character 2018-2025 ABB_LEGAL               "Anoka 2018-2025 (missing); Washington 201…
4 acres_deed numeric   2005-2025 ACRES_DEED              "Anoka 2005-2006, 2010 (zero); Dakota 2021…
```

### read_parcels()

Reads the years, counties and columns you ask for, and nothing else, so a single county-year is quick. Polygons come back as an sf object (a GeoDataFrame in Python) in UTM zone 15N (EPSG 26915).

```r
ramsey_2016 <- read_parcels(years = 2016, counties = "Ramsey",
                            cols = c("pin", "emv_land", "emv_total"))
```
```python
from parceldata import read_parcels
ramsey_2016 = read_parcels(years=2016, counties="Ramsey",
                           cols=["pin", "emv_land", "emv_total"])
```
```
  year county              pin emv_land emv_total                       geometry
1 2016 Ramsey 123-013022120066    99300    265100 MULTIPOLYGON (((500680.7 49...
2 2016 Ramsey 123-012822140052    48100    154200 MULTIPOLYGON (((501017 4976...
3 2016 Ramsey 123-052922140003    75100    187600 MULTIPOLYGON (((494760.1 49...
```

Skip the geometry and keep only some rows, here parcels worth over $1 million in 2014-2016:

```r
big <- read_parcels(2014:2016, "Ramsey", cols = c("pin", "emv_total"),
                    geometry = "none", filter = quote(emv_total > 1e6))
```
```python
import pyarrow.compute as pc
big = read_parcels([2014, 2015, 2016], "Ramsey", cols=["pin", "emv_total"],
                   geometry="none", filter=pc.field("emv_total") > 1e6)
```
```
   year county pin              emv_total
1  2014 Ramsey 123-313023130004   5806600
2  2014 Ramsey 123-142922110010   1242000
3  2014 Ramsey 123-173023310015   1285400
```

The county-published Points layers, one point per parcel or condo unit:

```r
pts <- read_parcels(2021, "Ramsey", layer = "points", cols = c("pin", "emv_total"))
```
```python
pts = read_parcels(2021, "Ramsey", layer="points", cols=["pin", "emv_total"])
```
```
  year county              pin emv_total                 geometry
1 2021 Ramsey 123-363023440088    246300 POINT (491516.3 4987126)
2 2021 Ramsey 123-363023440087    267600 POINT (491484.5 4987012)
3 2021 Ramsey 123-363023440086    309800 POINT (491515.7 4987097)
```

`names = "standardized"` (the default) gives one column per concept across years, and `names = "original"` returns exactly what `st_read()` of that year's file returned, a drop-in for older scripts. `geometry = "point"` turns polygons into one point each. `bbox` keeps parcels inside an area.

### get_sales()

Builds a sales history. Each yearly assessor file lists only a parcel's most recent sale (`sale_date`, `sale_value`), and that sale repeats in every later file until the parcel sells again. `get_sales()` stacks the files and keeps one row per county, PIN and sale date. Each sale gets the assessor values (market value, tax capacity, property type, homestead, year built and so on) from the first file that lists it, which is the assessment closest to the sale.

```r
s <- get_sales(2014:2024, "Ramsey", sale_years = 2020:2024)
s |> filter(sale_value > 0, emv_total > 0) |>
  select(pin, sale_date, sale_value, file_year, emv_total, use_class1)
```
```python
from parceldata import get_sales
s = get_sales(list(range(2014, 2025)), "Ramsey", sale_years=range(2020, 2025))
s[(s.sale_value > 0) & (s.emv_total > 0)][["pin", "sale_date", "sale_value", "file_year", "emv_total", "use_class1"]]
```
```
  pin              sale_date  sale_value file_year emv_total use_class1
1 123-0125M19090   2022-05-19      42900      2024     11100 1A/1B/4BB RESIDENTIAL SINGLE UNIT
2 123-0125M27200   2024-03-14      75000      2024     51000 1A/1B/4BB RESIDENTIAL SINGLE UNIT
3 123-012822110002 2021-10-15     302000      2021    244500 Res 1 unit
```

Columns: `sale_date`, `sale_year`, `sale_value`, `file_year` (the file the values come from), `value_lag_years` (`file_year` minus `sale_year`), `n_files` (how many files list the sale), then the values in `cols`. Add `geometry = "polygon"` or `"point"` for a map.

What to know:
- The files record no sale or deed type, so arm's-length sales cannot be told from others. `sale_value` of 0 or missing is kept, so filter it yourself.
- Two sales of one parcel between two yearly files show up as the later one only.
- Sales before the first file year searched take their values from that first file, so check `value_lag_years`.
- Rows with no PIN are dropped, and so are sale dates later than the file's own year (for example 8200 in Ramsey 2010). The number dropped is printed.
- Hennepin records sale dates to the month (always the 1st).
- All 7 counties and 21 years, 2.2 million sales, takes about 4 minutes.

### estimate_tax_cap()

Some counties did not publish tax capacity for many years (Ramsey `tax_capac` is 0 for 2005-2020). `estimate_tax_cap()` fills it in from market value, property type and homestead status, using Hennepin County's 2025-assessment class rates.

```r
p <- read_parcels(2005:2020, "Ramsey", cols = c("pin", "use_class1", "homestead", "emv_total"))
p <- estimate_tax_cap(p)   # adds prop_type, homestead_status, tmv_est, tax_capac_est
```
```python
from parceldata import estimate_tax_cap
p = estimate_tax_cap(read_parcels(list(range(2005, 2021)), "Ramsey",
                                  cols=["pin", "use_class1", "homestead", "emv_total"]))
```
```
  pin              use_class1 homestead emv_total prop_type tmv_est tax_capac_est
1 123-013022120066 Res 1 unit Y            265100 R          251719         2517.
2 123-012822140052 Res 1 unit Y            154200 R          130838         1308.
3 123-052922140003 Res 1 unit Y            187600 R          167244         1672.
```

**Warning:** the 2025 class rates are applied to every year, so earlier years are priced at 2025 rates. The homestead exclusion and each county's value timing do follow the year. Across every county-year with published values, a median 86-93% of parcels are within 1%, except Ramsey, whose published values look wrong. Dakota and Carver publish commercial-industrial tax capacity after the fiscal disparities contribution, and the estimate is before it. Prefer a county's published `tax_capac` where it exists. Method, rate table and checks: `docs/tax_capacity.md`.

### parcel_collapse_condos()

The Points layers have one point per condo unit, stacked on one building. This rolls them up to one row per building polygon: values such as `emv_total` and `num_units` are summed, `n_units` counts the units, and `unit_pins` lists their PINs. The easiest way is through `read_parcels()`.

```r
condo <- read_parcels(2021, "Ramsey", layer = "points", cols = c("pin", "emv_total"),
                      collapse_condos = TRUE)
```
```python
condo = read_parcels(2021, "Ramsey", layer="points", cols=["pin", "emv_total"],
                     collapse_condos=True)
```
```
  pin              n_units emv_total                 geometry
1 123-312922431577     598  52036000 POINT (492446.3 4977424)
2 123-312922431580     288  35444800   POINT (492514 4977320)
3 123-163023340017     284  15921100 POINT (485607.4 4992075)
```
(the three largest buildings, sorted by `n_units`)

## Data

The data are not in this repository. They go in `data/` (not tracked).

| Data | Source | Files |
|---|---|---|
| Standardized store, polygons and Points, 2005-2025 | Zenodo, DOI [10.5281/zenodo.24116899](https://doi.org/10.5281/zenodo.24116899) (10 GB, one zip per year and layer) | `data/standardized/`, `data/standardized_points/` |
| Raw release files (build input only) | MetroGIS Regional Parcel Dataset, once published on the Minnesota Geospatial Commons. Those archive links no longer resolve, and Metropolitan Council GIS holds the archive. | `data/raw/<year>/` |
| Column crosswalks | Built by `code/02_standardize.R` and `code/07_points_store.R` | `inst/extdata/column_crosswalk.csv`, `inst/extdata/points_column_crosswalk.csv` |

The source data are public domain under the Minnesota Government Data Practices Act (Minn. Stat. Ch. 13).

## Folders

- `R/` the R package: the reader (`read_parcels.R`), the downloader (`download_parcels.R`), the column lister (`parcel_columns.R`), the sales history builder (`get_sales.R`), the tax capacity estimator (`estimate_tax_cap.R`), `collapse_condos.R`, and where files are kept (`paths.R`). `verify_read.R` is a build tool, left out of the package. `DESCRIPTION` and `NAMESPACE` make the repository installable with `remotes::install_github()`.
- `inst/extdata/` the lookup tables both packages ship with: column crosswalks, the shapefile schema, known gaps, the class rate table and use-class map, the dtype manifests the `names = "original"` view needs, and the Zenodo checksums.
- `python/parceldata/` the Python package, with the same options. `pyproject.toml` makes it installable with pip. The `python/*.py` files next to it keep older `from read_parcels import ...` scripts working, and `python/build_*_manifest.py` build the dtype manifests.
- `code/` the build and cleanup scripts above.
- `verification/` per-project checks that each repointed script reads identical data from the store.
- `docs/` schema inventory, verification and write logs, `STATUS.md` (running build log and decisions), `REPOINTING.md`, the tax capacity method, and the Zenodo deposit README.

## Versions

| Version | What it is |
|---|---|
| Zenodo 1.0.0 | First deposit: polygons and Points, 2005-2025 (DOI 10.5281/zenodo.24116899) |

## Citation

Cite the Zenodo deposit (see `CITATION.cff`) and the MetroGIS Regional Parcel Dataset, developed by the seven metro counties and the Metropolitan Council.

## How to recreate the package

Users of the data only need Setup. These scripts built the store on Zenodo from the raw release files and are kept as the record of how it was made. Paths in them point to `PARCEL_HOME` and to `~` (the home folder). They run from a clone of this repository with the `PARCEL_HOME` environment variable set to the clone, and load the R files with `source(file.path(Sys.getenv("PARCEL_HOME"), "R/read_parcels.R"))`. With `PARCEL_HOME` set, the installed packages also read and download into `<PARCEL_HOME>/data`.

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
| 9 | `code/13_known_gaps.py` | List every column that is entirely blank or zero in a year and county (`inst/extdata/known_gaps.csv`). |
| 10 | `code/14_use_class_map.py` | Map each county's `use_class1` labels to a property type for `estimate_tax_cap()` (`inst/extdata/use_class_map.csv`). |
| 11 | `code/15_check_tax_cap.R` | Compare `estimate_tax_cap()` with every county-year's published tax capacity (`docs/tax_capacity_check.csv`). |

`code/06`, `09`, `10` and `12` are local disk-cleanup tools that removed duplicate copies of the parcel files from other projects once they read the store.
