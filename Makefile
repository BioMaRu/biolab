.DEFAULT_GOAL := help
.PHONY: help install dev web app build check fmt lint clean release watch mac mac-dev mac-run mac-dmg

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies (bun)
	bun install

dev: ## Run the desktop app in dev (native window + HMR)
	bun run tauri dev

web: ## Run just the SvelteKit UI in a browser (no native window)
	bun run --filter @biolab/desktop dev

app: ## Build the installable macOS .app / .dmg locally
	bun run tauri build

build: ## Production build of the SvelteKit frontend
	bun run build

check: ## Type-check (svelte-check)
	bun run check

fmt: ## Format everything with prettier
	bun run format

lint: ## Lint (stylelint + eslint where configured)
	bun run lint

clean: ## Remove build artifacts
	bun run clean

release: ## Cut a release: make release VERSION=0.2.0  (bumps, commits, tags, pushes → CI builds & publishes)
	@test -n "$(VERSION)" || { echo "Usage: make release VERSION=0.2.0"; exit 1; }
	bun scripts/bump-version.mjs $(VERSION)
	git commit -am "release: v$(VERSION)"
	git tag v$(VERSION)
	git push origin main --tags
	@echo "Pushed v$(VERSION). Watch the build with: make watch"

watch: ## Watch the latest GitHub Actions run
	gh run watch $$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')

mac: ## Build the native macOS app (apps/macos → dist/BioLab.app)
	cd apps/macos && ./build.sh

mac-dev: ## Fast debug build + launch of the native macOS app
	cd apps/macos && ./build.sh --debug --run

mac-run: ## Release build + launch of the native macOS app
	cd apps/macos && ./build.sh --run

mac-dmg: mac ## Build a polished install DMG (app + Applications, drag layout)
	cd apps/macos && ./make-dmg.sh
