.PHONY: build test lint clean format help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build all targets
	swift build

test: ## Run all tests
	swift test

lint: ## Lint with SwiftLint
	swiftlint lint --strict

format: ## Format with SwiftFormat (if available)
	swiftformat Sources/ Tests/ --swiftversion 5.9

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build/
