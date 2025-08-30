// Package tor048 implements process interfaces for statically linked
// Tor 0.4.8.x versions.
package tor048

import (
	"context"
	"fmt"
	"net"
	"os"

	"github.com/cretz/bine/process"
)

/*
// These paths assume the libraries are built and placed in the output directory
// relative to the module root. Update these if your structure differs.
#cgo CFLAGS: -I${SRCDIR}/../../output/include
#cgo LDFLAGS: -L${SRCDIR}/../../output/lib -ltor
#cgo LDFLAGS: -L${SRCDIR}/../../output/lib -levent
#cgo LDFLAGS: -L${SRCDIR}/../../output/lib -lz
#cgo LDFLAGS: -L${SRCDIR}/../../output/lib -lssl -lcrypto
#cgo LDFLAGS: -L${SRCDIR}/../../output/lib -lcap
#cgo windows LDFLAGS: -lws2_32 -lcrypt32 -lgdi32 -liphlpapi -Wl,-Bstatic -lpthread
#cgo !windows LDFLAGS: -lm -lpthread -ldl -static-libgcc

#include <stdlib.h>
#ifdef _WIN32
	#include <winsock2.h>
#endif
#include <tor_api.h>

// Helper functions for C string array manipulation
static char** makeCharArray(int size) {
	return calloc(sizeof(char*), size);
}

static void setArrayString(char **a, char *s, int n) {
	a[n] = s;
}

static void freeCharArray(char **a, int size) {
	int i;
	for (i = 0; i < size; i++)
		free(a[i]);
	free(a);
}
*/
import "C"

type embeddedCreator struct{}

// ProviderVersion returns the Tor provider name and version exposed from the
// Tor embedded API.
func ProviderVersion() string {
	return C.GoString(C.tor_api_get_provider_version())
}

// NewCreator creates a process.Creator for statically-linked Tor embedded in
// the binary.
func NewCreator() process.Creator {
	return embeddedCreator{}
}

type embeddedProcess struct {
	ctx      context.Context
	mainConf *C.struct_tor_main_configuration_t
	args     []string
	doneCh   chan int
}

// New implements process.Creator.New
func (embeddedCreator) New(ctx context.Context, args ...string) (process.Process, error) {
	return &embeddedProcess{
		ctx:      ctx,
		mainConf: C.tor_main_configuration_new(),
		args:     args,
	}, nil
}

// Start implements process.Process.Start
func (e *embeddedProcess) Start() error {
	if e.doneCh != nil {
		return fmt.Errorf("already started")
	}
	
	// Create the char array for the args
	args := append([]string{"tor"}, e.args...)
	charArray := C.makeCharArray(C.int(len(args)))
	for i, a := range args {
		C.setArrayString(charArray, C.CString(a), C.int(i))
	}
	
	// Build the conf
	if code := C.tor_main_configuration_set_command_line(e.mainConf, C.int(len(args)), charArray); code != 0 {
		C.tor_main_configuration_free(e.mainConf)
		C.freeCharArray(charArray, C.int(len(args)))
		return fmt.Errorf("failed to set command line args, code: %v", int(code))
	}
	
	// Run it async
	e.doneCh = make(chan int, 1)
	go func() {
		defer C.freeCharArray(charArray, C.int(len(args)))
		defer C.tor_main_configuration_free(e.mainConf)
		e.doneCh <- int(C.tor_run_main(e.mainConf))
	}()
	return nil
}

// Wait implements process.Process.Wait
func (e *embeddedProcess) Wait() error {
	if e.doneCh == nil {
		return fmt.Errorf("not started")
	}
	
	ctx := e.ctx
	if ctx == nil {
		ctx = context.Background()
	}
	
	select {
	case <-ctx.Done():
		return ctx.Err()
	case code := <-e.doneCh:
		if code == 0 {
			return nil
		}
		return fmt.Errorf("command completed with error exit code: %v", code)
	}
}

// EmbeddedControlConn implements process.Process.EmbeddedControlConn
func (e *embeddedProcess) EmbeddedControlConn() (net.Conn, error) {
	file := os.NewFile(uintptr(C.tor_main_configuration_setup_control_socket(e.mainConf)), "")
	conn, err := net.FileConn(file)
	if err != nil {
		err = fmt.Errorf("unable to create conn from control socket: %v", err)
	}
	return conn, err
}