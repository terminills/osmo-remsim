# OpenWRT Build Notes

## Overview

This document describes the OpenWRT cross-compilation support for osmo-remsim, including common issues and their solutions.

## Building for OpenWRT

### Quick Start

```bash
# Set the path to your OpenWRT SDK
export OPENWRT_SDK_PATH=/path/to/openwrt-sdk

# Build for OpenWRT (client only)
./build.sh --openwrt
```

The build script will:
1. Detect and configure the OpenWRT cross-compilation toolchain
2. Build minimal versions of dependencies (libosmocore, libosmo-netif)
3. Build only the osmo-remsim-client-openwrt binary

### What Gets Built

For OpenWRT, we build the absolute minimum needed to run on the router:

**osmo-remsim Components:**
- ✅ `osmo-remsim-client-openwrt` - The client that runs on the router
- ❌ `osmo-remsim-server` - Runs on server, not needed on router
- ❌ `osmo-remsim-bankd` - Runs on server, not needed on router
- ❌ `osmo-remsim-client-st2` - Requires libusb, not available on OpenWRT
- ❌ `osmo-remsim-client-ifdhandler` - Requires PCSC, not available on OpenWRT

**libosmocore Features:**
- ✅ Core libraries (libosmocore, libosmogsm, libosmocodec, etc.)
- ❌ Utilities/tools (osmo-arfcn, osmo-auc-gen, etc.) - Not needed on router
- ❌ SCTP support - Headers not available on OpenWRT
- ❌ libusb support - Not needed on router
- ❌ PCSC support - Not needed on router
- ❌ systemd logging - OpenWRT doesn't use systemd

**libosmo-netif Features:**
- ✅ Core library (libosmonetif)
- ❌ Example programs - Not needed on router, cause linking issues
- ❌ SCTP support - Headers not available on OpenWRT

## Common Issues and Solutions

### Issue: Undefined reference to multiaddr functions

**Symptoms:**
```
ld: ../src/.libs/libosmonetif.so: undefined reference to `osmo_multiaddr_ip_and_port_snprintf'
ld: ../src/.libs/libosmonetif.so: undefined reference to `osmo_sock_multiaddr_get_name_buf'
```

**Root Cause:**
libosmo-netif examples were trying to link during cross-compilation, but couldn't find SCTP-related multiaddr functions from libosmocore (which are stubbed out when SCTP is disabled).

**Solution:**
Added `--disable-examples` option to libosmo-netif and use it during OpenWRT builds. Examples are not needed on the router and avoiding their build prevents linking issues.

**Patches Applied:**
- `patches/libosmocore/0002-fix-multiaddr-functions-without-sctp.patch` - Provides stub implementations of multiaddr functions when SCTP is disabled
- `patches/libosmo-netif/0002-add-disable-examples-configure-option.patch` - Adds configure option to skip building examples

### Issue: Missing SCTP headers

**Symptoms:**
```
fatal error: netinet/sctp.h: No such file or directory
```

**Root Cause:**
OpenWRT's musl libc doesn't include SCTP headers by default.

**Solution:**
All SCTP-related code is made conditional via `--disable-libsctp` configure option and corresponding patches that wrap SCTP includes in `#ifdef HAVE_LIBSCTP`.

**Patches Applied:**
- `patches/libosmocore/0001-make-sctp-include-conditional.patch`
- `patches/libosmo-netif/0001-fix-openwrt-compatibility.patch`

### Issue: Deprecated sys/fcntl.h warnings

**Symptoms:**
```
warning: #warning redirecting incorrect #include <sys/fcntl.h>
```

**Root Cause:**
`<sys/fcntl.h>` is obsolete; POSIX standard requires `<fcntl.h>`.

**Solution:**
Replaced all `<sys/fcntl.h>` includes with `<fcntl.h>` in libosmo-netif source files.

**Patches Applied:**
- `patches/libosmo-netif/0001-fix-openwrt-compatibility.patch`

## Testing

A GitHub Actions workflow (`.github/workflows/openwrt-build.yml`) automatically tests OpenWRT builds using the official OpenWRT SDK for mediatek/filogic target (aarch64).

To test locally:
1. Download an OpenWRT SDK for your target architecture
2. Extract and set `OPENWRT_SDK_PATH`
3. Run `./build.sh --openwrt`

## Deployment

After building, deploy the binary to your OpenWRT router:

```bash
# Copy to router
scp src/client/osmo-remsim-client-openwrt root@router:/usr/bin/

# Copy dependencies (if not already present)
scp deps/install/lib/libosmo*.so* root@router:/usr/lib/
```

## Architecture Support

The OpenWRT build has been tested with:
- **Target:** mediatek/filogic (MT7981B, MT7986A SoCs)
- **Architecture:** aarch64-openwrt-linux-musl
- **Toolchain:** GCC 12.3.0 with musl libc
- **OpenWRT Version:** 23.05.6

Other architectures should work as long as you have the corresponding OpenWRT SDK.

## Performance Considerations

### Build Time
- **Full build:** ~10-15 minutes (first time, downloads all dependencies)
- **Incremental:** ~2-5 minutes (dependencies cached)

### Binary Size
- `osmo-remsim-client-openwrt`: ~100-200 KB (stripped)
- Dependencies: ~2-3 MB total

### Runtime Memory
- Typical usage: 5-10 MB RAM

## Future Improvements

Potential optimizations:
1. Static linking to eliminate dependency deployment
2. Strip debug symbols automatically
3. Size optimization flags (-Os)
4. Link-time optimization (LTO)

## References

- [OpenWRT Build System](https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem)
- [OpenWRT SDK Usage](https://openwrt.org/docs/guide-developer/toolchain/using_the_sdk)
- [osmo-remsim Documentation](../README.md)
- [OpenWRT Integration Guide](./README-OPENWRT.md)
