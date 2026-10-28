.DEFAULT_GOAL := build

ROOT_DIR := $(CURDIR)

TARGET ?= linux
VARIANT ?= C

UT_DIR := $(ROOT_DIR)/ut-core

.PHONY: all build clean framework test

all: build

build:
	@echo "========================================="
	@echo "Building Unified HALIF"
	@echo "TARGET  : $(TARGET)"
	@echo "VARIANT : $(VARIANT)"
	@echo "========================================="

	$(MAKE) -C $(UT_DIR) framework
	$(MAKE) -C $(UT_DIR) test

framework:
	$(MAKE) -C $(UT_DIR) framework

test:
	$(MAKE) -C $(UT_DIR) test

clean:
	@if [ -d "$(UT_DIR)" ]; then \
		$(MAKE) -C $(UT_DIR) cleanall || true ; \
	fi

	rm -rf build
	rm -rf ut-core
	rm -rf vts_hal_test_components

.PHONY: all build clean framework test