# Plugins de GeoServer

Inventario de extensiones disponibles en este despliegue, divididas en:

1. **Cargadas de fabrica** — ya en el classpath de Tomcat, sin gestion local.
2. **Activadas por `STABLE_EXTENSIONS`** — vienen dentro de la imagen y se encienden por nombre.
3. **Recomendados a futuro** — extensiones que tienen sentido para el ecosistema IIEG pero aun no estan instaladas.

Version base: GeoServer `2.28.4` (imagen `kartoza/geoserver:2.28.4`).

Desde 1.32.0 **no hay JARs bajo gestion local**. La imagen kartoza empaca el catalogo completo de
extensions estables en `/stable_plugins` y las instala al arrancar segun la variable
`STABLE_EXTENSIONS`. Esto elimina la clase entera de errores por mezclar versiones de JAR con la
version de GeoServer.

---

## 1. Cargadas de fabrica

Estas extensiones vienen ya empacadas y activas en la imagen. No requieren configuracion adicional
para estar en el classpath; algunas necesitan habilitarse via `data_dir/*.xml`.

| Extension | Servicio / Funcion | Estado actual |
|---|---|---|
| `gs-control-flow` | Limites de concurrencia (OWS, user, IP, rate) | Activo. Config: `geoserver_data/controlflow.properties` |
| `gs-monitor-core` | Monitor de requests con logging a BD/audit | Cargado, no configurado |
| `gs-gwc` + `gs-gwc-rest` + `gs-web-gwc` | GeoWebCache integrado | Activo. Config: `geoserver_data/gwc-gs.xml` |
| `gs-inspire` | INSPIRE metadata extension | Cargado, no usado |
| `gs-csw-core` + `gs-csw-iso` + `gs-web-csw` | Catalogue Service for the Web (ISO 19115/19139) | Cargado, no configurado |
| `gs-vectortiles` | Output vector tiles (MVT, GeoJSON, TopoJSON) en WMS GetMap | Cargado. Util si mapalab migra a `TileWMS` |
| `gs-gdal` | Output formats via GDAL (KMZ, varios raster) | Cargado |
| `gs-libjpeg-turbo` | Codec JPEG acelerado | Cargado |
| `gs-kml` | Output KML | Cargado. **En GeoServer 3 pasa a ser extension aparte** |
| `gs-wcs2` | Web Coverage Service 2.0 | Activo |
| `gs-wps-core` + `gs-web-wps` + `gs-wps-kml-ppio` | Web Processing Service base (~194 procesos: vector, raster, geometry) | **Activo**. Config: `geoserver_data/wps.xml`. Limites en `controlflow.properties` (`user.ows.wps.execute=1000/d;30s`) |
| `gs-sec-jdbc` + `gs-sec-ldap` | Auth providers JDBC/LDAP | Cargados, no usados (auth local en `users.xml`) |
| `gs-restconfig-*` | REST API para WCS/WFS/WMS/WMTS config | Activo. Usado por `mariachi` y `init-datastores.sh` |

> Para inventario en vivo:
> ```bash
> docker exec geoserver ls /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ | grep -E "^gs-" | sort
> ```

---

## 2. Activadas por `STABLE_EXTENSIONS`

Se declaran por nombre, separadas por coma, en el `.env`:

```
STABLE_EXTENSIONS=geopkg-output-plugin,wps-download-plugin
```

El entrypoint las instala al arrancar y reporta cada una en el log
(`[Entrypoint] Extension already exists : <nombre>`).

### GeoPackage Output

Habilita `OUTPUTFORMAT=application/geopackage` en WMS GetMap y WFS GetFeature → descarga de capas
en `.gpkg` (formato moderno, soportado por QGIS y GDAL).

### WPS Download

Procesos `gs:Download`, `gs:DownloadEstimator`, `gs:DownloadMap` y `gs:DownloadAnimation` para
descargas de raster/vector (sync para volumenes pequenos, async para grandes con notificacion via
callback). Incluye mosaicos animados en MP4.

**Limites**: por default sin cap. Para acotarlos, crear `geoserver_data/wps-download.xml` con
`<maxFeatures>`, `<rasterSizeLimits>`, etc. Ver [docs.geoserver.org](https://docs.geoserver.org/2.28.x/en/user/extensions/wps-download/).

**Concurrencia**: las descargas async respetan el limite global
`user.ows.wps.execute=1000/d;30s` de `controlflow.properties`.

### Verificar que cargaron

```bash
curl -s "http://localhost:8080/geoserver/ows?service=WFS&version=2.0.0&request=GetCapabilities" | grep -i geopkg
curl -s "http://localhost:8080/geoserver/ows?service=WPS&version=1.0.0&request=GetCapabilities" | grep -o "gs:Download[A-Za-z]*"
```

---

## 3. Recomendados a futuro (no instalados)

Extensiones del catalogo oficial que pueden aportar valor al ecosistema IIEG. No se activan por
default para mantener el arranque ligero. Todas estan **ya dentro de la imagen**: basta agregarlas
a `STABLE_EXTENSIONS` y recrear el contenedor.

| Extension | Por que podria interesar | Cuando instalar |
|---|---|---|
| `wps-jdbc` | Persiste estados WPS async en BD (sobrevive a restarts) | Si `gs:Download` async se vuelve critico |
| `params-extractor` | Reescribe URLs WMS para SEO o aliases publicos | Si se quieren URLs limpias tipo `/mapa/cultivos` |
| `printing` (MapFish) | Genera PDFs de alta calidad de un mapa configurado | Si mapalab quiere "exportar mapa a PDF" del lado servidor |
| `mbstyle` | Soporte MapBox style spec ademas de SLD | Si se adoptan estilos MapBox/MapLibre |
| `ysld` | YAML SLD (mas legible que XML) | Mejora DX al editar estilos a mano |
| `css` | CSS-like styling | Idem ysld, alternativa a SLD |
| `importer` | Importer batch de capas desde la UI/REST | Si se automatiza ingest de shapefiles/GeoTIFFs |
| `netcdf-out` | Output WCS en NetCDF | Si se exponen rasters cientificos a consumidores cientificos |
| `ogcapi-features` | OGC API - Features (sucesor de WFS) | Cuando consumidores externos lo pidan |
| `mapml` | MapML output | Experimental, no urgente |
| `dxf`, `excel`, `charts` | Outputs alternativos (CAD, XLSX, graficas) | A demanda |

Extensiones que **NO** aplican al despliegue actual:

- `wps-cluster-hazelcast`: requiere cluster multi-nodo. GeoServer corre single-instance.
- `geofence` / `geofence-wps`: auth granular pero ya hay control de acceso via gateway-hub.
- `ogr-wfs` / `ogr-wps`: requieren `ogr2ogr` binario en el contenedor.
- `mongodb`, `oracle`, `mysql`, `sqlserver`: el unico datasource es PostGIS.
- `app-schema`: solo si hay XSDs complejos tipo INSPIRE Annex II/III.
- `h2`: **eliminada en GeoServer 3**.

---

## Como agregar un plugin nuevo

1. **Verificar que la imagen la trae**:

   ```bash
   docker exec geoserver cat /stable_plugins/stable_plugins.txt | tr ' ' '\n' | grep <nombre>
   ```

2. **Agregar el nombre** a `STABLE_EXTENSIONS` en el `.env` y en `.env.example`.

3. **Recrear el contenedor** y verificar:

   ```bash
   make up
   docker logs geoserver --tail 100 | grep -iE "error|exception"
   ```

4. **Documentar** el plugin en la seccion 2 de este archivo y en `docs/CHANGELOG.md`.

Si una extension **no** esta en el catalogo de la imagen, se puede montar su JAR a mano — pero
**nunca** dentro de una ruta que el entrypoint haga `chown` (`/usr/share/fonts/`, el `data_dir`,
`/settings`, `/scripts`, `/docker-entrypoint-geoserver.d`): desde 2.28.4 un bind mount `:ro` ahi
deja el contenedor en crashloop. Ver el gotcha en el contexto del repo.

---

## Backup y restore

Los plugins ya **no** son estado per-host: viven en la imagen. `make backup` y `make restore`
solo manejan `geoserver_data/`. Los respaldos anteriores a 1.32.0 incluyen un `plugins/` que
`restore` ignora al extraer.

---

## Referencias

- Catalogo oficial: [sourceforge.net/projects/geoserver/files/GeoServer/2.28.4/extensions/](https://sourceforge.net/projects/geoserver/files/GeoServer/2.28.4/extensions/)
