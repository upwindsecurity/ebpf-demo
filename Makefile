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
BPFTOOL ?= $(shell which bpftool || false)
GOLANGCI_LINT ?= $(shell which golangci-lint || false)

# BPF
BPF_CFLAGS ?= "-g -O3 -fpie -Wall -Wextra -Wconversion"
bpf_src := $(shell find bpf -name "*.bpf.c")

# LIBBPF Headers
LIBBPF_VERSION = 1.3.0
libbpf_dir = bpf/libbpf
libbpf_headers := $(libbpf_dir)/LICENSE.BSD-2-Clause
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_core_read.h $(libbpf_dir)/bpf_endian.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_helper_defs.h $(libbpf_dir)/bpf_helpers.h
libbpf_headers := $(libbpf_headers) $(libbpf_dir)/bpf_tracing.h

# VMLinux
vmlinux_dir := bpf/vmlinux
vmlinux := $(vmlinux_dir)/vmlinux_$(ARCH).h

# Go files
go_env = CGO_ENABLED=0
go_src = $(shell find . -name "*.go")
go_module  = $(shell go list -m)
go_modules = $(shell go list ./...)

# Go build flags
go_ldflags := -ldflags "-s -w"

# Go generate files
generator_path = internal/ebpf
generator_files = $(foreach arch, $(ARCH), $(generator_path)/generate_$(arch).go)
generated_files = $(foreach ext, o go, $(generator_path)/bpf_bpfel_$(subst amd64,x86,$(ARCH)).$(ext))

.PHONY: all
all: vmlinux libbpf generate build

.PHONY: build
build: $(TARGET)

.PHONY: fmt
fmt:
	@go fmt ./...

.PHONY: lint
lint: generate
ifeq (, $(GOLANGCI_LINT))
	$(error "No golangci-lint in $$PATH. https://golangci-lint.run/usage/install/#local-installation")
endif
	-$(GOLANGCI_LINT) run --enable gofmt --skip-dirs-use-default ./...

.PHONY: test
test:
	go test $(go_modules)

.PHONY: generate
generate: $(generated_files)

$(generated_files): $(generator_files) $(libbpf_headers) $(vmlinux) $(bpf_src)
	@BPF_CFLAGS=$(BPF_CFLAGS) go generate ./...

.PHONY:
update-libbpf-headers:
	@LIBBPF_VERSION=$(LIBBPF_VERSION) scripts/update-libbpf-headers.sh

.PHONY: libbpf
libbpf: $(libbpf_headers)

$(libbpf_headers):
	@LIBBPF_VERSION=$(LIBBPF_VERSION) scripts/update-libbpf-headers.sh

.PHONY: vmlinux
vmlinux: $(vmlinux)

$(vmlinux):
ifeq ($(OS),Darwin)
	$(error "Can not build on MacOs. Run on Linux")
endif
ifeq (, $(BPFTOOL))
	$(error "No bpftool in $$PATH, make sure it is installed.")
endif
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

$(TARGET): $(go_src) $(generated_files)
	$(go_env) go build $(go_ldflags) -o $(TARGET) .

.PHONY: clean
clean:
	rm -f $(TARGET)
	rm -f $(generated_files)

.PHONY: clean-all
clean-all:
	-rm -rf $(TARGET)
	-rm -rf $(generated_files)
	-rm -rf $(vmlinux)
	-rm -rf $(libbpf_headers)

## Docker targets
.PHONY: docker-build docker-run docker-stop docker-logs
docker-build:
	@docker buildx build . -t $(TARGET)

docker-run:
	@-docker run --rm -d --privileged -v /sys/kernel/debug:/sys/kernel/debug --name $(TARGET) $(TARGET)

docker-stop:
	@-docker stop $(TARGET)

docker-logs:
	@-docker logs $(TARGET)


## Lima targets
lima_name := ebpf-demo
lima_env := LIMA_INSTANCE=$(lima_name)
.PHONY: lima-start lima-shell lima-generate lima-build lima-stop lima-remove
lima-start:
	@limactl start --tty=false ./lima/$(lima_name).yaml

lima-shell: lima-start
	@$(lima_env) lima

lima-generate: lima-start
	@$(lima_env) lima make generate

lima-build: lima-start
	@$(lima_env) lima make

lima-stop:
	@limactl stop $(lima_name) -f

lima-remove: lima-stop
	@limactl remove $(lima_name) -f
