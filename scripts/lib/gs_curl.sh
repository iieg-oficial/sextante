gs_escapar() {
    local v=$1
    v=${v//\\/\\\\}
    v=${v//\"/\\\"}
    printf '%s' "$v"
}

gs_token() {
    local cache="${TMPDIR:-/tmp}/sextante-gs-token-$(id -u)" ahora vence token respuesta
    ahora=$(date +%s)
    if [ -f "$cache" ] && read -r vence token < "$cache" && [ "$ahora" -lt $((vence - 60)) ]; then
        printf '%s' "$token"
        return 0
    fi
    respuesta=$(curl -s --max-time 20 -K <(
        printf 'data-urlencode = "%s"\n' \
            "grant_type=client_credentials" \
            "client_id=$(gs_escapar "$OIDC_CLIENT_ID")" \
            "client_secret=$(gs_escapar "$OIDC_CLIENT_SECRET")" \
            "audience=sextante"
    ) "${OIDC_INTERNAL_URL%/}/auth/token")
    read -r vence token < <(printf '%s' "$respuesta" | python3 -c '
import json, sys, time
d = json.load(sys.stdin)
print(int(time.time()) + int(d["expires_in"]), d["access_token"])' 2>/dev/null)
    if [ -z "${token:-}" ]; then
        echo "✗ minerva no dio token de servicio: $respuesta" >&2
        return 1
    fi
    (umask 077 && printf '%s %s\n' "$vence" "$token" > "$cache")
    printf '%s' "$token"
}

gs_curl() {
    if [ "${GEOSERVER_AUTH_MODE:-basic}" = "minerva" ]; then
        local token
        token=$(gs_token) || return 1
        curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$token") "$@"
    else
        local cred="${GEOSERVER_ADMIN_USER}:${GEOSERVER_ADMIN_PASSWORD}"
        curl -K <(printf 'user = "%s"\n' "$(gs_escapar "$cred")") "$@"
    fi
}
