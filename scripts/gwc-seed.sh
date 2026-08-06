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

GEOSERVER_URL="http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"
SEED_FILE="${SEED_FILE:-$PROJECT_DIR/config/gwc-seed.txt}"
FILTERS_FILE="${FILTERS_FILE:-$PROJECT_DIR/config/gwc-filters.txt}"
GRIDSET="${GWC_SEED_GRIDSET:-EPSG:900913}"
BBOX="${GWC_SEED_BBOX:--11766470.2,2149050.1,-11295588.7,2601813.2}"
ZOOM_MIN="${GWC_SEED_ZOOM_MIN:-6}"
ZOOM_MAX="${GWC_SEED_ZOOM_MAX:-13}"
THREADS="${GWC_SEED_THREADS:-2}"
ENV_VALUE="${GWC_SEED_ENV:-geom:geom_iieg}"
FORMAT="${GWC_SEED_FORMAT:-image/png}"

usage() {
  cat >&2 <<'USAGE'
Uso:
  gwc-seed.sh                       # siembra config/gwc-seed.txt
  gwc-seed.sh --auto                # capas iniciales del visor + config/gwc-seed-auto.txt
  gwc-seed.sh <workspace:capa> ...  # siembra solo esas capas
  gwc-seed.sh --status              # avance de las tareas en curso
  gwc-seed.sh --stop                # cancela todas las tareas de seed

--auto lee del catalogo de mapalab (MAPALAB_API_URL) las capas que el visor
enciende al abrirse, asi que si esas capas cambian el siguiente `up` siembra las
nuevas sin tocar configuracion. Les suma las de config/gwc-seed-auto.txt, que es
donde van las caras que no estan en la vista inicial. Es lo que corre `make up` y
`make deploy`; si el catalogo no responde, avisa y sigue con el archivo.

Pre-genera tiles en GeoWebCache para que el primer visitante de una zona no pague
el render. Sin esto el cache solo ayuda a partir de la segunda visita, y en un
despliegue nuevo el blobstore arranca vacio.

Requisito: la capa debe tener declarado el parameter filter de ENV
(scripts/init-gwc-filters.sh). Sin el, GWC descarta la peticion del visor y los
tiles sembrados no se usan nunca.

Solo se siembran capas SIN CQL_FILTER. Las que lo llevan dependen de la fecha que
elija el usuario; sembrar una combinacion que nadie pide solo gasta disco.

El seed corre en background dentro de GeoServer: el script encola y vuelve. Para
seguirlo, `--status`. Cada nivel de zoom cuadruplica los tiles; medido 10.8 KB por
tile, cubrir Jalisco con 45 capas son 5.6 GB hasta z13 y 22.3 GB hasta z14.

Variables: SEED_FILE, GWC_SEED_GRIDSET, GWC_SEED_BBOX, GWC_SEED_ZOOM_MIN,
GWC_SEED_ZOOM_MAX, GWC_SEED_THREADS, GWC_SEED_ENV, GWC_SEED_FORMAT.
USAGE
  exit 2
}

wait_for_gwc() {
  local attempt=0 code
  until code=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/gwc/rest/layers") && [ "$code" = "200" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 24 ]; then
      echo "GWC REST no respondio 200 tras 120s (ultimo code=$code)." >&2
      exit 1
    fi
    sleep 5
  done
}

show_status() {
  curl -s --max-time 30 -u "$AUTH" "$GEOSERVER_URL/gwc/rest/seed.json" \
    | python3 "$SCRIPT_DIR/lib/gwc_seed_status.py"
}

stop_all() {
  local -a capas=("$@")
  if [ "${#capas[@]}" -eq 0 ]; then
    local layer
    while IFS= read -r entry; do
      layer="${entry%%=*}"
      case " ${capas[*]} " in *" $layer "*) ;; *) capas+=("$layer") ;; esac
    done < <(read_seed_file "$SEED_FILE"; read_seed_file "$AUTO_FILE")
  fi

  local n=0
  for layer in "${capas[@]}"; do
    local body
    body=$(curl -s --max-time 30 -u "$AUTH" -X POST -d "kill_all=all" \
      "$GEOSERVER_URL/gwc/rest/seed/${layer}")
    local killed
    killed=$(printf '%s' "$body" | grep -o 'RUNNING\]' | wc -l)
    if [ "$killed" -gt 0 ]; then
      echo "  - $layer ($killed tarea(s))"
      n=$((n + killed))
    fi
  done

  if [ "$n" -gt 0 ]; then
    echo "$n tarea(s) canceladas."
  else
    echo "No habia tareas en curso de las capas conocidas."
    echo "Para una capa que no este en los archivos: gwc-seed.sh --stop <workspace:capa>"
  fi
}

build_payload() {
  local layer="$1" zmin="$2" zmax="$3" cql="${4:-}"
  local minx miny maxx maxy cql_entry=''
  IFS=',' read -r minx miny maxx maxy <<<"$BBOX"
  if [ -n "$cql" ]; then
    cql_entry=$(CQL="$cql" python3 -c '
import os
from xml.sax.saxutils import escape
print("    <entry>\n      <string>CQL_FILTER</string>\n      <string>%s</string>\n    </entry>"
      % escape(os.environ["CQL"]))')
  fi
  cat <<EOF
<seedRequest>
  <name>${layer}</name>
  <bounds>
    <coords>
      <double>${minx}</double>
      <double>${miny}</double>
      <double>${maxx}</double>
      <double>${maxy}</double>
    </coords>
  </bounds>
  <gridSetId>${GRIDSET}</gridSetId>
  <zoomStart>${zmin}</zoomStart>
  <zoomStop>${zmax}</zoomStop>
  <format>${FORMAT}</format>
  <type>seed</type>
  <threadCount>${THREADS}</threadCount>
  <parameters>
    <entry>
      <string>ENV</string>
      <string>${ENV_VALUE}</string>
    </entry>
${cql_entry}
  </parameters>
</seedRequest>
EOF
}

declared_cqls() {
  local layer="$1"
  [ -f "$FILTERS_FILE" ] || return 0
  while IFS= read -r line; do
    line="${line%%#*}"
    case "$line" in
      "$layer="*) printf '%s\n' "${line#*=}" ;;
    esac
  done < "$FILTERS_FILE"
}

post_seed() {
  local layer="$1" zmin="$2" zmax="$3" cql="${4:-}"
  curl -s -o /dev/null --max-time 60 -w "%{http_code}" -u "$AUTH" \
    -X POST -H "Content-Type: text/xml" \
    --data-binary "$(build_payload "$layer" "$zmin" "$zmax" "$cql")" \
    "$GEOSERVER_URL/gwc/rest/seed/${layer}.xml"
}

seed_layer() {
  local layer="$1" zmin="$2" zmax="$3"
  local current
  current=$(curl -s --max-time 30 -u "$AUTH" "$GEOSERVER_URL/gwc/rest/layers/${layer}.xml")
  if ! printf '%s' "$current" | grep -q "<GeoServerLayer>"; then
    echo "  x $layer (no esta publicado en GWC)" >&2
    return 1
  fi
  if ! printf '%s' "$current" | grep -q "<key>ENV</key>"; then
    echo "  x $layer (sin parameter filter de ENV; corre init-gwc-filters.sh antes)" >&2
    return 1
  fi

  local -a cqls=()
  while IFS= read -r c; do [ -n "$c" ] && cqls+=("$c"); done < <(declared_cqls "$layer")

  if [ "${#cqls[@]}" -eq 0 ]; then
    local code
    code=$(post_seed "$layer" "$zmin" "$zmax")
    if [ "$code" = "200" ]; then
      echo "  + $layer (z${zmin}-${zmax})"
      return 0
    fi
    echo "  x $layer (HTTP $code)" >&2
    return 1
  fi

  local n=0
  for cql in "${cqls[@]}"; do
    local code
    code=$(post_seed "$layer" "$zmin" "$zmax" "$cql")
    if [ "$code" = "200" ]; then
      n=$((n + 1))
    else
      echo "  x $layer (HTTP $code) con CQL: ${cql:0:60}..." >&2
    fi
  done

  if [ "$n" -gt 0 ]; then
    echo "  + $layer (z${zmin}-${zmax}, $n combinacion(es) de CQL)"
    return 0
  fi
  return 1
}

read_seed_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && printf '%s\n' "$line"
  done < "$file"
}

AUTO_FILE="${AUTO_FILE:-$PROJECT_DIR/config/gwc-seed-auto.txt}"

case "${1:-}" in
  --help|-h) usage ;;
  --status)  wait_for_gwc; show_status; exit 0 ;;
  --stop)    shift; wait_for_gwc; stop_all "$@"; exit 0 ;;
esac

entries=()
if [ "${1:-}" = "--auto" ]; then
  if [ -n "${MAPALAB_API_URL:-}" ]; then
    iniciales=$(MAPALAB_API_URL="$MAPALAB_API_URL" python3 "$SCRIPT_DIR/lib/gwc_seed_layers.py" 2>&1)
    if [ "$?" -eq 0 ]; then
      n=0
      while IFS= read -r l; do [ -n "$l" ] && { entries+=("$l"); n=$((n + 1)); }; done <<<"$iniciales"
      echo "Capas iniciales del visor segun el catalogo: $n"
    else
      echo "WARNING: no se pudo leer el catalogo, se usa solo $AUTO_FILE" >&2
      printf '  %s\n' "$iniciales" >&2
    fi
  else
    echo "WARNING: MAPALAB_API_URL no esta en el .env; se usa solo $AUTO_FILE" >&2
  fi
  while IFS= read -r l; do entries+=("$l"); done < <(read_seed_file "$AUTO_FILE")
elif [ "$#" -eq 0 ]; then
  if [ ! -f "$SEED_FILE" ]; then
    echo "No existe $SEED_FILE y no se pasaron capas." >&2
    usage
  fi
  echo "Sembrando $SEED_FILE"
  while IFS= read -r l; do entries+=("$l"); done < <(read_seed_file "$SEED_FILE")
else
  entries=("$@")
fi

if [ "${#entries[@]}" -eq 0 ]; then
  echo "Nada que sembrar."
  exit 0
fi

wait_for_gwc
echo "Encolando seeds en GWC (gridset $GRIDSET, ENV $ENV_VALUE, $THREADS hilos)..."

declare -A ranges=()
order=()
for entry in "${entries[@]}"; do
  if [[ "$entry" == *"="* ]]; then
    layer="${entry%%=*}"
    range="${entry#*=}"
  else
    layer="$entry"
    range=""
  fi
  if [ -z "${ranges[$layer]+x}" ]; then
    order+=("$layer")
    ranges["$layer"]="$range"
  elif [ -n "$range" ]; then
    ranges["$layer"]="$range"
  fi
done

ok=0
fail=0
for layer in "${order[@]}"; do
  range="${ranges[$layer]}"
  if [ -n "$range" ]; then
    zmin="${range%%-*}"
    zmax="${range##*-}"
  else
    zmin="$ZOOM_MIN"
    zmax="$ZOOM_MAX"
  fi
  if seed_layer "$layer" "$zmin" "$zmax"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done

echo "Seeds encolados: $ok · con error: $fail"
echo "Avance: scripts/gwc-seed.sh --status   ·   cancelar: --stop"

exit 0
