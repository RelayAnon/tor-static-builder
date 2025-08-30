# Tor Static Builder for Go Embedding

A complete solution for building statically linked Tor libraries that can be embedded in Go binaries using CGO.

## Features

- Builds Tor 0.4.8.x with all dependencies statically linked
- Includes OpenSSL, libevent, zlib, and libcap
- Produces a single `libtor.a` file containing all Tor code
- Docker-based build environment for reproducibility
- Persistent output volume for build artifacts

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Build and run the container
docker-compose up

# The output files will be in ./output/
ls -la ./output/lib/
```

### Using Docker Directly

```bash
# Build the image
docker build -t tor-static-builder .

# Run with volume mount
docker run -v $(pwd)/output:/output tor-static-builder

# Check the output
ls -la ./output/
```

### Manual Build (Without Docker)

```bash
# Make the script executable
chmod +x build-tor-static.sh

# Set environment variables
export BUILD_DIR=/tmp/tor-build
export OUTPUT_DIR=$(pwd)/output

# Run the build
./build-tor-static.sh
```

## Output Structure

After a successful build, you'll find:

```
output/
├── lib/
│   ├── libtor.a       # Combined Tor static library
│   ├── libssl.a       # OpenSSL SSL
│   ├── libcrypto.a    # OpenSSL Crypto
│   ├── libevent.a     # Libevent
│   ├── libz.a         # Zlib
│   └── libcap.a       # Linux capabilities
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

### For Manual Build
- Ubuntu 22.04 or similar Linux distribution
- GCC and build tools
- automake, autoconf, libtool
- pkg-config
- git, wget, curl
- ~2GB disk space

## Build Time

The complete build process takes approximately 10-20 minutes depending on your system.

## Troubleshooting

### Build fails with "libcap not found"
The script tries multiple locations for libcap. If it's not found, check the build logs.

### "Using 'getaddrinfo' in statically linked applications" warnings
These warnings are expected with glibc. The binary will still work, but for maximum portability consider using musl libc.

### Out of disk space
The build requires about 2GB of space. Use `docker system prune` to clean up if needed.

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