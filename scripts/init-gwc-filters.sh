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
ENV_VALUES="geom:geom_iieg,geom:geom_inegi"
ENV_DEFAULT="geom:geom_iieg"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-gateway-hub-nginx-1}"
SEXTANTE_CONTAINER="${SEXTANTE_CONTAINER:-sextante}"
LEARN_TAIL="${LEARN_TAIL:-20000}"

usage() {
  cat >&2 <<'USAGE'
Uso:
  init-gwc-filters.sh <workspace:capa>[=<valor CQL>] ...
  init-gwc-filters.sh --learn [workspace:capa ...]

Declara en GeoWebCache los parameter filters que permiten cachear una capa:
  - ENV         siempre (geom:geom_iieg | geom:geom_inegi)
  - CQL_FILTER  solo si se pasa un valor

Sin estos filtros GWC ni siquiera procesa la peticion: se pierden el cache y el
metatiling 4x4, y los poligonos que cruzan el borde de un tile salen cortados.

El valor tiene que coincidir BYTE A BYTE con el que manda el visor. mapalab
envuelve el filtro de fecha en parentesis -- "(fecha >= '2025-01-01' AND fecha <
'2026-01-01')" -- y combina varios con ' OR '. Declararlo a mano casi siempre
falla; para eso esta --learn.

--learn saca los valores del trafico real, en este orden:
  1. log del gateway, que ya registra el request_uri completo
  2. audit del monitor de GeoServer, si se activa a mano en la UI (Monitor ->
     configuracion): montarlo por archivo no sirve, GeoServer lo reescribe al
     arrancar

Sin argumentos extra aprende todas las capas que encuentre; con argumentos se
limita a esas. Un valor de CQL no declarado se sigue sirviendo (HTTP 200), solo
que sin cache: conviene declarar los de uso real y no la cola larga de fechas,
porque cada valor multiplica el disco del cache.

Varias capas a mano: como argumentos separados, o en una sola cadena separadas
por ';' (necesario desde make, donde el valor llega como un unico argumento).

Variables: GATEWAY_CONTAINER, SEXTANTE_CONTAINER, LEARN_TAIL.

Ejemplos:
  init-gwc-filters.sh general:cuerpos_de_agua_50k
  init-gwc-filters.sh "economia:cultivos=prediccion = 'Agave'"
  init-gwc-filters.sh --learn
  init-gwc-filters.sh --learn economia:cultivos
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

apply_filters() {
  local layer="$1" cql="$2"
  local current
  current=$(curl -s --max-time 30 -u "$AUTH" "$GEOSERVER_URL/gwc/rest/layers/${layer}.xml")
  if ! printf '%s' "$current" | grep -q "<GeoServerLayer>"; then
    echo "  x $layer (no esta publicado en GWC)" >&2
    return 1
  fi

  local nvals
  nvals=$(printf '%s' "$cql" | tr -cd '\x1f' | wc -c)

  local payload
  payload=$(GWC_XML="$current" ENV_VALUES="$ENV_VALUES" ENV_DEFAULT="$ENV_DEFAULT" CQL="$cql" \
    python3 "$SCRIPT_DIR/lib/gwc_filters.py")

  local code
  code=$(curl -s -o /dev/null --max-time 30 -w "%{http_code}" -u "$AUTH" \
    -X POST -H "Content-Type: text/xml; charset=UTF-8" --data-binary "$payload" \
    "$GEOSERVER_URL/gwc/rest/layers/${layer}.xml")

  if [ "$code" = "200" ]; then
    echo "  + $layer${cql:+ (CQL: $((nvals + 1)) valor(es))}"
    return 0
  fi
  echo "  x $layer (HTTP $code)" >&2
  return 1
}

learn_entries() {
  local raw=""

  if docker inspect "$GATEWAY_CONTAINER" >/dev/null 2>&1; then
    echo "Leyendo CQL_FILTER reales del log del gateway ($GATEWAY_CONTAINER)..." >&2
    raw=$(docker logs "$GATEWAY_CONTAINER" --tail "$LEARN_TAIL" 2>/dev/null | grep -F "CQL_FILTER" || true)
  fi

  if [ -z "$raw" ]; then
    echo "Sin datos en el gateway; probando el audit del monitor de GeoServer..." >&2
    raw=$(docker exec -u root "$SEXTANTE_CONTAINER" \
      sh -c 'cat /opt/geoserver/data_dir/monitoring/*.log 2>/dev/null' 2>/dev/null | grep -F "CQL_FILTER" || true)
  fi

  if [ -z "$raw" ]; then
    cat >&2 <<'EOF'
No se encontro ninguna peticion con CQL_FILTER.

  - El log del gateway solo conserva lo que siga en el buffer de Docker.
  - El audit del monitor hay que activarlo desde la UI de GeoServer; el archivo
    monitor.properties lo reescribe GeoServer en cada arranque.

Navega el visor con las capas que quieras cachear y reintenta.
EOF
    return 1
  fi

  printf '%s\n' "$raw" | GWC_ONLY="$*" python3 "$SCRIPT_DIR/lib/gwc_learn.py"
}

[ "$#" -eq 0 ] && usage

entries=()

if [ "${1:-}" = "--learn" ]; then
  shift
  learned=$(learn_entries "$@") || exit 1
  if [ -z "$learned" ]; then
    echo "Se encontraron peticiones, pero ninguna con LAYERS y CQL_FILTER utilizables." >&2
    exit 1
  fi
  echo "$learned" | cut -c1-110 | sed 's/^/  aprendido: /'
  mapfile -t entries <<< "$learned"
else
  for arg in "$@"; do
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [ -n "$line" ] && entries+=("$line")
    done < <(printf '%s\n' "${arg//;/$'\n'}")
  done
fi

if [ "${#entries[@]}" -eq 0 ]; then
  echo "No se recibio ninguna capa." >&2
  exit 2
fi

wait_for_gwc
echo "Declarando parameter filters en GWC..."

declare -A grouped=()
order=()
for entry in "${entries[@]}"; do
  if [[ "$entry" == *"="* ]]; then
    layer="${entry%%=*}"
    cql="${entry#*=}"
  else
    layer="$entry"
    cql=""
  fi
  if [ -z "${grouped[$layer]+x}" ]; then
    order+=("$layer")
    grouped["$layer"]="$cql"
  elif [ -n "$cql" ]; then
    if [ -n "${grouped[$layer]}" ]; then
      grouped["$layer"]="${grouped[$layer]}"$'\x1f'"$cql"
    else
      grouped["$layer"]="$cql"
    fi
  fi
done

ok=0
fail=0
for layer in "${order[@]}"; do
  if apply_filters "$layer" "${grouped[$layer]}"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
  fi
done

echo "Filtros aplicados: $ok · con error: $fail"
[ "$fail" -eq 0 ]
