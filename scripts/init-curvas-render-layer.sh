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

GEOSERVER_URL="http://${GEOSERVER_BIND_ADDR:-127.0.0.1}:${GEOSERVER_PORT:-8080}/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

WORKSPACE=general
DATASTORE=general
LAYER=curvas_de_nivel_render
TITLE="Curvas de nivel (render)"
STYLE=curvas_de_nivel
SRID=3857

FORCE="${1:-}"
FT_BASE="$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes"
FT_URL="$FT_BASE/$LAYER"
LAYER_URL="$GEOSERVER_URL/rest/layers/$WORKSPACE:$LAYER"

wait_for_geoserver() {
  local max_attempts=24
  local attempt=0
  local http_code
  echo "Esperando GeoServer (REST)..."
  until http_code=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/about/version.json") && [ "$http_code" = "200" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "REST no respondió 200 después de $((max_attempts * 5)) segundos (último code=$http_code)." >&2
      exit 1
    fi
    sleep 5
  done
}

build_payload() {
  cat <<EOF
<featureType>
  <name>${LAYER}</name>
  <nativeName>${LAYER}</nativeName>
  <title>${TITLE}</title>
  <srs>EPSG:${SRID}</srs>
  <projectionPolicy>FORCE_DECLARED</projectionPolicy>
  <enabled>true</enabled>
  <serviceConfiguration>true</serviceConfiguration>
  <disabledServices>
    <string>WFS</string>
  </disabledServices>
</featureType>
EOF
}

build_layer_payload() {
  cat <<EOF
<layer>
  <defaultStyle>
    <name>${WORKSPACE}:${STYLE}</name>
  </defaultStyle>
  <queryable>false</queryable>
</layer>
EOF
}

wait_for_geoserver

http_code=$(curl -s -o /dev/null --max-time 15 -w "%{http_code}" -u "$AUTH" "$FT_URL.xml")

if [ "$http_code" = "200" ] && [ "$FORCE" != "--force" ]; then
  echo "Capa '$WORKSPACE:$LAYER' ya publicada; skip (usa --force para reaplicar)."
  exit 0
fi

if [ "$http_code" = "200" ]; then
  method=PUT
  target="$FT_URL.xml?recalculate=nativebbox,latlonbbox"
  printf "Republicando '%s' en EPSG:%s... " "$WORKSPACE:$LAYER" "$SRID"
else
  method=POST
  target="$FT_BASE.xml"
  printf "Publicando '%s' en EPSG:%s... " "$WORKSPACE:$LAYER" "$SRID"
fi

http_code=$(curl -s -o /tmp/init_curvas_resp --max-time 60 -w "%{http_code}" -u "$AUTH" \
  -X "$method" \
  -H "Content-Type: text/xml" \
  -d "$(build_payload)" \
  "$target")

if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
  echo "OK"
else
  echo "WARNING (http=$http_code)" >&2
  echo "  Causa probable: la tabla mapa_base.${LAYER} no existe." >&2
  echo "  Aplica la migración 0026 en dataengine (make migrate) antes de publicar." >&2
  [ -s /tmp/init_curvas_resp ] && sed 's/^/  /' /tmp/init_curvas_resp >&2
  rm -f /tmp/init_curvas_resp
  exit 0
fi
rm -f /tmp/init_curvas_resp

printf "Asignando estilo '%s' y queryable=false... " "$WORKSPACE:$STYLE"
http_code=$(curl -s -o /tmp/init_curvas_resp --max-time 30 -w "%{http_code}" -u "$AUTH" \
  -X PUT \
  -H "Content-Type: text/xml" \
  -d "$(build_layer_payload)" \
  "$LAYER_URL.xml")

if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
  echo "OK"
else
  echo "WARNING (http=$http_code)" >&2
  [ -s /tmp/init_curvas_resp ] && sed 's/^/  /' /tmp/init_curvas_resp >&2
fi
rm -f /tmp/init_curvas_resp
