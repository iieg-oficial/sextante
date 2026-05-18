#!/bin/bash
sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    -e "s|\${TOMCAT_SECURE}|${TOMCAT_SECURE:-true}|g" \
    /opt/geoserver/server.xml.template > /usr/local/tomcat/conf/server.xml

sed -e "s|\${GEOSERVER_PROXY_BASE_URL}|${GEOSERVER_PROXY_BASE_URL}|g" \
    /opt/geoserver/global.xml.template > /opt/geoserver/data_dir/global.xml

exec /scripts/entrypoint.sh
