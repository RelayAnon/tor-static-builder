#!/bin/bash
# Build script for creating statically linked Tor libraries for Windows
# This script cross-compiles Tor 0.4.8.x with all dependencies for Windows
# Uses MinGW-w64 cross-compiler toolchain

set -e

echo "======================================"
echo "Tor Static Builder for Windows"
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
            echo "  --arch ARCH    Target architecture: amd64 (default)"
            echo "                 Note: Only amd64 is supported for Windows"
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

# Validate architecture - only amd64 supported for Windows currently
case $ARCH in
    amd64|x86_64)
        ARCH="amd64"
        TARGET_TRIPLE="x86_64-w64-mingw32"
        OPENSSL_TARGET="mingw64"
        ;;
    *)
        echo "Error: Unsupported Windows architecture: $ARCH"
        echo "Supported: amd64"
        exit 1
        ;;
esac

echo "Target architecture: $ARCH (Windows)"
echo "Target triple: $TARGET_TRIPLE"

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

# Check for MinGW-w64 cross-compiler
if ! command -v ${TARGET_TRIPLE}-gcc &> /dev/null; then
    log_error "${TARGET_TRIPLE}-gcc not found"
    echo "Install MinGW-w64 cross-compilation tools:"
    echo "  Ubuntu/Debian: sudo apt-get install mingw-w64"
    echo "  Fedora: sudo dnf install mingw64-gcc mingw64-gcc-c++"
    echo "  Arch: sudo pacman -S mingw-w64-gcc"
    exit 1
fi

# Set up cross-compilation environment
export CC="${TARGET_TRIPLE}-gcc"
export CXX="${TARGET_TRIPLE}-g++"
export AR="${TARGET_TRIPLE}-ar"
export RANLIB="${TARGET_TRIPLE}-ranlib"
export WINDRES="${TARGET_TRIPLE}-windres"
export RC="${TARGET_TRIPLE}-windres"
export CROSS_COMPILE="${TARGET_TRIPLE}-"
CONFIGURE_HOST="--host=${TARGET_TRIPLE}"

log_info "Using compiler: $CC"

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

# Always append windows-arch to paths
BUILD_DIR="$BUILD_DIR/windows-$ARCH"
OUTPUT_DIR="$OUTPUT_DIR/windows-$ARCH"
TOR_STATIC_REPO="https://github.com/cretz/tor-static.git"

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

# Step 3: Build zlib (Windows compatible)
log_info "Building zlib for Windows..."
cd "$BUILD_DIR/tor-static/zlib"

# Clean any previous build
make distclean 2>/dev/null || true

# zlib has special handling for MinGW
make -f win32/Makefile.gcc \
    PREFIX="${TARGET_TRIPLE}-" \
    CC="${CC}" \
    AR="${AR}" \
    RC="${WINDRES}" \
    -j$(nproc)

# Install manually
mkdir -p "$BUILD_DIR/tor-static/zlib/dist/lib"
mkdir -p "$BUILD_DIR/tor-static/zlib/dist/include"
cp libz.a "$BUILD_DIR/tor-static/zlib/dist/lib/"
cp zlib.h zconf.h "$BUILD_DIR/tor-static/zlib/dist/include/"
cd ..

# Step 4: Build OpenSSL for Windows
log_info "Building OpenSSL for Windows..."
cd openssl

# Clean any previous build
make clean 2>/dev/null || true

# Unset CC/CXX temporarily - OpenSSL uses --cross-compile-prefix instead
# which would double the prefix if CC is already set
unset CC CXX AR RANLIB

# Configure OpenSSL for Windows cross-compilation
./Configure $OPENSSL_TARGET \
    no-shared \
    no-dso \
    no-tests \
    --cross-compile-prefix="${TARGET_TRIPLE}-" \
    --prefix="$BUILD_DIR/tor-static/openssl/dist" \
    CFLAGS="-static"

# Build only libraries (not programs)
make -j$(nproc) build_libs

# Manually install libraries and headers (avoid install_sw which builds programs)
mkdir -p "$BUILD_DIR/tor-static/openssl/dist/lib"
mkdir -p "$BUILD_DIR/tor-static/openssl/dist/include/openssl"
cp libssl.a libcrypto.a "$BUILD_DIR/tor-static/openssl/dist/lib/"
cp include/openssl/*.h "$BUILD_DIR/tor-static/openssl/dist/include/openssl/"

# Restore cross-compilation environment
export CC="${TARGET_TRIPLE}-gcc"
export CXX="${TARGET_TRIPLE}-g++"
export AR="${TARGET_TRIPLE}-ar"
export RANLIB="${TARGET_TRIPLE}-ranlib"

cd ..

# Step 5: Build libevent for Windows
log_info "Building libevent for Windows..."
cd libevent

# Clean any previous build
make distclean 2>/dev/null || true
rm -rf dist

./autogen.sh

PKG_CONFIG_PATH="$BUILD_DIR/tor-static/openssl/dist/lib/pkgconfig:$PKG_CONFIG_PATH" \
./configure \
    --prefix="$BUILD_DIR/tor-static/libevent/dist" \
    --disable-shared \
    --enable-static \
    --with-pic \
    --disable-samples \
    --disable-libevent-regress \
    $CONFIGURE_HOST \
    CPPFLAGS="-I$BUILD_DIR/tor-static/openssl/dist/include" \
    LDFLAGS="-L$BUILD_DIR/tor-static/openssl/dist/lib -static" \
    CFLAGS="-static"

make -j$(nproc)
make install
cd ..

# Step 6: Build Tor for Windows
log_info "Building Tor 0.4.8 for Windows..."
cd tor

# Clean any previous build
make distclean 2>/dev/null || true

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
    --disable-unittests \
    --disable-seccomp \
    --disable-libscrypt \
    --disable-tool-name-check \
    --with-libevent-dir="$BUILD_DIR/tor-static/libevent/dist" \
    --with-openssl-dir="$BUILD_DIR/tor-static/openssl/dist" \
    --with-zlib-dir="$BUILD_DIR/tor-static/zlib/dist" \
    $CONFIGURE_HOST \
    CFLAGS="-static" \
    LDFLAGS="-static"

# Build Tor
make -j$(nproc)

# Combine all static libraries into libtor.a (excluding test libraries)
log_info "Creating combined libtor.a..."
cd src
rm -f *.o 2>/dev/null || true
find . -name '*.a' ! -name '*-testing.a' -exec ${AR} -x {} \;
${AR} -rcs ../libtor.a *.o
rm -f *.o
cd ..

# Step 7: Copy output files
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
Tor Static Build Information (Windows)
=======================================
Build Date: $(date)
Platform: Windows
Architecture: $ARCH
Target Triple: $TARGET_TRIPLE
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

Note: No libcap on Windows (Linux-specific)

To use in Go with CGO:
#cgo windows,amd64 CFLAGS: -I/path/to/output/windows-amd64/include
#cgo windows,amd64 LDFLAGS: -L/path/to/output/windows-amd64/lib -ltor -levent -lz -lssl -lcrypto -lws2_32 -lcrypt32 -lgdi32 -liphlpapi -lole32 -lshlwapi -Wl,-Bstatic -lpthread
EOF

log_info "Build complete! Output files are in: $OUTPUT_DIR"
log_info "Libraries: $OUTPUT_DIR/lib/"
log_info "Headers: $OUTPUT_DIR/include/"
log_info "Build info: $OUTPUT_DIR/build-info.txt"

# Calculate total size
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
log_info "Total output size: $TOTAL_SIZE"

echo "======================================"
echo "Windows build successful!"
echo "======================================"
