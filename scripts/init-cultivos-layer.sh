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

GEOSERVER_URL="http://localhost:8080/geoserver"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

WORKSPACE=economia
DATASTORE=economia
LAYER=cultivos
SCHEMA=economia
TABLE=cultivos
GEOM_COL=geom_3857
GEOM_TYPE=MultiPolygon
SRID=3857
KEY_COL=fid
SQL_SELECT="SELECT ${KEY_COL}, muestra, prediccion, clave_municipio, ${GEOM_COL} FROM ${SCHEMA}.${TABLE}"

FORCE="${1:-}"
FT_URL="$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes/$LAYER"

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
  <title>${LAYER}</title>
  <srs>EPSG:${SRID}</srs>
  <projectionPolicy>FORCE_DECLARED</projectionPolicy>
  <enabled>true</enabled>
  <metadata>
    <entry key="cachingEnabled">false</entry>
    <entry key="JDBC_VIRTUAL_TABLE">
      <virtualTable>
        <name>${LAYER}</name>
        <sql>${SQL_SELECT}</sql>
        <escapeSql>false</escapeSql>
        <keyColumn>${KEY_COL}</keyColumn>
        <geometry>
          <name>${GEOM_COL}</name>
          <type>${GEOM_TYPE}</type>
          <srid>${SRID}</srid>
        </geometry>
      </virtualTable>
    </entry>
  </metadata>
</featureType>
EOF
}

wait_for_geoserver

current=$(curl -s --max-time 15 -u "$AUTH" "$FT_URL.xml")
http_code=$(curl -s -o /dev/null --max-time 15 -w "%{http_code}" -u "$AUTH" "$FT_URL.xml")

if [ "$http_code" = "404" ]; then
  echo "WARNING: la capa '$WORKSPACE:$LAYER' no está publicada todavía; se omite la reproyección nativa." >&2
  exit 0
fi
if [ "$http_code" != "200" ]; then
  echo "WARNING: no se pudo leer '$WORKSPACE:$LAYER' (http=$http_code); se omite." >&2
  exit 0
fi

if printf '%s' "$current" | grep -q "EPSG:${SRID}" && printf '%s' "$current" | grep -q "JDBC_VIRTUAL_TABLE"; then
  if [ "$FORCE" != "--force" ]; then
    echo "Capa '$WORKSPACE:$LAYER' ya servida nativa en EPSG:${SRID}; skip (usa --force para reaplicar)."
    exit 0
  fi
fi

printf "Republicando '%s' nativa en EPSG:%s (vista SQL sobre %s)... " "$WORKSPACE:$LAYER" "$SRID" "$GEOM_COL"
http_code=$(curl -s -o /tmp/init_cultivos_resp --max-time 30 -w "%{http_code}" -u "$AUTH" \
  -X PUT \
  -H "Content-Type: text/xml" \
  -d "$(build_payload)" \
  "$FT_URL.xml?recalculate=nativebbox,latlonbbox")

if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
  echo "OK"
else
  echo "WARNING (http=$http_code)" >&2
  echo "  Causa probable: la columna ${SCHEMA}.${TABLE}.${GEOM_COL} no existe." >&2
  echo "  Aplica la migración 0022 en dataengine (make migrate) antes de republicar." >&2
  [ -s /tmp/init_cultivos_resp ] && sed 's/^/  /' /tmp/init_cultivos_resp >&2
  rm -f /tmp/init_cultivos_resp
  exit 0
fi
rm -f /tmp/init_cultivos_resp
