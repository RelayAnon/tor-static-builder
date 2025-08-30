package embed

import (
	"fmt"
	"sync"
	"testing"
)

func TestConcurrentOnionAddressAccess(t *testing.T) {
	const numGoroutines = 100
	const numOperations = 1000

	var wg sync.WaitGroup
	wg.Add(numGoroutines)

	// Clear initial state
	SetOnionAddress("")

	// Launch concurrent readers and writers
	for i := 0; i < numGoroutines; i++ {
		go func(id int) {
			defer wg.Done()
			
			for j := 0; j < numOperations; j++ {
				if id%2 == 0 {
					// Even goroutines write
					addr := fmt.Sprintf("test%d_%d.onion", id, j)
					SetOnionAddress(addr)
				} else {
					// Odd goroutines read
					_ = GetOnionAddress()
				}
			}
		}(i)
	}

	wg.Wait()

	// Should have some address set
	finalAddr := GetOnionAddress()
	if finalAddr == "" {
		t.Error("Expected some address to be set after concurrent access")
	}
	
	// Clear for other tests
	SetOnionAddress("")
}

func TestConcurrentTorInstanceAccess(t *testing.T) {
	const numGoroutines = 50
	const numReads = 1000

	// Note: We don't actually start Tor here, just test the atomic access
	var wg sync.WaitGroup
	wg.Add(numGoroutines)

	// Concurrent reads should not panic
	for i := 0; i < numGoroutines; i++ {
		go func() {
			defer wg.Done()
			
			for j := 0; j < numReads; j++ {
				instance := GetTorInstance()
				// Should be nil since we haven't started Tor
				if instance != nil {
					t.Error("Expected nil instance when Tor not started")
				}
			}
		}()
	}

	wg.Wait()
}

func TestRaceConditionSafety(t *testing.T) {
	// This test is mainly for running with -race flag
	// go test -race ./embed
	
	const iterations = 100
	
	done := make(chan bool)
	
	// Writer goroutine
	go func() {
		for i := 0; i < iterations; i++ {
			SetOnionAddress(fmt.Sprintf("addr%d.onion", i))
		}
		done <- true
	}()
	
	// Multiple reader goroutines
	for i := 0; i < 5; i++ {
		go func() {
			for j := 0; j < iterations; j++ {
				_ = GetOnionAddress()
			}
			done <- true
		}()
	}
	
	// Wait for all goroutines
	for i := 0; i < 6; i++ {
		<-done
	}
	
	// Clear state
	SetOnionAddress("")
}

func TestConcurrentConfigAccess(t *testing.T) {
	const numGoroutines = 10
	const numOperations = 100

	var wg sync.WaitGroup
	wg.Add(numGoroutines)

	// Multiple goroutines creating and using configs
	for i := 0; i < numGoroutines; i++ {
		go func(id int) {
			defer wg.Done()
			
			for j := 0; j < numOperations; j++ {
				config := DefaultConfig()
				config.SocksPort = 9050 + id
				config.ControlPort = 9051 + id
				
				args := config.BuildExtraArgs()
				if len(args) == 0 {
					t.Error("Expected non-empty args")
				}
			}
		}(i)
	}

	wg.Wait()
}

