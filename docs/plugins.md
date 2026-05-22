# Plugins de GeoServer

Inventario de extensiones disponibles en este despliegue, divididas en:

1. **Bundled en la imagen kartoza** — ya cargadas en el classpath de Tomcat, sin gestion local.
2. **Bind-mounted desde `plugins/`** — JARs descargados manualmente y montados via `docker-compose.yml`. Gitignored.
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

JARs descargados manualmente del SourceForge oficial de GeoServer y montados como volumenes `:ro` en `docker-compose.yml` → `/usr/local/tomcat/webapps/geoserver/WEB-INF/lib/`. El folder `plugins/` es **gitignored** y se incluye en los `tar.gz` de `make backup`.

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

## Como agregar un plugin nuevo

```bash
# 1. Bajar el zip de la extension (debe ser 2.27.0)
curl -sL -o /tmp/ext.zip \
  "https://sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/geoserver-2.27.0-<nombre>-plugin.zip/download"

# 2. Extraer SOLO los JARs (no licencias ni README)
cd /IIEG/geoserver/plugins
unzip -o -j /tmp/ext.zip "*.jar"

# 3. Verificar que los JARs no esten ya en la imagen
for f in *.jar; do
  docker exec geoserver test -f /usr/local/tomcat/webapps/geoserver/WEB-INF/lib/$f \
    && echo "DUPLICADO: $f (ya en imagen, borralo)" \
    || echo "OK: $f"
done

# 4. Agregar bind mounts a docker-compose.yml en el bloque volumes del servicio geoserver:
#    - ./plugins/<jar>:/usr/local/tomcat/webapps/geoserver/WEB-INF/lib/<jar>:ro

# 5. Recrear contenedor
make build

# 6. Verificar carga
docker logs geoserver --tail 100 | grep -iE "error|exception" | head -20
curl -s "http://localhost:8080/geoserver/web/" -o /dev/null -w "%{http_code}\n"
```

### Reglas

- **Solo JARs 2.27.0**. Mezclar versiones rompe el classpath silenciosamente (NoSuchMethodError).
- **No duplicar lo que ya trae la imagen** (`gs-wps-core`, `gs-monitor-core`, etc.). Sobreescribir un JAR bundled con un bind mount provoca `ClassCastException` si las versiones no matchean exactamente.
- **Las dependencias transitivas del zip son obligatorias**. Ejemplo: `wps-download` requiere `jcodec` aunque no se use animaciones — sin el JAR el plugin no carga.
- Documentar cada nuevo plugin en este archivo (seccion 2) y en `docs/CHANGELOG.md`.

---

## Backup y restore

`Makefile` trata `plugins/` como **estado per-host** junto con `geoserver_data/`:

- `make backup` → copia `plugins/` al staging y lo incluye en el `tar.gz` final (junto al data_dir).
- `make restore` → borra `plugins/` y `geoserver_data/`, restaura ambos desde el tar.gz mas reciente.
- `make clean` → borra `plugins/` (destructivo, con confirmacion).

Esto significa que al desplegar en un host nuevo restaurando un backup, **no hace falta volver a bajar los JARs**: vienen en el tar.gz. Solo asegurarse que el `docker-compose.yml` versionado tenga los mismos bind mounts.

---

## Referencias

- Catalogo oficial 2.27.0: [sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/](https://sourceforge.net/projects/geoserver/files/GeoServer/2.27.0/extensions/)
- Doc por extension: [docs.geoserver.org/2.27.x/en/user/extensions/](https://docs.geoserver.org/2.27.x/en/user/extensions/)
- Imagen kartoza (inventario de JARs bundled): [github.com/kartoza/docker-geoserver](https://github.com/kartoza/docker-geoserver)
- Contexto general del despliegue: [context.md](context.md)
