// SPDX-License-Identifier: Apache-2.0
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/cilium/ebpf/rlimit"
	"github.com/upwindsecurity/ebpf-demo/internal/ebpf"
)

func main() {
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)

	// Allow the current process to lock memory for eBPF resources.
	must(rlimit.RemoveMemlock(), "memlock error")

	execve := &ebpf.Execve{}
	must(execve.Start(), "execve start")
	defer func() {
		err := execve.Close()
		if err != nil {
			fmt.Println("Error closing execve: ", err)
		}
	}()

	// Set up waitgroup and context for the reader.
	wg := sync.WaitGroup{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	wg.Add(1)
	go func() {
		defer wg.Done()
		must(execve.Read(ctx), "execve read")
	}()

	// Wait for a signal to stop the program.
	// Once the signal is received, cancel the context and wait for the reader to finish.
	<-stop
	log.Println("Received signal, exiting program...")
	cancel()
	wg.Wait()
}

func must(err error, msg ...string) {
	if err != nil {
		m := "error"
		if msg != nil {
			m = msg[0]
		}
		log.Fatalf("%s: %v", m, err)
	}
}
