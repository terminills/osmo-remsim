# Dual-Modem OpenWRT Configuration for Remote SIM

## Overview

Many OpenWRT routers have **2 modems** for redundancy and high availability. For remote SIM (remsim) deployments, we use a specific dual-modem architecture:

- **Modem 1**: Primary modem using remote SIM via remsim (vSIM/SWSIM)
- **Modem 2**: Always-on IoT modem with local physical SIM for remsim connectivity

## Why Dual-Modem?

### The Heartbeat Problem

Remote SIM (vSIM) deployments face a critical chicken-and-egg problem:

```
┌─────────────────────────────────────────────────────────┐
│                    THE PROBLEM                           │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Router needs network connection                        │
│         ↓                                                │
│  To maintain remsim heartbeat                           │
│         ↓                                                │
│  To keep vSIM active                                     │
│         ↓                                                │
│  To have network connection  ← CATCH-22!                │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

If the router loses connectivity temporarily:
1. ❌ Heartbeat to remsim-server stops
2. ❌ Server marks vSIM as inactive/dead
3. ❌ vSIM stops working
4. ❌ Router has no way to restore connection
5. ❌ **DEADLOCK** - Manual intervention required

### The Solution: Always-On IoT Modem

```
┌──────────────────────────────────────────────────────────┐
│                   DUAL-MODEM SOLUTION                     │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────┐                  ┌──────────────┐      │
│  │  Modem 1    │                  │   Modem 2    │      │
│  │  (Primary)  │                  │ (Always-On)  │      │
│  │             │                  │              │      │
│  │  Remote SIM │                  │  Local IoT   │      │
│  │  via remsim │                  │  SIM Card    │      │
│  │  (vSIM)     │                  │              │      │
│  └─────────────┘                  └──────────────┘      │
│         │                                 │              │
│         │ Data traffic                    │              │
│         │ (primary connectivity)          │              │
│         │                                 │              │
│         │                            Heartbeat to        │
│         │                            remsim-server       │
│         │                            (keeps vSIM alive)  │
│         │                                 │              │
│         └─────────────────────────────────┘              │
│                                                           │
│  Result: vSIM stays active even if primary loses signal! │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

**Key Benefits:**
✅ Continuous heartbeat to remsim-server via IoT modem
✅ vSIM remains active even if primary modem disconnects
✅ Automatic failover and recovery
✅ No manual intervention needed
✅ Cost-effective (IoT SIMs are cheap, low data usage)

## Hardware Architecture

### Typical Dual-Modem Router Layout

**Reference Configuration: Fibocom FM350-GL + Fibocom 850L**

```
┌────────────────────────────────────────────────────┐
│              OpenWRT Router                        │
│                                                    │
│  ┌─────────────────────────────────────────────┐  │
│  │             CPU / SoC                       │  │
│  └──┬──────────────────────────────────────┬───┘  │
│     │                                      │      │
│     │ USB/PCIe                    USB      │      │
│     │                                      │      │
│  ┌──▼──────────────┐              ┌────────▼───┐  │
│  │  Modem 1        │              │  Modem 2   │  │
│  │  Fibocom        │              │  Fibocom   │  │
│  │  FM350-GL       │              │  850L      │  │
│  │  (5G)           │              │  (LTE)     │  │
│  │                 │              │            │  │
│  │  /dev/ttyUSB2   │              │ /dev/ttyUSB5│ │
│  │  /dev/cdc-wdm0  │              │/dev/cdc-wdm1││
│  │  2cb7:0a05      │              │ 2cb7:01a0  │  │
│  └────┬────────────┘              └──────┬──────┘  │
│       │                                  │         │
│    GPIO 20/21                        GPIO 22/23    │
│       │                                  │         │
│  ┌────▼────────────┐              ┌─────▼───────┐  │
│  │  SIM Switch 1   │              │ SIM Switch 2│  │
│  │  (ADG3304)      │              │ (Fixed)     │  │
│  └────┬────────────┘              └─────┬───────┘  │
│       │                                  │         │
│   ┌───┴────┐                        ┌───┴───┐     │
│   │ Local  │ Remote                 │ Local │     │
│   │  SIM   │  SIM                   │  IoT  │     │
│   │  Slot  │ (vSIM)                 │  SIM  │     │
│   └────────┘                        └───────┘     │
│                                                    │
└────────────────────────────────────────────────────┘
```

**Modem Specifications:**
- **FM350-GL**: 5G Sub-6GHz, USB 3.1, up to 4.67 Gbps
- **850L**: LTE Cat-4, USB 2.0, up to 150 Mbps
- See [FIBOCOM-MODEM-CONFIG.md](FIBOCOM-MODEM-CONFIG.md) for detailed setup

### GPIO Pin Mapping

| Component | GPIO Pin | Function |
|-----------|----------|----------|
| Modem 1 SIM Switch | 20 | 0=Local, 1=Remote (vSIM) |
| Modem 1 Reset | 21 | Pulse high-low to reset |
| Modem 2 SIM Switch | 22 | Always 0 (local IoT SIM) |
| Modem 2 Reset | 23 | Pulse high-low to reset |

## Configuration

### Environment Variables

Enable dual-modem mode using environment variables:

```bash
# Enable dual-modem mode
export OPENWRT_DUAL_MODEM=1

# Modem 1 (Primary/remsim) Configuration
export MODEM1_SIM_GPIO=20
export MODEM1_RESET_GPIO=21
export MODEM1_DEVICE=/dev/ttyUSB2

# Modem 2 (Always-on IoT) Configuration
export MODEM2_SIM_GPIO=22
export MODEM2_RESET_GPIO=23
export MODEM2_DEVICE=/dev/ttyUSB5
```

### Complete Configuration Script

```bash
#!/bin/sh
# /etc/remsim/dual-modem-config.sh

# Dual-modem setup
export OPENWRT_DUAL_MODEM=1

# Modem 1: Primary remsim modem
export MODEM1_SIM_GPIO=20
export MODEM1_RESET_GPIO=21
export MODEM1_DEVICE=/dev/ttyUSB2

# Modem 2: Always-on IoT modem for heartbeat
export MODEM2_SIM_GPIO=22
export MODEM2_RESET_GPIO=23
export MODEM2_DEVICE=/dev/ttyUSB5

# IonMesh orchestration
export IONMESH_HOST=ionmesh.example.com
export IONMESH_PORT=5000
export IONMESH_TENANT_ID=1
export IONMESH_MAPPING_MODE=KI_PROXY_SWSIM

# Run remsim client
osmo-remsim-client-openwrt \
  -e /etc/remsim/ionmesh-event-script.sh \
  -d DMAIN:DPCU
```

## Network Routing Configuration

### Route Remsim Traffic Through IoT Modem

To ensure remsim heartbeat traffic uses the always-on IoT modem:

```bash
#!/bin/sh
# /etc/remsim/setup-routing.sh

# Get IoT modem interface (typically wwan1 for second modem)
IOT_INTERFACE="wwan1"
IOT_GATEWAY=$(ip route | grep "default.*${IOT_INTERFACE}" | awk '{print $3}')

# Remsim server addresses
REMSIM_SERVER="ionmesh.example.com"
BANKD_SERVER="bankd1.example.com"

# Add static routes for remsim traffic through IoT modem
ip route add $(host -t A ${REMSIM_SERVER} | awk '{print $4}') via ${IOT_GATEWAY} dev ${IOT_INTERFACE}
ip route add $(host -t A ${BANKD_SERVER} | awk '{print $4}') via ${IOT_GATEWAY} dev ${IOT_INTERFACE}

echo "Remsim traffic routed through IoT modem (${IOT_INTERFACE})"
```

### Policy-Based Routing

For more advanced setups, use policy-based routing:

```bash
# /etc/config/network

config interface 'modem1'
    option device 'wwan0'
    option proto 'dhcp'
    option metric '100'  # Higher priority

config interface 'modem2'
    option device 'wwan1'
    option proto 'dhcp'
    option metric '200'  # Lower priority (backup)

# Create routing table for remsim traffic
config rule
    option priority '100'
    option dest '192.168.100.0/24'  # Remsim server subnet
    option lookup '10'

config route
    option interface 'modem2'
    option target '192.168.100.0'
    option netmask '255.255.255.0'
    option table '10'
```

## Modem-Specific Setup

### Fibocom FM350-GL + 850L (Recommended Configuration)

```bash
# Check modem presence
lsusb | grep -i fibocom
# Expected:
# Bus 001 Device 003: ID 2cb7:0a05 Fibocom Wireless Inc. FM350-GL
# Bus 001 Device 004: ID 2cb7:01a0 Fibocom Wireless Inc. 850L

ls -la /dev/ttyUSB*
# Should see: ttyUSB0-3 (FM350-GL), ttyUSB4-6 (850L)

# FM350-GL: Configure for remote SIM
echo "AT+GTUSBMODE=7" > /dev/ttyUSB2  # Enable QMI mode

# 850L: Configure for always-on IoT
echo "AT+CFUN=1" > /dev/ttyUSB5  # Enable radio
echo "AT+CGDCONT=1,\"IP\",\"iot\"" > /dev/ttyUSB5  # Set IoT APN
```

**See [FIBOCOM-MODEM-CONFIG.md](FIBOCOM-MODEM-CONFIG.md) for complete Fibocom setup guide.**

### Quectel EC25/EC20 Modems (Alternative)

```bash
# Check modem presence
ls -la /dev/ttyUSB*
# Should see: ttyUSB0-3 (modem1), ttyUSB4-7 (modem2)

# Modem 1: Configure for remote SIM
echo "AT+QCFG=\"usbnet\",0" > /dev/ttyUSB2  # Enable QMI mode

# Modem 2: Configure for always-on
echo "AT+QCFG=\"usbnet\",0" > /dev/ttyUSB5
echo "AT+CFUN=1" > /dev/ttyUSB5  # Enable radio
```

### Sierra Wireless MC7455 (Alternative)

```bash
# Enable QMI interface
echo 'AT!ENTERCND="A710"' > /dev/ttyUSB2
echo 'AT!USBCOMP=1,1,0000100D' > /dev/ttyUSB2
```

### Huawei ME909s (Alternative)

```bash
# Set to NCM mode
echo 'AT^SETPORT="FF;1,2,3,4,5,7"' > /dev/ttyUSB0
```

## IoT SIM Requirements

### Recommended IoT SIM Specs

For the always-on IoT modem, use a SIM with:

| Requirement | Specification |
|-------------|---------------|
| **Data Plan** | 10-50 MB/month minimum |
| **Coverage** | Same as primary modem coverage area |
| **Roaming** | Enabled if router is mobile |
| **APN** | Standard data APN (not restricted) |
| **Type** | M2M/IoT SIM (cost-optimized) |
| **Contract** | Prepaid or postpaid with overage protection |

### Data Usage Estimates

**Heartbeat traffic only:**
- Heartbeat interval: 60 seconds
- Payload size: ~200 bytes per heartbeat
- Monthly usage: ~500 KB/month

**With registration and status updates:**
- Total monthly: ~2-5 MB/month

**Recommended plan:** 10 MB/month with overage protection

### Recommended IoT SIM Providers

- **Hologram**: Global M2M SIM, pay-as-you-go
- **1NCE**: 10 years, 500 MB included
- **Twilio Super SIM**: Multi-carrier, developer-friendly
- **Soracom**: Flexible IoT connectivity
- **BICS**: Enterprise M2M solutions

## Failover Behavior

### Primary Modem Failure Scenarios

#### Scenario 1: Primary Loses Signal

```
Time: 0s
- Primary modem (remsim): 🔴 No signal
- IoT modem: ✅ Connected
- Result: vSIM stays active via IoT heartbeat

Time: 60s
- Primary modem: 🔴 Still no signal
- IoT modem: ✅ Heartbeat sent successfully
- Result: vSIM remains active

Time: 300s
- Primary modem: ✅ Signal restored
- IoT modem: ✅ Still connected
- Result: Traffic automatically resumes on primary
```

#### Scenario 2: IoT Modem Fails

```
Time: 0s
- Primary modem: ✅ Connected
- IoT modem: 🔴 Failed
- Result: Primary maintains heartbeat (fallback)

Time: 60s
- Automatic attempt to restore IoT modem
- GPIO reset triggered on modem 2

Time: 120s
- IoT modem: ✅ Recovered
- Result: Heartbeat routing returns to IoT modem
```

#### Scenario 3: Both Modems Fail

```
Time: 0s
- Primary: 🔴 Failed
- IoT: 🔴 Failed
- Result: vSIM enters grace period (~5 minutes)

Time: 180s
- Automatic modem resets triggered
- Client attempts reconnection

Time: 300s (grace period expires)
- If still disconnected: vSIM deactivated by server
- Manual intervention or auto-recovery script required
```

## Testing and Validation

### Test Dual-Modem Setup

```bash
# 1. Verify both modems are detected
ls -la /dev/ttyUSB* /dev/cdc-wdm*

# 2. Check GPIO configuration
cat /sys/class/gpio/gpio20/value  # Modem 1 SIM switch
cat /sys/class/gpio/gpio22/value  # Modem 2 SIM switch (should be 0)

# 3. Test modem connectivity
# Modem 1
echo "ATI" > /dev/ttyUSB2
cat /dev/ttyUSB2

# Modem 2
echo "ATI" > /dev/ttyUSB5
cat /dev/ttyUSB5

# 4. Verify network interfaces
ip link show | grep wwan

# 5. Check routing
ip route show
ip route get <remsim-server-ip>
```

### Test Heartbeat Routing

```bash
# Monitor heartbeat traffic
tcpdump -i wwan1 host ionmesh.example.com

# Should see regular POST requests to /api/backend/v1/remsim/heartbeat
```

### Simulate Primary Modem Failure

```bash
# Disable primary modem interface
ifconfig wwan0 down

# Wait 60 seconds and check logs
logread | grep remsim

# Expected: Heartbeat continues via IoT modem
# vSIM remains active

# Re-enable primary modem
ifconfig wwan0 up

# Verify traffic resumes on primary
```

## Troubleshooting

### Problem: IoT Modem Not Detected

```bash
# Check USB devices
lsusb

# Check kernel messages
dmesg | grep -i modem

# Verify USB power
echo "1-1" > /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-1" > /sys/bus/usb/drivers/usb/bind
```

### Problem: Heartbeat Not Using IoT Modem

```bash
# Check routing table
ip route show table all | grep remsim

# Verify source address
curl -v http://ionmesh.example.com:5000/api/backend/v1/remsim/discover

# Fix routing
source /etc/remsim/setup-routing.sh
```

### Problem: vSIM Deactivated Despite IoT Modem

```bash
# Check IoT modem connectivity
ping -I wwan1 8.8.8.8

# Verify remsim-server is reachable
curl -I http://ionmesh.example.com:5000

# Check client logs
logread -f | grep -E "remsim|heartbeat|ionmesh"

# Manually send heartbeat
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/remsim/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"client_id":"test-router","status":"active"}'
```

### Problem: High IoT Data Usage

```bash
# Monitor traffic on IoT modem
iftop -i wwan1

# Check for unexpected traffic
tcpdump -i wwan1 -w /tmp/capture.pcap

# Verify only heartbeat traffic
tcpdump -i wwan1 -A | grep -E "POST|heartbeat"
```

## Production Deployment Checklist

- [ ] Both modems detected and configured
- [ ] GPIO pins correctly mapped
- [ ] IoT SIM installed in modem 2 with active data plan
- [ ] IoT modem locked to local SIM (GPIO 22 = 0)
- [ ] Primary modem configured for remote SIM switching
- [ ] Network routing configured (remsim via IoT modem)
- [ ] Heartbeat traffic verified on IoT modem
- [ ] Failover tested (primary modem disconnected)
- [ ] Grace period configured appropriately (300s minimum)
- [ ] Monitoring and alerting configured
- [ ] Auto-recovery scripts in place
- [ ] IoT SIM data usage alerts configured

## Advanced: Load Balancing

For high-traffic scenarios, use both modems for data:

```bash
# /etc/config/mwan3

config interface 'modem1'
    option enabled '1'
    option family 'ipv4'
    option track_method 'ping'
    option track_ip '8.8.8.8'
    option weight '3'  # 75% of traffic

config interface 'modem2'
    option enabled '1'
    option family 'ipv4'
    option track_method 'ping'
    option track_ip '8.8.4.4'
    option weight '1'  # 25% of traffic

config rule 'remsim_traffic'
    option src_ip '0.0.0.0/0'
    option dest_ip '192.168.100.0/24'  # Remsim server
    option use_policy 'modem2_only'  # Force remsim via IoT
```

## Cost Analysis

### Monthly Costs (per router)

| Component | Cost |
|-----------|------|
| IoT SIM (10 MB) | $2-5/month |
| Primary vSIM (via remsim) | $0 (included in remsim) |
| **Total additional cost** | **$2-5/month** |

**ROI:**
- Eliminates manual intervention: ~$50/incident
- Prevents vSIM downtime: ~$100/hour
- Break-even: First prevented outage pays for 10+ months

## Related Documentation

- [OpenWRT Integration Guide](OPENWRT-INTEGRATION.md)
- [IonMesh Orchestrator Integration](IONMESH-INTEGRATION.md)
- [RSPRO Protocol Specification](https://osmocom.org/projects/osmo-remsim/wiki)
