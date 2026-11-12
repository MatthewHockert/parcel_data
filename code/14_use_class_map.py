#!/usr/bin/env python3
"""14_use_class_map.py: map every county's use_class1 label to a property type in
inst/extdata/class_rates_hennepin_2025.csv, so estimate_tax_cap() can price any county-year.
Writes inst/extdata/use_class_map.csv (county, use_class1, prop_type, rule, parcels, years).

Hennepin labels are Hennepin's own property-type descriptions and match the rate table
directly. Every other label is mapped by the keyword rules below, in order (first match
wins); the matching rule is recorded per row. This is a judgment call (Matt, 2026-11-11):
review inst/extdata/use_class_map.csv before relying on a county's estimate. Labels no rule
covers stay unmapped and get no estimate.

Run:  python3 -I code/14_use_class_map.py
"""
import glob, os, re
import pandas as pd
import pyarrow.parquet as pq

PD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rates = pd.read_csv(os.path.join(PD, "inst", "extdata", "class_rates_hennepin_2025.csv"))
by_desc = {d.upper(): p for d, p in zip(rates.description, rates.prop_type)}
# Hennepin spellings that differ from the rate table
by_desc.update({"RESIDENTIAL LAKE SHORE": "RL", "CONDOMINIUM": "X", "CONDO GARAGE/MISCELLANEOUS": "XM",
                "RESIDENTIAL - MISC/B&B/MULTIPLE": "RM", "RESIDENTIAL-MISC/B&B/MULTIPLE": "RM"})

# (rule name, regex on the upper-cased label, prop_type); first match wins
RULES = [
    ("exempt",            r"EXEMPT|\bT E\b|\bTE\b|MUNI|\b5E\b|SP TAX DIST|SPECIAL TAXING|PUBLIC|CHURCH|STATE OF|STATE PROP|STATE ACQ|\bROAD\b|NON-TAXABLE|PUB SERV|COUNTY OWN|\bCITY\b OWN|CO SRVC|CHARIT|TAX FORFEIT|ZERO EMV|VALUE INCLUDED", "EX"),
    ("seasonal (SRR)",    r"\bSRR\b", "S"),
    ("apartment (quads)", r"QUAD|FOURPLEX|4-PLEX", "A"),
    ("low income rental", r"LOW INC|\b4D\b|4D1|4D\(1\)|AFFORDABLE", "HL"),
    ("land trust",        r"LAND TRUST|4D2|4D\(2\)", "HT"),
    ("manufactured park", r"MANUFACTURED HOME PARK|MOBILE HOME PARK|\bMHP\b|4C5|4C\(5\)", "MH"),
    ("golf",              r"GOLF", "GC"),
    ("seasonal",          r"SEASONAL|CABIN|RESORT|4C12|4C\(12\)|RECREATION", "S"),
    ("utility",           r"UTILIT|ELECTRIC GEN|PIPELINE", "U"),
    ("railroad",          r"RAILROAD", "CR"),
    ("vacant commercial", r"(VACANT|V LAND|UNIMPROVED|VAC).*(COMM|COMMERCIAL)|(COMM|COMMERCIAL).*(VACANT|V LAND|UNIMPROVED)", "LC"),
    ("vacant industrial", r"(VACANT|V LAND|UNIMPROVED|VAC).*(IND)|(INDUST).*(VACANT|V LAND|UNIMPROVED)", "LI"),
    ("vacant apartment",  r"(VACANT|V LAND|UNIMPROVED).*(APT|APART)", "LA"),
    ("industrial",        r"INDUST|\bINDS\b", "I"),
    ("commercial",        r"COMM|\b3A\b|RETAIL|OFFICE|STORE|BUSINESS", "C"),
    ("apartment",         r"APART|\bAPT|\b4A\b|4\+ UNITS|4 OR MORE", "A"),
    ("farm",              r"\bAG\b|AGRIC|FARM|GREEN ACRE|AG PRESERVE|\b2A\b|\b2B\b|RURAL VACANT|TIMBER|FOREST", "F"),
    ("vacant residential", r"VACANT|V LAND|UNIMPROVED|\b4B4\b|4B\(4\)|\bLOT\b", "LR"),
    ("condo garage",      r"CONDO.*GARAGE|GARAGE.*CONDO", "XM"),
    ("condo",             r"CONDO|COOPERATIVE|\bCO-OP", "X"),
    ("townhouse",         r"TOWN", "Y"),
    ("2-3 units",         r"2-3|DUPLEX|DOUBLE|TRIPLEX|BUNGALOW|\b4B1\b|4B\(1\)|TWO FAMILY|THREE FAMILY|2 UNIT|3 UNIT", "TP"),
    ("residential",       r"RES|SINGLE|DWELL|HOMESTEAD|\b1A\b|4BB|HOUSE", "R"),
]

rows = []
for f in sorted(glob.glob(os.path.join(PD, "data", "standardized", "year=*", "county=*", "part-0.parquet"))):
    yr, cty = re.search(r"year=(\d+)/county=(\w+)", f).groups()
    vc = pq.read_table(f, columns=["use_class1"]).to_pandas().use_class1.value_counts()
    for lab, n in vc.items():
        rows.append((cty, int(yr), lab, int(n)))
labs = pd.DataFrame(rows, columns=["county", "year", "use_class1", "n"])
labs = labs.groupby(["county", "use_class1"]).agg(parcels=("n", "sum"), first=("year", "min"),
                                                 last=("year", "max")).reset_index()


def classify(county, label):
    u = re.sub(r"\s+", " ", str(label).strip().upper())
    # multi-use labels ("100 RES 1 UNIT/300 COMMERCIAL"): the first use is the primary one
    if re.match(r"^\d{3} [^/]+/\d{3}", u):
        u = u.split("/")[0]
    if county == "Hennepin" and u in by_desc:
        return by_desc[u], "Hennepin description"
    if not u:
        return None, "blank"
    for name, rx, pt in RULES:
        if re.search(rx, u):
            return pt, name
    return None, "unmapped"


out = labs.copy()
out[["prop_type", "rule"]] = [classify(c, l) for c, l in zip(out.county, out.use_class1)]

# a bare numeric code ("100") takes the property type its labelled form ("100 Res 1 unit")
# maps to in the same county, when every labelled form of that code agrees
lead = out.use_class1.astype(str).str.extract(r"^\s*(\d{3,4})\b")[0]
labelled = out.assign(code=lead)[lead.notna() & out.prop_type.notna() &
                                 ~out.use_class1.astype(str).str.fullmatch(r"\s*\d+\s*") &
                                 ~out.use_class1.astype(str).str.contains("/")]
code_map = labelled.groupby(["county", "code"]).prop_type.agg(lambda s: s.iloc[0] if s.nunique() == 1 else None)
bare = out.use_class1.astype(str).str.fullmatch(r"\s*\d{3,4}\s*") & out.prop_type.isna()
for i in out.index[bare]:
    pt = code_map.get((out.at[i, "county"], str(out.at[i, "use_class1"]).strip()))
    if pt:
        out.at[i, "prop_type"], out.at[i, "rule"] = pt, "bare code, same code's label"
out["years"] = out["first"].astype(str) + "-" + out["last"].astype(str)
out = out[["county", "use_class1", "prop_type", "rule", "parcels", "years"]].sort_values(
    ["county", "parcels"], ascending=[True, False])
out.to_csv(os.path.join(PD, "inst", "extdata", "use_class_map.csv"), index=False)

tot = out.groupby("county").parcels.sum()
mapped = out[out.prop_type.notna()].groupby("county").parcels.sum()
print("share of parcel-years with a mapped property type:")
print((mapped / tot).round(4).to_string())
