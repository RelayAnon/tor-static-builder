# Tor Static Builder Makefile
# Builds statically linked Tor libraries for embedding in Go binaries

.PHONY: all help build build-docker build-local build-android build-android-docker \
        build-windows build-windows-docker \
        clean test test-examples test-basic test-onion rebuild-tor fix-tor install-deps \
        shell shell-android shell-windows sizes info check

# Default build directory (can be overridden)
BUILD_DIR ?= $(HOME)/tor-build
OUTPUT_DIR ?= $(PWD)/output

help:
	@echo "Tor Static Builder - Available commands:"
	@echo ""
	@echo "Building Tor (Linux):"
	@echo "  make all          - Build everything (libs + test examples)"
	@echo "  make build        - Build Tor static libraries (local system)"
	@echo "  make build-docker - Build Tor static libraries (Docker)"
	@echo "  make rebuild-tor  - Rebuild only Tor (after dependency build)"
	@echo "  make fix-tor      - Fix Tor build issues (systemd conflicts)"
	@echo ""
	@echo "Building Tor (Android):"
	@echo "  make build-android        - Build Android libraries (local, requires NDK)"
	@echo "  make build-android-docker - Build Android libraries (Docker)"
	@echo ""
	@echo "Building Tor (Windows):"
	@echo "  make build-windows        - Cross-compile Windows libraries (requires mingw-w64)"
	@echo "  make build-windows-docker - Cross-compile Windows libraries (Docker)"
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
	@echo "  make build-docker         - Build Linux libs using Docker"
	@echo "  make build-android-docker - Build Android libs using Docker"
	@echo "  make build-windows-docker - Build Windows libs using Docker"
	@echo "  make shell                - Start interactive Docker shell (Linux)"
	@echo "  make shell-android        - Start interactive Docker shell (Android)"
	@echo "  make shell-windows        - Start interactive Docker shell (Windows)"

# Build everything
all: build test

# Default build (non-Docker)
build: build-local

# Non-Docker build (default)
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

# Build Android libraries (non-Docker)
build-android:
	@echo "Building Tor static libraries for Android..."
	@if [ -z "$$ANDROID_NDK_HOME" ] && [ ! -d "$$HOME/Android/Sdk/ndk" ]; then \
		echo "Error: Android NDK not found!"; \
		echo "Please set ANDROID_NDK_HOME or install NDK to ~/Android/Sdk/ndk/"; \
		exit 1; \
	fi
	@echo "Using BUILD_DIR=$(BUILD_DIR)"
	@echo "Using OUTPUT_DIR=$(OUTPUT_DIR)"
	@export BUILD_DIR="$(BUILD_DIR)" && \
	export OUTPUT_DIR="$(OUTPUT_DIR)" && \
	./build-tor-android.sh
	@echo "Android build complete! Check ./output/android-* for results"

# Build Android libraries using Docker (includes NDK)
build-android-docker:
	@echo "Building Tor static libraries for Android using Docker..."
	@docker-compose up --build android-builder
	@echo "Android build complete! Check ./output/android-* for results"

# Build Windows libraries (cross-compilation from Linux)
build-windows:
	@echo "Cross-compiling Tor static libraries for Windows..."
	@if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then \
		echo "Error: MinGW-w64 cross-compiler not found!"; \
		echo "Please install mingw-w64:"; \
		echo "  Ubuntu/Debian: sudo apt-get install mingw-w64"; \
		echo "  Fedora: sudo dnf install mingw64-gcc mingw64-gcc-c++"; \
		exit 1; \
	fi
	@echo "Using BUILD_DIR=$(BUILD_DIR)"
	@echo "Using OUTPUT_DIR=$(OUTPUT_DIR)"
	@export BUILD_DIR="$(BUILD_DIR)" && \
	export OUTPUT_DIR="$(OUTPUT_DIR)" && \
	./build-tor-windows.sh
	@echo "Windows build complete! Check ./output/windows-amd64 for results"

# Build Windows libraries using Docker (cross-compilation)
build-windows-docker:
	@echo "Cross-compiling Tor static libraries for Windows using Docker..."
	@docker-compose up --build windows-builder
	@echo "Windows build complete! Check ./output/windows-amd64 for results"

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

# Check that build outputs exist (detects native architecture)
check:
	@echo "Checking build outputs..."
	@ARCH=$$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'); \
	CHECK_DIR="$(OUTPUT_DIR)/$$ARCH"; \
	echo "Checking $$CHECK_DIR..."; \
	if [ ! -f "$$CHECK_DIR/lib/libtor.a" ]; then \
		echo "✗ libtor.a not found in $$CHECK_DIR"; \
		echo "  Run 'make build' first"; \
		exit 1; \
	fi; \
	if [ ! -f "$$CHECK_DIR/include/tor_api.h" ]; then \
		echo "✗ tor_api.h not found"; \
		echo "  Run 'make build' first"; \
		exit 1; \
	fi; \
	echo "✓ libtor.a: $$(ls -lh $$CHECK_DIR/lib/libtor.a | awk '{print $$5}')"; \
	echo "✓ libssl.a: $$(ls -lh $$CHECK_DIR/lib/libssl.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"; \
	echo "✓ libcrypto.a: $$(ls -lh $$CHECK_DIR/lib/libcrypto.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"; \
	echo "✓ libevent.a: $$(ls -lh $$CHECK_DIR/lib/libevent.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"; \
	echo "✓ libz.a: $$(ls -lh $$CHECK_DIR/lib/libz.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"; \
	echo "✓ libcap.a: $$(ls -lh $$CHECK_DIR/lib/libcap.a 2>/dev/null | awk '{print $$5}' || echo 'not found')"

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

# Interactive shell in Android Docker container
shell-android:
	@echo "Starting interactive shell in Android build container..."
	@docker-compose run --rm android-builder /bin/bash

# Interactive shell in Windows Docker container
shell-windows:
	@echo "Starting interactive shell in Windows build container..."
	@docker-compose run --rm windows-builder /bin/bash

# Show library sizes
sizes: check
	@ARCH=$$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'); \
	CHECK_DIR="$(OUTPUT_DIR)/$$ARCH"; \
	echo "Library sizes ($$ARCH):"; \
	ls -lh $$CHECK_DIR/lib/*.a | awk '{print $$9 ": " $$5}'; \
	echo ""; \
	echo "Total size: $$(du -sh $$CHECK_DIR/lib | cut -f1)"

# Quick info about the build
info:
	@echo "Tor Static Builder Configuration:"
	@echo "  BUILD_DIR:  $(BUILD_DIR)"
	@echo "  OUTPUT_DIR: $(OUTPUT_DIR)"
	@echo ""
	@ARCH=$$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'); \
	CHECK_DIR="$(OUTPUT_DIR)/$$ARCH"; \
	if [ -f "$$CHECK_DIR/lib/libtor.a" ]; then \
		echo "Build status ($$ARCH): ✓ Complete"; \
		echo ""; \
		$(MAKE) sizes; \
	else \
		echo "Build status ($$ARCH): ✗ Not built"; \
		echo "Run 'make build' to build Tor static libraries"; \
	fi