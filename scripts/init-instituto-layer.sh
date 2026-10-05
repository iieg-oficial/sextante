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
source "$SCRIPT_DIR/lib/gs_curl.sh"

WORKSPACE="instituto"
DATASTORE="instituto"
SCHEMA="instituto"
LAYER="espacios"
STYLE="instituto_espacios"
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

regla() {
  cat <<EOXML
      <Rule>
        <Name>$1</Name>
        <Title>$2</Title>
        <ogc:Filter><ogc:PropertyIsEqualTo><ogc:PropertyName>tipo</ogc:PropertyName><ogc:Literal>$1</ogc:Literal></ogc:PropertyIsEqualTo></ogc:Filter>
        <PolygonSymbolizer>
          <Fill><CssParameter name="fill">$3</CssParameter></Fill>
          <Stroke><CssParameter name="stroke">#8C6F9E</CssParameter><CssParameter name="stroke-width">0.6</CssParameter></Stroke>
        </PolygonSymbolizer>
      </Rule>
EOXML
}

estilo_sld() {
  cat <<EOXML
<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor version="1.0.0" xmlns="http://www.opengis.net/sld" xmlns:ogc="http://www.opengis.net/ogc" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.0.0/StyledLayerDescriptor.xsd">
  <NamedLayer>
    <Name>$STYLE</Name>
    <UserStyle>
      <Title>Espacios del instituto</Title>
      <FeatureTypeStyle>
$(regla oficina 'Oficina' '#EFE6D2')
$(regla trabajo 'Área de trabajo' '#E9DDC2')
$(regla sala 'Sala' '#E4D6EA')
$(regla recepcion 'Recepción' '#D9E7F1')
$(regla comedor 'Comedor' '#F2DCCB')
$(regla circulacion 'Circulación' '#ECEAE4')
$(regla servicio 'Servicio' '#DEDEDE')
$(regla exterior 'Exterior' '#CFDDBF')
      </FeatureTypeStyle>
      <FeatureTypeStyle>
        <Rule>
          <Name>nombres</Name>
          <MaxScaleDenominator>1500</MaxScaleDenominator>
          <TextSymbolizer>
            <Label><ogc:PropertyName>nombre</ogc:PropertyName></Label>
            <Font><CssParameter name="font-family">Garet</CssParameter><CssParameter name="font-size">10</CssParameter></Font>
            <Halo><Radius>1.5</Radius><Fill><CssParameter name="fill">#FFFFFF</CssParameter></Fill></Halo>
            <Fill><CssParameter name="fill">#3D2A4A</CssParameter></Fill>
            <VendorOption name="autoWrap">90</VendorOption>
            <VendorOption name="goodnessOfFit">0.3</VendorOption>
          </TextSymbolizer>
        </Rule>
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
EOXML
}

http_code() {
  gs_curl -s -o /dev/null -w "%{http_code}" "$@"
}

echo "Publicando $WORKSPACE:$LAYER ..."

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
if [ "$capa" != "200" ]; then
  payload="{\"featureType\":{\"name\":\"$LAYER\",\"nativeName\":\"$LAYER\",\"title\":\"Espacios del instituto\",\"srs\":\"$SRS\",\"cqlFilter\":\"incluir = true\",\"enabled\":true}}"
  code=$(http_code -XPOST -H "Content-Type: application/json" -d "$payload" \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes")
  if [ "$code" != "201" ]; then
    echo "✗ No se pudo publicar la capa (HTTP $code). ¿Corrió 'make migrate' en dataengine?" >&2
    exit 1
  fi
  echo "  capa publicada (HTTP $code)"
else
  echo "  capa ya publicada"
fi

estilo=$(http_code "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/styles/$STYLE.json")
if [ "$estilo" = "200" ]; then
  code=$(http_code -XPUT -H "Content-Type: application/vnd.ogc.sld+xml" --data-binary @- \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/styles/$STYLE" < <(estilo_sld))
  echo "  estilo actualizado (HTTP $code)"
else
  code=$(http_code -XPOST -H "Content-Type: application/vnd.ogc.sld+xml" --data-binary @- \
    "$GEOSERVER_URL/rest/workspaces/$WORKSPACE/styles?name=$STYLE" < <(estilo_sld))
  echo "  estilo creado (HTTP $code)"
fi
if [ "$code" != "200" ] && [ "$code" != "201" ]; then
  echo "✗ No se pudo guardar el estilo (HTTP $code)" >&2
  exit 1
fi

code=$(http_code -XPUT -H "Content-Type: application/json" \
  -d "{\"layer\":{\"defaultStyle\":{\"name\":\"$STYLE\",\"workspace\":\"$WORKSPACE\"}}}" \
  "$GEOSERVER_URL/rest/layers/$WORKSPACE:$LAYER")
if [ "$code" != "200" ]; then
  echo "✗ No se pudo asignar el estilo a la capa (HTTP $code)" >&2
  exit 1
fi

echo "✓ $WORKSPACE:$LAYER listo."
