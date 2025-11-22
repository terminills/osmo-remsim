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

# Skip building dependencies (use system or pre-installed)
# Useful for custom forks with modified dependencies
./build.sh --skip-deps

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

**Default Version**: OpenWrt SNAPSHOT r31338-c18476d0c5 (mediatek/filogic target)  
This matches the current version deployed on production routers (ZBT Z8102AX V2, ARMv8).

The build script supports two methods for OpenWRT SDK management:

#### Method 1: Git Submodule (Recommended for Automated/Nightly Builds)

Use this method when you need version-controlled, reproducible builds:

```bash
# Option A: Add OpenWRT SDK as a git submodule (if you have SDK in a git repo)
# This is ideal if you maintain your own SDK repository or use a team/CI repo
git submodule add https://github.com/your-org/openwrt-sdk.git openwrt-sdk
git submodule update --init --recursive

# Option B: Manually place extracted SDK in openwrt-sdk/ directory
# Download SDK for your target architecture from https://downloads.openwrt.org
# Using OpenWrt SNAPSHOT r31338 for mediatek/filogic (ZBT Z8102AX V2)
wget https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/openwrt-sdk-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-*.tar.xz
mv openwrt-sdk-* openwrt-sdk

# Then optionally add it as a submodule to track the directory
# (Note: The SDK download itself isn't a git repo, but you can make it one)
cd openwrt-sdk && git init && git add . && git commit -m "Initial SDK"
cd .. && git submodule add ./openwrt-sdk openwrt-sdk

# Build - script auto-detects the openwrt-sdk/ directory
./build.sh --openwrt
```

**Benefits of submodule approach:**
- Version-controlled SDK version
- Consistent builds across team/CI
- Automatic SDK checkout with repository
- Ideal for nightly/automated builds

#### Method 2: Environment Variable (Flexible for Local Builds)

Use this method for one-off builds or when switching SDK versions frequently:

```bash
# 1. Download and extract OpenWRT SDK
# Using OpenWrt SNAPSHOT r31338 for mediatek/filogic (ZBT Z8102AX V2)
wget https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/openwrt-sdk-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-*.tar.xz

# 2. Set SDK path and build
export OPENWRT_SDK_PATH=$(pwd)/openwrt-sdk-*
./build.sh --openwrt
```

**Note:** The script checks for `openwrt-sdk/` directory first (submodule), then falls back to `OPENWRT_SDK_PATH`.

The built binary will be at: `src/client/osmo-remsim-client-openwrt`

### Building Custom Forks

If you're working with a custom fork that has modified dependencies or additional components not in the upstream version:

```bash
# Option 1: Skip automatic dependency building and use your own
# This assumes you have the required Osmocom libraries (libosmocore, libosmo-netif, etc.) 
# already installed on your system or built separately
./build.sh --skip-deps --client-only

# Option 2: Set PKG_CONFIG_PATH to point to your custom dependencies
export PKG_CONFIG_PATH=/path/to/your/custom/libs/pkgconfig:$PKG_CONFIG_PATH
./build.sh --skip-deps

# Option 3: Build only the system dependencies, then build manually
./build.sh --deps-only
# ... build your custom dependencies ...
# ... then continue with osmo-remsim build ...
```

**Why use `--skip-deps`?**
- Your fork has custom or modified versions of Osmocom libraries
- You've already built dependencies separately
- You want to use system-installed dependencies
- You have a custom build process for prerequisites

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

**Note**: The build script automatically downloads and cross-compiles talloc as a dependency when building for OpenWRT, so you don't need to have it pre-installed in the SDK.

#### Technical Details: Talloc Cross-Compilation

Talloc uses the Waf build system (not autoconf), which requires special handling for cross-compilation:
- The build script uses `waf configure` directly with `--cross-compile` flag
- A pre-filled cross-answers file (`cache.txt`) is generated with known test results
- Python support is disabled (`--disable-python`) to avoid Python cross-compilation complexity
- This approach is based on the [official OpenWRT libtalloc package](https://github.com/openwrt/packages/blob/master/libs/libtalloc/Makefile)

#### Technical Details: Library Support in OpenWRT

OpenWRT environments have a minimal set of libraries and headers compared to full Linux distributions. The build script automatically handles this:
- When building for OpenWRT (`--openwrt` flag), the script adds several disable flags to libosmocore and libosmo-netif configure options:
  - `--disable-libsctp` - SCTP (Stream Control Transmission Protocol) support
  - `--disable-libmnl` - Netlink library support
  - `--disable-uring` - io_uring async I/O support
  - `--disable-gnutls` - GnuTLS library (used as getrandom() fallback in libosmocore)
  - `--disable-pcsc` - PC/SC smart card reader support (libpcsclite)
- A patch is automatically applied to libosmocore to make the `netinet/sctp.h` include conditional (see `patches/libosmocore/0001-make-sctp-include-conditional.patch`)
- This prevents build failures due to missing header files or libraries in the OpenWRT SDK
- These features are not required for the osmo-remsim client functionality on OpenWRT routers

The patch mechanism in the build script:
- Automatically applies patches from `patches/<dependency-name>/` directories before building each dependency
- Patches are applied in alphanumeric order (e.g., 0001-*.patch, 0002-*.patch)
- If a dependency is already cloned, patches are reapplied on each build by resetting the repository first

#### Technical Details: Build Artifact Cleanup for Cross-Compilation

When switching from a native build to cross-compilation (or vice versa), stale build artifacts can cause "Relocations in generic ELF" errors. The build script automatically handles this:

**Problem**: If you build for native architecture first, then run `./build.sh --openwrt`, the linker may try to link object files from different architectures:
- Example error: `Relocations in generic ELF (EM: 62)` means x86-64 object files (EM: 62) are being linked with aarch64 target
- This happens because old `.o` files from native build are still present when cross-compiling

**Solution**: The build script automatically cleans build artifacts before building each dependency:
- For autoconf-based builds (libosmocore, libosmo-netif, simtrace2): runs `make distclean` or `make clean` if Makefile exists
- For waf-based builds (talloc): runs `waf distclean` and removes build directories (`bin/`, `build/`, `.lock-waf*`, `.waf*`)
- Cleanup happens before `autoreconf`/`configure` to ensure a clean build environment

**Best Practice**: If you encounter architecture mismatch errors, you can manually clean with:
```bash
./build.sh --clean  # Clean osmo-remsim build artifacts
rm -rf deps/        # Clean all dependency build artifacts (most thorough)
```

### bankd Build Failure

There's a known issue with duplicate case labels in `src/bankd/bankd_main.c`. If you encounter this:
- Use `--client-only` flag to build just client components
- The client components (including OpenWRT client) build successfully

## Dependencies Reference

### Core Osmocom Libraries (built by script)
- **libosmocore** >= 1.11.0 - Core utilities library
- **libosmo-netif** >= 1.6.0 - Networking library
- **libosmo-simtrace2** >= 0.9.0 - SIMtrace2 support (for client-st2)
- **talloc** - Hierarchical memory allocator (built from source for OpenWRT cross-compilation)

### System Libraries (installed by package manager)
- **libtalloc** - Hierarchical memory allocator (used for native builds)
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
