#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

CONTAINER="geoserver"

echo "Reseteando credenciales admin en GeoServer..."
docker exec "$CONTAINER" bash -c '
  source /scripts/env-data.sh
  source /scripts/functions.sh

  GEOSERVER_INSTALL_DIR="$(detect_install_dir)"
  USERS_XML=${GEOSERVER_DATA_DIR}/security/usergroup/default/users.xml
  ROLES_XML=${GEOSERVER_DATA_DIR}/security/role/default/roles.xml
  CLASSPATH=${GEOSERVER_INSTALL_DIR}/webapps/${GEOSERVER_CONTEXT_ROOT}/WEB-INF/lib/

  export PWD_HASH=$(make_hash "$GEOSERVER_ADMIN_PASSWORD" "$CLASSPATH" "$HASHING_ALGORITHM")
  ESCAPED_USER=$(printf "%s\n" "$GEOSERVER_ADMIN_USER" | sed "s/[&/\\\\]/\\\\&/g")
  ESCAPED_HASH=$(printf "%s\n" "$PWD_HASH" | sed "s/[&/\\\\]/\\\\&/g")

  sed -i "0,/<user /{s/name=\"[^\"]*\"/name=\"${ESCAPED_USER}\"/; s/password=\"[^\"]*\"/password=\"${ESCAPED_HASH}\"/}" "$USERS_XML"

  python3 -c "
import xml.etree.ElementTree as ET
ET.register_namespace(\"\", \"http://www.geoserver.org/security/users\")
tree = ET.parse(\"$USERS_XML\")
root = tree.getroot()
ns = \"http://www.geoserver.org/security/users\"
users_el = root.find(\"{%s}users\" % ns)
seen = {}
to_remove = []
for u in users_el.findall(\"{%s}user\" % ns):
    name = u.get(\"name\")
    if name in seen:
        to_remove.append(seen[name])
    seen[name] = u
for u in to_remove:
    users_el.remove(u)
if to_remove:
    tree.write(\"$USERS_XML\", xml_declaration=True, encoding=\"UTF-8\", short_empty_elements=False)
    print(\"Duplicados eliminados:\", len(to_remove))
"

  if [ -f "$ROLES_XML" ]; then
    sed -i "s/username=\"[^\"]*\"/username=\"${ESCAPED_USER}\"/g" "$ROLES_XML"
  fi

  echo "Admin actualizado a: $GEOSERVER_ADMIN_USER"
'

echo "Reiniciando GeoServer para aplicar cambios..."
docker restart "$CONTAINER"

echo "Esperando que GeoServer esté listo..."
attempts=0; max=24
until docker exec "$CONTAINER" curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge "$max" ]; then
    echo ""
    echo "✗ GeoServer no respondió después de $((max * 5))s. Últimos logs:"
    docker logs "$CONTAINER" --tail 20 2>&1
    exit 1
  fi
  printf '.'
  sleep 5
done
echo ""
echo "Credenciales admin actualizadas correctamente."
