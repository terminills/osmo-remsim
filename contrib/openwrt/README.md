# OpenWrt IPK Package Generation for osmo-remsim

This directory contains OpenWrt package definitions for building IPK packages for osmo-remsim.

## Packages

### 1. osmo-remsim-client
Contains the binary executables and libraries:
- `osmo-remsim-client-openwrt` - Main OpenWrt client binary
- `osmo-remsim-client-shell` - Interactive shell client
- `libosmo-rspro.so` - Shared library
- Init script and configuration files
- Event script for hardware control

**Location:** `contrib/openwrt/osmo-remsim-client/`

### 2. luci-app-remsim
LuCI web interface for configuration and monitoring:
- Web-based configuration pages
- Real-time status monitoring
- Modem management interface
- IonMesh integration controls

**Location:** `contrib/openwrt/luci-app-remsim/`

### 3. Dependency Packages
To enable building osmo-remsim in OpenWrt, package definitions for required dependencies are included:

- **libtalloc** - Hierarchical memory allocator (required by libosmocore)
  - **Location:** `contrib/openwrt/libtalloc/`
  
- **libosmocore** - Osmocom core utilities library
  - **Location:** `contrib/openwrt/libosmocore/`
  - Includes libosmo-gsm sub-package
  
- **libosmo-netif** - Osmocom network interface library  
  - **Location:** `contrib/openwrt/libosmo-netif/`

These dependency packages are automatically built by the `build-ipk.sh` script before building osmo-remsim-client.

## Prerequisites

### OpenWrt SDK
Download the OpenWrt SDK for your target platform:

```bash
# For MediaTek MT7986 (Filogic) - aarch64
wget https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
cd openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64
```

### Dependency Handling
The required Osmocom libraries are **automatically built** as part of the IPK build process:
- libtalloc 2.4.2
- libosmocore 1.11.0 (includes libosmo-gsm)
- libosmo-netif 1.6.0

These are built from source during the package compilation and do not need to be pre-installed in the SDK.

## Building IPK Packages

### Method 1: Using build-ipk.sh Script (Recommended)

The easiest way to build all packages is using the provided `build-ipk.sh` script, which automatically handles dependencies:

```bash
# Set SDK path
export OPENWRT_SDK_PATH=/path/to/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64

# Build all packages (dependencies + client + LuCI)
cd /path/to/osmo-remsim
./contrib/openwrt/build-ipk.sh

# Or build only client package (still builds dependencies)
./contrib/openwrt/build-ipk.sh --client-only

# Or build with verbose output
./contrib/openwrt/build-ipk.sh --verbose
```

The script will:
1. Initialize the OpenWrt SDK
2. Copy all package definitions (dependencies + main packages)
3. Build dependencies in order: libtalloc → libosmocore → libosmo-netif
4. Build osmo-remsim-client and/or luci-app-remsim
5. Display the location of all built IPK files

### Method 2: Manual Build with OpenWrt SDK

If you prefer manual control:

1. **Setup the SDK:**
   ```bash
   export OPENWRT_SDK_PATH=/path/to/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64
   cd $OPENWRT_SDK_PATH
   ```

2. **Copy package definitions to SDK:**
   ```bash
   # Copy dependency packages
   cp -r /path/to/osmo-remsim/contrib/openwrt/libtalloc package/
   cp -r /path/to/osmo-remsim/contrib/openwrt/libosmocore package/
   cp -r /path/to/osmo-remsim/contrib/openwrt/libosmo-netif package/
   
   # Copy main packages
   cp -r /path/to/osmo-remsim/contrib/openwrt/osmo-remsim-client package/
   cp -r /path/to/osmo-remsim/contrib/openwrt/luci-app-remsim package/
   ```

3. **Install feed dependencies:**
   ```bash
   # Update feeds
   ./scripts/feeds update -a
   ./scripts/feeds install -a
   
   # Install LuCI if needed for luci-app-remsim
   ./scripts/feeds install luci
   ```

4. **Build the packages (in dependency order):**
   ```bash
   # Build dependencies first
   make package/libtalloc/compile V=s
   make package/libosmocore/compile V=s
   make package/libosmo-netif/compile V=s
   
   # Then build main packages
   make package/osmo-remsim-client/compile V=s
   
   # Build luci-app-remsim package
   make package/luci-app-remsim/compile V=s
   ```

5. **Find generated IPK files:**
   ```bash
   find bin/ -name "*.ipk"
   ```

   Typical locations:
   - `bin/packages/aarch64_cortex-a53/base/libtalloc_*.ipk`
   - `bin/packages/aarch64_cortex-a53/base/libosmocore_*.ipk`
   - `bin/packages/aarch64_cortex-a53/base/libosmo-gsm_*.ipk`
   - `bin/packages/aarch64_cortex-a53/base/libosmo-netif_*.ipk`
   - `bin/packages/aarch64_cortex-a53/base/osmo-remsim-client_*.ipk`
   - `bin/packages/aarch64_cortex-a53/luci/luci-app-remsim_*.ipk`

### Method 3: Using Image Builder

If you want to include these packages in a custom firmware image:

1. **Download Image Builder:**
   ```bash
   wget https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/openwrt-imagebuilder-23.05.6-mediatek-filogic.Linux-x86_64.tar.xz
   tar xf openwrt-imagebuilder-23.05.6-mediatek-filogic.Linux-x86_64.tar.xz
   cd openwrt-imagebuilder-23.05.6-mediatek-filogic.Linux-x86_64
   ```

2. **Add custom packages:**
   ```bash
   mkdir -p packages
   cp /path/to/*.ipk packages/
   ```

3. **Build custom firmware:**
   ```bash
   make image PACKAGES="osmo-remsim-client luci-app-remsim ..." PROFILE=yourprofile
   ```

## Package Installation

### Installing on OpenWrt Device

1. **Transfer IPK files to router:**
   ```bash
   # Transfer all packages (dependencies + main packages)
   scp libtalloc_*.ipk libosmocore_*.ipk libosmo-gsm_*.ipk libosmo-netif_*.ipk \
       osmo-remsim-client_*.ipk luci-app-remsim_*.ipk root@router.local:/tmp/
   ```

2. **Install packages (in dependency order):**
   ```bash
   ssh root@router.local
   opkg update
   
   # Install dependencies first
   opkg install /tmp/libtalloc_*.ipk
   opkg install /tmp/libosmocore_*.ipk /tmp/libosmo-gsm_*.ipk
   opkg install /tmp/libosmo-netif_*.ipk
   
   # Then install main packages
   opkg install /tmp/osmo-remsim-client_*.ipk
   opkg install /tmp/luci-app-remsim_*.ipk
   ```

3. **Configure via LuCI:**
   - Navigate to: Services → Remote SIM
   - Or edit: `/etc/config/remsim`

4. **Start service:**
   ```bash
   /etc/init.d/remsim enable
   /etc/init.d/remsim start
   ```

## Package Contents

### osmo-remsim-client Package Structure
```
/usr/bin/
  ├── osmo-remsim-client-openwrt
  └── osmo-remsim-client-shell
/usr/lib/
  └── libosmo-rspro.so*
/etc/config/
  └── remsim
/etc/init.d/
  └── remsim
/usr/share/osmo-remsim/
  └── openwrt-event-script.sh
```

### luci-app-remsim Package Structure
```
/usr/lib/lua/luci/controller/
  └── remsim.lua
/usr/lib/lua/luci/model/cbi/remsim/
  ├── config.lua
  ├── modems.lua
  └── advanced.lua
/usr/lib/lua/luci/view/remsim/
  └── status.htm
```

## Troubleshooting

### Missing Dependencies
The build system now includes package definitions for all required dependencies (libtalloc, libosmocore, libosmo-netif). 

If using the automated `build-ipk.sh` script, dependencies are built automatically. If building manually, ensure you build packages in this order:
```bash
make package/libtalloc/compile V=s
make package/libosmocore/compile V=s
make package/libosmo-netif/compile V=s
make package/osmo-remsim-client/compile V=s
```

### Build Errors
Enable verbose output to see detailed error messages:
```bash
make package/osmo-remsim-client/compile V=s 2>&1 | tee build.log
```

### Cross-Compilation Issues
Ensure the correct toolchain is being used:
```bash
# Check target architecture
grep "^CONFIG_TARGET_ARCH" .config

# Should match: CONFIG_TARGET_ARCH="aarch64"
```

## Development

### Testing Changes
To test changes without full rebuild:

1. Clean the package:
   ```bash
   make package/osmo-remsim-client/clean
   ```

2. Rebuild:
   ```bash
   make package/osmo-remsim-client/compile V=s
   ```

### Package Signing
To sign packages for production:

```bash
# Generate signing key (if not exists)
make package/index

# Build with signature
make package/osmo-remsim-client/compile BUILD_KEY=/path/to/key.pub
```

## References

- [OpenWrt Build System](https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem)
- [OpenWrt Package Guidelines](https://openwrt.org/docs/guide-developer/packages)
- [LuCI Development](https://github.com/openwrt/luci/wiki)
- [osmo-remsim Documentation](../../README.md)

## Support

For issues or questions:
- GitHub Issues: https://github.com/terminills/osmo-remsim/issues
- Osmocom Mailing List: simtrace@lists.osmocom.org
