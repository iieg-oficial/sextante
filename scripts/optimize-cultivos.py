#!/usr/bin/env python3
"""
Optimización del índice espacial y estadísticas de economia.cultivos.
Se ejecuta antes de init-datastores.sh.
Usa docker exec para correr psql dentro del contenedor dataengine-primary,
evitando dependencias externas como psycopg2 o acceso de red desde el host.
"""

import logging
import os
import subprocess
import sys
import pathlib
import re

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("optimize-cultivos")

log.info("=== Iniciando optimize-cultivos.py ===")

# ---------------------------------------------------------------------------
# Lectura del .env
# ---------------------------------------------------------------------------

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
ENV_FILE = PROJECT_DIR / ".env"

def load_env(path: pathlib.Path) -> dict:
    env = {}
    if not path.is_file():
        return env
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line)
            if m:
                key, value = m.group(1), m.group(2)
                if len(value) >= 2 and value[0] in ('"', "'") and value[-1] == value[0]:
                    value = value[1:-1]
                env[key] = value
    return env

dot_env = load_env(ENV_FILE)

def get(key: str, default: str = "") -> str:
    return os.environ.get(key) or dot_env.get(key, default)

DB_CONTAINER = get("POSTGIS_CONTAINER", "dataengine-primary")
DB_NAME = get("POSTGIS_DB")
DB_USER = get("POSTGIS_USER")
DB_PASS = get("POSTGIS_PASSWORD")

if not all([DB_NAME, DB_USER]):
    log.error("Faltan variables POSTGIS_DB o POSTGIS_USER en .env")
    sys.exit(1)

SCHEMA = "economia"
TABLE  = "cultivos"
INDEX  = "sidx_cultivos_geom"
COLUMN = "geom"

# ---------------------------------------------------------------------------
# Ejecución de queries via docker exec psql
# ---------------------------------------------------------------------------

def psql(sql: str, tuples_only: bool = False) -> subprocess.CompletedProcess:
    """Ejecuta SQL dentro del contenedor DB y retorna el resultado."""
    cmd = [
        "docker", "exec",
        "-e", f"PGPASSWORD={DB_PASS}",
        DB_CONTAINER,
        "psql", "-U", DB_USER, "-d", DB_NAME,
        "-v", "ON_ERROR_STOP=1",
    ]
    if tuples_only:
        cmd += ["-t", "-A"]
    cmd += ["-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True)

def psql_scalar(sql: str) -> str:
    """Ejecuta SQL y retorna el primer valor como string limpio."""
    result = psql(sql, tuples_only=True)
    return result.stdout.strip()

# ---------------------------------------------------------------------------
# Verificaciones de existencia
# ---------------------------------------------------------------------------

def container_running() -> bool:
    result = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Running}}", DB_CONTAINER],
        capture_output=True, text=True,
    )
    return result.returncode == 0 and result.stdout.strip() == "true"

def schema_exists() -> bool:
    val = psql_scalar(
        f"SELECT EXISTS (SELECT 1 FROM information_schema.schemata "
        f"WHERE schema_name = '{SCHEMA}')"
    )
    return val == "t"

def table_exists() -> bool:
    val = psql_scalar(
        f"SELECT EXISTS (SELECT 1 FROM information_schema.tables "
        f"WHERE table_schema = '{SCHEMA}' AND table_name = '{TABLE}')"
    )
    return val == "t"

# ---------------------------------------------------------------------------
# Operaciones
# ---------------------------------------------------------------------------

def print_stats():
    log.info("Estadísticas actuales de %s.%s:", SCHEMA, TABLE)
    result = psql(
        f"SELECT last_vacuum, last_analyze, n_live_tup, n_dead_tup "
        f"FROM pg_stat_user_tables WHERE relname = '{TABLE}'"
    )
    if result.returncode == 0 and result.stdout.strip():
        log.info("\n%s", result.stdout.strip())
    else:
        log.warning("Sin estadísticas disponibles (puede que ANALYZE no se haya ejecutado aún)")

def run_sql(description: str, sql: str):
    log.info("%s...", description)
    result = psql(sql)
    if result.returncode != 0:
        log.error("Falló: %s", result.stderr.strip())
        sys.exit(1)
    log.info("  OK")

def rebuild_index():
    fq_table = f"{SCHEMA}.{TABLE}"
    fq_index = f"{SCHEMA}.{INDEX}"

    run_sql(
        f"Eliminando índice {fq_index} (si existe)",
        f"DROP INDEX IF EXISTS {fq_index}",
    )
    run_sql(
        f"Creando índice GiST {INDEX} con fillfactor=90",
        f"CREATE INDEX {INDEX} ON {fq_table} USING gist({COLUMN}) WITH (fillfactor=90)",
    )
    run_sql(
        f"Ejecutando CLUSTER {fq_table} USING {INDEX}",
        f"CLUSTER {fq_table} USING {INDEX}",
    )
    run_sql(
        f"Ejecutando ANALYZE {fq_table}",
        f"ANALYZE {fq_table}",
    )

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    log.info("Usando contenedor DB: %s / base: %s / usuario: %s", DB_CONTAINER, DB_NAME, DB_USER)

    if not container_running():
        log.warning("El contenedor '%s' no está corriendo. Se omite la optimización.", DB_CONTAINER)
        return

    if not schema_exists():
        log.warning("El esquema '%s' no existe. Se omite la optimización.", SCHEMA)
        return

    if not table_exists():
        log.warning("La tabla '%s.%s' no existe. Se omite la optimización.", SCHEMA, TABLE)
        return

    print_stats()
    rebuild_index()
    log.info("Optimización de %s.%s completada.", SCHEMA, TABLE)

if __name__ == "__main__":
    main()
