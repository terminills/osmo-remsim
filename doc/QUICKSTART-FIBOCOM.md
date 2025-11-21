# Quick Start Guide: Fibocom FM350-GL + 850L Setup

## Overview

This guide will get you up and running with osmo-remsim-client on an OpenWRT router with:
- **Fibocom FM350-GL** (Primary 5G modem for data)
- **Fibocom 850L** (IoT LTE modem for always-on connectivity)

**Setup Time**: ~15 minutes

## Prerequisites

- OpenWRT router with 2x USB ports (or M.2/mPCIe slots)
- Fibocom FM350-GL modem installed
- Fibocom 850L modem installed
- IoT SIM card installed in 850L (with active data plan)
- SSH access to router
- Internet connection

## Step 1: Install Required Packages

```bash
# SSH into your router
ssh root@192.168.1.1

# Update package list
opkg update

# Install modem drivers
opkg install kmod-usb-net-qmi-wwan uqmi

# Install remsim client (if not already installed)
# opkg install osmo-remsim-client-openwrt

# Install LuCI web interface
opkg install luci-app-remsim

# Restart web server
/etc/init.d/uhttpd restart
```

## Step 2: Verify Modems Are Detected

```bash
# Check USB devices
lsusb | grep Fibocom

# Should see:
# Bus 001 Device 003: ID 2cb7:0a05 Fibocom Wireless Inc. FM350-GL
# Bus 001 Device 004: ID 2cb7:01a0 Fibocom Wireless Inc. 850L

# Check serial devices
ls -la /dev/ttyUSB* /dev/cdc-wdm*

# Should see:
# /dev/ttyUSB0-3 (FM350-GL)
# /dev/ttyUSB4-6 (850L)
# /dev/cdc-wdm0 (FM350-GL QMI)
# /dev/cdc-wdm1 (850L QMI)
```

## Step 3: Configure via LuCI Web Interface

### 3.1 Access LuCI

1. Open browser: `http://192.168.1.1`
2. Login with router credentials
3. Navigate to: **Services → Remote SIM**

### 3.2 Configure Modems

Go to **Modems** tab:

- ✓ **Enable Dual-Modem Mode**: Check this box

**Modem 1 (Primary/Remote SIM):**
- Device Path: `/dev/ttyUSB2`
- SIM Switch GPIO: `20`
- Reset GPIO: `21`

**Modem 2 (Always-On IoT):**
- Device Path: `/dev/ttyUSB5`
- SIM Switch GPIO: `22`
- Reset GPIO: `23`

Click **Save & Apply**

### 3.3 Configure IonMesh (Optional but Recommended)

Go to **Advanced** tab:

- ✓ **Enable IonMesh**: Check this box
- **IonMesh Host**: `ionmesh.example.com` (your IonMesh server)
- **IonMesh Port**: `5000`
- **Tenant ID**: `1` (or your tenant ID)
- **Mapping Mode**: `KI Proxy Software SIM`

Click **Save & Apply**

### 3.4 Enable Service

Go to **Configuration** tab:

- ✓ **Enable Service**: Check this box
- **Client Slot**: `0` (or as assigned)
- **Server Host**: (leave default if using IonMesh)
- **Server Port**: (leave default if using IonMesh)

Click **Save & Apply**

### 3.5 Start Service

Go to **Status** tab:

- Click **Restart Service**
- Wait 10 seconds
- Verify status shows "Running" (green indicator)

## Step 4: Verify Everything Works

### Check Service Status

On the **Status** page, you should see:

✅ **Service Status**: Running (green)
✅ **Client Information**: Shows client ID and slot
✅ **IonMesh Status**: Connected (if enabled)
✅ **Modem 1 Status**: Present (green)
✅ **Modem 2 Status**: Present (green)

### Test Connection

Click **Test Connection** button on Status page.

Expected result:
```
Connection Test Result:

✓ IonMesh server reachable
✓ FM350-GL modem responding
✓ 850L modem responding
✓ Network routing configured
```

### Check Logs

```bash
# Via SSH
logread | grep remsim

# Should see:
[remsim] IonMesh orchestration enabled
[remsim] Dual-modem mode enabled
[remsim] Successfully registered with IonMesh
[remsim] Modem 1 (remsim): /dev/ttyUSB2 (GPIO SIM:20 RST:21)
[remsim] Modem 2 (IoT): /dev/ttyUSB5 (GPIO SIM:22 RST:23)
[remsim] IoT modem set to use local SIM for always-on connectivity
```

## Step 5: Test SIM Switching

### Switch to Remote SIM

```bash
# Via command line
echo 1 > /sys/class/gpio/gpio20/value

# Or via event script
/etc/remsim/fibocom-event-script.sh request-card-insert

# Check FM350-GL recognizes new SIM
echo -e 'AT+CPIN?\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2

# Should show SIM ready
```

### Switch Back to Local SIM

```bash
echo 0 > /sys/class/gpio/gpio20/value

# Or via event script
/etc/remsim/fibocom-event-script.sh request-card-remove
```

## Step 6: Test Failover

### Simulate Primary Modem Failure

```bash
# Disable primary modem interface
ifconfig wwan0 down

# Wait 60 seconds
sleep 60

# Check that heartbeat continues via IoT modem
logread | grep heartbeat

# Should see successful heartbeats via wwan1
```

### Re-enable Primary Modem

```bash
ifconfig wwan0 up

# Verify traffic resumes on primary
```

## Common Issues and Fixes

### Issue: Modems Not Detected

**Check:**
```bash
lsusb
dmesg | grep -i fibocom
```

**Fix:**
```bash
# Reboot router
reboot

# Or reset USB bus
echo "1-1" > /sys/bus/usb/drivers/usb/unbind
sleep 2
echo "1-1" > /sys/bus/usb/drivers/usb/bind
```

### Issue: Service Won't Start

**Check logs:**
```bash
logread | grep -i error
```

**Fix:**
1. Verify GPIO pins don't conflict
2. Check server/IonMesh address is correct
3. Ensure both modems are detected
4. Review configuration in LuCI

### Issue: vSIM Not Working

**Check:**
```bash
# Verify remote SIM is selected
cat /sys/class/gpio/gpio20/value
# Should be: 1

# Check if modem detects SIM
echo -e 'AT+CPIN?\r' > /dev/ttyUSB2
timeout 1 cat /dev/ttyUSB2
```

**Fix:**
```bash
# Force SIM switch
echo 1 > /sys/class/gpio/gpio20/value

# Reset modem
echo -e 'AT+CFUN=1,1\r' > /dev/ttyUSB2
```

### Issue: IoT Modem Not Working

**Check:**
```bash
# Verify SIM is detected
echo -e 'AT+CPIN?\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5

# Check network registration
echo -e 'AT+CREG?\r' > /dev/ttyUSB5
timeout 1 cat /dev/ttyUSB5
```

**Fix:**
1. Verify IoT SIM card is properly inserted in 850L
2. Check IoT SIM has active data plan
3. Verify APN is configured correctly
4. Check signal strength

## Next Steps

### Production Deployment

1. **Configure Firewall Rules**
   - Allow outbound to remsim-server/IonMesh
   - Block unnecessary inbound traffic

2. **Enable Auto-Start**
   - Already configured if you checked "Enable Service"

3. **Setup Monitoring**
   ```bash
   # Add monitoring script
   vi /etc/cron.d/remsim-monitor
   
   # Add line:
   */5 * * * * /usr/bin/remsim-monitor.sh
   ```

4. **Configure Backup**
   - Backup configuration: System → Backup / Flash Firmware

5. **Document Settings**
   - Note GPIO pins used
   - Record IonMesh tenant ID
   - Save configuration backup

### Advanced Configuration

See detailed guides:
- [FIBOCOM-MODEM-CONFIG.md](FIBOCOM-MODEM-CONFIG.md) - Modem-specific settings
- [DUAL-MODEM-SETUP.md](DUAL-MODEM-SETUP.md) - Advanced dual-modem features
- [LUCI-WEB-INTERFACE.md](LUCI-WEB-INTERFACE.md) - Complete LuCI guide
- [IONMESH-INTEGRATION.md](IONMESH-INTEGRATION.md) - IonMesh orchestration

## Configuration Summary

Your working configuration:

```
┌──────────────────────────────────────────┐
│ Router: OpenWRT                          │
│                                          │
│ Modem 1: Fibocom FM350-GL (5G)          │
│   Device: /dev/ttyUSB2                   │
│   SIM Switch: GPIO 20                    │
│   Reset: GPIO 21                         │
│   Purpose: Primary data (remote vSIM)   │
│                                          │
│ Modem 2: Fibocom 850L (LTE)             │
│   Device: /dev/ttyUSB5                   │
│   SIM Switch: GPIO 22 (fixed to local)  │
│   Reset: GPIO 23                         │
│   Purpose: Always-on IoT connectivity   │
│                                          │
│ IonMesh: ionmesh.example.com:5000       │
│   Tenant: 1                              │
│   Mode: KI_PROXY_SWSIM                   │
│                                          │
│ Status: ✓ OPERATIONAL                    │
└──────────────────────────────────────────┘
```

## Support

- **Documentation**: See `/doc/` directory
- **Logs**: `logread | grep remsim`
- **Web Interface**: `http://192.168.1.1` → Services → Remote SIM
- **Issues**: https://github.com/terminills/osmo-remsim/issues

**Setup Complete!** Your router is now configured for remote SIM with automatic failover.
