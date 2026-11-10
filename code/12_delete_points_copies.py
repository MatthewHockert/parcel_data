#!/usr/bin/env python3
"""12_delete_points_copies.py -- delete project copies of the published Points layers.

Every Parcels<year><County>Points.* and Parcels<year>All7Points.* file under Desktop,
Downloads, Documents and research, except AO / AOData (hwy-36, kept as is) and this
repository. No project reads them any more: Points come from read_parcels(layer = "points").
Only iCloud-only (dataless) files are deleted; anything on local disk is reported, not
touched. iCloud.com keeps deleted files in Recently Deleted for 30 days (Matt, 2026-11-10).

Run:  python3 -I code/12_delete_points_copies.py            (dry run)
      python3 -I code/12_delete_points_copies.py --delete   (deletes)
"""
import csv, os, re, sys, collections

HOME = os.path.expanduser("~")
ROOTS = ["Desktop", "Downloads", "Documents", "research"]
SKIP = [HOME + "/Desktop/AO/", HOME + "/Desktop/AOData/", HOME + "/research/parcel_data/", HOME + "/.Trash/"]
DATALESS = 0x40000000
NAME = re.compile(r"^Parcels20\d{2}[A-Za-z0-9]+Points\.")
MANIFEST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "docs", "points_copies_delete_manifest_20261110.csv")

plan, kept = [], collections.Counter()
for root in ROOTS:
    for d, _, fs in os.walk(os.path.join(HOME, root)):
        for f in fs:
            if not NAME.match(f):
                continue
            p = os.path.join(d, f)
            if any(p.startswith(s) for s in SKIP):
                continue
            st = os.lstat(p)
            if not st.st_flags & DATALESS:
                kept["on_local_disk"] += 1; print("on disk, not touched:", p); continue
            plan.append((p, st.st_size))

print(f"{len(plan)} files, {sum(s for _, s in plan) / 1e9:.2f} GB to delete; kept: {dict(kept)}")
if "--delete" not in sys.argv:
    sys.exit("dry run; pass --delete to delete")

with open(MANIFEST, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["deleted_path", "bytes"])
    for p, s in plan:
        os.unlink(p); w.writerow([p, s])
print("deleted; manifest:", MANIFEST)
