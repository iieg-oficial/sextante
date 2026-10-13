#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  . "$PROJECT_DIR/.env"
  set +a
fi

CONTAINER="${CONTAINER:-sextante}"

echo "Reseteando credenciales admin en GeoServer..."
docker exec "$CONTAINER" geoserver-reset-admin

echo "Reiniciando GeoServer para aplicar cambios..."
docker restart "$CONTAINER"

echo "Esperando que GeoServer esté listo..."
attempts=0; max="${GEOSERVER_WAIT_MAX:-180}"
until docker exec "$CONTAINER" curl -sf "http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}/web/" > /dev/null 2>&1; do
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
