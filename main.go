// SPDX-License-Identifier: Apache-2.0
package main

import (
	"context"
	"log"
	"os/signal"
	"sync"
	"syscall"

	"github.com/cilium/ebpf/rlimit"

	"github.com/upwindsecurity/ebpf-demo/internal/ebpf"
)

func main() {
	// Set up signal handling to gracefully shut down on interrupt signals.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	defer stop()

	// Allow the current process to lock memory for eBPF resources.
	must(rlimit.RemoveMemlock(), "memlock error")

	processExec := new(ebpf.ProcessExecTracePoint)
	must(processExec.Start(), "processExec start")
	defer func() {
		if err := processExec.Close(); err != nil {
			log.Printf("Error closing processExec: %v", err)
		}
	}()

	// Set up waitgroup to wait for goroutines to finish.
	var wg sync.WaitGroup

	// Start a goroutine to read events from the eBPF program.
	// A read failure cancels the context so main can shut down cleanly;
	// log.Fatalf is avoided here because it would skip the deferred cleanup.
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := processExec.Read(ctx); err != nil {
			log.Printf("processExec read: %v", err)
			stop()
		}
	}()

	// Wait for a signal to stop the program, then wait for the reader to finish.
	<-ctx.Done()
	log.Println("Received signal, exiting program...")

	wg.Wait()
}

func must(err error, msg string) {
	if err != nil {
		log.Fatalf("%s: %v", msg, err)
	}
}
