"""scenic-quality_verify.py -- verify the repointed parcel read in
~/Desktop/Personal Info/scenic-quality/scripts/clean_parcels.py (load_counties).

Old read (the script before repointing, line 879):
    gpd.read_file("/vsizip/<repo>/data/parcels/gpkg_plan_regonal_parcels_2021.zip/
                   plan_regonal_parcels_2021.gpkg", layer="Parcels2021{County}")
New read (line 882 after repointing):
    read_parcels(years=2021, counties=county, names="original")

The store's 2021 is built from the same 2021 GeoPackage (Matt, 2026-11-07), so
the comparison is EXACT per county (default compare_reads: same rows in the
same order, names, values, WKB geometry), plus pandas dtypes, index, CRS and
geometry column name.
Plus a self-test that the Python original view equals geopandas read_file of
the raw 2017 Ramsey shapefile (exact) and matches R's original view on a few
columns (via Rscript, if available).

Run: /Users/matthewhockert/packaging-test/pkg-test/bin/python \
     /Users/matthewhockert/research/parcel_data/verification/scenic-quality_verify.py
Results: verification/scenic-quality_results.csv
"""
import gc
import os
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd
import geopandas as gpd

sys.path.insert(0, os.path.join(os.environ["PARCEL_HOME"], "python"))
from read_parcels import read_parcels  # noqa: E402
from verify_read import compare_reads  # noqa: E402

HOME = "/Users/matthewhockert/research/parcel_data"
REPO = "/Users/matthewhockert/Desktop/Personal Info/scenic-quality"
ZIP = f"{REPO}/data/parcels/gpkg_plan_regonal_parcels_2021.zip"
VSI = f"/vsizip/{ZIP}/plan_regonal_parcels_2021.gpkg"
COUNTIES = ["Anoka", "Carver", "Dakota", "Hennepin", "Ramsey", "Scott", "Washington"]
# copied from clean_parcels.py (KEEP_COLS)
KEEP_COLS = [
    "EMV_TOTAL", "EMV_LAND", "EMV_BLDG", "MKT_YEAR",
    "USECLASS1", "USECLASS2", "USECLASS3", "USECLASS4",
    "TAX_EXEMPT", "HOMESTEAD", "OWNERSHIP",
    "FIN_SQ_FT", "YEAR_BUILT", "NUM_UNITS", "DWELL_TYPE", "HOME_STYLE",
    "GARAGE", "GARAGESQFT", "BASEMENT", "HEATING", "COOLING",
    "ACRES_POLY", "ACRES_DEED",
    "SALE_DATE", "SALE_VALUE",
    "CO_NAME", "CTU_NAME", "ZIP", "SCHOOL_DST", "COUNTY_PIN", "PIN",
]
OUT = f"{HOME}/verification/scenic-quality_results.csv"


def keep(gdf):
    present = [c for c in KEEP_COLS if c in gdf.columns]   # as load_counties does
    return gdf[present + [gdf.geometry.name]].copy()


def self_test():
    rows = []
    shp = f"{HOME}/data/raw/2017/Parcels2017Ramsey.shp"
    old = gpd.read_file(shp)
    new = read_parcels(2017, "Ramsey", names="original")
    r = compare_reads(old, new, label="selftest 2017 Ramsey: python original view vs read_file(raw shp)")
    dt = [c for c in old.columns if c in new.columns and old[c].dtype != new[c].dtype]
    r["note"] = "dtype mismatches: " + (", ".join(dt) if dt else "none")
    r["ok"] = r["ok"] and not dt
    rows.append(r)
    # R's original view, a few columns
    cols = ["PIN", "EMV_TOTAL", "YEAR_BUILT", "GARAGESQFT", "SALE_DATE", "CITY"]
    tmp = tempfile.mktemp(suffix=".csv")
    rcode = (f'source("{HOME}/R/read_parcels.R"); '
             f'd <- read_parcels(2017, "Ramsey", cols = c({", ".join(repr(c) for c in cols)}), '
             f'names = "original", geometry = "none"); '
             f'd$SALE_DATE <- format(d$SALE_DATE, "%Y-%m-%d"); '
             f'write.csv(d, "{tmp}", row.names = FALSE, na = "")')
    try:
        subprocess.run(["Rscript", "-e", rcode], check=True, capture_output=True, timeout=600)
        rd = pd.read_csv(tmp, dtype=str, keep_default_na=False)
        os.remove(tmp)
        p = new[cols].copy()
        p["SALE_DATE"] = pd.to_datetime(p["SALE_DATE"], format="%Y/%m/%d", errors="coerce").dt.strftime("%Y-%m-%d")
        bad = []
        for c in cols:
            pv = p[c].map(lambda v: "" if v is None or (isinstance(v, float) and np.isnan(v)) else
                          (str(int(v)) if isinstance(v, (int, float, np.integer, np.floating)) and float(v).is_integer() else str(v)))
            rv = rd[c].map(lambda v: str(int(float(v))) if v not in ("",) and c in ("EMV_TOTAL", "YEAR_BUILT") else v)
            pv = pv.where(pv != "nan", "")
            if not (pv.reset_index(drop=True) == rv.reset_index(drop=True)).all():
                bad.append(c)
        rows.append(dict(label="selftest 2017 Ramsey: python vs R original view (" + ", ".join(cols) + ")",
                         rows_old=len(rd), rows_new=len(p), rows_ok=len(rd) == len(p), names_ok=True,
                         cols_differ=", ".join(bad), geom_ok=None, geom_detail="", losses_used="",
                         note="R side via Rscript; SALE_DATE compared as dates (R NA = python '0000/00/00')",
                         ok=len(rd) == len(p) and not bad))
    except Exception as e:  # Rscript missing / failed
        rows.append(dict(label="selftest 2017 Ramsey: python vs R original view", ok=False,
                         note=f"Rscript failed: {e}"))
    del old, new
    gc.collect()
    return rows


def main():
    rows = self_test()
    for cty in COUNTIES:
        layer = f"Parcels2021{cty}"
        old = gpd.read_file(VSI, layer=layer)                              # OLD read, exactly as the script did
        new = read_parcels(years=2021, counties=cty, names="original")     # NEW read, as repointed (line 882)
        r = compare_reads(old, new, label=f"clean_parcels.py:882 2021 {cty} (exact)")
        dt = [c for c in old.columns if c in new.columns and old[c].dtype != new[c].dtype]
        same_idx = old.index.equals(new.index)
        same_crs = old.crs == new.crs and old.geometry.name == new.geometry.name
        r["note"] = (f"dtype mismatches: {', '.join(dt) if dt else 'none'}; "
                     f"index equal: {same_idx}; crs+geometry name equal: {same_crs}")
        r["ok"] = r["ok"] and not dt and same_idx and same_crs
        rows.append(r)
        print(r["label"], r["ok"], r["cols_differ"], r["note"], flush=True)
        del old, new
        gc.collect()
    df = pd.DataFrame(rows)
    df.to_csv(OUT, index=False)
    print(df[["label", "ok", "cols_differ"]].to_string())


if __name__ == "__main__":
    main()
