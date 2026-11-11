"""read_parcels.py -- Python twin of R/read_parcels.R.

One entry point to the MetroGIS 7-county parcel store (2005-2025 files) at
$PARCEL_HOME/data/standardized, partitioned
year=YYYY/county=Name/part-0.parquet (plain Parquet, WKB geometry, EPSG 26915).

Use from any project:
    import os, sys; sys.path.insert(0, os.path.join(os.environ["PARCEL_HOME"], "python"))
    from read_parcels import read_parcels
    r16 = read_parcels(years=2016, counties="Ramsey", cols=["pin", "emv_land", "emv_total"])
    r21 = read_parcels(2021, "Ramsey", names="original")   # == gpd.read_file(<2021 Ramsey shp>)

Two views (same as the R helper):
  names="standardized"  one column per concept across years (plus year, county).
  names="original"      what geopandas/pyogrio read_file() of that year's file
                        returned: column names and order, pandas dtypes, values,
                        row order, geometry. One year and one county at a time.

The original view needs python/original_dtypes.csv and original_geometry.csv
(built from the raw files by python/build_original_manifest.py) to know the
exact pyogrio dtypes (R's crosswalk type "numeric" can be pyogrio int64 or
float64; an integer column with nulls comes back as float64; a shapefile date
column holding "0000/00/00" comes back as text). Without a manifest row it
falls back to: integer -> int32 (float64 if any NA), numeric -> float64,
Date -> datetime64[ms], POSIXct -> datetime64[ms, UTC], and warns.

Differences from the R helper:
  * `filter` is a pyarrow.compute Expression on standardized names, e.g.
    pc.field("emv_total") > 0 (R takes a quoted R expression).
  * bbox: (xmin, ymin, xmax, ymax) in EPSG 26915, or any shapely geometry /
    GeoSeries / GeoDataFrame (reprojected if it has a CRS). Parcels whose
    polygon intersects the box are kept: a cheap pre-filter on the stored
    pt_x / pt_y (box padded by 2000 m, as in R), then an exact polygon
    intersection. (The stored points were fixed and verified inside each
    parcel on 2026-11-07.)
  * geometry="none" returns a pandas DataFrame (like read_file(ignore_geometry=True)).

layer="points" (as in R) reads the county-published Points layers stored as
published in data/standardized_points (code/07_points_store.R), with
docs/points_column_crosswalk.csv and python/points_original_dtypes.csv /
points_original_geometry.csv (python/build_points_manifest.py). names="original"
equals read_file() of the Points layer. point_location="polygon" (the default
for standardized names) places each point at its polygon's centroid, as in R;
"published" (the default for names="original") keeps the published point.
point_method does not apply.
"""
from __future__ import annotations

import os
import re
import tempfile
import warnings

import numpy as np
import pandas as pd
import geopandas as gpd
import pyarrow.parquet as pq
import shapely

# the repo folder; falls back to the folder above this file
PARCEL_HOME = os.environ.get("PARCEL_HOME", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PARCEL_STORE = os.path.join(PARCEL_HOME, "data", "standardized")
PARCEL_XWALK = os.path.join(PARCEL_HOME, "docs", "column_crosswalk.csv")
PARCEL_DTYPES = os.path.join(PARCEL_HOME, "python", "original_dtypes.csv")
PARCEL_SHP_SCHEMA = os.path.join(PARCEL_HOME, "docs", "shapefile_schema.csv")
PARCEL_GEOMS = os.path.join(PARCEL_HOME, "python", "original_geometry.csv")
# layer="points": the published Points layers (code/07_points_store.R)
PARCEL_STORE_POINTS = os.path.join(PARCEL_HOME, "data", "standardized_points")
PARCEL_XWALK_POINTS = os.path.join(PARCEL_HOME, "docs", "points_column_crosswalk.csv")
PARCEL_DTYPES_POINTS = os.path.join(PARCEL_HOME, "python", "points_original_dtypes.csv")
PARCEL_GEOMS_POINTS = os.path.join(PARCEL_HOME, "python", "points_original_geometry.csv")
PARCEL_CRS = 26915

_LINEAR = {1, 2, 3, 4, 5, 6, 7}  # WKB base types shapely can parse (no curves)


def _as_list(x):
    if x is None:
        return None
    if isinstance(x, (str, int, np.integer)):
        return [x]
    return list(x)


def _partitions(years, counties, store=PARCEL_STORE):
    rows = []
    for yd in sorted(os.listdir(store)):
        m = re.fullmatch(r"year=(\d{4})", yd)
        if not m:
            continue
        for cd in sorted(os.listdir(os.path.join(store, yd))):
            mc = re.fullmatch(r"county=([^/]+)", cd)
            if mc and os.path.exists(os.path.join(store, yd, cd, "part-0.parquet")):
                rows.append((f"{yd}/{cd}", int(m.group(1)), mc.group(1)))
    parts = pd.DataFrame(rows, columns=["dir", "year", "county"])
    if years is not None:
        parts = parts[parts.year.isin([int(y) for y in years])]
    if counties is not None:
        parts = parts[parts.county.isin(counties)]
    if parts.empty:
        raise ValueError("no stored partitions match years/counties")
    return parts.reset_index(drop=True)


def _wkb_type(w):
    """Base geometry type code of a WKB blob (ISO or EWKB, either byte order)."""
    if w is None or len(w) < 5:
        return 0
    t = int.from_bytes(w[1:5], "little" if w[0] == 1 else "big")
    return (t & 0x0FFFFFFF) % 1000


def _linearize_wkb(wkbs):
    """Curved WKB (2023/2024 geodatabase boundaries) -> straight segments, using
    GDAL itself via a temporary GeoPackage round trip: pyogrio linearizes
    non-linear geometries when reading (OGR_G_GetLinearGeometry, default step),
    which is the same conversion read_file applies to the geodatabase."""
    import pyogrio.raw as praw
    tmpdir = tempfile.mkdtemp(prefix="read_parcels_")
    path = os.path.join(tmpdir, "curves.gpkg")
    try:
        praw.write(path, geometry=np.array(wkbs, dtype=object),
                   field_data=[np.arange(len(wkbs), dtype=np.int64)], fields=["rid"],
                   geometry_type="Unknown", crs=f"EPSG:{PARCEL_CRS}", driver="GPKG")
        meta, _, geom, fdata = praw.read(path)
        order = np.argsort(fdata[0])
        return [geom[i] for i in order]
    finally:
        for f in os.listdir(tmpdir):
            os.remove(os.path.join(tmpdir, f))
        os.rmdir(tmpdir)


def _wkb_to_geoms(wkbs):
    """Stored WKB -> shapely array; curved geometries are linearized by GDAL."""
    wkbs = list(wkbs)
    curved = [i for i, w in enumerate(wkbs) if w is not None and _wkb_type(w) not in _LINEAR]
    if curved:
        lin = _linearize_wkb([wkbs[i] for i in curved])
        for i, w in zip(curved, lin):
            wkbs[i] = w
    return shapely.from_wkb(np.array(wkbs, dtype=object))


def _make_valid_sf(g):
    """Repair polygons the way R's sf::st_make_valid() does (GEOS "structure"
    method, collapsed parts kept). Needs shapely >= 2.1."""
    try:
        return shapely.make_valid(g, method="structure", keep_collapsed=True)
    except TypeError:
        raise ImportError("read_parcels needs shapely >= 2.1 to repair polygons as R does: "
                          "pip install -U shapely") from None


def _shapefile_value(v, r_type, ogr_type, width, shp_side=None):
    """One column as read_file() of the year's shapefile returns it: text trimmed,
    cut to the field width, blanks as None; missing numbers as 0; dates without times."""
    if r_type == "character":
        if shp_side is not None:
            v = shp_side.where(shp_side.notna(), v)  # 2021 owner names kept from the shapefile
        w = None if pd.isna(width) else int(width)

        def clean(z):
            if z is None or (isinstance(z, float) and np.isnan(z)) or z is pd.NA:
                return None
            z = (z if isinstance(z, str) else _fmt_num(z)).strip(" \t\r\n")  # as R trimws()
            if w is not None:
                b = z.encode("utf-8")
                if len(b) > w:  # cut to width, then trim (as the shapefile reader does)
                    z = b[:w].decode("utf-8", errors="ignore").strip(" \t\r\n")
            return z or None
        return pd.Series([clean(z) for z in v.tolist()], index=v.index, dtype=object)
    if r_type in ("integer", "numeric"):
        x = pd.to_numeric(v, errors="coerce").fillna(0)
        if ogr_type == "Integer":
            return x.astype("int32")
        if ogr_type == "Integer64":
            return x.astype("int64")
        return x.astype("float64")
    if r_type in ("Date", "POSIXct"):
        t = pd.to_datetime(v, utc=True)
        return t.dt.tz_localize(None).dt.normalize().astype("datetime64[ms]")
    return v


def _bbox_geom(bbox):
    if isinstance(bbox, (gpd.GeoDataFrame, gpd.GeoSeries)):
        if bbox.crs is not None:
            bbox = bbox.to_crs(PARCEL_CRS)
        return shapely.box(*bbox.total_bounds)
    if isinstance(bbox, shapely.Geometry):  # assumed EPSG 26915
        return shapely.box(*bbox.bounds)
    return shapely.box(*bbox)  # (xmin, ymin, xmax, ymax), EPSG 26915


def _manifest(year, county, points=False):
    dt = gm = None
    f_dt, f_gm = (PARCEL_DTYPES_POINTS, PARCEL_GEOMS_POINTS) if points else (PARCEL_DTYPES, PARCEL_GEOMS)
    if os.path.exists(f_dt):
        d = pd.read_csv(f_dt)
        d = d[(d.year == year) & (d.county == county)]
        if len(d):
            dt = d.set_index("column")
    if os.path.exists(f_gm):
        g = pd.read_csv(f_gm)
        g = g[(g.year == year) & (g.county == county)]
        if len(g):
            gm = g.iloc[0]
    return dt, gm


def _fmt_num(v):
    """R's as.character() of a double: 12 -> '12', 1.5 -> '1.5'."""
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return None
    return str(int(v)) if float(v).is_integer() else repr(float(v))


def _restore(v: pd.Series, r_type: str, dtype: str | None, n_null: int, n_zero: int, name: str):
    """One stored column -> the pandas column pyogrio returned for the file."""
    if r_type == "character":
        if v.dtype == object or pd.api.types.is_string_dtype(v):  # pandas 3 "str" too
            out = v.astype(object)
        else:
            out = v.map(_fmt_num).astype(object)
        return out.where(out.notna(), None)
    if r_type in ("Date", "POSIXct"):
        t = pd.to_datetime(v, utc=True)
        if dtype is not None and dtype == "object":
            # shapefile dates pyogrio could not parse: text YYYY/MM/DD, invalid = "0000/00/00"
            s = t.dt.strftime("%Y/%m/%d").astype(object)
            if n_zero and n_null:
                warnings.warn(f"{name}: file had both nulls and '0000/00/00'; missing dates returned as None")
                fill = None
            else:
                fill = "0000/00/00" if n_zero else None
            return s.where(t.notna(), fill)
        if (dtype or "").endswith("UTC]") or (dtype is None and r_type == "POSIXct"):
            return t.astype("datetime64[ms, UTC]")
        return t.dt.tz_localize(None).astype("datetime64[ms]")
    # integer / numeric
    x = pd.to_numeric(v, errors="coerce")
    if dtype is None:
        dtype = "int32" if (r_type == "integer" and not x.isna().any()) else "float64"
    if dtype.startswith("int"):
        if x.isna().any():
            warnings.warn(f"{name}: NA in a column pyogrio read as {dtype}; returned float64")
            return x.astype("float64")
        return x.astype(dtype)
    if dtype == "bool":
        return x.astype(bool)
    return x.astype(dtype)


def read_parcels(years=None, counties=None, cols=None, filter=None, bbox=None,
                 geometry="polygon", point_method="surface", names="standardized",
                 layer="polygons", point_location=None, as_shapefile=False,
                 drop_owner_names=False, collapse_condos=False, orig_fid=False):
    """See module docstring. Returns a GeoDataFrame (EPSG 26915), or a pandas
    DataFrame when geometry="none". layer="points" reads the published Points layers."""
    if layer not in ("polygons", "points"):
        raise ValueError("layer must be 'polygons' or 'points'")
    is_points = layer == "points"
    store = PARCEL_STORE_POINTS if is_points else PARCEL_STORE
    if is_points and (point_method != "surface" or as_shapefile or orig_fid):
        raise ValueError('layer="points" returns the published points: as_shapefile, orig_fid and point_method do not apply')
    if geometry not in ("polygon", "point", "none"):
        raise ValueError("geometry must be 'polygon', 'point' or 'none'")
    if point_method not in ("surface", "centroid", "metrogis", "metrogis_rows"):
        raise ValueError("point_method must be 'surface', 'centroid', 'metrogis' or 'metrogis_rows'")
    if names not in ("standardized", "original"):
        raise ValueError("names must be 'standardized' or 'original'")
    years, counties, cols = _as_list(years), _as_list(counties), _as_list(cols)
    if not os.path.isdir(store):
        raise FileNotFoundError(store)
    if names == "original" and (years is None or counties is None or len(years) != 1 or len(counties) != 1):
        raise ValueError('names="original" needs exactly one year and one county')

    parts = _partitions(years, counties, store)
    bb = _bbox_geom(bbox) if bbox is not None else None

    xwalk = None
    if names == "original" and as_shapefile:
        # the year's SHAPEFILE version (2021, 2024): its field names, order and widths
        sx = pd.read_csv(PARCEL_SHP_SCHEMA)
        sx = sx[(sx.year == int(years[0])) & (sx.county == counties[0])].sort_values("position")
        if not len(sx):
            raise ValueError("as_shapefile=True is only for years stored from a richer container (2021, 2024)")
        xwalk = pd.DataFrame({"original_name": sx.shp_name.values, "std_name": sx.std_name.values,
                              "r_type": sx.r_type.values, "ogr_type": sx.ogr_type.values, "width": sx.width.values})
        if cols is not None:
            xwalk = xwalk[xwalk.original_name.isin(cols)]
        cols_std = list(dict.fromkeys(list(xwalk.std_name) + [s + "_raw" for s in xwalk.std_name] +
                                      [s + "_shp" for s in xwalk.std_name] + ["row_in_shp"] +
                                      (["geometry_shp"] if geometry != "none" else [])))
    elif names == "original":
        xwalk = pd.read_csv(PARCEL_XWALK_POINTS if is_points else PARCEL_XWALK)
        xwalk = xwalk[(xwalk.year == int(years[0])) & (xwalk.county == counties[0])]
        if cols is not None:
            xwalk = xwalk[xwalk.original_name.isin(cols)]
        cols_std = list(dict.fromkeys(list(xwalk.std_name) + [s + "_raw" for s in xwalk.std_name]))
    else:
        cols_std = None if cols is None else list(cols) + [c + "_shp" for c in cols]  # sidecars fill 2021 owner names

    need_geom = geometry != "none" or bb is not None
    keep = None
    if cols_std is not None:
        keep = ["row_in_file"] + list(cols_std) + (["geometry"] if need_geom else []) + \
               (["pt_x", "pt_y"] if bb is not None else [])

    frames, geoms = [], []
    for _, p in parts.iterrows():
        f = os.path.join(store, p.dir, "part-0.parquet")
        avail = pq.read_schema(f).names
        sel = [c for c in avail if bb is not None or c not in ("pt_x", "pt_y")] if keep is None else \
              [c for c in dict.fromkeys(keep) if c in avail]
        if not need_geom:
            sel = [c for c in sel if c != "geometry"]
        tb = pq.read_table(f, columns=sel)
        if filter is not None:
            tb = tb.filter(filter)
        if bb is not None:  # pre-filter on stored points; a parcel can intersect the box with its point outside
            import pyarrow.compute as pc
            pad = 2000.0
            x0, y0, x1, y1 = bb.bounds
            tb = tb.filter((pc.field("pt_x") >= x0 - pad) & (pc.field("pt_x") <= x1 + pad) &
                           (pc.field("pt_y") >= y0 - pad) & (pc.field("pt_y") <= y1 + pad))
        g = None
        if "geometry" in tb.column_names:
            g = _wkb_to_geoms(tb.column("geometry").to_pylist())
            tb = tb.drop(["geometry"])
        d = tb.to_pandas(types_mapper=None)
        if bb is not None:
            hit = shapely.intersects(g, bb)
            hit = np.where(pd.isna(hit), False, hit).astype(bool)
            d = d[hit].reset_index(drop=True)
            g = g[hit]
        d.insert(0, "county", p.county)
        d.insert(0, "year", int(p.year))
        frames.append(d)
        if g is not None:
            geoms.append(g)
    out = pd.concat(frames, ignore_index=True)
    geom = np.concatenate(geoms) if geoms else None

    if names == "original":
        yr, cty = int(years[0]), counties[0]
        dt, gm = _manifest(yr, cty, is_points)
        if dt is None:
            warnings.warn(f"no dtype manifest for {yr} {cty}; dtypes are approximate "
                          "(run python/build_original_manifest.py)")
        if as_shapefile and geom is not None and "geometry_shp" in out.columns:
            sg = out["geometry_shp"].notna().to_numpy()
            if sg.any():
                geom = np.array(geom, dtype=object)
                geom[sg] = _wkb_to_geoms(out["geometry_shp"][sg].tolist())
        out = out.drop(columns=["geometry_shp"], errors="ignore")
        order_col = "row_in_shp" if (as_shapefile and "row_in_shp" in out.columns) else "row_in_file"
        o = np.argsort(out[order_col].to_numpy(), kind="stable")  # back to the file's row order
        out = out.iloc[o].reset_index(drop=True)
        rif = out["row_in_file"].to_numpy()  # kept for ORIG_FID
        if geom is not None:
            geom = geom[o]
        res = {}
        if as_shapefile:
            geom_lin = None
            for _, r in xwalk.iterrows():
                std, typ, raw = r.std_name, r.r_type, r.std_name + "_raw"
                v = out[raw] if (typ == "character" and raw in out.columns) else out.get(std)
                if std in ("shape_leng", "shape_area") and std + "_shp" in out.columns:
                    v = out[std + "_shp"]  # the shapefile's own stored values
                elif v is None or v.isna().all():
                    if std in ("shape_leng", "shape_area") and geom is not None:
                        # not in the 2021 GeoPackage: recompute from the polygon
                        if geom_lin is None:
                            geom_lin = _make_valid_sf(np.array(geom, dtype=object))
                        v = pd.Series(shapely.area(geom_lin) if std == "shape_area" else
                                      shapely.length(shapely.boundary(geom_lin)), index=out.index)
                    elif v is None:
                        v = pd.Series([None] * len(out), index=out.index, dtype=object)
                res[r.original_name] = _shapefile_value(v, typ, r.ogr_type, r.width,
                                                        out.get(std + "_shp") if typ == "character" else None)
        else:
            for _, r in xwalk.iterrows():
                std, typ, raw = r.std_name, r.r_type, r.std_name + "_raw"
                v = out[raw] if (typ == "character" and raw in out.columns) else out[std]
                m = dt.loc[r.original_name] if (dt is not None and r.original_name in dt.index) else None
                res[r.original_name] = _restore(
                    v, typ, None if m is None else m["dtype"],
                    0 if m is None else int(m["n_null"]), 0 if m is None else int(m["n_zero_date"]),
                    f"{yr} {cty} {r.original_name}")
        out = pd.DataFrame(res, index=out.index)
        if as_shapefile:
            gm = {"driver": "ESRI Shapefile", "geometry_type": "", "z_all_zero": "True"}
        # geometry as pyogrio returns it from the original file
        if geom is not None and is_points and geometry != "none":
            geom = np.where(shapely.is_empty(geom), None, geom)  # GDAL null shapes: sf gives EMPTY, pyogrio None
        elif geom is not None and geometry == "polygon":
            empty = shapely.is_empty(geom)
            geom = np.where(empty, None, geom)  # GDAL null shapes: sf gives EMPTY, pyogrio None
            if gm is not None and gm["driver"] == "ESRI Shapefile":
                # sf promoted the shapefile's Polygons to MultiPolygon when the
                # store was written; GDAL/pyogrio returns single-part ones as Polygon
                tid = shapely.get_type_id(geom)
                one = (tid == 6) & (shapely.get_num_geometries(geom) == 1)
                if one.any():
                    geom[one] = shapely.get_geometry(geom[one], 0)
            if gm is not None and str(gm["geometry_type"]).endswith(" Z"):
                if str(gm["z_all_zero"]) == "True":
                    geom = shapely.force_3d(geom, z=0.0)  # the store dropped all-zero Z
                else:
                    warnings.warn(f"{yr} {cty}: source has non-zero Z values the store does not keep")
    else:
        out = out.drop(columns=["row_in_file"], errors="ignore")
        # standardized view: fill 2021 owner names from the shapefile sidecars, as in R
        out = out.drop(columns=["row_in_shp", "geometry_shp", "shape_leng_shp", "shape_area_shp"], errors="ignore")
        for sc in [c for c in out.columns if c.endswith("_shp")]:
            base = sc[:-4]
            if base in out.columns:
                out[base] = out[sc].where(out[sc].notna(), out[base])
            out = out.drop(columns=[sc])

    if drop_owner_names:
        for c in ("OWNER_NAME", "OWNER_MORE", "TAX_NAME", "owner_name", "owner_more", "tax_name"):
            if c in out.columns:
                out[c] = pd.Series([None] * len(out), index=out.index, dtype=object)

    # Points placed at their polygon's centroid, as in R: every unit point in a
    # building shares the building polygon's centroid, moved inside the parcel
    # when the centroid falls outside. Points in no polygon keep the published
    # location. Default "polygon" for standardized names, "published" for original.
    if is_points and geom is not None and geometry != "none":
        loc = point_location or ("polygon" if names == "standardized" else "published")
        if loc not in ("polygon", "published"):
            raise ValueError("point_location must be 'polygon' or 'published'")
        if loc == "polygon" and not collapse_condos:
            if names == "original":
                keys = np.array([f"{int(years[0])} {counties[0]}"] * len(out), dtype=object)
            else:
                keys = (out["year"].astype(str) + " " + out["county"].astype(str)).to_numpy()
            geom = np.array(geom, dtype=object)
            for k in pd.unique(keys):
                ix = np.flatnonzero(keys == k)
                yr, cty = k.split(" ", 1)
                pg = read_parcels(int(yr), cty, cols=["pin"], geometry="polygon")
                pgl = _make_valid_sf(np.asarray(pg.geometry.values, dtype=object))
                cen = shapely.centroid(pgl)
                inside = shapely.intersects(cen, pgl)
                inside = np.where(pd.isna(inside), False, inside).astype(bool)
                cen[~inside] = shapely.point_on_surface(pgl[~inside])
                pt_idx, poly_idx = shapely.STRtree(pgl).query(geom[ix], predicate="intersects")
                first = pd.Series(poly_idx).groupby(pt_idx).min()  # first containing polygon, as in R
                geom[ix[first.index.to_numpy()]] = cen[first.to_numpy()]

    if geom is not None and geometry == "point" and not is_points:
        g = geom.copy()
        g = _make_valid_sf(g)  # as R
        if point_method == "metrogis_rows":
            # one point per polygon row, placeholders kept, plain centroid (Washington 2015 Points)
            out = out.drop(columns=["Shape_Leng", "Shape_Length", "Shape_Area", "shape_leng", "shape_area"], errors="ignore")
            geom = shapely.centroid(g)
            if orig_fid:
                if names != "original":
                    raise ValueError('orig_fid=True needs names="original"')
                out["ORIG_FID"] = (rif - 1).astype("int32")
        elif point_method == "metrogis":
            pin_col = "pin" if "pin" in out.columns else "PIN" if "PIN" in out.columns else None
            if pin_col is None:
                raise ValueError('point_method="metrogis" needs the PIN column (include "pin"/"PIN" in cols)')
            pins = out[pin_col].astype(str).where(out[pin_col].notna(), "NA")
            digits = pins.str.replace(r"^[0-9]{3}-", "", n=1, regex=True).str.replace(r"[^0-9]", "", regex=True)
            real = (digits.str.len() >= 6).to_numpy()  # drop placeholder polygons (Water, 123-C94)
            out = out[real].reset_index(drop=True)
            g = g[real]
            out = out.drop(columns=["Shape_Leng", "Shape_Area", "shape_leng", "shape_area"], errors="ignore")
            # one point per remaining polygon ROW, as in R: multi-polygon parcels are not collapsed
            g_pin = g
            cen = shapely.centroid(g_pin)
            inside = shapely.intersects(cen, g_pin)  # centroid inside its OWN parcel?
            inside = np.where(pd.isna(inside), False, inside).astype(bool)
            cen[~inside] = shapely.point_on_surface(g_pin[~inside])
            geom = cen
        else:
            geom = shapely.point_on_surface(g) if point_method == "surface" else shapely.centroid(g)

    out = out.drop(columns=["pt_x", "pt_y"], errors="ignore")
    if collapse_condos:
        if not is_points or names != "standardized" or geometry == "none":
            raise ValueError('collapse_condos=True needs layer="points", names="standardized" and geometry')
        from collapse_condos import collapse_condos as _collapse
        gdf = gpd.GeoDataFrame(out, geometry=gpd.GeoSeries(geom, index=out.index, crs=PARCEL_CRS), crs=PARCEL_CRS)
        pieces = []
        for (yr, cty), d in gdf.groupby(["year", "county"], sort=False):
            pg = read_parcels(int(yr), cty, cols=["pin"], geometry="polygon")
            pieces.append(_collapse(d.reset_index(drop=True), pg))
        return gpd.GeoDataFrame(pd.concat(pieces, ignore_index=True), crs=PARCEL_CRS)
    if geom is not None and geometry != "none":
        return gpd.GeoDataFrame(out, geometry=gpd.GeoSeries(geom, index=out.index, crs=PARCEL_CRS),
                                crs=PARCEL_CRS)
    return out


from download_parcels import download_parcels  # noqa: E402  (get years from Zenodo)
from parcel_columns import parcel_columns  # noqa: E402  (list columns without reading data)
from estimate_tax_cap import estimate_tax_cap  # noqa: E402  (net tax capacity from 2025 class rates)
