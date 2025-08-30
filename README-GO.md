# Go Embedded Tor Module

This module provides a simple way to embed Tor directly into your Go applications.

## Installation

### Step 1: Build the Static Libraries

First, build the Tor static libraries:

```bash
git clone https://github.com/RelayAnon/tor-static-builder
cd tor-static-builder
make build  # or ./build-tor-static.sh
```

### Step 2: Import the Module

In your Go project:

```go
import "github.com/RelayAnon/tor-static-builder/embed"
```

## Quick Start

### Simplest Usage

```go
package main

import (
    "context"
    "log"
    "github.com/RelayAnon/tor-static-builder/embed"
)

func main() {
    // Start Tor with defaults
    tor, err := embed.QuickStart(context.Background())
    if err != nil {
        log.Fatal(err)
    }
    defer embed.StopTor()
    
    log.Println("Tor is running!")
}
```

### Creating an Onion Service

```go
package main

import (
    "context"
    "fmt"
    "net/http"
    "github.com/RelayAnon/tor-static-builder/embed"
    "github.com/cretz/bine/tor"
)

func main() {
    // Start Tor
    t, err := embed.QuickStart(context.Background())
    if err != nil {
        panic(err)
    }
    defer embed.StopTor()
    
    // Create onion service
    onion, err := t.Listen(context.Background(), &tor.ListenConf{
        RemotePorts: []int{80},
        Version3:    true,
    })
    if err != nil {
        panic(err)
    }
    
    fmt.Printf("Onion address: %s.onion\n", onion.ID)
    
    // Serve HTTP
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from Tor!")
    })
    http.Serve(onion, nil)
}
```

## API Reference

### Core Functions

#### `QuickStart(ctx context.Context) (*tor.Tor, error)`
Starts Tor with default settings and waits for bootstrap.

#### `StartTor(ctx context.Context, dataDir string, extraArgs ...string) (*tor.Tor, error)`
Starts Tor with custom configuration.

#### `StartTorWithBootstrap(ctx context.Context, dataDir string, timeout time.Duration) (*tor.Tor, error)`
Starts Tor and waits for bootstrap with timeout.

#### `StopTor() error`
Gracefully shuts down the Tor instance.

#### `GetVersion() string`
Returns the embedded Tor version.

#### `IsEmbedded() bool`
Returns true (always embedded when using this module).

### Configuration

#### `DefaultConfig() *Config`
Returns default configuration suitable for most use cases.

#### `Config.BuildExtraArgs() []string`
Converts configuration to Tor command-line arguments.

### Global State

#### `GetTorInstance() *tor.Tor`
Returns the current Tor instance if running.

#### `GetOnionAddress() string`
Returns the current onion service address if set.

#### `SetOnionAddress(addr string)`
Stores an onion address for later retrieval.

## Examples

### Run Examples

```bash
# Basic example
cd examples/basic
go run main.go

# Onion service example
cd examples/onion-service
go run main.go
```

## Building Your Application

### Standard Build

```bash
go build -o myapp main.go
```

### Static Build (Recommended)

```bash
CGO_ENABLED=1 go build \
    -ldflags "-linkmode external -extldflags '-static'" \
    -o myapp main.go
```

### Cross-Compilation

For other architectures, you'll need to:
1. Build Tor static libraries for the target architecture
2. Update CGO flags in `embed/tor048/process.go`
3. Cross-compile with appropriate toolchain

## Requirements

- Go 1.19 or later
- CGO enabled
- Built Tor static libraries in `output/` directory
- Linux x86_64 (for provided binaries)

## Troubleshooting

### "undefined reference" Errors

Ensure all static libraries are built:
```bash
ls -la output/lib/
# Should show: libtor.a, libssl.a, libcrypto.a, libevent.a, libz.a, libcap.a
```

### "tor_api.h: No such file"

Build the libraries first:
```bash
make build
```

### Bootstrap Timeout

Increase timeout in cloud environments:
```go
config := embed.DefaultConfig()
config.BootstrapTimeout = 5 * time.Minute
```

### Binary Size

The embedded binary will be ~26MB larger due to Tor inclusion. Use UPX for compression:
```bash
upx --best myapp  # Reduces size by ~50%
```

## Architecture Support

Currently supports:
- Linux x86_64 (tested)
- Linux ARM64 (with modified build)
- macOS x86_64 (experimental)
- Windows x64 (experimental)

## License

This module is a wrapper around Tor and various libraries, each with their own licenses:
- Tor: BSD-style license
- OpenSSL: Apache License 2.0
- libevent: BSD license
- bine: MIT license