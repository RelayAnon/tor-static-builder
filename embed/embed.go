// Package embed provides embedded Tor functionality for Go applications.
// It allows you to include Tor directly in your Go binary without requiring
// a separate Tor installation.
package embed

import (
	"context"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/RelayAnon/tor-static-builder/embed/tor048"
	"github.com/cretz/bine/process"
	"github.com/cretz/bine/tor"
)

// torInstance holds the global Tor instance
var torInstance atomic.Pointer[tor.Tor]

// onionAddress holds the current onion service address
var onionAddress atomic.Pointer[string]

// GetProcessCreator returns the embedded Tor process creator.
// This should be used with bine's tor.StartConf.
func GetProcessCreator() process.Creator {
	return tor048.NewCreator()
}

// IsEmbedded returns true, indicating that Tor is embedded in the binary.
func IsEmbedded() bool {
	return true
}

// GetVersion returns the Tor version string.
func GetVersion() string {
	return tor048.ProviderVersion()
}

// StartTor starts an embedded Tor instance with the given configuration.
// It returns the Tor instance or an error if startup fails.
func StartTor(ctx context.Context, dataDir string, extraArgs ...string) (*tor.Tor, error) {
	// Configure Tor start options
	startConf := &tor.StartConf{
		ProcessCreator:         GetProcessCreator(),
		UseEmbeddedControlConn: true,
		DataDir:                dataDir,
		NoAutoSocksPort:        true,
		ExtraArgs:              extraArgs,
	}

	// Start Tor
	t, err := tor.Start(ctx, startConf)
	if err != nil {
		return nil, fmt.Errorf("failed to start embedded Tor: %w", err)
	}

	// Store the instance
	torInstance.Store(t)
	return t, nil
}

// StartTorWithBootstrap starts Tor and waits for it to bootstrap.
// It's a convenience function that combines StartTor and EnableNetwork.
func StartTorWithBootstrap(ctx context.Context, dataDir string, timeout time.Duration) (*tor.Tor, error) {
	// Start Tor
	t, err := StartTor(ctx, dataDir)
	if err != nil {
		return nil, err
	}

	// Create timeout context for bootstrap
	bootCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	// Enable network and wait for bootstrap
	if err := t.EnableNetwork(bootCtx, true); err != nil {
		t.Close()
		return nil, fmt.Errorf("failed to bootstrap Tor: %w", err)
	}

	return t, nil
}

// GetTorInstance returns the current Tor instance if one is running.
func GetTorInstance() *tor.Tor {
	return torInstance.Load()
}

// GetOnionAddress returns the current onion service address if one is active.
func GetOnionAddress() string {
	addr := onionAddress.Load()
	if addr == nil {
		return ""
	}
	return *addr
}

// SetOnionAddress stores the onion service address for later retrieval.
func SetOnionAddress(addr string) {
	onionAddress.Store(&addr)
}

// StopTor gracefully shuts down the Tor instance if one is running.
func StopTor() error {
	t := torInstance.Load()
	if t == nil {
		return nil
	}

	if err := t.Close(); err != nil {
		return fmt.Errorf("failed to stop Tor: %w", err)
	}

	torInstance.Store(nil)
	return nil
}

// Config provides a simple configuration for embedded Tor.
type Config struct {
	// DataDir is the directory where Tor stores its data
	DataDir string

	// SocksPort is the SOCKS proxy port (0 to disable)
	SocksPort int

	// ControlPort is the control port (0 for auto)
	ControlPort int

	// ClientOnly runs Tor in client-only mode
	ClientOnly bool

	// Timeout for bootstrap process
	BootstrapTimeout time.Duration
}

// DefaultConfig returns a sensible default configuration.
func DefaultConfig() *Config {
	return &Config{
		DataDir:          "/tmp/tor-data",
		SocksPort:        0,
		ControlPort:      0,
		ClientOnly:       true,
		BootstrapTimeout: 3 * time.Minute,
	}
}

// BuildExtraArgs converts a Config to Tor command-line arguments.
func (c *Config) BuildExtraArgs() []string {
	args := []string{}

	if c.SocksPort == 0 {
		args = append(args, "--SocksPort", "0")
	} else {
		args = append(args, "--SocksPort", fmt.Sprintf("%d", c.SocksPort))
	}

	if c.ControlPort == 0 {
		args = append(args, "--ControlPort", "auto")
	} else {
		args = append(args, "--ControlPort", fmt.Sprintf("%d", c.ControlPort))
	}

	if c.ClientOnly {
		args = append(args, "--ClientOnly", "1")
	}

	return args
}

// QuickStart provides the simplest way to start embedded Tor with defaults.
func QuickStart(ctx context.Context) (*tor.Tor, error) {
	config := DefaultConfig()
	return StartTorWithBootstrap(ctx, config.DataDir, config.BootstrapTimeout)
}