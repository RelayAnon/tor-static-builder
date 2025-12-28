#!/bin/bash
# Build script for creating Android-specific statically linked Tor libraries
# This script builds Tor 0.4.8.x for Android using the NDK toolchain

set -e

echo "======================================"
echo "Tor Static Builder for Android"
echo "======================================"

# Configuration
ANDROID_API="${ANDROID_API:-21}"
ARCH="${ARCH:-arm64}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --api)
            ANDROID_API="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --arch ARCH    Target architecture: arm64 (default), arm, x86, x86_64"
            echo "  --api LEVEL    Android API level (default: 21)"
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

# Find Android NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        # Find the latest NDK version
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk/"* | sort -V | tail -1)
        echo "Found NDK at: $ANDROID_NDK_HOME"
    else
        echo "Error: ANDROID_NDK_HOME not set and NDK not found in standard location"
        echo "Please set ANDROID_NDK_HOME or install Android NDK"
        exit 1
    fi
fi

if [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "Error: NDK directory not found: $ANDROID_NDK_HOME"
    exit 1
fi

# Setup architecture-specific variables
case $ARCH in
    arm64|aarch64)
        ANDROID_ARCH="arm64"
        ANDROID_ABI="arm64-v8a"
        OPENSSL_TARGET="android-arm64"
        TARGET_TRIPLE="aarch64-linux-android"
        ;;
    arm|armv7)
        ANDROID_ARCH="arm"
        ANDROID_ABI="armeabi-v7a"
        OPENSSL_TARGET="android-arm"
        TARGET_TRIPLE="armv7a-linux-androideabi"
        ;;
    x86)
        ANDROID_ARCH="x86"
        ANDROID_ABI="x86"
        OPENSSL_TARGET="android-x86"
        TARGET_TRIPLE="i686-linux-android"
        ;;
    x86_64|amd64)
        ANDROID_ARCH="x86_64"
        ANDROID_ABI="x86_64"
        OPENSSL_TARGET="android-x86_64"
        TARGET_TRIPLE="x86_64-linux-android"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported: arm64, arm, x86, x86_64"
        exit 1
        ;;
esac

echo "Target architecture: $ANDROID_ARCH"
echo "Android ABI: $ANDROID_ABI"
echo "Android API level: $ANDROID_API"

# Setup NDK toolchain
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
export PATH="$TOOLCHAIN/bin:$PATH"

# Set compilers
export CC="$TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export AS="$TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
export LD="$TOOLCHAIN/bin/ld"
export STRIP="$TOOLCHAIN/bin/llvm-strip"

# Verify toolchain
if [ ! -f "$CC" ]; then
    echo "Error: Compiler not found: $CC"
    echo "Please check your NDK installation"
    exit 1
fi

echo "Using compiler: $CC"

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

# Build directories
BUILD_DIR="${BUILD_DIR:-$HOME/tor-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"

# Always append android-arch to paths
BUILD_DIR="$BUILD_DIR/android-$ANDROID_ARCH"
OUTPUT_DIR="$OUTPUT_DIR/android-$ANDROID_ARCH"

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

# Step 3: Build OpenSSL for Android
log_info "Building OpenSSL for Android..."
cd openssl

# Set Android environment variables for OpenSSL
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

./Configure $OPENSSL_TARGET \
    -D__ANDROID_API__=$ANDROID_API \
    no-shared \
    no-dso \
    --prefix="$BUILD_DIR/tor-static/openssl/dist"

make -j$(nproc) build_libs
make install_sw
cd ..

# Step 4: Build libevent for Android
log_info "Building libevent for Android..."
cd libevent
./autogen.sh

# Configure for Android
./configure \
    --prefix="$BUILD_DIR/tor-static/libevent/dist" \
    --host="$TARGET_TRIPLE" \
    --disable-shared \
    --enable-static \
    --with-pic \
    --disable-openssl \
    CFLAGS="-fPIC" \
    LDFLAGS="-fPIC"

make -j$(nproc)
make install
cd ..

# Step 5: Build zlib for Android
log_info "Building zlib for Android..."
cd zlib

CFLAGS="-fPIC" ./configure \
    --prefix="$BUILD_DIR/tor-static/zlib/dist" \
    --static

make -j$(nproc)
make install
cd ..

# Step 6: Build Tor for Android
log_info "Building Tor 0.4.8 for Android..."
cd tor

./autogen.sh

# Configure Tor for Android
# Note: We skip libcap as Android doesn't use Linux capabilities the same way
./configure \
    --prefix="$BUILD_DIR/tor-static/tor/dist" \
    --host="$TARGET_TRIPLE" \
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
    --disable-unittests \
    --disable-seccomp \
    --with-libevent-dir="$BUILD_DIR/tor-static/libevent/dist" \
    --with-openssl-dir="$BUILD_DIR/tor-static/openssl/dist" \
    --with-zlib-dir="$BUILD_DIR/tor-static/zlib/dist" \
    CFLAGS="-fPIC -D__ANDROID__" \
    LDFLAGS="-fPIC"

# Build Tor
make -j$(nproc)

# Combine all static libraries into libtor.a (excluding test libraries)
log_info "Creating combined libtor.a..."
cd src
find . -name '*.a' ! -name '*-testing.a' -exec ar -x {} \;
ar -rcs ../libtor.a *.o
rm -f *.o
cd ..

# Step 7: Copy output files
log_info "Copying output files..."

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
Tor Static Build Information (Android)
======================================
Build Date: $(date)
Architecture: $ANDROID_ARCH
Android ABI: $ANDROID_ABI
Android API Level: $ANDROID_API
Tor Version: 0.4.8.x

Libraries built:
- libtor.a (combined Tor static library)
- libssl.a (OpenSSL SSL)
- libcrypto.a (OpenSSL Crypto)
- libevent.a (Libevent)
- libz.a (Zlib)

Note: libcap not included (not needed for Android)

To use in Go with gomobile:
CGO_CFLAGS="-I$OUTPUT_DIR/include"
CGO_LDFLAGS="-L$OUTPUT_DIR/lib -ltor -lssl -lcrypto -levent -lz -lm -llog"
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
