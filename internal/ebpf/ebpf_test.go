// SPDX-License-Identifier: Apache-2.0
package ebpf

import (
	"bytes"
	"encoding/binary"
	"testing"
)

// marshalEvent encodes a bpfProcessExecEvent to its little-endian wire form,
// matching what the kernel writes into the ring buffer.
func marshalEvent(t *testing.T, event bpfProcessExecEvent) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := binary.Write(&buf, binary.LittleEndian, &event); err != nil {
		t.Fatalf("marshalEvent: %v", err)
	}

	return buf.Bytes()
}

// makeComm builds a NUL-padded 16-byte comm field from a string.
func makeComm(s string) [16]uint8 {
	var comm [16]uint8
	copy(comm[:], s)

	return comm
}

// makeFilename builds a NUL-padded 512-byte filename field from a string.
func makeFilename(s string) [512]uint8 {
	var filename [512]uint8
	copy(filename[:], s)

	return filename
}

func TestParseEvent(t *testing.T) {
	valid := bpfProcessExecEvent{
		Pid:         1234,
		Comm:        makeComm("bash"),
		Filename:    makeFilename("/usr/bin/ls"),
		FilenameLen: int32(len("/usr/bin/ls")),
	}

	tests := []struct {
		name    string
		raw     []byte
		wantErr bool
		want    bpfProcessExecEvent
	}{
		{
			name: "valid sample",
			raw:  marshalEvent(t, valid),
			want: valid,
		},
		{
			name:    "short buffer",
			raw:     make([]byte, 10),
			wantErr: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseEvent(tc.raw)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("parseEvent(%d bytes): expected error, got nil", len(tc.raw))
				}

				return
			}
			if err != nil {
				t.Fatalf("parseEvent: unexpected error: %v", err)
			}
			if got.Pid != tc.want.Pid {
				t.Errorf("Pid = %d, want %d", got.Pid, tc.want.Pid)
			}
			if got.Comm != tc.want.Comm {
				t.Errorf("Comm = %v, want %v", got.Comm, tc.want.Comm)
			}
			if got.Filename != tc.want.Filename {
				t.Errorf("Filename mismatch")
			}
			if got.FilenameLen != tc.want.FilenameLen {
				t.Errorf("FilenameLen = %d, want %d", got.FilenameLen, tc.want.FilenameLen)
			}
		})
	}
}

func TestCString(t *testing.T) {
	tests := []struct {
		name string
		in   []byte
		want string
	}{
		{
			name: "nul terminated",
			in:   append([]byte("bash"), make([]byte, 12)...),
			want: "bash",
		},
		{
			name: "no nul",
			in:   []byte("bash"),
			want: "bash",
		},
		{
			name: "empty slice",
			in:   []byte{},
			want: "",
		},
		{
			name: "nul at index zero",
			in:   []byte{0, 'b', 'a', 'd'},
			want: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := cString(tc.in); got != tc.want {
				t.Errorf("cString(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
