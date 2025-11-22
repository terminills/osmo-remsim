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

## Prerequisites

### OpenWrt SDK
Download the OpenWrt SDK for your target platform:

```bash
# For MediaTek MT7986 (Filogic) - aarch64
wget https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
cd openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64
```

### Required Dependencies
The packages depend on Osmocom libraries that need to be available in the OpenWrt SDK:
- libosmocore >= 1.11.0
- libosmo-netif >= 1.6.0
- libosmo-gsm >= 1.11.0

## Building IPK Packages

### Method 1: Using OpenWrt SDK (Recommended)

1. **Setup the SDK:**
   ```bash
   export OPENWRT_SDK_PATH=/path/to/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64
   cd $OPENWRT_SDK_PATH
   ```

2. **Copy package feeds to SDK:**
   ```bash
   # Copy the package definitions
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

4. **Configure packages:**
   ```bash
   make menuconfig
   # Navigate to:
   # - Network -> Telephony -> osmo-remsim-client [M]
   # - LuCI -> 3. Applications -> luci-app-remsim [M]
   # Save and exit
   ```

5. **Build the packages:**
   ```bash
   # Build osmo-remsim-client package
   make package/osmo-remsim-client/compile V=s
   
   # Build luci-app-remsim package
   make package/luci-app-remsim/compile V=s
   ```

6. **Find generated IPK files:**
   ```bash
   find bin/ -name "osmo-remsim-client*.ipk"
   find bin/ -name "luci-app-remsim*.ipk"
   ```

   Typical locations:
   - `bin/packages/aarch64_cortex-a53/base/osmo-remsim-client_*.ipk`
   - `bin/packages/aarch64_cortex-a53/luci/luci-app-remsim_*.ipk`

### Method 2: Using Image Builder

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
   scp osmo-remsim-client_*.ipk luci-app-remsim_*.ipk root@router.local:/tmp/
   ```

2. **Install packages:**
   ```bash
   ssh root@router.local
   opkg update
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
If you get errors about missing Osmocom libraries:

1. Add Osmocom feed to your SDK:
   ```bash
   echo "src-git osmocom https://gitea.osmocom.org/openwrt/meta-osmocom.git" >> feeds.conf.default
   ./scripts/feeds update osmocom
   ./scripts/feeds install -p osmocom libosmocore libosmo-netif
   ```

2. Build the dependencies first:
   ```bash
   make package/libosmocore/compile
   make package/libosmo-netif/compile
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
