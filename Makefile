REPO_NAME    := geoserver
COMPOSE_PROD := -f compose.yaml
BACKUP_DIR   := backups

UP_PRE        := _generate-config plugins-fetch
UP_GUARDS      = ensure_network; apply_global_config
UP_POST        = run_step 'Esperar' wait_geoserver; set_charset; init_all
DEPLOY_PRE    := _generate-config plugins-fetch
DEPLOY_GUARDS  = ensure_network; apply_global_config
DEPLOY_CMD     = dc prod up -d --build --force-recreate
CLEAN_EXTRA    = clean_data_dir

include make/common.mk
include make/init.mk
include make/backup.mk
