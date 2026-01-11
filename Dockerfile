# Dockerfile for osmo-remsim server and bankd
#
# This image builds and runs the osmo-remsim server and bank daemon (bankd)
# with support for USB smart card readers (like octosim).
#
# Usage:
#   docker build -t osmo-remsim .
#   docker run -d --name remsim-server -p 9997:9997 -p 9998:9998 osmo-remsim
#
# For bankd with USB access (octosim):
#   docker run -d --name remsim-bankd \
#     --privileged \
#     -v /dev/bus/usb:/dev/bus/usb \
#     -e REMSIM_SERVER_HOST=remsim-server \
#     osmo-remsim bankd
#
# Build stages:
#   1. Build stage: Compiles all dependencies and osmo-remsim
#   2. Runtime stage: Minimal image with just the binaries

FROM debian:bookworm-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libtalloc-dev \
    libpcsclite-dev \
    libusb-1.0-0-dev \
    libcsv-dev \
    libjansson-dev \
    libulfius-dev \
    liborcania-dev \
    liburing-dev \
    libsctp-dev \
    libmnl-dev \
    python3 \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy source code
COPY . /build/osmo-remsim

# Build osmo-remsim (full build including server and bankd)
WORKDIR /build/osmo-remsim
RUN ./build.sh --install

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libtalloc2 \
    libpcsclite1 \
    libusb-1.0-0 \
    libcsv3 \
    libjansson4 \
    libulfius2.7 \
    liborcania2.3 \
    liburing2 \
    libsctp1 \
    libmnl0 \
    pcscd \
    pcsc-tools \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built binaries and libraries from builder
COPY --from=builder /usr/local/bin/osmo-remsim-* /usr/local/bin/
COPY --from=builder /usr/local/lib/libosmo* /usr/local/lib/

# Copy dependency libraries (use shell to handle case when no files match)
RUN --mount=from=builder,source=/build/osmo-remsim/deps/install/lib,target=/mnt/libs \
    find /mnt/libs -name "*.so*" -exec cp {} /usr/local/lib/ \; 2>/dev/null || true

# Update library cache
RUN ldconfig

# Copy default configuration files
COPY --from=builder /build/osmo-remsim/contrib/etc_default/osmo-remsim-bankd /etc/default/
COPY --from=builder /build/osmo-remsim/contrib/etc_default/osmo-remsim-client /etc/default/

# Create configuration directory
RUN mkdir -p /etc/osmocom

# Create empty bankd_pcsc_slots.csv (required by bankd)
RUN touch /etc/osmocom/bankd_pcsc_slots.csv

# Expose ports
# 9997 - REST API
# 9998 - RSPRO protocol (server <-> bankd/client)
# 9999 - RSPRO protocol (bankd <-> client)
EXPOSE 9997 9998 9999

# Environment variables for configuration
ENV REMSIM_SERVER_HOST=""
ENV REMSIM_SERVER_PORT="9998"
ENV REMSIM_BANK_ID="1"
ENV REMSIM_NUM_SLOTS="8"
ENV REMSIM_BIND_IP=""
ENV REMSIM_BIND_PORT="9999"

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set working directory
WORKDIR /etc/osmocom

ENTRYPOINT ["docker-entrypoint.sh"]

# Default command: run the server
CMD ["server"]
