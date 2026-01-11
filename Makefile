.DEFAULT_GOAL := help

APP_DIR := lexilingo_app
FLUTTER ?= flutter
DART ?= dart

.PHONY: help
help: ## Show available commands
	@printf "LexiLingo helpers (run from repo root)\n\n"
	@printf "Usage:\n  make <target>\n\n"
	@printf "Targets:\n"
	@grep -E '^[a-zA-Z0-9_\-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

.PHONY: doctor
doctor: ## Run flutter doctor in $(APP_DIR)
	@cd $(APP_DIR) && $(FLUTTER) doctor

.PHONY: get
get: ## Run flutter pub get in $(APP_DIR)
	@cd $(APP_DIR) && $(FLUTTER) pub get

.PHONY: clean
clean: ## Clean Flutter build outputs in $(APP_DIR)
	@cd $(APP_DIR) && $(FLUTTER) clean

.PHONY: analyze
analyze: ## Analyze Dart code in $(APP_DIR)
	@cd $(APP_DIR) && $(FLUTTER) analyze

.PHONY: format
format: ## Format Dart code in $(APP_DIR)
	@cd $(APP_DIR) && $(DART) format .

.PHONY: test
test: ## Run Flutter tests in $(APP_DIR)
	@cd $(APP_DIR) && $(FLUTTER) test

.PHONY: run-web
run-web: ## Run app on Chrome (web)
	@cd $(APP_DIR) && $(FLUTTER) run -d chrome

.PHONY: run-ios
run-ios: ## Run app on iOS simulator (macOS only)
	@cd $(APP_DIR) && $(FLUTTER) run -d ios

.PHONY: run-android
run-android: ## Run app on Android device/emulator
	@cd $(APP_DIR) && $(FLUTTER) run -d android

.PHONY: build-web
build-web: ## Build web release bundle
	@cd $(APP_DIR) && $(FLUTTER) build web

.PHONY: build-apk
build-apk: ## Build Android APK release
	@cd $(APP_DIR) && $(FLUTTER) build apk
