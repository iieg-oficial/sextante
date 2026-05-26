#!/bin/bash
sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    -e "s|\${TOMCAT_SECURE}|${TOMCAT_SECURE:-true}|g" \
    /opt/geoserver/server.xml.template > /usr/local/tomcat/conf/server.xml

sed -e "s|\${GEOSERVER_PROXY_BASE_URL}|${GEOSERVER_PROXY_BASE_URL}|g" \
    /opt/geoserver/global.xml.template > /opt/geoserver/data_dir/global.xml

sed -e "s|\${GS_CONTROLFLOW_TIMEOUT}|${GS_CONTROLFLOW_TIMEOUT}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_GLOBAL}|${GS_CONTROLFLOW_OWS_GLOBAL}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_WMS_GETMAP}|${GS_CONTROLFLOW_OWS_WMS_GETMAP}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_WFS_MSEXCEL}|${GS_CONTROLFLOW_OWS_WFS_MSEXCEL}|g" \
    -e "s|\${GS_CONTROLFLOW_OWS_GWC}|${GS_CONTROLFLOW_OWS_GWC}|g" \
    -e "s|\${GS_CONTROLFLOW_USER}|${GS_CONTROLFLOW_USER}|g" \
    -e "s|\${GS_CONTROLFLOW_USER_WPS_EXECUTE}|${GS_CONTROLFLOW_USER_WPS_EXECUTE}|g" \
    -e "s|\${GS_CONTROLFLOW_USER_WMS_GETMAP}|${GS_CONTROLFLOW_USER_WMS_GETMAP}|g" \
    -e "s|\${GS_CONTROLFLOW_IP}|${GS_CONTROLFLOW_IP}|g" \
    /opt/geoserver/controlflow.properties.template > /opt/geoserver/data_dir/controlflow.properties

exec /scripts/entrypoint.sh
