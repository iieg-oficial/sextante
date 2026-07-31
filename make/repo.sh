BACKUP_DIR='backups'
GEOSERVER_WAIT_MAX=60

wait_geoserver() {
    local attempts=0
    until docker exec sextante curl -sf http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}/web/ >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$GEOSERVER_WAIT_MAX" ]; then
            printf '\n'
            docker logs sextante --tail 20 2>&1 | while IFS= read -r line; do
                printf '         %s\n' "$line"
            done
            fail "GeoServer:no respondio despues de $((GEOSERVER_WAIT_MAX * 5))s" \
                 'Revisa los logs de arriba: make logs'
        fi
        sleep 5
    done
}

set_charset() {
    local user pass
    user=$(docker exec sextante env | grep '^GEOSERVER_ADMIN_USER=' | cut -d= -f2)
    pass=$(docker exec sextante env | grep '^GEOSERVER_ADMIN_PASSWORD=' | cut -d= -f2)
    docker exec sextante curl -sf -u "$user:$pass" -X PUT \
        -H 'Content-Type: application/json' \
        -d '{"global":{"settings":{"charset":"UTF-8"}}}' \
        http://localhost:8080/${GEOSERVER_CONTEXT_ROOT:-sextante}/rest/settings >/dev/null 2>&1 || true
}

init_all() {
    run_step 'Datastores' bash scripts/init-datastores.sh
    run_step 'Cultivos' bash scripts/init-cultivos-layer.sh
    run_step 'Gridsets' bash scripts/init-gridsets.sh
    run_step 'URLChecks' bash scripts/setup-urlchecks.sh
    run_step 'GWC filters' bash scripts/init-gwc-filters.sh
}

clean_data_dir() {
    docker run --rm -v "$(pwd)":/data alpine rm -rf /data/geoserver_data
    row 'Data dir' 'eliminado' "$C_GREEN" 'geoserver_data/'
}

pick_backup() {
    local -a files
    mapfile -t files < <(ls -1t restore/geoserver_data_*.tar.gz "$BACKUP_DIR"/geoserver_data_*.tar.gz 2>/dev/null)
    if [ ${#files[@]} -eq 0 ]; then
        fail 'Backup:no hay archivos en restore/ ni en backups/' \
             'Copia un geoserver_data_*.tar.gz a restore/ y vuelve a intentar.'
    fi
    pick 'Archivo' "${files[@]}"
}
