#!/bin/bash
# Publica la capa del hexbin H3 precalculado por dataengine.
#
# Las tablas y la vista las crea dataengine (migraciones 0037 y 0038); aqui solo
# se registra en GeoServer lo que no vive en codigo: un datastore hacia el schema
# mapalab y la capa sobre la vista. Es idempotente.
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

WORKSPACE="mapalab"
DATASTORE="mapalab_hexbin"
SCHEMA="mapalab"
LAYER="hexbin_agregado"
SRS="EPSG:6368"

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

datastore_payload() {
  local escaped_passwd
  escaped_passwd=$(json_escape "$POSTGIS_PASSWORD")
  cat <<EOJSON
{
  "dataStore": {
    "name": "$DATASTORE",
    "connectionParameters": {
      "entry": [
        {"@key": "dbtype",   "\$": "postgis"},
        {"@key": "host",     "\$": "$POSTGIS_HOST"},
        {"@key": "port",     "\$": "$POSTGIS_PORT"},
        {"@key": "database", "\$": "$POSTGIS_DB"},
        {"@key": "schema",   "\$": "$SCHEMA"},
        {"@key": "user",     "\$": "$POSTGIS_USER"},
        {"@key": "passwd",   "\$": $escaped_passwd},
        {"@key": "sslmode",  "\$": "$POSTGIS_SSLMODE"},
        {"@key": "Expose primary keys", "\$": "true"},
        {"@key": "validate connections", "\$": "true"}
      ]
    }
  }
}
EOJSON
}

http_code() {
  curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" "$@"
}

echo "Publicando $WORKSPACE:$LAYER ..."

# El workspace es propio y no 'general' a proposito: init-datastores.sh fuerza
# todos los datastores de 'general' al schema mapa_base, y se llevaria este por
# delante en cada reapuntado.
ws=$(http_code "$GEOSERVER_URL/rest/workspaces/$WORKSPACE.json")
if [ "$ws" != "200" ]; then
  code=$(http_code -XPOST -H "Content-Type: application/json" \
    -d "{\"workspace\":{\"name\":\"$WORKSPACE\"}}" "$GEOSERVER_URL/rest/workspaces")
  echo "  workspace creado (HTTP $code)"
fi

existe=$(http_code "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE.json")
if [ "$existe" = "200" ]; then
  code=$(http_code -XPUT -H "Content-Type: application/json" --data-binary @- \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE" < <(datastore_payload))
  echo "  datastore actualizado (HTTP $code)"
else
  code=$(http_code -XPOST -H "Content-Type: application/json" --data-binary @- \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores" < <(datastore_payload))
  echo "  datastore creado (HTTP $code)"
fi

if [ "$code" != "200" ] && [ "$code" != "201" ]; then
  echo "✗ No se pudo configurar el datastore (HTTP $code)" >&2
  exit 1
fi

capa=$(http_code "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes/$LAYER.json")
if [ "$capa" = "200" ]; then
  echo "  capa ya publicada; nada que hacer."
else
  payload="{\"featureType\":{\"name\":\"$LAYER\",\"nativeName\":\"$LAYER\",\"title\":\"Hexbin agregado (H3)\",\"srs\":\"$SRS\",\"enabled\":true}}"
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$payload" \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes")
  if [ "$code" != "201" ]; then
    echo "✗ No se pudo publicar la capa (HTTP $code). ¿Corrió 'make migrate' en dataengine?" >&2
    exit 1
  fi
  echo "  capa publicada (HTTP $code)"
fi

echo "✓ $WORKSPACE:$LAYER listo."
