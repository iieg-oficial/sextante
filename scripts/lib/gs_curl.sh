gs_curl() {
    local cred="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"
    cred=${cred//\\/\\\\}
    cred=${cred//\"/\\\"}
    printf 'user = "%s"\n' "$cred" | curl -K - "$@"
}
