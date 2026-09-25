# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

## [2.12.0] - 2026-09-24

Reparaciones de la auditoria de seguridad del 2026-09-24 (`context-ame-esta`,
`historial/2026-09-24-auditoria-seguridad.md`). La consola, la REST y el catch-all de `/sextante/`
se cerraron del lado del gateway (gateway-hub 1.55.0).

### Corregido

- **Se elimina `proxy_server.py`.** Era un servidor de desarrollo que servia la raiz del repo
  —`.env` incluido— en `0.0.0.0`. Nada lo invocaba.
- **La contrasena de PostGIS ya no viaja en la linea de comandos de `curl`.** `init-datastores.sh` e
  `init-hexbin-layer.sh` mandan el cuerpo del datastore por stdin (`--data-binary @-`), asi que no
  aparece en `ps` mientras corre el script.
- **`set_charset` ya no saca la credencial del admin a la linea de comandos del host.** Antes la leia
  con `docker exec env` y la pasaba a `curl -u`; ahora el `curl` corre dentro del contenedor y recibe
  la cabecera `Authorization` por stdin con `-K -`.
- **Respaldos solo legibles por su dueno.** `make backup` corre con `umask 077` y deja `backups/` en
  `700`: el tar lleva los `datastore.xml` con la contrasena de PostGIS.

### Cambiado

- `.env.example`: `POSTGIS_SSLMODE=require` (dataengine ya tiene `ssl = on` y `hostssl` en
  `pg_hba`) y `ENABLE_JSONP=false` (ningun repo pide JSONP). **El `sslmode` queda guardado en el XML
  de cada datastore**: al cambiarlo en el `.env` hay que correr `make init-datastores`.
- `.env.example`: la arista de `ONTOY_PEER_CHECKS` a S4 pasa de `:6432` a `:5432`, porque pgbouncer ya
  no se publica fuera de la VM.
- El sidecar `version-api` ya no monta `docker.sock`; consulta contenedores por
  `DOCKER_HOST=tcp://docker-socket-proxy:2375` (`tecnativa/docker-socket-proxy:v0.5.0`,
  `CONTAINERS=1` y lo demas en 0, red interna `sextante-docker-api`) y corre como uid 65534.
- `ontoy_server.py` sincronizado con huachicol 2.18.0: 500 con texto fijo, tope de 8 hilos, timeout
  de 5 s, cache de 2 s y CPU sin sleep por peticion; desaparece `ONTOY_CPU_SAMPLE_SECONDS`.

## [2.11.0] - 2026-09-22

### Corregido: el terreno 3D colgaba una cortina de picos en el borde de Jalisco

Fuera del estado el DEM no tiene datos y el tile sale transparente; MapLibre lee un pixel
transparente como **0 metros**, así que en el borde —dentado a 15 m— el terreno caia al nivel del
mar pixel de por medio y quedaba un fleco de picos colgando.

Ahora la capa se publica sobre `elevacion_jalisco_relleno.tif`, que genera el propio script con
`gdal_fillnodata.py` (`-md 2500`, unos 37 km) si todavia no existe: el terreno continua mas alla del
limite y el corte se va al borde del bbox del DEM. El archivo se queda en el data dir, no se
versiona, y tarda varios minutos la primera vez.

- Coveragestore propio `raster:terreno_rgb`; si la capa seguia colgada del store `elevacion`, el
  script la retira antes de republicar.
- Al cambiar de origen se purga el cache de GWC de la capa (`masstruncate`), porque los tiles viejos
  traen los huecos.

## [2.10.0] - 2026-09-21

### Agregado: el DEM codificado en RGB para el terreno 3D de mapalab

`scripts/init-terreno-rgb-layer.sh` (`make init-terreno-rgb-layer`, y corre en cada `make up` y
`make deploy`) publica `raster:elevacion_terreno_rgb`: la misma cobertura que
`raster:elevacion_jalisco_intervalo_vertical_10m`, con el estilo `raster:terreno_rgb`, que guarda la
altura en los canales del PNG (`altura = R*256 + G`, en metros). mapalab 1.173.0 la lee como
`raster-dem` de MapLibre con `encoding: 'custom'`.

- El SLD es una rampa `extended="true"` generada por el script; sin `extended`, GeoServer la acota a
  256 colores y la codificación se rompe.
- Interpolación al vecino más cercano: un remuestreo bilineal mezclaría los canales y daría
  saltos de hasta 128 m en los cortes.
- Tile layer de GWC solo en `EPSG:900913` y `image/png`, con `expireClients` de una semana. Se
  siembra de z6 a z12 desde `config/gwc-seed-auto.txt` (≈55 KB por tile).
- Idempotente; `--force` rescribe el estilo. Falla explícitamente si no existe el coveragestore
  `raster:elevacion`.

Verificado contra el DEM original con `gdallocationinfo`: 3 920 m en el Nevado de Colima y 1 550 m
en Guadalajara, a z9 y z12, decodificados igual al metro.

## [2.9.1] - 2026-09-07

### Corregido: el login se bloqueaba desde cualquier nombre que no fuera el del `.env`

`GEOSERVER_PROXY_BASE_URL` traia un host fijo, y GeoServer arma con el el `action` del formulario de
login. Entrando por otro nombre el POST salia cross-origin y el `form-action 'self'` del gateway lo
bloqueaba: el boton no hacia nada. Con los nombres internos del AD en uso, esto dejo la consola
inaccesible por todos menos uno.

Ahora la URL base sigue las cabeceras del gateway:

```
GEOSERVER_PROXY_BASE_URL=$${X-Forwarded-Proto}://$${X-Forwarded-Host}/sextante
```

**Los `$$` son escape de compose, no un error**: GeoServer tiene que recibir `${...}` literal para
sustituirlo el mismo. Requiere `useHeadersProxyURL=true` en `config/global.xml.template`, que ya
venia activado.

Ampliar `form-action` no habria servido: la sesion se crearia en el host del `action` mientras se
navega otro, y el login entra en bucle.

`GEOSERVER_CSRF_WHITELIST` es un segundo candado independiente —GeoServer compara el `Referer`—, asi
que cada nombre nuevo por el que se vaya a entrar tiene que estar tambien ahi.

Diagnostico y verificacion en `runbook/sextante.md`.

## [2.9.0] - 2026-08-27

### Agregado: el `/ontoy` declara a que nodo pertenece

huachicol 2.9.0 amplio el contrato para que el monitor agrupe por servidor y no solo por servicio.
`ONTOY_NODE` dice donde corre este repo —**S3**— y `ONTOY_NODE_REPORTER` decide quien habla del
host. Es el reportero de su nodo, asi que su `/ontoy` agrega carga, RAM, swap y uptime, leidos de `/proc` sin exporters ni puertos nuevos.

`ONTOY_PEER_CHECKS` queda disponible para las aristas entre nodos; vacia por omision.

**Las dos primeras son obligatorias**: el compose falla si faltan, asi que hay que agregarlas al
`.env` de cada entorno antes de desplegar.

De paso, `ontoy_server.py` se sincroniza con el de huachicol, que es la fuente y llevaba tiempo
divergiendo entre copias. Los checks de maquina quedan marcados como informativos y ya no tumban el
estado del servicio.

## [2.8.0] - 2026-08-25

### Corregido: Tomcat rechazaba con 400 los CQL grandes del visor

El conector HTTP no declaraba `maxHttpHeaderSize`, asi que usaba el default de Tomcat —**8 192
bytes**— y cualquier `GetMap` con una URI mas larga moria con `400` antes de llegar a GeoServer. Se
sube a **65 536**.

El caso: la capa «Establecimientos de salud» agrupa 33 subcapas sobre `salud.unidades_salud`, cada
una con su filtro de institucion y nivel, mas el rango de fechas. Con la vista por municipio activa
la URI llegaba a **10 867 bytes**. En el visor la capa aparecia vacia y en consola solo se veia
`Failed to load resource: 400`.

**Eran dos topes en serie, no uno.** gateway-hub 1.49.0 subio antes `large_client_header_buffers`,
que estaba en el default de nginx de 4 x 8 KB; con eso la peticion ya cruzaba el proxy pero seguia
muriendo aqui. Comprobado con un CQL de 10 652 caracteres: **200 directo a Tomcat y 200 por el
gateway**, contra 400 en ambos antes del cambio.

**El CQL crece con el catalogo**: cada subcapa nueva del grupo alarga la URI, asi que los defaults
de 8 KB no dan para este visor.
## [2.7.5] - 2026-09-17

### Corregido: `make restore` dejaba al admin sin contraseña

`reset-admin.sh` cargaba `/scripts/env-data.sh` y `/scripts/functions.sh`, rutas que
`kartoza/geoserver:3.0.0` movio a `/scripts/lib/` (`env-data.sh`, `utils.sh`, `geoserver.sh`).
Sin esas libs `make_hash` no existia, `PWD_HASH` quedaba vacio y el `sed` escribia
`password=""` en `users.xml`: GeoServer respondia 500 a cualquier login y la interfaz web
quedaba inaccesible. El bloque remoto corria sin `set -e`, asi que el script seguia adelante e
imprimia "Admin actualizado a: <usuario>" sobre un archivo ya roto.

Ahora las libs se cargan desde `/scripts/lib/` cuando existe —la ruta vieja queda de respaldo
para entornos que sigan en la imagen 2.x—, el bloque remoto lleva `set -e` y un hash vacio
aborta antes de tocar `users.xml`.

La espera posterior al reinicio apuntaba a `http://localhost:8080/geoserver/web/`, con el
context root escrito a mano: con `GEOSERVER_CONTEXT_ROOT=sextante` esa URL da 404 siempre y el
paso terminaba en `Error 1` a los 120 s aunque GeoServer hubiera arrancado en 14 s. Pasa a
`${GEOSERVER_CONTEXT_ROOT:-sextante}`, igual que `wait_geoserver`.

Ese mismo bucle conservaba el limite de 24 intentos que `wait_geoserver` dejo atras en 2.7.4.
Como el reinicio ocurre con el `data_dir` ya restaurado, los mismos nueve minutos de arranque
volvian a agotarlo. Pasa a `${GEOSERVER_WAIT_MAX:-180}`.

## [2.7.4] - 2026-09-10

### Corregido: `make deploy` y `make restore` cortaban antes de que GeoServer respondiera

`wait_geoserver` esperaba 300 s (`GEOSERVER_WAIT_MAX=60`) y con el `data_dir` de produccion
GeoServer tarda cerca de nueve minutos en responder: el `fix_permissions` del entrypoint recorre
los directorios de la imagen en cada recreacion y despues carga el catalogo. El deploy terminaba en
`Error 1` sin correr `init_all` (datastores, cultivos, curvas, gridsets, URLChecks, filtros de GWC,
seed y cron) mientras el contenedor seguia arrancando y quedaba sano. Pasa a 180 intentos (15 min);
el bucle sale en cuanto responde, asi que esperar de mas no cuesta nada.

## [2.7.3] - 2026-08-18

### Corregido: `gwc_cache/` no estaba ignorado por git

Al sacar el blobstore del `data_dir` (2.5.0), el caché quedó en la raíz del repo y sin entrada en
`.gitignore`: aparecía como no rastreado en cada `git status` y un `git add -A` distraído lo habría
metido al repo. En este nodo son 156 KB, pero en el espejo son **1.5 millones de archivos**, y
además sus permisos hacen que `git status` avise de directorios que no puede leer.

## [2.7.2] - 2026-08-18

### Corregido: el hexbin va en su propio workspace, no en `general`

`init-datastores.sh` fuerza **todos** los datastores del workspace `general` al schema `mapa_base`
via `SCHEMA_MAP`. El datastore del hexbin apunta a `mapalab`, asi que cada reapuntado se lo llevaba
por delante y GeoServer respondia `Schema 'hexbin_agregado' does not exist`.

La capa pasa a `mapalab:hexbin_agregado`, en un workspace propio que el script crea si falta y que
ningun reapuntado toca.

## [2.7.1] - 2026-08-18

### Agregado: `make init-hexbin-layer`, publica la capa del hexbin H3

dataengine precalcula los conteos H3 de las capas de puntos y expone la vista
`mapalab.hexbin_agregado` (sus migraciones 0037 y 0038). Aqui se registra en GeoServer lo que no
vive en codigo: un datastore `mapalab_hexbin` hacia el schema `mapalab` y la capa
`general:hexbin_agregado` en EPSG:6368.

El script es idempotente: si el datastore existe lo actualiza, si la capa existe no hace nada. Usa
las mismas `POSTGIS_*` del `.env` que el resto de datastores, asi que no hay credencial nueva.

Sin esto, el visor no encuentra los conteos y cae al calculo en el navegador, que sigue funcionando
pero con su tope de 20 000 elementos.
## [2.7.0] - 2026-08-07

### Cambiado: la ruta del blobstore en el host se elige por nodo

El volumen del blobstore tenia el lado del host fijo en `./gwc_cache`, relativo al repo. Los nodos
del ecosistema corren sobre infraestructuras distintas —local, GCP, Proxmox y administracion— y no
todos quieren el millon y medio de tiles en el mismo disco que el codigo.

El lado del host pasa a `GWC_CACHE_HOST_DIR`, nueva en el `.env`. Son dos rutas distintas y se
confunden con facilidad:

| Variable | Donde | Varia por nodo |
|---|---|---|
| `GEOWEBCACHE_CACHE_DIR` | dentro del contenedor | no — es la misma imagen en todos |
| `GWC_CACHE_HOST_DIR` | en el host | si |

Una ruta relativa **tiene que llevar `./`**: sin la barra, compose la interpreta como volumen
nombrado y aborta con `refers to undefined volume gwc_cache`, un error que no menciona el `.env`.

**Al aplicarlo, las dos claves van al `.env` antes de bajar el contenedor.** El compose falla al
interpolar, asi que un `make deploy` sin ellas no llega ni al `down`: reporta `fail`, el contenedor
viejo sigue arriba y el nodo se queda en la version anterior.

### Corregido: el deploy terminaba en `Error 1` sin instalar el cron del seed

En un nodo con el crontab **vacio**, `cron_install` dejaba el cron sin instalar y hacia fallar el
deploy entero. Las recetas corren con `-eu -o pipefail`, y ahi `crontab -l | grep -v` devuelve 1
cuando no hay ninguna linea que conservar: el subshell muere antes del `echo` de la linea nueva y
el `crontab -` de la derecha recibe la entrada vacia.

El sintoma no apunta a nada: **todos los pasos salen `ok`** y el `make` termina en `Error 1` sin
una linea de error propia, porque quien falla es el ultimo paso, que no imprime fila. Los filtros
cuyo «no hay coincidencias» es legitimo se cierran con `|| true`.

Mismo bug y mismo arreglo en **mariachi** (respaldo de BD y refresh de stats) y **acervo**
(respaldo mensual). En un nodo que ya paso por esto, `crontab -l` vacio es la senal.

## [2.6.1] - 2026-08-07

### Corregido: `general:curvas_de_nivel` no cacheaba y saturaba la CPU del nodo

La capa quedo fuera de `gwc-filters.txt` cuando se publico `curvas_de_nivel_render`, su version
optimizada. Es correcto mientras todos los nodos corran un frontend que ya pida la nueva; en
cuanto uno se queda atras, **sigue pidiendo la vieja, que sin filtro de `ENV` no cachea nunca**.

Sin ese filtro GWC no procesa la peticion: el visor manda `ENV=geom:geom_iieg` en cada GetMap y
GWC la pasa directo a WMS. No es un `MISS` que se vuelve `HIT` a la segunda — es permanente.

Detectado en GCP el 2026-08-07, con el backend de mapalab 8 dias atras: 390 peticiones por hora
renderizando en vivo a ~3 s cada una, con el `load average` en **19.59** sobre 2 cores. No aparece
en ningun log como error; se manifiesta como saturacion de CPU intermitente.

| | Antes | Despues |
|---|---|---|
| 2a peticion, mismo tile | 2.64 s · `MISS` | **0.019 s · `HIT`** |
| 3a peticion, mismo tile | 2.99 s · `MISS` | **0.024 s · `HIT`** |

La capa sustituida se queda declarada mientras algun nodo pueda pedirla. Para encontrar otras
huerfanas, el barrido esta en `runbook/capas-y-tiles.md` del repo de contexto.

## [2.6.0] - 2026-08-07

### Corregido: el arranque pasaba de 1 min a casi 8 con el cache sembrado

Tras sembrar GWC, el blobstore quedo con **1 574 496 archivos** dentro de `geoserver_data/`. El
entrypoint de kartoza recorre el `data_dir` entero en cada arranque para verificar dueños
(`geo_data_file_perms`), asi que **cada `make deploy` o `restart` sumaba minutos en los que el
contenedor esta `unhealthy` y GeoServer no responde**. No es evidente: el sintoma es «esta arriba
pero no contesta», sin relacion aparente con el cache.

El blobstore sale del `data_dir` a `gwc_cache/`, via `GEOWEBCACHE_CACHE_DIR` (nueva en el `.env`).
Medido en el espejo, mismo nodo y mismos 7.5 GB de tiles:

| Blobstore | Arranque hasta `healthy` |
|---|---|
| Dentro de `geoserver_data/` | **7 min 44 s** |
| En `gwc_cache/` | **1 min 29 s** |

El entrypoint tambien hace `chown` sobre `GEOWEBCACHE_CACHE_DIR`, asi que la mejora no viene de
que deje de recorrerlo; viene de sacarlo del arbol que se recorre para todo lo demas. Se midio dos
veces (1 min 29 s y 1 min 38 s) para descartar que fuera cache de inodos.

**Al aplicarlo en un nodo existente, mover el cache con `mv`** —mismo filesystem, tarda menos de un
segundo y **preserva los dueños**—:

```bash
docker compose -p sextante -f compose.yaml down
sudo mkdir -p gwc_cache && sudo mv geoserver_data/gwc/* gwc_cache/
make up
```

**No hacer `chown` despues del `mv`.** El usuario dentro del contenedor es
`geoserveruser:geoserverusers`, **uid 2000**, no el 1000 del host. Un `chown -R 1000:1000` marca el
millon y medio de archivos como incorrectos y el entrypoint los corrige uno por uno: costo medido,
mas de 30 minutos, y si se reinicia a la mitad **vuelve a empezar**.

## [2.5.0] - 2026-08-06

### Agregado: exportar e importar el cache de tiles entre entornos

`scripts/gwc-cache.sh export|import` (targets `gwc-export` y `gwc-import`) empaqueta el blobstore
de GeoWebCache para llevarlo a otro entorno sin volver a sembrarlo. Pensado para **GCP**, que con
2 cores compartidos tarda horas en lo que aqui son minutos.

Los tiles son portables porque la carpeta de cada combinacion se nombra con un hash del **valor**
de los parameter filters —`ENV=geom:geom_iieg`—, no de la instalacion, y ese valor sale de
`config/gwc-filters.txt`, que esta versionado: mismo archivo de filtros, mismo hash, tiles
reutilizables.

`MAX_Z` (default **13**) recorta los niveles altos, que son casi todo el peso. Medido sobre las 7
capas del seed automatico: **647 MB hasta z13, 2.1 GB hasta z14 y 7.2 GB hasta z15** — o sea que
z14 y z15 son el 90 % del tamaño y los que menos se visitan. El paquete de z13 comprime a **490 MB
en 4 minutos**.

**Aviso:** el cache no sabe si el dato de origen cambio. Si el entorno destino tiene datos
distintos, los tiles mostraran los del origen hasta que se trunquen. Para datos que difieren,
sembrar en destino en vez de importar.

### Agregado: `gwc-bench.sh` para medir antes y despues

Pide una pantalla completa (10x7 tiles de 256 px, como el visor) por capa y reporta tiempo total y
cuantos salieron de GWC. Mide **dentro del contenedor**, saltandose el gateway, cuyo `proxy_cache`
devuelve la copia de la primera respuesta y enmascara el resultado.

Sirve para comparar el mismo entorno antes y despues de un cambio —importar un cache, crear
indices, tocar la JVM— en vez de estimar la mejora.

### Corregido: los respaldos cargaban 13 GB de peso muerto

`make backup` empaquetaba **todo** el `data_dir`, que con el seeding pasó a incluir 7.7 GB de
tiles **regenerables con un comando**. Ademas arrastraba `heapdumps`, un archivo suelto de 5.5 GB
del 10 de junio —un volcado de memoria de la JVM— que llevaba dos meses respaldandose.

Ambos quedan excluidos. Tras restaurar, el cache se repone con `make gwc-seed ARGS=--auto` o
importando un paquete de `gwc-export`.

## [2.4.0] - 2026-08-06

### Agregado: seeding de GeoWebCache, con las capas iniciales leidas del catalogo

El cache de tiles solo ayuda a partir de la segunda visita: el primer visitante de cada zona paga
el render completo. Se nota en cualquier despliegue nuevo, donde el blobstore arranca vacio, y
despues de purgar o regenerar datos. No habia nada en el ecosistema para pre-generarlos.

`scripts/gwc-seed.sh` encola seeds por REST. `--auto` **no usa una lista fija**: consulta
`/api/layers/initial-order` y `/api/layers/tree` de mapalab (`MAPALAB_API_URL`, nueva en el
`.env`) y siembra las capas con las que arranca el visor, asi que si esas capas cambian el
siguiente despliegue siembra las nuevas sin que nadie edite configuracion. Les suma
`config/gwc-seed-auto.txt`, donde van las caras que no estan en la vista inicial. Si el catalogo
no responde, avisa y sigue con el archivo.

Corre dentro de `make up` y `make deploy` **sin alargarlos**: GWC siembra en background y el
script vuelve en segundos. El tipo de peticion es `seed`, no `reseed`, asi que un `up` repetido
solo rellena lo que falte. `make gwc-seed` lanza el catalogo completo (`config/gwc-seed.txt`),
`ARGS=--status` da el avance y `ARGS=--stop` cancela.

Una capa con `CQL_FILTER` se siembra una vez por cada combinacion declarada en
`config/gwc-filters.txt` — una sola fuente de verdad para los CQL, sin duplicar configuracion.
Es lo que hace util sembrar `economia:cultivos`: son 8 capas del visor sobre el mismo featuretype
de 346 836 poligonos.

Medido en el espejo, sobre Jalisco:

| | Disco | Tiempo |
|---|---|---|
| Las 32 capas del catalogo, z6-13 | 775 MB | 4 min |
| `cuerpos_de_agua_50k` z14 (solo ese nivel) | +150 MB | 1 min 23 s |
| `cuerpos_de_agua_50k` z15 (solo ese nivel) | +570 MB | 6 min 39 s |

Cada nivel pesa mas que todo lo anterior junto, con un factor medido de 2.6x (curvas, que
comprimen mejor) a 3.75x (poligonos municipales). **El default es `z6-15`**: cubre hasta nivel de
manzana —4.5 m/pixel— y para las 7 capas del seed automatico son **7.0 GB**, medidos al terminar la
siembra completa. La mas pesada es `economia:cultivos` (1902 MB, con sus dos combinaciones de CQL)
y la mas ligera `cabeceras_municipales` (619 MB). Bajar a z18 serian ~237 GB solo esas siete, y no
aportan: un poligono municipal a 0.56 m/pixel muestra lo mismo que a z13, solo mas grande.

Sembrar con el servicio arriba no lo degrada de forma apreciable: con 2 hilos, medido contra el
gateway, `/mapalab/` pasa de 12 a 17-64 ms y un tile cacheado de 11 a 15-25 ms.

### Agregado: cron diario del seed y `--refresh` para datos que cambiaron

`make cron` instala el seed a las **04:30**, y `make up`/`make deploy` lo dejan puesto solos
(idempotente: si ya existe no lo duplica). No a las 04:00 a proposito: a esa hora corre
`run_refresh_layer_tree.py` en dataengine, que es justo el catalogo del que `--auto` lee las capas
iniciales.

El cron es barato porque **GWC salta los tiles que ya existen**: medido, 83 s la primera siembra de
una capa y 6 s la segunda. El reverso es que no detecta datos cambiados — si se recarga una capa o
se refresca su vista materializada, los tiles viejos se siguen sirviendo. Para eso esta
`gwc-seed.sh --refresh`, que trunca el cache de la capa antes de sembrarla.

### Corregido: un parameter filter fallido tumbaba el despliegue del ecosistema

`init-gwc-filters.sh` terminaba con `[ "$fail" -eq 0 ]`, asi que dos layer groups sin filtro
—`general:limite_iieg` y `general:limite_inegi`— hacian fallar `make deploy` y, con el,
`ecosystem-deploy` entero. Esta desproporcionado: un filtro que falta degrada el cache, no rompe
el servicio, y el resto de los `init-*` del repo ya avisan y siguen. Ahora imprime que capas
quedaron sin cache y por que, y deja pasar el despliegue.

## [2.3.0] - 2026-08-06

### Agregado: `init-curvas-render-layer.sh` publica la capa de curvas subdividida

La migración `0026_curvas_de_nivel_render` de dataengine materializa
`mapa_base.curvas_de_nivel_render` y deja anotado un «paso manual posterior (GeoServer, no DB)»:
publicar el featuretype. Ese paso nunca se ejecutó, así que la tabla existía con 180 865 filas y
el visor seguía pidiendo la tabla original. Medido sobre el mismo tile de 256 px en caliente:
**3 010 ms/tile contra 42 ms**.

El script publica `general:curvas_de_nivel_render` con SRS nativo 3857, le asigna el estilo
`general:curvas_de_nivel` y la deja con WFS deshabilitado y `queryable=false`. Es idempotente
(*skip* si ya existe, `--force` para reaplicar) y corre dentro de `make up` y `make deploy`, junto
a `init-cultivos-layer.sh`. Queda pendiente el `UPDATE` de `mapalab.layers.geoserver_layer`, que
vive en la base y no viaja en el despliegue.

### Agregado: el filtro de ENV se declara en las 121 capas del catálogo

`gwc-filters.txt` tenía 4 entradas. El visor manda `ENV=geom:geom_iieg` en **cada** GetMap, y GWC
no cachea ningún parámetro que no esté declarado como `parameterFilter`: sin el filtro, la capa
responde MISS siempre. Medido sobre `demografia:poblacion` con un tile alineado al gridset, la
segunda petición pasa de MISS a HIT en cuanto el filtro existe.

La consecuencia importante es al revés: **marcar una capa como `tiled` sin declararle el filtro de
ENV la deja en ~70 peticiones por pantalla sin caché, contra 1 sola de `ImageWMS`**. El archivo
ahora lista las 121 capas del catálogo y trae en la cabecera la consulta que regenera la lista.

### Corregido: dos capas de cada 121 fallaban al declararles filtros

Ambas devolvían `HTTP 500 · Duplicate field parameterFilters`, que no apunta a la causa:

- GWC serializa el `styleParameterFilter` con
  `<allowedStyles class="java.util.Collections$UnmodifiableSet">` y su propio XStream no lo vuelve
  a leer. Se quita el atributo `class` antes del POST y el filtro de estilos se conserva.
- `<parameterFilters/>` self-closing —el caso de los layer groups `general:limite_iieg` y
  `general:limite_inegi`— no coincidía con la búsqueda de la etiqueta de apertura, así que el
  script añadía un segundo bloque.

## [2.2.2] - 2026-07-31

### Agregado: `VERBOSE=1` en los targets que usan `run_step`

Sincronización de `make/lib.sh` y `make/common.mk` con gateway-hub 1.42.0. `run_step` esconde la
salida de cada paso y sólo la muestra —las últimas 40 líneas— si falla, así que un `docker build`
real y uno servido entero por caché se ven igual salvo por el cronómetro. Con `VERBOSE=1` la
salida se imprime en directo, indentada bajo el paso y conservando el `ok`/`fail` y el tiempo. El
comportamiento por defecto no cambia.

## [2.2.1] - 2026-07-31

### Corregido: cada arranque dejaba dos ERROR en el log de GeoServer

`setup-urlchecks.sh` creaba los URLChecks con un POST y trataba el 409 como éxito, así que el
script terminaba en verde. Pero GeoServer registra el POST duplicado como `ERROR [geoserver.rest] -
URL check '<nombre>' already exists` con su traza de `RestException 409 CONFLICT`, y eso aparecía
en el reporte de errores de `ecosystem-status` en cada `make up`.

Ahora consulta con un GET antes de crear. Sigue siendo idempotente y ya no ensucia el log; el
riesgo real era que dos errores esperados taparan uno de verdad.

## [2.2.0] - 2026-07-31

### Agregado: `config/gwc-filters.txt`, manifiesto versionado de parameter filters

Los filtros viven en `geoserver_data/gwc-layers/`, que es **per-host y no se versiona**: aplicarlos
por REST solo arreglaba el entorno donde se corria el comando. Ahora se declaran en un archivo
versionado que `init-gwc-filters.sh` aplica sin argumentos, y que `init_all` ejecuta en cada
`make up` y `make deploy`. Es lo que hace el ajuste reproducible entre local y produccion.

## [2.1.0] - 2026-07-31

### Agregado: `make init-gwc-filters` para declarar los parameter filters de GWC

Sin declarar un parametro como `parameterFilter`, **GeoWebCache ni siquiera procesa la peticion**:
no solo se pierde el cache, tambien el metatiling 4x4. Y sin metatiling cada tile de 256 px se
renderiza aislado, asi que los poligonos y etiquetas que cruzan la juntura salen cortados. Ese era
el sintoma reportado — «no cargan bien todas las tiles» — cuando en realidad todas respondian 200.

El script declara `ENV` siempre (`geom:geom_iieg` / `geom:geom_inegi`, que mapalab manda en cada
GetMap) y `CQL_FILTER` cuando se le pasa un valor. Es idempotente: reemplaza los filtros que
gestiona y respeta los demas, como el `styleParameterFilter` de STYLES.

```
make init-gwc-filters LAYERS="general:cuerpos_de_agua_50k"
make init-gwc-filters LAYERS="economia:cultivos=prediccion = 'Agave'"
make init-gwc-filters LAYERS="general:cuerpos_de_agua_50k;economia:cultivos=prediccion = 'Agave'"
```

Los valores de CQL llevan espacios, asi que **el target cita `$(LAYERS)`**: sin las comillas el
shell partia `economia:cultivos=prediccion = 'Agave'` en tres argumentos y trataba `Agave` como si
fuera una capa. Para varias capas en una sola invocacion se separan con `;`, porque desde make el
valor llega siempre como un unico argumento.

Verificado sobre `economia:cultivos`: primera peticion MISS, segunda **HIT**. Y un valor de CQL no
declarado se sigue sirviendo con HTTP 200 e imagen — simplemente no se cachea, que es justo lo
deseado para la cola larga de fechas que el usuario elige a mano. Cada valor declarado multiplica
el disco del cache, que crece por combinacion de gridset x estilo x CQL x ENV.

### Agregado: `--learn`, que saca los valores del trafico real

Declarar los valores a mano casi nunca funciona: tienen que coincidir **byte a byte** con lo que
manda el visor, y mapalab envuelve el filtro de fecha en parentesis y combina varios con ` OR `.
`--learn` los lee del log del gateway —que ya registra el `request_uri` completo— y cae al audit
del monitor de GeoServer si no encuentra nada ahi. Probado: aprendio de una sola pasada el CQL de
`economia:cultivos` y siete combinaciones de fecha de una capa de delitos.

La segunda fuente exige activar el audit **desde la UI de GeoServer**: versionar un
`monitor.properties` no funciona porque GeoServer reescribe el archivo en cada arranque y devuelve
`audit.enabled` a `false`. Con el `storage=memory` por defecto su buffer rota en segundos, asi que
en la practica la fuente util es el log del gateway.

La logica quedo en `scripts/lib/gwc_filters.py` y `scripts/lib/gwc_learn.py` en vez de heredocs
dentro del shell.

### Corregido: el POST a GWC perdia los acentos

Se enviaba con `Content-Type: text/xml` sin charset, asi que el servidor asumia ISO-8859-1 y un
valor como `(prediccion = 'Maiz')` se guardaba mal: el filtro quedaba declarado pero no coincidia
nunca. Ahora va como `text/xml; charset=UTF-8` con `--data-binary`.

Procedimiento y diagnostico en `runbook/sextante.md`.

## [2.0.0] - 2026-07-31

### Cambiado: el servicio pasa a llamarse sextante

El repo, el proyecto de Compose, los contenedores, la red interna, el slug de `/ontoy` y **la URL
pública** dejan de llamarse `geoserver`. El software sigue siendo GeoServer: lo que cambia es el
nombre del servicio del ecosistema, que ahora coincide con el del módulo del CMS de mariachi que
lo administra.

| | Antes | Ahora |
|---|---|---|
| Repo y ruta | `/IIEG/geoserver` | `/IIEG/sextante` |
| Contenedores | `geoserver`, `geoserver-version-api` | `sextante`, `sextante-version-api` |
| Red del proyecto | `geonetwork` | `sextante-net` |
| URL pública | `/geoserver/…` | `/sextante/…` |
| Variable del gateway | `GEOSERVER_HOST` | `SEXTANTE_HOST` |

Las variables `GEOSERVER_*` del `.env` **no** se renombran: son del software y las consume la
imagen kartoza. Igual `geoserver_data/`, que es el data dir de GeoServer.

### Agregado: `GEOSERVER_CONTEXT_ROOT` para servir bajo `/sextante`

La imagen kartoza renombra el webapp al arrancar, así que la ruta cambia de verdad — no es un
alias del proxy: dentro del contenedor `/geoserver/` responde 404. Todo lo que construía URLs a
mano quedó parametrizado con la variable: el `healthcheck` del compose, `wait_geoserver` y
`set_charset` en `make/repo.sh`, los cuatro `scripts/init-*.sh` y `proxy_server.py`.

`GEOSERVER_PROXY_BASE_URL` apunta ahora a `/sextante`, así que los GetCapabilities anuncian la
ruta nueva y los clientes migran solos conforme la refrescan.

### Agregado: compatibilidad indefinida para las URLs `/geoserver/…`

Los clientes WMS/WFS externos (QGIS, ArcGIS, portales de otras dependencias) tienen la URL vieja
guardada y no hay forma de inventariarlos. gateway-hub incluye
`nginx/includes/sextante-compat-geoserver.inc`, que mantiene la ruta anterior sirviendo:

- OGC (`ows`, `wms`, `wfs`, `wcs`, `gwc`) con `rewrite … last`, de modo que el tráfico vuelve a
  entrar por los `location` de `/sextante/` y conserva caché, rate limit y bot-protection sin
  duplicar configuración.
- `web`, `rest`, `j_spring_security` y `ontoy` con `301` a su equivalente en `/sextante/`.

No tiene fecha de caducidad técnica. Antes de retirarlo hay que medir el tráfico residual de
`/geoserver/` por `Referer` y `User-Agent` en los logs del gateway.

**Efecto conocido:** durante la convivencia el caché del gateway guarda dos entradas por tile,
porque `proxy_cache_key` usa `$request_uri` y `rewrite` no lo reescribe.

### Cambiado: los repos que lo consumen

- **gateway-hub**: `upstream sextante`, includes renombrados, zonas `sextante_cache` y
  `sextante_download`, caché en `/var/cache/nginx/sextante`, `robots.txt` y las listas de
  `envsubst` del `Dockerfile`. **Requiere rebuild de la imagen**: los includes viajan dentro.
- **mariachi** y **mapalab**: `GEOSERVER_URL` y `VITE_GEOSERVER_URL` a `/sextante/`. El de mapalab
  es build-time, así que necesita rebuild del frontend.
- **huachicol**: slug `sextante`, etiqueta `Sextante` y el sidecar en `sextante-version-api:8088`.

## [1.33.0] - 2026-07-31

### Cambiado: GeoServer 2.28.4 a 3.0.0

Primera version mayor del proyecto GeoServer. El salto arrastra toda la plataforma: **Java 17 a
21.0.11**, **Tomcat 9 a 11.0.24** (Jakarta EE Servlet 6.1), GeoTools 34.4 a 35 y GeoWebCache
1.28.4 a 2.0.0. El motor de proceso de imagenes pasa de JAI a **ImageN**.

Las 153 capas y los 12 workspaces quedaron identicos, `resourceErrorHandling` no reporto ninguna
capa saltada y el arranque no tomo mas tiempo que en 2.28.4 (18 s).

Verificado tras un ciclo `down`/`up` completo: WMS 1.1.1 y 1.3.0, WFS 1.0.0 y 2.0.0, WCS 1.0.0,
1.1.1 y 2.0.1, GetMap vectorial y de mosaico con dimension `TIME`, GetFeature en GeoJSON y
GeoPackage, y las 23 fuentes Garet.

### Cambiado: el bloque `<jai>` de `global.xml` se reduce a siete claves

ImageN es Java puro, asi que desaparecen los ajustes de aceleracion nativa y los de JAI-EXT. Del
template se retiraron `pngAcceleration`, `jpegAcceleration`, `allowNativeMosaic`,
`allowNativeWarp`, `pngEncoderType` y el bloque `<jaiext>` completo con sus 22 operadores. El
elemento `<jai>` **sigue existiendo** y conserva `allowInterpolation`, `recycling`, `tilePriority`,
`tileThreads`, `memoryCapacity`, `memoryThreshold` e `imageIOCache`.

La lista se tomo del `global.xml` de referencia que la propia imagen trae en
`/usr/local/tomcat/data/global.xml`, no de la documentacion: es la forma de saber que acepta la
version sin arriesgar el data dir real.

### Sin impacto: los modulos que 3.0 degrado a extension

GeoServer 3 saca del core WCS 1.0 y 1.1, WorldImage, ArcGRID y KML, y elimina el datastore H2.
Nada de eso nos afecta: la imagen kartoza los sigue empacando —WCS 1.0/1.1, KML y KMZ responden
igual que antes— y el despliegue no usa H2, WorldImage ni ArcGRID. Los rasters son GeoTIFF sobre
ImageMosaic con indice shapefile, y no hay NetCDF.

### Sin cambios: el tuning de JVM sobrevive a Java 21

`INITIAL_MEMORY`, `MAXIMUM_MEMORY` y `ADDITIONAL_JAVA_STARTUP_OPTIONS` se siguen aplicando igual y
no hay duplicacion de flags. Medido en produccion: Metaspace 139 MB contra un tope de 1 GB, old
gen 22 MB de 756 MB y cero full GC. La trampa de `jstat -gcutil` sigue vigente — su columna `M`
marca 99 % porque es `used/committed`, no `used/max`; hay que usar `-gc`.

## [1.32.0] - 2026-07-31

### Cambiado: GeoServer 2.27.0 a 2.28.4

Escala previa al salto a GeoServer 3. La documentacion oficial solo garantiza la migracion del
directorio de datos **desde 2.28.x**, asi que 2.27 no es un origen soportado para el 3.0. Sube
GeoTools de 33 a 34.4 y GeoWebCache de 1.27.0 a 1.28.4; Tomcat y Java no cambian. Las 153 capas y
los 12 workspaces quedaron identicos.

### Cambiado: las extensiones se activan con `STABLE_EXTENSIONS`

`geopkg-output-plugin` y `wps-download-plugin` ya vienen dentro de la imagen kartoza y se activan
con una variable. Se retiraron los seis bind mounts de JARs, `scripts/fetch-plugins.sh` y el
target `plugins-fetch`, que descargaban a mano unos JARs que ademas habia que mantener alineados
a la version de GeoServer. Verificado: `geopkg` aparece como formato de salida WFS y los procesos
`gs:Download*` en las capabilities de WPS.

### Corregido: los bind mounts `:ro` tumbaban el arranque en 2.28.4

2.28.4 reescribio `fix_permissions` para hacer `chown` sobre sus directorios, y el entrypoint
corre con `set -e`: cualquier bind mount de solo lectura en esas rutas aborta el arranque. El
contenedor quedaba en crashloop con
`chown: changing ownership of '/usr/share/fonts/custom': Read-only file system`.

Las rutas afectadas son `/usr/share/fonts/`, el `data_dir`, `/settings`, `/scripts` y
`/docker-entrypoint-geoserver.d` — es decir, tambien las vias "oficiales" de configuracion
externa de la imagen. La unica ruta que kartoza no toca es `/opt/geoserver/`, asi que todo lo
montado en solo lectura vive ahi y `entrypoint-wrapper.sh` lo copia a su destino final:
`wms.xml`, `wfs.xml`, `csp.xml` al data dir y las fuentes a `/usr/share/fonts/opentype`.

### Corregido: el `server.xml` propio nunca se estaba aplicando

El wrapper lo escribia en `/usr/local/tomcat/conf/server.xml` y despues la imagen lo regeneraba
con `xsltproc` en `setup_tomcat_ssl_status`, pisandolo. Ahora se escribe en `/settings/server.xml`,
que esa misma funcion copia tal cual cuando existe. Verificado: el connector ya sale con
`proxyName`, `scheme` y `secure` propios.

### Eliminado: `generate_config` y `apply_global_config`

Hacian `envsubst` en el host hacia `server.xml` y `config/global.xml`, archivos que el compose no
monta — el wrapper hace ese mismo reemplazo dentro del contenedor sobre los `.template`. Y
`apply_global_config` copiaba al data dir desde el host, donde el usuario no tiene permiso de
escritura (el directorio es del uid 2000): fallaba en silencio por su `|| true`. Con ellas se
retiran el target `_generate-config` y sus llamadas en `up`, `deploy` y `restore`.

### Corregido: `make backup` dejaba `.tmp` huerfanos

Solo borraba `global.xml.*.tmp`; el data dir acumulaba ademas `wfs.xml.*.tmp` (habia siete). El
`find` ahora cubre los tres patrones. `restore` extrae unicamente `data_dir`, asi que sigue
aceptando los respaldos anteriores, que incluian `plugins/`.

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
