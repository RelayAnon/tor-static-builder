// Example of creating an onion service with embedded Tor
package main

import (
	"context"
	"crypto/ed25519"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/RelayAnon/tor-static-builder/embed"
	"github.com/cretz/bine/tor"
)

// loadOrCreateKey loads an existing ed25519 key or creates a new one
func loadOrCreateKey(keyPath string) (ed25519.PrivateKey, bool, error) {
	// Try to load existing key
	if keyData, err := os.ReadFile(keyPath); err == nil {
		if len(keyData) == ed25519.PrivateKeySize {
			return ed25519.PrivateKey(keyData), true, nil
		}
	}
	
	// Generate new key
	_, privKey, err := ed25519.GenerateKey(nil)
	if err != nil {
		return nil, false, err
	}
	
	// Save key as raw bytes
	if err := os.WriteFile(keyPath, privKey, 0600); err != nil {
		return nil, false, err
	}
	
	return privKey, false, nil
}

func main() {
	fmt.Println("Starting onion service example...")

	// Create context
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start Tor with persistent data directory
	fmt.Println("Starting embedded Tor...")
	config := embed.DefaultConfig()
	config.DataDir = "./tor-data"
	
	// Create data directory if it doesn't exist
	if err := os.MkdirAll(config.DataDir, 0700); err != nil {
		log.Fatalf("Failed to create data directory: %v", err)
	}
	
	t, err := embed.StartTorWithBootstrap(ctx, config.DataDir, config.BootstrapTimeout)
	if err != nil {
		log.Fatalf("Failed to start Tor: %v", err)
	}

	fmt.Println("Tor bootstrapped! Creating onion service...")

	// Create an HTTP handler
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Tor! 🧅\n")
		fmt.Fprintf(w, "Current time: %s\n", time.Now().Format(time.RFC3339))
		fmt.Fprintf(w, "Your path: %s\n", r.URL.Path)
	})

	// Load or create persistent key
	keyDir := "./tor-data"
	if err := os.MkdirAll(keyDir, 0700); err != nil {
		log.Fatalf("Failed to create key directory: %v", err)
	}
	
	keyPath := filepath.Join(keyDir, "onion_key")
	privKey, isExisting, err := loadOrCreateKey(keyPath)
	if err != nil {
		log.Fatalf("Failed to load/create key: %v", err)
	}
	
	if isExisting {
		fmt.Println("✓ Using existing onion service key (address will remain the same)")
	} else {
		fmt.Println("✓ Created new onion service key (address will persist across restarts)")
	}
	
	// Create onion service with persistent key
	onion, err := t.Listen(ctx, &tor.ListenConf{
		RemotePorts: []int{80},
		Version3:    true,
		Key:         privKey,
	})
	if err != nil {
		log.Fatalf("Failed to create onion service: %v", err)
	}

	onionAddr := fmt.Sprintf("%s.onion", onion.ID)
	embed.SetOnionAddress(onionAddr)

	fmt.Println("========================================")
	fmt.Printf("Onion service is running!\n")
	fmt.Printf("Address: http://%s\n", onionAddr)
	fmt.Println("========================================")
	fmt.Println("\nYou can access this service using Tor Browser")
	fmt.Println("The address will remain the same across restarts")
	fmt.Println("Press Ctrl+C to stop...")

	// Start HTTP server in a goroutine
	go func() {
		server := &http.Server{
			Handler:      mux,
			ReadTimeout:  15 * time.Second,
			WriteTimeout: 15 * time.Second,
			IdleTimeout:  60 * time.Second,
		}
		if err := server.Serve(onion); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	// Test the onion service locally (optional)
	go func() {
		time.Sleep(5 * time.Second)
		fmt.Println("\nTesting onion service locally...")
		
		// Create a dialer through Tor
		dialer, err := t.Dialer(ctx, nil)
		if err != nil {
			log.Printf("Failed to create dialer: %v", err)
			return
		}

		// Make HTTP client that uses Tor
		client := &http.Client{
			Transport: &http.Transport{
				DialContext: dialer.DialContext,
			},
			Timeout: 30 * time.Second,
		}

		// Test the service
		resp, err := client.Get(fmt.Sprintf("http://%s", onionAddr))
		if err != nil {
			log.Printf("Failed to connect to onion service: %v", err)
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			log.Printf("Failed to read response: %v", err)
			return
		}

		fmt.Println("\nSelf-test successful! Response:")
		fmt.Println(string(body))
	}()

	// Handle shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	
	// Wait for shutdown signal
	sig := <-sigChan
	fmt.Printf("\nReceived signal: %v\n", sig)
	fmt.Println("Shutting down...")
	
	// Clean shutdown
	onion.Close()
	if err := embed.StopTor(); err != nil {
		log.Printf("Error stopping Tor: %v", err)
	}
}