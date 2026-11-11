"""parcel_columns(): list the columns read_parcels() can return, without reading any data.
Python twin of R/parcel_columns.R, same arguments and the same table.

    from read_parcels import parcel_columns
    parcel_columns()                                   # every standardized column, all years
    parcel_columns([2014, 2015, 2016], "Ramsey")       # columns recorded in those years
    parcel_columns(2016, "Ramsey", names="original")   # that file's own field names, in order
    parcel_columns(2021, "Ramsey", layer="points")

Reads the crosswalks in docs/, so it works before download_parcels(). Standardized
view: one row per column (year and county first), its type (as R names it), the years
it was recorded and the original field names it came from. A column not recorded in a
year is NA there. Original view: one row per field of one year x county file, in file order.
"""
import os
import pandas as pd

_HOME_DEFAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _year_ranges(y):
    y = sorted(set(int(v) for v in y))
    out, start = [], y[0]
    for a, b in zip(y, y[1:] + [None]):
        if b != a + 1:
            out.append(str(start) if start == a else f"{start}-{a}")
            start = b
    return ", ".join(out)


def _as_list(x):
    if x is None:
        return None
    return [x] if isinstance(x, (int, str)) else list(x)


def parcel_columns(years=None, counties=None, layer="polygons", names="standardized",
                   as_shapefile=False):
    if layer not in ("polygons", "points"):
        raise ValueError("layer must be 'polygons' or 'points'")
    if names not in ("standardized", "original"):
        raise ValueError("names must be 'standardized' or 'original'")
    years, counties = _as_list(years), _as_list(counties)
    if names == "original" and (years is None or counties is None or len(years) != 1 or len(counties) != 1):
        raise ValueError('names="original" needs exactly one year and one county')
    home = os.environ.get("PARCEL_HOME", _HOME_DEFAULT)
    docs = os.path.join(home, "docs")

    if names == "original" and as_shapefile:
        sx = pd.read_csv(os.path.join(docs, "shapefile_schema.csv"))
        sx = sx[(sx.year == int(years[0])) & (sx.county == counties[0])].sort_values("position")
        if not len(sx):
            raise ValueError("as_shapefile=True is only for 2021 and 2024")
        return pd.DataFrame({"column": sx.shp_name.values, "std_name": sx.std_name.values,
                             "type": sx.r_type.values})

    all_xw = pd.read_csv(os.path.join(docs, "points_column_crosswalk.csv" if layer == "points"
                                      else "column_crosswalk.csv"))
    xw = all_xw
    if years is not None:
        xw = xw[xw.year.isin([int(y) for y in years])]
    if counties is not None:
        xw = xw[xw.county.isin(counties)]
    if not len(xw):
        raise ValueError("no columns for those years / counties (years are 2005-2025)")

    if names == "original":
        return pd.DataFrame({"column": xw.original_name.values, "std_name": xw.std_name.values,
                             "type": xw.r_type.values})

    # the type read_parcels() returns, from every year's types: text only -> character,
    # dates -> POSIXct (stored as UTC timestamps), anything numeric -> numeric
    def store_type(ty):
        ty = set(ty)
        if ty == {"character"}:
            return "character"
        if ty <= {"Date", "POSIXct"}:
            return "POSIXct"
        return "numeric"
    types = all_xw.groupby("std_name").r_type.agg(store_type)
    mixed_all = set(all_xw.groupby("std_name").r_type.agg(
        lambda ty: "character" in set(ty) and bool(set(ty) & {"numeric", "integer"}))
        .loc[lambda s: s].index)

    rows = []
    for std, d in xw.groupby("std_name", sort=True):
        rows.append({"column": std, "type": types[std], "years": _year_ranges(d.year),
                     "original_names": ", ".join(pd.unique(d.original_name))})
    out = pd.DataFrame(rows)
    # columns stored as numbers in some years and text in others keep a <col>_raw text copy
    raw = out[out.column.isin(mixed_all)].assign(column=lambda d: d.column + "_raw", type="character")
    out = pd.concat([out, raw], ignore_index=True).sort_values("column", kind="stable")
    ids = pd.DataFrame({"column": ["year", "county"], "type": ["integer", "character"],
                        "years": _year_ranges(xw.year), "original_names": "(added by read_parcels)"})
    return pd.concat([ids, out], ignore_index=True)
