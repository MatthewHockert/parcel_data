"""estimate_tax_cap(x): Python twin of R/estimate_tax_cap.R, same steps and output.

    from read_parcels import read_parcels, estimate_tax_cap
    p = read_parcels(list(range(2005, 2021)), "Ramsey", cols=["pin", "use_class1", "homestead", "emv_total"])
    p = estimate_tax_cap(p)     # adds prop_type, homestead_status, payable_year, tmv_est, tax_capac_est

WARNING: the class rates are Hennepin County's table for the 2025 assessment (taxes payable
2026, docs/class_rates_hennepin_2025.csv), applied to every year, so earlier years are
priced at 2025 rates. Only the homestead exclusion follows the year. Use it to fill gaps, and prefer the county's tax_capac where published.
See R/estimate_tax_cap.R for the steps.
"""
import os
import warnings
import numpy as np
import pandas as pd

_HOME_DEFAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def estimate_tax_cap(x, value="emv_total", homestead_exclusion=True):
    need = ["year", "county", "use_class1", "homestead", value]
    miss = [c for c in need if c not in x.columns]
    if miss:
        raise ValueError(f"estimate_tax_cap needs columns: {', '.join(miss)} (read with names='standardized')")
    home = os.environ.get("PARCEL_HOME", _HOME_DEFAULT)
    rates = pd.read_csv(os.path.join(home, "docs", "class_rates_hennepin_2025.csv"))
    umap = pd.read_csv(os.path.join(home, "docs", "use_class_map.csv"), keep_default_na=False,
                       na_values={"prop_type": [""]})
    warnings.warn("estimate_tax_cap: Hennepin 2025-assessment class rates applied to every year; "
                  "earlier years are priced at 2025 rates (the homestead exclusion follows the year)", stacklevel=2)

    lut = dict(zip(zip(umap.county, umap.use_class1.astype(str)), umap.prop_type))
    uc = x["use_class1"].astype(object).where(x["use_class1"].notna(), "NA").astype(str)
    pt = pd.Series([lut.get(k) for k in zip(x["county"].astype(str), uc)], index=x.index, dtype=object)
    pt = pt.where(pt.notna() & (pt != ""), None)
    r = rates.set_index("prop_type").reindex(pt.fillna("__none__").to_numpy())
    r.index = x.index

    h = x["homestead"].astype(object).where(x["homestead"].notna(), "").astype(str).str.strip().str.upper()
    status = np.select([h.isin(["Y", "YES", "1"]), h.isin(["P", "FRACTIONAL"]), h.isin(["N", "NO", "0"])],
                       ["homestead", "partial", "non-homestead"], "unknown")
    hm = np.isin(status, ["homestead", "partial"]) & r["hmstd_base1_rate"].notna().to_numpy()

    # the taxes-payable year the value is for: file year + the county's fitted offset
    offset = np.where(x["county"].astype(str).isin(["Hennepin", "Ramsey"]).to_numpy(), 0, 1)
    payable = pd.to_numeric(x["year"].astype(str), errors="coerce").to_numpy(dtype=float) + offset

    v = pd.to_numeric(x[value], errors="coerce").to_numpy(dtype=float)
    excl = np.zeros(len(x))
    if homestead_exclusion:
        elig = hm & (r["class_homestead"].astype(str).str[:2].isin(["1a", "1b"]).to_numpy() |
                     (pt.to_numpy() == "FF"))
        cap = np.where(payable >= 2025, 95000.0, 76000.0)  # value with the largest exclusion (40%)
        e = np.where(v <= cap, 0.40 * v, np.maximum(0, 0.40 * cap - 0.09 * (v - cap)))
        excl = np.where(elig & ~np.isnan(v) & (payable >= 2012), e, 0.0)
    tmv = v - excl

    def z(a):
        return np.nan_to_num(a.to_numpy(dtype=float), nan=0.0)

    def tier(val, lim1, rate1, rate2):  # first lim1 at rate1, rest at rate2 (rate1 if none)
        rate2 = np.where(np.isnan(rate2), rate1, rate2)
        lim1 = np.where(np.isnan(lim1), np.inf, lim1)
        return (np.minimum(val, lim1) * rate1 + np.maximum(val - lim1, 0) * rate2) / 100

    col = lambda c: r[c].to_numpy(dtype=float)
    bdp = z(r["limit_bdp"])
    est_h = np.minimum(tmv, bdp) * z(r["hmstd_bdp_rate"]) / 100 + \
        tier(np.maximum(tmv - bdp, 0), col("limit_base1"), col("hmstd_base1_rate"), col("hmstd_over_rate"))
    lim_n = np.where(np.isnan(col("limit_base1")), np.nan, bdp + col("limit_base1"))
    est_n = tier(tmv, lim_n, col("nonhmstd_rate"), col("nonhmstd_over_rate"))
    est = np.where(hm, est_h, est_n)
    unpriced = pt.isna().to_numpy()
    est[unpriced] = np.nan

    out = x.copy()
    out["prop_type"] = pt.to_numpy()
    out["homestead_status"] = status
    out["payable_year"] = payable
    out["tmv_est"] = np.where(unpriced, np.nan, tmv)
    out["tax_capac_est"] = est
    return out
