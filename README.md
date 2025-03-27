# ebpf-demo

Demo eBPF Program.

## Requirements

When running on **macOS** you need to build and run this in a Linux virtual machine.

Install Dependencies:

```shell
brew bundle
```

Start a virtual machine using [Lima](https://lima-vm.io) and QEMU, and getting a terminal:

```shell
limactl start ./lima/ebpf-demo.yaml
ilamctl shell ebpf-demo
```

## Building

On a linux environment run `make build`.

## Running

Running applications that load BPF programs needs privilege so running the application as root or using `sudo` is required.

```shell
sudo ./demo
```
