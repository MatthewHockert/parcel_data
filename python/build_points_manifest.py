"""build_points_manifest.py

Points-layer twin of build_original_manifest.py: records, for every partition
of the POINTS store (code/07_points_store.R), what geopandas/pyogrio
`read_file` returns for the published Points layer, so
read_parcels(layer="points", names="original") can rebuild pyogrio's exact
pandas dtypes.

Inputs : the sources in docs/points_sources.csv (the same copies 07 read)
Outputs: python/points_original_dtypes.csv   (year, county, column, dtype, n_null, n_zero_date)
         python/points_original_geometry.csv (year, county, driver, geometry_type, n_rows, z_all_zero)
Run:     /Users/matthewhockert/packaging-test/pkg-test/bin/python python/build_points_manifest.py [years ...]
A partial run replaces only its own years. Sources must be local (not
iCloud placeholders); 07/08 download them first.
"""
import os, sys, gc
import numpy as np
import pandas as pd
import pyogrio
import shapely

HOME = os.environ.get("PARCEL_HOME", "/Users/matthewhockert/research/parcel_data")
OUT_D = os.path.join(HOME, "python", "points_original_dtypes.csv")
OUT_G = os.path.join(HOME, "python", "points_original_geometry.csv")
COUNTIES = ["Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington"]


def main(years):
    src = pd.read_csv(os.path.join(HOME, "docs", "points_sources.csv"))
    xw = pd.read_csv(os.path.join(HOME, "docs", "points_column_crosswalk.csv"))
    src = src[src.year.isin(years)]
    rows_d, rows_g = [], []
    for _, s in src.iterrows():
        yr, cty, path, layer = int(s.year), s.county, s.source, s.layer
        info = pyogrio.read_info(path, layer=layer)
        df = pyogrio.read_dataframe(path, layer=layer, read_geometry=False)
        rt = xw[(xw.year == yr) & (xw.county == cty)].set_index("original_name")["r_type"]
        for c in df.columns:
            v = df[c]
            n_zero = 0
            if v.dtype == object and rt.get(c) in ("Date", "POSIXct"):
                n_zero = int((v == "0000/00/00").sum())
            rows_d.append(dict(year=yr, county=cty, column=c, dtype=str(v.dtype),
                               n_null=int(v.isna().sum()), n_zero_date=n_zero))
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
    if os.path.exists(OUT_D) and os.path.exists(OUT_G):
        od, og = pd.read_csv(OUT_D), pd.read_csv(OUT_G)
        d = pd.concat([od[~od.year.isin(years)], d]); g = pd.concat([og[~og.year.isin(years)], g])
    for t, out in ((d, OUT_D), (g, OUT_G)):
        t = t.assign(_c=t.county.map(COUNTIES.index)).sort_values(["year", "_c"], kind="stable").drop(columns="_c")
        t.to_csv(out + ".tmp", index=False); os.replace(out + ".tmp", out)


if __name__ == "__main__":
    yrs = [int(a) for a in sys.argv[1:]] or list(range(2005, 2026))
    main(yrs)
