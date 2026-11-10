#!/bin/bash
# Package the store for the Zenodo deposit (DOI 10.5281/zenodo.24116899).
# One uncompressed zip per year and layer (parquet is already compressed);
# paths inside start at standardized/ or standardized_points/, so unzipping
# into $PARCEL_HOME/data puts every partition where read_parcels() looks.
set -euo pipefail

PARCEL_HOME="${PARCEL_HOME:-$HOME/research/parcel_data}"
OUT="$PARCEL_HOME/data/zenodo"
mkdir -p "$OUT"
cd "$PARCEL_HOME/data"

for yr in $(seq 2005 2025); do
  zip -0 -r -q -X "$OUT/parcels_polygons_${yr}.zip" "standardized/year=${yr}"
  zip -0 -r -q -X "$OUT/parcels_points_${yr}.zip"   "standardized_points/year=${yr}"
  echo "$yr done"
done

# docs the readers need, plus the deposit README
cp "$PARCEL_HOME/docs/column_crosswalk.csv" \
   "$PARCEL_HOME/docs/points_column_crosswalk.csv" "$OUT/"
cp "$PARCEL_HOME/docs/zenodo_README.md" "$OUT/README.md"

cd "$OUT"
shasum -a 256 *.zip *.csv README.md > SHA256SUMS.txt
