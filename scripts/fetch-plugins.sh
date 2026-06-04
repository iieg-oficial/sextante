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

extract_jar_from_zip() {
    local zip_path="$1"
    local jar_name="$2"
    local dest_dir="$3"

    if command -v unzip >/dev/null 2>&1; then
        unzip -o -j "$zip_path" "$jar_name" -d "$dest_dir" 2>&1
        return $?
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$zip_path" "$jar_name" "$dest_dir" <<'PY' 2>&1
import os, sys, zipfile
zip_path, jar_name, dest_dir = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with zipfile.ZipFile(zip_path) as z:
        matches = [n for n in z.namelist() if os.path.basename(n) == jar_name]
        if not matches:
            sys.stderr.write("jar {} no encontrado en zip\n".format(jar_name))
            sys.exit(1)
        with z.open(matches[0]) as src, open(os.path.join(dest_dir, jar_name), "wb") as dst:
            dst.write(src.read())
except Exception as e:
    sys.stderr.write("error extrayendo {}: {}\n".format(jar_name, e))
    sys.exit(1)
PY
        return $?
    fi

    echo "ni 'unzip' ni 'python3' estan disponibles para extraer JARs" >&2
    return 127
}

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
        target="$PLUGINS_DIR/$jar"
        if [ -d "$target" ]; then
            if rmdir "$target" 2>/dev/null; then
                echo "[info]  ${name}: removido directorio vacio en lugar de ${jar}" >&2
            else
                echo "[warn]  ${name}: ${target} existe como directorio no vacio; eliminalo manualmente y reintenta" >&2
                extract_failed=1
                break
            fi
        fi
        extract_out=$(extract_jar_from_zip "$tmp_zip" "$jar" "$PLUGINS_DIR") || extract_rc=$?
        if [ "${extract_rc:-0}" -ne 0 ]; then
            echo "[warn]  ${name}: fallo al extraer ${jar}:" >&2
            echo "$extract_out" | sed 's/^/        /' >&2
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
