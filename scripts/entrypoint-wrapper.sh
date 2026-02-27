#!/bin/bash
sed -e "s|\${HTTP_SCHEME}|${HTTP_SCHEME}|g" \
    -e "s|\${PROXY_HOST}|${PROXY_HOST}|g" \
    -e "s|\${PROXY_PORT}|${PROXY_PORT}|g" \
    /opt/geoserver/server.xml.template > /usr/local/tomcat/conf/server.xml

sed -e "s|\${GEOSERVER_PROXY_BASE_URL}|${GEOSERVER_PROXY_BASE_URL}|g" \
    /opt/geoserver/global.xml.template > /opt/geoserver/data_dir/global.xml

WEB_XML="/usr/local/tomcat/webapps/geoserver/WEB-INF/web.xml"
ERROR_PAGES="/opt/geoserver/config/web-error-pages.xml"
if [ -f "$WEB_XML" ] && [ -f "$ERROR_PAGES" ] && ! grep -q "<error-page>" "$WEB_XML"; then
    awk -v ef="$ERROR_PAGES" '/<\/web-app>/{while((getline l < ef)>0) print l}{print}' "$WEB_XML" > "${WEB_XML}.tmp" && mv "${WEB_XML}.tmp" "$WEB_XML"
fi

cp /opt/geoserver/error-pages/*.html /usr/local/tomcat/webapps/geoserver/error/ 2>/dev/null || {
    mkdir -p /usr/local/tomcat/webapps/geoserver/error
    cp /opt/geoserver/error-pages/*.html /usr/local/tomcat/webapps/geoserver/error/
}

exec /scripts/entrypoint.sh
