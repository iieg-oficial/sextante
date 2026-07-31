#!/bin/bash
set -e

DATA_DIR="${GEOSERVER_DATA_DIR:-/opt/geoserver/data_dir}"
CONFIG_DIR=/opt/geoserver/config
FONTS_SRC=/opt/geoserver/fonts

mkdir -p /settings "$DATA_DIR/security"

sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    -e "s|\${TOMCAT_SECURE}|${TOMCAT_SECURE:-true}|g" \
    /opt/geoserver/server.xml.template > /settings/server.xml

sed -e "s|\${GEOSERVER_PROXY_BASE_URL}|${GEOSERVER_PROXY_BASE_URL}|g" \
    /opt/geoserver/global.xml.template > "$DATA_DIR/global.xml"

sed -e "s|\${GS_CONTROLFLOW_TIMEOUT}|${GS_CONTROLFLOW_TIMEOUT}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_GLOBAL}|${GS_CONTROLFLOW_OWS_GLOBAL}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_WMS_GETMAP}|${GS_CONTROLFLOW_OWS_WMS_GETMAP}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_WFS_MSEXCEL}|${GS_CONTROLFLOW_OWS_WFS_MSEXCEL}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_GWC}|${GS_CONTROLFLOW_OWS_GWC}|g" \
    -e "s|\${GS_CONTROLFLOW_USER}|${GS_CONTROLFLOW_USER}|g" \
    -e "s|\${GS_CONTROLFLOW_USER_WPS_EXECUTE}|${GS_CONTROLFLOW_USER_WPS_EXECUTE}|g" \
    -e "s|\${GS_CONTROLFLOW_USER_WMS_GETMAP}|${GS_CONTROLFLOW_USER_WMS_GETMAP}|g" \
    -e "s|\${GS_CONTROLFLOW_IP}|${GS_CONTROLFLOW_IP}|g" \
    /opt/geoserver/controlflow.properties.template > "$DATA_DIR/controlflow.properties"

cp -f "$CONFIG_DIR/wms.xml" "$DATA_DIR/wms.xml"
cp -f "$CONFIG_DIR/wfs.xml" "$DATA_DIR/wfs.xml"
cp -f "$CONFIG_DIR/csp.xml" "$DATA_DIR/security/csp.xml"

if ls "$FONTS_SRC"/*.otf >/dev/null 2>&1; then
    mkdir -p /usr/share/fonts/opentype
    cp -f "$FONTS_SRC"/*.otf /usr/share/fonts/opentype/
fi
if ls "$FONTS_SRC"/*.ttf >/dev/null 2>&1; then
    mkdir -p /usr/share/fonts/truetype
    cp -f "$FONTS_SRC"/*.ttf /usr/share/fonts/truetype/
fi

exec /scripts/entrypoint.sh
