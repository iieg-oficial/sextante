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
DATA_DIR=/opt/geoserver/data_dir
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
MAX_Z="${MAX_Z:-13}"

usage() {
  cat >&2 <<'USAGE'
Uso:
  gwc-cache.sh export [archivo]     # empaqueta el cache de tiles
  gwc-cache.sh import <archivo>     # lo restaura en este GeoServer

Mueve los tiles ya generados entre entornos para no volver a sembrarlos. Pensado
para GCP, que con 2 cores compartidos tarda horas en lo que aqui son minutos.

Los tiles son portables: la carpeta de cada combinacion se nombra con un hash del
VALOR de los parameter filters (`ENV=geom:geom_iieg`), no de la instalacion, y ese
valor sale de config/gwc-filters.txt, que esta versionado. Mismo archivo de
filtros => mismo hash => los tiles se reutilizan.

MAX_Z (default 13) corta los niveles altos, que son casi todo el peso. Medido
sobre las 7 capas del seed automatico:

  hasta z13    647 MB
  hasta z14    2.1 GB
  hasta z15    7.2 GB

z14 y z15 son el 90% del tamaño y los que menos se visitan: conviene dejarlos al
vuelo salvo que haya una razon concreta. `MAX_Z=15` exporta todo.

AVISO: el cache no sabe si el dato de origen cambio. Si el entorno destino tiene
datos distintos —GCP es staging— los tiles mostrarian los del origen hasta que se
trunquen. Para datos que difieren, sembrar en destino en vez de importar.
USAGE
  exit 2
}

exclude_args() {
  local z
  for z in 14 15 16 17 18 19 20 21; do
    [ "$z" -gt "$MAX_Z" ] && printf -- "--exclude=gwc/*_%s_* " "$z"
  done
}

do_export() {
  local file="${1:-$BACKUP_DIR/gwc-cache-z$MAX_Z-$(date +%Y%m%d_%H%M%S).tar.gz}"
  mkdir -p "$(dirname "$file")"

  if ! docker exec "$CONTAINER" test -d "$DATA_DIR/gwc"; then
    echo "No hay cache que exportar en $DATA_DIR/gwc" >&2
    exit 1
  fi

  echo "Empaquetando el cache hasta z$MAX_Z..."
  # shellcheck disable=SC2046
  docker exec -u root "$CONTAINER" tar -cf - \
    --exclude='gwc/diskquota_page_store_hsql' \
    $(exclude_args) \
    -C "$DATA_DIR" gwc | gzip -1 > "$file"

  if [ ! -s "$file" ]; then
    echo "El paquete salio vacio." >&2
    rm -f "$file"
    exit 1
  fi
  echo "  $file ($(du -h "$file" | cut -f1))"
  echo
  echo "Para llevarlo al otro entorno:"
  echo "  scp $file <destino>:/tmp/"
  echo "  make gwc-import ARGS=/tmp/$(basename "$file")"
}

do_import() {
  local file="${1:-}"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "Falta el archivo a importar." >&2
    usage
  fi

  echo "Restaurando $file en $CONTAINER..."
  if ! gzip -dc "$file" | docker exec -i -u root "$CONTAINER" tar -xf - -C "$DATA_DIR"; then
    echo "Fallo al extraer." >&2
    exit 1
  fi

  docker exec -u root "$CONTAINER" chown -R geoserveruser:geoserverusers "$DATA_DIR/gwc" 2>/dev/null || true
  echo "  ok · $(docker exec "$CONTAINER" du -sh "$DATA_DIR/gwc" | cut -f1) en el blobstore"
  echo
  echo "GeoWebCache lee el disco al vuelo: no hace falta reiniciar."
  echo "Verificar con un tile alineado al gridset (debe dar HIT a la primera)."
}

case "${1:-}" in
  export) shift; do_export "${1:-}" ;;
  import) shift; do_import "${1:-}" ;;
  *)      usage ;;
esac
