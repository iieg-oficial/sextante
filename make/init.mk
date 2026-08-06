.PHONY: init-datastores init-gridsets init-cultivos-layer init-curvas-render-layer init-gwc-filters gwc-seed cron

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

gwc-seed: ## Pre-generar tiles de las capas de config/gwc-seed.txt (ARGS=--auto|--status|--stop)
	@$(LIB)
	banner 'GWC' 'seed'
	rule
	bash scripts/gwc-seed.sh $(ARGS)

cron: ## Instalar o desinstalar el cron del seed de GWC
	@$(LIB)
	banner 'CRON'
	action=$$(pick 'Accion' 'instalar' 'desinstalar')
	rule
	if [ "$$action" = 'instalar' ]; then cron_install; else cron_remove; fi
	rule
	printf '\n'
