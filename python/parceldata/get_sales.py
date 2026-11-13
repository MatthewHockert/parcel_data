"""get_sales(): Python twin of R/get_sales.R, same steps and output.

    from parceldata import get_sales
    s = get_sales(list(range(2014, 2025)), "Ramsey")

One row per county, pin and sale date. Each yearly file lists only a parcel's
most recent sale, repeated in later files, so the files are stacked and the
assessor values come from the FIRST file listing the sale. The files record no
sale or deed type. Dropped: rows with no sale_date or no pin, and sale dates
after the file's year. See R/get_sales.R for the details.
"""
import numpy as np
import pandas as pd
import pyarrow.compute as pc

from .read_parcels import read_parcels

DEFAULT_COLS = ["emv_land", "emv_bldg", "emv_total", "tax_capac", "use_class1",
                "homestead", "year_built", "fin_sq_ft", "num_units"]


def get_sales(years=None, counties=None, cols=None, sale_years=None, geometry="none"):
    cols = DEFAULT_COLS if cols is None else ([cols] if isinstance(cols, str) else list(cols))
    keys = ["pin", "sale_date", "sale_value"]
    p = read_parcels(years, counties, cols=list(dict.fromkeys(keys + cols)), geometry=geometry,
                     filter=pc.field("sale_date").is_valid())
    sd = pd.to_datetime(p["sale_date"])
    if sd.dt.tz is not None:   # stored as UTC midnight; return plain dates like R
        sd = sd.dt.tz_convert("UTC").dt.tz_localize(None)
    p["sale_date"] = sd.dt.normalize()

    pin = p["pin"].astype("string").str.strip()
    no_pin = pin.isna() | pin.str.fullmatch(r"[0-9]{3}-?").fillna(False).astype(bool)
    if no_pin.any():
        print(f"{int(no_pin.sum())} rows dropped: no pin")
    p = p[~no_pin.to_numpy()]

    bad = p["sale_date"].dt.year > p["year"]
    if bad.any():
        n_par = p.loc[bad, ["county", "pin"]].drop_duplicates().shape[0]
        print(f"{int(bad.sum())} rows dropped: sale date after the file's year ({n_par} parcels)")
    p = p[~bad.to_numpy()]

    p = p.sort_values(["county", "pin", "sale_date", "year"], kind="mergesort")
    grp = p.groupby(["county", "pin", "sale_date"], sort=False)
    p = p.assign(n_files=grp["year"].transform("size").astype("int32"))
    p = p[~p.duplicated(["county", "pin", "sale_date"])]

    p = p.rename(columns={"year": "file_year"})
    p["sale_year"] = p["sale_date"].dt.year.astype("int32")
    p["value_lag_years"] = (p["file_year"] - p["sale_year"]).astype("int32")
    if sale_years is not None:
        sy = [sale_years] if np.isscalar(sale_years) else list(sale_years)
        p = p[p["sale_year"].isin(sy)]
    p = p.drop(columns=["row_in_file"], errors="ignore")

    front = ["county", "pin", "sale_date", "sale_year", "sale_value",
             "file_year", "value_lag_years", "n_files"]
    p = p[front + [c for c in p.columns if c not in front]]
    return p.reset_index(drop=True)
