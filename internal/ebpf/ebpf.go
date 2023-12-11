package ebpf

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"log"
	"os"

	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/perf"
)

type Execve struct {
	objects *bpfObjects
	link    link.Link
	reader  *perf.Reader
}

func (e *Execve) Read() error {
	for {
		ev, err := e.reader.Read()

		if err != nil {
			return fmt.Errorf("execve: read error: %w", err)
		}

		if ev.LostSamples != 0 {
			log.Printf("execve: perf event ring buffer full, dropped %d samples", ev.LostSamples)
			continue
		}

		b_arr := bytes.NewBuffer(ev.RawSample)

		var data bpfExecDataT
		if err := binary.Read(b_arr, binary.LittleEndian, &data); err != nil {
			log.Printf("parsing perf event: %s", err)
			continue
		}

		log.Printf("On CPU %02d %s ran: %s (PID: %d)\n",
			ev.CPU, data.Comm, data.Fname, data.Pid)
	}
}

func (e *Execve) Start() error {
	// Load pre-compiled programs and maps into the kernel.
	log.Printf("execve: Loading Execve BFP Objects")
	e.objects = &bpfObjects{}
	if err := loadBpfObjects(e.objects, nil); err != nil {
		return fmt.Errorf("execve: loading objects: %w", err)
	}

	log.Printf("execve: Attaching Tracepoint")
	// SEC("tracepoint/syscalls/sys_enter_execve")
	var err error
	e.link, err = link.Tracepoint("syscalls", "sys_enter_execve", e.objects.EnterExecve, nil)
	if err != nil {
		return fmt.Errorf("execve: attach tracepoint: %w", err)
	}

	log.Printf("execve: Setting up Reader")
	e.reader, err = perf.NewReader(e.objects.Events, os.Getpagesize())
	if err != nil {
		return fmt.Errorf("execve: create reader: %w", err)
	}

	log.Printf("execve: Successfully started!")

	return nil
}

func (e *Execve) Close() error {
	if err := e.objects.Close(); err != nil {
		return fmt.Errorf("execve: closing objects: %w", err)
	}
	if err := e.link.Close(); err != nil {
		return fmt.Errorf("execve: closing link: %w", err)
	}
	if err := e.reader.Close(); err != nil {
		return fmt.Errorf("execve: closing reader: %w", err)
	}

	return nil
}
