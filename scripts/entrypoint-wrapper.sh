#!/bin/bash
sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    /opt/geoserver/server.xml.template > /usr/local/tomcat/conf/server.xml

sed -e "s|\${GEOSERVER_PROXY_BASE_URL}|${GEOSERVER_PROXY_BASE_URL}|g" \
    /opt/geoserver/global.xml.template > /opt/geoserver/data_dir/global.xml

APP_VERSION=$(tr -d ' \n' < /opt/geoserver/VERSION 2>/dev/null || echo unknown)
RELEASED_AT=$(grep -m1 -E "^## \[${APP_VERSION}\] - " /opt/geoserver/CHANGELOG.md 2>/dev/null \
    | sed -E 's/^## \[[^]]+\] - ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
[ -z "$RELEASED_AT" ] && RELEASED_AT=$(date -u -r /opt/geoserver/VERSION +%Y-%m-%d 2>/dev/null || echo unknown)
mkdir -p /usr/local/tomcat/webapps/ROOT
printf '{"version":"%s","service":"geoserver","released_at":"%s"}\n' \
    "$APP_VERSION" "$RELEASED_AT" \
    > /usr/local/tomcat/webapps/ROOT/ontoy.json

exec /scripts/entrypoint.sh
