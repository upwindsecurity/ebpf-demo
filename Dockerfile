# SPDX-License-Identifier: Apache-2.0
FROM ubuntu:22.04 AS builder
RUN apt-get update -y -q && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -q \
        ca-certificates \
        curl \
        git \
        build-essential \
        llvm \
        clang \
        libbpf-dev \
        linux-tools-common \
        linux-tools-generic \
        linux-tools-$(uname -r | rev | cut -d- -f2- | rev)-generic \
    && rm -rf /var/lib/apt/lists/*
ARG BUILDOS BUILDARCH
ARG GO_VERSION=1.24.1
ENV PATH=$PATH:/usr/local/go/bin
RUN curl -sL https://go.dev/dl/go${GO_VERSION}.${BUILDOS}-${BUILDARCH}.tar.gz | tar -v -C /usr/local -xz
WORKDIR /opt/ebpf-demo
COPY . . 
RUN make

FROM scratch
COPY --from=builder /opt/ebpf-demo/demo /opt/ebpf-demo/bin/
CMD ["/opt/ebpf-demo/bin/demo"]
