#!/usr/bin/env bash
set -uo pipefail

GS_VERSION="2.27.0"
SF_BASE="https://sourceforge.net/projects/geoserver/files/GeoServer/${GS_VERSION}/extensions"
PLUGINS_DIR="$(cd "$(dirname "$0")/.." && pwd)/plugins"

mkdir -p "$PLUGINS_DIR"

PLUGINS=(
    "geopkg-output|gs-geopkg-output-core-${GS_VERSION}.jar,gs-geopkg-output-wfs-${GS_VERSION}.jar,gs-geopkg-output-wms-${GS_VERSION}.jar"
    "wps-download|gs-wps-download-${GS_VERSION}.jar,jcodec-0.2.3.jar,jcodec-javase-0.2.3.jar"
)

skipped=()
installed=()
failed=()

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
        skipped+=("$name")
        continue
    fi

    echo "[fetch] ${name}: faltan ${#missing_jars[@]}/${#jar_list[@]} JAR(s) (${missing_jars[*]})"

    zip_url="${SF_BASE}/geoserver-${GS_VERSION}-${name}-plugin.zip/download"
    tmp_zip="$(mktemp -t "geoserver-plugin-${name}-XXXXXX.zip")"

    if ! curl -fsSL -o "$tmp_zip" "$zip_url"; then
        echo "[warn]  ${name}: fallo descargando ${zip_url}" >&2
        failed+=("$name (download)")
        rm -f "$tmp_zip"
        continue
    fi

    zip_size=$(stat -c %s "$tmp_zip" 2>/dev/null || stat -f %z "$tmp_zip" 2>/dev/null || echo 0)
    if [ "$zip_size" -lt 1024 ]; then
        echo "[warn]  ${name}: zip descargado parece truncado (${zip_size} bytes)" >&2
        failed+=("$name (truncated zip)")
        rm -f "$tmp_zip"
        continue
    fi

    extract_failed=0
    for jar in "${missing_jars[@]}"; do
        unzip_out=$(unzip -o -j "$tmp_zip" "$jar" -d "$PLUGINS_DIR" 2>&1) || extract_rc=$?
        if [ "${extract_rc:-0}" -ne 0 ]; then
            echo "[warn]  ${name}: unzip fallo al extraer ${jar}:" >&2
            echo "$unzip_out" | sed 's/^/        /' >&2
            extract_failed=1
            unset extract_rc
            break
        fi
        if [ ! -f "$PLUGINS_DIR/$jar" ]; then
            echo "[warn]  ${name}: ${jar} no aparecio tras extraer" >&2
            extract_failed=1
            break
        fi
    done

    rm -f "$tmp_zip"

    if [ "$extract_failed" -eq 1 ]; then
        failed+=("$name (extract)")
        continue
    fi

    echo "[ok]    ${name}: instalado"
    installed+=("$name")
done

echo ""
echo "Resumen: ${#installed[@]} instalado(s), ${#skipped[@]} ya presente(s), ${#failed[@]} con error"

if [ "${#failed[@]}" -gt 0 ]; then
    echo ""
    echo "AVISO: las siguientes extensions no se pudieron instalar:" >&2
    for f in "${failed[@]}"; do
        echo "  - $f" >&2
    done
    echo "" >&2
    echo "GeoServer arrancara igual; los procesos/outputs de esas extensions no estaran disponibles." >&2
    echo "Re-ejecuta 'make plugins-fetch' cuando el problema se resuelva." >&2
fi

exit 0
