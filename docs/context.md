# Contexto del Proyecto GeoServer

Despliegue dockerizado de [GeoServer](https://geoserver.org) para el ecosistema IIEG. Sirve datos espaciales via WMS / WFS / WCS a los visores (Mapalab) y otros consumidores. La data viva en PostGIS (servida por DataEngine), GeoServer la rinde como capas geoespaciales.

Este documento condensa la operacion, la integracion con el ecosistema, y las decisiones no-obvias que rigen el deployment.

---

## Stack

| | Valor |
|---|---|
| Imagen base | `kartoza/geoserver:2.27.0` |
| Servidor app | Apache Tomcat (incluido en la imagen) |
| Java runtime | OpenJDK (de la imagen kartoza) |
| Plugins extras | `gs-geopkg-output-{core,wfs,wms}-2.27.0.jar` (GeoPackage como output format) |
| Datasource | PostgreSQL/PostGIS (vive en repo `dataengine`) |
| Lenguaje de scripts | Bash + Python 3 (psql via `docker exec`) |

GeoServer **no almacena datos espaciales**: lee de PostGIS y de rasters en disco (`geoserver_data/geoserver-raster/`). Los datastores se configuran via REST en el bootstrap.

---

## Ecosistema IIEG — quien habla con quien

```
                         Internet
                            │
                            ▼
        ┌──────────────────────────────────────────┐
        │ gateway-hub-nginx                         │
        │  /geoserver/ows  → proxy_cache 6h         │
        │  /geoserver/(wfs|wcs)  (sin cache)        │
        │  /geoserver/web,rest  (admin, sin cache)  │
        └────────────────┬─────────────────────────┘
                         │
                         ▼  http://geoserver:8080
              ┌─────────────────────┐
              │     GeoServer       │
              │ (Tomcat + WMS/WFS)  │
              └──┬───────────────┬──┘
                 │               │
                 │               │
   ┌─────────────┘               └─────────────┐
   │ JDBC (sslmode=allow)        Imagenes ExternalGraphic
   ▼                                            ▼
┌─────────────────┐                  ┌────────────────────┐
│ dataengine-     │                  │  acervo-minio      │
│ primary         │                  │  (bucket mapalab/  │
│ (PostGIS)       │                  │   simbologia/)     │
└─────────────────┘                  └────────────────────┘
```

| Repo | Rol respecto a GeoServer |
|---|---|
| `gateway-hub` | Proxy publico, cache `geoserver_cache` 6h con `proxy_ignore_headers Cache-Control` para servir WMS GetMap aun cuando GeoServer responde `no-store`. Bot-protection + rate limit. Ver `gateway-hub/docs/recursos-servidores.md` y `rendimiento.md`. |
| `dataengine` | PostgreSQL+PostGIS detras de PgBouncer. GeoServer se conecta a `dataengine-primary:5432` via red docker `dataengine-network`. La tabla `economia.cultivos` se optimiza pre-arranque con `scripts/optimize-cultivos.py` (ver `docs/readme_optimize_cultivos.md`). |
| `mariachi` | Editor de capas. `mariachi/api/app/api/routes/geoserver.py` lista workspaces/layers via REST de GeoServer (`GeoServerClient`). Las altas/bajas de metadatos viven en mariachi; GeoServer queda sincronizado. |
| `mapalab` | Consumidor principal del WMS. Frontend con `ImageWMS` (no `TileWMS`); BBOX/WIDTH/HEIGHT ad-hoc por viewport. Loop temporal de capas raster cicla el parametro `TIME` (ver `mapalab/MEMORY.md`). |
| `acervo` | Bucket S3-compatible (SeaweedFS). Sirve PNGs/SVGs referenciados por SLDs como `<ExternalGraphic>`. Reachable via red `iieg-network`. |

---

## Estructura del repo

```
geoserver/
├── Makefile                    # Operacion completa (up/down/backup/restore/init-datastores)
├── docker-compose.yml          # Servicio geoserver + 3 redes externas
├── server.xml                  # Conector Tomcat (HTTPS via proxy)
├── server.xml.template         # Template; envsubst con vars .env
├── config/
│   ├── global.xml              # Generado desde global.xml.template
│   ├── global.xml.template     # JAI + coverageAccess + proxyBaseUrl
│   ├── wms.xml                 # Servicio WMS (versiones, charset, cache deshabilitado a nivel servicio)
│   ├── wfs.xml                 # Servicio WFS
│   ├── web-error-pages.xml     # Errores custom GeoServer
│   └── security/csp.xml        # Content Security Policy
├── scripts/
│   ├── entrypoint-wrapper.sh   # Sustituye templates + escribe /ontoy.json + lanza entrypoint kartoza
│   ├── init-datastores.sh      # Crea/actualiza datastores PostGIS via REST
│   ├── reset-admin.sh          # Resetea credenciales admin en el .env tras restore
│   └── optimize-cultivos.py    # ANALYZE/CLUSTER/CREATE INDEX en economia.cultivos pre-WMS
├── plugins/                    # JARs montados al classpath de Tomcat (gitignored)
│   └── gs-geopkg-output-*.jar  # 3 plugins de salida GeoPackage
├── fonts/                      # Garet (font family corporativa IIEG) montado en /usr/share/fonts/custom
├── geoserver_data/             # Data dir persistente (gitignored)
│   ├── workspaces/             # Workspaces y datastores configurados
│   ├── styles/                 # SLDs
│   ├── controlflow.properties  # Limites de concurrencia (importante, ver mas abajo)
│   └── gwc-gs.xml              # GeoWebCache config
├── backups/                    # tar.gz del data_dir, generados por make backup (gitignored)
├── error-pages/                # Paginas HTML de error
├── .env                        # Per-host, gitignored
├── .env.example                # Template versionado, con tuning recomendado por entorno
└── docs/
    ├── CHANGELOG.md
    ├── readme_optimize_cultivos.md  # Detalle del script de optimizacion PostGIS
    └── context.md              # Este archivo
```

`.env` y `geoserver_data/` son **per-host** y nunca se versionan. La sincronizacion entre staging y produccion es manual (`scp` o edicion in-place sobre cada VM).

---

## Hosts y dimensionamiento por entorno

Fuente: `gateway-hub/docs/recursos-servidores.md`.

| Entorno | Servidor | CPU | RAM | Que corre |
|---|---|---|---|---|
| **GCP Staging** | `mapalab.us-central1-c.c.iieg2025-cloud.internal` | 2 | 7.8 GB | TODO el ecosistema (~20 contenedores). GeoServer apretado. |
| **Produccion S3** | dedicado | 8 | 15 GB | **Solo GeoServer**. Margen amplio. |

PostGIS no esta en el mismo host que GeoServer:
- Staging: PostGIS y GeoServer comparten VM (`dataengine-primary` corre en mismo docker).
- Produccion: PostGIS vive en S4 (4c/7.7GB dedicado a DataEngine). GeoServer en S3 se conecta a S4 via LAN.

### JVM tuning (a partir de 1.19.0)

La imagen `kartoza/geoserver` no setea caps explicitos de heap ni Metaspace; sin tuning la JVM corre con defaults chicos. Sintoma observado en staging: Old gen al 99.85 % en 5 segundos, Metaspace al 99.32 %, concurrent GC robando CPU al render.

| Entorno | `JAVA_OPTS` recomendado |
|---|---|
| GCP Staging | `-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Xms1g -Xmx2g -XX:MaxMetaspaceSize=512m -XX:+UseG1GC` |
| Produccion S3 | `-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g -XX:+UseG1GC` |

Validar con `docker exec geoserver jstat -gcutil 1 5s 5`. Old gen y Metaspace deben quedar muy por debajo del 90 % bajo carga normal.

El `.env.example` lleva la version conservadora como default seguro; comentario inline explica la variante prod.

---

## Variables de entorno (.env)

| Variable | Que hace |
|---|---|
| `GEOSERVER_ADMIN_USER`, `_PASSWORD` | Credenciales web/REST. Aplicadas en cada arranque si `RESET_ADMIN_CREDENTIALS=TRUE`. |
| `RESET_ADMIN_CREDENTIALS` | Si `TRUE`, kartoza reescribe `users.xml` al arrancar. Mantener `FALSE` en produccion una vez seteadas. |
| `GEOSERVER_DATA_DIR` | Ruta del data dir dentro del contenedor (`/opt/geoserver/data_dir`). |
| `GEOSERVER_PROXY_BASE_URL` | URL publica del proxy (ej. `https://iieg.jalisco.gob.mx/geoserver`). Se inyecta en `global.xml`. |
| `GEOSERVER_CSRF_WHITELIST` | Hosts/IPs autorizados para CSRF (admin UI/REST). |
| `GEOSERVER_XSTREAM_WHITELIST` | Clases Java extra permitidas en deserializacion XStream. |
| `HTTP_SCHEME`, `PROXY_HOST`, `PROXY_PORT`, `TOMCAT_SECURE` | Inyectados en `server.xml` para que Tomcat sepa que esta tras un reverse proxy. |
| `ENABLE_JSONP`, `MAX_FILTER_RULES`, `OPTIMIZE_LINE_WIDTH` | Toggles de kartoza. |
| `JAVA_OPTS` | Flags JVM. Ver seccion de tuning. |
| `POSTGIS_*` | Coordenadas y credenciales del PostGIS. `POSTGIS_SSLMODE=allow` por default. |

`server.xml` y `config/global.xml` se regeneran con `envsubst` en cada `make up`/`make build` (target `generate-config`). El `entrypoint-wrapper.sh` los aplica al arranque del contenedor y escribe ademas un `ontoy.json` con `{version, service, released_at}` en `/usr/local/tomcat/webapps/ROOT/`.

---

## Datastores y workspaces

Los workspaces se crean inicialmente desde la UI de GeoServer (o restaurando un backup). Una vez creados, `scripts/init-datastores.sh` los **reapunta** al PostGIS configurado en `.env` cada vez que se ejecuta `make up`, `make restore`, o `make init-datastores`.

Flujo del script:
1. Espera a que la web y el REST de GeoServer respondan 200.
2. Verifica que las credenciales del `.env` sean aceptadas (reintento 60s).
3. Lista workspaces; para cada uno, lista datastores.
4. Para cada datastore, hace `PUT` (si existe) o `POST` (si no) con un payload JSON que define conexion PostGIS con pool tuned:
   - `max connections=50`, `min=5`, timeout `20s`, validate idle, evictor cada 5min.
   - `Loose bbox=true`, `Estimated extends=true` para acelerar BBOX requests.
   - `prepare statements=true`.
5. El schema PostGIS por default es el nombre del workspace, salvo overrides en `SCHEMA_MAP` (actualmente solo `general` → `mapa_base`).

Workspaces conocidos en el ecosistema (referencias desde mapalab):
- `raster` — capas raster (mosaicos mensuales, anuales). Time dimension habilitada en algunas (`raster:temperaturas`, `raster:precipitacion`, etc.).
- `recursos` — capas vectoriales tematicas.
- `general` — capa base, schema `mapa_base`.
- Otros workspaces tematicos (economia, demografia, etc.) segun crecimiento.

Para agregar un datastore nuevo: crearlo en la UI primero, despues `make init-datastores` o `make restore` para reaplicar la config.

---

## ControlFlow — limites de concurrencia

`geoserver_data/controlflow.properties` define los limites del plugin Control Flow (incluido en kartoza):

```
timeout=60                      # Request timeout global
ows.global=100                  # Max OWS concurrentes
ows.wms.getmap=10               # Max GetMap concurrentes globalmente
ows.wfs.getfeature.application/msexcel=4
user=6                          # Max requests concurrentes por usuario
ows.gwc=16                      # Max GWC concurrentes
user.ows.wps.execute=1000/d;30s
user.ows.wms.getmap=30/s        # Rate limit GetMap por usuario
ip=10                           # Max requests concurrentes por IP
```

Estos limites son la **segunda linea de defensa** despues del rate limit de nginx en gateway-hub (`zone=geoserver_download rate=10r/s burst=10`). El primer cuello suele ser nginx; cuando un cliente lo evade (referer/UA legitimo + IPs distintas), ControlFlow lo agarra.

`ows.wms.getmap=10` significa que **solo 10 GetMap se renderizan en paralelo**. Esto, combinado con `proxy_cache_lock` de nginx (30s tras 1.24.11), serializa el primer render por tile y libera HIT al resto.

---

## GeoWebCache (GWC)

`geoserver_data/gwc-gs.xml` configura GWC bundled:

| Setting | Valor | Comentario |
|---|---|---|
| `directWMSIntegrationEnabled` | true | GetMap WMS con BBOX alineada a tile se sirve desde GWC |
| `requireTiledParameter` | true | Solo cachea si la request trae `tiled=true` |
| `WMSCEnabled` / `TMSEnabled` | true | Servicios alternativos habilitados |
| `cacheLayersByDefault` | true | Nuevas capas se cachean por default en GWC |
| `metaTilingX`, `metaTilingY` | 4×4 | Cada render produce 16 tiles a la vez (eficiente) |
| `defaultCachingGridSetIds` | WebMercatorQuad, EPSG:4326, WebMercatorQuadx2, EPSG:900913 | Grids por default |
| `defaultCoverageCacheFormats` | image/png, image/jpeg | Para rasters |
| `defaultVectorCacheFormats` | mvt, png, jpeg | Para vectoriales |

**Limitacion practica**: el frontend de mapalab usa `ImageWMS` con BBOX/WIDTH/HEIGHT del viewport del usuario, **no alineados a grid de GWC**. `requireTiledParameter=true` + `tiled=false` (default OL) hace que GWC **no intercepte** las requests del visor. El cache que realmente acelera el visor es el de nginx en gateway-hub, no GWC.

GWC sigue util para:
- Clientes externos que consumen WMTS/TMS directo.
- Warm-up indirecto: rendear via GWC calienta GeoServer (page cache de rasters, JIT, datastore pool).
- Futuro: si en algun momento migramos a `TileWMS` en mapalab, GWC ya estaria listo.

---

## Cache layers — todas las capas combinadas

```
mapalab ImageWMS ──► nginx (gateway-hub) ──► GeoServer ──► PostGIS / raster files
                     [proxy_cache 6h]        [GWC opcional, no usado por ImageWMS]
                                             [JAI cache, mem 50%]
                                             [datastore pool]
                                                      └──► [page cache kernel]
```

Capa por capa:

| Capa | TTL | Cache hit? | Comentario |
|---|---|---|---|
| nginx gateway `geoserver_cache` | 6h | Si por `$request_uri` exacto | El cache mas efectivo para WMS GetMap. Llave es URL completa, incluye BBOX/TIME/STYLES/CQL_FILTER. Cache miss en pan/zoom. |
| GWC en GeoServer | persistente | No con ImageWMS (BBOX no alinea) | Solo activo si cliente manda `tiled=true` y BBOX alineada. |
| JAI tile cache (GeoServer) | runtime | Si para operaciones intermedias | Configurado en `global.xml.template` con `memoryCapacity=0.5` (50% del heap). Acelera reproyecciones y operaciones raster compuestas. |
| Datastore connection pool | runtime | Conexiones reutilizadas | `max=50`, `min=5`, validate idle. Definido en `init-datastores.sh`. |
| Page cache kernel (OS) | runtime | Si para reads de rasters | El kernel cachea bloques de los GeoTIFFs en `geoserver_data/geoserver-raster/`. Por eso conviene heap moderado y dejar RAM libre para el OS. |

**Invalidacion del cache nginx**: hoy es solo por TTL (6h) o `inactive=12h`, y purga manual via `rm /var/cache/nginx/geoserver/*`. No hay invalidacion reactiva cuando se edita una geometria via mariachi. Riesgo asumido; ver `gateway-hub/docs/CHANGELOG.md` 1.24.11.

---

## Servicios WMS / WFS / WCS — config relevante

`config/wms.xml`:
- Versiones expuestas: 1.1.1, 1.3.0.
- `citeCompliant=false` (compatibilidad con clientes laxos).
- `interpolation=Nearest` (default para raster discreto).
- `getFeatureInfoMimeTypeCheckingEnabled=false` y `getMapMimeTypeCheckingEnabled=false` (permisivo).
- `dynamicStylingDisabled=false` (permite SLD inline).
- `featuresReprojectionDisabled=false` (reproyecta on-the-fly).
- `maxBuffer=0`, `maxRequestMemory=0`, `maxRenderingTime=0` (sin tope: el limite real lo pone ControlFlow + JVM heap).
- `cacheConfiguration.enabled=false` — el cache WMS interno de GeoServer (legacy) esta apagado a favor del cache de nginx.

`config/wfs.xml`:
- Versiones: 1.0.0, 1.1.0, 2.0.0.
- `SHAPE-ZIP_DEFAULT_PRJ_IS_ESRI=false`.
- `maxNumberOfFeaturesForPreview=0` (sin tope para preview).

`global.xml.template`:
- JAI con `memoryCapacity=0.5` (50 % del heap para tiles) y `tileThreads=7`.
- `coverageAccess.maxPoolSize=5`, `corePoolSize=5` — pool de readers raster.
- `resourceErrorHandling=SKIP_MISCONFIGURED_LAYERS` — si una capa rompe la config, se ignora en vez de tumbar el arranque.
- `featureTypeCacheSize=0` (sin limite explicito).
- `xmlExternalEntitiesEnabled=false` (seguridad).

---

## Plugins

`plugins/` se monta a `/opt/geoserver/webapps/geoserver/WEB-INF/lib/` (classpath de Tomcat). JARs presentes:

- `gs-geopkg-output-core-2.27.0.jar`
- `gs-geopkg-output-wfs-2.27.0.jar`
- `gs-geopkg-output-wms-2.27.0.jar`

Habilitan `OUTPUTFORMAT=application/geopackage` en WFS GetFeature y WMS GetMap. Permite descargar capas en `.gpkg` (formato espacial moderno, soportado en QGIS y GDAL).

Para agregar un plugin nuevo: bajar el JAR oficial de la version 2.27.0 que matchee, ponerlo en `plugins/`, `make build`. La imagen kartoza ya trae `monitor`, `control-flow`, `csp`, `inspire`, `wps`, `gwc`, entre otros — no requiere instalacion manual.

---

## Redes Docker

`docker-compose.yml` conecta el contenedor `geoserver` a tres redes:

| Red | Tipo | Para que |
|---|---|---|
| `geonetwork` | bridge interna del proyecto | Aislamiento del propio compose (no se usa para nada externo aun) |
| `dataengine-network` | external | Acceso a `dataengine-primary` (PostGIS) |
| `iieg-network` | external | Acceso a `acervo-minio` para SLDs con `<ExternalGraphic>` (desde 1.18.0) y a `gateway-hub-nginx` para fluir requests externos |

El `Makefile` hace `docker network inspect ... || docker network create dataengine-network` antes de levantar para evitar fallar si la red no existe. `iieg-network` se asume preexistente.

---

## Operacion (Makefile)

| Target | Que hace |
|---|---|
| `make up` | `generate-config` → `docker compose up -d` → espera a /web/ → setea charset UTF-8 via REST → `optimize-cultivos.py` → `init-datastores.sh` |
| `make build` | Igual que up pero con `--force-recreate --build` |
| `make down` / `restart` / `logs` | Compose passthrough |
| `make backup` | Detiene? No, **no** detiene. Limpia `.tmp`, extrae data_dir del contenedor a staging, copia plugins, comprime con `tar -czf`. Genera `backups/geoserver_data_YYYYMMDD_HHMMSS.tar.gz`. |
| `make restore` | Detiene contenedor, borra data_dir y plugins, descomprime el backup mas reciente (o `RESTORE_FILE=...`), genera config desde .env, levanta, ejecuta `reset-admin.sh` + `init-datastores.sh` + `optimize-cultivos.py` |
| `make init-datastores` | Solo el script de reapuntar datastores; util cuando cambias IP/credenciales de PostGIS |
| `make clean` | Con confirmacion `s/N`: down + `rm -rf geoserver_data/`. Destructivo. |

`make up` y `make restore` esperan hasta 2 minutos (24 intentos × 5s) a que GeoServer responda en `/web/`. Si no responde, abortan con los ultimos 20 logs.

**Backups grandes**: el `geoserver_data/geoserver-raster/` puede ocupar varios GB. `make backup` comprime con `tar -czf` un punto por cada 1000 archivos como heartbeat visual.

---

## Despliegue en host nuevo

Pasos resumidos (detalle en `README.md`):

```bash
git clone <repo> && cd geoserver
cp .env.example .env
# Editar .env: credenciales, PROXY_HOST, POSTGIS_*, JAVA_OPTS segun host
# Para servidor dedicado: bumpear heap a 8g segun tabla de tuning

# Copiar backup del servidor anterior (opcional pero recomendado)
scp usuario@servidor-anterior:/IIEG/geoserver/backups/geoserver_data_*.tar.gz backups/

make restore   # Si hay backup
# o
make up        # Si bootstrap limpio
```

Tras el restore, validar:
1. `docker logs geoserver --tail 50` — sin errores fatales
2. `curl -u admin:pwd http://localhost:8080/geoserver/rest/workspaces.json` — lista workspaces
3. `docker exec geoserver jstat -gcutil 1` — Old gen y Metaspace estables <90 %

---

## Errores frecuentes documentados

### `pg_hba.conf rejects connection ... no encryption`

PostgreSQL exige cifrado en la IP de origen. Solucion: `POSTGIS_SSLMODE=allow` (o `prefer`/`require`) en `.env`, despues `make init-datastores`. El script reaplica los datastores con sslmode actualizado. Detalle completo en `README.md`.

### `OOM: Metaspace` (latente)

Antes de 1.19.0 la JVM corria con defaults sin caps explicitos. Sintoma observado en staging: Metaspace al 99.32 %. Si vuelve a ocurrir, validar que el `.env` del host tenga `-XX:MaxMetaspaceSize=...` en `JAVA_OPTS`.

### GeoServer no inicia post-restore — credenciales

Si tras un restore las credenciales del `.env` no son aceptadas (`401` en REST), `init-datastores.sh` reintenta 12 veces antes de abortar. La causa suele ser que el hash en `users.xml` del backup no matchea el password actual del `.env`. `make restore` ya ejecuta `reset-admin.sh` automaticamente para corregirlo.

### `host not found in upstream "acervo-minio:9000"`

GeoServer no esta conectado a `iieg-network`. Verificar `docker network connect iieg-network geoserver` o que `docker-compose.yml` la incluya en `networks:` del servicio. Necesario para `<ExternalGraphic>` con URLs de Acervo.

---

## Versionado y CHANGELOG

`VERSION` + `docs/CHANGELOG.md` siguen Keep a Changelog + SemVer. El entrypoint-wrapper publica `version.json` (similar al `ontoy.json` que usa todo el ecosistema IIEG para `/ontoy` endpoints) leyendo de `VERSION` + el ultimo timestamp del CHANGELOG.

Convencion de bumps: una caracteristica por commit, version subida en el mismo commit. Ver historial reciente para el estilo.

---

## Referencias cruzadas

- `gateway-hub/docs/recursos-servidores.md` — Inventario hardware + tabla de tuning JVM por entorno.
- `gateway-hub/docs/rendimiento.md` — Stress test, rate limiting, capacidad estimada.
- `dataengine/docs/context.md` — PostGIS, schemas, particionamiento de tablas espaciales.
- `mariachi/api/app/api/routes/geoserver.py` — Cliente REST que sincroniza workspaces editables.
- `mapalab/MEMORY.md` y `mapalab/docs/context.md` — Como el visor consume WMS, loop temporal, capas raster.
