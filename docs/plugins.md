# Plugins de GeoServer

Inventario de extensiones disponibles en este despliegue, divididas en:

1. **Bundled en la imagen kartoza** — ya cargadas en el classpath de Tomcat, sin gestion local.
2. **Bind-mounted desde `plugins/`** — JARs descargados manualmente y montados via `compose.yaml`. Gitignored.
3. **Recomendados a futuro** — extensiones que tienen sentido para el ecosistema IIEG pero aun no estan instaladas.

Version base: GeoServer `2.27.0` (imagen `kartoza/geoserver:2.27.0`). Toda extension instalada manualmente **debe matchear** la version 2.27.0 para evitar conflictos de classpath.

---

## 1. Bundled en kartoza/geoserver:2.27.0

Estas extensiones vienen ya empacadas en la imagen oficial. No requieren configuracion adicional para estar disponibles en el classpath; algunas necesitan habilitarse o configurarse via `data_dir/*.xml`.

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
| `gs-kml` | Output KML | Cargado |
| `gs-wcs2` | Web Coverage Service 2.0 | Activo |
| `gs-wps-core` + `gs-web-wps` + `gs-wps-kml-ppio` | Web Processing Service base (~194 procesos: vector, raster, geometry) | **Activo**. Config: `geoserver_data/wps.xml`. Limites en `controlflow.properties` (`user.ows.wps.execute=1000/d;30s`) |
| `gs-sec-jdbc` + `gs-sec-ldap` | Auth providers JDBC/LDAP | Cargados, no usados (auth local en `users.xml`) |
| `gs-restconfig-*` | REST API para WCS/WFS/WMS/WMTS config | Activo. Usado por `mariachi` y `init-datastores.sh` |

> Para inventario en vivo:
> ```bash
> docker exec geoserver ls /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/ | grep -E "^gs-" | sort
> ```

---

## 2. Bind-mounted desde `plugins/`

JARs descargados manualmente del SourceForge oficial de GeoServer y montados como volumenes `:ro` en `compose.yaml` → `/usr/local/tomcat/webapps/geoserver/WEB-INF/lib/`. El folder `plugins/` es **gitignored** y se incluye en los `tar.gz` de `make backup`.

### GeoPackage Output

Habilita `OUTPUTFORMAT=application/geopackage` en WMS GetMap y WFS GetFeature → descarga de capas en `.gpkg` (formato moderno, soportado por QGIS y GDAL).

| JAR | Tamano | Origen |
|---|---|---|
| `gs-geopkg-output-core-2.27.0.jar` | 5.3 KB | `geoserver-2.27.0-geopkg-output-plugin.zip` |
| `gs-geopkg-output-wfs-2.27.0.jar` | 9.4 KB | idem |
| `gs-geopkg-output-wms-2.27.0.jar` | 23.6 KB | idem |

### WPS Download

Procesos `gs:Download` y `gs:DownloadEstimator` para descargas grandes asincronas de raster/vector (sync para volumenes pequenos, async para volumenes grandes con notificacion via callback). Anade soporte de mosaicos animados (MP4) — de ahi la dependencia `jcodec`.

| JAR | Tamano | Origen |
|---|---|---|
| `gs-wps-download-2.27.0.jar` | 180 KB | `geoserver-2.27.0-wps-download-plugin.zip` |
| `jcodec-0.2.3.jar` | 2.0 MB | bundled en el zip oficial (dep de animaciones) |
| `jcodec-javase-0.2.3.jar` | 14 KB | bundled en el zip oficial |

**Limites**: por default sin cap. Si en algun momento conviene acotarlos, crear `geoserver_data/wps-download.xml` con `<maxFeatures>`, `<rasterSizeLimits>`, etc. Ver doc oficial: [docs.geoserver.org/2.27.x/en/user/extensions/wps-download/](https://docs.geoserver.org/2.27.x/en/user/extensions/wps-download/).

**Concurrencia**: las descargas async respetan el limite global `user.ows.wps.execute=1000/d;30s` ya definido en `controlflow.properties`.

---

## 3. Recomendados a futuro (no instalados)

Extensiones del catalogo oficial 2.27.0 que pueden aportar valor al ecosistema IIEG. No se instalan por default para mantener la imagen ligera.

| Extension | Por que podria interesar | Cuando instalar |
|---|---|---|
| `wps-jdbc` | Persiste estados WPS async en BD (sobrevive a restarts) | Si `gs:Download` async se vuelve critico |
| `params-extractor` | Reescribe URLs WMS para SEO o aliases publicos | Si se quieren URLs limpias tipo `/mapa/cultivos` en vez de `?LAYERS=recursos:cultivos` |
| `printing` (MapFish) | Genera PDFs de alta calidad de un mapa configurado | Si mapalab quiere "exportar mapa a PDF" del lado servidor |
| `mbstyle` | Soporte MapBox style spec ademas de SLD | Si se adoptan estilos MapBox/MapLibre |
| `ysld` | YAML SLD (mas legible que XML) | Mejora DX al editar estilos a mano |
| `css` | CSS-like styling | Idem ysld, alternativa a SLD |
| `importer` | Importer batch de capas desde la UI/REST | Si se automatiza ingest de shapefiles/GeoTIFFs |
| `netcdf-out` | Output WCS en NetCDF | Si se exponen rasters cientificos (temperatura, precipitacion) a consumidores cientificos |
| `ogcapi-features` | OGC API - Features (sucesor de WFS) | Cuando consumidores externos lo pidan |
| `mapml` | MapML output | Experimental, no urgente |
| `dxf`, `excel`, `charts` | Outputs alternativos (CAD, XLSX, graficas) | A demanda |

Extensiones que **NO** aplican al despliegue actual:

- `wps-cluster-hazelcast`: requiere cluster multi-nodo. GeoServer corre single-instance.
- `geofence` / `geofence-wps`: auth granular pero ya hay control de acceso via gateway-hub.
- `ogr-wfs` / `ogr-wps`: requieren `ogr2ogr` binario instalado en el contenedor (kartoza no lo trae).
- `mongodb`, `oracle`, `mysql`, `sqlserver`: el unico datasource es PostGIS.
- `app-schema`: solo si hay XSDs complejos tipo INSPIRE Annex II/III.

---

## Auto-fetch en bootstrap

`plugins/` esta gitignored, asi que un `git clone` limpio no trae los JARs. Para evitar tener que copiarlos manualmente entre hosts, hay un script idempotente que los descarga del SourceForge oficial:

- Script: [scripts/fetch-plugins.sh](../scripts/fetch-plugins.sh)
- Target: `make plugins-fetch`
- Integracion: corre automaticamente como prerequisito de `make up` y `make deploy`.

El script lleva un manifiesto declarativo inline con la lista de extensions a instalar y los JARs esperados de cada una. Para cada extension:

1. Si **todos** los JARs ya estan en `plugins/`, hace skip.
2. Si **al menos uno** falta, descarga el zip oficial, extrae unicamente los JARs declarados (no licencias ni README), y los coloca en `plugins/`.
3. No sobreescribe JARs ya presentes (`unzip -o` se invoca solo para los faltantes).

Esto cubre dos casos:

- **Clone limpio en host nuevo**: `make up` baja todo automaticamente.
- **JAR borrado o corrupto**: re-ejecutar `make plugins-fetch` lo recupera sin tocar el resto.

Para validar:

```bash
make plugins-fetch                                # primera vez: descarga
make plugins-fetch                                # segunda vez: [skip] todos los plugins
rm plugins/jcodec-0.2.3.jar                       # simular perdida
make plugins-fetch                                # solo baja lo faltante
```

---

## Como agregar un plugin nuevo

1. **Verificar disponibilidad** en [sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/](https://sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/). Anotar el nombre exacto del zip (sin el sufijo `-plugin.zip`).

2. **Descargar localmente** una vez para listar los JARs reales:

   ```bash
   curl -sL -o /tmp/ext.zip \
     "https://sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/geoserver-2.27.0-<nombre>-plugin.zip/download"
   unzip -l /tmp/ext.zip | grep '\.jar$'
   ```

3. **Filtrar duplicados con la imagen kartoza**:

   ```bash
   for f in <jars-del-zip>; do
     docker exec geoserver test -f /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/$f \
       && echo "DUPLICADO: $f" || echo "OK: $f"
   done
   ```

   Los duplicados deben **excluirse** del manifest (sobreescribirlos provoca `ClassCastException` si las versiones no matchean exactamente).

4. **Agregar al manifest** en [scripts/fetch-plugins.sh](../scripts/fetch-plugins.sh):

   ```bash
   PLUGINS=(
       ...
       "<nombre>|<jar1>,<jar2>,..."
   )
   ```

5. **Agregar bind mounts** en `compose.yaml` para cada JAR nuevo:

   ```yaml
   - ./plugins/<jar>:/usr/local/tomcat/webapps/geoserver/WEB-INF/lib/<jar>:ro
   ```

6. **Recrear contenedor** y verificar:

   ```bash
   make deploy
   docker logs geoserver --tail 100 | grep -iE "error|exception"
   ```

7. **Documentar** el plugin en este archivo (seccion 2) y en `docs/CHANGELOG.md`.

### Reglas

- **Solo JARs 2.27.0**. Mezclar versiones rompe el classpath silenciosamente (NoSuchMethodError).
- **No duplicar lo que ya trae la imagen** (`gs-wps-core`, `gs-monitor-core`, etc.).
- **Las dependencias transitivas del zip son obligatorias**. Ejemplo: `wps-download` requiere `jcodec` aunque no se use animaciones — sin el JAR el plugin no carga.

---

## Backup y restore

`Makefile` trata `plugins/` como **estado per-host** junto con `geoserver_data/`:

- `make backup` → copia `plugins/` al staging y lo incluye en el `tar.gz` final (junto al data_dir).
- `make restore` → borra `plugins/` y `geoserver_data/`, restaura ambos desde el tar.gz que se elija en el selector.
- `make clean` → borra `geoserver_data/` y los volumenes (destructivo, con confirmacion). **No toca `plugins/`**.

Dos caminos para que los JARs persistan en un host nuevo:

1. **Con backup previo**: `make restore` extrae `plugins/` del tar.gz elegido junto al data_dir.
2. **Sin backup**: `make up` corre `plugins-fetch` automaticamente y los baja de SourceForge segun el manifest en [scripts/fetch-plugins.sh](../scripts/fetch-plugins.sh).

---

## Referencias

- Catalogo oficial 2.27.0: [sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/](https://sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/)
- Doc por extension: [docs.geoserver.org/2.27.x/en/user/extensions/](https://docs.geoserver.org/2.27.x/en/user/extensions/)
- Imagen kartoza (inventario de JARs bundled): [github.com/kartoza/docker-geoserver](https://github.com/kartoza/docker-geoserver)
- Contexto general del despliegue: `repos/geoserver/contexto.md` en el repositorio central de contexto
