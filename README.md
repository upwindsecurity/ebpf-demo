# ebpf-demo

Demo eBPF Program.

This program uses an eBPF Tracepoint, `sched/sched_process_exec`, to monitor new processes being executed.

Tracepoints are eBPF programs that attach to pre-defined trace points in the linux kernel. These tracepoints are often placed in locations which are interesting or common locations to measure performance.

## Requirements

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
