gs_curl() {
    local cred="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"
    cred=${cred//\\/\\\\}
    cred=${cred//\"/\\\"}
    curl -K <(printf 'user = "%s"\n' "$cred") "$@"
}
