# GeoServer Docker

Despliegue de [GeoServer 2.27.0](https://geoserver.org/) mediante Docker usando la imagen oficial de [kartoza/geoserver](https://hub.docker.com/r/kartoza/geoserver), con conexión a una base de datos PostgreSQL/PostGIS remota.

---

## Arquitectura

```
Internet (HTTPS)
      │
      ▼
Dominio  (proxy inverso / SSL)
      │
      ▼
GeoServer en Docker  →  PostgreSQL/PostGIS :5433
      │
   puerto 8080
```

---

## Requisitos

- Docker >= 24
- Docker Compose >= 2
- Acceso de red entre geoserver y base de datos en el puerto `5433`

---

## Estructura del proyecto

```
geoserver-docker/
├── docker-compose.yml       # Definición del servicio GeoServer
├── .env                     # Variables de entorno (no subir a git)
├── geoserver_data/          # Data dir persistente de GeoServer
└── plugins/                 # JARs adicionales montados en WEB-INF/lib/
```

---

## Configuración

Las variables de entorno se gestionan en el archivo `.env`. Copia el ejemplo y ajusta los valores:

```bash
cp .env.example .env   # si existe el ejemplo, o edita .env directamente
```

| Variable                  | Descripción                                      | 
|---------------------------|--------------------------------------------------|
| `GEOSERVER_ADMIN_USER`    | Usuario administrador de GeoServer               | 
| `GEOSERVER_ADMIN_PASSWORD`| Contraseña del administrador                     | 
| `GEOSERVER_DATA_DIR`      | Ruta del data dir dentro del contenedor          | 
| `ENABLE_JSONP`            | Habilita respuestas JSONP                        | 
| `MAX_FILTER_RULES`        | Número máximo de reglas de filtro                | 
| `OPTIMIZE_LINE_WIDTH`     | Optimización de ancho de línea                   | 
| `GEOSERVER_PROXY_BASE_URL`| URL pública de GeoServer (tras el proxy)         | 
| `GEOSERVER_CSRF_WHITELIST`| Dominio permitido para CSRF                      | 
| `HTTP_SCHEME`             | Esquema HTTP usado por el proxy                  | 
| `POSTGIS_HOST`            | IP del servidor PostgreSQL/PostGIS               |
| `POSTGIS_PORT`            | Puerto de PostgreSQL en el host remoto           | 
| `POSTGIS_DB`              | Nombre de la base de datos                       | 
| `POSTGIS_USER`            | Usuario de PostgreSQL                            | 
| `POSTGIS_PASSWORD`        | Contraseña de PostgreSQL                         | 

> **Importante:** Nunca subas el archivo `.env` a un repositorio público. Agrégalo a `.gitignore`.

---

## Uso

### Iniciar el servicio

```bash
docker compose up -d
```

### Ver logs

```bash
docker compose logs -f geoserver
```

### Detener el servicio

```bash
docker compose down
```

### Reiniciar

```bash
docker compose restart geoserver
```

---

## Acceso

| Interfaz        | URL                                                      |
|-----------------|----------------------------------------------------------|
| Web UI (local)  | http://localhost:8080/geoserver/web                      |
| Web UI (público)| dominio/geoserver/web              |
| OGC Services    | dominio/geoserver/wms, /wfs, /wcs |


---

## Volúmenes

| Ruta en el host              | Ruta en el contenedor                              | Descripción                       |
|------------------------------|----------------------------------------------------|-----------------------------------|
| `./geoserver_data`           | `/opt/geoserver/data_dir`                          | Configuración y datos persistentes|
| `./plugins`                  | `/opt/geoserver/webapps/geoserver/WEB-INF/lib/`   | Plugins/extensiones adicionales   |

---

## Plugins

Para agregar extensiones a GeoServer, coloca los archivos `.jar` en la carpeta `plugins/`. Serán montados directamente en el classpath del servidor al iniciar el contenedor.

---

## Conexión a PostgreSQL/PostGIS

La conexión se establece desde VM1 hacia VM2. Para más detalles sobre la configuración de red, reglas de `pg_hba.conf` y troubleshooting, consulta [CONEXION_GEOSERVER_POSTGIS.md](CONEXION_GEOSERVER_POSTGIS.md).

---

## .gitignore recomendado

```
.env
geoserver_data/logs/
geoserver_data/tmp/
geoserver_data/temp/
geoserver_data/gwc/tmp/
```
