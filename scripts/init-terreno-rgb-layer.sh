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

WORKSPACE=raster
STORE=terreno_rgb
ORIGEN_STORE=elevacion
NATIVE=elevacion_jalisco_relleno
ORIGEN_TIF=workspaces/raster/terreno/elevacion_jalisco_intervalo_vertical_10m.tif
RELLENO_TIF=workspaces/raster/terreno/elevacion_jalisco_relleno.tif
FILL_MAX_DISTANCE=2500
MARGEN_M=200000
RESOLUCION_M=30
COPERNICUS=https://copernicus-dem-90m.s3.amazonaws.com
LATITUDES="17 18 19 20 21 22 23 24"
LONGITUDES="100 101 102 103 104 105 106 107 108"
LAYER=elevacion_terreno_rgb
LAYER_JALISCO=elevacion_jalisco_rgb
ORIGEN_NATIVE=elevacion_jalisco_intervalo_vertical_10m
STYLE=terreno_rgb
MAX_ELEVATION=4352
CONTENEDOR=${GEOSERVER_CONTAINER_NAME:-sextante}
DATA_DIR=/opt/geoserver/data_dir

FORCE="${1:-}"
PURGAR=0
REST="$GEOSERVER_URL/rest"

http_code() {
  curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" "$@"
}

style_sld() {
  python3 - "$MAX_ELEVATION" <<'EOPY'
import sys
top = int(sys.argv[1])
rows = ['<ColorMapEntry color="#000000" quantity="-1000" opacity="1"/>']
for base in range(0, top, 256):
    r = base // 256
    rows.append(f'<ColorMapEntry color="#{r:02x}0000" quantity="{base}" opacity="1"/>')
    rows.append(f'<ColorMapEntry color="#{r:02x}ff00" quantity="{base + 255}" opacity="1"/>')
entries = '\n              '.join(rows)
print(f'''<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor version="1.0.0" xmlns="http://www.opengis.net/sld" xmlns:ogc="http://www.opengis.net/ogc"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.0.0/StyledLayerDescriptor.xsd">
  <NamedLayer>
    <Name>terreno_rgb</Name>
    <UserStyle>
      <Title>Altura codificada en RGB (R*256+G)</Title>
      <FeatureTypeStyle>
        <Rule>
          <RasterSymbolizer>
            <Opacity>1.0</Opacity>
            <ColorMap type="ramp" extended="true">
              {entries}
            </ColorMap>
          </RasterSymbolizer>
        </Rule>
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>''')
EOPY
}

gwc_layer_xml() {
  cat <<EOXML
<GeoServerLayer>
  <enabled>true</enabled>
  <name>$WORKSPACE:$1</name>
  <mimeFormats><string>image/png</string></mimeFormats>
  <gridSubsets>
    <gridSubset><gridSetName>EPSG:900913</gridSetName></gridSubset>
  </gridSubsets>
  <metaWidthHeight><int>4</int><int>4</int></metaWidthHeight>
  <expireCache>0</expireCache>
  <expireClients>604800</expireClients>
  <gutter>0</gutter>
</GeoServerLayer>
EOXML
}

echo "Publicando $WORKSPACE:$LAYER ..."

origen=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$ORIGEN_STORE.json")
if [ "$origen" != "200" ]; then
  echo "✗ No existe el coveragestore $WORKSPACE:$ORIGEN_STORE (HTTP $origen). Sin el DEM no hay terreno." >&2
  exit 1
fi

bajar_contexto() {
  local destino=$1 lat lon nombre codigo bajados=0
  for lat in $LATITUDES; do
    for lon in $LONGITUDES; do
      nombre="Copernicus_DSM_COG_30_N${lat}_00_W${lon}_00_DEM"
      codigo=$(curl -s -o "$destino/$nombre.tif" -w "%{http_code}" "$COPERNICUS/$nombre/$nombre.tif")
      if [ "$codigo" = "200" ]; then
        bajados=$((bajados + 1))
      else
        rm -f "$destino/$nombre.tif"
      fi
    done
  done
  [ "$bajados" -gt 0 ]
}

dem_con_contexto() {
  local local_dir remoto=/tmp/terreno-contexto
  local_dir=$(mktemp -d)
  echo "  bajando Copernicus GLO-90 alrededor de Jalisco..."
  if ! bajar_contexto "$local_dir"; then
    rm -rf "$local_dir"
    return 1
  fi
  docker exec "$CONTENEDOR" rm -rf "$remoto" >/dev/null 2>&1
  docker cp "$local_dir" "$CONTENEDOR:$remoto" >/dev/null || { rm -rf "$local_dir"; return 1; }
  rm -rf "$local_dir"
  echo "  armando el DEM con el terreno vecino (tarda unos minutos)..."
  docker exec -e ORIGEN="$DATA_DIR/$ORIGEN_TIF" -e SALIDA="$DATA_DIR/$RELLENO_TIF" -e REMOTO="$remoto" \
    -e MARGEN="$MARGEN_M" -e RES="$RESOLUCION_M" "$CONTENEDOR" bash -c '
    set -e
    read -r x0 y0 x1 y1 < <(python3 -c "
import json, subprocess, os
info = json.loads(subprocess.check_output([\"gdalinfo\", \"-json\", os.environ[\"ORIGEN\"]]))
x0, y1 = info[\"cornerCoordinates\"][\"upperLeft\"]
x1, y0 = info[\"cornerCoordinates\"][\"lowerRight\"]
m = int(os.environ[\"MARGEN\"])
open(os.environ[\"REMOTO\"] + \"/srs.wkt\", \"w\").write(info[\"coordinateSystem\"][\"wkt\"])
print(x0 - m, y0 - m, x1 + m, y1 + m)
")
    gdalbuildvrt -q "$REMOTO/contexto.vrt" "$REMOTO"/Copernicus_*.tif
    gdalwarp -q -overwrite -t_srs "$REMOTO/srs.wkt" -tr "$RES" "$RES" -te "$x0" "$y0" "$x1" "$y1" -r cubic \
      -ot Int16 -dstnodata -32768 -multi -wo NUM_THREADS=ALL_CPUS \
      -co TILED=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co BIGTIFF=IF_SAFER "$REMOTO/contexto.vrt" "$REMOTO/salida.tif"
    gdalwarp -q -r average -srcnodata -32768 "$ORIGEN" "$REMOTO/salida.tif"
    gdaladdo -q -r average --config COMPRESS_OVERVIEW DEFLATE --config PREDICTOR_OVERVIEW 2 "$REMOTO/salida.tif" 2 4 8 16 32
    mv "$REMOTO/salida.tif" "$SALIDA"
    rm -rf "$REMOTO"
  ' >/dev/null 2>&1
}

dem_relleno() {
  echo "  sin terreno vecino: rellenando los huecos con gdal_fillnodata..."
  docker exec "$CONTENEDOR" gdal_fillnodata.py -md "$FILL_MAX_DISTANCE" -of GTiff \
    -co TILED=YES -co COMPRESS=DEFLATE -co BIGTIFF=IF_SAFER \
    "$DATA_DIR/$ORIGEN_TIF" "$DATA_DIR/$RELLENO_TIF" >/dev/null 2>&1
}

if ! docker exec "$CONTENEDOR" test -f "$DATA_DIR/$RELLENO_TIF"; then
  if ! dem_con_contexto && ! dem_relleno; then
    echo "✗ No se pudo generar el DEM del terreno dentro de $CONTENEDOR" >&2
    exit 1
  fi
  docker exec "$CONTENEDOR" chown geoserveruser:geoserverusers "$DATA_DIR/$RELLENO_TIF" >/dev/null 2>&1 || true
  PURGAR=1
  REGENERADO=1
fi

tienda=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$STORE.json")
if [ "$tienda" != "200" ]; then
  payload="{\"coverageStore\":{\"name\":\"$STORE\",\"type\":\"GeoTIFF\",\"enabled\":true,\"workspace\":{\"name\":\"$WORKSPACE\"},\"url\":\"file:$RELLENO_TIF\"}}"
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$payload" "$REST/workspaces/$WORKSPACE/coveragestores")
  echo "  coveragestore creado (HTTP $code)"
fi

vieja=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$ORIGEN_STORE/coverages/$LAYER.json")
if [ "$vieja" = "200" ]; then
  code=$(http_code -XDELETE "$REST/workspaces/$WORKSPACE/coveragestores/$ORIGEN_STORE/coverages/$LAYER?recurse=true")
  echo "  capa anterior sobre el DEM con huecos retirada (HTTP $code)"
  PURGAR=1
fi

sld_file=$(mktemp)
trap 'rm -f "$sld_file"' EXIT
style_sld > "$sld_file"

estilo=$(http_code "$REST/workspaces/$WORKSPACE/styles/$STYLE.json")
if [ "$estilo" != "200" ]; then
  code=$(http_code -XPOST -H "Content-Type: application/vnd.ogc.sld+xml" --data-binary "@$sld_file" \
    "$REST/workspaces/$WORKSPACE/styles?name=$STYLE")
  echo "  estilo creado (HTTP $code)"
elif [ "$FORCE" = "--force" ]; then
  code=$(http_code -XPUT -H "Content-Type: application/vnd.ogc.sld+xml" --data-binary "@$sld_file" \
    "$REST/workspaces/$WORKSPACE/styles/$STYLE")
  echo "  estilo actualizado (HTTP $code)"
fi

coverage_json="{\"coverage\":{\"name\":\"$LAYER\",\"nativeName\":\"$NATIVE\",\"nativeCoverageName\":\"$NATIVE\",\"title\":\"Terreno 3D (altura en RGB)\",\"enabled\":true}}"
capa=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$STORE/coverages/$LAYER.json")
if [ "$capa" != "200" ]; then
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$coverage_json" \
    "$REST/workspaces/$WORKSPACE/coveragestores/$STORE/coverages")
  if [ "$code" != "201" ]; then
    echo "✗ No se pudo publicar la capa (HTTP $code)" >&2
    exit 1
  fi
  echo "  capa publicada (HTTP $code)"
elif [ "${REGENERADO:-0}" = "1" ]; then
  code=$(http_code -XPOST "$REST/workspaces/$WORKSPACE/coveragestores/$STORE/reset")
  echo "  store releido (HTTP $code)"
  code=$(http_code -XPUT -H "Content-Type: application/json" -d '{"coverage":{"enabled":true}}' \
    "$REST/workspaces/$WORKSPACE/coveragestores/$STORE/coverages/$LAYER?calculate=nativebbox,latlonbbox")
  echo "  extension recalculada para el DEM nuevo (HTTP $code)"
fi

jalisco_json="{\"coverage\":{\"name\":\"$LAYER_JALISCO\",\"nativeName\":\"$ORIGEN_NATIVE\",\"nativeCoverageName\":\"$ORIGEN_NATIVE\",\"title\":\"Sombreado 3D de Jalisco (altura en RGB)\",\"enabled\":true}}"
capa=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$ORIGEN_STORE/coverages/$LAYER_JALISCO.json")
if [ "$capa" != "200" ]; then
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$jalisco_json" \
    "$REST/workspaces/$WORKSPACE/coveragestores/$ORIGEN_STORE/coverages")
  if [ "$code" != "201" ]; then
    echo "✗ No se pudo publicar $LAYER_JALISCO (HTTP $code)" >&2
    exit 1
  fi
  echo "  capa del sombreado publicada (HTTP $code)"
  PURGAR=1
fi

layer_json="{\"layer\":{\"defaultStyle\":{\"name\":\"$WORKSPACE:$STYLE\"},\"defaultInterpolationMethod\":\"NEAREST_NEIGHBOR\",\"queryable\":false}}"
for capa in "$LAYER" "$LAYER_JALISCO"; do
  code=$(http_code -XPUT -H "Content-Type: application/json" -d "$layer_json" "$REST/layers/$WORKSPACE:$capa")
  echo "  $capa: estilo por defecto e interpolacion al vecino mas cercano (HTTP $code)"

  code=$(http_code -XPUT -H "Content-Type: text/xml" -d "$(gwc_layer_xml "$capa")" \
    "$GEOSERVER_URL/gwc/rest/layers/$WORKSPACE:$capa.xml")
  echo "  $capa: tile layer de GWC (HTTP $code)"

  if [ "$PURGAR" = "1" ] || [ "$FORCE" = "--force" ]; then
    code=$(http_code -XPOST -H "Content-Type: text/xml" \
      -d "<truncateLayer><layerName>$WORKSPACE:$capa</layerName></truncateLayer>" \
      "$GEOSERVER_URL/gwc/rest/masstruncate")
    echo "  $capa: cache de GWC purgado (HTTP $code)"
  fi
done

echo "✓ $WORKSPACE:$LAYER y $WORKSPACE:$LAYER_JALISCO listos."
