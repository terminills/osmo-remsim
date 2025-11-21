# OpenWRT Integration Guide for osmo-remsim-client

## Overview

The `osmo-remsim-client-openwrt` binary provides OpenWRT router integration for the osmo-remsim remote SIM system. It enables OpenWRT routers to bypass their local SIM slot and use remote SIM cards through the remsim-server infrastructure, including support for KI (Authentication Key) proxy functionality.

## Features

- **SIM Slot Bypass**: Hardware-level switching between local and remote SIM cards via GPIO control
- **Router Integration**: Direct integration with OpenWRT modem subsystem
- **KI Proxy Support**: Authentication handled through remsim-server with KI proxy capabilities
- **Automatic Hardware Detection**: Auto-detects common OpenWRT modem devices
- **Event Script Support**: Extensible event-driven architecture for custom hardware control
- **GPIO Configuration**: Flexible GPIO pin mapping for different hardware platforms

## Architecture

```
OpenWRT Router
├── Modem (e.g., QMI/AT interface)
├── SIM Switch (GPIO-controlled)
│   ├── Local SIM Slot (physical)
│   └── Remote SIM (via remsim-client)
└── osmo-remsim-client-openwrt
    ├── Connects to remsim-server (control plane)
    └── Connects to remsim-bankd (data plane)
```

## Hardware Requirements

### GPIO Pins

The client requires two GPIO pins for basic operation:

1. **SIM Switch GPIO**: Controls routing between local and remote SIM
   - Low (0): Local SIM slot active
   - High (1): Remote SIM active (bypass mode)
   - Default: GPIO 20

2. **Modem Reset GPIO**: Triggers modem hardware reset
   - Pulse high-to-low to reset modem
   - Default: GPIO 21

### Supported Modems

The client supports OpenWRT routers with:
- Qualcomm QMI-based modems (e.g., `/dev/cdc-wdm0`)
- Serial AT command modems (e.g., `/dev/ttyUSB2`)
- Any modem with standard SIM interface

## Installation

### Prerequisites

```bash
# On OpenWRT router
opkg update
opkg install libosmocore libosmo-netif libosmo-gsm
```

### Building for OpenWRT

#### Option 1: Cross-compile on development machine

```bash
# Configure for OpenWRT toolchain
export PATH=/path/to/openwrt/staging_dir/toolchain-xxx/bin:$PATH
export CC=xxx-linux-gcc
export PKG_CONFIG_PATH=/path/to/openwrt/staging_dir/target-xxx/usr/lib/pkgconfig

./configure --host=xxx-linux --disable-remsim-server
make
```

#### Option 2: Include in OpenWRT buildroot

Copy the osmo-remsim package to your OpenWRT build system's `feeds/packages/net/` directory.

### Installing on Router

```bash
# Copy binary to router
scp osmo-remsim-client-openwrt root@router:/usr/bin/

# Copy event script
scp contrib/openwrt-event-script.sh root@router:/etc/remsim/event-script.sh
chmod +x /etc/remsim/event-script.sh

# Create config directory
ssh root@router 'mkdir -p /etc/remsim'
```

## Configuration

### Command-Line Options

```bash
osmo-remsim-client-openwrt \
  -i <server-ip>           # remsim-server IP address
  -p <server-port>         # remsim-server port (default: 9998)
  -c <client-id>           # RSPRO Client ID (0-1023)
  -n <client-slot>         # RSPRO Slot number (0-1023)
  -V <gpio-sim-switch>     # GPIO pin for SIM switching (default: 20)
  -P <gpio-modem-reset>    # GPIO pin for modem reset (default: 21)
  -H <modem-device>        # Modem device path (e.g., /dev/ttyUSB2)
  -e <event-script>        # Path to event script
  -a <atr-hex>             # Default ATR in hex format
  -d <debug-options>       # Debug logging (e.g., DMAIN:DST2)
```

### GPIO Pin Configuration

GPIO pins are specified using the existing USB vendor/product ID options for maximum compatibility:

- `-V <pin>`: SIM switch GPIO pin number
- `-P <pin>`: Modem reset GPIO pin number

Example:
```bash
# Use GPIO 22 for SIM switch and GPIO 23 for modem reset
osmo-remsim-client-openwrt -V 22 -P 23 -i 192.168.1.100 -c 1 -n 0
```

### Event Script

The event script is called for various hardware control operations. Configure it with environment variables:

```bash
export SIM_SWITCH_GPIO=20
export MODEM_RESET_GPIO=21
export OPENWRT_MODEM_DEVICE=/dev/ttyUSB2

osmo-remsim-client-openwrt -e /etc/remsim/event-script.sh \
  -i 192.168.1.100 -c 1 -n 0
```

## Usage Examples

### Basic Remote SIM Usage

```bash
# Connect to remsim-server and use remote SIM in slot 0
osmo-remsim-client-openwrt \
  -i 192.168.1.100 \
  -p 9998 \
  -c 1 \
  -n 0 \
  -e /etc/remsim/event-script.sh
```

### Custom GPIO Configuration

```bash
# Use non-default GPIO pins for hardware with different layout
osmo-remsim-client-openwrt \
  -i 192.168.1.100 \
  -c 1 -n 0 \
  -V 25 \  # SIM switch on GPIO 25
  -P 26 \  # Modem reset on GPIO 26
  -H /dev/cdc-wdm0  # QMI modem device
```

### With KI Proxy Support

The KI proxy is configured on the remsim-server side:

```bash
# On remsim-server
osmo-remsim-server -k -K 5 -M 123456789012345

# On OpenWRT router (client connects normally)
osmo-remsim-client-openwrt -i 192.168.1.100 -c 1 -n 0
```

The server will proxy authentication requests, allowing the router to authenticate without direct access to Ki keys.

### Running as Daemon

Create a systemd service or init.d script:

```bash
# /etc/init.d/remsim-client
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/osmo-remsim-client-openwrt \
        -i 192.168.1.100 \
        -c 1 -n 0 \
        -e /etc/remsim/event-script.sh
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

Enable and start:
```bash
/etc/init.d/remsim-client enable
/etc/init.d/remsim-client start
```

## Troubleshooting

### Check GPIO Exports

```bash
# List exported GPIOs
ls -la /sys/class/gpio/

# Check GPIO value
cat /sys/class/gpio/gpio20/value
```

### Check Modem Device

```bash
# List USB serial devices
ls -la /dev/ttyUSB*

# List QMI devices
ls -la /dev/cdc-wdm*

# Test modem communication
echo -e "ATI\r" > /dev/ttyUSB2
cat /dev/ttyUSB2
```

### Enable Debug Logging

```bash
osmo-remsim-client-openwrt \
  -d DMAIN:DPCU:DST2:DSLOTMAPS:DRSPRO \
  -i 192.168.1.100 -c 1 -n 0
```

### Check Connection Status

```bash
# View logs
logread | grep remsim

# Check process
ps | grep osmo-remsim-client-openwrt

# Test server connectivity
telnet 192.168.1.100 9998
```

## Hardware-Specific Notes

### Common OpenWRT Routers

#### GL.iNet Routers (e.g., GL-X750)
- SIM switch typically on GPIO 7 or GPIO 20
- Modem reset on GPIO 21
- Modem device: `/dev/ttyUSB2` or `/dev/cdc-wdm0`

#### Teltonika RUT Routers
- Check manufacturer documentation for GPIO mappings
- Usually uses QMI interface: `/dev/cdc-wdm0`

#### Generic OpenWRT with USB Modem
- SIM switching may require external relay/multiplexer
- GPIO configuration varies by board

### Custom Hardware Integration

For custom SIM switching hardware:

1. Identify GPIO pins for SIM routing
2. Test GPIO control manually:
   ```bash
   echo 20 > /sys/class/gpio/export
   echo out > /sys/class/gpio/gpio20/direction
   echo 1 > /sys/class/gpio/gpio20/value
   ```
3. Configure event script for your hardware
4. Run client with appropriate GPIO settings

## Security Considerations

1. **Network Security**: Use VPN or secure network for remsim-server communication
2. **Authentication**: Configure proper client authentication on remsim-server
3. **KI Protection**: KI keys should only be stored on remsim-bankd, never on client
4. **Access Control**: Restrict access to GPIO and modem devices

## Advanced Features

### Multiple SIM Slots

For routers with multiple modems, run separate client instances:

```bash
# Modem 1
osmo-remsim-client-openwrt -c 1 -n 0 -V 20 -P 21 -H /dev/ttyUSB2 &

# Modem 2
osmo-remsim-client-openwrt -c 2 -n 0 -V 22 -P 23 -H /dev/ttyUSB5 &
```

### ATR Customization

Provide custom ATR if needed:

```bash
osmo-remsim-client-openwrt \
  -a 3B9F95801FC78031E073FE211B66D00090004831 \
  -r \  # Ignore ATR from bankd
  -i 192.168.1.100 -c 1 -n 0
```

## Related Documentation

- [osmo-remsim User Manual](https://downloads.osmocom.org/docs/latest/osmo-remsim-usermanual.pdf)
- [RSPRO Protocol Specification](https://osmocom.org/projects/osmo-remsim/wiki)
- [OpenWRT Development Guide](https://openwrt.org/docs/guide-developer/start)

## Support

For issues specific to OpenWRT integration:
- Check logs: `logread | grep remsim`
- Test GPIO manually
- Verify modem connectivity
- Report issues on [osmocom.org](https://osmocom.org/projects/osmo-remsim/issues)
