REPO_NAME    := sextante
COMPOSE_PROD := -f compose.yaml
BACKUP_DIR   := backups

UP_GUARDS      = ensure_network; ensure_data_dirs
UP_POST        = run_step 'Esperar' wait_geoserver; set_charset; init_all
DEPLOY_GUARDS  = ensure_network; ensure_data_dirs
DEPLOY_CMD     = dc prod up -d --build --force-recreate
CLEAN_EXTRA    = clean_data_dir

include make/common.mk
include make/init.mk
include make/backup.mk
