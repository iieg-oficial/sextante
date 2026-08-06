.PHONY: backup restore gwc-export gwc-import

##@ Respaldos

backup: ## Respaldar geoserver_data y plugins en backups/
	@$(LIB)
	banner 'BACKUP'
	mkdir -p $(BACKUP_DIR)
	file=$(BACKUP_DIR)/geoserver_data_$$(date +%Y%m%d_%H%M%S).tar.gz
	docker exec -u root sextante find /opt/geoserver/data_dir \( -name 'global.xml.*.tmp' -o -name 'wfs.xml.*.tmp' -o -name 'wms.xml.*.tmp' \) -delete 2>/dev/null || true
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/.backup_staging
	mkdir -p .backup_staging
	run_step 'Extraer' bash -c 'docker exec -u root sextante tar -cf - --exclude=data_dir/gwc --exclude=data_dir/heapdumps -C /opt/geoserver data_dir | tar -xf - -C .backup_staging'
	run_step 'Comprimir' tar -czf "$$file" -C .backup_staging data_dir
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/.backup_staging
	rule
	printf '  %sBackup%s  %s (%s)\n\n' "$$C_GREEN" "$$C_RESET" "$$file" "$$(du -h "$$file" | cut -f1)"

gwc-export: ## Empaquetar el cache de tiles para llevarlo a otro entorno (MAX_Z=13)
	@$(LIB)
	banner 'GWC' 'export'
	rule
	bash scripts/gwc-cache.sh export $(ARGS)

gwc-import: ## Restaurar un cache de tiles exportado (ARGS=<archivo>)
	@$(LIB)
	banner 'GWC' 'import'
	rule
	bash scripts/gwc-cache.sh import $(ARGS)

restore: ## Restaurar un respaldo, con selector
	@$(LIB)
	banner 'RESTORE'
	file=$$(pick_backup)
	row 'Archivo' "$$(du -h "$$file" | cut -f1)" "$$C_GREEN" "$$file"
	confirm 'Esto reemplaza geoserver_data/ por completo.' 'restaurar'
	rule
	run_step 'Down' dc prod down
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/geoserver_data /data/plugins
	run_step 'Extraer' tar -xzf "$$file" data_dir
	mv data_dir geoserver_data
	ensure_network
	run_step 'Up' dc prod up -d
	run_step 'Esperar' wait_geoserver
	run_step 'Admin' bash scripts/reset-admin.sh
	init_all
	rule
	printf '\n'
