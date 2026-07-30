.PHONY: backup restore

##@ Respaldos

backup: ## Respaldar geoserver_data y plugins en backups/
	@$(LIB)
	banner 'BACKUP'
	mkdir -p $(BACKUP_DIR)
	file=$(BACKUP_DIR)/geoserver_data_$$(date +%Y%m%d_%H%M%S).tar.gz
	docker exec -u root geoserver find /opt/geoserver/data_dir -name 'global.xml.*.tmp' -delete 2>/dev/null || true
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/.backup_staging
	mkdir -p .backup_staging
	run_step 'Extraer' bash -c 'docker exec -u root geoserver tar -cf - -C /opt/geoserver data_dir | tar -xf - -C .backup_staging'
	cp -r plugins .backup_staging/
	run_step 'Comprimir' tar -czf "$$file" -C .backup_staging data_dir plugins
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/.backup_staging
	rule
	printf '  %sBackup%s  %s (%s)\n\n' "$$C_GREEN" "$$C_RESET" "$$file" "$$(du -h "$$file" | cut -f1)"

restore: _generate-config ## Restaurar un respaldo, con selector
	@$(LIB)
	banner 'RESTORE'
	file=$$(pick_backup)
	row 'Archivo' "$$(du -h "$$file" | cut -f1)" "$$C_GREEN" "$$file"
	confirm 'Esto reemplaza geoserver_data/ y plugins/ por completo.' 'restaurar'
	rule
	run_step 'Down' dc prod down
	docker run --rm -v $(CURDIR):/data alpine rm -rf /data/geoserver_data /data/plugins
	run_step 'Extraer' tar -xzf "$$file"
	mv data_dir geoserver_data
	apply_global_config
	ensure_network
	run_step 'Up' dc prod up -d
	run_step 'Esperar' wait_geoserver
	run_step 'Admin' bash scripts/reset-admin.sh
	init_all
	rule
	printf '\n'
