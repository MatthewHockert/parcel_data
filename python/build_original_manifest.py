"""build_original_manifest.py

Records, for every stored partition, what geopandas/pyogrio `read_file` returns
for the ORIGINAL source file, so read_parcels.py (names="original") can rebuild
pyogrio's exact pandas dtypes and geometry form. R's crosswalk r_type cannot
say this on its own: R "numeric" is pyogrio int64 OR float64, pyogrio turns an
integer column with nulls into float64, and a shapefile date column holding
"0000/00/00" comes back from pyogrio as text.

Inputs : data/raw/<year>/... (the same sources code/02_standardize.R read;
         2021 from the GeoPackage, 2023 and 2024 from the geodatabases, 2025 = Parcels{County}.shp)
Outputs: inst/extdata/original_dtypes.csv   (year, county, column, dtype, n_null, n_zero_date)
         inst/extdata/original_geometry.csv (year, county, driver, geometry_type, n_rows, z_all_zero)
Fully regenerable:  <pkg-test python> python/build_original_manifest.py
Reads one partition at a time (attributes without geometry; geometry only to
check Z values on Z-typed shapefiles).
"""
import os, sys, gc
import numpy as np
import pandas as pd
import pyogrio
import shapely

HOME = os.environ["PARCEL_HOME"]
RAW = os.path.join(HOME, "data", "raw")
OUT_D = os.path.join(HOME, "inst", "extdata", "original_dtypes.csv")
OUT_G = os.path.join(HOME, "inst", "extdata", "original_geometry.csv")
COUNTIES = ["Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington"]
GDB_YEARS = (2023, 2024)


def source(year, county):
    if year == 2021:  # store's 2021 rebuilt from the GeoPackage (Matt, 2026-11-07)
        return os.path.join(RAW, "2021", "plan_regonal_parcels_2021.gpkg"), f"Parcels2021{county}"
    if year in GDB_YEARS:
        return os.path.join(RAW, str(year), f"plan_regonal_parcels_{year}.gdb"), f"Parcels{year}{county}"
    if year == 2025:
        return os.path.join(RAW, "2025", f"Parcels{county}.shp"), None
    return os.path.join(RAW, str(year), f"Parcels{year}{county}.shp"), None


def main(years):
    xw = pd.read_csv(os.path.join(HOME, "inst", "extdata", "column_crosswalk.csv"))
    rows_d, rows_g = [], []
    for yr in years:
        for cty in COUNTIES:
            path, layer = source(yr, cty)
            if not os.path.exists(path):
                print("missing", path, file=sys.stderr); continue
            info = pyogrio.read_info(path, layer=layer)
            df = pyogrio.read_dataframe(path, layer=layer, read_geometry=False)
            rt = xw[(xw.year == yr) & (xw.county == cty)].set_index("original_name")["r_type"]
            for c in df.columns:
                s = df[c]
                n_zero = 0
                if s.dtype == object and rt.get(c) in ("Date", "POSIXct"):
                    n_zero = int((s == "0000/00/00").sum())
                rows_d.append(dict(year=yr, county=cty, column=c, dtype=str(s.dtype),
                                   n_null=int(s.isna().sum()), n_zero_date=n_zero))
            z_zero = ""
            if info["geometry_type"].endswith(" Z"):
                g = pyogrio.read_dataframe(path, layer=layer, columns=[]).geometry.values
                z = shapely.get_coordinates(g, include_z=True)[:, 2]
                z_zero = bool(np.all(z == 0))
                del g, z
            rows_g.append(dict(year=yr, county=cty, driver=info["driver"],
                               geometry_type=info["geometry_type"], n_rows=len(df), z_all_zero=z_zero))
            print(yr, cty, len(df), info["geometry_type"], flush=True)
            del df; gc.collect()
    d, g = pd.DataFrame(rows_d), pd.DataFrame(rows_g)
    # merge with any existing manifest (so a partial rerun only replaces its years)
    if os.path.exists(OUT_D) and os.path.exists(OUT_G):
        od, og = pd.read_csv(OUT_D), pd.read_csv(OUT_G)
        d = pd.concat([od[~od.year.isin(years)], d]); g = pd.concat([og[~og.year.isin(years)], g])
    d.sort_values(["year", "county"], kind="stable").to_csv(OUT_D, index=False)
    g.sort_values(["year", "county"], kind="stable").to_csv(OUT_G, index=False)


if __name__ == "__main__":
    yrs = [int(a) for a in sys.argv[1:]] or list(range(2005, 2026))
    main(yrs)
