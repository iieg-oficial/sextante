#!/bin/bash
set +H
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://${GEOSERVER_BIND_ADDR:-127.0.0.1}:${GEOSERVER_PORT:-8080}/${GEOSERVER_CONTEXT_ROOT:-sextante}"
source "$PROJECT_DIR/scripts/lib/gs_curl.sh"
source "$PROJECT_DIR/make/lib.sh"

WORKSPACE=raster
CONTENEDOR=${GEOSERVER_CONTAINER_NAME:-sextante}
DATA_DIR=/opt/geoserver/data_dir
RAIZ=geoserver-raster
REST="$GEOSERVER_URL/rest"

CARPETA="${1:-}"
MODO="${2:-}"
if [ "$CARPETA" = "--revisar" ]; then
  CARPETA=""
  MODO="--revisar"
fi

http_code() {
  gs_curl -s -o /dev/null -w "%{http_code}" "$@"
}

nombres_json() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1:]:
    d = d.get(k) or {}
    if isinstance(d, str):
        d = {}
for item in d if isinstance(d, list) else []:
    print(item["name"])' "$@" 2>/dev/null
}

normalizar() {
  local ruta=${1#file:}
  ruta=${ruta#//}
  ruta=${ruta#"$DATA_DIR"/}
  ruta=${ruta#/}
  ruta=${ruta#data/}
  printf '%s' "$ruta"
}

if [ "$(http_code "$REST/workspaces/$WORKSPACE.json")" != "200" ]; then
  echo "✗ No existe el workspace $WORKSPACE en $GEOSERVER_URL" >&2
  exit 1
fi

if [ -z "$CARPETA" ]; then
  mapfile -t carpetas < <(docker exec "$CONTENEDOR" find "$DATA_DIR/$RAIZ" -mindepth 1 -maxdepth 1 -type d \
    -printf "$RAIZ/%f\n" | sort)
  [ ${#carpetas[@]} -gt 0 ] || fail "Rasters: no hay carpetas en $RAIZ"
  CARPETA=$(pick 'Carpeta' "${carpetas[@]}") || exit 1
  rule
fi
CARPETA=${CARPETA%/}

if [[ "$CARPETA" == /* || "$CARPETA" == *..* ]]; then
  echo "✗ La carpeta va relativa al data dir y sin '..': $CARPETA" >&2
  exit 1
fi

if ! docker exec "$CONTENEDOR" test -d "$DATA_DIR/$CARPETA"; then
  echo "✗ No existe $DATA_DIR/$CARPETA dentro de $CONTENEDOR" >&2
  exit 1
fi

mapfile -t ARCHIVOS < <(docker exec "$CONTENEDOR" find "$DATA_DIR/$CARPETA" -maxdepth 1 -type f \
  \( -iname '*.tif' -o -iname '*.tiff' \) -printf '%f\n' | sort)
[ ${#ARCHIVOS[@]} -gt 0 ] || fail "Rasters: $CARPETA no tiene .tif"

echo "Leyendo lo que ya hay en $WORKSPACE..."

declare -A CAPAS=()
while read -r capa; do
  [ -n "$capa" ] && CAPAS[$capa]=1
done < <(gs_curl -s "$REST/workspaces/$WORKSPACE/layers.json" | nombres_json layers layer)

declare -A STORE_DE_RUTA=()
declare -A RUTA_DE_STORE=()
while read -r store; do
  [ -n "$store" ] || continue
  url=$(gs_curl -s "$REST/workspaces/$WORKSPACE/coveragestores/$store.json" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["coverageStore"].get("url", ""), end="")' 2>/dev/null)
  ruta=$(normalizar "$url")
  RUTA_DE_STORE[$store]=$ruta
  [ -n "$ruta" ] && STORE_DE_RUTA[$ruta]=$store
done < <(gs_curl -s "$REST/workspaces/$WORKSPACE/coveragestores.json" | nombres_json coverageStores coverageStore)

POR_PUBLICAR=()
SOLO_CAPA=()
existentes=0
conflictos=0

echo
for archivo in "${ARCHIVOS[@]}"; do
  nombre=${archivo%.*}
  ruta="$CARPETA/$archivo"

  if ! [[ "$nombre" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "  ✗ $archivo: el nombre solo admite letras, numeros, guion y guion bajo"
    conflictos=$((conflictos + 1))
    continue
  fi

  if [ -n "${CAPAS[$nombre]:-}" ]; then
    echo "  = $nombre: ya existe la capa $WORKSPACE:$nombre"
    existentes=$((existentes + 1))
    continue
  fi

  otro=${STORE_DE_RUTA[$ruta]:-}
  if [ -n "$otro" ] && [ "$otro" != "$nombre" ]; then
    echo "  = $nombre: el archivo ya esta publicado en el store $otro"
    existentes=$((existentes + 1))
    continue
  fi

  if [ -n "${RUTA_DE_STORE[$nombre]+x}" ] && [ "${RUTA_DE_STORE[$nombre]}" != "$ruta" ]; then
    echo "  ✗ $nombre: ya hay un store con ese nombre apuntando a ${RUTA_DE_STORE[$nombre]}"
    conflictos=$((conflictos + 1))
    continue
  fi

  if [ "$otro" = "$nombre" ]; then
    echo "  + $nombre (el store ya existe, falta la capa)"
    SOLO_CAPA+=("$nombre")
  else
    echo "  + $nombre"
  fi
  POR_PUBLICAR+=("$archivo")
done

echo
echo "${#ARCHIVOS[@]} archivos · por publicar: ${#POR_PUBLICAR[@]} · ya existen: $existentes · con conflicto: $conflictos"

if [ "$MODO" = "--revisar" ] || [ ${#POR_PUBLICAR[@]} -eq 0 ]; then
  exit 0
fi

rule
confirm "Se publicaran ${#POR_PUBLICAR[@]} capas en $WORKSPACE desde $CARPETA" 'publicar'
rule

declare -A SIN_STORE=()
for nombre in "${SOLO_CAPA[@]}"; do
  SIN_STORE[$nombre]=1
done

publicadas=0
fallidas=()

for archivo in "${POR_PUBLICAR[@]}"; do
  nombre=${archivo%.*}

  if [ -z "${SIN_STORE[$nombre]:-}" ]; then
    payload="{\"coverageStore\":{\"name\":\"$nombre\",\"type\":\"GeoTIFF\",\"enabled\":true,\"workspace\":{\"name\":\"$WORKSPACE\"},\"url\":\"file:$CARPETA/$archivo\"}}"
    code=$(http_code -XPOST -H "Content-Type: application/json" -d "$payload" "$REST/workspaces/$WORKSPACE/coveragestores")
    if [ "$code" != "201" ]; then
      echo "  ✗ $nombre: no se pudo crear el store (HTTP $code)"
      fallidas+=("$archivo")
      continue
    fi
  fi

  coverage_json="{\"coverage\":{\"name\":\"$nombre\",\"nativeName\":\"$nombre\",\"nativeCoverageName\":\"$nombre\",\"title\":\"$nombre\",\"enabled\":true}}"
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$coverage_json" \
    "$REST/workspaces/$WORKSPACE/coveragestores/$nombre/coverages")
  if [ "$code" != "201" ]; then
    echo "  ✗ $nombre: store listo pero la capa no se publico (HTTP $code)"
    fallidas+=("$archivo")
    continue
  fi

  code=$(http_code -XPUT -H "Content-Type: application/json" -d '{"coverage":{"enabled":true}}' \
    "$REST/workspaces/$WORKSPACE/coveragestores/$nombre/coverages/$nombre?calculate=nativebbox,latlonbbox")
  if [ "$code" != "200" ]; then
    echo "  ✗ $nombre: publicada pero sin recalcular encuadres (HTTP $code)"
    fallidas+=("$archivo")
    continue
  fi

  echo "  ✓ $nombre"
  publicadas=$((publicadas + 1))
done

echo
echo "Publicadas: $publicadas · fallidas: ${#fallidas[@]}"
if [ ${#fallidas[@]} -gt 0 ]; then
  printf '  %s\n' "${fallidas[@]}"
  exit 1
fi
