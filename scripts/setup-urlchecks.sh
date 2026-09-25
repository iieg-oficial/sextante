#!/bin/bash
# Configura los URLChecks que permiten a GeoServer leer ExternalGraphic desde
# buckets internos del Acervo (SeaweedFS) cuando renderea SLDs.
#
# Idempotente: consulta antes de crear. El POST duplicado devolvia 409, que el
# script trataba como exito, pero GeoServer lo registra como ERROR en su log y
# ensuciaba el reporte del ecosistema en cada arranque.
#
# PENDIENTE: cuando estos URLChecks se persistan via configuracion declarativa
# (ej. provisioning del volumen geoserver_data en el bootstrap de produccion),
# remover este script y la invocacion desde el target `up` del Makefile.
set +H
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://${GEOSERVER_BIND_ADDR:-127.0.0.1}:${GEOSERVER_PORT:-8080}/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

URLCHECKS=(
  "acervo_mapalab|Acervo SeaweedFS interno (bucket mapalab)|^http://acervo-seaweedfs:8333/mapalab/.+$"
  "acervo_iieg_leyendas|Acervo SeaweedFS interno (bucket iieg, prefijo leyendas/)|^http://acervo-seaweedfs:8333/iieg/leyendas/.+$"
)

ensure_urlcheck() {
  local name="$1" description="$2" regex="$3"
  local existing
  existing=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" \
    -u "$AUTH" "$GEOSERVER_URL/rest/urlchecks/$name")
  [ "$existing" = "200" ] && return 0
  local payload
  payload=$(printf '{"regexUrlCheck":{"name":"%s","description":"%s","enabled":true,"regex":"%s"}}' \
    "$name" "$description" "$regex")
  local code
  code=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" \
    -u "$AUTH" -H "Content-Type: application/json" -X POST \
    "$GEOSERVER_URL/rest/urlchecks" -d "$payload")
  case "$code" in
    201) echo "  + $name (creado)" ;;
    409) ;;
    *)   echo "  ✗ $name (HTTP $code)" >&2; return 1 ;;
  esac
}

echo "Configurando URLChecks de GeoServer..."
for entry in "${URLCHECKS[@]}"; do
  IFS='|' read -r name description regex <<< "$entry"
  ensure_urlcheck "$name" "$description" "$regex" || exit 1
done
echo "URLChecks OK."
