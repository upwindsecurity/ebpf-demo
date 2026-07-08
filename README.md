# ebpf-demo

Demo eBPF Program.

This program uses an eBPF Tracepoint, `sched/sched_process_exec`, to monitor new processes being executed. Events are passed from the kernel to the Go user-space program through a BPF ring buffer, which reads and logs them.

Tracepoints are eBPF programs that attach to pre-defined trace points in the linux kernel. These tracepoints are often placed in locations which are interesting or common locations to measure performance.

## Requirements

### Kernel

The target Linux kernel must be **>= 5.8** (for the BPF ring buffer) and built with `CONFIG_DEBUG_INFO_BTF=y`. That option exposes `/sys/kernel/btf/vmlinux`, which is required both for CO-RE (Compile Once – Run Everywhere) and for regenerating the vmlinux headers.

### macOS

* [Lima](https://lima-vm.io)
* QEMU

When running on **macOS** you need to build and run this in a Linux virtual machine (VM). On macOS 13.0+ VMs can also be run
using macOS's Virtualization Framework (**vz**) instead of QEMU but it has some limitations so QEMU is preferred.

**_Note_**: Some of the limitations of **vz** are that it fails to cross-compile for multiple architectures and also can not
emulate a different architecture and can only run VMs using its own native architecture; example M3 Macs (arm64 arch) can only
run arm64 VMs.

#### Install Dependencies (macOS)

```shell
brew bundle
```

Start a virtual machine using Lima and QEMU, and getting a terminal:

```shell
limactl start ./lima/ebpf-demo.yaml
limactl shell ebpf-demo
```

Or use the Make shortcuts, which wrap the commands above: `make lima-start` to bring the VM up and `make lima-shell` to open a shell in it.

* To start the VM using a different architecture add `--arch=<ARCH>` where `<ARCH>` can be one of: `x86_64` or `aarch64`.

## Linux

* Go
* linux-tools
* build-essential
* llvm
* clang
* libbpf-dev
* libelf-dev
* libpcap-dev
* bpftool
* curl

### Install Dependencies (Linux)

* [Install Go](https://go.dev/doc/install)
* Install dependencies:

    ```shell
    export KERNEL_VERSION=`uname -r`
    apt-get update -q
    apt-get install -q -y \
    apt-transport-https ca-certificates curl \
    linux-tools-common linux-tools-generic linux-tools-${KERNEL_VERSION} \
    build-essential llvm clang \
    libbpf-dev libelf-dev libpcap-dev
    ```

* Install BPFTool

    ```shell
    git clone --recurse-submodules https://github.com/libbpf/bpftool.git /tmp/bpftool
    pushd /tmp/bpftool/src
    make install
    popd
    ```

## Building

On a linux environment run `make build`.

Since the generated Go bindings and compiled BPF objects are committed to the repo, a plain `go build` also works from a clean clone with only the Go toolchain — no clang or Linux required. The full toolchain is only needed when the BPF C source changes.

## Code generation and headers

* **Go bindings and BPF objects** are produced by [bpf2go](https://github.com/cilium/ebpf), which compiles `bpf/program.bpf.c` into per-arch Go bindings and compiled BPF objects via the `//go:generate` directives in `internal/ebpf/generate_{amd64,arm64}.go`. Run `make generate` on Linux.
* Both the generated `.go` and `.o` files are **committed to the repo**, so a plain `go build` works from a clean clone. Regeneration is only needed when the BPF C source changes.
* **libbpf helper headers** are vendored under `bpf/libbpf/`, pinned to `LIBBPF_VERSION` in the `Makefile`, and refreshed with `make update-libbpf-headers`.
* **vmlinux headers** are generated per-arch with `bpftool btf dump file /sys/kernel/btf/vmlinux format c` (`make vmlinux`) and committed under `bpf/vmlinux/`. The correct arch is selected by `bpf/vmlinux/vmlinux.h`, keyed on the standard `__TARGET_ARCH_x86` / `__TARGET_ARCH_arm64` macros. The source kernel version for each arch is recorded in `bpf/vmlinux/version_<arch>`.

## Make targets

Run `make help` to see all targets. The main ones:

| Target | Description |
| --- | --- |
| `make all` | Build everything (vmlinux, libbpf, generate, build) |
| `make build` | Build the main binary (`./demo`) |
| `make generate` | Generate Go eBPF bindings and objects |
| `make vmlinux` | Generate the vmlinux header files |
| `make update-libbpf-headers` | Refresh the vendored libbpf headers |
| `make test` | Run tests |
| `make lint` | Run the linter |
| `make lima-{start,stop,shell,generate,build}` | Manage and run inside the Lima VM (macOS) |
| `make docker-{build,run,stop,logs}` | Build and run the app in Docker |

## Running

Running applications that load BPF programs needs privilege so running the application as root or using `sudo` is required.

```shell
sudo ./demo
```

## Links

Some useful links for additional information and learning about **eBPF**:

* [Official Documentary - eBPF: Unlocking the Kernel](https://www.youtube.com/watch?v=Wb_vD3XZYOA)
* [eBPF.io](https://ebpf.io)
* [eBPF Docs](https://docs.ebpf.io)
* [eBPF Labs](https://ebpf.io/labs/)
* [eBPF Books](https://ebpf.io/get-started/#books)
