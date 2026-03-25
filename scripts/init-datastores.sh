#!/bin/bash
set +H
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://localhost:8080/geoserver"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

wait_for_geoserver() {
  local max_attempts=24
  local attempt=0
  echo "Esperando GeoServer..."
  until curl -sf --max-time 10 "$GEOSERVER_URL/web/" > /dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "GeoServer no respondió después de $((max_attempts * 5)) segundos." >&2
      exit 1
    fi
    sleep 5
  done
  echo "GeoServer listo."
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

create_datastore() {
  local workspace=$1
  local name=$2
  local schema=${3:-$name}

  local escaped_passwd
  escaped_passwd=$(json_escape "$POSTGIS_PASSWORD")

  local payload
  payload=$(cat <<EOJSON
{
  "dataStore": {
    "name": "$name",
    "connectionParameters": {
      "entry": [
        {"@key": "dbtype",   "\$": "postgis"},
        {"@key": "host",     "\$": "$POSTGIS_HOST"},
        {"@key": "port",     "\$": "$POSTGIS_PORT"},
        {"@key": "database", "\$": "$POSTGIS_DB"},
        {"@key": "schema",   "\$": "$schema"},
        {"@key": "user",     "\$": "$POSTGIS_USER"},
        {"@key": "passwd",   "\$": $escaped_passwd},
        {"@key": "sslmode",  "\$": "$POSTGIS_SSLMODE"}
      ]
    }
  }
}
EOJSON
)

  local http_code
  http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" \
    "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name.json")

  if [ "$http_code" = "200" ]; then
    echo "Actualizando datastore '$name'..."
    curl -s --max-time 30 -u "$AUTH" \
      -XPUT \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name"
    echo " OK"
  else
    echo "Creando datastore '$name'..."
    curl -s --max-time 30 -u "$AUTH" \
      -XPOST \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$GEOSERVER_URL/rest/workspaces/$workspace/datastores"
    echo " OK"
  fi
}

wait_for_geoserver

verify_credentials() {
  local http_code
  http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/workspaces")
  while [ "$http_code" = "401" ]; do
    echo "Error 401: Credenciales incorrectas."
    read -p "Usuario GeoServer: " input_user
    read -s -p "Contrasena GeoServer: " input_pass
    echo ""
    AUTH="${input_user}:${input_pass}"
    http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/workspaces")
  done
}

verify_credentials

WORKSPACES=(
  "demografia"
  "desarrollo_social"
  "economia"
  "educacion"
  "general"
  "gobierno_y_ciudadania"
  "recursos_y_calidad_de_vida"
  "salud"
  "seguridad_y_proteccion_ciudadana"
)

declare -A SCHEMA_MAP=(
  ["general"]="mapa_base"
)

for ws in "${WORKSPACES[@]}"; do
  schema="${SCHEMA_MAP[$ws]:-$ws}"
  create_datastore "$ws" "$ws" "$schema"
done