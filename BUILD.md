# Building osmo-remsim

This document describes how to build osmo-remsim from source, including all prerequisites and dependencies.

## Quick Start

The easiest way to build osmo-remsim is using the provided `build.sh` script:

```bash
# Clone the repository
git clone https://gitea.osmocom.org/sim-card/osmo-remsim
cd osmo-remsim

# Build everything (requires sudo for dependency installation)
./build.sh

# Or build only client components
./build.sh --client-only
```

The build script will:
1. Detect your system's package manager
2. Install required system packages
3. Download and build Osmocom dependencies (libosmocore, libosmo-netif, simtrace2)
4. Build osmo-remsim components

## Build Script Usage

### Basic Commands

```bash
# Show help
./build.sh --help

# Build everything (server, bankd, clients)
./build.sh

# Build only client components (recommended for most users)
./build.sh --client-only

# Clean previous builds before building
./build.sh --clean

# Only download and build dependencies
./build.sh --deps-only

# Build and install to system (requires sudo)
sudo ./build.sh --install
```

### Environment Variables

```bash
# Build with manual PDFs
WITH_MANUALS=1 ./build.sh

# Set custom installation prefix
PREFIX=/opt/osmo-remsim ./build.sh --install

# Set number of parallel build jobs
JOBS=8 ./build.sh
```

### OpenWRT Cross-Compilation

To build for OpenWRT routers:

```bash
# 1. Download and extract OpenWRT SDK
wget https://downloads.openwrt.org/releases/22.03.5/targets/ramips/mt7621/openwrt-sdk-22.03.5-ramips-mt7621_gcc-11.2.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-*.tar.xz

# 2. Set SDK path and build
export OPENWRT_SDK_PATH=$(pwd)/openwrt-sdk-*
./build.sh --openwrt
```

The built binary will be at: `src/client/osmo-remsim-client-openwrt`

## Manual Build Process

If you prefer to build manually without the script:

### 1. Install System Dependencies

#### Debian/Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y \
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
    python3-pip
```

#### Red Hat/CentOS/Fedora

```bash
sudo dnf install -y \
    gcc \
    gcc-c++ \
    make \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    talloc-devel \
    pcsc-lite-devel \
    libusb1-devel \
    libcsv-devel \
    jansson-devel \
    ulfius-devel \
    orcania-devel \
    liburing-devel \
    lksctp-tools-devel \
    libmnl-devel \
    python3 \
    python3-pip
```

### 2. Build Osmocom Dependencies

```bash
# Create dependencies directory
mkdir -p deps
cd deps
export DEPS_INST=$(pwd)/install

# Build libosmocore
git clone https://github.com/osmocom/libosmocore.git
cd libosmocore
autoreconf -fi
./configure --prefix=$DEPS_INST --disable-doxygen
make -j$(nproc)
make install
cd ..

# Build libosmo-netif
git clone https://github.com/osmocom/libosmo-netif.git
cd libosmo-netif
autoreconf -fi
export PKG_CONFIG_PATH=$DEPS_INST/lib/pkgconfig:$PKG_CONFIG_PATH
./configure --prefix=$DEPS_INST --disable-doxygen
make -j$(nproc)
make install
cd ..

# Build simtrace2 (for client-st2 support)
git clone https://github.com/osmocom/simtrace2.git
cd simtrace2/host
autoreconf -fi
./configure --prefix=$DEPS_INST
make -j$(nproc)
make install
cd ../..

cd ..
```

### 3. Build osmo-remsim

```bash
# Set up environment
export PKG_CONFIG_PATH=deps/install/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=deps/install/lib:$LD_LIBRARY_PATH
export PATH=deps/install/bin:$PATH

# Build
autoreconf -fi

# Full build (includes server and bankd)
./configure

# Or client-only build
./configure --disable-remsim-server --disable-remsim-bankd

# Compile
make -j$(nproc)

# Optionally install
sudo make install
```

## Build Output

After a successful build, you'll find:

### Server Components
- `src/server/osmo-remsim-server` - Central server for SIM management
- `src/server/osmo-remsim-apitool` - API tool for server management

### Bankd Components
- `src/bankd/osmo-remsim-bankd` - SIM bank daemon

### Client Components
- `src/client/osmo-remsim-client-st2` - Client for SIMtrace2 hardware
- `src/client/osmo-remsim-client-shell` - Interactive shell client
- `src/client/osmo-remsim-client-openwrt` - OpenWRT router client
- `src/client/libifd_remsim_client.so` - PC/SC driver

### Libraries
- `src/libosmo-rspro.so` - RSPRO protocol library

## Troubleshooting

### Build Fails with "Package not found"

If you see errors like `Package 'libosmocore' not found`, ensure:
1. PKG_CONFIG_PATH includes the deps install directory
2. Dependencies were built successfully

```bash
export PKG_CONFIG_PATH=$(pwd)/deps/install/lib/pkgconfig:$PKG_CONFIG_PATH
```

### Network Issues Downloading Dependencies

If osmocom git servers are unavailable, the build script automatically falls back to GitHub mirrors:
- Primary: `https://git.osmocom.org/`
- Fallback: `https://github.com/osmocom/`

### OpenWRT Cross-Compilation Issues

Common issues:
1. **SDK not found**: Ensure `OPENWRT_SDK_PATH` points to extracted SDK directory
2. **Wrong architecture**: Download SDK matching your target hardware
3. **Missing toolchain**: Ensure SDK includes `toolchain-*` directory in `staging_dir/`

### bankd Build Failure

There's a known issue with duplicate case labels in `src/bankd/bankd_main.c`. If you encounter this:
- Use `--client-only` flag to build just client components
- The client components (including OpenWRT client) build successfully

## Dependencies Reference

### Core Osmocom Libraries (built by script)
- **libosmocore** >= 1.11.0 - Core utilities library
- **libosmo-netif** >= 1.6.0 - Networking library
- **libosmo-simtrace2** >= 0.9.0 - SIMtrace2 support (for client-st2)

### System Libraries (installed by package manager)
- **libtalloc** - Hierarchical memory allocator
- **libpcsclite** - PC/SC smart card library
- **libusb-1.0** - USB device library
- **libcsv** - CSV file handling (for bankd)
- **libjansson** - JSON library (for server)
- **libulfius** - HTTP framework (for server)
- **liborcania** - Utility library (for server)
- **liburing** - Async I/O (for libosmocore)
- **libsctp** - SCTP protocol support
- **libmnl** - Netlink library

## Platform Support

The build script supports:
- **Linux**: Debian, Ubuntu, Fedora, CentOS, RHEL, openSUSE, Arch Linux
- **OpenWRT**: Via cross-compilation with OpenWRT SDK

Tested on:
- Ubuntu 20.04, 22.04, 24.04
- Debian 11, 12
- Fedora 38, 39
- OpenWRT 22.03, 23.05

## Additional Documentation

- [OpenWRT Integration](doc/OPENWRT-INTEGRATION.md) - Complete OpenWRT router setup
- [Fibocom Modem Config](doc/FIBOCOM-MODEM-CONFIG.md) - Fibocom modem configuration
- [Quick Start Guide](doc/QUICKSTART-FIBOCOM.md) - 15-minute setup guide
- [README](README.md) - Project overview

## Contributing

When modifying the build system:
1. Test on multiple distributions if possible
2. Update this documentation
3. Ensure backward compatibility with manual builds
4. Test both full and client-only builds

## License

osmo-remsim is licensed under GPLv2. See [COPYING](COPYING) for details.
