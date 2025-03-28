#include "vmlinux.h"
#include "bpf_helpers.h"
#include "bpf_core_read.h"

// Include common definitiona and helpers
#include "common.bpf.h"

// Create a ringbuffer map to store events
// Ringbuffers are a type of BPF map that can be used to store events
// that can be read by user-space programs
struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024); // 256 KB
} events SEC(".maps");

// Data structure to store events
// This structure will be used to store data about process exec events
struct process_exec_event {
	u32 pid;
	u8 comm[TASK_COMM_LEN];
	u8 filename[MAX_FILENAME_LEN];
	int filname_len;
} __attribute__((packed));

struct sched_process_exec_args {
	struct common_tracepoint_entry_args_t common;

	__u32 __data_loc_filename;
	__s8 pid;
	__s8 old_pid;
};

SEC("tracepoint/sched/sched_process_exec")
int sched_process_exec(struct sched_process_exec_args *ctx)
{
	struct process_exec_event *e;
	char unknown[8] = "unknown";

	// Reserve space in the ringbuffer for the event data
	e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
	if (!e) {
		return 0;
	}

	e->pid = LAST_32_BITS(bpf_get_current_pid_tgid());

	bpf_get_current_comm(e->comm, sizeof(e->comm));

	// The __data_loc_filename field encodes the offset (lower 16 bits)
    	// where the filename string is stored, relative to the context pointer.
    	unsigned int offset = ctx->__data_loc_filename & 0xFFFF;

	// Read the filename from the computed address.
    	// Note: bpf_core_read_str() will read up to sizeof(e->filename) bytes.
	long ret =
	bpf_core_read_str(e->filename, sizeof(e->filename), (void *)ctx + offset);

	// If the read fails, copy the string "unknown" to the filename field
	if (ret < 0) {
		bpf_probe_read_kernel_str(e->filename, sizeof(e->filename), unknown);
		ret = sizeof(unknown);
	}

	// Store the length of the filename
	e->filname_len = (int)ret;

	// bpf_printk is a helper function that prints a message to the kernel log
	// This can be useful for debugging, but should be used sparingly
	// The message will be visible in the kernel trace pipe 
	// (e.g. /sys/kernel/debug/tracing/trace_pipe)
	bpf_printk("sched_process_exec filename: %s\n", e->filename);

	// Submit the event to the ringbuffer
	bpf_ringbuf_submit(e, 0);

	return 0;
}

char LICENSE[] SEC("license") = "Dual MIT/GPL";
