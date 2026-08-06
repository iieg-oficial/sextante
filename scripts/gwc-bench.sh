#!/usr/bin/env bash
set +H
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

CONTAINER="${SEXTANTE_CONTAINER:-sextante}"
CONTEXT="${GEOSERVER_CONTEXT_ROOT:-sextante}"
BASE="http://localhost:8080/$CONTEXT"
ZOOM="${BENCH_ZOOM:-12}"
COLS="${BENCH_COLS:-10}"
ROWS="${BENCH_ROWS:-7}"

CAPAS_DEFAULT="general:limite_municipal general:cabeceras_municipales general:cuerpos_de_agua_50k general:curvas_de_nivel_render"

usage() {
  cat >&2 <<'USAGE'
Uso:
  gwc-bench.sh [workspace:capa ...]

Mide el rendimiento de render de tiles para comparar el mismo entorno antes y
despues de un cambio: importar un cache, crear indices, cambiar la JVM.

Por cada capa pide una pantalla completa (10x7 tiles de 256 px, como el visor) y
reporta el tiempo total y cuantos salieron de GeoWebCache. Correrlo dos veces
seguidas separa el costo de render del de servir cacheado.

Se mide DENTRO del contenedor, saltandose el gateway: su proxy_cache devuelve la
copia de la primera respuesta y enmascara el resultado de GWC.

Variables: BENCH_ZOOM (12), BENCH_COLS (10), BENCH_ROWS (7), SEXTANTE_CONTAINER.

Ejemplo de uso comparativo:
  scripts/gwc-bench.sh > /tmp/antes.txt
  make gwc-import ARGS=/tmp/gwc-cache-z13.tar.gz
  scripts/gwc-bench.sh > /tmp/despues.txt
  diff -y /tmp/antes.txt /tmp/despues.txt
USAGE
  exit 2
}

[ "${1:-}" = "--help" ] && usage

capas=("$@")
[ "${#capas[@]}" -eq 0 ] && read -ra capas <<<"$CAPAS_DEFAULT"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "No existe el contenedor '$CONTAINER'. Ajusta SEXTANTE_CONTAINER." >&2
  exit 1
fi

urls_de() {
  local layer="$1" ws="${1%%:*}" ly="${1##*:}"
  python3 - "$ws" "$ly" "$ZOOM" "$COLS" "$ROWS" "$CONTEXT" <<'PY'
import math, sys, urllib.parse
ws, ly, z, cols, rows, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
span = 40075016.68557849 / (2 ** z)
o = -20037508.342789244
c0 = math.floor((-11541000 - o) / span)
r0 = math.floor((2370000 - o) / span)
for i in range(cols):
    for j in range(rows):
        x0, y0 = o + (c0 + i - cols // 2) * span, o + (r0 + j - rows // 2) * span
        bb = f"{x0:.6f},{y0:.6f},{x0+span:.6f},{y0+span:.6f}"
        q = (f"REQUEST=GetMap&SERVICE=WMS&VERSION=1.1.0&FORMAT=image%2Fpng&STYLES="
             f"&TRANSPARENT=true&LAYERS={urllib.parse.quote(ws + ':' + ly)}&TILED=true"
             f"&ENV=geom%3Ageom_iieg&WIDTH=256&HEIGHT=256&SRS=EPSG%3A3857&BBOX={bb}")
        print(f"http://localhost:8080/{ctx}/{ws}/wms?{q}")
PY
}

total_tiles=$((COLS * ROWS))
echo "gwc-bench · z$ZOOM · ${COLS}x${ROWS} = $total_tiles tiles por capa · contenedor $CONTAINER"
echo "blobstore: $(docker exec "$CONTAINER" du -sm /opt/geoserver/data_dir/gwc 2>/dev/null | cut -f1 || echo '?') MB"
echo
printf "%-46s %9s %8s %8s\n" "CAPA" "TIEMPO" "HIT" "MISS"
printf -- "%.0s-" {1..76}; echo

for layer in "${capas[@]}"; do
  urls_de "$layer" > /tmp/gwc-bench-urls.txt
  docker cp /tmp/gwc-bench-urls.txt "$CONTAINER:/tmp/gwc-bench-urls.txt" >/dev/null 2>&1

  read -r ms hit miss < <(docker exec "$CONTAINER" sh -c '
    s=$(date +%s%N); hit=0; miss=0
    while IFS= read -r u; do
      r=$(curl -s -o /dev/null -D - "$u" | grep -i "geowebcache-cache-result" | tr -d "\r" | awk "{print \$2}")
      case "$r" in HIT) hit=$((hit+1));; *) miss=$((miss+1));; esac
    done < /tmp/gwc-bench-urls.txt
    e=$(date +%s%N); echo "$(( (e-s)/1000000 )) $hit $miss"')

  seg=$(awk -v m="$ms" 'BEGIN{printf "%.2f", m/1000}')
  printf "%-46s %8ss %8s %8s\n" "$layer" "$seg" "$hit" "$miss"
done

echo
echo "Correrlo dos veces: la 1a mide render, la 2a cuanto aporta el cache."
