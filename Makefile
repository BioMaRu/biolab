.DEFAULT_GOAL := help
.PHONY: help install dev build format lint check clean tauri-build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies (bun)
	bun install

dev: ## Run the desktop app (native window)
	bun run tauri dev

build: ## Production build (SvelteKit)
	bun run build

tauri-build: ## Package the macOS .app / .dmg
	bun run tauri build

format: ## Format with prettier
	bun run format

lint: ## Lint (eslint + stylelint)
	bun run lint

check: ## Type-check (svelte-check)
	bun run check

clean: ## Remove build artifacts
	bun run clean
