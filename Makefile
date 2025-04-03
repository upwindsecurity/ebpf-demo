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
GOLANGCI_LINT ?= $(GO) tool golangci-lint

# BPF
BPF_CFLAGS ?= "-g -O3 -fpie -Wall -Wextra -Wconversion"
bpf_src := $(shell find bpf -name "*.bpf.c")

# LIBBPF Headers
LIBBPF_VERSION = 1.4.7
libbpf_dir = bpf/libbpf
libbpf_headers := $(libbpf_dir)/LICENSE.BSD-2-Clause
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_core_read.h $(libbpf_dir)/bpf_endian.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_helper_defs.h $(libbpf_dir)/bpf_helpers.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_tracing.h

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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: all
all: prereq vmlinux libbpf generate build ## Build everything

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

.PHONY: vmlinux
vmlinux: $(vmlinux) ## Generate vmlinux header files

$(vmlinux):
ifeq ($(OS),Darwin)
	$(error "Can not build on MacOs. Run on Linux\nFor example, use Docker or Lima VM")
endif
ifeq (, $(BPFTOOL))
	$(error "No bpftool in $$PATH, make sure it is installed.")
endif
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

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

VM_NAME ?= ebpf-demo
lima_env := LIMA_INSTANCE=$(VM_NAME)

.PHONY: lima-start lima-stop lima-shell lima-generate lima-build lima-remove
lima-start: lima-prereq lima/ebpf-demo.yaml
	@if [ -z "$$(limactl list | grep $(VM_NAME))" ]; then \
			limactl start --name=$(VM_NAME) --tty=false ./lima/ebpf-demo.yaml; \
	else \
		if [ -z "$$(limactl list | grep Running)" ]; then \
			limactl start $(VM_NAME); \
		else \
			echo "VM $(VM_NAME) already running"; \
		fi; \
	fi

lima-stop: lima-prereq
	@limactl stop $(VM_NAME)

lima-remove: lima-prereq lima-stop
	@limactl remove $(VM_NAME) -f

lima-shell: lima-prereq lima-start
	@$(lima_env) lima

lima-generate: lima-prereq lima-start
	@$(lima_env) lima make generate

lima-vmlinuxh: lima-prereq lima-start
	@$(lima_env) lima make vmlinux

lima-build: lima-prereq lima-start
	@$(lima_env) lima make
