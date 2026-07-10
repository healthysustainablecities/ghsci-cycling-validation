#!/bin/bash
# Build one <slug>.pmtiles per city from the GeoJSONSeq layers exported by
# _export_validation_tiles.py (copied out of the ghsci container).
set -e
SCRATCH="/c/Users/E33390/AppData/Local/Temp/claude/C--Users-E33390-OneDrive---RMIT-University-GOHSC-cycling-indicators---General/289836d9-34cf-416f-bf2b-561a5d10ce3c/scratchpad"
DATA="$SCRATCH/data"
WIN_DATA="C:/Users/E33390/AppData/Local/Temp/claude/C--Users-E33390-OneDrive---RMIT-University-GOHSC-cycling-indicators---General/289836d9-34cf-416f-bf2b-561a5d10ce3c/scratchpad/data"
mkdir -p "$DATA"

tc() { MSYS_NO_PATHCONV=1 docker run --rm -v "$WIN_DATA:/data" tippecanoe:local "$@"; }

# layer name -> extra tippecanoe args (all builds share -z13)
layer_args() {
  case "$1" in
    lts)          echo "-Z8 --drop-densest-as-needed --extend-zooms-if-still-dropping" ;;
    grid)         echo "-Z8 --coalesce-smallest-as-needed --drop-smallest-as-needed --maximum-tile-bytes=3000000" ;;
    destinations|pt_frequent) echo "-Z8 --drop-densest-as-needed" ;;
    pos_any|pos_large|ac_local|ac_complete) echo "-Z11 --drop-densest-as-needed" ;;
    boundary)     echo "-Z4" ;;
  esac
}

for slug in "$@"; do
  echo "== $slug"
  [ -d "$DATA/$slug" ] || docker cp "ghsci:/tmp/validation_tiles/$slug" "$DATA/"
  parts=()
  for f in "$DATA/$slug"/*.geojsonl; do
    layer=$(basename "$f" .geojsonl)
    args=$(layer_args "$layer")
    echo "-- $layer ($args)"
    tc tippecanoe -q --force -o "/data/$slug/$layer.pmtiles" -l "$layer" \
      -z12 $args "/data/$slug/$layer.geojsonl"
    parts+=("/data/$slug/$layer.pmtiles")
  done
  tc tile-join -q --force -pk -o "/data/$slug.pmtiles" "${parts[@]}"
  ls -lh "$DATA/$slug.pmtiles"
done
