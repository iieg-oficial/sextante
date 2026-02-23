#!/bin/bash
set -e

GEOSERVER_URL="http://localhost:8080/geoserver"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

wait_for_geoserver() {
  echo "Esperando GeoServer..."
  until curl -sf -u "$AUTH" "$GEOSERVER_URL/rest/about/version.json" > /dev/null; do
    sleep 5
  done
  echo "GeoServer listo."
}

create_datastore() {
  local workspace=$1
  local name=$2

  exists=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" \
    "$GEOSERVER_URL/rest/workspaces/$workspace/datastores/$name.json")

  if [ "$exists" = "200" ]; then
    echo "Datastore '$name' ya existe, omitiendo."
    return
  fi

  echo "Creando datastore '$name'..."
  curl -sf -u "$AUTH" \
    -XPOST \
    -H "Content-Type: application/json" \
    -d "{
      \"dataStore\": {
        \"name\": \"$name\",
        \"connectionParameters\": {
          \"entry\": [
            {\"@key\": \"dbtype\",     \"\$\": \"postgis\"},
            {\"@key\": \"host\",       \"\$\": \"$POSTGIS_HOST\"},
            {\"@key\": \"port\",       \"\$\": \"$POSTGIS_PORT\"},
            {\"@key\": \"database\",   \"\$\": \"$POSTGIS_DB\"},
            {\"@key\": \"user\",       \"\$\": \"$POSTGIS_USER\"},
            {\"@key\": \"passwd\",     \"\$\": \"$POSTGIS_PASSWORD\"},
            {\"@key\": \"ssl\",        \"\$\": \"true\"},
            {\"@key\": \"sslfactory\", \"\$\": \"org.postgresql.ssl.NonValidatingFactory\"}
          ]
        }
      }
    }" \
    "$GEOSERVER_URL/rest/workspaces/$workspace/datastores"
  echo "Datastore '$name' creado."
}

wait_for_geoserver
create_datastore "economia" "postgis_iieg"
