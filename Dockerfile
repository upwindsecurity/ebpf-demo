FROM ubuntu:22.04 as builder
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
ARG GO_VERSION=1.21.5
ENV PATH $PATH:/usr/local/go/bin
RUN curl -sL https://go.dev/dl/go${GO_VERSION}.${BUILDOS}-${BUILDARCH}.tar.gz | tar -v -C /usr/local -xz
WORKDIR /opt/ebpf-demo
COPY . . 
RUN make

FROM scratch
COPY --from=builder /opt/ebpf-demo/demo /opt/ebpf-demo/bin/
CMD ["/opt/ebpf-demo/bin/demo"]
