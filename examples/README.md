# Embedded Tor Examples

This directory contains example programs demonstrating how to use the tor-static-builder Go module to embed Tor in your applications.

## Basic Example

The `basic/` example shows minimal Tor embedding:
- Starts embedded Tor
- Waits for bootstrap
- Shows version info
- **Clean shutdown with single Ctrl+C**

```bash
cd basic
go build -tags prod -o test-basic .
./test-basic
```

## Onion Service Example

The `onion-service/` example demonstrates creating a persistent onion service:
- Starts embedded Tor
- Creates an HTTP onion service
- **Persists keys in `./tor-data/onion-keys/`**
- **The .onion address remains the same across restarts**
- Self-tests the service through Tor
- **Clean shutdown with single Ctrl+C**

```bash
cd onion-service
go build -tags prod -o test-onion .
./test-onion
```

### Persistent Onion Addresses

The onion service example stores its keys in `./tor-data/onion-keys/`. This means:

1. **First run**: Creates a new onion service and saves the keys
2. **Subsequent runs**: Reuses the same keys, keeping the same .onion address
3. **To get a new address**: Delete `./tor-data/onion-keys/` and restart

This is important for production services where you want a stable .onion URL that users can bookmark.

## Building the Examples

Both examples require the Tor static libraries to be built first:

```bash
# From the repository root
make all    # Build everything (libraries + examples)
```

Or step by step:
```bash
make build  # Build Tor libraries first
make test   # Then build all examples
```

Or build examples individually:
```bash
make test-basic  # Build just the basic example
make test-onion  # Build just the onion service example
```

## Binary Sizes

With embedded Tor, the binaries are self-contained:
- Basic example: ~15MB
- Onion service: ~20MB

These binaries include the entire Tor daemon and don't require any external Tor installation.

## Signal Handling

Both examples properly handle Ctrl+C:
- First Ctrl+C triggers clean shutdown
- Tor is stopped gracefully
- Connections are closed properly
- No "broken pipe" errors

## Data Directories

- Basic example: Uses temporary directory (new each time)
- Onion service: Uses `./tor-data/` (persistent)

The persistent data directory for the onion service ensures:
- Faster startup (cached network consensus)
- Same .onion address across restarts
- Preserved guard nodes for better security