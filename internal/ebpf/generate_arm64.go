//go:build arm64

package ebpf

//go:generate sh -c "echo Generating for arm64"
//go:generate sh -c "echo Using cflags: $BPF_CFLAGS"
//go:generate go run github.com/cilium/ebpf/cmd/bpf2go -cflags "$BPF_CFLAGS" -type exec_data_t -target arm64 bpf ../../bpf/program.bpf.c -- -I../../bpf/vmlinux -I../../bpf/libbpf -D__TARGET_ARCH_arm64
