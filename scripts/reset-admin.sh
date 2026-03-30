#!/bin/bash
# Fuerza el reset de credenciales admin dentro del contenedor,
# sin importar cuántos usuarios existan en users.xml.
# Los demás usuarios se conservan intactos.

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

  # Buscar el primer usuario en users.xml (el admin) y reemplazar nombre y password
  sed -i "0,/<user /{s/name=\"[^\"]*\"/name=\"${ESCAPED_USER}\"/; s/password=\"[^\"]*\"/password=\"${ESCAPED_HASH}\"/}" "$USERS_XML"

  # Actualizar el rol admin en roles.xml
  if [ -f "$ROLES_XML" ]; then
    sed -i "s/username=\"[^\"]*\"/username=\"${ESCAPED_USER}\"/g" "$ROLES_XML"
  fi

  echo "Admin actualizado a: $GEOSERVER_ADMIN_USER"
'

# Reiniciar GeoServer para que tome los cambios
echo "Reiniciando GeoServer para aplicar cambios..."
docker restart "$CONTAINER"

# Esperar a que esté listo de nuevo
until docker exec "$CONTAINER" curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do
  printf '.'
  sleep 5
done
echo ""
echo "Credenciales admin actualizadas correctamente."
