#!/bin/bash
#
# build-ipk.sh - Build OpenWrt IPK packages for osmo-remsim
#
# This script automates the process of building IPK packages using the OpenWrt SDK
#
# Usage:
#   ./build-ipk.sh [OPTIONS]
#
# Environment variables:
#   OPENWRT_SDK_PATH    Path to OpenWrt SDK (required)
#   BUILD_JOBS          Number of parallel jobs (default: auto-detect)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
BUILD_CLIENT=1
BUILD_LUCI=1
CLEAN_BUILD=0
VERBOSE=0

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
Build OpenWrt IPK packages for osmo-remsim

Usage: $0 [OPTIONS]

Options:
  --help              Show this help message
  --sdk PATH          Path to OpenWrt SDK (or set OPENWRT_SDK_PATH)
  --client-only       Build only osmo-remsim-client package
  --luci-only         Build only luci-app-remsim package
  --clean             Clean before building
  --verbose           Enable verbose output
  --jobs N            Number of parallel build jobs

Environment Variables:
  OPENWRT_SDK_PATH    Path to OpenWrt SDK (optional if using git submodule or --sdk)
  BUILD_JOBS          Number of parallel jobs (default: auto-detect)

SDK Path Resolution (priority order):
  1. Command line: --sdk PATH (overrides all other methods)
  2. Environment: OPENWRT_SDK_PATH (if set, skips git submodule check)
  3. Auto-detect: git submodule at ./openwrt-sdk/ (checked if above are not set)

Examples:
  # Build all packages (auto-detect SDK from git submodule or environment)
  ./build-ipk.sh

  # Build all packages with explicit SDK path
  ./build-ipk.sh --sdk /path/to/openwrt-sdk

  # Build only client package with verbose output
  ./build-ipk.sh --sdk /path/to/openwrt-sdk --client-only --verbose

  # Using environment variable
  export OPENWRT_SDK_PATH=/path/to/openwrt-sdk
  ./build-ipk.sh

  # Using git submodule (recommended for automated builds)
  git submodule add <sdk-repo-url> openwrt-sdk
  git submodule update --init --recursive
  ./build-ipk.sh

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --sdk)
            OPENWRT_SDK_PATH="$2"
            shift 2
            ;;
        --client-only)
            BUILD_CLIENT=1
            BUILD_LUCI=0
            shift
            ;;
        --luci-only)
            BUILD_CLIENT=0
            BUILD_LUCI=1
            shift
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --jobs|-j)
            BUILD_JOBS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate SDK path
# Priority: 1) --sdk command line option (already sets OPENWRT_SDK_PATH during arg parsing)
#           2) OPENWRT_SDK_PATH environment variable (if set, used directly)
#           3) Git submodule at ./openwrt-sdk (checked only if OPENWRT_SDK_PATH not set)
#
# Note: This differs from build.sh which has no command line option and checks
# git submodule first, then environment variable. Here, explicit user input
# (--sdk or env var) takes precedence over auto-detection (git submodule).
if [ -z "$OPENWRT_SDK_PATH" ]; then
    # Fallback: Check for git submodule (for automated builds and version control)
    # Note: We don't require staging_dir to exist yet - it will be created during initialization
    if [ -d "${REPO_ROOT}/openwrt-sdk" ]; then
        OPENWRT_SDK_PATH="${REPO_ROOT}/openwrt-sdk"
        log_info "Using OpenWrt SDK from git submodule: $OPENWRT_SDK_PATH"
    else
        log_error "OpenWrt SDK not found!"
        log_info ""
        log_info "Please provide the OpenWrt SDK path using one of these methods:"
        log_info ""
        log_info "1. Git submodule (recommended for automated/reproducible builds):"
        log_info "   git submodule add <sdk-repo-url> openwrt-sdk"
        log_info "   git submodule update --init --recursive"
        log_info ""
        log_info "2. Environment variable:"
        log_info "   # Download OpenWrt SDK for your target architecture"
        log_info "   wget https://downloads.openwrt.org/snapshots/targets/<target>/<subtarget>/openwrt-sdk-*.tar.xz"
        log_info "   tar xf openwrt-sdk-*.tar.xz"
        log_info "   export OPENWRT_SDK_PATH=\$(pwd)/openwrt-sdk-*"
        log_info ""
        log_info "3. Command line option (overrides above methods):"
        log_info "   ./build-ipk.sh --sdk /path/to/openwrt-sdk"
        exit 1
    fi
fi

if [ ! -d "$OPENWRT_SDK_PATH" ]; then
    log_error "OpenWrt SDK not found at: $OPENWRT_SDK_PATH"
    exit 1
fi

# Detect number of CPU cores if not set
if [ -z "$BUILD_JOBS" ]; then
    if command -v nproc &> /dev/null; then
        BUILD_JOBS=$(nproc)
    else
        BUILD_JOBS=1
    fi
fi

log_info "OpenWrt SDK: $OPENWRT_SDK_PATH"
log_info "Repository: $REPO_ROOT"
log_info "Build jobs: $BUILD_JOBS"

# Change to SDK directory and set TOPDIR for OpenWrt build system
cd "$OPENWRT_SDK_PATH"

# Unset PROMPT_DIRTRIM to prevent bash from abbreviating paths with "..."
# This is critical because OpenWrt's Makefile system uses shell commands
# that can be affected by this environment variable, causing paths like
# /home/user/.../openwrt-sdk/staging_dir which fail when used literally
unset PROMPT_DIRTRIM

# Export TOPDIR as absolute path for OpenWrt's build system
# This prevents path abbreviation issues (e.g., "..." in paths) that occur
# when TOPDIR is computed from relative paths or contains symlinks
export TOPDIR="$(pwd)"

# Initialize SDK if not already initialized
# The SDK needs staging_dir/host to exist before building packages
if [ ! -d "staging_dir/host" ]; then
    log_info "Initializing OpenWrt SDK..."
    
    # Create staging_dir/host directory structure
    # This is required before running make commands on the SDK
    # The -p flag creates parent directories as needed and doesn't error if they exist
    mkdir -p staging_dir/host
    
    # Run defconfig to initialize the SDK and create necessary files
    if ! make defconfig > /dev/null 2>&1; then
        log_error "Failed to initialize OpenWrt SDK"
        log_info "This usually means the SDK is incomplete or corrupted"
        log_info "Please verify the SDK was properly extracted and is compatible"
        exit 1
    fi
    log_success "OpenWrt SDK initialized"
fi

# Copy package definitions to SDK
log_info "Copying package definitions to SDK..."

if [ $BUILD_CLIENT -eq 1 ]; then
    log_info "Setting up osmo-remsim-client package..."
    rm -rf package/osmo-remsim-client
    cp -r "$SCRIPT_DIR/osmo-remsim-client" package/
    log_success "osmo-remsim-client package copied"
fi

if [ $BUILD_LUCI -eq 1 ]; then
    log_info "Setting up luci-app-remsim package..."
    rm -rf package/luci-app-remsim
    cp -r "$SCRIPT_DIR/luci-app-remsim" package/
    log_success "luci-app-remsim package copied"
fi

# Update feeds
log_info "Updating feeds..."
./scripts/feeds update -a > /dev/null 2>&1 || true

# Install required feeds
log_info "Installing required feeds..."
./scripts/feeds install -a > /dev/null 2>&1 || true

# Clean if requested
if [ $CLEAN_BUILD -eq 1 ]; then
    log_info "Cleaning previous builds..."
    if [ $BUILD_CLIENT -eq 1 ]; then
        make package/osmo-remsim-client/clean > /dev/null 2>&1 || true
    fi
    if [ $BUILD_LUCI -eq 1 ]; then
        make package/luci-app-remsim/clean > /dev/null 2>&1 || true
    fi
    log_success "Clean complete"
fi

# Build packages
MAKE_OPTS="-j${BUILD_JOBS}"
if [ $VERBOSE -eq 1 ]; then
    MAKE_OPTS="$MAKE_OPTS V=s"
fi

if [ $BUILD_CLIENT -eq 1 ]; then
    log_info "Building osmo-remsim-client package..."
    if make package/osmo-remsim-client/compile $MAKE_OPTS; then
        log_success "osmo-remsim-client package built successfully"
    else
        log_error "Failed to build osmo-remsim-client package"
        exit 1
    fi
fi

if [ $BUILD_LUCI -eq 1 ]; then
    log_info "Building luci-app-remsim package..."
    if make package/luci-app-remsim/compile $MAKE_OPTS; then
        log_success "luci-app-remsim package built successfully"
    else
        log_error "Failed to build luci-app-remsim package"
        exit 1
    fi
fi

# Find and display built packages
log_info "Locating built IPK packages..."
echo ""

CLIENT_IPKS=$(find bin/ -name "osmo-remsim-client*.ipk" 2>/dev/null || true)
LUCI_IPKS=$(find bin/ -name "luci-app-remsim*.ipk" 2>/dev/null || true)
ALL_IPKS=$(find bin/ \( -name "osmo-remsim-client*.ipk" -o -name "luci-app-remsim*.ipk" \) 2>/dev/null || true)

if [ -n "$CLIENT_IPKS" ]; then
    log_success "Client package(s) built:"
    for ipk in $CLIENT_IPKS; do
        echo "  - $ipk ($(du -h "$ipk" | cut -f1))"
    done
fi

if [ -n "$LUCI_IPKS" ]; then
    log_success "LuCI package(s) built:"
    for ipk in $LUCI_IPKS; do
        echo "  - $ipk ($(du -h "$ipk" | cut -f1))"
    done
fi

echo ""
log_success "Build complete!"
log_info "To install on your router:"
if [ -n "$CLIENT_IPKS" ] && [ -n "$LUCI_IPKS" ]; then
    log_info "  1. Transfer IPK files: scp $CLIENT_IPKS $LUCI_IPKS root@router:/tmp/"
elif [ -n "$CLIENT_IPKS" ]; then
    log_info "  1. Transfer IPK files: scp $CLIENT_IPKS root@router:/tmp/"
elif [ -n "$LUCI_IPKS" ]; then
    log_info "  1. Transfer IPK files: scp $LUCI_IPKS root@router:/tmp/"
fi
log_info "  2. SSH to router: ssh root@router"
log_info "  3. Install: opkg install /tmp/*.ipk"
