# Desplegar este GeoServer desde cero

Guía para levantar sextante en una institución distinta al IIEG. Del host vacío a una capa
publicada, con respaldos y actualización. Los comandos son los del repositorio: no hay pasos
manuales dentro del contenedor.

## 1. Lo que necesitas antes de empezar

| Requisito | Detalle |
|---|---|
| Docker Engine y Compose v2 | `docker compose version` debe responder |
| `make` | Todo el ciclo de vida pasa por ahí |
| PostgreSQL con PostGIS | Accesible desde el host donde corre Docker |
| Un usuario en el grupo `docker` | El `gid` va en el `.env` |
| Disco | El `data_dir` crece con las capas; el caché de teselas, mucho más |

Memoria: GeoServer pide lo que le des. Con 4 GB de RAM en la máquina, 2 GB de heap es un punto de
partida razonable.

## 2. Clonar y configurar

```bash
git clone <este-repo> sextante && cd sextante
cp .env.example .env
```

El `.env` **no se versiona** y el compose **falla si falta una variable**: no hay valores por
defecto escondidos. Lo mínimo que hay que llenar:

```bash
# Credenciales del administrador. RESET_ADMIN_CREDENTIALS=TRUE las reescribe en cada arranque,
# que es lo que quieres mientras montas el servidor.
GEOSERVER_ADMIN_USER=admin
GEOSERVER_ADMIN_PASSWORD=<una larga, sin comillas>
RESET_ADMIN_CREDENTIALS=TRUE

# Dónde se publica y bajo qué prefijo
GEOSERVER_BIND_ADDR=127.0.0.1
GEOSERVER_PORT=8080
GEOSERVER_CONTEXT_ROOT=geoserver

# Base de datos
POSTGIS_HOST=<host>
POSTGIS_PORT=5432
POSTGIS_DB=<base>
POSTGIS_USER=<usuario>
POSTGIS_PASSWORD=<contraseña>
POSTGIS_SSLMODE=require

# Memoria de la JVM
INITIAL_MEMORY=1G
MAXIMUM_MEMORY=2G

# Grupo docker del host
DOCKER_GID=<el de abajo>
```

El `gid` sale de:

```bash
getent group docker | cut -d: -f3
```

> **No entrecomilles los valores.** Compose se queda las comillas como parte del valor: una
> contraseña entre comillas simples llega con dos caracteres de más y el REST responde 401 sin
> decir por qué.

## 3. Primer arranque

```bash
make up
```

Hace, en orden: crea la red de Docker si no existe, levanta los tres contenedores, espera a que
GeoServer responda y corre la inicialización (`init_all`). Tarda un par de minutos la primera vez,
porque descarga la imagen.

Si algo falla, `make logs` abre un selector de servicio.

## 4. Verificar

```bash
source .env
curl -s -o /dev/null -w '%{http_code}\n' \
  -u "$GEOSERVER_ADMIN_USER:$GEOSERVER_ADMIN_PASSWORD" \
  "http://$GEOSERVER_BIND_ADDR:$GEOSERVER_PORT/$GEOSERVER_CONTEXT_ROOT/rest/about/version.json"
```

**200** y listo. Un **401** casi siempre es el `.env` entrecomillado, no una contraseña mal puesta.
`make status` muestra los contenedores y su salud; la interfaz web queda en
`/$GEOSERVER_CONTEXT_ROOT/web`.

## 5. Publicar la primera capa

Con el servidor arriba, lo normal es crear el *workspace* y el *store* desde la interfaz web. Para
automatizarlo, los scripts de `scripts/` son el ejemplo: hablan por REST y toman la conexión del
`.env`.

```bash
make init-datastores   # reapunta los datastores existentes al PostGIS del .env
make init-gridsets     # crea un gridset en la proyección local
```

`init-datastores` es útil al mover un `data_dir` de un servidor a otro: reescribe la conexión de
todos los stores sin tocar las capas. `init-gridsets` crea el gridset de Jalisco (EPSG:6368) y su
extensión: cambia esos valores en `scripts/init-gridsets.sh` por los de tu territorio, o sáltatelo
y quédate con los gridsets que GeoServer trae.

## 6. Detrás de un proxy inverso

Es el punto donde más gente se atora. GeoServer arma la URL del formulario de inicio de sesión con
`GEOSERVER_PROXY_BASE_URL`. Si ahí pones un host fijo, el formulario apunta siempre a ese host y el
navegador **bloquea el envío** desde cualquier otro nombre; el login no falla, simplemente no pasa
nada al dar clic.

```bash
GEOSERVER_PROXY_BASE_URL=$${X-Forwarded-Proto}://$${X-Forwarded-Host}/geoserver
GEOSERVER_CSRF_WHITELIST=<dominio>,<otro-dominio>,<ip>,localhost
```

Los `$$` son el escape de Compose: GeoServer debe recibir `${...}` literal y sustituirlo con las
cabeceras. El proxy tiene que mandar `X-Forwarded-Proto` y `X-Forwarded-Host`. Cada nombre por el
que se entre debe estar en el whitelist, o GeoServer rechaza el POST por CSRF.

Entrando directo al puerto, sin proxy, esas cabeceras no existen: para eso están `PROXY_HOST` y
`PROXY_PORT`, que alimentan el conector de Tomcat.

## 7. Límites de carga

`GS_CONTROLFLOW_*` limita peticiones concurrentes por tipo y por usuario. Sin eso, un cliente que
pide muchos tiles a la vez satura la JVM y tumba el servicio para todos. El `.env.example` trae
valores de partida.

## 8. Respaldos

```bash
make backup    # data_dir completo a backups/, sin el caché de teselas
make restore   # con selector del archivo a restaurar
```

El respaldo sale con `umask 077` y excluye `gwc` y los volcados de memoria, que se regeneran. El
caché de teselas se mueve aparte:

```bash
make gwc-export            # empaqueta hasta el zoom 13
make gwc-import ARGS=<archivo>
```

Programa el respaldo en el `cron` del host apuntando a `make backup`. El `make cron` del repo
instala otra cosa: un sembrado del caché a las 04:30.

## 9. Actualizar

```bash
make deploy
```

Sincroniza el repositorio, reconstruye y vuelve a levantar, y repite la inicialización del paso 3.

## 10. Quitar lo que es del IIEG

Tres cosas que no te sirven si no eres el instituto:

1. **`init_all`, en `make/repo.sh`**, corre en cada `up` y `deploy`: publica capas propias
   (`cultivos`, `curvas-render`, `terreno-rgb`), que contra tu base van a fallar, y crea el gridset
   de Jalisco. Quita esas líneas o cámbialas por tus propios scripts.
2. **El sidecar `version-api` y las variables `ONTOY_*`** alimentan un monitoreo interno. Sin él,
   solo reporta la versión desplegada; se puede borrar el servicio del compose.
3. **La red `iieg-network`** se llama así en `compose.yaml`. Renómbrala si te estorba; `make up` la
   crea sola.

## 11. Cuando algo sale mal

| Síntoma | Causa habitual |
|---|---|
| REST responde 401 con la contraseña correcta | El valor va entrecomillado en el `.env` |
| El botón de inicio de sesión no hace nada | `GEOSERVER_PROXY_BASE_URL` con host fijo detrás del proxy |
| El contenedor reinicia sin parar, con `Read-only file system` | Un montaje `:ro` dentro de una ruta que la imagen hace `chown` |
| Una capa nueva no aparece | Falta recargar la configuración: `POST /rest/reset` |
| Un mosaico temporal no anuncia sus fechas | El índice se construyó antes de que existieran sus `.properties` |

Los dos últimos renglones son de mosaicos y cachés; para el detalle, `docs/CHANGELOG.md` registra
cada cambio con su motivo.
