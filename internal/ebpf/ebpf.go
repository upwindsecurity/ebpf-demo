// SPDX-License-Identifier: Apache-2.0
package ebpf

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
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

// parseEvent decodes a raw ring buffer sample into the bpf2go-generated
// event struct (see -type process_exec_event in the go:generate directives).
func parseEvent(raw []byte) (bpfProcessExecEvent, error) {
	var event bpfProcessExecEvent
	if err := binary.Read(bytes.NewReader(raw), binary.LittleEndian, &event); err != nil {
		return event, fmt.Errorf("parsing event: %w", err)
	}

	return event, nil
}

// cString converts a NUL-terminated byte buffer into a Go string.
func cString(b []byte) string {
	if i := bytes.IndexByte(b, 0); i >= 0 {
		return string(b[:i])
	}

	return string(b)
}

func (e *ProcessExecTracePoint) Read(ctx context.Context) error {
	// Close the reader when the context is canceled; Close interrupts a
	// blocked Read. Reader.Close is idempotent, so the deferred Close in
	// main stays safe.
	go func() {
		<-ctx.Done()
		if err := e.reader.Close(); err != nil {
			log.Printf("closing ringbuf reader: %v", err)
		}
	}()

	for {
		record, err := e.reader.Read()
		if err != nil {
			// The ring buffer was closed (context canceled or shutdown), exit gracefully.
			if errors.Is(err, ringbuf.ErrClosed) {
				log.Println("Stopping ProcessExecTracePoint reader...")

				return nil
			}

			return fmt.Errorf("read: %w", err)
		}

		event, err := parseEvent(record.RawSample)
		if err != nil {
			log.Printf("parsing ringbuf event: %s", err)

			continue
		}

		log.Printf("PID: %d Process: %s Filename: %s",
			event.Pid, cString(event.Comm[:]), cString(event.Filename[:]))
	}
}

func (e *ProcessExecTracePoint) Start() error {
	// Load eBPF programs and maps into the kernel.
	log.Printf("Loading ProcessExecTracePoint BPF Objects")
	e.objects = new(bpfObjects)
	if err := loadBpfObjects(e.objects, nil); err != nil {
		return fmt.Errorf("loading objects: %w", err)
	}

	log.Printf("Attaching Tracepoint")
	// SEC("tracepoint/sched/sched_process_exec")
	var err error
	e.link, err = link.Tracepoint("sched", "sched_process_exec", e.objects.SchedProcessExec, nil)
	if err != nil {
		_ = e.objects.Close()

		return fmt.Errorf("attach tracepoint: %w", err)
	}

	log.Printf("Setting up Reader")
	e.reader, err = ringbuf.NewReader(e.objects.Events)
	if err != nil {
		_ = e.link.Close()
		_ = e.objects.Close()

		return fmt.Errorf("create reader: %w", err)
	}

	log.Printf("Successfully started!")

	return nil
}

func (e *ProcessExecTracePoint) Close() error {
	var errs []error
	if e.reader != nil {
		if err := e.reader.Close(); err != nil {
			errs = append(errs, fmt.Errorf("closing reader: %w", err))
		}
	}
	if e.link != nil {
		if err := e.link.Close(); err != nil {
			errs = append(errs, fmt.Errorf("closing link: %w", err))
		}
	}
	if e.objects != nil {
		if err := e.objects.Close(); err != nil {
			errs = append(errs, fmt.Errorf("closing objects: %w", err))
		}
	}

	return errors.Join(errs...)
}
