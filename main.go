package main

import (
	"log"
	"os"
	"os/signal"
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
	defer execve.Close()

	go func() {
		must(execve.Read(), "execve read")
	}()

	<-stop
	log.Println("Received signal, exiting program...")
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
