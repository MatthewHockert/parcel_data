#!/usr/bin/env python3
"""13_known_gaps.py: list every column that is entirely blank or entirely zero in a
year x county, for the polygon and Points stores. Writes docs/known_gaps.csv.

Only columns the county's file actually carried that year (docs/column_crosswalk.csv,
docs/points_column_crosswalk.csv) are checked, so a field a county never published is
not listed here (it is simply absent from that year in parcel_columns()). The store keeps
values as published, so every gap here is in the county's release, not the store.

Run:  python3 -I code/13_known_gaps.py
"""
import glob, os, re
import pandas as pd
import pyarrow.parquet as pq

PD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORES = {"polygons": ("standardized", "column_crosswalk.csv"),
          "points": ("standardized_points", "points_column_crosswalk.csv")}

rows = []
for layer, (store, xw_file) in STORES.items():
    xw = pd.read_csv(os.path.join(PD, "docs", xw_file))
    for f in sorted(glob.glob(os.path.join(PD, "data", store, "year=*", "county=*", "part-0.parquet"))):
        yr, cty = re.search(r"year=(\d+)/county=(\w+)", f).groups()
        rec = xw[(xw.year == int(yr)) & (xw.county == cty)]
        avail = set(pq.read_schema(f).names)
        cols = [c for c in pd.unique(rec.std_name) if c in avail]
        d = pq.read_table(f, columns=cols).to_pandas()
        n = len(d)
        for c in cols:
            v = d[c]
            if v.isna().all():
                issue = "all missing"
            elif pd.api.types.is_numeric_dtype(v) and (v.fillna(0) == 0).all():
                issue = "all zero"
            elif v.dtype == object and v.fillna("").astype(str).str.strip().eq("").all():
                issue = "all missing"
            else:
                continue
            orig = ", ".join(rec.loc[rec.std_name == c, "original_name"].unique())
            rows.append((layer, int(yr), cty, c, orig, issue, n))

out = pd.DataFrame(rows, columns=["layer", "year", "county", "column", "original_name", "issue", "rows"])
out = out.sort_values(["layer", "column", "county", "year"]).reset_index(drop=True)
out.to_csv(os.path.join(PD, "docs", "known_gaps.csv"), index=False)
print(f"{len(out)} empty column x year x county cells written to docs/known_gaps.csv")
print(out.groupby(["layer", "issue"]).size().to_string())
