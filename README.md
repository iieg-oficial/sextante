<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo-iieg-dark.svg">
    <img src="docs/assets/logo-iieg.svg" alt="Instituto de Información Estadística y Geográfica de Jalisco" width="220">
  </picture>
</p>

<h1 align="center">sextante</h1>

<p align="center">
  <img src="https://img.shields.io/badge/versión-2.13.0-5C2472" alt="Versión 2.13.0">
  <img src="https://img.shields.io/badge/GeoServer-3.0.0-1F6FEB" alt="GeoServer 3.0.0">
  <img src="https://img.shields.io/badge/Tomcat-11-D97706" alt="Tomcat 11">
  <img src="https://img.shields.io/badge/Java-21_LTS-DC2626" alt="Java 21 LTS">
  <img src="https://img.shields.io/badge/licencia-MIT-16A34A" alt="Licencia MIT">
</p>

Despliegue de **GeoServer** en Docker, listo para producción: publica capas WMS y WFS desde una
base PostGIS, con caché de teselas persistente, respaldos, control de carga y un arranque
reproducible desde un solo archivo de configuración.

Nació en el Instituto de Información Estadística y Geográfica de Jalisco y se comparte por si le
sirve a otra institución. Todo lo propio del IIEG está aislado en dos lugares, señalados más
abajo, y el resto funciona tal cual.

## Requisitos

- Docker Engine y Docker Compose v2
- `make`
- Una base PostgreSQL con PostGIS accesible desde el contenedor
- El `gid` del grupo `docker` del host, para el proxy del socket

## Arranque

```bash
cp .env.example .env    # llenar los valores; no se versiona
make up                 # desarrollo
make deploy             # producción: sincroniza el repo, reconstruye y levanta
```

El contenedor escucha en el 8080; qué interfaz y qué puerto se publican en el host sale de
`GEOSERVER_BIND_ADDR` y `GEOSERVER_PORT`. El `.env.example` documenta las 46 variables, y el
compose falla si falta alguna. Las que casi siempre se tocan:

| Variable | Para qué |
|---|---|
| `GEOSERVER_ADMIN_USER` · `GEOSERVER_ADMIN_PASSWORD` | Credenciales del administrador |
| `RESET_ADMIN_CREDENTIALS` | Reescribe esas credenciales en cada arranque |
| `GEOSERVER_CONTEXT_ROOT` | Prefijo de la ruta pública |
| `GEOSERVER_BIND_ADDR` · `GEOSERVER_PORT` | Dónde se publica en el host |
| `GEOSERVER_DATA_DIR` · `GWC_CACHE_HOST_DIR` | Dónde viven los datos y el caché de teselas |
| `POSTGIS_*` | Conexión a la base de datos |
| `INITIAL_MEMORY` · `MAXIMUM_MEMORY` | Memoria de la JVM |
| `STABLE_EXTENSIONS` | Extensiones a activar; ya vienen en la imagen |
| `GS_CONTROLFLOW_*` | Límites de peticiones concurrentes |
| `DOCKER_GID` | Grupo `docker` del host |

**Detrás de un proxy inverso**, `GEOSERVER_PROXY_BASE_URL` debe seguir las cabeceras
(`$${X-Forwarded-Proto}://$${X-Forwarded-Host}/...`) en vez de fijar un host: con un host fijo, el
formulario de inicio de sesión apunta siempre ahí y el navegador bloquea el envío desde cualquier
otro nombre. Los `$$` son el escape de Compose. Cada nombre por el que se entre debe estar en
`GEOSERVER_CSRF_WHITELIST`.

## Qué corre

| Contenedor | Qué hace |
|---|---|
| `sextante` | GeoServer 3.0.0 sobre Tomcat 11 y Java 21 |
| `sextante-docker-socket-proxy` | Acceso acotado y sin root al socket de Docker |
| `sextante-version-api` | Expone la versión desplegada y el estado del nodo |

## Comandos

`make help` los lista todos. Los de diario:

| | |
|---|---|
| Ciclo de vida | `up` · `deploy` · `down` · `restart` · `clean` |
| Diagnóstico | `logs` · `status` · `shell` |
| Datos | `backup` · `restore` · `cron` |
| Caché de teselas | `gwc-seed` · `gwc-export` · `gwc-import` |
| Publicación | `init-datastores` · `init-gridsets` · `init-gwc-filters` |

**`up` y `deploy` corren solos la publicación**: reapuntan los datastores al PostGIS del `.env`,
crean los gridsets, aplican los filtros de GWC, registran los URLChecks y siembran el caché.

## Estructura

```
compose.yaml        un archivo, sin overlays
config/             plantillas de configuración de GeoServer
scripts/            arranque y provisión de capas vía REST
make/               los targets, por dominio
version-api/        el sidecar de versión
geoserver_data/     data dir de GeoServer (no se versiona)
gwc_cache/          caché de teselas (no se versiona)
docs/CHANGELOG.md   qué cambió en cada versión
```

## Lo que es propio del IIEG

Dos cosas que conviene adaptar o quitar al reutilizar el repo:

- **Los `init-*-layer`** (`cultivos`, `curvas-render`, `terreno-rgb`, y `hexbin` a mano) publican
  capas concretas del instituto y esperan tablas propias. Los tres primeros **corren en cada `up` y
  `deploy`**, desde `init_all` en `make/repo.sh`: al reutilizar el repo hay que quitarlos de ahí o
  cambiarlos por los propios. Sirven como ejemplo de provisión por REST.
- **El contrato `/ontoy`** del sidecar y las variables `ONTOY_*` alimentan un monitoreo interno.
  Sin él, el sidecar solo reporta la versión.

## Licencia

MIT. Ver [`LICENSE`](LICENSE).
