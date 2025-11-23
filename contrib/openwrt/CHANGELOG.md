# OpenWrt Package Build System - Changelog

## [Unreleased] - 2024-11-23

### Added
- **Dependency Package Definitions**: Added OpenWrt package definitions for required Osmocom dependencies:
  - `libtalloc` (v2.4.2) - Hierarchical memory allocator from Samba project
  - `libosmocore` (v1.11.0) - Core Osmocom utilities library
  - `libosmo-gsm` (v1.11.0) - GSM-specific utilities (sub-package of libosmocore)
  - `libosmo-netif` (v1.6.0) - Network interface utilities library

- **Automated Dependency Building**: Enhanced `build-ipk.sh` script to:
  - Automatically copy all dependency packages to OpenWrt SDK
  - Build dependencies in correct order before main packages
  - Display all built IPK files including dependencies
  - Provide installation instructions with proper dependency order

### Changed
- **Build Process**: Modified build workflow to ensure dependencies are built before osmo-remsim-client
- **Documentation**: Updated all documentation files to reflect new dependency handling:
  - `README.md` - Added dependency package information and updated build instructions
  - `INSTALL.md` - Updated with proper dependency installation order
  - `PACKAGE_SUMMARY.md` - Expanded with complete package listings

### Fixed
- **Issue #XX**: Resolved "dependency does not exist" warnings during IPK package compilation
  - The build system no longer requires external Osmocom feeds
  - All required dependencies are now built from included package definitions
  - Eliminates `WARNING: Makefile 'package/osmo-remsim-client/Makefile' has a dependency on 'libosmocore', which does not exist` errors

### Technical Details

#### Dependency Build Order
The build system now ensures packages are built in the correct dependency order:
```
libtalloc → libosmocore + libosmo-gsm → libosmo-netif → osmo-remsim-client
```

#### Package Features
- **libtalloc Package**:
  - Uses Waf build system with cross-compilation support
  - Pre-filled cross-answers cache for OpenWrt targets
  - Python disabled for minimal dependencies

- **libosmocore Package**:
  - Disabled features not needed for OpenWrt: SCTP, libmnl, liburing, GnuTLS, PCSC, libusb
  - Split into main package (libosmocore) and sub-package (libosmo-gsm)
  - Provides multiple libraries: core, vty, ctrl, coding, sim, usb, isdn, gb

- **libosmo-netif Package**:
  - Disabled SCTP for OpenWrt compatibility
  - Provides IPA, LAPD, and stream support

#### OpenWrt SDK Compatibility
Tested with:
- OpenWrt 23.05.6 (MediaTek Filogic / aarch64)
- gcc-12.3.0 with musl libc

### Migration Guide

For users who were previously attempting to build with external feeds:

**Before** (required manual feed setup):
```bash
echo "src-git osmocom https://gitea.osmocom.org/openwrt/meta-osmocom.git" >> feeds.conf.default
./scripts/feeds update osmocom
./scripts/feeds install -p osmocom libosmocore libosmo-netif
make package/osmo-remsim-client/compile
```

**After** (fully automated):
```bash
export OPENWRT_SDK_PATH=/path/to/openwrt-sdk
cd /path/to/osmo-remsim
./contrib/openwrt/build-ipk.sh
```

### Installation Instructions

When installing on a router, packages must be installed in dependency order:

```bash
# Transfer all packages
scp libtalloc_*.ipk libosmocore_*.ipk libosmo-gsm_*.ipk \
    libosmo-netif_*.ipk osmo-remsim-client_*.ipk root@router:/tmp/

# Install in order
ssh root@router
opkg install /tmp/libtalloc_*.ipk
opkg install /tmp/libosmocore_*.ipk /tmp/libosmo-gsm_*.ipk
opkg install /tmp/libosmo-netif_*.ipk
opkg install /tmp/osmo-remsim-client_*.ipk
```

### Files Changed
- `contrib/openwrt/libtalloc/Makefile` (new)
- `contrib/openwrt/libosmocore/Makefile` (new)
- `contrib/openwrt/libosmo-netif/Makefile` (new)
- `contrib/openwrt/build-ipk.sh` (modified)
- `contrib/openwrt/README.md` (modified)
- `contrib/openwrt/INSTALL.md` (modified)
- `contrib/openwrt/PACKAGE_SUMMARY.md` (modified)
- `contrib/openwrt/CHANGELOG.md` (new)

### Known Issues
None at this time.

### Future Enhancements
- Consider adding pre-built IPK repository for common architectures
- Add support for additional OpenWrt versions (22.03, SNAPSHOT)
- Explore integration with official OpenWrt package feeds

---

## Package Versions

| Package | Version | Source |
|---------|---------|--------|
| libtalloc | 2.4.2 | https://www.samba.org/ftp/talloc |
| libosmocore | 1.11.0 | https://github.com/osmocom/libosmocore |
| libosmo-gsm | 1.11.0 | https://github.com/osmocom/libosmocore |
| libosmo-netif | 1.6.0 | https://github.com/osmocom/libosmo-netif |
| osmo-remsim-client | 0.4.1 | (this repository) |

---

**Maintainer**: Osmocom <openbsc@lists.osmocom.org>  
**License**: GPL-2.0 / LGPL-3.0  
**Last Updated**: 2024-11-23
