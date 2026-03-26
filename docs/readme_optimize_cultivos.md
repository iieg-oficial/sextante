# optimize-cultivos.py

Script Python que optimiza el rendimiento espacial de la tabla `economia.cultivos` en PostgreSQL/PostGIS **antes de que GeoServer registre los datastores**, durante la ejecución de `make up` o `make restore`.

---

## ¿Por qué existe?

GeoServer al registrar un datastore y publicar capas hace las primeras consultas WFS/WMS a la tabla. Si el índice ya está optimizado y las estadísticas actualizadas en ese momento, las primeras solicitudes son rápidas en lugar de lentas.

---

## Cómo se invoca

El Makefile lo llama automáticamente antes de `init-datastores.sh`:

```
make up
  └─ docker compose up -d
  └─ (espera a que GeoServer esté listo)
  └─ python3 scripts/optimize-cultivos.py   ← aquí
  └─ bash scripts/init-datastores.sh
```

También se ejecuta en `make restore` tras restaurar un backup.

---

## Configuración

Las credenciales se leen del archivo `.env` del proyecto. Las variables de entorno del sistema tienen **prioridad** sobre el `.env`, lo que permite sobreescribir valores puntualmente.

| Variable           | Descripción                                  | Default               |
|--------------------|----------------------------------------------|-----------------------|
| `POSTGIS_CONTAINER`| Nombre del contenedor Docker con PostgreSQL  | `dataengine-primary`  |
| `POSTGIS_DB`       | Nombre de la base de datos                   | —                     |
| `POSTGIS_USER`     | Usuario de PostgreSQL                        | —                     |
| `POSTGIS_PASSWORD` | Contraseña de PostgreSQL                     | —                     |

Ejemplo en `.env`:
```
POSTGIS_CONTAINER=dataengine-primary
POSTGIS_DB=iieg_gis
POSTGIS_USER=gisuser
POSTGIS_PASSWORD=secreto
```

---

## Cómo se conecta a la base de datos

No usa ninguna librería Python externa (ni psycopg2 ni similar). En su lugar, invoca `psql` directamente dentro del contenedor usando `docker exec`:

```bash
docker exec -e PGPASSWORD=... dataengine-primary \
  psql -U gisuser -d iieg_gis -v ON_ERROR_STOP=1 -c "..."
```

**Ventajas de este enfoque:**
- Sin dependencias Python adicionales.
- Sin problemas de resolución DNS desde el host (el contenedor resuelve su propia red).
- Sin necesidad de exponer el puerto de PostgreSQL al host.
- `ON_ERROR_STOP=1` hace que cualquier error SQL detenga el script inmediatamente.

---

## Flujo de ejecución

### 1. Verificaciones de seguridad

Antes de operar, el script verifica en orden:

1. Que el contenedor `dataengine-primary` esté corriendo (`docker inspect`).
2. Que el schema `economia` exista en la base de datos.
3. Que la tabla `cultivos` exista en ese schema.

Si alguna condición falla, registra un `WARNING` y **termina limpiamente sin error** (exit 0) para no bloquear el resto del `make up`.

### 2. Estadísticas previas

Consulta `pg_stat_user_tables` para mostrar el estado de la tabla antes de optimizar:

```sql
SELECT last_vacuum, last_analyze, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'cultivos';
```

| Columna        | Significado                                      |
|----------------|--------------------------------------------------|
| `last_vacuum`  | Última vez que se ejecutó VACUUM en la tabla     |
| `last_analyze` | Última vez que se actualizaron las estadísticas  |
| `n_live_tup`   | Número de filas vivas (visibles)                 |
| `n_dead_tup`   | Número de filas muertas (pendientes de limpiar)  |

### 3. Reconstrucción del índice espacial

Se ejecutan 4 operaciones en secuencia. Si cualquiera falla, el script aborta con error.

#### Paso 1 — Eliminar el índice existente

```sql
DROP INDEX IF EXISTS economia.sidx_cultivos_geom;
```

Se elimina el índice viejo para poder recrearlo completamente con los parámetros óptimos. `IF EXISTS` evita error si el índice no existía.

#### Paso 2 — Crear el índice GiST

```sql
CREATE INDEX sidx_cultivos_geom
ON economia.cultivos
USING gist(geom) WITH (fillfactor=90);
```

- **`USING gist`**: índice espacial R-Tree optimizado para geometrías PostGIS.
- **`fillfactor=90`**: reserva un 10% de espacio libre en cada página del índice. Reduce la fragmentación y los rebalanceos cuando se insertan o actualizan geometrías en el futuro.

#### Paso 3 — CLUSTER

```sql
CLUSTER economia.cultivos USING sidx_cultivos_geom;
```

Reordena físicamente las filas de la tabla en disco siguiendo el orden del índice espacial. Las geometrías geográficamente cercanas quedan en los mismos bloques de disco, lo que reduce drásticamente la cantidad de I/O en consultas por área o bounding box.

> **Nota:** `CLUSTER` bloquea la tabla con `ACCESS EXCLUSIVE` durante su ejecución. En producción con carga continua se debe programar en horario de baja actividad.

#### Paso 4 — ANALYZE

```sql
ANALYZE economia.cultivos;
```

Actualiza las estadísticas internas del planificador de consultas de PostgreSQL. Con estadísticas actualizadas, el planificador elige los planes de ejecución más eficientes (p. ej. si usar el índice espacial o hacer un seqscan).

---

## Salida esperada

```
2026-03-26 13:44:51 [INFO] === Iniciando optimize-cultivos.py ===
2026-03-26 13:44:51 [INFO] Usando contenedor DB: dataengine-primary / base: iieg_gis / usuario: gisuser
2026-03-26 13:44:51 [INFO] Estadísticas actuales de economia.cultivos:
2026-03-26 13:44:52 [INFO]
 last_vacuum | last_analyze | n_live_tup | n_dead_tup
-------------+--------------+------------+------------
             |              |    1823401 |          0
2026-03-26 13:44:52 [INFO] Eliminando índice economia.sidx_cultivos_geom (si existe)...
2026-03-26 13:44:52 [INFO]   OK
2026-03-26 13:44:52 [INFO] Creando índice GiST sidx_cultivos_geom con fillfactor=90...
2026-03-26 13:44:52 [INFO]   OK
2026-03-26 13:44:52 [INFO] Ejecutando CLUSTER economia.cultivos USING sidx_cultivos_geom...
2026-03-26 13:44:57 [INFO]   OK
2026-03-26 13:44:57 [INFO] Ejecutando ANALYZE economia.cultivos...
2026-03-26 13:44:57 [INFO]   OK
2026-03-26 13:44:57 [INFO] Optimización de economia.cultivos completada.
```

---

## Casos especiales

| Situación | Comportamiento |
|-----------|---------------|
| Contenedor DB no está corriendo | Avisa con WARNING y continúa (exit 0) |
| Schema `economia` no existe | Avisa con WARNING y continúa (exit 0) |
| Tabla `cultivos` no existe | Avisa con WARNING y continúa (exit 0) |
| Error SQL en cualquier paso | Registra ERROR y aborta (exit 1) |

---

## Archivos relacionados

| Archivo | Rol |
|---------|-----|
| [scripts/optimize-cultivos.py](scripts/optimize-cultivos.py) | Script principal |
| [scripts/init-datastores.sh](scripts/init-datastores.sh) | Se ejecuta después de este script |
| [Makefile](Makefile) | Orquesta la ejecución en `make up` y `make restore` |
| [.env.example](.env.example) | Variables de entorno requeridas |
