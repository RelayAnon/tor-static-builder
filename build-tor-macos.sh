#!/bin/bash
# Build script for creating statically linked Tor libraries for Go embedding on macOS
# This script builds Tor 0.4.8.x with all dependencies statically linked

set -e

echo "======================================"
echo "Tor Static Builder for macOS"
echo "======================================"

# Check for required dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo ""
        echo "Error: '$1' is not installed."
        echo ""
        echo "Please install the required build tools:"
        echo "  brew install automake autoconf libtool"
        echo ""
        echo "If libtool commands are prefixed with 'g', add to your PATH:"
        echo "  export PATH=\"/opt/homebrew/opt/libtool/libexec/gnubin:\$PATH\""
        echo ""
        exit 1
    fi
}

echo "Checking dependencies..."
check_dependency "automake"
check_dependency "autoconf"
check_dependency "libtool"
check_dependency "git"
check_dependency "make"
check_dependency "gcc"
echo "All dependencies found."

# Parse command line arguments
ARCH="${ARCH:-arm64}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --arch ARCH    Target architecture: arm64 (default) or amd64"
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

# Validate architecture
case $ARCH in
    amd64|x86_64)
        OPENSSL_TARGET="darwin64-x86_64-cc"
        TARGET_ARCH="x86_64"
        ;;
    arm64|aarch64)
        OPENSSL_TARGET="darwin64-arm64-cc"
        TARGET_ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: amd64, arm64"
        exit 1
        ;;
esac

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script is for macOS only"
    echo "Use build-tor-static.sh for Linux"
    exit 1
fi

echo "Native build for $TARGET_ARCH on macOS"
CONFIGURE_HOST=""

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
BUILD_DIR="${BUILD_DIR:-$HOME/tor-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"

# Always append architecture to paths
BUILD_DIR="$BUILD_DIR/darwin-$ARCH"
OUTPUT_DIR="$OUTPUT_DIR/darwin-$ARCH"

TOR_STATIC_REPO="https://github.com/cretz/tor-static.git"

log_info "Build directory: $BUILD_DIR"
log_info "Output directory: $OUTPUT_DIR"

# Get number of CPUs on macOS
NPROC=$(sysctl -n hw.ncpu)

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

# Step 3: Build all dependencies (no libcap on macOS)
cd "$BUILD_DIR/tor-static"

log_info "Building OpenSSL..."
cd openssl
./Configure no-shared no-dso $OPENSSL_TARGET --prefix="$BUILD_DIR/tor-static/openssl/dist"
make -j$NPROC build_libs
make install_sw
cd ..

log_info "Building libevent..."
cd libevent
./autogen.sh
PKG_CONFIG_PATH="$BUILD_DIR/tor-static/openssl/dist/lib/pkgconfig:$PKG_CONFIG_PATH" \
./configure --prefix="$BUILD_DIR/tor-static/libevent/dist" --disable-shared --enable-static --with-pic \
    CPPFLAGS="-I$BUILD_DIR/tor-static/openssl/dist/include" \
    LDFLAGS="-L$BUILD_DIR/tor-static/openssl/dist/lib"
make -j$NPROC
make install
cd ..

log_info "Building zlib..."
cd zlib
./configure --prefix="$BUILD_DIR/tor-static/zlib/dist" --static
make -j$NPROC
make install
cd ..

# Step 4: Build Tor with zstd disabled
log_info "Building Tor 0.4.8..."
cd tor

# Apply configuration
# Note: We don't use --enable-static-tor because macOS doesn't support fully static binaries
# Instead we build the static libraries and combine them
./autogen.sh
./configure \
    --prefix="$BUILD_DIR/tor-static/tor/dist" \
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
    --disable-seccomp \
    --with-libevent-dir="$BUILD_DIR/tor-static/libevent/dist" \
    --with-openssl-dir="$BUILD_DIR/tor-static/openssl/dist" \
    --with-zlib-dir="$BUILD_DIR/tor-static/zlib/dist"

# Build Tor - the executable linking will fail on macOS but we only need the static libraries
# Use -k to continue past errors, as we only need the .a files
make -j$NPROC -k || true

# Verify that the libraries were built
if ! ls src/lib/*.a &>/dev/null && ! ls src/core/*.a &>/dev/null; then
    log_error "Static libraries were not built"
    exit 1
fi
log_info "Static libraries built successfully (executable linking errors are expected on macOS)"

# Combine all static libraries into libtor.a (excluding test libraries)
log_info "Creating combined libtor.a..."
cd src
find . -name '*.a' ! -name '*-testing.a' -exec ar -x {} \;
ar -rcs ../libtor.a *.o
rm -f *.o
cd ..

# Step 5: Copy output files
log_info "Copying output files..."
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

# Copy libraries
cp "$BUILD_DIR/tor-static/tor/libtor.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/openssl/dist/lib/libssl.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/openssl/dist/lib/libcrypto.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/libevent/dist/lib/libevent.a" "$OUTPUT_DIR/lib/"
cp "$BUILD_DIR/tor-static/zlib/dist/lib/libz.a" "$OUTPUT_DIR/lib/"

# Copy tor_api.h header
cp "$BUILD_DIR/tor-static/tor/src/feature/api/tor_api.h" "$OUTPUT_DIR/include/"

# Create a summary file
cat > "$OUTPUT_DIR/build-info.txt" <<EOF
Tor Static Build Information (macOS)
====================================
Build Date: $(date)
Platform: macOS $(sw_vers -productVersion)
Architecture: $ARCH
Tor Version: 0.4.8.x
OpenSSL Version: $(cd "$BUILD_DIR/tor-static/openssl" && git describe --tags 2>/dev/null || echo "unknown")
Libevent Version: $(cd "$BUILD_DIR/tor-static/libevent" && git describe --tags 2>/dev/null || echo "unknown")
Zlib Version: $(cd "$BUILD_DIR/tor-static/zlib" && git describe --tags 2>/dev/null || echo "unknown")

Libraries built:
- libtor.a (combined Tor static library)
- libssl.a (OpenSSL SSL)
- libcrypto.a (OpenSSL Crypto)
- libevent.a (Libevent)
- libz.a (Zlib)

Note: libcap is not available on macOS (Linux-only)

To use in Go with CGO:
#cgo darwin CFLAGS: -I/path/to/output/include
#cgo darwin LDFLAGS: -L/path/to/output/lib -ltor -lssl -lcrypto -levent -lz -lm -lpthread
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
