# Tor Static Builder for Go Embedding

A complete solution for building statically linked Tor libraries that can be embedded in Go binaries using CGO.

**This repository is also a Go module!** You can import it directly:
```go
import "github.com/RelayAnon/tor-static-builder/embed"
```

See [README-GO.md](README-GO.md) for Go module documentation.

## Quick Command Reference

```bash
make all          # Build libraries + test examples (recommended)
make build        # Build Tor static libraries
make rebuild-tor  # Rebuild only Tor (after dependency build)
make test         # Build Go test programs
make run-basic    # Run basic embedded Tor example
make info         # Show build status and library sizes
make help         # Show all available commands
```

## Features

- Builds Tor 0.4.8.x with all dependencies statically linked
- Includes OpenSSL, libevent, zlib, and libcap
- Produces a single `libtor.a` file containing all Tor code
- Docker-based build environment for reproducibility
- Persistent output volume for build artifacts

## Quick Start

### Step 1: Build Tor Static Libraries

```bash
# Build Tor and all dependencies (takes ~10-20 minutes)
make build

# Or use Docker for reproducible builds
make build-docker
```

### Step 2: Test the Build

```bash
# Build and test the Go examples
make test

# Or test individually:
make test-basic   # Build basic example (15MB binary)
make test-onion   # Build onion service example (20MB binary)
```

### Step 3: Run the Examples

```bash
# Run the basic embedded Tor example
make run-basic

# Run the onion service example (displays .onion address)
make run-onion
```

## Complete Build Process

The recommended workflow is:

```bash
# 1. Build everything (libraries + test examples)
make all

# 2. Check what was built
make info

# 3. Run an example to verify it works
make run-basic
```

## Manual Build Options

If you prefer manual control:

```bash
# Local build (default, uses your system, builds for native architecture)
./build-tor-static.sh

# Build for specific architecture
./build-tor-static.sh --arch amd64
./build-tor-static.sh --arch arm64

# Docker build (for reproducibility, default: amd64)
docker-compose up

# Docker build for specific architecture
ARCH=amd64 docker-compose up
ARCH=arm64 docker-compose up

# Custom directories (architecture will be appended automatically)
export BUILD_DIR=/tmp/my-tor-build
export OUTPUT_DIR=/path/to/output
make build
```

Note: The architecture (amd64 or arm64) is automatically appended to both BUILD_DIR and OUTPUT_DIR.

## Directory Structure

The build process uses two main directories:

- **Build directory** (`~/tor-build/<arch>/`): Temporary build files and source code
- **Output directory** (`./output/<arch>/`): Final static libraries and headers

After a successful build, you'll find architecture-specific outputs in `./output/amd64/` or `./output/arm64/`:

```
output/
├── amd64/                # x86_64 / amd64 build outputs
│   ├── lib/
│   │   ├── libtor.a       # Combined Tor static library (25MB)
│   │   ├── libssl.a       # OpenSSL SSL (1MB)
│   │   ├── libcrypto.a    # OpenSSL Crypto (5.5MB)
│   │   ├── libevent.a     # Libevent (2.2MB)
│   │   ├── libz.a         # Zlib (150KB)
│   │   └── libcap.a       # Linux capabilities (58KB)
│   ├── include/
│   │   └── tor_api.h      # Tor API header
│   └── build-info.txt     # Build information and versions
└── arm64/                # aarch64 / arm64 build outputs (if built)
    └── ... (same structure as amd64)
```

## Using in Your Go Project

### Option 1: Use as a Go Module (Recommended)

```go
import "github.com/RelayAnon/tor-static-builder/embed"

// Use the embedded Tor
creator := embed.GetProcessCreator()
```

### Option 2: Copy the Libraries

1. Build the libraries with `make build` (builds for native architecture by default)
2. The libraries will be in `./output/amd64/` or `./output/arm64/` after building
3. See our working examples for how to use them:
   - **Basic example**: [examples/basic/main.go](examples/basic/main.go) - Simple Tor client
   - **Onion service**: [examples/onion-service/main.go](examples/onion-service/main.go) - Hidden service with persistent keys

   Both examples use the embed package which references [embed/tor048/process.go](embed/tor048/process.go) for the CGO configuration.

4. Create a process.go file in your project with CGO directives pointing to where you built them:

```go
/*
// For amd64 builds
#cgo amd64 CFLAGS: -I${SRCDIR}/../../tor-static-builder/output/amd64/include
#cgo amd64 LDFLAGS: -L${SRCDIR}/../../tor-static-builder/output/amd64/lib -ltor -levent -lz -lssl -lcrypto -lcap

// For arm64 builds
#cgo arm64 CFLAGS: -I${SRCDIR}/../../tor-static-builder/output/arm64/include
#cgo arm64 LDFLAGS: -L${SRCDIR}/../../tor-static-builder/output/arm64/lib -ltor -levent -lz -lssl -lcrypto -lcap

// Common linker flags
#cgo LDFLAGS: -lm -lpthread -ldl -static-libgcc
*/
import "C"
```

Or if you copy the architecture-specific output directory to your project (e.g., `tor-libs/amd64/`):

```go
/*
#cgo amd64 CFLAGS: -I${SRCDIR}/tor-libs/amd64/include
#cgo amd64 LDFLAGS: -L${SRCDIR}/tor-libs/amd64/lib -ltor -levent -lz -lssl -lcrypto -lcap

#cgo arm64 CFLAGS: -I${SRCDIR}/tor-libs/arm64/include
#cgo arm64 LDFLAGS: -L${SRCDIR}/tor-libs/arm64/lib -ltor -levent -lz -lssl -lcrypto -lcap

#cgo LDFLAGS: -lm -lpthread -ldl -static-libgcc
*/
import "C"
```

Note: `${SRCDIR}` in the CGO directives is automatically set by Go to the directory containing the source file.

5. Build your Go binary with CGO enabled:

```bash
CGO_ENABLED=1 go build -ldflags "-linkmode external -extldflags '-static'" -o myapp .
```

## Requirements

### For Docker Build
- Docker
- Docker Compose (optional)
- ~2GB disk space

### For Local Build
- Ubuntu 22.04 or similar Linux distribution
- Basic build tools: gcc, g++, make
- Autotools: automake, autoconf, libtool
- pkg-config, git, wget
- ~2GB disk space
- **No library packages needed!** All libraries (OpenSSL, libevent, zlib, libcap) are built from source

## Build Time

The complete build process takes approximately:
- **First build**: 15-20 minutes (downloads all source code)
- **Subsequent builds**: 10-15 minutes (reuses downloaded sources)
- **Rebuild after changes**: 2-5 minutes (only rebuilds changed components)

## Troubleshooting

### "Using 'getaddrinfo' in statically linked applications" warnings
These warnings are expected with glibc. The binary will still work. These functions will use the system's resolver at runtime.


### Out of disk space
The build requires about 2GB of space:
```bash
make clean        # Remove all build artifacts
make clean-build  # Remove only build directory, keep outputs
docker system prune  # Clean Docker if using Docker build
```

## Advanced Options

### Custom Tor Version

To build a different Tor version, modify the tor-static submodule:

```bash
cd tor-static/tor
git checkout tor-0.4.7.13
cd ../..
./build-tor-static.sh
```

### Cross-compilation

The build script supports both amd64 (x86_64) and arm64 (aarch64) architectures:

```bash
# Build for amd64 (default)
./build-tor-static.sh --arch amd64

# Build for arm64 (requires cross-compilation tools on non-ARM systems)
./build-tor-static.sh --arch arm64

# Install cross-compilation tools if needed (Ubuntu/Debian):
sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

#### Using Docker for Cross-compilation

Docker is the easiest way to cross-compile since all tools are pre-installed:

```bash
# Build for ARM64 using Docker (cross-compilation tools included)
ARCH=arm64 docker-compose up

# Build for both architectures
ARCH=amd64 docker-compose up
ARCH=arm64 docker-compose up
```

Output will be placed in `./output/amd64/` or `./output/arm64/` respectively.

## License

This build system is provided as-is. Tor is distributed under its own license.

## Credits

Based on the [cretz/tor-static](https://github.com/cretz/tor-static) project.