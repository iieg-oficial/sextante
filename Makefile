.DiEFAULT_GOAL := help
BACKUP_DIR    := backups
BACKUP_FILE   ?= $(BACKUP_DIR)/geoserver_data_$(shell date +%Y%m%d_%H%M%S).tar.gz
RESTORE_FILE  ?= $(lastword $(sort $(wildcard $(BACKUP_DIR)/geoserver_data_*.tar.gz)))

.PHONY: help up down restart logs backup restore clean generate-config

help:
	@echo ""
	@echo "Uso: make [target]"
	@echo ""  @echo "  generate-config  Genera server.xml y config/global.xml desde .env"	@echo "  up           Levanta GeoServer e inicializa datastores"
	@echo "  down         Detiene GeoServer"
	@echo "  restart      Reinicia GeoServer"
	@echo "  logs         Muestra logs en tiempo real"
	@echo "  backup       Respalda geoserver_data/ en $(BACKUP_DIR)/"
	@echo "  restore      Restaura el backup más reciente (o RESTORE_FILE=ruta)"
	@echo "  clean        Detiene contenedor y elimina geoserver_data/"
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
	docker compose up -d
	@echo "Esperando que GeoServer esté listo..."
	@until docker exec geoserver curl -sf -u "$$(docker exec geoserver env | grep GEOSERVER_ADMIN_USER | cut -d= -f2):$$(docker exec geoserver env | grep GEOSERVER_ADMIN_PASSWORD | cut -d= -f2)" http://localhost:8080/geoserver/rest/about/version.json > /dev/null 2>&1; do \
		printf '.'; sleep 5; \
	done
	@echo ""
	@bash scripts/init-datastores.sh

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

backup:
	@mkdir -p $(BACKUP_DIR)
	@echo "Creando backup en $(BACKUP_FILE)..."
	@docker exec geoserver tar -czf - -C /opt/geoserver data_dir > $(BACKUP_FILE)
	@echo "Backup guardado: $(BACKUP_FILE)"

restore:
	@if [ -z "$(RESTORE_FILE)" ]; then \
		echo "Error: no se encontró ningún backup en $(BACKUP_DIR)/"; exit 1; \
	fi
	@if [ ! -f "$(RESTORE_FILE)" ]; then \
		echo "Error: archivo no encontrado: $(RESTORE_FILE)"; exit 1; \
	fi
	@echo "Restaurando desde $(RESTORE_FILE)..."
	docker compose down
	rm -rf geoserver_data
	mkdir -p geoserver_data
	tar -xzf $(RESTORE_FILE) --strip-components=1 -C geoserver_data
	docker compose up -d
	@echo "Restauración completa."

clean:
	@echo "Advertencia: esto eliminará geoserver_data/ permanentemente."
	@read -p "¿Continuar? [s/N]: " confirm && [ "$$confirm" = "s" ] || exit 1
	docker compose down
	rm -rf geoserver_data
	@echo "Limpieza completa."