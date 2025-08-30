package embed

import (
	"testing"
	"time"
)

func TestDefaultConfig(t *testing.T) {
	config := DefaultConfig()
	
	// Check defaults
	if config.SocksPort != 9050 {
		t.Errorf("Expected SocksPort 9050, got %d", config.SocksPort)
	}
	
	if config.ControlPort != 9051 {
		t.Errorf("Expected ControlPort 9051, got %d", config.ControlPort)
	}
	
	if !config.ClientOnly {
		t.Error("Expected ClientOnly to be true by default")
	}
	
	if config.DataDir == "" {
		t.Error("Expected DataDir to be set")
	}
	
	if config.BootstrapTimeout != 2*time.Minute {
		t.Errorf("Expected BootstrapTimeout 2m, got %v", config.BootstrapTimeout)
	}
}

func TestConfigBuildExtraArgs(t *testing.T) {
	tests := []struct {
		name   string
		config Config
		want   map[string]string // expected args as key-value pairs
	}{
		{
			name: "basic config",
			config: Config{
				SocksPort:   9150,
				ControlPort: 9151,
				ClientOnly:  true,
			},
			want: map[string]string{
				"SocksPort":   "9150",
				"ControlPort": "9151",
				"ClientOnly":  "1",
			},
		},
		{
			name: "with log level",
			config: Config{
				SocksPort:   9050,
				ControlPort: 9051,
				LogLevel:    "debug",
			},
			want: map[string]string{
				"SocksPort":   "9050",
				"ControlPort": "9051",
				"Log":         "debug",
			},
		},
		{
			name: "with bridge",
			config: Config{
				SocksPort:   9050,
				ControlPort: 9051,
				Bridge:      "obfs4 192.168.1.1:443",
			},
			want: map[string]string{
				"SocksPort":   "9050",
				"ControlPort": "9051",
				"UseBridges":  "1",
				"Bridge":      "obfs4 192.168.1.1:443",
			},
		},
		{
			name: "disabled ports",
			config: Config{
				SocksPort:   0,
				ControlPort: 0,
			},
			want: map[string]string{
				"SocksPort":   "0",
				"ControlPort": "0",
			},
		},
		{
			name: "with extra args",
			config: Config{
				SocksPort:   9050,
				ControlPort: 9051,
				ExtraArgs: []string{
					"--DNSPort", "5353",
					"--SafeLogging", "1",
				},
			},
			want: map[string]string{
				"SocksPort":    "9050",
				"ControlPort":  "9051",
				"DNSPort":      "5353",
				"SafeLogging":  "1",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			args := tt.config.BuildExtraArgs()
			
			// Convert args slice to map for easier checking
			argsMap := make(map[string]string)
			for i := 0; i < len(args)-1; i += 2 {
				if args[i][:2] == "--" {
					key := args[i][2:] // Remove "--" prefix
					argsMap[key] = args[i+1]
				}
			}
			
			// Check expected values
			for key, expectedVal := range tt.want {
				if val, ok := argsMap[key]; !ok {
					t.Errorf("Missing arg %s", key)
				} else if val != expectedVal {
					t.Errorf("Arg %s: got %s, want %s", key, val, expectedVal)
				}
			}
		})
	}
}

func TestConfigValidation(t *testing.T) {
	tests := []struct {
		name      string
		config    Config
		wantError bool
	}{
		{
			name: "valid config",
			config: Config{
				SocksPort:   9050,
				ControlPort: 9051,
				DataDir:     "/tmp/tor",
			},
			wantError: false,
		},
		{
			name: "negative port",
			config: Config{
				SocksPort:   -1,
				ControlPort: 9051,
			},
			wantError: false, // Currently no validation, but could add
		},
		{
			name: "port too high",
			config: Config{
				SocksPort:   70000,
				ControlPort: 9051,
			},
			wantError: false, // Currently no validation, but could add
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// If we add validation in the future, test it here
			args := tt.config.BuildExtraArgs()
			if len(args) == 0 && !tt.wantError {
				t.Error("Expected args to be built")
			}
		})
	}
}

func TestConfigCopy(t *testing.T) {
	original := Config{
		SocksPort:        9150,
		ControlPort:      9151,
		ClientOnly:       false,
		LogLevel:         "info",
		Bridge:           "test bridge",
		DataDir:          "/custom/dir",
		BootstrapTimeout: 5 * time.Minute,
		ExtraArgs:        []string{"--Test", "1"},
	}

	// Make a copy
	copy := original

	// Modify the copy
	copy.SocksPort = 9250
	copy.ExtraArgs = append(copy.ExtraArgs, "--Another", "2")

	// Original should be unchanged (except for ExtraArgs slice)
	if original.SocksPort != 9150 {
		t.Error("Original SocksPort was modified")
	}

	// Note: ExtraArgs is a slice, so it's shared between copies
	// This is expected Go behavior
	if len(original.ExtraArgs) == len(copy.ExtraArgs) {
		// This is expected due to slice semantics
		t.Log("Note: ExtraArgs slice is shared between copies")
	}
}