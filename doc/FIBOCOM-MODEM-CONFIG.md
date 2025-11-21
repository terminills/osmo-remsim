# Fibocom Modem Configuration for osmo-remsim-client

## Overview

This document provides specific configuration details for Fibocom modems used with osmo-remsim-client-openwrt:

- **Fibocom FM350-GL**: Main data modem (Modem 1) for remote SIM (vSIM)
- **Fibocom 850L**: Always-on IoT modem (Modem 2) for heartbeat connectivity

## Hardware Specifications

### Fibocom FM350-GL (Main Data Modem)

**Product Details:**
- **Type**: 5G Sub-6GHz Module
- **Form Factor**: M.2 3052
- **Interface**: USB 3.1 / PCIe
- **Bands**: 
  - 5G NR: n1, n2, n3, n5, n7, n8, n12, n20, n25, n28, n38, n40, n41, n48, n66, n71, n77, n78, n79
  - LTE: B1-B5, B7, B8, B12, B13, B14, B17-B20, B25, B26, B28-B32, B34, B38-B43, B46, B48, B66, B71
- **Max Speed**: 4.67 Gbps DL / 1.25 Gbps UL
- **Chipset**: Qualcomm SDX62
- **USB VID:PID**: 2cb7:0a05

**USB Device Enumeration:**
```
/dev/ttyUSB0  - AT command port (Diag)
/dev/ttyUSB1  - AT command port (NMEA)
/dev/ttyUSB2  - AT command port (Main)
/dev/ttyUSB3  - AT command port (Modem)
/dev/cdc-wdm0 - QMI interface
```

### Fibocom 850L (IoT Modem)

**Product Details:**
- **Type**: LTE Cat-4 Module  
- **Form Factor**: LCC+LGA
- **Interface**: USB 2.0
- **Bands**:
  - LTE: B1, B2, B3, B4, B5, B7, B8, B12, B13, B18, B19, B20, B25, B26, B28, B66
- **Max Speed**: 150 Mbps DL / 50 Mbps UL
- **Chipset**: Qualcomm MDM9607
- **USB VID:PID**: 2cb7:01a0

**USB Device Enumeration:**
```
/dev/ttyUSB4  - AT command port (Diag)
/dev/ttyUSB5  - AT command port (Main)
/dev/ttyUSB6  - AT command port (Aux)
/dev/cdc-wdm1 - QMI interface
```

## Device Detection and Identification

### Check Connected Modems

```bash
# List USB devices and find Fibocom modems
lsusb | grep -i fibocom

# Expected output:
# Bus 001 Device 003: ID 2cb7:0a05 Fibocom Wireless Inc. FM350-GL
# Bus 001 Device 004: ID 2cb7:01a0 Fibocom Wireless Inc. 850L

# List serial devices
ls -la /dev/ttyUSB* /dev/cdc-wdm*

# Check which modem is which
for dev in /dev/ttyUSB2 /dev/ttyUSB5; do
  echo "=== $dev ==="
  echo -e "ATI\r" > $dev
  timeout 1 cat $dev 2>/dev/null | head -5
done
```

### Verify Modem Information

```bash
# FM350-GL (Main modem)
echo -e "ATI\r" > /dev/ttyUSB2 && timeout 1 cat /dev/ttyUSB2

# Expected output:
# Manufacturer: Fibocom Wireless Inc.
# Model: FM350-GL
# Revision: 18100.1000.00.00.11.02_GC
# IMEI: xxxxxxxxxxxxx

# 850L (IoT modem)
echo -e "ATI\r" > /dev/ttyUSB5 && timeout 1 cat /dev/ttyUSB5

# Expected output:
# Manufacturer: Fibocom Wireless Inc.
# Model: L850-GL
# Revision: 18418.5001.00.03.05.08
# IMEI: xxxxxxxxxxxxx
```

## OpenWRT Configuration

### Dual-Modem Configuration

Create configuration file: `/etc/config/remsim`

```bash
config service 'service'
	option enabled '1'

config client 'client'
	option client_id ''
	option client_slot '0'

config modems 'modems'
	option dual_modem '1'

config modem1 'modem1'
	option device '/dev/ttyUSB2'
	option sim_switch_gpio '20'
	option reset_gpio '21'
	# FM350-GL specific settings

config modem2 'modem2'
	option device '/dev/ttyUSB5'
	option sim_switch_gpio '22'
	option reset_gpio '23'
	# 850L specific settings

config ionmesh 'ionmesh'
	option enabled '1'
	option host 'ionmesh.example.com'
	option port '5000'
	option tenant_id '1'
	option mapping_mode 'KI_PROXY_SWSIM'
```

### Environment Variables Method

```bash
#!/bin/sh
# /etc/remsim/fibocom-config.sh

# Enable dual-modem mode
export OPENWRT_DUAL_MODEM=1

# Fibocom FM350-GL (Primary/Remote SIM)
export MODEM1_DEVICE=/dev/ttyUSB2
export MODEM1_SIM_GPIO=20
export MODEM1_RESET_GPIO=21

# Fibocom 850L (Always-on IoT)
export MODEM2_DEVICE=/dev/ttyUSB5
export MODEM2_SIM_GPIO=22
export MODEM2_RESET_GPIO=23

# IonMesh configuration
export IONMESH_HOST=ionmesh.example.com
export IONMESH_PORT=5000
export IONMESH_TENANT_ID=1
export IONMESH_MAPPING_MODE=KI_PROXY_SWSIM

# Run remsim client
osmo-remsim-client-openwrt \
  -e /etc/remsim/fibocom-event-script.sh \
  -d DMAIN:DPCU
```

## Modem-Specific Configuration

### FM350-GL Configuration (Main Modem)

#### Enable QMI Mode

```bash
# Check current USB configuration
echo -e 'AT+GTUSBMODE?\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Set to QMI mode (if not already)
echo -e 'AT+GTUSBMODE=7\r' > /dev/ttyUSB2

# Restart modem to apply
echo -e 'AT+CFUN=1,1\r' > /dev/ttyUSB2
sleep 5
```

#### Configure APN

```bash
# Set APN for your carrier
# Replace "your.apn.here" with actual APN
echo -e 'AT+CGDCONT=1,"IP","your.apn.here"\r' > /dev/ttyUSB2

# Example for AT&T
echo -e 'AT+CGDCONT=1,"IP","broadband"\r' > /dev/ttyUSB2

# Example for T-Mobile
echo -e 'AT+CGDCONT=1,"IP","fast.t-mobile.com"\r' > /dev/ttyUSB2

# Example for Verizon
echo -e 'AT+CGDCONT=1,"IP","vzwinternet"\r' > /dev/ttyUSB2
```

#### Verify 5G Configuration

```bash
# Check network registration
echo -e 'AT+COPS?\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Check signal quality
echo -e 'AT+CSQ\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Check serving cell (5G NR or LTE)
echo -e 'AT+QENG="servingcell"\r' > /dev/ttyUSB2
timeout 2 cat /dev/ttyUSB2
```

#### Enable GPS (Optional)

```bash
# FM350-GL has built-in GPS
echo -e 'AT+QGPS=1\r' > /dev/ttyUSB2

# Check GPS status
echo -e 'AT+QGPSLOC=2\r' > /dev/ttyUSB2
timeout 2 cat /dev/ttyUSB2
```

### 850L Configuration (IoT Modem)

#### Basic Setup

```bash
# Enable modem
echo -e 'AT+CFUN=1\r' > /dev/ttyUSB5

# Set APN for IoT SIM
# Most IoT SIMs use simple APN like "iot" or "m2m"
echo -e 'AT+CGDCONT=1,"IP","iot"\r' > /dev/ttyUSB5

# Check network registration
echo -e 'AT+CREG?\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5
```

#### Power Saving Mode (Optional)

```bash
# Enable power saving for IoT modem (reduces power consumption)
echo -e 'AT+CPSMS=1\r' > /dev/ttyUSB5

# Set eDRX mode for power efficiency
echo -e 'AT+CEDRXS=1,4\r' > /dev/ttyUSB5
```

#### Lock to Specific Band (Optional)

```bash
# Lock to specific LTE band for stability
# Example: Lock to Band 12 (700 MHz, good coverage)
echo -e 'AT+QCFG="band",0,1000,0\r' > /dev/ttyUSB5

# Lock to Band 2 (1900 MHz)
echo -e 'AT+QCFG="band",0,2,0\r' > /dev/ttyUSB5
```

## Network Interface Configuration

### QMI Network Setup

#### Install Required Packages

```bash
opkg update
opkg install kmod-usb-net-qmi-wwan uqmi
```

#### Configure Network Interfaces

Edit `/etc/config/network`:

```
# FM350-GL (Primary data)
config interface 'wwan0'
	option device '/dev/cdc-wdm0'
	option proto 'qmi'
	option apn 'your.apn.here'
	option pdptype 'ipv4v6'
	option modes 'all'
	option metric '100'

# 850L (IoT heartbeat)
config interface 'wwan1'
	option device '/dev/cdc-wdm1'
	option proto 'qmi'
	option apn 'iot'
	option pdptype 'ip'
	option modes 'lte'
	option metric '200'
```

Restart network:
```bash
/etc/init.d/network restart
```

### Verify Connectivity

```bash
# Check both interfaces
ifconfig wwan0
ifconfig wwan1

# Test primary modem
ping -I wwan0 -c 4 8.8.8.8

# Test IoT modem
ping -I wwan1 -c 4 8.8.8.8
```

## GPIO Configuration for SIM Switching

### Hardware Setup

Both modems require hardware SIM switching circuits:

```
┌─────────────────────────────────────────────────┐
│  FM350-GL (Modem 1)                             │
│  ┌──────────────┐                               │
│  │   SIM IF     │                               │
│  └──────┬───────┘                               │
│         │                                        │
│    GPIO 20 (Control)                            │
│         │                                        │
│  ┌──────▼───────┐                               │
│  │  ADG3304     │  (SIM Switch IC)              │
│  │  or TS3A27518│                               │
│  └──────┬───────┘                               │
│         │                                        │
│    ┌────┴─────┐                                 │
│    │          │                                  │
│  Local      Remote                              │
│  SIM Slot   (vSIM)                              │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  850L (Modem 2)                                 │
│  ┌──────────────┐                               │
│  │   SIM IF     │                               │
│  └──────┬───────┘                               │
│         │                                        │
│    GPIO 22 (Fixed Low)                          │
│         │                                        │
│  ┌──────▼───────┐                               │
│  │  Local IoT   │  (Always connected)           │
│  │  SIM Card    │                               │
│  └──────────────┘                               │
└─────────────────────────────────────────────────┘
```

### Configure GPIOs

```bash
# Export GPIOs
echo 20 > /sys/class/gpio/export  # FM350-GL SIM switch
echo 21 > /sys/class/gpio/export  # FM350-GL reset
echo 22 > /sys/class/gpio/export  # 850L SIM switch
echo 23 > /sys/class/gpio/export  # 850L reset

# Set directions
echo out > /sys/class/gpio/gpio20/direction
echo out > /sys/class/gpio/gpio21/direction
echo out > /sys/class/gpio/gpio22/direction
echo out > /sys/class/gpio/gpio23/direction

# Initialize values
echo 0 > /sys/class/gpio/gpio20/value  # FM350: Start with local SIM
echo 0 > /sys/class/gpio/gpio21/value  # Reset inactive
echo 0 > /sys/class/gpio/gpio22/value  # 850L: Always use local IoT SIM
echo 0 > /sys/class/gpio/gpio23/value  # Reset inactive
```

## Event Script for Fibocom Modems

Create `/etc/remsim/fibocom-event-script.sh`:

```bash
#!/bin/sh
# Event script for Fibocom FM350-GL and 850L modems

CAUSE="$1"

# Device paths
FM350_DEVICE="/dev/ttyUSB2"
L850_DEVICE="/dev/ttyUSB5"

# GPIO pins
FM350_SIM_GPIO=20
FM350_RESET_GPIO=21
L850_SIM_GPIO=22
L850_RESET_GPIO=23

log_message() {
	logger -t remsim-fibocom "$1"
	echo "[$(date)] $1"
}

gpio_set() {
	local gpio=$1
	local value=$2
	
	if [ ! -d "/sys/class/gpio/gpio${gpio}" ]; then
		echo "${gpio}" > /sys/class/gpio/export 2>/dev/null || true
		sleep 0.1
	fi
	
	echo "out" > "/sys/class/gpio/gpio${gpio}/direction" 2>/dev/null
	echo "${value}" > "/sys/class/gpio/gpio${gpio}/value" 2>/dev/null
	
	log_message "Set GPIO ${gpio} to ${value}"
}

modem_at_command() {
	local device=$1
	local cmd=$2
	
	if [ -c "${device}" ]; then
		echo -e "${cmd}\r" > "${device}" 2>/dev/null
		log_message "Sent AT command to ${device}: ${cmd}"
	fi
}

case "${CAUSE}" in
	event-server-connect)
		log_message "Connected to remsim-server"
		;;
		
	event-bankd-connect)
		log_message "Connected to bankd"
		;;
		
	event-config-bankd)
		log_message "Bankd configuration received"
		;;
		
	request-card-insert)
		log_message "Switching FM350-GL to remote SIM"
		gpio_set "${FM350_SIM_GPIO}" 1
		
		# Small delay for SIM switch to settle
		sleep 1
		
		# Trigger modem to detect new SIM
		modem_at_command "${FM350_DEVICE}" "AT+CFUN=1,1"
		;;
		
	request-card-remove)
		log_message "Switching FM350-GL to local SIM"
		gpio_set "${FM350_SIM_GPIO}" 0
		sleep 1
		modem_at_command "${FM350_DEVICE}" "AT+CFUN=1,1"
		;;
		
	request-modem-reset)
		log_message "Resetting FM350-GL modem"
		
		# Hardware reset via GPIO
		gpio_set "${FM350_RESET_GPIO}" 1
		sleep 1
		gpio_set "${FM350_RESET_GPIO}" 0
		sleep 3
		
		# Or software reset
		modem_at_command "${FM350_DEVICE}" "AT+CFUN=1,1"
		;;
		
	request-sim-remote)
		log_message "Remote SIM mode enabled"
		gpio_set "${FM350_SIM_GPIO}" 1
		;;
		
	request-sim-local)
		log_message "Local SIM mode enabled"
		gpio_set "${FM350_SIM_GPIO}" 0
		;;
		
	*)
		log_message "Unknown event: ${CAUSE}"
		;;
esac

exit 0
```

Make executable:
```bash
chmod +x /etc/remsim/fibocom-event-script.sh
```

## Troubleshooting

### FM350-GL Issues

#### Issue: Modem Not Detected

```bash
# Check USB connection
lsusb | grep 2cb7:0a05

# Check kernel messages
dmesg | grep -i fibocom

# Try USB reset
echo "1-1" > /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-1" > /sys/bus/usb/drivers/usb/bind
```

#### Issue: No 5G Connection

```bash
# Check if 5G is enabled
echo -e 'AT+QNWPREFCFG="mode_pref"\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Enable 5G
echo -e 'AT+QNWPREFCFG="mode_pref",AUTO\r' > /dev/ttyUSB2

# Check available bands
echo -e 'AT+QNWPREFCFG="nr5g_band"\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2
```

#### Issue: SIM Not Recognized

```bash
# Check SIM status
echo -e 'AT+CPIN?\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Check ICCID
echo -e 'AT+ICCID\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Check IMSI
echo -e 'AT+CIMI\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Verify SIM switch GPIO
cat /sys/class/gpio/gpio20/value
```

### 850L Issues

#### Issue: IoT Modem Offline

```bash
# Check modem status
echo -e 'AT+CFUN?\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5

# Reset modem
echo -e 'AT+CFUN=1,1\r' > /dev/ttyUSB5
sleep 5

# Check network registration
echo -e 'AT+CREG?\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5
```

#### Issue: High Data Usage on IoT SIM

```bash
# Check data usage
echo -e 'AT+QGDCNT=1\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5

# Verify only heartbeat traffic
tcpdump -i wwan1 -n

# Should only see traffic to remsim-server/ionmesh
```

## Performance Optimization

### FM350-GL Optimization

```bash
# Disable unnecessary services
echo -e 'AT+QGPS=0\r' > /dev/ttyUSB2  # Disable GPS if not needed

# Optimize for throughput
echo -e 'AT+QCFG="usbnet",0\r' > /dev/ttyUSB2  # QMI mode
echo -e 'AT+QCFG="data_interface",0,0\r' > /dev/ttyUSB2
```

### 850L Power Saving

```bash
# Enable power saving (for battery-powered setups)
echo -e 'AT+CPSMS=1,"","","00000111","00000000"\r' > /dev/ttyUSB5

# Reduce LED brightness (if applicable)
echo -e 'AT+QLEDMODE=0\r' > /dev/ttyUSB5
```

## Firmware Updates

### Check Firmware Version

```bash
# FM350-GL
echo -e 'AT+CGMR\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# 850L
echo -e 'AT+CGMR\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5
```

### Update Firmware

⚠️ **Warning**: Firmware updates should be done carefully. Contact Fibocom support for latest firmware.

```bash
# Firmware update typically requires:
# 1. Download firmware from Fibocom
# 2. Use Fibocom upgrade tool
# 3. Follow vendor-specific procedures

# DO NOT attempt manual firmware flashing without proper tools
```

## Reference

### Useful AT Commands

| Command | FM350-GL | 850L | Description |
|---------|----------|------|-------------|
| ATI | ✓ | ✓ | Modem information |
| AT+CGMR | ✓ | ✓ | Firmware version |
| AT+CPIN? | ✓ | ✓ | SIM PIN status |
| AT+COPS? | ✓ | ✓ | Operator selection |
| AT+CSQ | ✓ | ✓ | Signal quality |
| AT+QNWPREFCFG | ✓ | - | 5G network preference |
| AT+QENG | ✓ | ✓ | Network engineering mode |
| AT+CGDCONT | ✓ | ✓ | PDP context |
| AT+CFUN | ✓ | ✓ | Modem functionality |

### Vendor Resources

- **Fibocom Website**: https://www.fibocom.com/
- **FM350-GL Product Page**: https://www.fibocom.com/en/product/detail/23.html
- **850L Product Page**: https://www.fibocom.com/en/product/detail/59.html
- **Technical Support**: support@fibocom.com

## Related Documentation

- [Dual-Modem Setup Guide](DUAL-MODEM-SETUP.md)
- [OpenWRT Integration Guide](OPENWRT-INTEGRATION.md)
- [LuCI Web Interface Guide](LUCI-WEB-INTERFACE.md)
