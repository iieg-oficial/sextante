BACKUP_DIR='backups'
GEOSERVER_WAIT_MAX=180

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
    docker exec -i sextante sh -c '
        auth=$(printf "%s:%s" "$GEOSERVER_ADMIN_USER" "$GEOSERVER_ADMIN_PASSWORD" | base64 -w0)
        printf "header = \"Authorization: Basic %s\"\n" "$auth" | curl -sf -K - -X PUT \
            -H "Content-Type: application/json" \
            -d "{\"global\":{\"settings\":{\"charset\":\"UTF-8\"}}}" \
            "http://localhost:8080/$GEOSERVER_CONTEXT_ROOT/rest/settings"
    ' >/dev/null 2>&1 || true
}

init_all() {
    run_step 'Datastores' bash scripts/init-datastores.sh
    run_step 'Cultivos' bash scripts/init-cultivos-layer.sh
    run_step 'Curvas render' bash scripts/init-curvas-render-layer.sh
    run_step 'Terreno RGB' bash scripts/init-terreno-rgb-layer.sh
    run_step 'Gridsets' bash scripts/init-gridsets.sh
    run_step 'URLChecks' bash scripts/setup-urlchecks.sh
    run_step 'GWC filters' bash scripts/init-gwc-filters.sh
    run_step 'GWC seed' bash scripts/gwc-seed.sh --auto
    cron_ensure
}

cron_install() {
    local dir
    dir=$(pwd)
    mkdir -p "$dir/logs"
    {
        crontab -l 2>/dev/null | grep -v 'sextante-gwc-seed' || true
        echo "30 4 * * * cd $dir && make gwc-seed ARGS=--auto >> $dir/logs/gwc-seed.log 2>&1 # sextante-gwc-seed"
    } | crontab -
    row 'Cron' 'instalado' "$C_GREEN" 'seed de GWC 04:30'
    crontab -l | grep 'sextante-gwc-seed' | while IFS= read -r line; do
        printf '         %s\n' "$line"
    done || true
}

cron_remove() {
    { crontab -l 2>/dev/null | grep -v 'sextante-gwc-seed' || true; } | crontab -
    row 'Cron' 'desinstalado' "$C_GREEN"
}

cron_ensure() {
    if crontab -l 2>/dev/null | grep -q 'sextante-gwc-seed'; then
        row 'Cron' 'ya instalado' "$C_DIM" 'seed de GWC 04:30'
        return 0
    fi
    cron_install
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
