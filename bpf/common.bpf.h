#ifndef __BPF_COMMON_BPF_H
#define __BPF_COMMON_BPF_H
#include "vmlinux.h"

// Define the maximum length of the task comm and filename
// This is the same as the kernel's TASK_COMM_LEN
// and the maximum filename length in the kernel
#define TASK_COMM_LEN 16
#define MAX_FILENAME_LEN 512

// Helpers to extract the first and last 32 bits of a 64-bit value
#define FIRST_32_BITS(x) x >> 32
#define LAST_32_BITS(x) x & 0xFFFFFFFF

struct common_tracepoint_entry_args_t {
	__u16 common_type;
	__u8 common_flags;
	__u8 common_preempt_count;
	__s32 common_pid;
};

#endif // __BPF_COMMON_BPF_H
