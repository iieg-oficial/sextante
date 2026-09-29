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

GeoServer del ecosistema IIEG: las capas WMS y WFS que consume el visor. Corre sobre
`kartoza/geoserver`, se expone por el gateway bajo `/sextante/` y lee sus capas de la PostgreSQL
de dataengine.

```bash
make up       # desarrollo
make deploy   # producción, con git pull y rebuild
```

## Qué corre aquí

| Contenedor | Qué hace |
|---|---|
| `sextante` | GeoServer 3.0.0 sobre Tomcat 11 y Java 21 |
| `sextante-docker-socket-proxy` | Acceso acotado al socket de Docker |
| `sextante-version-api` | Publica `/ontoy` para el monitoreo de huachicol |

## Comandos

`make up` · `deploy` · `down` · `restart` · `clean` · `logs` · `status` · `shell` ·
`backup` · `restore` · `cron`

Preparación de capas: `init-datastores`, `init-gridsets`, `init-gwc-filters`,
`init-cultivos-layer`, `init-curvas-render-layer`, `init-hexbin-layer`,
`init-terreno-rgb-layer`.

Caché de teselas: `gwc-seed`, `gwc-export`, `gwc-import`.

## Versiones

La versión vive en `VERSION`; el detalle de cada una, en [`docs/CHANGELOG.md`](docs/CHANGELOG.md).

La documentación vive en [context-ame-esta](https://github.com/iieg-oficial/context-ame-esta):
stack y gotchas en `repos/sextante/`, diagnóstico de incidentes en `runbook/sextante.md`.
