#!/bin/bash
set +H
set -uo pipefail

FAILED_DATASTORES=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

GEOSERVER_URL="http://${GEOSERVER_BIND_ADDR:-127.0.0.1}:${GEOSERVER_PORT:-8080}/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

wait_for_geoserver() {
  local max_attempts=24
  local attempt=0
  echo "Esperando GeoServer (web)..."
  until curl -sf --max-time 10 "$GEOSERVER_URL/web/" > /dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "GeoServer no respondió después de $((max_attempts * 5)) segundos." >&2
      exit 1
    fi
    sleep 5
  done
  echo "Esperando GeoServer (REST)..."
  attempt=0
  local http_code
  until http_code=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/workspaces.json") && [ "$http_code" = "200" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "REST no respondió 200 después de $((max_attempts * 5)) segundos (último code=$http_code)." >&2
      exit 1
    fi
    sleep 5
  done
  echo "GeoServer listo."
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")'
}

build_datastore_payload() {
  local name=$1
  local schema=$2
  local escaped_passwd
  escaped_passwd=$(json_escape "$POSTGIS_PASSWORD")
  cat <<EOJSON
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
        {"@key": "sslmode",  "\$": "$POSTGIS_SSLMODE"},
        {"@key": "max connections", "\$": "50"},
        {"@key": "min connections", "\$": "5"},
        {"@key": "Connection timeout", "\$": "20"},
        {"@key": "validate connections", "\$": "true"},
        {"@key": "Test while idle", "\$": "true"},
        {"@key": "Evictor run periodicity", "\$": "300"},
        {"@key": "Max connection idle time", "\$": "300"},
        {"@key": "Evictor tests per run", "\$": "3"},
        {"@key": "Loose bbox", "\$": "true"},
        {"@key": "Estimated extends", "\$": "true"},
        {"@key": "fetch size", "\$": "1000"},
        {"@key": "prepare statements", "\$": "true"}
      ]
    }
  }
}
EOJSON
}

datastore_request() {
  local method=$1
  local url=$2
  local payload=$3
  local max_retries=3
  local attempt=0
  local http_code
  while [ "$attempt" -lt "$max_retries" ]; do
    http_code=$(curl -s -o /dev/null --max-time 60 -w "%{http_code}" -u "$AUTH" \
      -X "$method" \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "$url" <<<"$payload")
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
      echo "$http_code"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -lt "$max_retries" ]; then
      sleep $((attempt * 5))
    fi
  done
  echo "$http_code"
  return 1
}

create_datastore() {
  local workspace=$1
  local name=$2
  local schema=${3:-$name}

  local payload
  payload=$(build_datastore_payload "$name" "$schema")

  local http_code
  http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" \
    "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name.json")

  local result
  if [ "$http_code" = "200" ]; then
    printf "Actualizando datastore '%s:%s' (schema=%s)... " "$workspace" "$name" "$schema"
    if result=$(datastore_request "PUT" "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name" "$payload"); then
      echo "OK"
    else
      echo "FAIL (http=$result)"
      FAILED_DATASTORES+=("$workspace:$name")
    fi
  else
    printf "Creando datastore '%s:%s' (schema=%s)... " "$workspace" "$name" "$schema"
    if result=$(datastore_request "POST" "$GEOSERVER_URL/rest/workspaces/$workspace/datastores" "$payload"); then
      echo "OK"
    elif result=$(datastore_request "PUT" "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name" "$payload"); then
      echo "OK (ya existia; actualizado)"
    else
      echo "FAIL (http=$result)"
      FAILED_DATASTORES+=("$workspace:$name")
    fi
  fi
}

list_workspaces() {
  curl -s --max-time 15 -u "$AUTH" "$GEOSERVER_URL/rest/workspaces.json" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
node = d.get("workspaces")
if isinstance(node, dict):
    for w in (node.get("workspace") or []):
        print(w["name"])
'
}

list_datastores_with_schema() {
  local workspace=$1
  curl -s --max-time 15 -u "$AUTH" "$GEOSERVER_URL/rest/workspaces/$workspace/datastores.json" \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
node = d.get("dataStores")
if not isinstance(node, dict):
    sys.exit(0)
for ds in (node.get("dataStore") or []):
    print(ds["name"])
' | while read -r ds; do
    [ -z "$ds" ] && continue
    local schema
    schema=$(curl -s --max-time 15 -u "$AUTH" "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$ds.json" \
      | python3 -c '
import json, sys
d = json.load(sys.stdin)
ce = {e["@key"]: e.get("$") for e in d.get("dataStore", {}).get("connectionParameters", {}).get("entry", [])}
print(ce.get("schema") or "")
')
    printf '%s\t%s\n' "$ds" "$schema"
  done
}

wait_for_geoserver

verify_credentials() {
  local http_code
  local max_retries=12
  local attempt=0
  http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/workspaces")
  while [ "$http_code" = "401" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_retries" ]; then
      echo "Error: Las credenciales del .env no fueron aceptadas tras $max_retries intentos." >&2
      echo "Verifica GEOSERVER_ADMIN_USER y GEOSERVER_ADMIN_PASSWORD en el .env" >&2
      exit 1
    fi
    echo "Credenciales aun no aplicadas, reintentando en 5s... (intento $attempt/$max_retries)"
    sleep 5
    http_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" -u "$AUTH" "$GEOSERVER_URL/rest/workspaces")
  done
}

verify_credentials

declare -A SCHEMA_MAP=(
  ["general"]="mapa_base"
)

mapfile -t WORKSPACES < <(list_workspaces)

if [ ${#WORKSPACES[@]} -eq 0 ]; then
  echo "Sin workspaces en GeoServer; nada que reapuntar." >&2
  exit 0
fi

for ws in "${WORKSPACES[@]}"; do
  ds_lines=$(list_datastores_with_schema "$ws")
  if [ -z "$ds_lines" ]; then
    echo "Workspace '$ws' sin datastores; skip."
    continue
  fi
  while IFS=$'\t' read -r ds schema_actual; do
    [ -z "$ds" ] && continue
    schema_override="${SCHEMA_MAP[$ws]:-}"
    if [ -n "$schema_override" ]; then
      schema="$schema_override"
    elif [ -n "$schema_actual" ]; then
      schema="$schema_actual"
    else
      schema="$ws"
    fi
    create_datastore "$ws" "$ds" "$schema"
  done <<< "$ds_lines"
done

if [ "${#FAILED_DATASTORES[@]}" -gt 0 ]; then
  echo ""
  echo "✗ Datastores con error (${#FAILED_DATASTORES[@]}):"
  for ds in "${FAILED_DATASTORES[@]}"; do
    echo "  - $ds"
  done
  exit 1
fi