# parcel_data

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.24116899.svg)](https://doi.org/10.5281/zenodo.24116899)

One store for the MetroGIS / Metropolitan Council regional parcel releases
(Twin Cities 7-county area: Anoka, Carver, Dakota, Hennepin, Ramsey, Scott,
Washington), file years 2005-2025, as Hive-partitioned GeoParquet
(`year=YYYY/county=Name/`), so every project reads one verified copy instead
of keeping its own shapefiles.

**The data are not in this repository.** The built store (10 GB) is on Zenodo,
DOI [10.5281/zenodo.24116899](https://doi.org/10.5281/zenodo.24116899), one zip
per year and layer. The source releases are the public "Regional Parcel
Dataset" files once published on the Minnesota Geospatial Commons (public
domain, Minn. Stat. Ch. 13); those archive links no longer resolve.
`code/01_collect_raw.R` and `code/01b_collect_2025.sh` record which release
file each year/county came from.

## Setup
1. Clone this repository.
2. Set `PARCEL_HOME` to the clone: `PARCEL_HOME=${HOME}/parcel_data` in
   `~/.Renviron` for R, `export PARCEL_HOME="$HOME/parcel_data"` in your shell
   profile for Python.
3. Download the years you need (each zip has all 7 counties; checked
   against `docs/zenodo_md5.txt`, unzipped into `$PARCEL_HOME/data`):
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
   download_parcels(2021, layer="points")      # Python returns the published points
   ```
   In R, standardized Points reads place each point on its polygon, so R
   fetches that year's polygons too; `point_location = "published"` skips it.
4. Install the dependencies: R `sf`, `arrow`, `dplyr`, `tibble`; Python
   `pip install -r python/requirements.txt`.

## Layout
- `code/` – build pipeline, run in order: collect raw files (01), standardize
  to GeoParquet (02), verify every partition against its source (03), fix
  label points (04), shapefile schema (05), published Points layers (07, 08).
  06 and 09 are local disk-cleanup tools.
- `R/download_parcels.R`, `python/download_parcels.py` – fetch years from Zenodo.
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

## Citation
Cite the Zenodo deposit (see `CITATION.cff`) and the MetroGIS Regional Parcel
Dataset, developed by the seven metro counties and the Metropolitan Council.
