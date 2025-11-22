# OpenWrt IPK Package Generation - Summary

This document summarizes the OpenWrt package infrastructure created for osmo-remsim.

## What Was Created

### 1. Package Definitions

Two OpenWrt packages have been created to enable easy deployment of osmo-remsim on OpenWrt routers:

#### osmo-remsim-client (Binary Package)
**Location:** `contrib/openwrt/osmo-remsim-client/`

**Contents:**
- `Makefile` - OpenWrt package build definition
- `files/remsim.config` - Default UCI configuration
- `files/remsim.init` - Procd init script

**What it installs:**
- `/usr/bin/osmo-remsim-client-openwrt` - Main OpenWrt client (ELF aarch64)
- `/usr/bin/osmo-remsim-client-shell` - Interactive shell client (ELF aarch64)
- `/usr/lib/libosmo-rspro.so*` - Shared RSPRO protocol library
- `/etc/config/remsim` - UCI configuration file
- `/etc/init.d/remsim` - Service init script
- `/usr/share/osmo-remsim/openwrt-event-script.sh` - Hardware event handler

**Dependencies:**
- libosmocore (>= 1.11.0)
- libosmo-netif (>= 1.6.0)
- libosmo-gsm (>= 1.11.0)
- libpthread
- librt

#### luci-app-remsim (Web Interface Package)
**Location:** `contrib/openwrt/luci-app-remsim/`

**Contents:**
- `Makefile` - LuCI application package definition
- `luasrc/` - LuCI application code (already existed)
  - `controller/remsim.lua` - Application controller
  - `model/cbi/remsim/*.lua` - Configuration pages
  - `view/remsim/status.htm` - Status page template
- `root/` - Root filesystem overlays (already existed)
  - `etc/config/remsim` - Default configuration
  - `etc/init.d/remsim` - Init script

**What it provides:**
- LuCI web interface at: **Services → Remote SIM**
- Configuration pages:
  - Server connection settings
  - Client identification
  - Modem configuration (single/dual)
  - IonMesh integration
  - Advanced options
- Real-time status monitoring
- Service control (start/stop/restart)

**Dependencies:**
- osmo-remsim-client
- luci-base

### 2. Documentation

#### README.md
**Location:** `contrib/openwrt/README.md`

Comprehensive guide covering:
- Package overview
- OpenWrt SDK setup
- Build instructions (SDK and Image Builder methods)
- Installation procedures
- Package contents
- Troubleshooting tips

#### INSTALL.md
**Location:** `contrib/openwrt/INSTALL.md`

Step-by-step installation guide including:
- Prerequisites
- Package transfer and installation
- Configuration (LuCI and CLI)
- Advanced setup (dual-modem, IonMesh)
- Troubleshooting common issues
- Uninstallation steps

### 3. Build Automation

#### build-ipk.sh
**Location:** `contrib/openwrt/build-ipk.sh`

Automated build script features:
- Automatic SDK detection and setup
- Package feed installation
- Parallel compilation
- Build both or individual packages
- Clean build support
- Verbose output option
- Built package location reporting

**Usage:**
```bash
export OPENWRT_SDK_PATH=/path/to/openwrt-sdk-23.05.6-mediatek-filogic
./contrib/openwrt/build-ipk.sh
```

### 4. Configuration Changes

#### .gitignore Update
Modified to allow tracking of OpenWrt package Makefiles while still ignoring generated Makefiles from autotools:

```gitignore
Makefile.in
Makefile
Makefile.am.sample

# But keep OpenWrt package Makefiles
!contrib/openwrt/*/Makefile
```

## Target Platform

The packages are designed for the MediaTek Filogic platform:

- **Architecture:** aarch64 (ARM 64-bit)
- **Target:** mediatek/filogic
- **OpenWrt Version:** 23.05.6
- **Toolchain:** gcc-12.3.0 with musl libc
- **SDK:** `openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64`

**Source:** https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/

The binaries mentioned in the issue match this configuration:
```
src/client/.libs/osmo-remsim-client-openwrt: ELF 64-bit LSB executable, ARM aarch64
src/client/.libs/osmo-remsim-client-shell: ELF 64-bit LSB executable, ARM aarch64
```

## Building IPK Packages

### Quick Start

1. **Download OpenWrt SDK:**
   ```bash
   wget https://downloads.openwrt.org/releases/23.05.6/targets/mediatek/filogic/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
   tar xf openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
   ```

2. **Set SDK path:**
   ```bash
   export OPENWRT_SDK_PATH=$PWD/openwrt-sdk-23.05.6-mediatek-filogic_gcc-12.3.0_musl.Linux-x86_64
   ```

3. **Build packages:**
   ```bash
   cd /path/to/osmo-remsim
   ./contrib/openwrt/build-ipk.sh
   ```

4. **Find built packages:**
   ```bash
   find $OPENWRT_SDK_PATH/bin/ -name "*.ipk"
   ```

   Expected output:
   ```
   bin/packages/aarch64_cortex-a53/base/osmo-remsim-client_0.4.1-1_aarch64_cortex-a53.ipk
   bin/packages/aarch64_cortex-a53/luci/luci-app-remsim_0.4.1-1_all.ipk
   ```

### Manual Build

If you prefer manual control:

```bash
cd $OPENWRT_SDK_PATH

# Copy package definitions
cp -r /path/to/osmo-remsim/contrib/openwrt/osmo-remsim-client package/
cp -r /path/to/osmo-remsim/contrib/openwrt/luci-app-remsim package/

# Update feeds
./scripts/feeds update -a
./scripts/feeds install -a

# Build packages
make package/osmo-remsim-client/compile V=s
make package/luci-app-remsim/compile V=s
```

## Installing on Router

### Basic Installation

```bash
# Transfer IPK files
scp osmo-remsim-client_*.ipk luci-app-remsim_*.ipk root@router:/tmp/

# SSH to router
ssh root@router

# Install packages
opkg update
opkg install /tmp/osmo-remsim-client_*.ipk
opkg install /tmp/luci-app-remsim_*.ipk

# Configure and start
vi /etc/config/remsim  # or use LuCI web interface
/etc/init.d/remsim enable
/etc/init.d/remsim start
```

### Configuration

**Via LuCI Web Interface:**
1. Browse to `http://router/cgi-bin/luci`
2. Navigate to: Services → Remote SIM
3. Configure settings
4. Click Save & Apply

**Via UCI Command Line:**
```bash
uci set remsim.service.enabled='1'
uci set remsim.client.client_id='router-001'
uci set remsim.server.host='remsim.example.com'
uci set remsim.server.port='9998'
uci commit remsim
/etc/init.d/remsim restart
```

## Package Features

### osmo-remsim-client Features

1. **Remote SIM Authentication**
   - Connects to remsim-server infrastructure
   - Proxies SIM card communication
   - Supports KI proxy mode

2. **Modem Support**
   - Single modem mode
   - Dual modem mode (FM350-GL + 850L)
   - Automatic device detection
   - GPIO-based SIM slot switching

3. **Integration**
   - OpenWrt UCI configuration
   - Procd process management
   - Syslog logging
   - Event scripts for hardware control

4. **IonMesh Support** (optional)
   - Centralized orchestration
   - Dynamic SIM mapping
   - Tenant isolation
   - MCC/MNC filtering

### luci-app-remsim Features

1. **Configuration Pages**
   - **Configuration:** Server and client settings
   - **Modems:** Device paths and GPIO configuration
   - **Advanced:** Logging, event scripts, TLS settings
   - **Status:** Real-time monitoring

2. **Status Monitoring**
   - Service running/stopped status
   - Client connection information
   - Modem detection and status
   - IonMesh reachability

3. **Service Control**
   - Start/stop/restart service
   - Enable/disable autostart
   - Test connection
   - View logs

## File Structure

```
contrib/openwrt/
├── README.md                          # Build and usage documentation
├── INSTALL.md                         # Installation guide
├── PACKAGE_SUMMARY.md                 # This file
├── build-ipk.sh                       # Automated build script
├── osmo-remsim-client/               # Binary package
│   ├── Makefile                       # OpenWrt package definition
│   └── files/
│       ├── remsim.config             # Default UCI config
│       └── remsim.init               # Init script
└── luci-app-remsim/                  # Web interface package
    ├── Makefile                       # LuCI package definition
    ├── luasrc/                        # LuCI application code
    │   ├── controller/
    │   │   └── remsim.lua
    │   ├── model/cbi/remsim/
    │   │   ├── config.lua
    │   │   ├── modems.lua
    │   │   └── advanced.lua
    │   └── view/remsim/
    │       └── status.htm
    └── root/                          # Root filesystem overlay
        └── etc/
            ├── config/remsim
            └── init.d/remsim
```

## Next Steps

### For Developers

1. **Test the build process** with your OpenWrt SDK
2. **Verify package installation** on target hardware
3. **Test functionality** with remsim-server
4. **Report any issues** on GitHub

### For End Users

1. **Build the packages** following README.md
2. **Install on your router** following INSTALL.md
3. **Configure via LuCI** or command line
4. **Connect to remsim-server** infrastructure

### Future Enhancements

Potential improvements:
- [ ] Add Osmocom feed integration for easier dependency management
- [ ] Create pre-built IPK repository
- [ ] Add more architectures (ramips, ipq40xx, etc.)
- [ ] Integrate with OpenWrt's SQM for QoS
- [ ] Add network namespace support
- [ ] Create upgrade scripts for seamless updates

## Support and Resources

- **Repository:** https://github.com/terminills/osmo-remsim
- **Issues:** https://github.com/terminills/osmo-remsim/issues
- **Documentation:** See `README.md` in repository root
- **Mailing List:** simtrace@lists.osmocom.org
- **OpenWrt Docs:** https://openwrt.org/docs/

## License

All OpenWrt package files are licensed under GPL-2.0, consistent with OpenWrt packaging guidelines and the osmo-remsim project license.

## Acknowledgments

- Osmocom project for the remsim suite
- OpenWrt community for the excellent build system
- Contributors to the luci-app-remsim web interface

---

**Package Version:** 0.4.1  
**Release:** 1  
**Last Updated:** 2024-11-22  
**Maintainer:** Osmocom <openbsc@lists.osmocom.org>
