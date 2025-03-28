// SPDX-License-Identifier: Apache-2.0
package ebpf

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"log"

	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/ringbuf"
)

type ProcessExecTracePoint struct {
	objects *bpfObjects
	link    link.Link
	reader  *ringbuf.Reader
}

// processExecEvent is the struct that represents the data that is read from the ring buffer.
// This should match the struct defined in the eBPF program.
// (See process_exec_event struct in program.bpf.c)
type processExecEvent struct {
	PID        uint32
	Comm       [16]uint8
	Filename   [512]uint8
	FilnameLen int32
}

func (e *ProcessExecTracePoint) Read(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			// The context was canceled, stop reading events and return.
			return nil
		default:
			ev, err := e.reader.Read()

			if err != nil {
				return fmt.Errorf("read: %w", err)
			}

			b_arr := bytes.NewBuffer(ev.RawSample)

			var data processExecEvent
			if err := binary.Read(b_arr, binary.LittleEndian, &data); err != nil {
				log.Printf("parsing perf event: %s", err)
				continue
			}

			log.Printf("PID: %d Process: %s Filename: %s\n",
				data.PID, data.Comm, data.Filename[:data.FilnameLen])
		}
	}
}

func (e *ProcessExecTracePoint) Start() error {
	// Load eBPF programs and maps into the kernel.
	log.Printf("Loading ProcessExecTracePoint BFP Objects")
	e.objects = new(bpfObjects)
	if err := loadBpfObjects(e.objects, nil); err != nil {
		return fmt.Errorf("loading objects: %w", err)
	}

	log.Printf("Attaching Tracepoint")
	// SEC("tracepoint/sched/sched_process_exec")
	var err error
	e.link, err = link.Tracepoint("sched", "sched_process_exec", e.objects.SchedProcessExec, nil)
	if err != nil {
		return fmt.Errorf("attach tracepoint: %w", err)
	}

	log.Printf("Setting up Reader")
	e.reader, err = ringbuf.NewReader(e.objects.Events)
	if err != nil {
		return fmt.Errorf("create reader: %w", err)
	}

	log.Printf("Successfully started!")

	return nil
}

func (e *ProcessExecTracePoint) Close() error {
	if err := e.reader.Close(); err != nil {
		return fmt.Errorf("closing reader: %w", err)
	}
	if err := e.link.Close(); err != nil {
		return fmt.Errorf("closing link: %w", err)
	}
	if err := e.objects.Close(); err != nil {
		return fmt.Errorf("closing objects: %w", err)
	}

	return nil
}
