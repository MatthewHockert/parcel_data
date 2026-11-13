#!/bin/bash
# 01b_collect_2025.sh
# Copy the 2025 MetroGIS release (7-county Parcels{County}.shp, files dated
# Jan 2026; found in st_paul_rc_affordable_housing/shp_plan_regional_parcels)
# into data/raw/2025/, polygons only, original file names kept.
# Waits on iCloud: requests each evicted file and copies it once local.
# Verifies byte size after copy. Rerunnable.
SRC="$HOME/Desktop/Personal Info/st_paul_rc_affordable_housing/shp_plan_regional_parcels"
DST="$PARCEL_HOME/data/raw/2025"
mkdir -p "$DST"
for i in $(seq 1 120); do
  left=0
  for c in Anoka Carver Dakota Hennepin Ramsey Scott Washington; do
    for e in shp shx dbf prj cpg; do
      f="$SRC/Parcels$c.$e"; [ -e "$f" ] || continue
      d="$DST/Parcels$c.$e"
      if [ -f "$d" ] && [ "$(stat -f %z "$d")" = "$(stat -f %z "$f")" ]; then continue; fi
      if ls -lO "$f" | grep -q dataless; then brctl download "$f" >/dev/null 2>&1; left=$((left+1)); continue; fi
      cp -p "$f" "$d" && echo "$(date +%H:%M) copied Parcels$c.$e"
    done
  done
  [ $left -eq 0 ] && { echo "2025 complete"; break; }
  sleep 60
done
