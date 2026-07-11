#!/bin/bash
# Build three PMTiles archives per city from the GeoJSONSeq layers exported by
# _export_validation_tiles.py (run first, inside the ghsci container):
#   <slug>_lts.pmtiles   dense street network (own archive -> full tile budget)
#   <slug>_grid.pmtiles  100m indicator grid  (own archive -> full tile budget)
#   <slug>.pmtiles       everything else (destinations, PT, POS, ACs, boundary)
# All archives end at z12 (MapLibre overzooms beyond that). IMPORTANT: never use
# --extend-zooms-if-still-dropping here — one layer extending past the others
# makes the joined/advertised maxzoom lie, and layers vanish at high zoom.
#
# Usage (from anywhere): bash build/build_tiles.sh <slug> [<slug> ...]
# Requires: docker image tippecanoe:local (see build/Dockerfile) and the
# "ghsci" container running with /tmp/validation_tiles/<slug> already exported.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$SCRIPT_DIR/_work"
mkdir -p "$WORK"

# Docker Desktop on Windows needs a Windows-style path for -v; pwd -W (Git Bash)
# gives that directly, spaces and all. Falls back to the plain path (WSL2 / Linux).
if MOUNT="$(cd "$WORK" && pwd -W 2>/dev/null)"; then :; else MOUNT="$WORK"; fi

tc() { MSYS_NO_PATHCONV=1 docker run --rm -v "$MOUNT:/data" tippecanoe:local "$@"; }

# below z11, keep only arterial roads and cycleways so overview zooms thin
# cartographically instead of dropping random segments
LTS_ZOOM_FILTER='{"lts":["any",[">=","$zoom",11],["in","highway","motorway","motorway_link","trunk","trunk_link","primary","primary_link","secondary","secondary_link","tertiary","tertiary_link","cycleway"]]}'

layer_args() {
  case "$1" in
    destinations|pt_frequent) echo "-Z8 --drop-densest-as-needed" ;;
    pos_any|pos_large|ac_local|ac_complete) echo "-Z11 --drop-densest-as-needed" ;;
    boundary)     echo "-Z4" ;;
  esac
}

for slug in "$@"; do
  echo "== $slug"
  [ -d "$WORK/$slug" ] || docker cp "ghsci:/tmp/validation_tiles/$slug" "$WORK/"

  echo "-- lts (own archive)"
  tc tippecanoe -q --force -o "/data/${slug}_lts.pmtiles" -l lts -Z8 -z12 \
    -j "$LTS_ZOOM_FILTER" --maximum-tile-bytes=2500000 \
    --drop-densest-as-needed "/data/$slug/lts.geojsonl"

  echo "-- grid (own archive)"
  tc tippecanoe -q --force -o "/data/${slug}_grid.pmtiles" -l grid -Z8 -z12 \
    --maximum-tile-bytes=5000000 --coalesce-smallest-as-needed \
    --drop-smallest-as-needed "/data/$slug/grid.geojsonl"

  parts=()
  for f in "$WORK/$slug"/*.geojsonl; do
    layer=$(basename "$f" .geojsonl)
    if [ "$layer" = "lts" ] || [ "$layer" = "grid" ]; then continue; fi
    args=$(layer_args "$layer")
    echo "-- $layer ($args)"
    tc tippecanoe -q --force -o "/data/$slug/$layer.pmtiles" -l "$layer" \
      -z12 $args "/data/$slug/$layer.geojsonl"
    parts+=("/data/$slug/$layer.pmtiles")
  done
  tc tile-join -q --force -pk -o "/data/$slug.pmtiles" "${parts[@]}"
  echo "-- built:"
  ls -lh "$WORK/$slug.pmtiles" "$WORK/${slug}_lts.pmtiles" "$WORK/${slug}_grid.pmtiles"
  echo "   (copy these + $WORK/$slug/manifest.json into ../tiles/ when ready)"
done
