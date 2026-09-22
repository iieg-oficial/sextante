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

GEOSERVER_URL="http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}"
AUTH="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"

WORKSPACE=raster
STORE=elevacion
NATIVE=elevacion_jalisco_intervalo_vertical_10m
LAYER=elevacion_terreno_rgb
STYLE=terreno_rgb
MAX_ELEVATION=4352

FORCE="${1:-}"
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
  <name>$WORKSPACE:$LAYER</name>
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

store=$(http_code "$REST/workspaces/$WORKSPACE/coveragestores/$STORE.json")
if [ "$store" != "200" ]; then
  echo "✗ No existe el coveragestore $WORKSPACE:$STORE (HTTP $store). Sin el DEM no hay terreno." >&2
  exit 1
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
fi

layer_json="{\"layer\":{\"defaultStyle\":{\"name\":\"$WORKSPACE:$STYLE\"},\"defaultInterpolationMethod\":\"NEAREST_NEIGHBOR\",\"queryable\":false}}"
code=$(http_code -XPUT -H "Content-Type: application/json" -d "$layer_json" "$REST/layers/$WORKSPACE:$LAYER")
echo "  estilo por defecto e interpolacion al vecino mas cercano (HTTP $code)"

code=$(http_code -XPUT -H "Content-Type: text/xml" -d "$(gwc_layer_xml)" \
  "$GEOSERVER_URL/gwc/rest/layers/$WORKSPACE:$LAYER.xml")
echo "  tile layer de GWC (HTTP $code)"

echo "✓ $WORKSPACE:$LAYER listo."
