#!/usr/bin/env bash
set -euo pipefail

GS_VERSION="2.27.0"
SF_BASE="https://sourceforge.net/projects/geoserver/files/GeoServer/${GS_VERSION}/extensions"
PLUGINS_DIR="$(cd "$(dirname "$0")/.." && pwd)/plugins"

mkdir -p "$PLUGINS_DIR"

PLUGINS=(
    "geopkg-output|gs-geopkg-output-core-${GS_VERSION}.jar,gs-geopkg-output-wfs-${GS_VERSION}.jar,gs-geopkg-output-wms-${GS_VERSION}.jar"
    "wps-download|gs-wps-download-${GS_VERSION}.jar,jcodec-0.2.3.jar,jcodec-javase-0.2.3.jar"
)

fetched_any=0
failed=0

for entry in "${PLUGINS[@]}"; do
    name="${entry%%|*}"
    jars_csv="${entry#*|}"

    IFS=',' read -ra jar_list <<< "$jars_csv"

    missing_jars=()
    for jar in "${jar_list[@]}"; do
        [ -f "$PLUGINS_DIR/$jar" ] || missing_jars+=("$jar")
    done

    if [ "${#missing_jars[@]}" -eq 0 ]; then
        echo "[skip] ${name}: ${#jar_list[@]} JAR(s) ya presentes"
        continue
    fi

    echo "[fetch] ${name}: faltan ${#missing_jars[@]}/${#jar_list[@]} JAR(s) (${missing_jars[*]})"

    zip_url="${SF_BASE}/geoserver-${GS_VERSION}-${name}-plugin.zip/download"
    tmp_zip="$(mktemp -t "geoserver-plugin-${name}-XXXXXX.zip")"
    trap 'rm -f "$tmp_zip"' EXIT

    if ! curl -fsSL -o "$tmp_zip" "$zip_url"; then
        echo "[error] ${name}: fallo descargando ${zip_url}" >&2
        failed=1
        rm -f "$tmp_zip"
        trap - EXIT
        continue
    fi

    extract_failed=0
    for jar in "${missing_jars[@]}"; do
        if ! unzip -o -j "$tmp_zip" "$jar" -d "$PLUGINS_DIR" >/dev/null 2>&1; then
            echo "[error] ${name}: no se pudo extraer ${jar} del zip" >&2
            extract_failed=1
            break
        fi
        if [ ! -f "$PLUGINS_DIR/$jar" ]; then
            echo "[error] ${name}: ${jar} no aparecio tras extraer" >&2
            extract_failed=1
            break
        fi
    done

    rm -f "$tmp_zip"
    trap - EXIT

    if [ "$extract_failed" -eq 1 ]; then
        failed=1
        continue
    fi

    echo "[ok]    ${name}: instalado"
    fetched_any=1
done

if [ "$failed" -eq 1 ]; then
    echo ""
    echo "✗ Hubo errores descargando uno o mas plugins. Revisa la salida arriba." >&2
    exit 1
fi

if [ "$fetched_any" -eq 0 ]; then
    echo ""
    echo "✓ Todos los plugins ya estaban instalados."
else
    echo ""
    echo "✓ Plugins listos en ${PLUGINS_DIR}"
fi
