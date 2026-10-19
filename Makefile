SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

API := services/api

.PHONY: help setup fmt lint test check scan build up down logs migrate shell clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

setup: ## Install dependencies and the git hooks (needs uv and pre-commit)
	cd $(API) && uv sync
	pre-commit install

fmt: ## Format all code
	cd $(API) && uv run ruff format . && uv run ruff check --fix .

lint: ## Lint and type-check everything (same as CI)
	cd $(API) && uv run ruff format --check . && uv run ruff check . && uv run mypy

test: ## Run the tests with the coverage gate (SQLite; set DATABASE_URL for PostgreSQL)
	cd $(API) && uv run pytest

check: lint test ## Everything CI runs before building images

scan: ## Secret and vulnerability scans (needs gitleaks and trivy)
	gitleaks git --redact --no-banner .
	trivy fs --scanners vuln,misconfig,secret --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 .

build: ## Build the container image
	docker compose build

up: ## Run PostgreSQL, local SQS and the API on :8000
	docker compose up --build --detach --wait
	docker compose ps

down: ## Stop and remove local containers (add `-v` by hand to drop the database volume)
	docker compose down --remove-orphans

logs: ## Follow logs of all services
	docker compose logs --follow

migrate: ## Apply database migrations to the local stack
	docker compose run --rm migrate

shell: ## Django shell against the local stack
	docker compose run --rm --entrypoint python api manage.py shell

clean: ## Remove build, test and cache artifacts
	rm -rf $(API)/.venv $(API)/.pytest_cache $(API)/.mypy_cache $(API)/.ruff_cache $(API)/.coverage
