# Dependency Patches

This directory contains patches that are automatically applied to external dependencies during the build process.

## Structure

```
patches/
├── libosmocore/
│   └── 0001-make-sctp-include-conditional.patch
├── libosmo-netif/
│   └── 0001-fix-openwrt-compatibility.patch
└── <dependency-name>/
    └── <patch-files>.patch
```

## How It Works

The `build.sh` script's `build_dependency()` function automatically:
1. Clones or updates the dependency repository
2. Looks for patches in `patches/<dependency-name>/`
3. Applies all `.patch` files in alphanumeric order
4. Builds and installs the patched dependency

## Patch Naming Convention

Patches should be named with a numeric prefix for ordering:
- `0001-description.patch` - First patch
- `0002-description.patch` - Second patch
- etc.

## Creating Patches

Patches should be in unified diff format (`diff -u` or `git diff`):

```bash
# Example: Create a patch from git diff
cd deps/libosmocore
git diff > /path/to/osmo-remsim/patches/libosmocore/0001-my-patch.patch
```

## Existing Patches

### libosmocore

#### 0001-make-sctp-include-conditional.patch
- **Purpose**: Fix OpenWRT build failure due to missing `netinet/sctp.h`
- **Details**: Makes the SCTP header include conditional on `HAVE_LIBSCTP` being defined
- **Affects**: `src/core/osmo_io_internal.h` and `src/core/osmo_io_uring.c`
- **When applied**: Always (harmless on systems with SCTP support)

#### 0002-fix-multiaddr-functions-without-sctp.patch
- **Purpose**: Fix undefined reference errors when linking against libosmocore built with `--disable-libsctp`
- **Details**: The functions `osmo_sock_multiaddr_get_name_buf()` and `osmo_multiaddr_ip_and_port_snprintf()` 
  were only compiled when SCTP support was enabled (guarded by `#ifdef HAVE_LIBSCTP`), but libosmo-netif 
  depends on them unconditionally. This caused linker errors during OpenWRT cross-compilation. The patch 
  removes both `#ifdef HAVE_LIBSCTP` blocks that guard these functions and `osmo_sock_multiaddr_get_ip_and_port()`, 
  making them always available. SCTP-specific implementation details remain conditional with appropriate fallbacks 
  for non-SCTP builds (using regular single-address functions).
- **Affects**: `src/core/socket.c`
- **When applied**: Always (maintains API compatibility while fixing linker errors)

### libosmo-netif

#### 0001-fix-openwrt-compatibility.patch
- **Purpose**: Fix OpenWRT build issues - deprecated header warnings and missing SCTP support
- **Details**: 
  1. Replaces deprecated `<sys/fcntl.h>` with POSIX-standard `<fcntl.h>` in source files
  2. Makes SCTP header includes and function declarations conditional on `HAVE_LIBSCTP`
  3. Guards SCTP-specific function calls in stream_cli.c and stream_srv.c
  4. Protects SCTP-only connection setup code with compile-time checks
- **Affects**: 
  - Headers: `include/osmocom/netif/sctp.h`, `include/osmocom/netif/stream_private.h`
  - Sources: `src/datagram.c`, `src/stream_cli.c`, `src/stream.c`, `src/stream_srv.c`
- **When applied**: Always (eliminates warnings and build failures on OpenWRT with --disable-libsctp)

#### 0002-add-disable-examples-configure-option.patch
- **Purpose**: Add configure option to skip building example programs
- **Details**: 
  Adds `--disable-examples` configure option to optionally skip building the examples directory.
  This solves linking issues during cross-compilation where examples may fail to link even though
  the main library builds successfully. Examples are built by default for backward compatibility.
- **Affects**: `Makefile.am`, `configure.ac`
- **When applied**: Always (no effect unless --disable-examples is used)
- **Used by**: OpenWRT builds (via `build.sh --openwrt`)

## Notes

- Patches are reapplied on every build (repository is reset first)
- Failed patch application will stop the build process
- Patches are only applied during dependency builds, not for osmo-remsim itself
