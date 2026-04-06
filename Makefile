.PHONY: build up down shell logs restart clean rebuild help

## ─── Auto-detecção do engine (Docker ou Podman) ──────────────────────────────
ENGINE := $(shell \
	if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then \
		echo docker; \
	elif command -v podman &>/dev/null; then \
		echo podman; \
	else \
		echo ""; \
	fi)

ifeq ($(ENGINE),docker)
  COMPOSE = docker compose
else ifeq ($(ENGINE),podman)
  COMPOSE = podman compose
else
  $(error Nenhum engine encontrado. Instale Docker ou Podman.)
endif

## ─── Variáveis ────────────────────────────────────────────────────────────────
SERVICE = ubuntu

## ─── Targets ──────────────────────────────────────────────────────────────────

help: ## Exibe esta ajuda
	@echo "  Engine detectado: \033[33m$(ENGINE)\033[0m"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Constrói a imagem
	$(COMPOSE) build

up: ## Sobe o container em background
	$(COMPOSE) up -d

down: ## Para e remove o container
	$(COMPOSE) down

shell: ## Entra no container com bash interativo
	$(COMPOSE) exec $(SERVICE) /bin/bash

logs: ## Exibe os logs do container em tempo real
	$(COMPOSE) logs -f $(SERVICE)

restart: ## Reinicia o container
	$(COMPOSE) restart $(SERVICE)

clean: ## Para o container e remove imagens/volumes órfãos
	$(COMPOSE) down --rmi local --volumes --remove-orphans

rebuild: clean build up ## Limpa tudo e reconstrói do zero
