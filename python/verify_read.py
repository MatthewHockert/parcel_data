"""verify_read.py -- Python twin of R/verify_read.R::compare_reads.

compare_reads(old, new, label, key=None, geom_tol=None, shp_losses=False,
              shp_side="old") -> dict (one results row)

  rows     same number of rows
  names    same column names in the same order
  values   per column: identical, or numbers equal within 1e-9 relative
  geometry identical WKB per row; or, with geom_tol, rows whose WKB differs
           pass if the Hausdorff distance is <= geom_tol metres (curves are
           already linearized by GDAL on the Python side)

key="PIN": rows aligned by key, ties broken by the bounding-box corner rounded
to 1 m (as in R); Shape_Length vs Shape_Leng and the geometry column name are
ignored; `new` is reduced to `old`'s columns.

shp_losses=True allows exactly the shapefile format's known losses (R rule,
Matt 2026-11-07): a missing number on the non-shapefile side may be 0 on the
shapefile side; dates/date-times compare at day precision; text is compared
after trimming spaces, and "" on the non-shapefile side may be NA on the
shapefile side. In R the shapefile is always `old`; `shp_side` says which side
is the shapefile here ("old" as in R, or "new" when the store holds the
shapefile release and the old read is a GeoPackage/geodatabase).
Each loss actually used is counted and reported in `losses_used`.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import geopandas as gpd
import shapely


def _corner(d):
    if not isinstance(d, gpd.GeoDataFrame):
        n = np.arange(len(d))
        return n, n
    b = shapely.bounds(d.geometry.values)  # NaN for empty / None
    return np.round(b[:, 0]), np.round(b[:, 1])


def _is_time(s):
    return pd.api.types.is_datetime64_any_dtype(s)


def _to_utc_ns(s):
    t = pd.to_datetime(s, utc=True) if _is_time(s) else s
    return t


def compare_reads(old, new, label="", key=None, geom_tol=None, shp_losses=False, shp_side="old"):
    losses = {}
    if key is not None:
        co, cn = _corner(old), _corner(new)
        o_ord = np.lexsort((co[1], co[0], old[key].astype(str).to_numpy()))
        n_ord = np.lexsort((cn[1], cn[0], new[key].astype(str).to_numpy()))
        old = old.iloc[o_ord].reset_index(drop=True)
        new = new.iloc[n_ord].reset_index(drop=True)
        if "Shape_Length" in old.columns and "Shape_Leng" in new.columns:
            old = old.rename(columns={"Shape_Length": "Shape_Leng"})
        if "Shape_Leng" in old.columns and "Shape_Length" in new.columns:
            new = new.rename(columns={"Shape_Length": "Shape_Leng"})
    g_old = old.geometry.values if isinstance(old, gpd.GeoDataFrame) else None
    g_new = new.geometry.values if isinstance(new, gpd.GeoDataFrame) else None
    a = pd.DataFrame(old.drop(columns=old.geometry.name)) if g_old is not None else pd.DataFrame(old)
    b = pd.DataFrame(new.drop(columns=new.geometry.name)) if g_new is not None else pd.DataFrame(new)
    if key is not None:
        b = b[[c for c in a.columns if c in b.columns]]

    rows_ok = len(a) == len(b)
    names_ok = list(a.columns) == list(b.columns)
    col_diff = []
    if rows_ok:
        for nm in [c for c in a.columns if c in b.columns]:
            x, y = a[nm].reset_index(drop=True), b[nm].reset_index(drop=True)
            # s = shapefile side, o = the other side
            if shp_losses:
                if _is_time(x) or _is_time(y):
                    x = pd.to_datetime(x, utc=True, errors="coerce").dt.floor("D") if (_is_time(x) or x.dtype == object) else x
                    y = pd.to_datetime(y, utc=True, errors="coerce").dt.floor("D") if (_is_time(y) or y.dtype == object) else y
                s, o = (x, y) if shp_side == "old" else (y, x)
                if pd.api.types.is_numeric_dtype(s) and pd.api.types.is_numeric_dtype(o) \
                        and not pd.api.types.is_bool_dtype(s):
                    m = o.isna() & s.notna() & (s == 0)
                    if m.any():
                        losses[nm] = losses.get(nm, 0) + int(m.sum())
                        o = o.astype("float64").copy(); o[m] = 0.0
                if s.dtype == object and o.dtype == object:
                    s = s.map(lambda v: v.strip() if isinstance(v, str) else v)
                    o = o.map(lambda v: v.strip() if isinstance(v, str) else v)
                    m = o.notna() & (o == "") & s.isna()
                    if m.any():
                        losses[nm] = losses.get(nm, 0) + int(m.sum())
                        o = o.copy(); o[m] = None
                x, y = (s, o) if shp_side == "old" else (o, s)
            if _is_time(x) and _is_time(y):
                tx, ty = pd.to_datetime(x, utc=True), pd.to_datetime(y, utc=True)
                same = bool((tx.isna() == ty.isna()).all() and (tx[tx.notna()] == ty[tx.notna()]).all())
                # R also requires the same kind (Date vs date-time); pandas has one
                # datetime kind, so dtype must match unless losses were allowed
                if not shp_losses and str(x.dtype) != str(y.dtype):
                    same = False
            elif pd.api.types.is_numeric_dtype(x) and pd.api.types.is_numeric_dtype(y) \
                    and not pd.api.types.is_bool_dtype(x):
                xv, yv = x.to_numpy(dtype="float64"), y.to_numpy(dtype="float64")
                na_x, na_y = np.isnan(xv), np.isnan(yv)
                same = bool((na_x == na_y).all() and np.allclose(xv[~na_x], yv[~na_x], rtol=1e-9, atol=0))
            else:
                sx = x.map(lambda v: None if v is None or (isinstance(v, float) and np.isnan(v)) else str(v))
                sy = y.map(lambda v: None if v is None or (isinstance(v, float) and np.isnan(v)) else str(v))
                same = bool(((sx.isna() & sy.isna()) | (sx == sy)).all())
            if not same:
                col_diff.append(nm)

    geom_ok, geom_detail = None, ""
    if g_old is not None and g_new is not None and rows_ok:
        wo = shapely.to_wkb(g_old)
        wn = shapely.to_wkb(g_new)
        if geom_tol is None:
            geom_ok = bool(all(p == q for p, q in zip(wo, wn)))
        else:
            diff = np.array([p != q for p, q in zip(wo, wn)])
            go, gn = g_old[diff], g_new[diff]
            eo = pd.isna(go) | shapely.is_empty(go)
            en = pd.isna(gn) | shapely.is_empty(gn)
            both = ~eo & ~en
            hd = shapely.hausdorff_distance(go[both], gn[both]) if both.any() else np.array([])
            bad = int((eo != en).sum() + (hd > geom_tol).sum())
            geom_ok = bad == 0
            geom_detail = (f"{int(diff.sum())} rows differ in WKB; {bad} beyond {geom_tol:g} m "
                           f"(max {hd.max() if len(hd) else 0:.2f} m)")
    ok = rows_ok and names_ok and not col_diff and geom_ok is not False
    return dict(label=label, rows_old=len(a), rows_new=len(b), rows_ok=rows_ok, names_ok=names_ok,
                cols_differ=", ".join(col_diff), geom_ok=geom_ok, geom_detail=geom_detail,
                losses_used="; ".join(f"{k}:{v}" for k, v in losses.items()), ok=ok)
