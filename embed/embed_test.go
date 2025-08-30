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

