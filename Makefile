.DEFAULT_GOAL := help
BACKUP_DIR    := backups
BACKUP_FILE   ?= $(BACKUP_DIR)/geoserver_data_$(shell date +%Y%m%d_%H%M%S).tar.gz
RESTORE_FILE_CANDIDATE_RESTORE := $(lastword $(sort $(wildcard restore/geoserver_data_*.tar.gz)))
RESTORE_FILE_CANDIDATE_BACKUP := $(lastword $(sort $(wildcard $(BACKUP_DIR)/geoserver_data_*.tar.gz)))
RESTORE_FILE  ?= $(if $(RESTORE_FILE_CANDIDATE_RESTORE),$(RESTORE_FILE_CANDIDATE_RESTORE),$(RESTORE_FILE_CANDIDATE_BACKUP))

.PHONY: help up down restart logs backup restore clean generate-config

help:
	@echo ""
	@echo "Uso: make [target]"
	@echo ""  
	@echo "  generate-config  	Genera server.xml y config/global.xml desde .env"
	@echo "  up           		Levanta GeoServer e inicializa datastores"
	@echo "  down         		Detiene GeoServer"
	@echo "  restart      		Reinicia GeoServer"
	@echo "  logs         		Muestra logs en tiempo real"
	@echo "  backup       		Respalda geoserver_data/ y plugins/ en $(BACKUP_DIR)/"
	@echo "  restore      		Restaura el backup más reciente (o RESTORE_FILE=ruta)"
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

up: generate-config
	@cp -f config/global.xml geoserver_data/global.xml 2>/dev/null && chmod 666 geoserver_data/global.xml || true
	@docker network inspect dataengine-network >/dev/null 2>&1 || docker network create dataengine-network
	docker compose up -d
	@echo "Esperando que GeoServer esté listo..."
	@until docker exec geoserver curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do \
		printf '.'; sleep 5; \
	done
	@echo ""
	@docker exec geoserver curl -sf -u "$$(docker exec geoserver env | grep '^GEOSERVER_ADMIN_USER=' | cut -d= -f2):$$(docker exec geoserver env | grep '^GEOSERVER_ADMIN_PASSWORD=' | cut -d= -f2)" -X PUT -H "Content-Type: application/json" -d '{"global":{"settings":{"charset":"UTF-8"}}}' http://localhost:8080/geoserver/rest/settings > /dev/null 2>&1 || true
	@bash scripts/init-datastores.sh

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

backup:
	@mkdir -p $(BACKUP_DIR)
	@echo ""
	@echo "═══ Backup GeoServer ═══"
	@echo "[1/5] Limpiando archivos temporales..."
	@docker exec geoserver find /opt/geoserver/data_dir -name "global.xml.*.tmp" -delete 2>/dev/null || true
	@echo "[2/5] Preparando staging..."
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
		echo "[5/5] Levantando contenedor..."; \
		docker network inspect dataengine-network >/dev/null 2>&1 || docker network create dataengine-network; \
		docker compose up -d; \
		echo "Esperando que GeoServer esté listo..."; \
		until docker exec geoserver curl -sf http://localhost:8080/geoserver/web/ > /dev/null 2>&1; do \
			printf '.'; sleep 5; \
		done; \
		echo ""; \
		bash scripts/init-datastores.sh; \
		echo ""; \
		echo "✓ Restauración completa."; \
		echo ""; \
	fi

clean:
	@echo "Advertencia: esto eliminará geoserver_data/ permanentemente."
	@read -p "¿Continuar? [s/N]: " confirm && [ "$$confirm" = "s" ] || exit 1
	docker compose down
	@docker run --rm -v $(CURDIR):/data alpine rm -rf /data/geoserver_data
	@echo "Limpieza completa."