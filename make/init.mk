.PHONY: init-datastores init-gridsets init-cultivos-layer plugins-fetch _generate-config

##@ Inicializacion

init-datastores: _generate-config ## Reapuntar los datastores al PostGIS del .env
	@$(LIB)
	banner 'INIT' 'datastores'
	rule
	bash scripts/init-datastores.sh

init-gridsets: ## Crear o actualizar los gridsets de GWC via REST
	@$(LIB)
	banner 'INIT' 'gridsets'
	rule
	bash scripts/init-gridsets.sh

init-cultivos-layer: ## Provisionar la capa de cultivos
	@$(LIB)
	banner 'INIT' 'cultivos'
	rule
	bash scripts/init-cultivos-layer.sh

plugins-fetch: ## Descargar los JARs de extensions faltantes
	@$(LIB)
	banner 'PLUGINS'
	rule
	bash scripts/fetch-plugins.sh

_generate-config:
	@$(LIB)
	generate_config
