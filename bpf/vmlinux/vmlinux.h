#if defined(__TARGET_ARCH_amd64)
#include "vmlinux_amd64.h"
#elif defined(__TARGET_ARCH_arm64)
#include "vmlinux_arm64.h"
#else
#error "Unknown architecture"
#endif
