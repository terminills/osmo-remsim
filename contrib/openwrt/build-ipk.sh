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
  OPENWRT_SDK_PATH    Path to OpenWrt SDK (required if --sdk not specified)
  BUILD_JOBS          Number of parallel jobs (default: auto-detect)

Examples:
  # Build all packages
  ./build-ipk.sh --sdk /path/to/openwrt-sdk

  # Build only client package with verbose output
  ./build-ipk.sh --sdk /path/to/openwrt-sdk --client-only --verbose

  # Using environment variable
  export OPENWRT_SDK_PATH=/path/to/openwrt-sdk
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
if [ -z "$OPENWRT_SDK_PATH" ]; then
    log_error "OpenWrt SDK path not specified"
    echo "Set OPENWRT_SDK_PATH environment variable or use --sdk option"
    exit 1
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

# Change to SDK directory
cd "$OPENWRT_SDK_PATH"

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
log_info "  1. Transfer IPK files: scp bin/packages/*/osmo-remsim*.ipk root@router:/tmp/"
log_info "  2. SSH to router: ssh root@router"
log_info "  3. Install: opkg install /tmp/osmo-remsim-client*.ipk /tmp/luci-app-remsim*.ipk"
