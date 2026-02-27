#!/bin/bash
sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    /opt/geoserver/server.xml.template > /usr/local/tomcat/conf/server.xml

exec /scripts/entrypoint.sh
