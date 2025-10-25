# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dual-purpose repository:
1. A build system that creates statically-linked Tor libraries for embedding in Go applications
2. A Go module (`github.com/RelayAnon/tor-static-builder/embed`) that provides embedded Tor functionality

The key innovation is that all dependencies (OpenSSL, libevent, zlib, libcap) are built from source and statically linked, eliminating external dependencies.

## Architecture

### Build System
- **build-tor-static.sh**: Main build script that orchestrates building Tor and all dependencies for Linux
- **build-tor-android.sh**: Android-specific build script using Android NDK toolchain
- **Makefile**: Provides convenient commands for building, testing, and managing the project
- **Architecture Support**: Builds are architecture-specific (amd64/arm64 for Linux; arm64/arm/x86/x86_64 for Android), with outputs in `output/<arch>/` or `output/android-<arch>/`
- **Cross-compilation**: Supports cross-compiling for different architectures using `--arch` flag

### Go Module Structure
- **embed/embed.go**: High-level Go API for embedded Tor (QuickStart, StartTor, StopTor, etc.)
- **embed/tor048/process.go**: CGO integration layer that interfaces with Tor's C API via tor_api.h
- **examples/**: Working examples demonstrating basic usage and onion services

The CGO layer uses the `bine` library's process interfaces to wrap statically-linked Tor 0.4.8.x.

### Critical CGO Configuration
The `embed/tor048/process.go` file contains architecture-specific CGO directives:
```go
// AMD64 / x86_64 architecture
#cgo amd64 CFLAGS: -I${SRCDIR}/../../output/amd64/include
#cgo amd64 LDFLAGS: -L${SRCDIR}/../../output/amd64/lib -ltor -levent -lz -lssl -lcrypto -lcap

// ARM64 / aarch64 architecture
#cgo arm64 CFLAGS: -I${SRCDIR}/../../output/arm64/include
#cgo arm64 LDFLAGS: -L${SRCDIR}/../../output/arm64/lib -ltor -levent -lz -lssl -lcrypto -lcap
```

These paths use Go's build tags to automatically select the correct architecture-specific libraries during compilation.

## Common Commands

### Building Tor Libraries (Linux)
```bash
make build              # Build all static libraries for native architecture
make build-docker       # Build using Docker (reproducible)

# Non-Docker builds for specific architecture
./build-tor-static.sh --arch amd64   # Build for amd64
./build-tor-static.sh --arch arm64   # Cross-compile for ARM64

# Docker builds for specific architecture
ARCH=amd64 docker-compose up         # Build amd64 in Docker
ARCH=arm64 docker-compose up         # Build arm64 in Docker (cross-compilation)
```

### Building Tor Libraries (Android)
```bash
# Build for Android using Makefile (simplest)
make build-android                              # Non-Docker build (requires NDK)
make build-android-docker                       # Docker build (no NDK needed!)

# Build for Android directly with script (requires Android NDK)
./build-tor-android.sh                          # Default: ARM64, API 21
./build-tor-android.sh --arch arm64             # ARM64 (most Android devices)
./build-tor-android.sh --arch arm               # ARMv7 (older devices)
./build-tor-android.sh --arch x86               # x86 (emulators)
./build-tor-android.sh --arch x86_64            # x86_64 (emulators)
./build-tor-android.sh --arch arm64 --api 21    # Specify API level

# Build for Android using docker-compose directly
ARCH=arm64 docker-compose up --build android-builder
ARCH=arm ANDROID_API=23 docker-compose up --build android-builder

# Interactive Android build shell (for debugging)
make shell-android
```

**Android Build Requirements:**
- **Docker builds:** No requirements - NDK included in Docker image
- **Non-Docker builds:** Android NDK must be installed and `ANDROID_NDK_HOME` set, or NDK in `~/Android/Sdk/ndk/`
- All standard Linux build tools (gcc, make, autotools, etc.)

First build takes 15-20 minutes; subsequent builds are faster.

**Output locations:**
- Non-Docker builds: `./output/<arch>/` or `./output/android-<arch>/` (build cache in `~/tor-build/`)
- Docker builds: `./output/<arch>/` or `./output/android-<arch>/` (build cache in Docker volume)

### Testing
```bash
make test              # Build both Go examples
make test-basic        # Build basic example only
make test-onion        # Build onion service example only
make run-basic         # Build and run basic example
make run-onion         # Build and run onion service example

# Go tests (unit tests)
go test ./embed/...    # Run package tests
go test -tags integration ./embed/...  # Run integration tests (slower)
```

### Debugging & Utilities
```bash
make check             # Verify all build outputs exist
make info              # Show build configuration and status
make clean             # Remove all build artifacts
make clean-build       # Remove build directory, keep outputs
make rebuild-tor       # Rebuild only Tor (after dependency changes)
```

## Output Directory Structure

After building, outputs are organized by platform and architecture:

### Linux Builds
```
output/
├── amd64/              # x86_64 build outputs
│   ├── lib/            # Static libraries (libtor.a, libssl.a, etc.)
│   ├── include/        # tor_api.h header
│   └── build-info.txt  # Build metadata
└── arm64/              # ARM64 build outputs (if built)
    ├── lib/
    ├── include/
    └── build-info.txt
```

Build artifacts are placed in `~/tor-build/<arch>/` by default. The `<arch>` directory is automatically appended to both `BUILD_DIR` and `OUTPUT_DIR`.

### Android Builds
```
output/
├── android-arm64/      # Android ARM64 build outputs
│   ├── lib/            # Static libraries (libtor.a, libssl.a, etc., NO libcap)
│   ├── include/        # tor_api.h header
│   └── build-info.txt  # Build metadata
├── android-arm/        # Android ARMv7 (if built)
├── android-x86/        # Android x86 (if built)
└── android-x86_64/     # Android x86_64 (if built)
```

Android build artifacts are placed in `~/tor-build/android-<arch>/` by default.

## Important Implementation Details

### Architecture-Specific Build Paths

**Linux builds** (build-tor-static.sh):
- **Non-Docker builds**: `~/tor-build/amd64/` or `~/tor-build/arm64/`
- **Output**: `./output/amd64/` or `./output/arm64/`
- **Docker builds**: `/build/amd64/` and `/output/amd64/` (or arm64)

**Android builds** (build-tor-android.sh):
- **Non-Docker builds**: `~/tor-build/android-<arch>/` (e.g., `~/tor-build/android-arm64/`)
- **Output**: `./output/android-<arch>/` (e.g., `./output/android-arm64/`)
- **Docker builds**: `/build/android-<arch>/` and `/output/android-<arch>/`
- Supported architectures: arm64, arm, x86, x86_64

### Static Library Combination
The build process combines all Tor component libraries into a single `libtor.a`:
```bash
cd src
find . -name '*.a' ! -name '*-testing.a' -exec ar -x {} \;
ar -rcs ../libtor.a *.o
```
This simplifies linking in Go applications - you only need to link against one Tor library.

### Tor Configuration Flags
The Tor build disables features not needed for client/embedded use:
- `--disable-systemd`: Prevents systemd conflicts
- `--disable-zstd --disable-lzma`: Disables optional compression
- `--disable-module-relay --disable-module-dirauth`: Client-only mode

### Bootstrap Process
When embedding Tor in Go:
1. Call `StartTor()` to initialize the Tor process
2. Call `EnableNetwork()` to begin bootstrap (can take 1-3 minutes)
3. Default timeout is 3 minutes; increase for slow networks

The `QuickStart()` function combines both steps for convenience.

### Global State Management
The embed package uses atomic pointers for thread-safe global state:
- `torInstance`: The running Tor instance
- `onionAddress`: Current onion service address (if any)

## Testing Strategy

1. **Unit Tests** (`embed/embed_test.go`): Fast tests of basic functionality
2. **Integration Tests** (`embed/embed_integration_test.go`): Full Tor bootstrap (use `-tags integration`)
3. **Concurrent Tests** (`embed/concurrent_test.go`): Thread-safety validation
4. **Example Programs**: Real-world usage patterns in `examples/`

Integration tests are slow (2-5 minutes) due to Tor bootstrap time.

## Known Issues & Fixes

### "Using 'getaddrinfo' in statically linked applications" warnings
Expected with glibc static linking. The binary works correctly; these functions use the system resolver at runtime.

### Architecture Mismatch
If you get linking errors:
1. Verify you've built for the correct architecture: `ls output/`
2. The architecture must match your Go build: `go env GOARCH`
3. Rebuild if needed: `make clean && make build`

### External Usage of this Module
When using this module in external projects, you must:
1. Build the libraries: `cd tor-static-builder && make build`
2. The CGO directives in `embed/tor048/process.go` will automatically use the correct architecture
3. Ensure the `output/<arch>/` directories exist relative to the module root

If you want to copy the libraries elsewhere, create your own `process.go` file with custom CGO paths pointing to your library location.

### Docker vs Non-Docker Builds
- Docker builds use `/build/<arch>/` and `/output/<arch>/`
- Non-Docker builds use `~/tor-build/<arch>/` and `./output/<arch>/`
- Set `BUILD_DIR` and `OUTPUT_DIR` environment variables to override (architecture is still appended)

## Android-Specific Details

### Android Build Script (build-tor-android.sh)
The Android build script is a specialized version that:
- Uses the Android NDK toolchain instead of standard gcc/g++
- Builds for Android architectures: arm64, arm (armv7), x86, x86_64
- Targets Android API 21 by default (minimum for modern Android devices)
- Does NOT build libcap (Android doesn't use Linux capabilities the same way)
- Produces libraries suitable for gomobile and Android NDK projects
- **Can run in Docker** via `make build-android-docker` or `docker-compose up android-builder` (no local NDK needed)

### Key Differences from Linux Builds
1. **No libcap**: Android builds exclude libcap library
2. **NDK toolchain**: Uses NDK's clang/llvm instead of system gcc
3. **Android-specific flags**: Adds `-D__ANDROID__` and uses Android API level
4. **Output directories**: Uses `output/android-<arch>/` instead of `output/<arch>/`
5. **Additional linker flags**: Android builds need `-lm -llog` instead of `-lpthread -ldl`

### Android NDK Detection
**For non-Docker builds**, the script auto-detects the NDK in this order:
1. `$ANDROID_NDK_HOME` environment variable
2. `~/Android/Sdk/ndk/` (finds latest version automatically)
3. Exits with error if NDK not found

**For Docker builds**, the NDK is pre-installed in the Docker image at `/opt/android-ndk` (NDK r26d LTS).

### Using Android Libraries
To use the Android libraries with gomobile:

```bash
# Build for Android ARM64
./build-tor-android.sh --arch arm64

# Set environment variables for gomobile
export CGO_CFLAGS="-I$(pwd)/output/android-arm64/include"
export CGO_LDFLAGS="-L$(pwd)/output/android-arm64/lib -ltor -lssl -lcrypto -levent -lz -lm -llog"

# Build your gomobile library
gomobile bind -target=android/arm64 -o mylib.aar github.com/myuser/myproject
```

**Important:** Note that Android uses `-llog` instead of `-ldl` and doesn't need `-lcap`.

### Android Build Configuration
The script configures Tor with Android-specific options:
- `--disable-seccomp`: Android doesn't support seccomp the same way
- `--disable-tool-name-check`: Allows cross-compilation
- `--host=$TARGET_TRIPLE`: Sets the target platform correctly
- Uses NDK's llvm-ar and llvm-ranlib instead of GNU ar/ranlib

## Build Time Expectations

- **Initial build**: 15-20 minutes (downloads all sources)
- **Tor rebuild**: 2-5 minutes (after dependency changes)
- **Go examples**: 5-10 seconds each
- **Docker build**: 20-30 minutes (includes image building)

## Development Workflow

When making changes:
1. **Build script changes**: Test with `make clean && make build`
2. **Go code changes**: Test with `make test` and `make run-basic`
3. **Cross-compilation**: Test both amd64 and arm64 if architecture-sensitive
4. **CGO changes**: Rebuild examples to verify linking works
5. **Documentation**: Update README.md, README-GO.md, and this file together

## Dependencies

### Build Dependencies (host system)
- gcc, g++, make
- automake, autoconf, libtool
- pkg-config, git, wget
- For cross-compilation: gcc-aarch64-linux-gnu, g++-aarch64-linux-gnu
- **For Android builds**: Android NDK (r21 or later)

### Go Dependencies
- Go 1.19+
- CGO_ENABLED=1
- github.com/cretz/bine v0.2.0 (Tor control library)
- **For gomobile/Android**: gomobile (install with `go install golang.org/x/mobile/cmd/gomobile@latest`)

### Built from Source (no system packages needed)
- Tor 0.4.8.x
- OpenSSL 1.1.1w
- libevent
- zlib
- libcap 2.69 (Linux builds only, not included in Android builds)

All of these are downloaded and built automatically by the build scripts.
