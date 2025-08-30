package embed

import (
	"testing"
)

func TestGetProcessCreator(t *testing.T) {
	creator := GetProcessCreator()
	if creator == nil {
		t.Fatal("GetProcessCreator returned nil")
	}
}

func TestIsEmbedded(t *testing.T) {
	if !IsEmbedded() {
		t.Fatal("IsEmbedded should return true")
	}
}

func TestGetVersion(t *testing.T) {
	version := GetVersion()
	if version == "" {
		t.Skip("GetVersion requires built libraries")
	}
	t.Logf("Tor version: %s", version)
}

func TestDefaultConfig(t *testing.T) {
	config := DefaultConfig()
	if config == nil {
		t.Fatal("DefaultConfig returned nil")
	}
	
	if config.DataDir == "" {
		t.Error("DataDir should not be empty")
	}
	
	if config.BootstrapTimeout == 0 {
		t.Error("BootstrapTimeout should not be zero")
	}
}

func TestConfigBuildExtraArgs(t *testing.T) {
	config := &Config{
		SocksPort:   9050,
		ControlPort: 9051,
		ClientOnly:  true,
	}
	
	args := config.BuildExtraArgs()
	if len(args) == 0 {
		t.Error("BuildExtraArgs returned empty slice")
	}
	
	// Check for expected arguments
	hasControl := false
	hasSocks := false
	hasClient := false
	
	for i := 0; i < len(args)-1; i++ {
		switch args[i] {
		case "--SocksPort":
			if args[i+1] == "9050" {
				hasSocks = true
			}
		case "--ControlPort":
			if args[i+1] == "9051" {
				hasControl = true
			}
		case "--ClientOnly":
			if args[i+1] == "1" {
				hasClient = true
			}
		}
	}
	
	if !hasSocks {
		t.Error("SocksPort not found in args")
	}
	if !hasControl {
		t.Error("ControlPort not found in args")
	}
	if !hasClient {
		t.Error("ClientOnly not found in args")
	}
}