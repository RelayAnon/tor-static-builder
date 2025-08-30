// Basic example of using embedded Tor
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/RelayAnon/tor-static-builder/embed"
)

func main() {
	fmt.Println("Starting embedded Tor example...")
	fmt.Printf("Tor version: %s\n", embed.GetVersion())

	// Create context that cancels on interrupt
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start Tor with bootstrap
	fmt.Println("Starting Tor (this may take a minute)...")
	t, err := embed.QuickStart(ctx)
	if err != nil {
		log.Fatalf("Failed to start Tor: %v", err)
	}
	
	// Handle shutdown gracefully
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigChan
		fmt.Printf("\nReceived signal: %v\n", sig)
		fmt.Println("Shutting down Tor...")
		if err := embed.StopTor(); err != nil {
			log.Printf("Error stopping Tor: %v", err)
		}
		cancel()
		// Exit immediately after cleanup
		os.Exit(0)
	}()

	fmt.Println("Tor is running and bootstrapped!")
	
	// Get some information
	info, err := t.Control.GetInfo("version", "config-file")
	if err != nil {
		log.Printf("Failed to get info: %v", err)
	} else {
		for _, i := range info {
			fmt.Printf("%s: %s\n", i.Key, i.Val)
		}
	}

	fmt.Println("\nPress Ctrl+C to exit...")
	
	// Wait for context cancellation
	<-ctx.Done()
	
	// If we get here without signal handler, do cleanup
	fmt.Println("Context cancelled, cleaning up...")
	if err := embed.StopTor(); err != nil {
		log.Printf("Error stopping Tor: %v", err)
	}
}