#* ******************************************************************************
#*  If not stated otherwise in this file or this component's LICENSE
#*  file the following copyright and licenses apply:
#*
#*  Copyright 2026 RDK Management
#*
#*  Licensed under the Apache License, Version 2.0 (the License);
#*  you may not use this file except in compliance with the License.
#*  You may obtain a copy of the License at
#*
#*  http://www.apache.org/licenses/LICENSE-2.0
#*
#*  Unless required by applicable law or agreed to in writing, software
#*  distributed under the License is distributed on an AS IS BASIS,
#*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#*  See the License for the specific language governing permissions and
#*  limitations under the License.
#*
#* ******************************************************************************


.DEFAULT_GOAL := build

ROOT_DIR := $(CURDIR)

TARGET ?= linux
VARIANT ?= C

UT_DIR := $(ROOT_DIR)/ut-core

.PHONY: all build framework test clean dist_clean

all: build

build:
	@echo "========================================="
	@echo "Building Unified HALIF"
	@echo "TARGET  : $(TARGET)"
	@echo "VARIANT : $(VARIANT)"
	@echo "========================================="

	$(MAKE) -C $(UT_DIR) framework TARGET=$(TARGET) VARIANT=$(VARIANT)
	$(MAKE) -C $(UT_DIR) test TARGET=$(TARGET) VARIANT=$(VARIANT)

framework:
	$(MAKE) -C $(UT_DIR) framework TARGET=$(TARGET) VARIANT=$(VARIANT)

test:
	$(MAKE) -C $(UT_DIR) test TARGET=$(TARGET) VARIANT=$(VARIANT)

clean:
	@echo "Cleaning build artifacts..."
	@if [ -d "$(UT_DIR)" ]; then \
		$(MAKE) -C $(UT_DIR) cleanall || true; \
	fi
	rm -rf build

dist_clean: clean
	@echo "Removing framework and checked-out repositories..."
	rm -rf ut-core
	rm -rf vts_hal_test_components

help:
	@echo "Available targets:"
	@echo "  make build        - Build Unified HALIF"
	@echo "  make framework    - Build framework only"
	@echo "  make test         - Build tests only"
	@echo "  make clean        - Cleans the build folder"
	@echo "  make dist_clean   - Deletes all build and checkout folders"