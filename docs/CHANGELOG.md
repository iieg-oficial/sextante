# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

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
- **`.env`** (instancia con `PROXY_HOST=10.25.7.17`, destino produccion S3): `INITIAL_MEMORY=2G`, `MAXIMUM_MEMORY=8G`, `ADDITIONAL_JAVA_STARTUP_OPTIONS=-XX:MaxMetaspaceSize=1g`. El `-XX:+UseG1GC` y el encoding ya los pone kartoza por default.
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

- **`.env`** (instancia con `PROXY_HOST=10.25.7.17`, destino produccion S3): `JAVA_OPTS` ampliado con `-Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g -XX:+UseG1GC`. S3 es VM dedicada 8c/15GB y solo corre el contenedor de GeoServer (1.4 GB usados hoy de 15 disponibles segun `gateway-hub/docs/recursos-servidores.md`), por lo que el heap de 8 GB queda ~50 % de la VM y deja ~7 GB para page cache del kernel donde el OS pone los GeoTIFFs.
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
