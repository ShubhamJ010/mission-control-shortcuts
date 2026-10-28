# MCSC Makefile
# Standard development, build, and installation tasks

APP_NAME          := MCSC
BUNDLE_ID         := sj010.MCSC
INSTALL_DIR       := /Applications
APP_PATH          := $(INSTALL_DIR)/$(APP_NAME).app
DERIVED_DATA_PATH := build
BUILT_APP_PATH    := $(DERIVED_DATA_PATH)/Build/Products/Release/$(APP_NAME).app

# Auto-detect Xcode 27+ if available, fallback to active developer dir
XCODE_27_APP      := $(firstword $(wildcard /Applications/Xcode-27*.app /Applications/Xcode*27*.app))
DEVELOPER_DIR     ?= $(if $(XCODE_27_APP),$(XCODE_27_APP)/Contents/Developer,$(shell xcode-select -p))

# Code signing identity: auto-detect 'MCSC-Dev' if present in keychain, otherwise '-' (ad-hoc)
HAS_MCSC_DEV      := $(shell security find-identity -p codesigning -v 2>/dev/null | grep -q "MCSC-Dev" && echo 1 || echo 0)
ifeq ($(HAS_MCSC_DEV),1)
    CODE_SIGN_IDENTITY ?= MCSC-Dev
else
    CODE_SIGN_IDENTITY ?= -
endif

.PHONY: all help build run install stop clean reset-tcc lint format profile profile-live logs bench audit audit-stress audit-ci

all: help

help: ## Show this help message
	@echo "MCSC Build & Development CLI"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Signing Identity: $(CODE_SIGN_IDENTITY) (Pass CODE_SIGN_IDENTITY='...' to override)"

build: ## Build Release configuration
	@echo "==> Building $(APP_NAME) [Release] (Signing: $(CODE_SIGN_IDENTITY))..."
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme "$(APP_NAME)" \
		-configuration Release \
		-derivedDataPath "$(DERIVED_DATA_PATH)" \
		CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" \
		build

stop: ## Terminate running instance of MCSC
	@if pgrep -x "$(APP_NAME)" > /dev/null; then \
		echo "==> Stopping running $(APP_NAME)..."; \
		killall "$(APP_NAME)" 2>/dev/null || true; \
		TRIES=0; \
		while pgrep -x "$(APP_NAME)" > /dev/null; do \
			sleep 0.2; \
			TRIES=$$((TRIES + 1)); \
			if [ $$TRIES -ge 25 ]; then \
				echo "Force-stopping $(APP_NAME)..."; \
				killall -9 "$(APP_NAME)" 2>/dev/null || true; \
				break; \
			fi; \
		done; \
	fi

install: build stop ## Build Release and copy to /Applications
	@if [ ! -d "$(BUILT_APP_PATH)" ]; then \
		echo "Error: Built app not found at $(BUILT_APP_PATH)"; \
		exit 1; \
	fi
	@echo "==> Installing to $(APP_PATH)..."
	rm -rf "$(APP_PATH)"
	cp -R "$(BUILT_APP_PATH)" "$(APP_PATH)"
	@if [ "$(CODE_SIGN_IDENTITY)" = "-" ]; then \
		$(MAKE) reset-tcc; \
	fi

run: install ## Build, install to /Applications, and launch
	@echo "==> Launching $(APP_PATH)..."
	open "$(APP_PATH)"

reset-tcc: ## Reset macOS Accessibility permissions for MCSC
	@./scripts/reset-accessibility.sh

logs: ## Stream unified system logs for MCSC
	@./scripts/stream-logs.sh

audit: ## Audit memory budget and leaks (<=13MB)
	@./scripts/audit.sh --samples 3 --interval 1 --json build/benchmark_report.json

audit-stress: ## Audit memory with simulated Mission Control cycle
	@./scripts/audit.sh --stress --samples 3 --interval 1 --json build/benchmark_report.json

audit-ci: ## Audit memory in CI mode (fail if budget >13MB)
	@./scripts/audit.sh --ci --samples 3 --interval 1 --json build/benchmark_report.json

bench: audit ## Alias for audit
profile: audit ## Alias for audit

profile-live: ## Run 30-second live profiling listener during active use
	@./scripts/live-profile-listener.sh

lint: ## Run SwiftLint code analysis
	@swiftlint lint

format: ## Run SwiftFormat
	@swiftformat .

clean: stop ## Remove build outputs and DerivedData
	@echo "==> Cleaning build artifacts..."
	rm -rf "$(DERIVED_DATA_PATH)"
