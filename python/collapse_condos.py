"""collapse_condos(points, polygons): Python twin of R/collapse_condos.R.

Rolls the county-published unit points (condo units stacked on one building) up
to ONE row per polygon. Used by read_parcels(..., layer="points", collapse_condos=True).
Rules (Matt, 2026-11-08):
  - each point is assigned to the polygon it falls in (same year / county); if it
    falls in several (stacked condo polygons, 2018+), the first
  - additive fields are SUMMED: emv_land, emv_bldg, emv_total, tax_capac,
    total_tax, spec_asses, fin_sq_ft, num_units, sale_value
  - n_units = number of points combined
  - every other field takes the MOST COMMON non-missing value among the units
    (ties: the first seen). Where units disagree a <col>_n_distinct column says
    how many distinct values there were (only for columns where that happens)
  - pin = the polygon's PIN, unit_pins = the unit PINs joined by ";"
  - geometry = one point per polygon (centroid, moved inside if outside)
  - points inside no polygon are kept as their own rows, unmatched = True
Works on the STANDARDIZED view (lower-case names).
"""
import numpy as np
import pandas as pd
import geopandas as gpd
import shapely

ADDITIVE = ["emv_land", "emv_bldg", "emv_total", "tax_capac", "total_tax",
            "spec_asses", "fin_sq_ft", "num_units", "sale_value"]


def _mode(v):
    v = v[v.notna()]
    if not len(v):
        return None
    counts = v.value_counts(sort=False)  # first-seen order, as R's unique()
    return counts.index[int(np.argmax(counts.to_numpy()))]


def collapse_condos(points, polygons):
    from read_parcels import _make_valid_sf
    if "pin" not in points.columns or "pin" not in polygons.columns:
        raise ValueError("points and polygons need a pin column")
    pg = _make_valid_sf(np.asarray(polygons.geometry.values, dtype=object))
    pgeom = np.asarray(points.geometry.values, dtype=object)
    pt_idx, poly_idx = shapely.STRtree(pg).query(pgeom, predicate="intersects")
    first = pd.Series(poly_idx).groupby(pt_idx).min()
    poly_of = np.full(len(points), -1)
    poly_of[first.index.to_numpy()] = first.to_numpy()

    pts = pd.DataFrame(points.drop(columns=points.geometry.name))
    pts["_poly"] = poly_of
    matched = pts[pts._poly >= 0]
    unmatched = pts[pts._poly < 0].copy()
    attr_cols = [c for c in matched.columns if c not in ("_poly", "pin", "year", "county")]

    sizes = matched.groupby("_poly", sort=True).size()
    multi_ids = set(sizes.index[sizes > 1])
    single = matched[~matched._poly.isin(multi_ids)].copy()
    single = single.set_index("_poly", drop=False).loc[sorted(set(sizes.index) - multi_ids)].reset_index(drop=True)
    single["n_units"] = 1
    single["unit_pins"] = single["pin"]

    rows = []
    for pid, d in matched[matched._poly.isin(multi_ids)].groupby("_poly", sort=True):
        r = d.iloc[0].to_dict()
        for c in attr_cols:
            v = d[c]
            if c in ADDITIVE and pd.api.types.is_numeric_dtype(v):
                r[c] = np.nan if v.isna().all() else v.sum(skipna=True)
            else:
                r[c] = _mode(v)
                nd = v.dropna().nunique()
                if nd > 1:
                    r[c + "_n_distinct"] = nd
        r["n_units"] = len(d)
        r["unit_pins"] = ";".join(d["pin"].astype(str))
        rows.append(r)
    multi_df = pd.DataFrame(rows) if rows else None

    out = pd.concat([single, multi_df], ignore_index=True) if multi_df is not None else single
    out["pin"] = polygons["pin"].to_numpy()[out["_poly"].to_numpy()]  # the building's PIN
    out["unmatched"] = False
    geom = list(pg[out["_poly"].to_numpy()])

    if len(unmatched):
        unmatched["n_units"] = 1
        unmatched["unit_pins"] = unmatched["pin"]
        unmatched["unmatched"] = True
        out = pd.concat([out, unmatched], ignore_index=True)
        geom += list(pgeom[poly_of < 0])

    # one point per polygon: centroid, moved inside when it falls outside
    geom = np.array(geom, dtype=object)
    is_poly = ~out["unmatched"].to_numpy()
    if is_poly.any():
        g = geom[is_poly]
        cen = shapely.centroid(g)
        inside = shapely.intersects(cen, g)
        inside = np.where(pd.isna(inside), False, inside).astype(bool)
        cen[~inside] = shapely.point_on_surface(g[~inside])
        geom[is_poly] = cen
    out = out.drop(columns=["_poly"])
    for c in [c for c in out.columns if c.endswith("_n_distinct")]:
        out[c] = out[c].fillna(1).astype(int)
    return gpd.GeoDataFrame(out, geometry=gpd.GeoSeries(geom, crs=points.crs), crs=points.crs)
