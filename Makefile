# Tor Static Builder Makefile
# Builds statically linked Tor libraries for embedding in Go binaries

.PHONY: all help build build-docker build-local clean test test-examples \
        test-basic test-onion rebuild-tor fix-tor install-deps

# Default build directory (can be overridden)
BUILD_DIR ?= $(HOME)/tor-build
OUTPUT_DIR ?= $(PWD)/output

help:
	@echo "Tor Static Builder - Available commands:"
	@echo ""
	@echo "Building Tor:"
	@echo "  make all          - Build everything (libs + test examples)"
	@echo "  make build        - Build Tor static libraries (local system)"
	@echo "  make build-docker - Build Tor static libraries (Docker)"
	@echo "  make rebuild-tor  - Rebuild only Tor (after dependency build)"
	@echo "  make fix-tor      - Fix Tor build issues (systemd conflicts)"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Build and test Go examples"
	@echo "  make test-basic   - Build basic embedded Tor example"
	@echo "  make test-onion   - Build onion service example"
	@echo "  make run-basic    - Run the basic example"
	@echo "  make run-onion    - Run the onion service example"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Remove all build artifacts"
	@echo "  make clean-build  - Remove only build directory"
	@echo "  make check        - Verify build outputs exist"
	@echo "  make install-deps - Install required system dependencies"
	@echo ""
	@echo "Docker (optional):"
	@echo "  make build-docker - Build using Docker container"
	@echo "  make shell        - Start interactive Docker shell"

# Build everything
all: build test

# Default build uses local system
build: build-local

# Build on local system (default)
build-local: install-deps
	@echo "Building Tor static libraries locally..."
	@echo "Using BUILD_DIR=$(BUILD_DIR)"
	@echo "Using OUTPUT_DIR=$(OUTPUT_DIR)"
	@export BUILD_DIR="$(BUILD_DIR)" && \
	export OUTPUT_DIR="$(OUTPUT_DIR)" && \
	./build-tor-static.sh
	@$(MAKE) check

# Build using Docker (optional, for reproducibility)
build-docker:
	@echo "Building Tor static libraries using Docker..."
	@docker-compose up --build
	@echo "Build complete! Check ./output/ for results"
	@$(MAKE) check

# Install required build tools (Ubuntu/Debian)
# Note: Only build tools needed - all libraries are built from source!
install-deps:
	@echo "Checking/installing build tools (not libraries)..."
	@which gcc >/dev/null || (echo "Installing gcc..." && sudo apt-get update && sudo apt-get install -y gcc g++)
	@which automake >/dev/null || (echo "Installing autotools..." && sudo apt-get install -y automake autoconf libtool)
	@which pkg-config >/dev/null || (echo "Installing pkg-config..." && sudo apt-get install -y pkg-config)
	@which git >/dev/null || (echo "Installing git..." && sudo apt-get install -y git)
	@echo "Build tools ready (all libraries will be built from source)"

# Rebuild only Tor (useful after fixing issues)
rebuild-tor:
	@echo "Rebuilding Tor with fixes..."
	@cd $(BUILD_DIR)/tor-static/tor && \
	make clean 2>/dev/null || true && \
	./configure \
		--prefix="$(BUILD_DIR)/tor-static/tor/dist" \
		--enable-static-tor \
		--disable-asciidoc \
		--disable-manpage \
		--disable-html-manual \
		--disable-system-torrc \
		--disable-module-relay \
		--disable-module-dirauth \
		--disable-systemd \
		--disable-zstd \
		--disable-lzma \
		--with-libevent-dir="$(BUILD_DIR)/tor-static/libevent/dist" \
		--with-openssl-dir="$(BUILD_DIR)/tor-static/openssl/dist" \
		--with-zlib-dir="$(BUILD_DIR)/tor-static/zlib/dist" && \
	make -j$$(nproc)
	@echo "Creating combined libtor.a..."
	@cd $(BUILD_DIR)/tor-static/tor/src && \
	find . -name '*.a' ! -name '*-testing.a' -print0 | xargs -0 ar -x && \
	ar -rcs ../libtor.a *.o && \
	rm *.o
	@echo "Copying to output..."
	@mkdir -p $(OUTPUT_DIR)/lib
	@cp $(BUILD_DIR)/tor-static/tor/libtor.a $(OUTPUT_DIR)/lib/
	@echo "Tor rebuild complete!"

# Fix common Tor build issues
fix-tor:
	@echo "Applying Tor build fixes..."
	@echo "1. Ensuring systemd is disabled in build script..."
	@grep -q "disable-systemd" build-tor-static.sh || \
		sed -i '/disable-lzma/a\    --disable-systemd \\' build-tor-static.sh
	@echo "2. Ensuring correct tor_api.h is in place..."
	@if [ -f "$(BUILD_DIR)/tor-static/tor/src/feature/api/tor_api.h" ]; then \
		cp $(BUILD_DIR)/tor-static/tor/src/feature/api/tor_api.h $(OUTPUT_DIR)/include/; \
		echo "   Copied tor_api.h from Tor source"; \
	fi
	@echo "Fixes applied!"

# Build and test Go examples
test: test-examples

test-examples: test-basic test-onion
	@echo "All examples built successfully!"

# Build basic example
test-basic: check
	@echo "Building basic embedded Tor example..."
	@cd examples/basic && \
	CGO_ENABLED=1 go build -tags prod -o test-basic . && \
	echo "✓ Basic example built: $$(ls -lh test-basic | awk '{print $$5}')"

# Build onion service example  
test-onion: check
	@echo "Building onion service example..."
	@cd examples/onion-service && \
	CGO_ENABLED=1 go build -tags prod -o test-onion . && \
	echo "✓ Onion service example built: $$(ls -lh test-onion | awk '{print $$5}')"

# Run the basic example
run-basic: test-basic
	@echo "Running basic embedded Tor example..."
	@echo "Press Ctrl+C to stop"
	@cd examples/basic && ./test-basic

# Run the onion service example
run-onion: test-onion
	@echo "Running onion service example..."
	@echo "The onion address will be displayed when ready"
	@echo "Press Ctrl+C to stop"
	@cd examples/onion-service && ./test-onion

# Check that build outputs exist
check:
	@echo "Checking build outputs..."
	@if [ ! -f "$(OUTPUT_DIR)/lib/libtor.a" ]; then \
		echo "✗ libtor.a not found"; \
		echo "  Run 'make build' first"; \
		exit 1; \
	fi
	@if [ ! -f "$(OUTPUT_DIR)/include/tor_api.h" ]; then \
		echo "✗ tor_api.h not found"; \
		if [ -f "$(BUILD_DIR)/tor-static/tor/src/feature/api/tor_api.h" ]; then \
			echo "  Copying from Tor source..."; \
			mkdir -p $(OUTPUT_DIR)/include; \
			cp $(BUILD_DIR)/tor-static/tor/src/feature/api/tor_api.h $(OUTPUT_DIR)/include/; \
		else \
			echo "  Run 'make build' first"; \
			exit 1; \
		fi; \
	fi
	@echo "✓ libtor.a: $$(ls -lh $(OUTPUT_DIR)/lib/libtor.a | awk '{print $$5}')"
	@echo "✓ libssl.a: $$(ls -lh $(OUTPUT_DIR)/lib/libssl.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"
	@echo "✓ libcrypto.a: $$(ls -lh $(OUTPUT_DIR)/lib/libcrypto.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"
	@echo "✓ libevent.a: $$(ls -lh $(OUTPUT_DIR)/lib/libevent.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"
	@echo "✓ libz.a: $$(ls -lh $(OUTPUT_DIR)/lib/libz.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"
	@echo "✓ libcap.a: $$(ls -lh $(OUTPUT_DIR)/lib/libcap.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"

# Clean everything
clean: clean-build
	@echo "Cleaning output files..."
	@rm -rf $(OUTPUT_DIR)
	@rm -f examples/basic/test-basic
	@rm -f examples/onion-service/test-onion
	@docker-compose down -v 2>/dev/null || true
	@echo "Clean complete"

# Clean only build directory (preserve output)
clean-build:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "Build directory cleaned"

# Interactive shell in Docker container
shell:
	@echo "Starting interactive shell in build container..."
	@docker-compose run --rm tor-builder /bin/bash

# Show library sizes
sizes: check
	@echo "Library sizes:"
	@ls -lh $(OUTPUT_DIR)/lib/*.a | awk '{print $$9 ": " $$5}'
	@echo ""
	@echo "Total size: $$(du -sh $(OUTPUT_DIR)/lib | cut -f1)"

# Quick info about the build
info:
	@echo "Tor Static Builder Configuration:"
	@echo "  BUILD_DIR:  $(BUILD_DIR)"
	@echo "  OUTPUT_DIR: $(OUTPUT_DIR)"
	@echo ""
	@if [ -f "$(OUTPUT_DIR)/lib/libtor.a" ]; then \
		echo "Build status: ✓ Complete"; \
		echo ""; \
		$(MAKE) sizes; \
	else \
		echo "Build status: ✗ Not built"; \
		echo "Run 'make build' to build Tor static libraries"; \
	fi