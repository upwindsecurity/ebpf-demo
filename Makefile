# SPDX-License-Identifier: Apache-2.0
#https://clarkgrubb.com/makefile-style-guide
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

TARGET ?= demo

# OS/Platform Information
OS ?= $(shell uname | tr '[:upper:]' '[:lower:]')
ARCH ?= $(shell uname -m)
ARCH := $(subst x86_64,amd64,$(ARCH))
ARCH := $(subst aarch64,arm64,$(ARCH))

# Common variables
empty :=
space := $(empty) $(empty)
comma := ,

# Git SHA and tag Information
git_sha          = $(shell git describe --match=NeVeRmAtCh --always --abbrev=40 --dirty)
git_short_sha    = $(shell git describe --match=NeVeRmAtCh --always --dirty)
git_tag          = $(shell git describe --tags --always --dirty)
git_version_tag  = $(shell git tag --points-at HEAD | grep -P '^v[0-9]+\.[0-9]+\.[0-9]+(?:-(?:alpha|beta|rc)[0-9]+)?$$' || git rev-parse --abbrev-ref HEAD)

# Tools
GO ?= $(shell which go || false)
BPFTOOL ?= $(shell which bpftool || false)
DOCKER ?= $(shell which docker || false)
LIMA ?= $(shell which limactl || false)
GOLANGCI_LINT ?= $(GO) tool -modfile tools/tools.mod golangci-lint

# BPF
BPF_CFLAGS ?= "-g -O2 -Wall -Wextra -Wconversion"
bpf_src := $(shell find bpf -name "*.bpf.c")

# LIBBPF Headers
LIBBPF_VERSION = 1.7.0
libbpf_dir = bpf/libbpf
libbpf_headers := $(libbpf_dir)/LICENSE.BSD-2-Clause
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf/bpf_core_read.h $(libbpf_dir)/bpf/bpf_endian.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf/bpf_helper_defs.h $(libbpf_dir)/bpf/bpf_helpers.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf/bpf_tracing.h

# VMLinux
vmlinux_dir := bpf/vmlinux
vmlinux := $(vmlinux_dir)/vmlinux_$(ARCH).h

# Go files
go_os ?= linux
go_arch ?= $(shell go env GOARCH)
go_env = CGO_ENABLED=0
go_env += GOOS=$(go_os)
go_env += GOARCH=$(go_arch)
go_src = $(shell find . -name "*.go")
go_module  = $(shell go list -m)
go_modules = $(shell go list ./...)

# Go build flags (-s: strip symbol table, -w: strip debug info)
go_ldflags := -ldflags "-s -w"

# Go generate files
# generator_path: Path to eBPF code generator
# generator_files: Architecture-specific generator source files
# generated_files: Output files (object and Go files) for each architecture
generator_path := internal/ebpf
generator_files := $(foreach arch, amd64 arm64, $(generator_path)/generate_$(arch).go)
generated_files := $(foreach ext, o go, $(foreach arch, amd64 arm64, $(generator_path)/bpf_$(subst amd64,x86,$(arch))_bpfel.$(ext)))

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: all
all: vmlinux libbpf generate build ## Build everything

.PHONY: build
build: $(TARGET) ## Build the main target

.PHONY: fmt
fmt: ## Format Go code
	@go fmt ./...

.PHONY: lint
lint: generate ## Run linter
	-$(GOLANGCI_LINT) run  ./...

.PHONY: test
test: ## Run tests
	go test $(go_modules)

.PHONY: generate
generate: $(generated_files) ## Generate Go eBPF code

$(generated_files): $(generator_files) $(libbpf_headers) $(vmlinux) $(bpf_src)
	@BPF_CFLAGS=$(BPF_CFLAGS) GOARCH=amd64 go generate ./...
	@BPF_CFLAGS=$(BPF_CFLAGS) GOARCH=arm64 go generate ./...

.PHONY: update-libbpf-headers
update-libbpf-headers: ## Update libbpf headers
	@LIBBPF_VERSION=$(LIBBPF_VERSION) scripts/update-libbpf-headers.sh

.PHONY: libbpf
libbpf: $(libbpf_headers)

$(libbpf_headers):
	@LIBBPF_VERSION=$(LIBBPF_VERSION) scripts/update-libbpf-headers.sh

# vmlinux re-dumps only when it has to: the recipe compares the running kernel
# (uname -r) against the recorded version_<arch> and dumps just on a mismatch or
# a missing header. macOS can't dump (and has no Linux kernel to compare), so
# there it only checks the committed dump exists.
.PHONY: vmlinux
vmlinux: ## Dump vmlinux.h for the host arch (only when the running kernel differs)
ifeq ($(OS),darwin)
	@test -f $(vmlinux) || { echo "error: $(vmlinux) missing; dump it from Linux, e.g. 'make lima-vmlinuxh-$(ARCH)'"; exit 1; }
	@echo "vmlinux.h ($(ARCH)): can't refresh on macOS; keeping committed dump"
else
ifeq (, $(BPFTOOL))
	$(error "No bpftool in $$PATH, make sure it is installed.")
endif
	@current=$$(uname -r); \
	recorded=$$(cat $(vmlinux_dir)/version_$(ARCH) 2>/dev/null || true); \
	if [ -f "$(vmlinux)" ] && [ "$$current" = "$$recorded" ]; then \
		echo "vmlinux.h ($(ARCH)): up to date ($$current)"; \
	else \
		echo "vmlinux.h ($(ARCH)): dumping $${recorded:-none} -> $$current"; \
		$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $(vmlinux) && \
		echo "$$current" > $(vmlinux_dir)/version_$(ARCH); \
	fi
endif

$(TARGET): $(go_src) $(generated_files)
	$(go_env) go build $(go_ldflags) -o $(TARGET) .

.PHONY: clean
clean: ## Clean workspace
	rm -f $(TARGET)
	rm -f internal/ebpf/bpf_*.o

.PHONY: clean-all
clean-all: ## Clean all
	-rm -rf $(TARGET)
	-rm -rf $(generated_files)
	-rm -rf $(vmlinux)
	-rm -rf $(libbpf_headers)


## Docker targets
.PHONY: docker-prereq docker-build docker-run docker-stop docker-logs
docker-prereq:
ifeq (, $(DOCKER))
	$(error "Docker not found in $$PATH")
endif

.PHONY: docker-build docker-run docker-stop docker-logs
docker-build: docker-prereq
	@docker buildx build . -t $(TARGET)

docker-run: docker-prereq
	@-docker run --rm -d --privileged -v /sys/kernel/debug:/sys/kernel/debug --name $(TARGET) $(TARGET)

docker-stop: docker-prereq
	@-docker stop $(TARGET)

docker-logs: docker-prereq
	@-docker logs $(TARGET)


## Lima VM targets
.PHONY: lima-prereq
lima-prereq:
ifeq (, $(LIMA))
	$(error "limactl not found in $$PATH")
endif

# VM instances are named by architecture so it is always clear which arch a VM
# and its targets operate on. The canonical VM (used by the arch-agnostic
# generate/build targets, which cross-compile every arch from one guest)
# defaults to the host arch; the amd64 dump on an arm64 host is emulated.
VM_NAME ?= ebpf-demo-$(ARCH)
lima_config := tools/lima/ebpf-demo.yaml
lima_env := LIMA_INSTANCE=$(VM_NAME)
# Empty unless a per-arch vmlinuxh target pins a non-native guest architecture.
LIMA_ARCH ?=

.PHONY: lima-start lima-stop lima-shell lima-generate lima-build lima-remove
.PHONY: lima-vmlinuxh lima-vmlinuxh-amd64 lima-vmlinuxh-arm64 lima-vmlinuxh-all
# LIMA_ARCH pins a non-native guest architecture (emulated via qemu). The
# ebpf-demo config lists both the amd64 and arm64 images, so --arch selects
# which one boots; unset means Lima picks the host arch.
lima-start: lima-prereq $(lima_config)
	@if ! limactl list -q 2>/dev/null | grep -qx '$(VM_NAME)'; then \
		limactl start --name=$(VM_NAME) --tty=false $(if $(LIMA_ARCH),--arch=$(LIMA_ARCH)) $(lima_config); \
	elif [ "$$(limactl list $(VM_NAME) --format '{{.Status}}')" != "Running" ]; then \
		limactl start $(VM_NAME); \
	else \
		echo "VM $(VM_NAME) already running"; \
	fi

lima-stop: lima-prereq
	@limactl stop $(VM_NAME)

lima-remove: lima-prereq lima-stop
	@limactl remove $(VM_NAME) -f

lima-shell: lima-prereq lima-start
	@$(lima_env) lima

lima-generate: lima-prereq lima-start
	@$(lima_env) lima make generate

# vmlinux.h is dumped from the guest's running kernel, so each arch's dump must
# come from a guest of that arch. The per-arch targets below invoke this worker
# with a matching VM_NAME/LIMA_ARCH; it is not meant to be called directly.
lima-vmlinuxh: lima-prereq lima-start
	@$(lima_env) lima make vmlinux

lima-vmlinuxh-amd64: lima-prereq ## Dump vmlinux.h for amd64 (emulated on arm64 hosts)
	@$(MAKE) lima-vmlinuxh VM_NAME=ebpf-demo-amd64 LIMA_ARCH=x86_64

lima-vmlinuxh-arm64: lima-prereq ## Dump vmlinux.h for arm64 (emulated on amd64 hosts)
	@$(MAKE) lima-vmlinuxh VM_NAME=ebpf-demo-arm64 LIMA_ARCH=aarch64

# The two dumps use separate VMs and separate arch images, so they are fully
# independent; -j2 runs them concurrently regardless of the outer make's flags.
lima-vmlinuxh-all: lima-prereq ## Dump vmlinux.h for both arches (in parallel)
	@$(MAKE) -j2 lima-vmlinuxh-amd64 lima-vmlinuxh-arm64

lima-build: lima-prereq lima-start
	@$(lima_env) lima make
