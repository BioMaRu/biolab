.DEFAULT_GOAL := help
.PHONY: help build dev clean watch mac mac-dev mac-run mac-dmg

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: mac ## Build the native macOS app

dev: mac-dev ## Fast debug build + launch

clean: ## Remove native build artifacts
	rm -rf apps/macos/.build apps/macos/dist

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
