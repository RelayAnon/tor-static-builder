# Example: Using Tor Static Libraries in Your Go Project

## Project Structure

```
your-go-project/
├── cmd/
│   ├── embedded/
│   │   └── tor-0.4.8/
│   │       └── process.go  (from templates/process.go)
│   ├── tor_embedded.go
│   ├── tor_regular.go
│   └── main.go
├── tor-libs/               (copy from output/)
│   ├── lib/
│   │   ├── libtor.a
│   │   ├── libssl.a
│   │   ├── libcrypto.a
│   │   ├── libevent.a
│   │   ├── libz.a
│   │   └── libcap.a
│   └── include/
│       └── tor_api.h
└── go.mod
```

## Step 1: Build the Static Libraries

```bash
# Using Docker
cd tor-static-builder
make build

# Copy output to your project
cp -r output/* /path/to/your-project/tor-libs/
```

## Step 2: Create Build Tag Files

**cmd/tor_embedded.go** (with build tag):
```go
//go:build embedded
// +build embedded

package cmd

import (
    "github.com/cretz/bine/process"
    tor048 "yourproject/cmd/embedded/tor-0.4.8"
)

func getProcessCreator() process.Creator {
    return tor048.NewCreator()
}

func isEmbedded() bool {
    return true
}
```

**cmd/tor_regular.go** (without build tag):
```go
//go:build !embedded
// +build !embedded

package cmd

import "github.com/cretz/bine/process"

func getProcessCreator() process.Creator {
    return nil
}

func isEmbedded() bool {
    return false
}
```

## Step 3: Update process.go CGO Paths

Edit `cmd/embedded/tor-0.4.8/process.go`:

```go
/*
#cgo CFLAGS: -I${SRCDIR}/../../../tor-libs/include
#cgo LDFLAGS: -L${SRCDIR}/../../../tor-libs/lib -ltor
#cgo LDFLAGS: -L${SRCDIR}/../../../tor-libs/lib -levent
#cgo LDFLAGS: -L${SRCDIR}/../../../tor-libs/lib -lz
#cgo LDFLAGS: -L${SRCDIR}/../../../tor-libs/lib -lssl -lcrypto
#cgo LDFLAGS: -L${SRCDIR}/../../../tor-libs/lib -lcap
#cgo LDFLAGS: -lm -lpthread -ldl -static-libgcc
*/
import "C"
```

## Step 4: Build Your Application

### Regular build (uses system Tor):
```bash
go build -o myapp .
```

### Embedded build (Tor included in binary):
```bash
CGO_ENABLED=1 go build -tags embedded \
    -ldflags "-linkmode external -extldflags '-static'" \
    -o myapp-embedded .
```

## Step 5: Verify the Binary

```bash
# Check size (embedded should be ~26MB larger)
ls -lh myapp myapp-embedded

# Check for dynamic dependencies
ldd myapp-embedded
# Should show: "not a dynamic executable" or minimal dependencies

# Run the embedded version
./myapp-embedded --version
```

## Complete Example Code

**main.go**:
```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"
    
    "github.com/cretz/bine/tor"
    "yourproject/cmd"
)

func main() {
    fmt.Printf("Starting with embedded Tor: %v\n", cmd.IsEmbedded())
    
    // Start Tor
    startConf := &tor.StartConf{
        ProcessCreator: cmd.GetProcessCreator(),
        DataDir:        "/tmp/tor-data",
    }
    
    t, err := tor.Start(context.Background(), startConf)
    if err != nil {
        log.Fatal(err)
    }
    defer t.Close()
    
    // Enable network and wait for bootstrap
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
    defer cancel()
    
    if err := t.EnableNetwork(ctx, true); err != nil {
        log.Fatal(err)
    }
    
    fmt.Println("Tor bootstrapped successfully!")
    
    // Create an onion service
    onion, err := t.Listen(context.Background(), &tor.ListenConf{
        RemotePorts: []int{80},
        Version3:    true,
    })
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Printf("Onion service: %s.onion\n", onion.ID)
}
```

## Makefile for Your Project

```makefile
.PHONY: build build-embedded clean

# Regular build (requires system Tor)
build:
	go build -o myapp .

# Embedded build (includes Tor)
build-embedded:
	CGO_ENABLED=1 go build -tags embedded \
		-ldflags "-linkmode external -extldflags '-static'" \
		-o myapp-embedded .

# Build both versions
all: build build-embedded

clean:
	rm -f myapp myapp-embedded

test:
	go test ./...

# Check binary size and dependencies
check-embedded:
	@echo "Binary size:"
	@ls -lh myapp-embedded
	@echo ""
	@echo "Dynamic dependencies:"
	@ldd myapp-embedded || echo "Static binary (no dynamic deps)"
```

## Troubleshooting

### CGO Errors
- Ensure `CGO_ENABLED=1` is set
- Check that all library paths in process.go are correct
- Verify all .a files exist in tor-libs/lib/

### Linking Errors
- The order of `-l` flags matters
- Make sure `-static-libgcc` is included
- On some systems, you may need to add `-static` to extldflags

### Runtime Errors
- "tor: executable file not found": You're running the non-embedded version
- "Unable to create conn from control socket": Check file descriptors/permissions
- Bootstrap timeout: Increase timeout or check network connectivity

## Notes

- The embedded binary will be ~26MB larger than the regular version
- First startup may be slower as Tor bootstraps
- The binary is fully self-contained and portable
- Works on Linux x86_64; other architectures need cross-compilation