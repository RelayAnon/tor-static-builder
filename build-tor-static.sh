#!/bin/bash
# Build script for creating statically linked Tor libraries for Go embedding
# This script builds Tor 0.4.8.x with all dependencies statically linked

set -e

echo "======================================"
echo "Tor Static Builder for Go Embedding"
echo "======================================"

# Configuration
# Detect if running in Docker container
if [ -f /.dockerenv ]; then
    # Running in Docker
    BUILD_DIR="${BUILD_DIR:-/build}"
    OUTPUT_DIR="${OUTPUT_DIR:-/output}"
else
    # Running on host system
    BUILD_DIR="${BUILD_DIR:-$HOME/tor-build}"
    OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
fi
TOR_STATIC_REPO="https://github.com/cretz/tor-static.git"
LIBCAP_VERSION="2.69"
LIBCAP_URL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-${LIBCAP_VERSION}.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

cd "$BUILD_DIR"

# Step 1: Clone tor-static repository
log_info "Cloning tor-static repository..."
if [ ! -d "tor-static" ]; then
    git clone "$TOR_STATIC_REPO"
fi
cd tor-static

# Step 2: Initialize and update submodules
log_info "Initializing submodules..."
git submodule update --init --recursive

# Step 3: Build libcap from source
log_info "Building libcap from source..."
cd "$BUILD_DIR"
if [ ! -f "libcap-${LIBCAP_VERSION}.tar.gz" ]; then
    log_info "Downloading libcap ${LIBCAP_VERSION}..."
    wget "$LIBCAP_URL"
fi

tar xzf "libcap-${LIBCAP_VERSION}.tar.gz"
cd "libcap-${LIBCAP_VERSION}"

# Build libcap statically
log_info "Compiling libcap..."
make SHARED=no DESTDIR="$BUILD_DIR/tor-static/libcap/dist" prefix=/ install

# Step 4: Build all dependencies
cd "$BUILD_DIR/tor-static"

log_info "Building OpenSSL..."
cd openssl
./Configure no-shared no-dso linux-x86_64 --prefix="$BUILD_DIR/tor-static/openssl/dist"
make -j$(nproc)
make install_sw
cd ..

log_info "Building libevent..."
cd libevent
./autogen.sh
./configure --prefix="$BUILD_DIR/tor-static/libevent/dist" --disable-shared --enable-static --with-pic
make -j$(nproc)
make install
cd ..

log_info "Building zlib..."
cd zlib
./configure --prefix="$BUILD_DIR/tor-static/zlib/dist" --static
make -j$(nproc)
make install
cd ..

# Step 5: Build Tor with zstd disabled
log_info "Building Tor 0.4.8..."
cd tor

# Apply configuration
./autogen.sh
./configure \
    --prefix="$BUILD_DIR/tor-static/tor/dist" \
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
    --with-libevent-dir="$BUILD_DIR/tor-static/libevent/dist" \
    --with-openssl-dir="$BUILD_DIR/tor-static/openssl/dist" \
    --with-zlib-dir="$BUILD_DIR/tor-static/zlib/dist"

# Build Tor
make -j$(nproc)

# Combine all static libraries into libtor.a (excluding test libraries)
log_info "Creating combined libtor.a..."
cd src
find . -name '*.a' ! -name '*-testing.a' -exec ar -x {} \;
ar -rcs ../libtor.a *.o
rm -f *.o
cd ..

# Step 6: Copy output files
log_info "Copying output files..."
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"
mkdir -p "$OUTPUT_DIR/go"

# Copy libraries
cp "$BUILD_DIR/tor-static/tor/libtor.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/openssl/dist/lib/libssl.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/openssl/dist/lib/libcrypto.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/libevent/dist/lib/libevent.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/zlib/dist/lib/libz.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/libcap/dist/lib64/libcap.a" "$OUTPUT_DIR/lib/" 2>/dev/null || \
   cp "$BUILD_DIR/tor-static/libcap/dist/lib/libcap.a" "$OUTPUT_DIR/lib/" 2>/dev/null || \
   log_warn "libcap.a not found in expected locations"

# Copy tor_api.h header
cp "$BUILD_DIR/tor-static/tor/src/feature/api/tor_api.h" "$OUTPUT_DIR/include/"

# Create a summary file
cat > "$OUTPUT_DIR/build-info.txt" <<EOF
Tor Static Build Information
============================
Build Date: $(date)
Tor Version: 0.4.8.x
OpenSSL Version: $(cd "$BUILD_DIR/tor-static/openssl" && git describe --tags 2>/dev/null || echo "unknown")
Libevent Version: $(cd "$BUILD_DIR/tor-static/libevent" && git describe --tags 2>/dev/null || echo "unknown")
Zlib Version: $(cd "$BUILD_DIR/tor-static/zlib" && git describe --tags 2>/dev/null || echo "unknown")
Libcap Version: ${LIBCAP_VERSION}

Libraries built:
- libtor.a (combined Tor static library)
- libssl.a (OpenSSL SSL)
- libcrypto.a (OpenSSL Crypto)
- libevent.a (Libevent)
- libz.a (Zlib)
- libcap.a (Capabilities)

To use in Go with CGO:
#cgo CFLAGS: -I/path/to/output/include
#cgo LDFLAGS: -L/path/to/output/lib -ltor -lssl -lcrypto -levent -lz -lcap -lm -lpthread -ldl -static-libgcc
EOF

log_info "Build complete! Output files are in: $OUTPUT_DIR"
log_info "Libraries: $OUTPUT_DIR/lib/"
log_info "Headers: $OUTPUT_DIR/include/"
log_info "Build info: $OUTPUT_DIR/build-info.txt"

# Calculate total size
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
log_info "Total output size: $TOTAL_SIZE"

echo "======================================"
echo "Build successful!"
echo "======================================"