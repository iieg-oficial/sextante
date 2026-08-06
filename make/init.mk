.PHONY: init-datastores init-gridsets init-cultivos-layer init-curvas-render-layer init-gwc-filters

##@ Inicializacion

init-datastores: ## Reapuntar los datastores al PostGIS del .env
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

init-curvas-render-layer: ## Publicar la capa de curvas de nivel subdividida (tabla de render)
	@$(LIB)
	banner 'INIT' 'curvas render'
	rule
	bash scripts/init-curvas-render-layer.sh

init-gwc-filters: ## Declarar parameter filters de GWC (ENV y CQL_FILTER) en una o mas capas
	@$(LIB)
	banner 'INIT' 'gwc filters'
	rule
	bash scripts/init-gwc-filters.sh "$(LAYERS)"
