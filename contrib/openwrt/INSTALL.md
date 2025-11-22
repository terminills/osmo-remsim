# Installation Guide for OpenWrt IPK Packages

This guide walks through installing the osmo-remsim packages on your OpenWrt router.

## Prerequisites

- OpenWrt router running version 23.05 or later
- SSH access to the router
- Internet connection (for installing dependencies)
- At least 5MB free space on the router

## Quick Installation

### Step 1: Transfer IPK Files

Transfer the built IPK files to your router:

```bash
# Replace <router-ip> with your router's IP address
scp osmo-remsim-client_*.ipk root@<router-ip>:/tmp/
scp luci-app-remsim_*.ipk root@<router-ip>:/tmp/
```

### Step 2: Connect to Router

```bash
ssh root@<router-ip>
```

### Step 3: Install Packages

```bash
# Update package list
opkg update

# Install the client package (includes binaries and libraries)
opkg install /tmp/osmo-remsim-client_*.ipk

# Install the LuCI web interface (optional but recommended)
opkg install /tmp/luci-app-remsim_*.ipk
```

### Step 4: Configure

#### Option A: Using LuCI Web Interface (Recommended)

1. Open your router's web interface: `http://<router-ip>/`
2. Log in with your credentials
3. Navigate to: **Services → Remote SIM**
4. Configure the following:
   - **Server**: Remote SIM server hostname/IP and port
   - **Client**: Client ID and slot number
   - **Modems**: Modem device paths and GPIO settings
5. Click **Save & Apply**

#### Option B: Using Command Line

Edit the configuration file:

```bash
vi /etc/config/remsim
```

Minimal configuration example:

```
config service 'service'
    option enabled '1'

config client 'client'
    option client_id 'router-001'
    option client_slot '0'

config server 'server'
    option host 'remsim.example.com'
    option port '9998'

config modems 'modems'
    option dual_modem '0'
    option device '/dev/ttyUSB2'
```

### Step 5: Start Service

```bash
# Enable service to start at boot
/etc/init.d/remsim enable

# Start the service
/etc/init.d/remsim start

# Check status
/etc/init.d/remsim status
```

### Step 6: Verify Installation

Check that the service is running:

```bash
# Check process
ps | grep osmo-remsim-client-openwrt

# Check logs
logread | grep remsim

# Test connection (if LuCI installed)
/usr/bin/remsim-test-connection.sh
```

## Advanced Configuration

### Dual-Modem Setup

For routers with multiple modems (e.g., FM350-GL + 850L):

```
config modems 'modems'
    option dual_modem '1'

config modem1 'modem1'
    option device '/dev/ttyUSB2'
    option sim_switch_gpio '20'
    option reset_gpio '21'

config modem2 'modem2'
    option device '/dev/ttyUSB5'
    option sim_switch_gpio '22'
    option reset_gpio '23'
```

### IonMesh Integration

To enable centralized orchestration:

```
config ionmesh 'ionmesh'
    option enabled '1'
    option host 'ionmesh.example.com'
    option port '5000'
    option tenant_id '1'
    option mapping_mode 'KI_PROXY_SWSIM'
```

### Debug Logging

Enable detailed logging for troubleshooting:

```
config logging 'logging'
    option debug '1'
    option log_categories 'DMAIN:DEBUG:DPCU:DEBUG'
    option syslog '1'
```

View logs:

```bash
logread -f | grep remsim
```

### Custom Event Script

For hardware-specific actions (GPIO control, LED indicators):

```
config advanced 'advanced'
    option event_script '/usr/share/osmo-remsim/openwrt-event-script.sh'
    option keep_running '1'
```

## Troubleshooting

### Service Won't Start

Check configuration:
```bash
uci show remsim
```

Check for errors:
```bash
logread | grep -i error
```

Test manually:
```bash
/usr/bin/osmo-remsim-client-openwrt -i remsim.example.com -p 9998 -c router-001
```

### Can't Connect to Server

Verify network connectivity:
```bash
ping remsim.example.com
telnet remsim.example.com 9998
```

Check firewall rules:
```bash
iptables -L -n | grep 9998
```

### Modem Not Detected

List available devices:
```bash
ls -la /dev/ttyUSB*
ls -la /dev/cdc-wdm*
```

Check modem status:
```bash
# For QMI modems
uqmi -d /dev/cdc-wdm0 --get-device-operating-mode

# For AT command modems
echo "ATI" > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2
```

### LuCI Interface Not Showing

Clear LuCI cache:
```bash
rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart
```

## Uninstallation

To remove the packages:

```bash
# Stop service
/etc/init.d/remsim stop
/etc/init.d/remsim disable

# Remove packages
opkg remove luci-app-remsim
opkg remove osmo-remsim-client

# Optional: Remove configuration
rm -rf /etc/config/remsim
```

## Package Information

### osmo-remsim-client Package Contents

```
/usr/bin/osmo-remsim-client-openwrt    # Main OpenWrt client binary
/usr/bin/osmo-remsim-client-shell      # Interactive shell client
/usr/lib/libosmo-rspro.so*             # RSPRO protocol library
/etc/config/remsim                     # UCI configuration file
/etc/init.d/remsim                     # Init script (procd)
/usr/share/osmo-remsim/                # Additional scripts
```

### luci-app-remsim Package Contents

```
/usr/lib/lua/luci/controller/remsim.lua           # Main controller
/usr/lib/lua/luci/model/cbi/remsim/*.lua          # Configuration pages
/usr/lib/lua/luci/view/remsim/status.htm          # Status page template
```

## Dependencies

The packages require the following libraries:
- libosmocore (>= 1.11.0)
- libosmo-netif (>= 1.6.0)
- libosmo-gsm (>= 1.11.0)
- libpthread
- librt

These should be automatically installed by opkg.

## Support

For issues or questions:
- GitHub Issues: https://github.com/terminills/osmo-remsim/issues
- Documentation: See `README.md` in the repository root
- Mailing List: simtrace@lists.osmocom.org

## Version Information

- Package Version: 0.4.1
- Release: 1
- License: GPL-2.0
- Maintainer: Osmocom <openbsc@lists.osmocom.org>
