# OpenWRT Client Enhancements

This document describes the enhancements made to the osmo-remsim-client-openwrt implementation.

## New Features

### 1. Statistics Tracking

The OpenWRT client now tracks comprehensive statistics about its operation:

- **Uptime**: Time since client started
- **TPDUs sent**: Number of TPDUs transmitted to modem
- **TPDUs received**: Number of TPDUs received from modem
- **Errors**: Count of transmission errors
- **Reconnections**: Number of times reconnected to server
- **SIM switches**: Number of times switched between local and remote SIM

Statistics are automatically printed every hour (configurable) and can also be printed on-demand by sending SIGUSR2 signal to the process.

### 2. Signal Strength Monitoring

The client now periodically queries the modem signal strength using the AT+CSQ command. Signal strength is reported in dBm format.

Default monitoring interval: 60 seconds (configurable)

Signal strength values are included in statistics output.

### 3. Graceful Shutdown

The client now handles SIGINT and SIGTERM signals gracefully:

- Prints final statistics
- Switches back to local SIM before exiting
- Ensures clean shutdown

### 4. On-Demand Statistics

Send SIGUSR2 signal to the running process to print current statistics without restarting:

```bash
killall -USR2 osmo-remsim-client-openwrt
```

## Environment Variables

The following environment variables can be used to configure the OpenWRT client behavior:

### Signal Monitoring

- **OPENWRT_SIGNAL_INTERVAL**: Signal strength check interval in seconds
  - Default: 60
  - Set to 0 to disable signal monitoring
  - Example: `OPENWRT_SIGNAL_INTERVAL=120` (check every 2 minutes)

### Statistics Reporting

- **OPENWRT_STATS_INTERVAL**: Statistics print interval in seconds
  - Default: 3600 (1 hour)
  - Set to 0 to disable automatic printing
  - Example: `OPENWRT_STATS_INTERVAL=1800` (print every 30 minutes)

### Dual-Modem Configuration

- **OPENWRT_DUAL_MODEM**: Enable dual-modem mode
  - Default: disabled (single modem)
  - Example: `OPENWRT_DUAL_MODEM=1`

- **MODEM1_SIM_GPIO**: GPIO pin for modem 1 SIM switch
  - Default: 20
  - Example: `MODEM1_SIM_GPIO=6`

- **MODEM1_RESET_GPIO**: GPIO pin for modem 1 reset
  - Default: 21
  - Example: `MODEM1_RESET_GPIO=4`

- **MODEM1_DEVICE**: Device path for modem 1
  - Default: auto-detect (/dev/ttyUSB2 or /dev/cdc-wdm0)
  - Example: `MODEM1_DEVICE=/dev/ttyUSB2`

- **MODEM2_SIM_GPIO**: GPIO pin for modem 2 SIM switch
  - Default: 22
  - Example: `MODEM2_SIM_GPIO=7`

- **MODEM2_RESET_GPIO**: GPIO pin for modem 2 reset
  - Default: 23
  - Example: `MODEM2_RESET_GPIO=5`

- **MODEM2_DEVICE**: Device path for modem 2
  - Default: auto-detect (/dev/ttyUSB5 or /dev/cdc-wdm1)
  - Example: `MODEM2_DEVICE=/dev/ttyUSB5`

### IonMesh Configuration

- **IONMESH_HOST**: IonMesh orchestrator hostname
  - Default: localhost
  - Example: `IONMESH_HOST=ionmesh.example.com`

- **IONMESH_PORT**: IonMesh orchestrator port
  - Default: 5000
  - Example: `IONMESH_PORT=8080`

- **IONMESH_TENANT_ID**: Tenant ID for multi-tenant deployments
  - Default: 1
  - Example: `IONMESH_TENANT_ID=42`

- **IONMESH_MAPPING_MODE**: SIM mapping mode
  - Options: ONE_TO_ONE_SWSIM, ONE_TO_ONE_VSIM, KI_PROXY_SWSIM
  - Default: ONE_TO_ONE_SWSIM
  - Example: `IONMESH_MAPPING_MODE=KI_PROXY_SWSIM`

- **IONMESH_MCC_MNC**: Mobile Country Code and Mobile Network Code
  - Format: MCCMNC (e.g., 310410 for AT&T USA)
  - Used for carrier-specific SIM assignment
  - Example: `IONMESH_MCC_MNC=310410`

## Usage Examples

### Basic Usage

```bash
# Start client with default settings
osmo-remsim-client-openwrt -i 192.168.1.100

# With verbose logging
osmo-remsim-client-openwrt -i 192.168.1.100 -d DMAIN:DEBUG
```

### Custom Signal Monitoring

```bash
# Check signal strength every 30 seconds
OPENWRT_SIGNAL_INTERVAL=30 osmo-remsim-client-openwrt -i 192.168.1.100

# Disable signal monitoring
OPENWRT_SIGNAL_INTERVAL=0 osmo-remsim-client-openwrt -i 192.168.1.100
```

### Dual-Modem Setup

```bash
# Enable dual-modem mode with custom GPIO pins
OPENWRT_DUAL_MODEM=1 \
MODEM1_SIM_GPIO=6 \
MODEM1_RESET_GPIO=4 \
MODEM1_DEVICE=/dev/ttyUSB2 \
MODEM2_SIM_GPIO=7 \
MODEM2_RESET_GPIO=5 \
MODEM2_DEVICE=/dev/ttyUSB5 \
osmo-remsim-client-openwrt -i 192.168.1.100
```

### IonMesh Integration

```bash
# Register with IonMesh orchestrator
IONMESH_HOST=ionmesh.example.com \
IONMESH_PORT=5000 \
IONMESH_TENANT_ID=1 \
IONMESH_MAPPING_MODE=ONE_TO_ONE_SWSIM \
IONMESH_MCC_MNC=310410 \
osmo-remsim-client-openwrt -i 192.168.1.100 -e /usr/bin/ionmesh-event-script.sh
```

### Statistics and Monitoring

```bash
# Print statistics every 30 minutes
OPENWRT_STATS_INTERVAL=1800 osmo-remsim-client-openwrt -i 192.168.1.100

# Print statistics on demand (while client is running)
killall -USR2 osmo-remsim-client-openwrt
```

## Statistics Output Example

```
=== OpenWRT Client Statistics ===
Uptime: 2h 15m 42s
TPDUs sent: 1234
TPDUs received: 5678
Errors: 0
Reconnections: 2
SIM switches: 4
Last signal RSSI: -75 dBm
=================================
```

## Signal Handlers

The client responds to the following signals:

- **SIGINT (Ctrl+C)**: Graceful shutdown with statistics
- **SIGTERM**: Graceful shutdown with statistics
- **SIGUSR1**: Print talloc memory report (osmocom feature)
- **SIGUSR2**: Print current statistics without shutting down

## Logging

The client uses osmocom logging infrastructure. Debug categories:

- **DMAIN**: Main operations, statistics, signal monitoring
- **DRSPRO**: RSPRO protocol messages
- **DST2**: SIMtrace2 operations

Example logging configuration:

```bash
# Enable all debug messages
osmo-remsim-client-openwrt -i 192.168.1.100 -d DMAIN:DEBUG,DRSPRO:DEBUG

# Notice level for main, debug for protocol
osmo-remsim-client-openwrt -i 192.168.1.100 -d DMAIN:NOTICE,DRSPRO:DEBUG
```

## Router-Specific Configurations

### Zbtlink ZBT-Z8102AX

The client automatically detects ZBT-Z8102AX routers and applies appropriate GPIO mappings:

- Modem 1 SIM: GPIO 6
- Modem 1 Power: GPIO 4
- Modem 2 SIM: GPIO 7
- Modem 2 Power: GPIO 5
- PCIe Power: GPIO 3

These can be overridden using environment variables if needed.

## Best Practices

1. **Enable signal monitoring** for production deployments to track connection quality
2. **Set appropriate statistics interval** based on your monitoring needs (hourly for production, more frequent for troubleshooting)
3. **Use dual-modem mode** for critical deployments requiring 24/7 connectivity
4. **Monitor SIGUSR2 statistics** regularly to detect issues early
5. **Enable verbose logging** during initial deployment and troubleshooting
6. **Use IonMesh orchestration** for large-scale deployments with centralized management

## Troubleshooting

### No signal strength reported

- Check that modem device is accessible: `ls -l /dev/ttyUSB*` or `/dev/cdc-wdm*`
- Verify modem supports AT+CSQ command: `echo -e "AT+CSQ\r\n" > /dev/ttyUSB2`
- Check signal monitoring is enabled: `OPENWRT_SIGNAL_INTERVAL` > 0
- Enable debug logging: `-d DMAIN:DEBUG`

### Statistics not printing

- Check statistics interval: `OPENWRT_STATS_INTERVAL` should be > 0
- Send SIGUSR2 manually: `killall -USR2 osmo-remsim-client-openwrt`
- Check syslog: `logread | grep remsim`

### GPIO not working

- Verify GPIO is exported: `ls /sys/class/gpio/gpio20/`
- Check GPIO permissions: `ls -l /sys/class/gpio/gpio20/value`
- Try manual GPIO control: `echo 1 > /sys/class/gpio/gpio20/value`
- Check router-specific documentation for correct GPIO numbers

## Future Enhancements

Planned features (see ROADMAP.md):

- Prometheus metrics export
- Web UI for monitoring and configuration
- Advanced modem support (Sierra, Quectel)
- Automated failover and self-healing
- Load balancing across multiple modems
- eSIM profile management

---

**Related Documentation**:
- [README-OPENWRT.md](README-OPENWRT.md) - OpenWRT integration overview
- [ROADMAP.md](../ROADMAP.md) - Future enhancement plans
- [Q1-PROMETHEUS-METRICS.md](features/Q1-PROMETHEUS-METRICS.md) - Planned metrics export

**Version**: 1.0  
**Last Updated**: 2025-11-23
