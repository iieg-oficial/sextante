#!/bin/bash
set +H
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

GRIDSET_NAME="Jalisco_ITRF2008_13N"
GRIDSET_SRS=6368
GRIDSET_MINX=-1396865.12
GRIDSET_MINY=1337614.43
GRIDSET_MAXX=2759543.0
GRIDSET_MAXY=3809957.21
GRIDSET_TILE=256
GRIDSET_LEVELS=18

FORCE="${1:-}"

wait_for_geoserver() {
  local max_attempts=24
  local attempt=0
  echo "Esperando GeoServer (REST/GWC)..."
  local http_code
  until http_code=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/gwc/rest/gridsets") && [ "$http_code" = "200" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "GWC REST no respondió 200 después de $((max_attempts * 5)) segundos (último code=$http_code)." >&2
      exit 1
    fi
    sleep 5
  done
  echo "GeoServer listo."
}

build_gridset_xml() {
  python3 - "$GRIDSET_NAME" "$GRIDSET_SRS" "$GRIDSET_MINX" "$GRIDSET_MINY" "$GRIDSET_MAXX" "$GRIDSET_MAXY" "$GRIDSET_TILE" "$GRIDSET_LEVELS" <<'PYEOF'
import sys
name, srs = sys.argv[1], sys.argv[2]
minx, miny, maxx, maxy = map(float, sys.argv[3:7])
tile, levels = int(sys.argv[7]), int(sys.argv[8])
res0 = max((maxx - minx) / tile, (maxy - miny) / tile)
side = res0 * tile
maxx, maxy = minx + side, miny + side
res = [res0 / (2 ** i) for i in range(levels)]
out = ["<gridSet>", f"  <name>{name}</name>", f"  <srs><number>{srs}</number></srs>", "  <extent><coords>"]
out += [f"    <double>{v}</double>" for v in (minx, miny, maxx, maxy)]
out += ["  </coords></extent>", "  <alignTopLeft>false</alignTopLeft>", "  <resolutions>"]
out += [f"    <double>{r}</double>" for r in res]
out += ["  </resolutions>", "  <metersPerUnit>1.0</metersPerUnit>", "  <pixelSize>2.8E-4</pixelSize>", "  <scaleNames>"]
out += [f"    <string>{name}:{i}</string>" for i in range(levels)]
out += ["  </scaleNames>", f"  <tileHeight>{tile}</tileHeight>", f"  <tileWidth>{tile}</tileWidth>", "  <yCoordinateFirst>false</yCoordinateFirst>", "</gridSet>"]
print("\n".join(out))
PYEOF
}

wait_for_geoserver

http_code=$(curl -s -o /dev/null --max-time 15 -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/gwc/rest/gridsets/$GRIDSET_NAME.xml")
if [ "$http_code" = "200" ]; then
  if [ "$FORCE" != "--force" ]; then
    echo "Gridset '$GRIDSET_NAME' ya existe; skip (usa --force para reescribir)."
    exit 0
  fi
  # Actualizar en sitio un gridset en uso corrompe el extent en GWC; borrar y recrear limpio.
  echo "Gridset '$GRIDSET_NAME' existe; borrando para recrear limpio (--force)..."
  curl -s -o /dev/null --max-time 30 -u "$AUTH" -X DELETE "$GEOSERVER_URL/gwc/rest/gridsets/$GRIDSET_NAME"
fi

payload=$(build_gridset_xml)

printf "Aplicando gridset '%s' (EPSG:%s, %s niveles)... " "$GRIDSET_NAME" "$GRIDSET_SRS" "$GRIDSET_LEVELS"
http_code=$(curl -s -o /dev/null --max-time 30 -w "%{http_code}" -u "$AUTH" \
  -X PUT \
  -H "Content-Type: application/xml" \
  -d "$payload" \
  "$GEOSERVER_URL/gwc/rest/gridsets/$GRIDSET_NAME")

if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
  echo "OK"
else
  echo "FAIL (http=$http_code)" >&2
  exit 1
fi
