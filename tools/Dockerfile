FROM ubuntu:22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    clang-14 \
    llvm-14 \
    libelf-dev \
    libzstd-dev \
    zlib1g-dev \
    libc6-dev \
    pkg-config \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Go 1.21
RUN wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz && \
    rm go1.21.6.linux-amd64.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"
ENV CC=clang-14
ENV CLANG=clang-14

# Clone and build ebpf_exporter
WORKDIR /build
RUN git clone https://github.com/cloudflare/ebpf_exporter.git . && \
    make build

# Final image
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    libelf1 \
    libzstd1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/ebpf_exporter /usr/local/bin/ebpf_exporter

# Make it executable
RUN chmod +x /usr/local/bin/ebpf_exporter

ENTRYPOINT ["/usr/local/bin/ebpf_exporter"]
