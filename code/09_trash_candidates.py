#!/usr/bin/env python3
"""09_trash_candidates.py -- move reviewed deletion candidates to the Trash.

Deletion review with Matt, 2026-11-09 (see docs/STATUS.md). Source list:
docs/deletion_candidates.csv from code/06_deletion_candidates.py. A folder is
in a tier only after its project's code was checked line by line for live
reads of it.
  tier1  folders no code reads at all
  tier2  folders named only by dead code (repointed scripts' leftover path
         variables, disabled blocks, pseudocode, an archived original script),
         minus what is still read live: matthew_maps Points shapefiles (three
         green_line scripts st_read them) and brownfield data/raw/parcels/2024
         (brownfield_spillovers.qmd chunk load-brownfields, eval: true)

Only files FULLY ON DISK are moved: moving an iCloud-only (dataless) file out
of a synced folder would make macOS download it first, and those use no local
disk anyway.

Files go to ~/.Trash/parcel_cleanup_<tier>_20261109/<path relative to home>.
Nothing is permanently deleted; space returns only when Matt empties the Trash.
Manifest (original path -> trash path) for an exact restore:
docs/trash_manifest_<tier>_20261109.csv (also copied into the Trash folder).

Run:  python3 -I code/09_trash_candidates.py tier2           (dry run)
      python3 -I code/09_trash_candidates.py tier2 --move    (moves)
History: tier1 moved 2026-11-09 (974 files, 46.24 GB) as 09_trash_tier1.py.
"""
import csv, os, sys, shutil

HOME = "/Users/matthewhockert"
PD = HOME + "/research/parcel_data"
DATALESS = 0x40000000
PI = HOME + "/Desktop/Personal Info/"

def is_points(p):
    return "Points." in os.path.basename(p)

# tier -> list of (folder prefix, exclude(path) -> bool)
TIERS = {
    "tier1": [
        (HOME + "/Desktop/UMN/hennepin_conservation_easements/", None),
        (HOME + "/Downloads/", None),
        (PI + "st_paul_rc_affordable_housing/shp_plan_regional_parcels/", None),
        (HOME + "/research/brownfield_stpaul/data/raw/parcels/2023/plan_regonal_parcels_2023.gdb/", None),
    ],
    "tier2": [
        (HOME + "/research/hennepin_conservation_easements/", None),
        (HOME + "/Desktop/UMN/hc_easement_simulations/", None),
        (PI + "matthew_maps_saint_paul/", is_points),          # Points still read live by green_line
        (HOME + "/research/brownfield_stpaul/data/raw/parcels/",
         lambda p: "/data/raw/parcels/2024/" in p),             # 2024 read by load-brownfields chunk
        (PI + "minneapolis_st_paul_housing_reform_paper/", None),
        (PI + "vacant_land_fees_st_paul_blog/", None),
    ],
    # after the three green_line Points reads were repointed to the Points store
    # and verified identical (parcel_data/verification/green_line_points_verify.R,
    # 2026-11-09), nothing reads matthew_maps' Points shapefiles any more
    "green_line_points": [
        (PI + "matthew_maps_saint_paul/", lambda p: not is_points(p)),
    ],
    # after brownfield_spillovers.qmd load-brownfields was repointed to
    # read_parcels(2024, as_shapefile = TRUE) and checked identical (same 88,732
    # polygons, same PINs for all 1,302 sites; 2026-11-09)
    "brownfield_2024": [
        (HOME + "/research/brownfield_stpaul/data/raw/parcels/2024/", None),
    ],
}

tier = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in TIERS else sys.exit("usage: 09_trash_candidates.py tier1|tier2|green_line_points|brownfield_2024 [--move]")
move = "--move" in sys.argv
RULES = TIERS[tier]
TRASH = HOME + f"/.Trash/parcel_cleanup_{tier}_20261109"
MANIFEST = PD + f"/docs/trash_manifest_{tier}_20261109.csv"
if move and os.path.exists(MANIFEST):
    sys.exit(f"{MANIFEST} exists: {tier} was already moved")

cands = list(csv.DictReader(open(PD + "/docs/deletion_candidates.csv")))
plan, skipped = [], {"icloud_only": 0, "missing": 0, "excluded_live": 0}
for r in cands:
    p = r["path"]
    rule = next(((t, ex) for t, ex in RULES if p.startswith(t)), None)
    if rule is None:
        continue
    assert "/research/parcel_data/" not in p
    if rule[1] and rule[1](p):
        skipped["excluded_live"] += 1
        continue
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        skipped["missing"] += 1
        continue
    if st.st_flags & DATALESS:
        skipped["icloud_only"] += 1
        continue
    plan.append((p, os.path.join(TRASH, os.path.relpath(p, HOME)), st.st_size, rule[0]))

by = {}
for _, _, b, t in plan:
    n, s = by.get(t, (0, 0)); by[t] = (n + 1, s + b)
for t, (n, s) in by.items():
    print(f"{n:6d} files {s/1e9:7.2f} GB  {t.replace(HOME, '~')}")
print(f"TOTAL {len(plan)} files {sum(b for _, _, b, _ in plan)/1e9:.2f} GB | skipped: {skipped}")

if not move:
    print("dry run: nothing moved (use --move)")
    sys.exit(0)

done = []
for src, dst, b, _ in plan:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    os.rename(src, dst)              # same volume: a rename, no copy, no extra space
    done.append((src, dst, b))
with open(MANIFEST, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["original_path", "trash_path", "bytes"]); w.writerows(done)
shutil.copy2(MANIFEST, os.path.join(TRASH, os.path.basename(MANIFEST)))
# remove only folders THIS move emptied: walk up from each moved file's folder
# while it is empty, never above its tier root's parent (pre-existing empty
# folders elsewhere, e.g. inside .git, are left alone)
roots = [t for t, _ in RULES]
for d in sorted({os.path.dirname(s) for s, _, _ in done}, key=len, reverse=True):
    root = next(t for t in roots if (d + "/").startswith(t)).rstrip("/")
    stop = os.path.dirname(root) if root != HOME + "/Downloads" else root
    while d.startswith(stop) and d != stop and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)
print(f"moved {len(done)} files; manifest {MANIFEST}")
