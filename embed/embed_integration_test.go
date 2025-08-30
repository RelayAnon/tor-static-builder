// +build integration

package embed

import (
	"context"
	"testing"
	"time"
)

func TestStartTorIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// Test basic start
	tor, err := StartTor(ctx, t.TempDir())
	if err != nil {
		t.Fatalf("Failed to start Tor: %v", err)
	}
	defer StopTor()

	// Verify instance is set
	if GetTorInstance() == nil {
		t.Error("Tor instance should be set after start")
	}

	// Test control connection
	info, err := tor.Control.GetInfo("version")
	if err != nil {
		t.Errorf("Failed to get version info: %v", err)
	}
	if len(info) == 0 || info[0].Val == "" {
		t.Error("Expected version info")
	}
}

func TestStartTorWithBootstrapIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	ctx := context.Background()
	dataDir := t.TempDir()
	timeout := 3 * time.Minute

	// Start with bootstrap
	tor, err := StartTorWithBootstrap(ctx, dataDir, timeout)
	if err != nil {
		t.Fatalf("Failed to start Tor with bootstrap: %v", err)
	}
	defer StopTor()

	// Verify bootstrapped
	info, err := tor.Control.GetInfo("status/bootstrap-phase")
	if err != nil {
		t.Errorf("Failed to get bootstrap status: %v", err)
	}
	t.Logf("Bootstrap status: %v", info)
}

func TestQuickStartIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	tor, err := QuickStart(ctx)
	if err != nil {
		t.Fatalf("QuickStart failed: %v", err)
	}
	defer StopTor()

	// Should be bootstrapped
	if tor == nil {
		t.Fatal("QuickStart returned nil Tor instance")
	}

	// Test that we can use the connection
	info, err := tor.Control.GetInfo("net/listeners/socks")
	if err != nil {
		t.Errorf("Failed to get SOCKS info: %v", err)
	}
	if len(info) == 0 || info[0].Val == "" {
		t.Error("Expected SOCKS listener info")
	}
}

func TestStopTorIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	ctx := context.Background()

	// Start Tor
	_, err := StartTor(ctx, t.TempDir())
	if err != nil {
		t.Fatalf("Failed to start Tor: %v", err)
	}

	// Verify started
	if GetTorInstance() == nil {
		t.Fatal("Tor instance should be set")
	}

	// Stop Tor
	err = StopTor()
	if err != nil {
		t.Errorf("Failed to stop Tor: %v", err)
	}

	// Verify stopped
	if GetTorInstance() != nil {
		t.Error("Tor instance should be nil after stop")
	}

	// Stop again should be no-op
	err = StopTor()
	if err != nil {
		t.Errorf("Stopping already stopped Tor should not error: %v", err)
	}
}

func TestOnionAddressManagementIntegration(t *testing.T) {
	// Start with no address
	if GetOnionAddress() != "" {
		t.Error("Initial onion address should be empty")
	}

	// Set address
	testAddr := "test1234567890abcdef.onion"
	SetOnionAddress(testAddr)

	// Verify set
	if GetOnionAddress() != testAddr {
		t.Errorf("Got %s, want %s", GetOnionAddress(), testAddr)
	}

	// Update address
	newAddr := "new1234567890abcdef.onion"
	SetOnionAddress(newAddr)

	// Verify updated
	if GetOnionAddress() != newAddr {
		t.Errorf("Got %s, want %s", GetOnionAddress(), newAddr)
	}

	// Clear for other tests
	SetOnionAddress("")
}