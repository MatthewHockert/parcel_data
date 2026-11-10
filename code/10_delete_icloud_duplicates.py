#!/usr/bin/env python3
"""10_delete_icloud_duplicates.py -- delete iCloud-only copies of parcel files the store replaces.

A file qualifies only if it is iCloud-only (dataless), its folder passed the live-read
review (09_trash_candidates.py tiers), and data/raw holds a file with the same name and
byte size (the copy the store was built from) or, for Points files, the same name and
size as the copy the Points store was verified against (docs/points_sources.csv folders,
now in the Trash per docs/trash_manifest_*.csv). Deleting a dataless file removes it from
iCloud without downloading it; iCloud.com keeps it in Recently Deleted for 30 days.

Run:  python3 -I code/10_delete_icloud_duplicates.py            (dry run)
      python3 -I code/10_delete_icloud_duplicates.py --delete   (deletes)
"""
import csv, os, sys, collections

HOME = "/Users/matthewhockert"
PD = HOME + "/research/parcel_data"
PI = HOME + "/Desktop/Personal Info/"
DATALESS = 0x40000000
MANIFEST = PD + "/docs/icloud_delete_manifest_20261110.csv"

# folders cleared in the live-read review; every project in them reads the store now
CLEARED = [
    HOME + "/Desktop/UMN/hennepin_conservation_easements/",
    HOME + "/Desktop/UMN/hc_easement_simulations/",
    PI + "matthew_maps_saint_paul/",
    PI + "minneapolis_st_paul_housing_reform_paper/",
    PI + "vacant_land_fees_st_paul_blog/",
    PI + "st_paul_rc_affordable_housing/",
]
# held back: AO / AOData (hwy-36 paper, later), scenic-quality (data for McWay)

raw = collections.defaultdict(set)              # file name -> sizes present in data/raw
for d, _, fs in os.walk(PD + "/data/raw"):
    for f in fs:
        raw[f].add(os.lstat(os.path.join(d, f)).st_size)

# Points layers have no data/raw copy; use the verified source copies instead
import glob
src_dirs = {os.path.dirname(r["source"]) for r in csv.DictReader(open(PD + "/docs/points_sources.csv"))}
for m in glob.glob(PD + "/docs/trash_manifest_*.csv"):
    for r in csv.DictReader(open(m)):
        if os.path.dirname(r["original_path"]) in src_dirs:
            raw[os.path.basename(r["original_path"])].add(int(r["bytes"]))

plan, skip = [], collections.Counter()
for r in csv.DictReader(open(PD + "/docs/deletion_candidates.csv")):
    p = r["path"]
    root = next((c for c in CLEARED if p.startswith(c)), None)
    if root is None:
        skip["held_back_or_not_cleared"] += 1; continue
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        skip["already_gone"] += 1; continue
    if not st.st_flags & DATALESS:
        skip["on_disk_not_icloud_only"] += 1; continue
    if st.st_size not in raw.get(os.path.basename(p), ()):
        skip["no_same_name_size_in_raw"] += 1; continue
    plan.append((p, st.st_size, root))

by = collections.defaultdict(lambda: [0, 0])
for _, b, t in plan:
    by[t][0] += 1; by[t][1] += b
for t, (n, b) in sorted(by.items(), key=lambda x: -x[1][1]):
    print(f"{n:6d} files {b/1e9:7.2f} GB  {t.replace(HOME, '~')}")
print(f"TOTAL {len(plan)} files {sum(b for _, b, _ in plan)/1e9:.2f} GB | skipped: {dict(skip)}")

if "--delete" not in sys.argv:
    print("dry run: nothing deleted (use --delete)"); sys.exit(0)
if os.path.exists(MANIFEST):
    sys.exit(f"{MANIFEST} exists: already run")
with open(MANIFEST, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["deleted_path", "bytes"])
    for p, b, _ in plan:
        os.unlink(p); w.writerow([p, b])
print(f"deleted {len(plan)} files; manifest {MANIFEST}")
