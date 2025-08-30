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
make build        # Build Tor static libraries only
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
# Local build (default, uses your system)
./build-tor-static.sh

# Docker build (for reproducibility)
docker-compose up

# Custom directories
export BUILD_DIR=/tmp/my-tor-build
export OUTPUT_DIR=/path/to/output
make build
```

## Directory Structure

The build process uses two main directories:

- **Build directory** (`~/tor-build/`): Temporary build files and source code
- **Output directory** (`./output/`): Final static libraries and headers

After a successful build, you'll find in `./output/`:

```
output/
├── lib/
│   ├── libtor.a       # Combined Tor static library (25MB)
│   ├── libssl.a       # OpenSSL SSL (1MB)
│   ├── libcrypto.a    # OpenSSL Crypto (5.5MB)
│   ├── libevent.a     # Libevent (2.2MB)
│   ├── libz.a         # Zlib (150KB)
│   └── libcap.a       # Linux capabilities (58KB)
├── include/
│   └── tor_api.h      # Tor API header
└── build-info.txt     # Build information and versions
```

## Using in Your Go Project

### 1. Copy the process.go template

Copy `templates/process.go` to your project (e.g., `cmd/embedded/tor-0.4.8/process.go`)

### 2. Update the CGO paths

Edit the CGO directives in process.go to point to your output directory:

```go
/*
#cgo CFLAGS: -I/path/to/output/include
#cgo LDFLAGS: -L/path/to/output/lib -ltor -levent -lz -lssl -lcrypto -lcap
#cgo LDFLAGS: -lm -lpthread -ldl -static-libgcc
*/
import "C"
```

### 3. Use build tags

Build your Go binary with the embedded tag:

```bash
CGO_ENABLED=1 go build -tags embedded \
    -ldflags "-linkmode external -extldflags '-static'" \
    -o myapp .
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

### Build fails with "libcap not found"
The build script automatically downloads and builds libcap-2.69 from kernel.org source. No system packages are required - everything is built from source.

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

For ARM or other architectures, modify the configure flags in `build-tor-static.sh`.

## License

This build system is provided as-is. Tor is distributed under its own license.

## Credits

Based on the [cretz/tor-static](https://github.com/cretz/tor-static) project.