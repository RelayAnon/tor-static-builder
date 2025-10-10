# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dual-purpose repository:
1. A build system that creates statically-linked Tor libraries for embedding in Go applications
2. A Go module (`github.com/RelayAnon/tor-static-builder/embed`) that provides embedded Tor functionality

The key innovation is that all dependencies (OpenSSL, libevent, zlib, libcap) are built from source and statically linked, eliminating external dependencies.

## Architecture

### Build System
- **build-tor-static.sh**: Main build script that orchestrates building Tor and all dependencies
- **Makefile**: Provides convenient commands for building, testing, and managing the project
- **Architecture Support**: Builds are architecture-specific (amd64/arm64), with outputs in `output/<arch>/`
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

### Building Tor Libraries
```bash
make build              # Build all static libraries for native architecture
make build-docker       # Build using Docker (reproducible)
./build-tor-static.sh --arch amd64   # Build for specific architecture
./build-tor-static.sh --arch arm64   # Cross-compile for ARM64
```

First build takes 15-20 minutes; subsequent builds are faster. Build artifacts are cached in `~/tor-build/<arch>/` by default.

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

After building, outputs are organized by architecture:
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

## Important Implementation Details

### Architecture-Specific Build Paths
The build script automatically appends the architecture to paths:
- **Local builds**: `~/tor-build/amd64/` or `~/tor-build/arm64/`
- **Output**: `./output/amd64/` or `./output/arm64/`
- **Docker builds**: `/build/amd64/` and `/output/amd64/` (or arm64)

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

### Docker vs Local Builds
- Docker builds use `/build/<arch>/` and `/output/<arch>/`
- Local builds use `~/tor-build/<arch>/` and `./output/<arch>/`
- Set `BUILD_DIR` and `OUTPUT_DIR` environment variables to override (architecture is still appended)

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

### Go Dependencies
- Go 1.19+
- CGO_ENABLED=1
- github.com/cretz/bine v0.2.0 (Tor control library)

### Built from Source (no system packages needed)
- Tor 0.4.8.x
- OpenSSL 1.1.1w
- libevent
- zlib
- libcap 2.69

All of these are downloaded and built automatically by the build script.
