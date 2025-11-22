#!/bin/bash
# build.sh - Comprehensive build script for osmo-remsim
#
# This script downloads all prerequisites and builds osmo-remsim including OpenWRT modules.
#
# Usage:
#   ./build.sh                    # Build everything (server, bankd, clients)
#   ./build.sh --help             # Show help
#   ./build.sh --client-only      # Build only client components
#   ./build.sh --openwrt          # Setup for OpenWRT cross-compilation
#   ./build.sh --install          # Install after building
#
# Environment variables:
#   WITH_MANUALS=1               # Build manual PDFs
#   OPENWRT_SDK_PATH=<path>      # Path to OpenWRT SDK for cross-compilation
#   PREFIX=/usr/local            # Installation prefix (default: /usr/local)
#   JOBS=<n>                     # Number of parallel make jobs (default: auto-detect)

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
DEPS_DIR="${BASE_DIR}/deps"
INST_DIR="${DEPS_DIR}/install"
BUILD_TYPE="full"
DO_INSTALL=0
OPENWRT_MODE=0
SKIP_DEPS=0

# Default installation prefix
PREFIX="${PREFIX:-/usr/local}"

# Detect number of CPU cores for parallel builds
if [ -z "$JOBS" ]; then
    if command -v nproc &> /dev/null; then
        JOBS=$(nproc)
    else
        JOBS=1
    fi
fi
export JOBS

PARALLEL_MAKE="-j${JOBS}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_help() {
    cat << EOF
osmo-remsim Build Script

Usage: $0 [OPTIONS]

Options:
  --help              Show this help message
  --client-only       Build only client components (no server/bankd)
  --openwrt           Setup for OpenWRT cross-compilation
  --install           Install binaries after building (requires sudo)
  --clean             Clean build artifacts before building
  --deps-only         Only download and build dependencies
  --skip-deps         Skip building Osmocom dependencies (use system or pre-installed)

Environment Variables:
  WITH_MANUALS=1               Build manual PDFs
  OPENWRT_SDK_PATH=<path>      Path to OpenWRT SDK for cross-compilation
  PREFIX=/path/to/install      Installation prefix (default: /usr/local)
  JOBS=<n>                     Number of parallel make jobs

Examples:
  # Build everything with default settings
  ./build.sh

  # Build only client components
  ./build.sh --client-only

  # Build using system/pre-installed dependencies (for custom forks)
  ./build.sh --skip-deps

  # Build and install to system
  sudo ./build.sh --install

  # Clean build
  ./build.sh --clean

  # Setup for OpenWRT cross-compilation
  export OPENWRT_SDK_PATH=/path/to/openwrt-sdk
  ./build.sh --openwrt

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --client-only)
            BUILD_TYPE="client"
            shift
            ;;
        --openwrt)
            OPENWRT_MODE=1
            BUILD_TYPE="client"
            shift
            ;;
        --install)
            DO_INSTALL=1
            shift
            ;;
        --clean)
            log_info "Cleaning build artifacts..."
            rm -rf "${DEPS_DIR}"
            make clean 2>/dev/null || true
            make distclean 2>/dev/null || true
            log_success "Cleaned"
            shift
            ;;
        --deps-only)
            BUILD_TYPE="deps"
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v opkg &> /dev/null; then
        echo "opkg"
    else
        echo "unknown"
    fi
}

# Install system dependencies
install_system_dependencies() {
    local pkg_mgr=$(detect_package_manager)
    
    log_info "Detected package manager: $pkg_mgr"
    log_info "Installing system dependencies..."
    
    case $pkg_mgr in
        apt)
            log_info "Using apt-get to install dependencies..."
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
                python3-pip \
                wget \
                curl
            ;;
        yum|dnf)
            log_info "Using $pkg_mgr to install dependencies..."
            sudo $pkg_mgr install -y \
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
                python3 \
                python3-pip \
                wget \
                curl
            ;;
        zypper)
            log_info "Using zypper to install dependencies..."
            sudo zypper install -y \
                gcc \
                gcc-c++ \
                make \
                git \
                autoconf \
                automake \
                libtool \
                pkg-config \
                libtalloc-devel \
                pcsc-lite-devel \
                libusb-1_0-devel \
                libcsv-devel \
                libjansson-devel \
                python3 \
                python3-pip \
                wget \
                curl
            ;;
        pacman)
            log_info "Using pacman to install dependencies..."
            sudo pacman -Sy --noconfirm \
                base-devel \
                git \
                autoconf \
                automake \
                libtool \
                pkg-config \
                talloc \
                pcsclite \
                libusb \
                jansson \
                python \
                python-pip \
                wget \
                curl
            ;;
        opkg)
            log_info "Using opkg (OpenWRT) to install dependencies..."
            opkg update
            opkg install \
                gcc \
                make \
                git \
                autoconf \
                automake \
                libtool \
                pkg-config \
                libusb-1.0 \
                python3
            ;;
        unknown)
            log_warn "Could not detect package manager!"
            log_warn "Please install the following dependencies manually:"
            log_warn "  - build-essential/gcc/make"
            log_warn "  - git, autoconf, automake, libtool, pkg-config"
            log_warn "  - libtalloc-dev, libpcsclite-dev, libusb-1.0-dev"
            log_warn "  - libcsv-dev, libjansson-dev, libulfius-dev"
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ "^[Yy]$" ]]; then
                exit 1
            fi
            ;;
    esac
    
    log_success "System dependencies installed"
}

# Build and install a dependency from git
build_dependency() {
    local name=$1
    local repo_url=$2
    local branch=${3:-master}
    local configure_opts=${4:-}
    local fallback_url=${5:-}
    
    log_info "Building dependency: $name"
    
    # Create deps directory if it doesn't exist
    mkdir -p "${DEPS_DIR}"
    cd "${DEPS_DIR}"
    
    # Clone or update repository
    if [ -d "$name" ]; then
        log_info "Updating existing repository: $name"
        cd "$name"
        git fetch origin
        git checkout "$branch"
        git pull
    else
        log_info "Cloning repository: $name"
        if ! git clone "$repo_url" "$name" 2>/dev/null; then
            if [ -n "$fallback_url" ]; then
                log_warn "Primary repository failed, trying fallback..."
                git clone "$fallback_url" "$name"
            else
                log_error "Failed to clone repository: $name"
                exit 1
            fi
        fi
        cd "$name"
        git checkout "$branch"
    fi
    
    # Apply patches if they exist
    local patches_dir="${BASE_DIR}/patches/${name}"
    if [ -d "$patches_dir" ] && [ -n "$(ls -A $patches_dir/*.patch 2>/dev/null)" ]; then
        log_info "Applying patches for $name..."
        # Reset any previous patches first (in case of re-running build)
        git reset --hard HEAD 2>/dev/null || true
        git clean -fd 2>/dev/null || true
        
        # Apply all patches in order
        for patch_file in $patches_dir/*.patch; do
            if [ -f "$patch_file" ]; then
                log_info "  Applying $(basename "$patch_file")"
                if ! patch -p1 < "$patch_file"; then
                    log_error "Failed to apply patch: $(basename "$patch_file")"
                    exit 1
                fi
            fi
        done
        log_success "Patches applied successfully"
    fi
    
    # Clean any previous build artifacts to avoid architecture mismatch
    # This is critical for cross-compilation to prevent mixing host and target object files
    if [ -f "Makefile" ]; then
        log_info "Cleaning previous build artifacts for $name..."
        make distclean 2>/dev/null || make clean 2>/dev/null || true
    fi
    
    # Build and install
    log_info "Building $name..."
    autoreconf -fi
    
    # Setup PKG_CONFIG_PATH and LD_LIBRARY_PATH for dependencies
    export PKG_CONFIG_PATH="${INST_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${INST_DIR}/lib:${LD_LIBRARY_PATH}"
    export PATH="${INST_DIR}/bin:${PATH}"
    
    # In OpenWRT mode, also add our install directory to CFLAGS/LDFLAGS
    # so dependencies can find each other
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        export CFLAGS="-I${INST_DIR}/include ${CFLAGS}"
        export CPPFLAGS="-I${INST_DIR}/include ${CPPFLAGS}"
        # Add both -L (library search path) and -Wl,-rpath-link (transitive dependency path for cross-compilation)
        # The rpath-link is critical for the linker to find indirect dependencies like libosmoisdn during libosmocore build
        export LDFLAGS="-L${INST_DIR}/lib -Wl,-rpath-link=${INST_DIR}/lib ${LDFLAGS}"
        
        # For libosmocore specifically, also add the source tree's .libs directories to rpath-link
        # This is needed because libosmocore's utilities (osmo-arfcn, osmo-auc-gen, etc.) are built
        # during 'make' (before 'make install') and link against libosmogsm.so which depends on libosmoisdn.so.
        # At that point, libosmoisdn.so is only in the build tree (src/isdn/.libs/), not yet in ${INST_DIR}/lib.
        # The linker needs -Wl,-rpath-link to find these transitive dependencies during cross-compilation.
        if [ "$name" = "libosmocore" ]; then
            export LDFLAGS="-Wl,-rpath-link=${DEPS_DIR}/$name/src/isdn/.libs -Wl,-rpath-link=${DEPS_DIR}/$name/src/gsm/.libs ${LDFLAGS}"
        fi
        
        # For libosmo-netif, ensure the linker can find all libosmocore libraries during example builds
        # The examples link against libosmonetif.so (from ../src/.libs/) which depends on libosmocore.so.
        # During cross-compilation, the linker needs explicit rpath-link to follow transitive dependencies.
        # We prepend multiple rpath-link paths to ensure the linker can find:
        # 1. Installed libosmocore libraries (in ${INST_DIR}/lib)
        # 2. libosmocore build tree libraries (in various .libs/ subdirectories)
        # This is necessary because during the build of libosmo-netif examples, libosmocore libraries
        # might be in either location depending on build order and timing.
        if [ "$name" = "libosmo-netif" ]; then
            # Build the rpath-link flags for better readability
            local rpath_flags="-Wl,-rpath-link=${INST_DIR}/lib"
            rpath_flags="$rpath_flags -Wl,-rpath-link=${DEPS_DIR}/libosmocore/src/core/.libs"
            rpath_flags="$rpath_flags -Wl,-rpath-link=${DEPS_DIR}/libosmocore/src/gsm/.libs"
            rpath_flags="$rpath_flags -Wl,-rpath-link=${DEPS_DIR}/libosmocore/src/vty/.libs"
            rpath_flags="$rpath_flags -Wl,-rpath-link=${DEPS_DIR}/libosmocore/src/isdn/.libs"
            export LDFLAGS="$rpath_flags ${LDFLAGS}"
        fi
    fi
    
    # Add --host flag for cross-compilation in OpenWRT mode
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        # Validate CC variable is set and follows expected pattern (*-gcc)
        if [ -z "$CC" ]; then
            log_error "CC environment variable is not set for cross-compilation"
            exit 1
        fi
        if [[ ! "$CC" =~ -gcc$ ]]; then
            log_error "CC variable does not follow expected pattern (*-gcc): $CC"
            exit 1
        fi
        
        # Extract host triplet from CC variable (e.g., aarch64-openwrt-linux-gcc -> aarch64-openwrt-linux)
        # This is safe because we validated CC ends with '-gcc' above
        local host_triplet="${CC%-gcc}"
        log_info "Cross-compiling for: $host_triplet"
        ./configure --host="$host_triplet" --prefix="${INST_DIR}" $configure_opts
    else
        ./configure --prefix="${INST_DIR}" $configure_opts
    fi
    
    make ${PARALLEL_MAKE}
    make install
    
    log_success "Built and installed: $name"
    cd "${BASE_DIR}"
}

# Build talloc from git repository
build_talloc() {
    local version="2.4.2"
    local tag="talloc-${version}"
    local repo_url="https://github.com/samba-team/samba.git"
    local name="samba-talloc"
    
    log_info "Building talloc ${version} for OpenWRT cross-compilation..."
    
    mkdir -p "${DEPS_DIR}"
    cd "${DEPS_DIR}"
    
    # Clone or update full Samba repository at the specific tag
    # We need multiple lib directories for talloc to build (replace, ccan, etc.)
    if [ -d "$name" ]; then
        log_info "Updating existing repository: $name"
        cd "$name"
        git fetch origin "refs/tags/${tag}:refs/tags/${tag}" 2>/dev/null || true
        git checkout "$tag"
    else
        log_info "Cloning Samba repository at tag $tag..."
        # Clone with sparse checkout to minimize download size
        # Suppress detached HEAD advice since we intentionally checkout a tag
        git -c advice.detachedHead=false clone --depth 1 --filter=blob:none --sparse --branch "$tag" "$repo_url" "$name"
        cd "$name"
        # Checkout only the directories needed for talloc build
        git sparse-checkout set lib/talloc lib/replace lib/ccan buildtools third_party/waf
    fi
    
    # Move to talloc subdirectory for build
    cd lib/talloc
    
    # Clean any previous build artifacts to avoid architecture mismatch
    # This is critical for cross-compilation to prevent mixing host and target object files
    log_info "Cleaning previous build artifacts for talloc..."
    if [ -x "../../buildtools/bin/waf" ]; then
        ../../buildtools/bin/waf distclean 2>/dev/null || true
    fi
    # Also remove any leftover files from previous builds
    rm -rf bin build .lock-waf* .waf* cache.txt 2>/dev/null || true
    
    # Build and install
    log_info "Building talloc..."
    
    # Setup PKG_CONFIG_PATH and LD_LIBRARY_PATH for dependencies
    export PKG_CONFIG_PATH="${INST_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${INST_DIR}/lib:${LD_LIBRARY_PATH}"
    export PATH="${INST_DIR}/bin:${PATH}"
    
    # In OpenWRT mode, add our install directory to CFLAGS/LDFLAGS
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        export CFLAGS="-I${INST_DIR}/include ${CFLAGS}"
        export CPPFLAGS="-I${INST_DIR}/include ${CPPFLAGS}"
        # Add both -L (library search path) and -Wl,-rpath-link (transitive dependency path for cross-compilation)
        export LDFLAGS="-L${INST_DIR}/lib -Wl,-rpath-link=${INST_DIR}/lib ${LDFLAGS}"
        
        # Validate CC variable is set
        if [ -z "$CC" ]; then
            log_error "CC environment variable is not set for cross-compilation"
            exit 1
        fi
        if [[ ! "$CC" =~ -gcc$ ]]; then
            log_error "CC variable does not follow expected pattern (*-gcc): $CC"
            exit 1
        fi
        
        # Extract host triplet and architecture from CC variable
        local host_triplet="${CC%-gcc}"
        # Extract architecture - first field of triplet (e.g., aarch64-openwrt-linux -> aarch64)
        # This works for standard GNU triplets (arch-vendor-os or arch-os)
        local arch
        arch=$(echo "$host_triplet" | cut -d'-' -f1)
        log_info "Cross-compiling talloc for: $host_triplet (architecture: $arch)"
        
        # Create cross-answers cache file for waf cross-compilation
        # Based on OpenWRT's libtalloc package: https://github.com/openwrt/packages/blob/master/libs/libtalloc/Makefile
        # These answers are for configure tests that can't be executed during cross-compilation
        # Format: "Test description: result" where result can be:
        #   - OK/YES: test passes
        #   - NO/FAIL: test fails
        #   - (returncode, "output"): specific exit code and output
        #   - "value": string value result
        cat > cache.txt << 'EOF'
Checking simple C program: "hello world"
rpath library support: (127, "")
-Wl,--version-script support: (127, "")
Checking getconf LFS_CFLAGS: NO
Checking for large file support without additional flags: OK
Checking correct behavior of strtoll: OK
Checking for working strptime: NO
Checking for C99 vsnprintf: "1"
Checking for HAVE_SHARED_MMAP: NO
Checking for HAVE_MREMAP: NO
Checking for HAVE_INCOHERENT_MMAP: (2, "")
Checking for HAVE_SECURE_MKSTEMP: OK
EOF
        
        # Add uname information specific to target architecture
        # Note: Kernel version 5.10.0 is used as a generic LTS version
        # The exact version doesn't affect talloc compilation, but waf needs some value
        cat >> cache.txt << EOF
Checking uname machine type: "${arch}"
Checking uname release type: "5.10.0"
Checking uname sysname type: "Linux"
Checking uname version type: "#1 SMP"
EOF
        
        # Use waf directly for cross-compilation (talloc uses waf build system, not autoconf)
        # The waf executable is in the Samba repository at buildtools/bin/waf
        # This path is relative to lib/talloc/ where we are currently located
        local waf_bin="../../buildtools/bin/waf"
        if [ ! -x "$waf_bin" ]; then
            log_error "Waf executable not found at $waf_bin"
            log_error "Expected location for talloc 2.4.2 from Samba repository"
            log_error "Current directory: $(pwd)"
            exit 1
        fi
        
        # Set PYTHONHASHSEED for reproducible builds
        # Waf uses Python and this ensures deterministic ordering of hash-based operations
        export PYTHONHASHSEED=1
        
        log_info "Running waf configure..."
        if ! "$waf_bin" configure \
            --prefix="${INST_DIR}" \
            --cross-compile \
            --cross-answers=cache.txt \
            --disable-python \
            --disable-rpath \
            --disable-rpath-install; then
            log_error "Waf configure failed for talloc cross-compilation"
            log_error "Check cache.txt answers or cross-compilation environment"
            exit 1
        fi
        
        log_info "Running waf build..."
        # Waf uses the JOBS environment variable for parallel builds, not make-style -j flags
        # Set JOBS based on the number of CPUs (already set at script start)
        if ! "$waf_bin" build; then
            log_error "Waf build failed for talloc"
            exit 1
        fi
        
        log_info "Running waf install..."
        if ! "$waf_bin" install; then
            log_error "Waf install failed for talloc"
            exit 1
        fi
        
        # Clean up cross-answers cache file
        rm -f cache.txt
    else
        # Native build - use standard configure wrapper
        ./configure --prefix="${INST_DIR}"
        make ${PARALLEL_MAKE}
        make install
    fi
    
    log_success "Built and installed: talloc ${version}"
    cd "${BASE_DIR}"
}

# Download and build Osmocom dependencies
build_osmocom_dependencies() {
    log_info "Building Osmocom dependencies..."
    
    mkdir -p "${INST_DIR}"
    
    # Build talloc (required by libosmocore) when in OpenWRT mode
    # In non-OpenWRT mode, use system talloc
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        build_talloc
    fi
    
    # Build libosmocore
    local libosmocore_opts="--disable-doxygen"
    # Disable SCTP, libmnl, io_uring, GnuTLS, PCSC, and libusb support for OpenWRT builds (headers/libraries not available)
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        libosmocore_opts="$libosmocore_opts --disable-libsctp --disable-libmnl --disable-uring --disable-gnutls --disable-pcsc --disable-libusb"
    fi
    build_dependency \
        "libosmocore" \
        "https://git.osmocom.org/libosmocore" \
        "master" \
        "$libosmocore_opts" \
        "https://github.com/osmocom/libosmocore.git"
    
    # Build libosmo-netif
    local libosmonetif_opts="--disable-doxygen"
    # Disable SCTP support for OpenWRT builds (netinet/sctp.h not available)
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        libosmonetif_opts="$libosmonetif_opts --disable-libsctp"
    fi
    build_dependency \
        "libosmo-netif" \
        "https://git.osmocom.org/libosmo-netif" \
        "master" \
        "$libosmonetif_opts" \
        "https://github.com/osmocom/libosmo-netif.git"
    
    # Build simtrace2 (for client-st2 support)
    # Note: simtrace2 has the build system in host/ subdirectory
    if [ "$BUILD_TYPE" != "client" ] || [ "$OPENWRT_MODE" -eq 0 ]; then
        log_info "Building dependency: simtrace2"
        mkdir -p "${DEPS_DIR}"
        cd "${DEPS_DIR}"
        
        if [ -d "simtrace2" ]; then
            log_info "Updating existing repository: simtrace2"
            cd "simtrace2"
            git fetch origin
            git checkout master
            git pull
        else
            log_info "Cloning repository: simtrace2"
            if ! git clone "https://git.osmocom.org/simtrace2" "simtrace2" 2>/dev/null; then
                log_warn "Primary repository failed, trying fallback..."
                git clone "https://github.com/osmocom/simtrace2.git" "simtrace2"
            fi
            cd "simtrace2"
        fi
        
        # Build from host/ subdirectory
        cd host
        log_info "Building simtrace2 host component..."
        
        # Clean any previous build artifacts to avoid architecture mismatch
        if [ -f "Makefile" ]; then
            log_info "Cleaning previous build artifacts for simtrace2..."
            make distclean 2>/dev/null || make clean 2>/dev/null || true
        fi
        
        autoreconf -fi
        export PKG_CONFIG_PATH="${INST_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
        export LD_LIBRARY_PATH="${INST_DIR}/lib:${LD_LIBRARY_PATH}"
        export PATH="${INST_DIR}/bin:${PATH}"
        
        # Configure with cross-compilation support if needed
        if [ "$OPENWRT_MODE" -eq 1 ]; then
            # Add CFLAGS/LDFLAGS for OpenWRT cross-compilation
            export CFLAGS="-I${INST_DIR}/include ${CFLAGS}"
            export CPPFLAGS="-I${INST_DIR}/include ${CPPFLAGS}"
            # Add both -L (library search path) and -Wl,-rpath-link (transitive dependency path for cross-compilation)
            export LDFLAGS="-L${INST_DIR}/lib -Wl,-rpath-link=${INST_DIR}/lib ${LDFLAGS}"
            local host_triplet="${CC%-gcc}"
            ./configure --host="$host_triplet" --prefix="${INST_DIR}"
        else
            ./configure --prefix="${INST_DIR}"
        fi
        
        make ${PARALLEL_MAKE}
        make install
        log_success "Built and installed: simtrace2"
        cd "${BASE_DIR}"
    fi
    
    log_success "Osmocom dependencies built successfully"
}

# Setup OpenWRT cross-compilation environment
setup_openwrt_environment() {
    # Check for OpenWRT SDK in submodule first, then fall back to environment variable
    local sdk_path=""
    
    # Option 1: Check for git submodule (for nightly builds and version control)
    if [ -d "${BASE_DIR}/openwrt-sdk" ] && [ -d "${BASE_DIR}/openwrt-sdk/staging_dir" ]; then
        sdk_path="${BASE_DIR}/openwrt-sdk"
        log_info "Using OpenWRT SDK from git submodule: $sdk_path"
    # Option 2: Use environment variable
    elif [ -n "$OPENWRT_SDK_PATH" ]; then
        sdk_path="$OPENWRT_SDK_PATH"
        log_info "Using OpenWRT SDK from OPENWRT_SDK_PATH: $sdk_path"
    else
        log_error "OpenWRT SDK not found!"
        log_info ""
        log_info "Option 1 - Use git submodule (recommended for automated builds):"
        log_info "  git submodule add <sdk-repo-url> openwrt-sdk"
        log_info "  git submodule update --init --recursive"
        log_info ""
        log_info "Option 2 - Download and set environment variable:"
        log_info "  # Using OpenWrt SNAPSHOT r31338 for mediatek/filogic (ZBT Z8102AX V2)"
        log_info "  wget https://downloads.openwrt.org/snapshots/targets/mediatek/filogic/openwrt-sdk-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.xz"
        log_info "  tar xf openwrt-sdk-*.tar.xz"
        log_info "  export OPENWRT_SDK_PATH=\$(pwd)/openwrt-sdk-*"
        exit 1
    fi
    
    if [ ! -d "$sdk_path" ]; then
        log_error "OpenWRT SDK path does not exist: $sdk_path"
        exit 1
    fi
    
    log_info "Setting up OpenWRT cross-compilation environment..."
    log_info "SDK Path: $sdk_path"
    
    # Find toolchain directory
    local toolchain_dir=$(find "$sdk_path/staging_dir" -maxdepth 1 -name "toolchain-*" -type d | head -n 1)
    local target_dir=$(find "$sdk_path/staging_dir" -maxdepth 1 -name "target-*" -type d | head -n 1)
    
    if [ -z "$toolchain_dir" ] || [ -z "$target_dir" ]; then
        log_error "Could not find toolchain or target directory in OpenWRT SDK"
        exit 1
    fi
    
    log_info "Toolchain: $toolchain_dir"
    log_info "Target: $target_dir"
    
    # Extract target architecture
    local arch=$(basename "$target_dir" | sed 's/target-//' | cut -d'_' -f1)
    
    # Setup environment variables for cross-compilation
    export PATH="${toolchain_dir}/bin:${PATH}"
    export STAGING_DIR="${sdk_path}/staging_dir"
    export PKG_CONFIG_PATH="${toolchain_dir}/usr/lib/pkgconfig:${target_dir}/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CC="${arch}-openwrt-linux-gcc"
    export CXX="${arch}-openwrt-linux-g++"
    export AR="${arch}-openwrt-linux-ar"
    export RANLIB="${arch}-openwrt-linux-ranlib"
    
    # Set CFLAGS and LDFLAGS to use OpenWRT SDK sysroot
    # Include both toolchain (build dependencies) and target (runtime) paths
    export CFLAGS="-I${toolchain_dir}/usr/include -I${target_dir}/usr/include ${CFLAGS:-}"
    export CPPFLAGS="-I${toolchain_dir}/usr/include -I${target_dir}/usr/include ${CPPFLAGS:-}"
    # Add -Wl,-rpath-link for both directories to help linker find transitive dependencies during cross-compilation
    export LDFLAGS="-L${toolchain_dir}/usr/lib -L${target_dir}/usr/lib -Wl,-rpath-link=${toolchain_dir}/usr/lib -Wl,-rpath-link=${target_dir}/usr/lib ${LDFLAGS:-}"
    
    log_success "OpenWRT environment configured for: $arch"
}

# Build osmo-remsim
build_osmo_remsim() {
    log_info "Building osmo-remsim..."
    
    cd "${BASE_DIR}"
    
    # Setup PKG_CONFIG_PATH and LD_LIBRARY_PATH
    # Only add deps/install paths if we built dependencies
    if [ "$SKIP_DEPS" -eq 0 ] && [ -d "${INST_DIR}" ]; then
        export PKG_CONFIG_PATH="${INST_DIR}/lib/pkgconfig:${PKG_CONFIG_PATH}"
        export LD_LIBRARY_PATH="${INST_DIR}/lib:${LD_LIBRARY_PATH}"
        export PATH="${INST_DIR}/bin:${PATH}"
        log_info "Using dependencies from: ${INST_DIR}"
    else
        log_info "Using system or pre-installed dependencies"
    fi
    
    # Run autoreconf if needed
    if [ ! -f configure ]; then
        log_info "Running autoreconf..."
        autoreconf -fi
    fi
    
    # Configure options
    local configure_opts=""
    
    if [ "$BUILD_TYPE" = "client" ]; then
        configure_opts="--disable-remsim-server --disable-remsim-bankd"
        log_info "Building client-only configuration"
    fi
    
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        # For OpenWRT, disable components that aren't needed
        configure_opts="--disable-remsim-server --disable-remsim-bankd --disable-remsim-client-st2 --disable-remsim-client-ifdhandler"
        log_info "Building for OpenWRT (client-openwrt only)"
    fi
    
    if [ "$WITH_MANUALS" = "1" ]; then
        configure_opts="$configure_opts --enable-manuals"
    fi
    
    # Configure
    log_info "Configuring osmo-remsim with options: $configure_opts"
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        # Cross-compilation for OpenWRT
        ./configure --host="${CC%-gcc}" $configure_opts
    else
        ./configure $configure_opts
    fi
    
    # Build
    log_info "Compiling osmo-remsim..."
    make ${PARALLEL_MAKE}
    
    log_success "osmo-remsim built successfully!"
}

# Install osmo-remsim
install_osmo_remsim() {
    log_info "Installing osmo-remsim to $PREFIX..."
    
    cd "${BASE_DIR}"
    
    if [ "$PREFIX" = "/usr/local" ] || [ "$PREFIX" = "/usr" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            log_error "Installation to $PREFIX requires root privileges"
            log_info "Please run with sudo: sudo ./build.sh --install"
            exit 1
        fi
    fi
    
    make install
    
    # Run ldconfig if installing to system directories
    if [ "$PREFIX" = "/usr/local" ] || [ "$PREFIX" = "/usr" ]; then
        log_info "Running ldconfig..."
        ldconfig
    fi
    
    log_success "osmo-remsim installed to $PREFIX"
}

# Show build summary
show_summary() {
    log_info "=========================================="
    log_info "Build Summary"
    log_info "=========================================="
    log_info "Build Type: $BUILD_TYPE"
    log_info "OpenWRT Mode: $OPENWRT_MODE"
    log_info "Dependencies: ${DEPS_DIR}"
    log_info "Install Prefix: ${INST_DIR}"
    log_info "Parallel Jobs: $JOBS"
    log_info "=========================================="
    
    if [ "$OPENWRT_MODE" -eq 0 ]; then
        log_info "Built binaries are located in:"
        log_info "  - src/server/osmo-remsim-server"
        log_info "  - src/bankd/osmo-remsim-bankd"
        log_info "  - src/client/osmo-remsim-client-*"
    else
        log_info "Built OpenWRT binary:"
        log_info "  - src/client/osmo-remsim-client-openwrt"
    fi
    
    if [ "$DO_INSTALL" -eq 0 ]; then
        log_info ""
        log_info "To install, run: ./build.sh --install"
    fi
    
    log_info "=========================================="
}

# Main execution
main() {
    log_info "osmo-remsim Build Script"
    log_info "========================"
    log_info ""
    
    # Check for OpenWRT mode
    if [ "$OPENWRT_MODE" -eq 1 ]; then
        setup_openwrt_environment
    else
        # Install system dependencies only in normal mode
        install_system_dependencies
    fi
    
    # Build dependencies (unless skipped)
    if [ "$SKIP_DEPS" -eq 0 ]; then
        build_osmocom_dependencies
    else
        log_info "Skipping Osmocom dependency build (--skip-deps specified)"
        log_info "Using system or pre-installed dependencies"
    fi
    
    # Build osmo-remsim (unless deps-only mode)
    if [ "$BUILD_TYPE" != "deps" ]; then
        build_osmo_remsim
    fi
    
    # Install if requested
    if [ "$DO_INSTALL" -eq 1 ] && [ "$BUILD_TYPE" != "deps" ]; then
        install_osmo_remsim
    fi
    
    # Show summary
    if [ "$BUILD_TYPE" != "deps" ]; then
        show_summary
    fi
    
    log_success "Build completed successfully!"
}

# Run main
main
