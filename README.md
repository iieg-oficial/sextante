 GeoServer Docker

Despliegue de [GeoServer](https://geoserver.org/) mediante Docker usando la imagen oficial de [kartoza/geoserver](https://hub.docker.com/r/kartoza/geoserver), con conexión a una base de datos PostgreSQL/PostGIS remota.

---

## Arquitectura

```
Internet (HTTPS)
      │
      ▼
Proxy inverso nginx (SSL termination)
      │
      ▼
GeoServer en Docker :8080  →  PostgreSQL/PostGIS
```

---

## Requisitos

- Docker >= 24
- Docker Compose >= 2
- `make`
- Acceso de red al servidor PostgreSQL/PostGIS

---

## Estructura del proyecto

```
geoserver/
├── Makefile                         # Comandos de operación
├── docker-compose.yml               # Definición del servicio
├── server.xml                       # Conector Tomcat (HTTPS/proxy)
├── config/
│   ├── global.xml                   # URL pública del proxy
│   └── security/
│       └── csp.xml                  # Content Security Policy
├── scripts/
│   └── init-datastores.sh           # Crea datastores con SSL en PostgreSQL
├── .env.example                     # Template de variables de entorno
├── geoserver_data/                  # Data dir persistente (no versionado)
├── plugins/                         # JARs adicionales (no versionado)
└── backups/                         # Backups del data dir (no versionado)
```

---

## Configuración

Copia el archivo de ejemplo y ajusta los valores:

```bash
cp .env.example .env
```

| Variable                   | Descripción                              |
|----------------------------|------------------------------------------|
| `GEOSERVER_ADMIN_USER`     | Usuario administrador de GeoServer       |
| `GEOSERVER_ADMIN_PASSWORD` | Contraseña del administrador             |
| `GEOSERVER_DATA_DIR`       | Ruta del data dir dentro del contenedor  |
| `ENABLE_JSONP`             | Habilita respuestas JSONP                |
| `MAX_FILTER_RULES`         | Número máximo de reglas de filtro        |
| `OPTIMIZE_LINE_WIDTH`      | Optimización de ancho de línea           |
| `GEOSERVER_PROXY_BASE_URL` | URL pública de GeoServer tras el proxy   |
| `GEOSERVER_CSRF_WHITELIST` | IP/dominio permitido para CSRF           |
| `HTTP_SCHEME`              | Esquema usado por el proxy (`https`)     |
| `POSTGIS_HOST`             | IP del servidor PostgreSQL               |
| `POSTGIS_PORT`             | Puerto de PostgreSQL                     |
| `POSTGIS_DB`               | Nombre de la base de datos               |
| `POSTGIS_USER`             | Usuario de PostgreSQL                    |
| `POSTGIS_PASSWORD`         | Contraseña de PostgreSQL                 |

> **Importante:** Nunca subas `.env` al repositorio.

---

## Uso

Todos los comandos se ejecutan con `make`:

```bash
make help
```

### Primer despliegue

```bash
# 1. Configurar variables de entorno
cp .env.example .env

# 2. Levantar GeoServer e inicializar datastores
make up
```
> Nota: RESET_ADMIN_CREDENTIALS:FALSE en producción

### Operación diaria

```bash
make up        # Levantar
make down      # Detener
make restart   # Reiniciar
make logs      # Ver logs en tiempo real
```

### Backup y restore

```bash
# Crear backup (se guarda en backups/ con timestamp)
make backup

# Restaurar el backup más reciente
make restore

# Restaurar un backup específico
make restore RESTORE_FILE=backups/geoserver_data_20260220_120000.tar.gz
```

### Limpiar todo

```bash
make clean     # Detiene el contenedor y elimina geoserver_data/
```

---

## Despliegue en otra máquina

```bash
# 1. Clonar el repositorio
git clone <repo> && cd geoserver

# 2. Configurar variables
cp .env.example .env

# 3. Copiar el backup del servidor anterior
scp usuario@servidor-anterior:/ruta/backups/geoserver_data_*.tar.gz backups/

# 4. Restaurar y levantar
make restore
```

Si no hay backup previo, `make up` levanta GeoServer con configuración base.

---

## Acceso

| Interfaz         | URL                                        |
|------------------|--------------------------------------------|
| Web UI (local)   | http://localhost:8080/geoserver/web        |
| Web UI (público) | https://iieg.jalisco.gob.mx/geoserver/web  |
| WMS              | https://iieg.jalisco.gob.mx/geoserver/wms  |
| WFS              | https://iieg.jalisco.gob.mx/geoserver/wfs  |

---

## Volúmenes

| Host                         | Contenedor                                        | Descripción                        |
|------------------------------|---------------------------------------------------|------------------------------------|
| `./geoserver_data`           | `/opt/geoserver/data_dir`                         | Datos y configuración persistentes |
| `./plugins`                  | `/opt/geoserver/webapps/geoserver/WEB-INF/lib/`  | Plugins adicionales                |
| `./server.xml`               | `/usr/local/tomcat/conf/server.xml`               | Conector Tomcat HTTPS              |
| `./config/global.xml`        | `/opt/geoserver/data_dir/global.xml`              | URL del proxy                      |
| `./config/security/csp.xml`  | `/opt/geoserver/data_dir/security/csp.xml`        | Content Security Policy            |

---

## Plugins

Coloca los archivos `.jar` en la carpeta `plugins/`. Se montan directamente en el classpath al iniciar el contenedor.

---

## Conexión PostgreSQL/PostGIS

La conexión usa `sslmode` configurable mediante la variable `POSTGIS_SSLMODE` en el `.env` (valor por defecto: `allow`). El script `scripts/init-datastores.sh` crea o actualiza los datastores automáticamente al ejecutar `make up`, leyendo las credenciales del `.env`.

Para añadir más datastores, edita `scripts/init-datastores.sh` agregando nuevas llamadas a `create_datastore`.

---

## Errores frecuentes

### Error al crear datastore: `pg_hba.conf rejects connection ... no encryption`

**Mensaje completo:**
```
Error creating data store, check the parameters. Error message: Unable to obtain
connection: Cannot create PoolableConnectionFactory (FATAL: pg_hba.conf rejects
connection for host "10.x.x.x", user "usrgis", database "iieg_gis", no encryption)
```

**Causa:** El servidor PostgreSQL exige cifrado en las conexiones de esa IP, pero el datastore se configuró sin SSL.

**Solución:** Al crear o editar el datastore en GeoServer, establecer el campo **SSL mode** en `allow` (o `prefer`/`require` según la configuración del servidor).

Si el datastore ya existe, el script `init-datastores.sh` lo actualiza automáticamente usando el valor de `POSTGIS_SSLMODE` del `.env`:

```bash
bash scripts/init-datastores.sh
```
