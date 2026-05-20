.DEFAULT_GOAL := help
BACKUP_DIR    := backups
BACKUP_FILE   ?= $(BACKUP_DIR)/geoserver_data_$(shell date +%Y%m%d_%H%M%S).tar.gz
RESTORE_FILE_CANDIDATE_RESTORE := $(lastword $(sort $(wildcard restore/geoserver_data_*.tar.gz)))
RESTORE_FILE_CANDIDATE_BACKUP := $(lastword $(sort $(wildcard $(BACKUP_DIR)/geoserver_data_*.tar.gz)))
RESTORE_FILE  ?= $(if $(RESTORE_FILE_CANDIDATE_RESTORE),$(RESTORE_FILE_CANDIDATE_RESTORE),$(RESTORE_FILE_CANDIDATE_BACKUP))

.PHONY: help up down restart build logs backup restore clean generate-config init-datastores version-json

help:
	@echo ""
	@echo "Uso: make [target]"
	@echo ""  
	@echo "  generate-config  	Genera server.xml y config/global.xml desde .env"
	@echo "  up           		Levanta GeoServer e inicializa datastores"
	@echo "  build        		Recrea contenedor con cambios de .env"
	@echo "  down         		Detiene GeoServer"
	@echo "  restart      		Reinicia GeoServer"
	@echo "  logs         		Muestra logs en tiempo real"
	@echo "  backup       		Respalda geoserver_data/ y plugins/ en $(BACKUP_DIR)/"
	@echo "  restore      		Restaura el backup más reciente (o RESTORE_FILE=ruta)"
	@echo "  init-datastores	Reapunta todos los datastores al PostGIS configurado en .env"
	@echo "  version-json    	Regenerar version-api/html/version.json desde VERSION"
	@echo "  clean        		Detiene contenedor y elimina geoserver_data/"
	@echo ""
	@echo "Ejemplos:"
	@echo "  make restore RESTORE_FILE=backups/geoserver_data_20260220_120000.tar.gz"
	@echo ""

generate-config:
	@echo "Generando configuración desde .env..."
	@set -a && . ./.env && set +a && \
		envsubst < server.xml.template > server.xml && \
		envsubst < config/global.xml.template > config/global.xml
	@echo "Archivos generados: server.xml, config/global.xml"

up: generate-config version-json
	@cp -f config/global.xml geoserver_data/global.xml 2>/dev/null && chmod 666 geoserver_data/global.xml || true
	@docker network inspect dataengine-network >/dev/null 2>&1 || docker network create dataengine-network
	docker compose up -d
	@echo "Esperando que GeoServer esté listo..."
	@attempts=0; max=24; \
	until docker exec geoserver curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do \
		attempts=$$((attempts+1)); \
		if [ $$attempts -ge $$max ]; then \
			echo ""; \
			echo "✗ GeoServer no respondió después de $$((max*5))s. Últimos logs:"; \
			docker logs geoserver --tail 20 2>&1; \
			exit 1; \
		fi; \
		printf '.'; sleep 5; \
	done
	@echo ""
	@docker exec geoserver curl -sf -u "$$(docker exec geoserver env | grep '^GEOSERVER_ADMIN_USER=' | cut -d= -f2):$$(docker exec geoserver env | grep '^GEOSERVER_ADMIN_PASSWORD=' | cut -d= -f2)" -X PUT -H "Content-Type: application/json" -d '{"global":{"settings":{"charset":"UTF-8"}}}' http://localhost:8080/geoserver/rest/settings > /dev/null 2>&1 || true
	@python3 scripts/optimize-cultivos.py
	@bash scripts/init-datastores.sh
	# PENDIENTE: remover cuando los URLChecks se provisionen via geoserver_data en bootstrap de produccion.
	@bash scripts/setup-urlchecks.sh

build: generate-config version-json
	@cp -f config/global.xml geoserver_data/global.xml 2>/dev/null && chmod 666 geoserver_data/global.xml || true
	@docker network inspect dataengine-network >/dev/null 2>&1 || docker network create dataengine-network
	docker compose up -d --force-recreate --build
	@echo "Esperando que GeoServer esté listo..."
	@attempts=0; max=24; \
	until docker exec geoserver curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do \
		attempts=$$((attempts+1)); \
		if [ $$attempts -ge $$max ]; then \
			echo ""; \
			echo "✗ GeoServer no respondió después de $$((max*5))s. Últimos logs:"; \
			docker logs geoserver --tail 20 2>&1; \
			exit 1; \
		fi; \
		printf '.'; sleep 5; \
	done
	@echo ""

down:
	docker compose down

restart: version-json
	docker compose restart

version-json:
	@SERVICE=geoserver; \
	 VERSION=$$(tr -d '[:space:]' < VERSION); \
	 RELEASED_AT=$$(grep -m1 "^## \[$$VERSION\]" docs/CHANGELOG.md | sed -E 's/^## \[[^]]+\] - ([0-9-]+).*/\1/'); \
	 if [ -z "$$RELEASED_AT" ]; then echo "WARN: no se encontro entrada '## [$$VERSION] - YYYY-MM-DD' en docs/CHANGELOG.md" >&2; fi; \
	 printf '{"version":"%s","service":"%s","released_at":"%s"}\n' "$$VERSION" "$$SERVICE" "$$RELEASED_AT" > version-api/html/version.json; \
	 echo "version.json -> $$VERSION ($$SERVICE, $$RELEASED_AT)"

logs:
	docker compose logs -f

backup:
	@mkdir -p $(BACKUP_DIR)
	@echo ""
	@echo "═══ Backup GeoServer ═══"
	@echo "[1/5] Limpiando archivos temporales..."
	@docker exec geoserver find /opt/geoserver/data_dir -name "global.xml.*.tmp" -delete 2>/dev/null || true
	# PENDIENTE: remover cuando el umask del entrypoint cree directorios con 755 (hoy a veces crea drw-r--r-- sin bit x y tar falla por Permission denied al hacer stat).
	@docker exec geoserver find /opt/geoserver/data_dir -type d ! -perm -u+x -exec chmod u+rx {} +
	@echo "[2/5] Preparando staging..."
	# PENDIENTE: si la corrida previa extrajo dirs con permisos malos del container, rm -rf no puede entrar a ellos. Arreglar primero.
	@chmod -R u+rwX .backup_staging 2>/dev/null || true
	@rm -rf .backup_staging && mkdir -p .backup_staging
	@echo "[3/5] Extrayendo data_dir del contenedor..."
	@docker exec geoserver tar -cf - -C /opt/geoserver data_dir | tar -xf - -C .backup_staging
	@echo "[4/5] Copiando plugins..."
	@cp -r plugins .backup_staging/
	@echo "[5/5] Comprimiendo backup (un punto = 1000 archivos)..."
	@tar -czf $(BACKUP_FILE) -C .backup_staging --checkpoint=1000 --checkpoint-action=exec='printf .' data_dir plugins && echo ''
	@rm -rf .backup_staging
	@FILESIZE=$$(du -h $(BACKUP_FILE) | cut -f1); \
		echo ""; \
		echo "✓ Backup guardado: $(BACKUP_FILE) ($$FILESIZE)"
	@echo ""

restore: generate-config
	@if [ -z "$(RESTORE_FILE)" ] || [ ! -f "$(RESTORE_FILE)" ]; then \
		echo "No se encontró ningún backup en restore/ ni en backups/."; \
	else \
		FILESIZE=$$(du -h "$(RESTORE_FILE)" | cut -f1); \
		echo ""; \
		echo "═══ Restore GeoServer ═══"; \
		echo "Archivo: $(RESTORE_FILE) ($$FILESIZE)"; \
		echo "[1/5] Deteniendo contenedor..."; \
		docker compose down; \
		echo "[2/5] Limpiando datos anteriores..."; \
		docker run --rm -v $(CURDIR):/data alpine rm -rf /data/geoserver_data /data/plugins; \
		echo "[3/5] Extrayendo backup (un punto = 1000 archivos)..."; \
		tar -xzf "$(RESTORE_FILE)" --checkpoint=1000 --checkpoint-action=exec='printf .' && echo ''; \
		mv data_dir geoserver_data; \
		echo "[4/5] Aplicando configuración..."; \
		cp -f config/global.xml geoserver_data/global.xml 2>/dev/null && chmod 666 geoserver_data/global.xml || true; \
		echo "[5/6] Levantando contenedor..."; \
		docker network inspect dataengine-network >/dev/null 2>&1 || docker network create dataengine-network; \
		docker compose up -d; \
		echo "Esperando que GeoServer esté listo..."; \
		attempts=0; max=24; \
		until docker exec geoserver curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do \
			attempts=$$((attempts+1)); \
			if [ $$attempts -ge $$max ]; then \
				echo ""; \
				echo "✗ GeoServer no respondió después de $$((max*5))s. Últimos logs:"; \
				docker logs geoserver --tail 20 2>&1; \
				exit 1; \
			fi; \
			printf '.'; sleep 5; \
		done; \
		echo ""; \
		echo "[6/6] Actualizando credenciales admin e inicializando datastores..."; \
		bash scripts/reset-admin.sh; \
		bash scripts/init-datastores.sh; \
		python3 scripts/optimize-cultivos.py; \
		echo ""; \
		echo "✓ Restauración completa."; \
		echo ""; \
	fi

init-datastores: generate-config
	@bash scripts/init-datastores.sh

clean:
	@echo "Advertencia: esto eliminará geoserver_data/ permanentemente."
	@read -p "¿Continuar? [s/N]: " confirm && [ "$$confirm" = "s" ] || exit 1
	docker compose down
	@docker run --rm -v $(CURDIR):/data alpine rm -rf /data/geoserver_data
	@echo "Limpieza completa."