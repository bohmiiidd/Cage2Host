#!/usr/bin/make -f

SHELL := /bin/bash

# ==========================================
#  CONFIGURATION
# ==========================================
BASE_DIR := $(shell pwd)

START      := $(BASE_DIR)/start.sh
BUILDER    := $(BASE_DIR)/core/build-routes.sh
BUILD_SFX  := $(BASE_DIR)/core/build.sh
ROUTES     := $(BASE_DIR)/config/routes.conf

# ==========================================
#  COLORS
# ==========================================
GREEN  = \033[1;32m
RED    = \033[1;31m
BLUE   = \033[1;34m
YELLOW = \033[1;33m
RESET  = \033[0m

# ==========================================
#  DEFAULT TARGET
# ==========================================
.PHONY: all
all:
	@echo -e "$(BLUE)[INFO]$(RESET) Available commands:"
	@echo -e "  make install     – Build modules & routing"
	@echo -e "  make run         – Launch main tool"
	@echo -e "  make random      – Launch --random-mode"
	@echo -e "  make utility     – Launch --utility-mode"
	@echo -e "  make auto        – Launch auto-mode"
	@echo -e "  make list        – Show modules"
	@echo -e "  make exploits    – Show exploits"
	@echo -e "  make build       – Build standalone binary"
	@echo -e "  make clean       – Remove routing table"
	@echo -e "  make rebuild     – Clean + install"

# ==========================================
#  CHECKERS
# ==========================================
.PHONY: _check_start _check_builder

_check_start:
	@if [[ ! -f "$(START)" ]]; then \
		echo -e "$(RED)[ERROR]$(RESET) start.sh missing at: $(START)"; \
		exit 1; \
	fi

_check_builder:
	@if [[ ! -f "$(BUILDER)" ]]; then \
		echo -e "$(RED)[ERROR]$(RESET) build-routes.sh missing at: $(BUILDER)"; \
		exit 1; \
	fi

# ==========================================
#  INSTALLATION
# ==========================================
.PHONY: install
install: _check_builder
	@echo -e "$(BLUE)[INFO]$(RESET) Setting execution permissions..."
	@chmod -R +x modules/* bin/* core/* utility/* themes/* 2>/dev/null || true
	@echo -e "$(GREEN)[OK]$(RESET) Permissions applied."

	@echo -e "$(BLUE)[INFO]$(RESET) Building routing table & modules..."
	@bash "$(BUILDER)"
	@echo -e "$(GREEN)[OK]$(RESET) Module build complete."

# ==========================================
#  RUNTIME MODES
# ==========================================
.PHONY: run random utility auto list exploits

run: _check_start
	@echo -e "$(BLUE)[RUN]$(RESET) Launching tool..."
	@bash "$(START)"

random: _check_start
	@echo -e "$(BLUE)[RAND]$(RESET) Launching random-mode..."
	@bash "$(START)" --random-mode

utility: _check_start
	@echo -e "$(BLUE)[UTIL]$(RESET) Launching utility-mode..."
	@bash "$(START)" --utility-mode

auto: _check_start
	@echo -e "$(BLUE)[AUTO]$(RESET) Launching auto-mode..."
	@bash "$(START)" --auto

list: _check_start
	@echo -e "$(BLUE)[INFO]$(RESET) Listing modules..."
	@bash "$(START)" --list-modules

exploits: _check_start
	@echo -e "$(BLUE)[INFO]$(RESET) Listing exploits..."
	@bash "$(START)" --list-exploits

# ==========================================
#  BUILD STANDALONE BINARY
# ==========================================
.PHONY: build
build:
	@echo -e "$(BLUE)[BUILD]$(RESET) Generating standalone binary..."
	@bash "$(BUILD_SFX)"
	@echo -e "$(GREEN)[OK]$(RESET) Built → dist/escaper"

# ==========================================
#  CLEAN + REBUILD
# ==========================================
.PHONY: clean rebuild

clean:
	@echo -e "$(YELLOW)[WARN]$(RESET) Removing routing table..."
	@rm -f "$(ROUTES)"
	@echo -e "$(GREEN)[OK]$(RESET) routes.conf removed."

rebuild: clean install
	@echo -e "$(GREEN)[OK]$(RESET) Rebuild complete."
