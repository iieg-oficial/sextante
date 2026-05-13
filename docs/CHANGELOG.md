# Changelog

Todos los cambios notables del proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Versionado Semántico](https://semver.org/lang/es/).

## [No publicado]

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
