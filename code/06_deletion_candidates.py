#!/usr/bin/env python3
"""06_deletion_candidates.py -- READ-ONLY. List every copy of a MetroGIS parcel
file outside parcel_data that the central store now replaces, grouped for
Matt's review. Nothing is deleted here. Output: docs/deletion_candidates.csv
(+ printed summary). Categories:
  polygons_shp     Parcels<yr><County>.* (all components) in shp_plan_regonal_parcels_<yr>
  points_shp       Parcels<yr><County>Points.* / All7Points (published point layers; not stored,
                   reproduced by read_parcels point_method = metrogis / metrogis_rows)
  gdb_gpkg         plan_regonal_parcels_<yr>.gdb / .gpkg / the 2021 gpkg zip
  release_2025     shp_plan_regional_parcels/Parcels<County>[Points].* (Jan 2026 files)
  brownfield_copy  brownfield_stpaul/data/raw/parcels (local copies made 2026-11-05)
Excluded: anything under parcel_data; plan_parcels_open files (a different dataset).
"""
import os, re, csv, collections
ROOTS = [os.path.expanduser("~/Desktop"), os.path.expanduser("~/Downloads"), os.path.expanduser("~/research")]
SKIP = ("/Library/", "/.Trash/", "/research/parcel_data/")
DATALESS = 0x40000000
pat_poly = re.compile(r"^Parcels(20\d{2})(Anoka|Carver|Dakota|Hennepin|Ramsey|Scott|Washington)\.")
pat_pts  = re.compile(r"^Parcels(20\d{2})(Anoka|Carver|Dakota|Hennepin|Ramsey|Scott|Washington|All7)Points\.")
pat_25   = re.compile(r"^Parcels(Anoka|Carver|Dakota|Hennepin|Ramsey|Scott|Washington)(Points)?\.")
rows = []
def add(cat, path, st):
    rows.append(dict(category=cat, path=path, bytes=st.st_size,
                     icloud_only=bool(st.st_flags & DATALESS),
                     synced=path.startswith(os.path.expanduser("~/Desktop/"))))
for r in ROOTS:
    for d, dn, fn in os.walk(r):
        if any(s in d + "/" for s in SKIP): dn[:] = []; continue
        base = os.path.basename(d)
        if re.match(r"plan_regonal_parcels_20\d{2}\.gdb$", base):
            for f in fn: add("gdb_gpkg", os.path.join(d, f), os.lstat(os.path.join(d, f)))
            dn[:] = []; continue
        for f in fn:
            p = os.path.join(d, f)
            try: st = os.lstat(p)
            except OSError: continue
            if "brownfield_stpaul/data/raw/parcels" in d: add("brownfield_copy", p, st)
            elif pat_pts.match(f): add("points_shp", p, st)
            elif pat_poly.match(f): add("polygons_shp", p, st)
            elif base == "shp_plan_regional_parcels" and pat_25.match(f): add("release_2025", p, st)
            elif re.match(r"(gpkg|fgdb|shp)_plan_regonal_parcels_20\d{2}\.zip$", f) or re.match(r"plan_regonal_parcels_20\d{2}\.gpkg$", f):
                add("gdb_gpkg", p, st)
out = os.path.join(os.environ["PARCEL_HOME"], "docs/deletion_candidates.csv")
with open(out, "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
agg = collections.defaultdict(lambda: [0, 0, 0, 0])
for x in rows:
    a = agg[x["category"]]; a[0] += 1; a[1] += x["bytes"]
    if x["icloud_only"]: a[2] += x["bytes"]
    else: a[3] += x["bytes"]
print(f"{'category':16s} {'files':>7s} {'total GB':>9s} {'on disk GB':>11s} {'iCloud-only GB':>15s}")
for k, (n, b, ic, ld) in sorted(agg.items()):
    print(f"{k:16s} {n:7d} {b/1e9:9.1f} {ld/1e9:11.1f} {ic/1e9:15.1f}")
tb = sum(x["bytes"] for x in rows); tl = sum(x["bytes"] for x in rows if not x["icloud_only"])
print(f"{'TOTAL':16s} {len(rows):7d} {tb/1e9:9.1f} {tl/1e9:11.1f} {(tb-tl)/1e9:15.1f}")
proj = collections.Counter()
for x in rows:
    m = re.match(re.escape(os.path.expanduser("~")) + r"/((?:Desktop/(?:Personal Info|UMN|AO|AOData)/[^/]+)|Desktop/[^/]+|Downloads|research/[^/]+)", x["path"])
    proj[m.group(1) if m else "?"] += x["bytes"]
print("\nby folder (GB):"); [print(f"  {v/1e9:7.1f}  {k}") for k, v in proj.most_common()]
