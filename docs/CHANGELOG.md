# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

## [1.31.0] - 2026-07-30

### Cambiado: Makefile homologado con el resto del ecosistema

La interfaz de comandos es ahora la misma en los nueve repos: `up` levanta desarrollo sin
reconstruir y `deploy` hace produccion completa (`git pull` + `down` + `build` + `up`). Se
retiraron todas las banderas: el entorno se detecta por el nombre de proyecto de Compose y lo que
antes era un argumento ahora es un selector interactivo. Lo transversal vive en `make/common.mk` y
`make/lib.sh`, copiados en cada repo. Convencion completa en `ecosistema/makefiles.md` del repo de
contexto.

Las reglas se partieron en `make/init.mk` y `make/backup.mk`.

### Corregido: el bucle de espera de `build` estaba roto

Escribia `attempts=$((attempts+1))` y `$attempts` sin escapar, asi que **Make los expandia como
variables propias vacias** y la receta llegaba al shell como `attempts=` y `if [ ttempts -ge ax ]`.
El health-check nunca esperaba de verdad. El mismo bucle en `up` si escapaba con `$$`. Ahora vive
una sola vez en `wait_geoserver`, en `make/repo.sh`, y no pasa por la interpolacion de Make.

### Eliminado: `version-json`

El `/ontoy` lee la version de `VERSION`, ya montado en el sidecar. Se retiraron el target, el mount
de `version.json` y la carpeta `version-api/html`.

### Cambiado: `restart` ya regenera la configuracion

Antes no dependia de `generate-config`, asi que editar el `.env` y reiniciar dejaba GeoServer con
el `server.xml` viejo. Ahora `_generate-config` es prerequisito de todo lo que levanta.

## [1.30.2] - 2026-07-30

### Corregido: el `/ontoy` del sidecar no era alcanzable desde otra VM

`geoserver-version-api` no publicaba ningun puerto al host: su 8088 existia solo dentro de
`iieg-network`. En un despliegue monolito eso alcanza, porque el monitor comparte red docker con el
sidecar. **En produccion cada servicio vive en su propia VM y `iieg-network` no cruza de nodo**, asi
que `huachicol-monitor` no podia alcanzarlo y la tarjeta de GeoServer llevaba dias caida con
`[Errno 111] Connection refused`.

`Connection refused` y no timeout: el paquete llegaba al host y este respondia con RST, o sea el
camino de red ya estaba permitido y solo faltaba que algo escuchara. No hizo falta pedir apertura
de puertos.

Se replica el patron que ya usaba dataengine, el unico servicio en otra VM que siempre se monitoreo
bien.

#### Agregado

- El servicio `version-api` publica su 8088 al host mediante `VERSION_API_PORT`.
- `VERSION_API_PORT` en `.env.example`.

> **Al desplegar: agregar `VERSION_API_PORT` al `.env` de cada entorno antes del `make up`.** La
> variable se declara con `:?`, asi que el compose falla explicito si falta.

---

## [1.30.1] - 2026-07-29

### El contexto se movio al repo central

Solo documentacion; sin cambios en GeoServer ni en las capas.

#### Eliminado

- `docs/context.md`, que vive ahora en `repos/geoserver/contexto.md` del repositorio central de
  contexto (`iieg-oficial/context-ame-esta`). Los contratos con dataengine (las columnas de la capa
  de cultivos), con acervo (la simbologia de los SLDs) y con gateway-hub (el cache WMS de 6 h)
  quedaron en `ecosistema/contratos.md`.

#### Corregido

- `docs/plugins.md` enlazaba al `context.md` eliminado.

## [1.30.0] - 2026-07-23

### Cambiado: `GS_CONTROLFLOW_USER_WMS_GETMAP` de `120/s` a `600/s`

El visor de MapaLab devolvía **429** al hacer zoom rápido sobre capas servidas por tiles. El 429 lo emite control-flow, no el gateway: los rechazos llegaban con `upstream_addr` y `upstream_response_time` en el log de nginx, y `limit_req` registró **0**.

`user.ows.wms.getmap` es un rate limit por segundo y se cuenta **por cookie `GS_FLOW_CONTROL`**, así que el navegador acumula todas sus peticiones en el mismo cubo. Reproducido: 420 tiles únicos con 40 en paralelo dan **193 × 429** con la cookie fija y **0 errores** sin ella — por eso `curl` a secas no lo reproduce aunque supere el límite.

El valor `120/s` se diseñó para el modelo WMS de imagen única (1 GetMap por render, como los `2350x1499` que aparecen en los logs). Con tiles de 256 px una sola pantalla son ~70 peticiones y un zoom de varios niveles las multiplica. Con `600/s`, la misma prueba pasa a **420/420 OK**.

- Cambio efectivo en `GS_CONTROLFLOW_USER_WMS_GETMAP` de `/IIEG/geoserver/.env`, que está **gitignoreado**: el valor real no viaja en el repo y hay que aplicarlo a mano en cada entorno. Requiere recrear el contenedor.
- El resto de límites no se tocó. `ows.wms.getmap` (80) y `ip` (40) son de concurrencia: encolan, no devuelven 429.
- Mitigación complementaria en gateway-hub 1.32.0 (caché de tiles WMS) y mapalab 1.85.0 (relieve por GWC). Contexto completo en `mapalab/docs/render_layers.md`.

## [1.29.1] - 2026-07-16

### Refactor: eliminar defaults inline del compose

Sin cambios de runtime del servicio.

#### Cambiado

- **`docker-compose.yml`**: eliminados los defaults inline `${VAR:-valor}`. `INITIAL_MEMORY` y `MAXIMUM_MEMORY` pasan a obligatorios (`${VAR:?}`, ya presentes en `.env.example`); `ADDITIONAL_JAVA_STARTUP_OPTIONS` queda opcional.

## [1.29.0] - 2026-07-07

### `make backup`: eliminados los parches de permisos (raíz atacada vía root en contenedor)

Los dos guards `PENDIENTE` que `1.22.1` agregó al target `backup` (un `chmod u+rx` dentro del contenedor antes del `tar` y un `chmod -R u+rwX` sobre `.backup_staging` antes del `rm -rf`) dependían de los permisos del usuario del host (uid 1000): si el contenedor generaba un directorio sin bit `x` para el dueño, tanto la lectura como la limpieza tronaban, y por eso hacían falta los parches.

Al revisar la causa raíz: la imagen `kartoza/geoserver:2.27.0` corre la JVM con `umask 0027` (forzado por el `SecurityListener` de Tomcat, `-Dorg.apache.catalina.security.SecurityListener.UMASK=0027`), así que los directorios nacen `0750` — **con** bit `x`. El entrypoint de kartoza tampoco hace `chmod` sobre `data_dir` (solo `chown -R`). El `drw-r--r--` que motivó `1.22.1` no se reproduce con esa config; era cicatriz histórica. Bajar el umask a `0022` (el "fix" que planteaban los `PENDIENTE`) sería contraproducente: el `SecurityListener` impone `0027` como hardening y aflojarlo puede impedir el arranque.

En vez de parchar permisos, el backup ya no depende del usuario del host: todas las lecturas del contenedor y todas las limpiezas de staging corren como root.

#### Cambiado

- **`Makefile` (target `backup`)**:
  - Las operaciones dentro del contenedor (`find ... -delete` de `.tmp` y `tar -cf -` de `data_dir`) ahora usan `docker exec -u root`. Root ignora los bits de permiso, así que el `tar` nunca falla con `Cannot stat: Permission denied` sin importar el modo de los directorios → elimina el primer `PENDIENTE` de raíz.
  - La limpieza de `.backup_staging` (antes y después de comprimir) usa `docker run --rm -v $(CURDIR):/data alpine rm -rf`, el mismo patrón que ya usan `restore` y `clean`. Al correr como root borra cualquier modo sin el `chmod` previo → elimina el segundo `PENDIENTE` de raíz.

#### Notas

- Si en algún momento reaparecieran directorios sin bit `x` en `data_dir`, sería síntoma de un problema de umask a corregir en la imagen/entrypoint, no algo a parchar de nuevo en el backup.

## [1.28.0] - 2026-06-30

### `economia:cultivos`: campo `clave_municipio` para filtro por municipio + caché de tiles

mapalab filtra la "Vista por municipio" con un CQL sobre un campo de la capa. La vista SQL de cultivos no exponía la columna `clave_municipio` (agregada en dataengine 1.23.0), así que el filtro tronaba con `Illegal property name`. Se agrega al SELECT.

#### Cambiado

- **`scripts/init-cultivos-layer.sh`**: la vista SQL ahora selecciona `clave_municipio` además de `fid, muestra, prediccion, geom_3857`, para que GeoServer la exponga y mapalab pueda filtrar `clave_municipio IN (...)`.

#### Notas operativas (per-host, GWC — replicar en producción)

- `economia:cultivos` se sirve por tiles. Para cachear las variantes filtradas por `prediccion` (y municipio) se agregó un `regexParameterFilter` de `CQL_FILTER` a la capa en GWC (sin él, GWC devuelve `no parameter filter exists for CQL_FILTER` y nunca cachea).
- Los mapas base `raster:hillshade_iieg_cog` y `raster:hillshade_inegi_cog` estaban como "not a tile layer" (MISS siempre); se habilitaron como tile layers en GWC y se sembraron (zooms 6-13). Estas configuraciones viven en `geoserver_data/gwc-layers/` (per-host).

## [1.27.0] - 2026-06-29

### Optimización de `economia.cultivos` movida a dataengine (migración Alembic)

El script `scripts/optimize-cultivos.py` se conectaba a PostGIS via `docker exec dataengine-primary`, lo que asume que el contenedor de la base corre en el mismo host que GeoServer. Es cierto en staging, pero **falso en producción** (PostGIS vive en un servidor dedicado): el `docker inspect` fallaba, el script registraba "el contenedor no está corriendo" y se omitía silenciosamente. La optimización nunca corría donde más importaba, y además reconstruía el índice + `CLUSTER` (lock `ACCESS EXCLUSIVE`) en **cada** arranque.

La optimización es 100% una operación de base de datos sobre una tabla que pertenece a dataengine. Se reubica allí como migración Alembic (`0020_cultivos_spatial_index`), que corre una sola vez junto a PostGIS en ambos entornos y queda versionada/auditada como el resto del schema.

#### Agregado

- **`scripts/init-cultivos-layer.sh`** (nuevo, versionado): republica `economia:cultivos` como vista SQL (virtual table) sobre la columna `geom_3857`, sirviéndola nativa en EPSG:3857. mapalab renderiza en 3857 y su `ImageWMS` pide cada GetMap en 3857, mientras la geom original está en 6368: GeoServer reproyectaba on-the-fly en cada request. Con la capa nativa en 3857 esa reproyección desaparece. Mantiene el nombre de la capa (mapalab no cambia) y el SLD sigue usando la geometría por defecto. Idempotente: si ya está en 3857 hace skip; con `--force` reaplica. Defensivo: si la capa no existe o la columna `geom_3857` aún no fue provisionada (migración 0022 de dataengine), avisa y no rompe el bootstrap. La columna `geom_3857` la crea dataengine (`20260629_0022_cultivos_geom_3857`).
- **`Makefile`**: target `init-cultivos-layer` (acepta `FORCE=--force`) y llamada en los flujos `up` y `restore`, tras `init-datastores`.

#### Eliminado

- **`scripts/optimize-cultivos.py`** y **`docs/readme_optimize_cultivos.md`**: la lógica vive ahora en `dataengine/jobs/alembic/versions/20260629_0020_cultivos_spatial_index.py`.
- **`Makefile`**: se quita la invocación `python3 scripts/optimize-cultivos.py` de los flujos `up` y `restore`.

## [1.26.0] - 2026-06-15

### Gridset `Jalisco_ITRF2008_13N` (EPSG:6368) via REST de GeoWebCache

La página web de creación de gridsets de GeoServer 2.27.0 tiene un bug: el popup "Find" del selector de SRS entrega el código ya prefijado (`EPSG:6368`) y la página le antepone otro `EPSG:`, produciendo `EPSG:EPSG:6368`. El decode falla, el CRS queda `null` y la página revienta con `NullPointerException` en `AbstractGridSetPage$GridSetCRSPanel.onCodeClicked`. Afecta a cualquier código elegido desde "Find", no solo al 6368 (reportado upstream en el foro OSGeo, sept. 2024).

Para crear gridsets de forma reproducible y a prueba de ese bug, se provisionan ahora por la REST de GeoWebCache en el bootstrap, en vez de la UI.

#### Agregado

- **`scripts/init-gridsets.sh`** (nuevo, versionado): crea/actualiza el gridset `Jalisco_ITRF2008_13N` via `PUT /gwc/rest/gridsets/{name}`. EPSG:6368 (México ITRF2008 / UTM zona 13N), partiendo de los bounds proyectados oficiales del CRS según epsg.io/6368 (`-1396865.12, 1337614.43, 2759543.0, 3809957.21`). El script **cuadra el extent** (extiende el lado corto desde la esquina inferior-izquierda) para que la malla sea cuadrada (`matrixWidth == matrixHeight == 2^L`) y el origen top-left sea constante en todos los niveles — requisito para que clientes WMTS/vector-tile (OpenLayers) aligneen sin distorsión, igual que los gridsets nativos `WebMercatorQuad`. Tiles 256×256, 18 niveles (resolución base 16235.97 m/px, hasta ~0.12 m/px). Idempotente: si existe hace skip; con `--force` **borra y recrea** (actualizar en sitio un gridset en uso corrompe el extent en GWC). Resoluciones calculadas en Python.
- **`Makefile`**: target `init-gridsets` (acepta `FORCE=--force`) y llamada en los flujos `up` y `restore`, tras `init-datastores`.

#### Notas

- Para que una capa servida en este gridset no devuelva `400 TileOutOfRange` en zonas sin datos (que aborta el render en OpenLayers), su `gridSubset` debe cubrir **todo el extent del gridset**, no solo el bbox de la capa: así los tiles vacíos devuelven `200` (MVT vacío) en vez de `400`. Esto se setea en la config GWC de la capa (`PUT /gwc/rest/layers/{layer}.xml`), vive en `geoserver_data/gwc-layers/` (per-host, no versionado).
- Modificar parámetros después: editar las constantes en `scripts/init-gridsets.sh` y correr `make init-gridsets FORCE=--force` (borra y recrea). Tras cambiar el gridset hay que **truncar el caché** (`POST /gwc/rest/masstruncate`) y, si una capa lo referenciaba, **recomputar su `gridSubset`** (al cambiar el extent del gridset la cobertura de la capa queda obsoleta y apunta a coordenadas del grid viejo).

## [1.25.0] - 2026-05-26

### `controlflow.properties` como template versionado parametrizado por `.env`

Los límites de concurrencia del plugin Control-flow se gestionaban editando directamente `geoserver_data/controlflow.properties`, archivo que vive en el volumen mounted y NO está versionado (está en `.gitignore`). Cualquier cambio se perdía si alguien recreaba el volumen y no había trazabilidad de las versiones de límites por entorno.

Adicionalmente, para soportar el modo "Vista por municipio" del visor (mapalab 1.50.0) que dispara varias requests WMS concurrentes al cambiar de municipio, se subieron los límites desde el default conservador (`user=6`, `ows.wms.getmap=10`) a valores más permisivos (`user=40`, `ows.wms.getmap=80`).

#### Agregado

- **`config/controlflow.properties.template`** (nuevo, versionado): template con placeholders `${GS_CONTROLFLOW_*}` para cada límite. Generado por `entrypoint-wrapper.sh` en cada arranque del contenedor.
- **`scripts/entrypoint-wrapper.sh`**: nuevo `sed` que sustituye las 9 variables de control-flow y escribe el archivo final a `/opt/geoserver/data_dir/controlflow.properties`. Sigue el mismo patrón de los templates ya existentes (`server.xml.template`, `global.xml.template`).
- **`docker-compose.yml`**: nuevas 9 env vars en el bloque `environment` del servicio `geoserver` (`GS_CONTROLFLOW_TIMEOUT`, `GS_CONTROLFLOW_OWS_GLOBAL`, `GS_CONTROLFLOW_OWS_WMS_GETMAP`, `GS_CONTROLFLOW_OWS_WFS_MSEXCEL`, `GS_CONTROLFLOW_OWS_GWC`, `GS_CONTROLFLOW_USER`, `GS_CONTROLFLOW_USER_WPS_EXECUTE`, `GS_CONTROLFLOW_USER_WMS_GETMAP`, `GS_CONTROLFLOW_IP`) + mount del template como `:ro`.
- **`.env.example`** y `.env`: valores por defecto (más permisivos que el default histórico de Control-flow):
  - `GS_CONTROLFLOW_OWS_GLOBAL=200` (antes 100)
  - `GS_CONTROLFLOW_OWS_WMS_GETMAP=80` (antes 10)
  - `GS_CONTROLFLOW_USER=40` (antes 6)
  - `GS_CONTROLFLOW_IP=40` (antes 10)
  - `GS_CONTROLFLOW_USER_WMS_GETMAP=120/s` (antes 30/s)
  - El resto (`timeout`, `ows.gwc`, `ows.wfs.getfeature.application/msexcel`, `user.ows.wps.execute`) sin cambio.

#### Notas operativas

- GeoServer Control-flow recarga el archivo automáticamente cuando cambia su mtime (default ~5s), sin restart del contenedor. Útil para ajustar límites en caliente: editar `data_dir/controlflow.properties` directamente (efímero, se sobrescribe en próximo restart) o modificar las env vars y reiniciar.
- Cuando todas las capas críticas del visor tengan `clave_municipio`/`municipio_field` configurado en `mapalab.layers` (plan en `mapalab/docs/planes/PLAN_CLAVE_MUNICIPIO_EN_TABLAS.md`), las URLs serán naturalmente cortas y los límites podrán volver a valores más conservadores.

## [1.24.2] - 2026-05-22

### Fallback a `python3` cuando `unzip` no está instalado

El host GCP staging no tiene `unzip` instalado, por lo que `make plugins-fetch` (introducido en 1.24.0) no podía extraer los JARs descargados (`scripts/fetch-plugins.sh: line 58: unzip: command not found`). Aunque desde 1.24.1 esto ya no abortaba el orquestador del ecosistema, los plugins igual no se instalaban en GCP.

#### Cambiado

- **`scripts/fetch-plugins.sh`**: nueva función `extract_jar_from_zip` que intenta primero con `unzip` (rápido, formato nativo) y si no está disponible cae automáticamente a un snippet inline de `python3 -c "import zipfile..."`. Python3 ya es una dependencia hard del repo (`scripts/optimize-cultivos.py`), así que el fallback no agrega nuevas dependencias. Soporta JARs ubicados en cualquier subdirectorio dentro del zip (busca por `basename`).

#### Notas operativas

- En hosts con `unzip` (la mayoría de Debian/Ubuntu por default): comportamiento idéntico a antes.
- En hosts sin `unzip` (GCP staging): se usa Python3 transparentemente. Se prueba en CI/local removiendo `unzip` del PATH y validando que los JARs se extraen igual.
- Si ninguno de los dos está disponible, el script emite `[warn] ni 'unzip' ni 'python3' estan disponibles para extraer JARs` y termina con `exit 0` (sin abortar el orquestador, gracias a 1.24.1).

## [1.24.1] - 2026-05-22

### `plugins-fetch` no aborta el flujo cuando una extension falla

En el primer despliegue de `1.24.0` en GCP staging, `make plugins-fetch` falló (`no se pudo extraer gs-wps-download-2.27.0.jar del zip`) y como el script terminaba con `exit 1`, el orquestador del ecosistema (`gateway-hub` `make ecosystem-up`) abortó completo en el paso `[4/8] geoserver`, dejando los servicios siguientes sin levantar. Además el mensaje no decía **por qué** falló `unzip` (stderr silenciado con `>/dev/null 2>&1`).

#### Cambiado

- **`scripts/fetch-plugins.sh`**:
  - **No fatal**: si una extension falla descargando o extrayendo, el script imprime un `[warn]` y un resumen final claro (`AVISO: las siguientes extensions no se pudieron instalar: ...`) pero termina con `exit 0`. GeoServer arranca igual, simplemente sin los procesos/outputs de las extensions fallidas.
  - **Diagnóstico real**: el stderr de `unzip` y `curl` ya no se silencia. Si `unzip` reporta `cannot create extraction directory` o `bad CRC`, el mensaje aparece indentado debajo del `[warn]`.
  - **Validación de zip truncado**: antes de invocar `unzip`, se chequea que el zip descargado pese al menos 1024 bytes. Detecta el caso típico donde `curl -fsSL` no marca error pero el cuerpo es un HTML de redirect/login en vez del binario.
  - **Resumen final**: imprime conteo `X instalado(s), Y ya presente(s), Z con error` para facilitar diagnóstico en logs de CI/orquestadores.
  - Cambiado `set -euo pipefail` por `set -uo pipefail` (sin `-e`) para permitir el flujo no-fatal sin abortes implícitos.

#### Notas operativas

- Tras este cambio, una falla de SourceForge u otro problema transient en un solo host **no detiene** el resto del ecosistema. Re-ejecutar `make plugins-fetch` cuando el problema se resuelva basta para recuperar.
- El aviso final va a **stderr**, así que sigue siendo visible en logs sin contaminar stdout.

## [1.24.0] - 2026-05-22

### Auto-fetch idempotente de plugins en `make up`

`plugins/` está gitignored, por lo que un `git clone` limpio no traía los JARs declarados como bind mounts en `docker-compose.yml`. Hasta ahora la única forma de tenerlos en un host nuevo era restaurar un `tar.gz` de backup; sin él, Docker creaba directorios vacíos en lugar de los JARs y GeoServer arrancaba silenciosamente sin las extensiones (geopkg-output, wps-download).

#### Agregado

- **`scripts/fetch-plugins.sh`** (nuevo): script idempotente que descarga las extensiones declaradas en su manifiesto inline (`PLUGINS=(...)`). Para cada extension valida si todos los JARs esperados están presentes en `plugins/`; si falta al menos uno, baja el zip oficial de `sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/`, extrae **solo** los JARs declarados (no licencias ni README) y los coloca en `plugins/`. JARs ya presentes no se sobreescriben. Manifest inicial cubre `geopkg-output` y `wps-download` (6 JARs en total, ~2.3 MB).

#### Cambiado

- **`Makefile`**: nuevo target `plugins-fetch` que invoca el script. Encadenado como prerequisito de los targets `up` y `build`, de forma que cualquier despliegue limpio descarga los plugins faltantes antes del `docker compose up`. Agregado también al `help`.
- **`docs/plugins.md`**: nueva sección `## Auto-fetch en bootstrap` explicando el flujo. Sección `## Como agregar un plugin nuevo` reescrita en 7 pasos para reflejar el flujo via manifest (no manual). Sección `## Backup y restore` actualizada para listar los dos caminos de persistencia (backup vs auto-fetch).

#### Notas operativas

- **Idempotencia**: ejecuciones repetidas con todos los JARs presentes imprimen `[skip] <nombre>: N JAR(s) ya presentes` y no tocan disco.
- **Recuperación selectiva**: borrar un JAR individual y re-ejecutar `make plugins-fetch` descarga solo lo faltante.
- **Dependencia**: SourceForge debe estar accesible la primera vez. En entornos sin red, el camino via `make restore` desde un `tar.gz` sigue siendo válido.
- **Para agregar un plugin nuevo**: editar el array `PLUGINS=(...)` en `scripts/fetch-plugins.sh`, agregar bind mounts en `docker-compose.yml`, `make build`. Detalle paso a paso en `docs/plugins.md`.

## [1.23.0] - 2026-05-22

### Habilitar extension WPS Download

Se monta la extension oficial `wps-download` (GeoServer 2.27.0) en el classpath del contenedor. La imagen `kartoza/geoserver:2.27.0` trae el WPS base (~194 procesos: vector, raster, geometry) pero **no** trae el plugin de descarga, que es el que permite exportar resultados de procesos como archivos descargables grandes vía `gs:Download` y `gs:DownloadEstimator` con soporte sync/async.

#### Agregado

- **`plugins/gs-wps-download-2.27.0.jar`**, **`plugins/jcodec-0.2.3.jar`**, **`plugins/jcodec-javase-0.2.3.jar`**: extraídos del zip oficial `geoserver-2.27.0-wps-download-plugin.zip` del SourceForge de GeoServer. `jcodec` es dependencia transitiva (soporta export a MP4 vía `gs:DownloadAnimation`).
- **`docker-compose.yml`**: tres bind mounts `:ro` adicionales al servicio `geoserver` mapeando los JARs anteriores a `/usr/local/tomcat/webapps/geoserver/WEB-INF/lib/`.
- **`docs/plugins.md`** (nuevo): catálogo completo de extensiones disponibles, dividido en (1) bundled en la imagen kartoza, (2) bind-mounted desde `plugins/`, (3) recomendados a futuro para el ecosistema IIEG. Incluye el procedimiento manual para agregar plugins nuevos y reglas sobre versionado, duplicados y dependencias transitivas.

#### Cambiado

- **`docs/context.md`** sección `## Plugins`: acortada, ahora apunta a `plugins.md` para el detalle. Menciona explícitamente el plugin `wps-download` recién instalado y las extensiones bundled (WPS base, monitor, control-flow, gwc, etc.) sin duplicar el inventario.

#### Notas operativas

- WPS aporta 4 procesos nuevos al `GetCapabilities`: `gs:Download`, `gs:DownloadEstimator`, `gs:DownloadMap`, `gs:DownloadAnimation`. Total: 198 procesos.
- Sin caps explícitos de tamaño/features. Si en algún momento conviene acotarlos, crear `geoserver_data/wps-download.xml` con `<maxFeatures>`, `<rasterSizeLimits>`, etc.
- Las descargas async respetan el límite global `user.ows.wps.execute=1000/d;30s` ya definido en `controlflow.properties`.
- Los JARs viven en `plugins/` (gitignored). La persistencia entre hosts queda cubierta por el `tar.gz` de `make backup`/`make restore`; el clone limpio sin backup aún no descarga automáticamente — eso se resuelve en `1.24.0`.

## [1.22.1] - 2026-05-20

### `make backup` tolera directorios con permisos `drw-r--r--`

La kartoza image `2.27.0` ocasionalmente crea directorios dentro de `data_dir` con umask malo (sin bit `x` para el dueño). Esto rompía `make backup` en dos puntos:

1. **`tar -cf -` dentro del container** fallaba con `Cannot stat: Permission denied` al intentar leer esos directorios.
2. **`rm -rf .backup_staging`** en el host fallaba también si la corrida previa había extraído dirs con esos mismos permisos al staging.

#### Cambiado

- **`Makefile` (target `backup`)** agrega dos guards selectivos antes de los puntos de fallo, ambos marcados como **PENDIENTE** para remover cuando se arregle el umask del entrypoint del container:
  - `docker exec geoserver find /opt/geoserver/data_dir -type d ! -perm -u+x -exec chmod u+rx {} +` — arregla solo los directorios sin bit `x` del dueño antes del `tar`, sin tocar permisos de "other" ni archivos.
  - `chmod -R u+rwX .backup_staging 2>/dev/null || true` — destraba el staging heredado de corridas previas fallidas antes del `rm -rf`. La `X` mayúscula aplica `x` solo a directorios.

#### Notas operativas

- Ambos chmods son no-op en entornos saludables (el `find` no encuentra dirs problemáticos).
- El fix permanente (umask `0022` en `scripts/entrypoint-wrapper.sh`) queda pendiente para una iteración posterior.

## [1.22.0] - 2026-05-20

### URLChecks idempotentes provisionados en `make up`

Mariachi necesita que GeoServer permita resolver `<ExternalGraphic>` apuntando a buckets internos del Acervo (SeaweedFS) cuando rendera SLDs. GeoServer 2.20+ bloquea todas las URLs externas en SLDs si no hay `URLCheck` definido. Hasta ahora se configuraba manualmente vía `curl` post-deploy, lo que se olvidaba con cada despliegue limpio.

#### Agregado

- **`scripts/setup-urlchecks.sh`** (nuevo): script idempotente que provisiona los URLChecks vía REST API (`POST /rest/urlchecks`). Trata `HTTP 201` (creado) y `HTTP 409` (ya existe) como éxito; falla explícito en cualquier otro código. Sin output cuando todos ya existen. Define dos checks por defecto:
  - `acervo_mapalab` → `^http://acervo-seaweedfs:8333/mapalab/.+$` (catálogo de símbolos del editor SLD de mariachi-admin).
  - `acervo_iieg_leyendas` → `^http://acervo-seaweedfs:8333/iieg/leyendas/.+$` (SVGs subidos por el admin de mariachi al bucket `iieg`).

#### Cambiado

- **`Makefile`** (target `up`): se invoca `bash scripts/setup-urlchecks.sh` después de `init-datastores.sh`. Comentario marcado como **PENDIENTE** para remover cuando los URLChecks se persistan declarativamente vía `geoserver_data/` en el bootstrap de producción.

#### Notas operativas

- En despliegues nuevos (`make build` o volumen `geoserver_data` recién creado): los dos URLChecks se crean automáticamente en el primer `make up`.
- En despliegues existentes con URLChecks ya configurados: el script no hace nada (POST devuelve 409).
- Si en producción Acervo es accesible vía otro hostname/HTTPS, ampliar la lista `URLCHECKS` en el script.

## [1.21.0] - 2026-05-18

### Endpoint `/ontoy` via sidecar `version-api`

El `entrypoint-wrapper.sh` escribia el JSON en `/usr/local/tomcat/webapps/ROOT/ontoy.json`, pero esa webapp no existe en `kartoza/geoserver:2.27.0` (solo esta desplegada `webapps/geoserver/`), asi que cualquier `GET /ontoy` respondia 404. La consecuencia: `mariachi` mostraba una version hardcoded (`static_version` en `platforms_config.py`) que se desactualizaba cada release del ecosistema.

#### Agregado

- **`version-api/`**: nuevo container sidecar (`python:3.13-alpine` + `ontoy_server.py` 47 lineas stdlib, sin deps) que sirve `GET /ontoy` en puerto interno `8088`. Mismo patron que `dataengine/jobs/ontoy_server.py`.
- **`docker-compose.yml`**: servicio `version-api` conectado solo a `iieg-network`. Monta `./VERSION` y `./version-api/html/version.json` read-only. Healthcheck contra `http://127.0.0.1:8088/ontoy`.
- **`Makefile`**: target `version-json` que regenera `version-api/html/version.json` leyendo `VERSION` y la fecha de `docs/CHANGELOG.md`. Hookeado a `up`, `build` y `restart` como prerequisito.

#### Cambiado

- **`scripts/entrypoint-wrapper.sh`**: removida la generacion de `webapps/ROOT/ontoy.json` (no servia para nada). El wrapper se reduce a procesar `server.xml` y `global.xml` desde sus templates.
- **`docker-compose.yml`** (servicio `geoserver`): removidos los mounts de `./VERSION` y `./docs/CHANGELOG.md` dentro del container; el sidecar es ahora quien necesita esos archivos.

#### Notas

`gateway-hub` debe actualizarse en paralelo para que `/geoserver/ontoy` deje de responder con el hardcode `1.14.1` y haga `proxy_pass` al sidecar; `mariachi` debe eliminar el `static_version: "1.20.1"` de `geoserver` en `platforms_config.py`.

## [1.20.1] - 2026-05-15

### Corregida la metodologia de validacion JVM post-tuning

Las dos secciones de `docs/context.md` que recomendaban validar con `docker exec geoserver jstat -gcutil 1` daban una guia engañosa. La columna `M` de `gcutil` reporta `used / committed`, **no `used / max`**: muestra 99 % cuando la JVM apenas crecio Metaspace y todavia tiene mucho headroom hasta `MaxMetaspaceSize`. Tras aplicar el tuning de 1.20.0 en GCP staging y ver `M=99 %` con valores correctos (`MU=137 MB` de 512 MB cap), confirmamos que el percentage es enganoso y el chequeo real esta en los numeros absolutos.

#### Changed

- **`docs/context.md`** (seccion "JVM tuning" y subseccion de despliegue): cambiada la recomendacion a `jstat -gc 1` (sin `util`). Documentadas las columnas relevantes (`OC`/`OU`, `MC`/`MU` en KB) y el indicador clave `FGC = 0`. Explicito que `MU` muy por debajo de `MaxMetaspaceSize` con `OU < OC` con margen es la lectura sana, no el porcentaje de `gcutil`.

## [1.20.0] - 2026-05-15

### Refactor del tuning JVM: usar variables nativas de kartoza

El tuning aplicado en 1.19.0 metia `-Xms`/`-Xmx`/`-XX:+UseG1GC`/`-Dfile.encoding` directo en `JAVA_OPTS`. Eso colisionaba con el bloque `GEOSERVER_OPTS` interno de kartoza (`scripts/entrypoint.sh:55-100`), que ya define exactamente esos mismos flags y luego concatena `export JAVA_OPTS="${JAVA_OPTS} ${GEOSERVER_OPTS}"`. La doble definicion mas el parsing del concatenado produjo `Invalid maximum heap size: -Xmx2g-XX:MaxMetaspaceSize=512m` al arrancar (observado en GCP staging 2026-05-15: dos `-Xmx`, dos `-XX:+UseG1GC`, espacios perdidos en algun punto del pipeline catalina.sh).

### Cambiado

- **`docker-compose.yml`**: removida `JAVA_OPTS: ${JAVA_OPTS}` del bloque `environment`. Agregadas `INITIAL_MEMORY`, `MAXIMUM_MEMORY` y `ADDITIONAL_JAVA_STARTUP_OPTIONS` con defaults explicitos (`2G`, `4G`, vacio) — son las variables que kartoza expone para tunear heap y flags extras sin tocar `JAVA_OPTS`.
- **`.env`** (instancia con `PROXY_HOST=<host-staging>`, destino produccion S3): `INITIAL_MEMORY=2G`, `MAXIMUM_MEMORY=8G`, `ADDITIONAL_JAVA_STARTUP_OPTIONS=-XX:MaxMetaspaceSize=1g`. El `-XX:+UseG1GC` y el encoding ya los pone kartoza por default.
- **`.env.example`**: placeholders `<initial_memory>`, `<maximum_memory>`, `<additional_java_opts>` con bloque de comentario inline mostrando los valores recomendados para Local/Staging vs Produccion S3.

### Requiere paso manual post-deploy

En cada host donde tenia el `JAVA_OPTS` viejo, reemplazar:

```
JAVA_OPTS="-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Xms<X> -Xmx<Y> -XX:MaxMetaspaceSize=<Z> -XX:+UseG1GC"
```

por:

```
INITIAL_MEMORY=<X>
MAXIMUM_MEMORY=<Y>
ADDITIONAL_JAVA_STARTUP_OPTIONS=-XX:MaxMetaspaceSize=<Z>
```

y `make build` (o `docker compose up -d` con `--force-recreate`).

### Notas

- La unica flag extra que vale la pena agregar es `-XX:MaxMetaspaceSize` — kartoza no la setea y es la que dispara `OOM: Metaspace` con el tiempo. G1GC, Marlin, encoding ya estan activos por default.
- Si necesitas mas flags exoticos en el futuro (perfiling, debug, etc.), agregalos a `ADDITIONAL_JAVA_STARTUP_OPTIONS` — kartoza los append al final del comando java.

---

## [1.19.1] - 2026-05-15

### Agregado

- **`docs/context.md`**: documento de contexto del proyecto siguiendo la convencion del ecosistema (`gateway-hub`, `mapalab`, `dataengine`, etc.). Condensa: stack, integracion con mariachi/dataengine/mapalab/gateway-hub/acervo, estructura del repo, dimensionamiento por entorno (staging vs S3), tuning JVM aplicado en 1.19.0, variables de entorno, flujo de datastores (`init-datastores.sh`), limites de ControlFlow (`controlflow.properties`), configuracion de GWC y por que `ImageWMS` del visor no la aprovecha, capas de cache combinadas, plugins, redes Docker, Makefile, despliegue en host nuevo y errores frecuentes documentados. Cierra el hueco de un context.md que faltaba versus los otros repos del ecosistema.

## [1.19.0] - 2026-05-15

### Tuning de la JVM de GeoServer

Diagnostico en GCP staging mostro la JVM al limite: Old gen subiendo de 56 % a 99.85 % en 5 segundos, Metaspace al 99.32 % (a un par de class loads de un `OutOfMemoryError: Metaspace`), 16 ciclos de concurrent GC robando CPU al render. Causa raiz: la imagen `kartoza/geoserver` no setea caps explicitos de heap/Metaspace y el `JAVA_OPTS` que teniamos solo contenia flags de encoding, dejando la JVM al merced de defaults muy chicos para una carga raster real.

### Cambiado

- **`.env`** (instancia con `PROXY_HOST=<host-staging>`, destino produccion S3): `JAVA_OPTS` ampliado con `-Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g -XX:+UseG1GC`. S3 es VM dedicada 8c/15GB y solo corre el contenedor de GeoServer (1.4 GB usados hoy de 15 disponibles segun `gateway-hub/docs/recursos-servidores.md`), por lo que el heap de 8 GB queda ~50 % de la VM y deja ~7 GB para page cache del kernel donde el OS pone los GeoTIFFs.
- **`.env.example`** sustituido el placeholder `JAVA_OPTS=<>` por un valor conservador documentado (`-Xmx 2g`, apto para VM compartida tipo staging) con comentario explicando la variante aggressive para servidor dedicado. Cierra el agujero de "default invisible" que tenia el repo: cualquiera que clone y arranque desde el example obtiene caps explicitos en vez de quedar expuesto al `OOM: Metaspace`.

### Requiere paso manual post-deploy

- Reiniciar el contenedor en cada host donde aplique:
  ```
  docker compose -f /IIEG/geoserver/docker-compose.yml up -d
  ```
- En GCP staging (VM compartida 2c/8GB) el `.env` del host **no es este**; aplicar manualmente sobre ese host la version conservadora: `JAVA_OPTS="-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Xms1g -Xmx2g -XX:MaxMetaspaceSize=512m -XX:+UseG1GC"`. Si subes el heap a 8 GB en GCP comprometes a PostGIS/Mariachi (recursos compartidos).
- Validar con `docker exec geoserver jstat -gcutil 1`: Old gen y Metaspace deberian estabilizarse muy por debajo del 90 % bajo carga normal.

---

## [1.18.0] - 2026-05-13

### Agregado a `iieg-network` para alcanzar `acervo-minio` desde SLDs

Habilitacion del shape `point` con `<ExternalGraphic>` en mariachi: GeoServer ahora rendera capas de puntos que apuntan a imagenes en el bucket Acervo `mapalab/simbologia/`.

### Cambiado

- `docker-compose.yml`: el servicio `geoserver` se agrega a `iieg-network` (external), ademas de `geonetwork` y `dataengine-network`. Asi el container resuelve `acervo-minio:9000` y puede hacer fetch de PNGs/SVGs al renderizar SLDs con `<ExternalGraphic>`.

### Requiere paso manual post-deploy

GeoServer 2.20+ bloquea por defecto cualquier URL externa en SLDs cuando no hay URLChecks configurados. Tras este deploy, ejecutar **una vez** contra cada entorno:

```bash
curl -u "$GEOSERVER_ADMIN_USER:$GEOSERVER_ADMIN_PASSWORD" \
  -H 'Content-Type: application/json' -X POST \
  "$GEOSERVER_URL/rest/urlchecks" -d '{
    "regexUrlCheck": {
      "name": "acervo_mapalab",
      "description": "Acervo MinIO interno (bucket mapalab)",
      "enabled": true,
      "regex": "^http://acervo-minio:9000/mapalab/.+$"
    }
  }'
```

Sin esto, las capas de puntos con simbologia de emoji/imagen renderearan cuadrados grises (placeholder de ExternalGraphic fallido) en lugar del simbolo.

---

## [1.17.0] - 2026-05-06

### Agregado
- Target `make init-datastores` para reapuntar los datastores al PostGIS configurado en
  `.env` sin necesidad de hacer un `restore` completo.
- Verificación robusta de disponibilidad del REST API (`/rest/workspaces.json` con
  auth) además del endpoint `/web/`, evitando que el primer `PUT` se dispare antes de
  que GeoServer esté completamente caliente.
- Lógica de reintentos (3 intentos con backoff de 5s/10s) y timeout de 60s en las
  operaciones `PUT`/`POST` de datastores.

### Cambiado
- `init-datastores.sh` ya no aborta todo el script si un datastore falla: acumula los
  errores y los reporta al final con código de salida no-cero.

## [1.16.0] - 2026-05-06

### Agregado
- Sincronización automática de datastores para todos los workspaces y schemas
  detectados en GeoServer (antes era una lista fija).

### Cambiado
- Modularización de la generación del payload del datastore (`build_datastore_payload`)
  para reutilización entre creación y actualización.

## [1.15.0] - 2026-05-06

### Agregado
- Target `make build` que recrea el contenedor con los cambios del `.env`.
- Variable `TOMCAT_SECURE` configurable desde `.env` para integrar correctamente con
  reverse proxies (HTTPS terminando en el proxy).

## [1.14.2] - 2026-05-06

### Agregado
- Archivo `LICENSE` MIT en la raíz para que GitHub detecte la licencia del proyecto.

### Cambiado
- Simplificación de la sección de versionado y mantenimiento del `CHANGELOG`.

## [1.14.1] - 2026-04-22

### Cambiado
- `reset-admin.sh` ahora elimina usuarios duplicados antes de regenerar el admin.
- Manejo de timeout al verificar la disponibilidad de GeoServer durante el reset.

## [1.14.0] - 2026-03-30

### Agregado
- Reseteo automatizado de credenciales del admin de GeoServer.
- Lógica de reintentos en la inicialización de los datastores para tolerar arranques
  lentos del contenedor.

## [1.13.0] - 2026-03-26

### Agregado
- Script `optimize-cultivos` para regenerar y optimizar capas de cultivos.
- Documentación `docs/readme_optimize_cultivos.md` con el uso del script.

## [1.12.0] - 2026-03-26

### Agregado
- Integración de GeoServer con la red Docker externa `dataengine-network`.
- Optimización del pooling y parámetros de rendimiento de los datastores PostGIS.

### Cambiado
- Se garantiza que `dataengine-network` exista antes de levantar el contenedor de
  GeoServer.
- Corrección de un typo en el Makefile.

## [1.11.0] - 2026-03-25

### Agregado
- Verificación interactiva de credenciales de GeoServer ante respuestas `401` (solicita
  input al usuario para reintentar con credenciales válidas).

## [1.10.2] - 2026-03-25

### Cambiado
- Refactor del help del Makefile (split de `echo` para mejorar legibilidad).
- Alineación de las descripciones del help message del Makefile.

## [1.10.1] - 2026-03-20

### Corregido
- Escape JSON de las contraseñas de GeoServer.
- Refactor del payload del datastore para hacerlo más robusto.

## [1.10.0] - 2026-03-20

### Agregado
- Timeouts en `curl` y límite máximo de reintentos al esperar a que GeoServer esté
  disponible.

## [1.9.0] - 2026-03-19

### Agregado
- Directorio dedicado `restore/` para los respaldos de GeoServer.

### Cambiado
- `.gitignore` actualizado para el nuevo directorio.
- Healthchecks de GeoServer simplificados en scripts y targets de Make.

## [1.8.1] - 2026-03-06

### Corregido
- `grep` anclado en el Makefile para extraer las credenciales del admin de GeoServer de
  manera más robusta.

## [1.8.0] - 2026-03-06

### Agregado
- Familia tipográfica Garet, montada dentro del contenedor de GeoServer.

## [1.7.1] - 2026-02-27

### Eliminado
- Configuración de páginas de error personalizadas, archivos HTML y la lógica de
  integración del entrypoint y Docker Compose (revert de `1.7.0`).

## [1.7.0] - 2026-02-27

### Agregado
- Páginas de error personalizadas para varios códigos HTTP, junto con su despliegue.

### Cambiado
- Reportes detallados de errores del servidor deshabilitados.
- Nivel del servicio WFS configurado a básico.

## [1.6.0] - 2026-02-27

### Agregado
- Montaje de los JARs específicos del plugin de salida GeoPackage en el `docker-compose`
  de GeoServer.

## [1.5.0] - 2026-02-27

### Agregado
- Configuración del servicio WFS.
- URL de proxy global dinámica para GeoServer.

### Cambiado
- Charset del WMS actualizado.

## [1.4.0] - 2026-02-27

### Agregado
- Generación dinámica del `server.xml` mediante un wrapper de entrypoint en GeoServer.

## [1.3.0] - 2026-02-26

### Agregado
- Configuración global de charset UTF-8 (templates actualizados y comando de setup).

## [1.2.0] - 2026-02-26

### Agregado
- `GEOSERVER_XSTREAM_WHITELIST` y extensión de `GEOSERVER_CSRF_WHITELIST` en la
  configuración de entorno de GeoServer.

## [1.1.1] - 2026-02-26

### Corregido
- Volumen WMS de configuración: agregado y posteriormente removido tras detectar el
  problema que introducía.

## [1.1.0] - 2026-02-26

### Agregado
- Variable de entorno para `JAVA_OPTS` de GeoServer.

## [1.0.2] - 2026-02-26

### Corregido
- `proxy=true` en la configuración de GeoServer.

## [1.0.1] - 2026-02-26

### Corregido
- Comando en `make restore` para refrescar usuario y contraseña.

## [1.0.0] - 2026-02-25

Primer despliegue a `production` (PR #1 desde `develop`).

### Agregado
- Mejora del backup/restore de GeoServer para incluir plugins.
- Manejo ajustado de `global.xml`.
- Creación automatizada de múltiples datastores PostGIS con soporte de schema.

## [Pre-1.0]

Etapa de configuración inicial sobre `main`/`develop` previa al despliegue a
`production`. Incluye `docker-compose`, Makefile con reglas de production, manejo de
errores, soporte multi-servidor, `.gitignore` para artefactos generados y README inicial
del despliegue de GeoServer en Docker.
