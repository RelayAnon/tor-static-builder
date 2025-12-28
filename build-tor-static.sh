#!/bin/bash
# Build script for creating statically linked Tor libraries for Go embedding
# This script builds Tor 0.4.8.x with all dependencies statically linked

set -e

echo "======================================"
echo "Tor Static Builder for Go Embedding"
echo "======================================"

# Parse command line arguments
ARCH="${ARCH:-amd64}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --arch ARCH    Target architecture: amd64 (default) or arm64"
            echo "  --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect host architecture
HOST_ARCH=$(uname -m)

# Validate architecture and setup cross-compilation if needed
case $ARCH in
    amd64|x86_64)
        OPENSSL_TARGET="linux-x86_64"
        TARGET_ARCH="x86_64"
        ;;
    arm64|aarch64)
        OPENSSL_TARGET="linux-aarch64"
        TARGET_ARCH="aarch64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: amd64, arm64"
        exit 1
        ;;
esac

# Setup cross-compilation if host != target
if [ "$HOST_ARCH" != "$TARGET_ARCH" ] && [ "$HOST_ARCH" != "${ARCH}" ]; then
    echo "Cross-compiling from $HOST_ARCH to $TARGET_ARCH"

    # Check for cross-compiler
    if [ "$TARGET_ARCH" = "aarch64" ]; then
        if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
            echo "Error: aarch64-linux-gnu-gcc not found"
            echo "Install cross-compilation tools:"
            echo "  Ubuntu/Debian: sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
            exit 1
        fi
        export CC=aarch64-linux-gnu-gcc
        export CXX=aarch64-linux-gnu-g++
        export AR=aarch64-linux-gnu-ar
        export RANLIB=aarch64-linux-gnu-ranlib
        export CROSS_COMPILE=aarch64-linux-gnu-
        CONFIGURE_HOST="--host=aarch64-linux-gnu"
    elif [ "$TARGET_ARCH" = "x86_64" ]; then
        if ! command -v x86_64-linux-gnu-gcc &> /dev/null; then
            echo "Error: x86_64-linux-gnu-gcc not found"
            echo "Install cross-compilation tools:"
            echo "  Ubuntu/Debian: sudo apt-get install gcc-x86-64-linux-gnu g++-x86-64-linux-gnu"
            exit 1
        fi
        export CC=x86_64-linux-gnu-gcc
        export CXX=x86_64-linux-gnu-g++
        export AR=x86_64-linux-gnu-ar
        export RANLIB=x86_64-linux-gnu-ranlib
        export CROSS_COMPILE=x86_64-linux-gnu-
        CONFIGURE_HOST="--host=x86_64-linux-gnu"
    fi
else
    echo "Native build for $TARGET_ARCH"
    CONFIGURE_HOST=""
fi

echo "Target architecture: $ARCH"

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

# Always append architecture to paths
BUILD_DIR="$BUILD_DIR/$ARCH"
OUTPUT_DIR="$OUTPUT_DIR/$ARCH"

TOR_STATIC_REPO="https://github.com/cretz/tor-static.git"
LIBCAP_VERSION="2.69"
LIBCAP_URL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-${LIBCAP_VERSION}.tar.gz"

log_info "Build directory: $BUILD_DIR"
log_info "Output directory: $OUTPUT_DIR"

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
make SHARED=no DESTDIR="$BUILD_DIR/tor-static/libcap/dist" prefix=/ install BUILD_CC=gcc CC="${CC:-gcc}" AR="${AR:-ar}" RANLIB="${RANLIB:-ranlib}"

# Step 4: Build all dependencies
cd "$BUILD_DIR/tor-static"

log_info "Building OpenSSL..."
cd openssl
# OpenSSL uses CROSS_COMPILE prefix, so temporarily unset it and use CC directly
if [ -n "$CROSS_COMPILE" ]; then
    OPENSSL_CC="$CC" CROSS_COMPILE="" ./Configure no-shared no-dso $OPENSSL_TARGET --prefix="$BUILD_DIR/tor-static/openssl/dist" CC="$CC" AR="$AR" RANLIB="$RANLIB"
else
    ./Configure no-shared no-dso $OPENSSL_TARGET --prefix="$BUILD_DIR/tor-static/openssl/dist"
fi
# Build only libraries, skip tests to avoid cross-compilation issues
make -j$(nproc) build_libs
make install_sw
cd ..

log_info "Building libevent..."
cd libevent
./autogen.sh
# Set PKG_CONFIG_PATH for cross-compilation
PKG_CONFIG_PATH="$BUILD_DIR/tor-static/openssl/dist/lib/pkgconfig:$PKG_CONFIG_PATH" \
./configure --prefix="$BUILD_DIR/tor-static/libevent/dist" --disable-shared --enable-static --with-pic $CONFIGURE_HOST \
    CPPFLAGS="-I$BUILD_DIR/tor-static/openssl/dist/include" \
    LDFLAGS="-L$BUILD_DIR/tor-static/openssl/dist/lib"
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
    --disable-tool-name-check \
    --with-libevent-dir="$BUILD_DIR/tor-static/libevent/dist" \
    --with-openssl-dir="$BUILD_DIR/tor-static/openssl/dist" \
    --with-zlib-dir="$BUILD_DIR/tor-static/zlib/dist" \
    $CONFIGURE_HOST

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
Architecture: $ARCH
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