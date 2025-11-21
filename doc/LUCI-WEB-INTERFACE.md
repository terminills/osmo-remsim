## LuCI Web Interface for osmo-remsim-client

## Overview

The LuCI web interface provides a user-friendly, password-protected configuration and monitoring interface for osmo-remsim-client-openwrt. It eliminates the need for SSH access and command-line configuration, making it easy to manage remote SIM settings through the OpenWRT web interface.

## Features

✅ **Password Protected**: Secured by OpenWRT's built-in authentication system
✅ **Configuration Management**: Web-based configuration of all remsim settings
✅ **Real-Time Status**: Monitor service status, modem connectivity, and IonMesh connection
✅ **Dual-Modem Support**: Easy configuration of dual-modem setups
✅ **IonMesh Integration**: Configure orchestrator settings through the web UI
✅ **Modem Detection**: Automatic detection and display of connected modems
✅ **Service Control**: Start, stop, and restart remsim service from the web interface
✅ **Connection Testing**: Built-in connectivity test functionality

## Installation

### Prerequisites

```bash
# Install LuCI if not already present
opkg update
opkg install luci luci-ssl

# Install remsim client
opkg install osmo-remsim-client-openwrt
```

### Install LuCI App

```bash
# Copy LuCI app package to router
scp -r luci-app-remsim root@router:/tmp/

# Install the package
cd /tmp
opkg install luci-app-remsim_*.ipk

# Restart web server
/etc/init.d/uhttpd restart
```

## Accessing the Interface

### Default Access

1. Open web browser and navigate to router IP:
   - `http://192.168.1.1` (or your router's IP)
   - For HTTPS: `https://192.168.1.1`

2. Log in with router credentials:
   - Username: `root`
   - Password: (your router password)

3. Navigate to:
   - **Services** → **Remote SIM**

### Menu Structure

```
Services
└── Remote SIM
    ├── Configuration     (Basic settings)
    ├── Status           (Real-time monitoring)
    ├── Modems           (Hardware configuration)
    └── Advanced         (IonMesh & advanced options)
```

## Configuration Pages

### 1. Configuration Page

**Path**: Services → Remote SIM → Configuration

#### Service Control
- **Enable Service**: Checkbox to enable/disable remsim client on boot
  - Default: Disabled
  - Changes take effect after restart

#### Client Configuration
- **Client ID**: Unique identifier (0-1023)
  - Leave empty for auto-generation from hostname
  - Example: `42` or leave blank for `router1-slot0`
  
- **Client Slot**: Slot number (0-1023)
  - Default: `0`
  - Used when IonMesh is disabled

#### Server Configuration
- **Server Host**: remsim-server hostname or IP
  - Example: `remsim.example.com` or `192.168.100.10`
  - Note: Overridden by IonMesh when enabled
  
- **Server Port**: TCP port for remsim-server
  - Default: `9998`
  
- **Default ATR**: Answer-To-Reset in hex (optional)
  - Example: `3B9F95801FC78031E073FE211B66D00090004831`
  - Leave empty for default (`3B00`)
  
- **Ignore RSPRO ATR**: Checkbox to use only configured ATR
  - Default: Disabled (use ATR from bankd)

### 2. Status Page

**Path**: Services → Remote SIM → Status

Real-time monitoring dashboard showing:

#### Service Status Card
- **Status**: Running (green) or Stopped (red)
- **Process ID**: PID of running service
- **Autostart**: Whether service starts on boot
- **Action Buttons**:
  - Restart Service
  - Test Connection

#### Client Information Card
- **Client ID**: Current client identifier
- **Client Slot**: Assigned slot number
- **Mapping Mode**: Current SIM mapping mode
- **Dual-Modem Mode**: Enabled/Disabled

#### IonMesh Orchestration Card
(Only shown when IonMesh is enabled)
- **Status**: Connected (green) or Unreachable (yellow)
- **Host**: IonMesh server address and port

#### Modem Status Card

**Single Modem Mode:**
- Device path
- Present: Yes/No with indicator
- Modem information from AT commands

**Dual-Modem Mode:**
- **Modem 1 (Primary/Remote SIM)**
  - Device, presence, and information
- **Modem 2 (Always-On IoT)**
  - Device, presence, and information
  
### 3. Modems Page

**Path**: Services → Remote SIM → Modems

#### Modem Mode Selection
- **Enable Dual-Modem Mode**: Checkbox
  - Unchecked: Single modem mode
  - Checked: Dual-modem mode (recommended)

#### Single Modem Settings
(Shown when dual-modem is disabled)

- **Modem Device**: Path to modem device
  - Example: `/dev/ttyUSB2` or `/dev/cdc-wdm0`
  - Leave empty for auto-detection
  
- **SIM Switch GPIO**: GPIO pin number for SIM switching
  - Default: `20`
  - 0 = local SIM, 1 = remote vSIM
  
- **Reset GPIO**: GPIO pin for modem reset
  - Default: `21`

#### Modem 1 - Primary (Remote SIM)
(Shown when dual-modem is enabled)

- **Device Path**: Primary modem device
  - Default: `/dev/ttyUSB2`
  
- **SIM Switch GPIO**: GPIO for modem 1
  - Default: `20`
  
- **Reset GPIO**: Reset pin for modem 1
  - Default: `21`

#### Modem 2 - Always-On IoT SIM
(Shown when dual-modem is enabled)

- **Device Path**: IoT modem device
  - Default: `/dev/ttyUSB5`
  
- **SIM Switch GPIO**: GPIO for modem 2
  - Default: `22`
  
- **Reset GPIO**: Reset pin for modem 2
  - Default: `23`

**⚠️ Important Note**: Displays warning that modem 2 requires a local IoT SIM for always-on connectivity.

### 4. Advanced Page

**Path**: Services → Remote SIM → Advanced

#### IonMesh Orchestration
- **Enable IonMesh**: Checkbox for orchestrator support
  - When enabled, shows additional fields:
  
- **IonMesh Host**: Orchestrator hostname
  - Example: `ionmesh.example.com`
  
- **IonMesh Port**: API port
  - Default: `5000`
  
- **Tenant ID**: Multi-tenancy identifier
  - Default: `1`
  
- **Mapping Mode**: Dropdown selection
  - `One-to-One Software SIM`
  - `One-to-One Virtual SIM`
  - `KI Proxy Software SIM` (recommended)
  
- **MCC/MNC**: Mobile Country/Network Code (optional)
  - Example: `310410` for AT&T USA
  - Leave empty for any carrier

#### Logging and Debug
- **Enable Debug Logging**: Verbose output
  - Warning: Increases log size
  
- **Log Categories**: Debug categories when enabled
  - Example: `DMAIN:DPCU:DST2`
  
- **Log to Syslog**: Send logs to system log
  - Default: Enabled

#### Network Routing
(Shown in dual-modem mode)

- **Force IoT Modem for Heartbeat**: Route heartbeat via modem 2
  - Default: Enabled
  - Recommended: Keep enabled
  
- **IoT Modem Interface**: Network interface name
  - Default: `wwan1`

#### Event Handling
- **Event Script Path**: Custom event handler
  - Default: `/etc/remsim/event-script.sh`
  
- **Keep Running on Error**: Don't exit on connection failure
  - Default: Enabled

#### Heartbeat Configuration
- **Heartbeat Interval**: Time between heartbeats (seconds)
  - Range: 10-300
  - Default: `60`
  
- **Connection Timeout**: Max wait time (seconds)
  - Range: 5-60
  - Default: `10`

#### Security Settings
- **Use TLS/SSL**: Encrypt connections
  - Default: Disabled
  - When enabled, shows certificate fields:
  
- **CA Certificate Path**: CA cert for verification
  - Default: `/etc/ssl/certs/ca-certificates.crt`
  
- **Client Certificate**: Path to client cert
- **Client Private Key**: Path to private key

## Common Configuration Scenarios

### Scenario 1: Basic Single Modem Setup

1. Go to **Configuration**
   - Enable Service: ✓
   - Client Slot: `0`
   - Server Host: `remsim.example.com`
   - Server Port: `9998`

2. Go to **Modems**
   - Dual-Modem Mode: ☐ (unchecked)
   - Modem Device: `/dev/ttyUSB2`
   - SIM Switch GPIO: `20`
   - Reset GPIO: `21`

3. Click **Save & Apply**
4. Go to **Status** and click **Restart Service**

### Scenario 2: Dual-Modem with IonMesh

1. Go to **Configuration**
   - Enable Service: ✓
   - (Server settings will be auto-configured)

2. Go to **Modems**
   - Enable Dual-Modem Mode: ✓
   - Modem 1 Device: `/dev/ttyUSB2`
   - Modem 1 SIM GPIO: `20`
   - Modem 1 Reset GPIO: `21`
   - Modem 2 Device: `/dev/ttyUSB5`
   - Modem 2 SIM GPIO: `22`
   - Modem 2 Reset GPIO: `23`

3. Go to **Advanced**
   - Enable IonMesh: ✓
   - IonMesh Host: `ionmesh.example.com`
   - IonMesh Port: `5000`
   - Tenant ID: `1`
   - Mapping Mode: `KI Proxy Software SIM`
   - MCC/MNC: `310410` (if specific carrier)
   
4. **Save & Apply** on each page
5. Go to **Status** → **Restart Service**
6. Verify **IonMesh Status** shows "Connected"

### Scenario 3: High-Security Setup with TLS

1. Configure basic settings (Scenario 1 or 2)

2. Go to **Advanced** → **Security Settings**
   - Use TLS/SSL: ✓
   - CA Certificate Path: `/etc/ssl/certs/ca-certificates.crt`
   - Client Certificate: `/etc/remsim/client.crt`
   - Client Private Key: `/etc/remsim/client.key`

3. Upload certificates via SSH:
   ```bash
   scp client.crt root@router:/etc/remsim/
   scp client.key root@router:/etc/remsim/
   chmod 600 /etc/remsim/client.key
   ```

4. **Save & Apply** and restart service

## Monitoring and Troubleshooting

### Status Indicators

| Indicator | Meaning |
|-----------|---------|
| 🟢 Green dot | Running / Connected |
| 🔴 Red dot | Stopped / Disconnected |
| 🟡 Yellow dot | Warning / Unreachable |

### Test Connection Button

Click **Test Connection** on the Status page to:
- Check connectivity to remsim-server or IonMesh
- Verify modem responses
- Test network routing

Results appear in a popup dialog.

### Reading Logs

Access logs via LuCI:
1. Navigate to **Status** → **System Log**
2. Filter for "remsim":
   ```
   [remsim] IonMesh orchestration enabled
   [remsim] Successfully registered with IonMesh
   [remsim] Modem 1 device: /dev/ttyUSB2
   ```

Or via SSH:
```bash
logread | grep remsim
logread -f | grep remsim  # Live tail
```

### Common Issues

#### Issue: Service Won't Start

**Check**:
1. Status page → Service status shows "Stopped"
2. System Log for error messages

**Fix**:
1. Verify modems are connected: Check Modem Status cards
2. Check server/IonMesh connectivity
3. Review configuration for typos
4. Ensure GPIO pins don't conflict

#### Issue: Modem Not Detected

**Check**:
1. Modems page → Status shows device not present

**Fix**:
1. SSH into router: `ls -la /dev/ttyUSB* /dev/cdc-wdm*`
2. Update device path in Modems page
3. Check USB connections
4. Try different USB ports

#### Issue: IonMesh Unreachable

**Check**:
1. Status page → IonMesh Status shows "Unreachable"

**Fix**:
1. Verify IonMesh host address
2. Check network connectivity: `ping ionmesh.example.com`
3. Verify IonMesh port is correct (default 5000)
4. Check firewall rules
5. Ensure IoT modem (if dual-modem) is connected

#### Issue: vSIM Keeps Deactivating

**Check**:
1. Status page → verify service is running
2. Advanced page → check heartbeat interval

**Fix**:
1. Enable dual-modem mode
2. Ensure modem 2 has IoT SIM installed
3. Enable "Force IoT Modem for Heartbeat"
4. Reduce heartbeat interval if network is unstable
5. Check IoT SIM has active data plan

## Security Best Practices

### Password Protection

The LuCI interface is automatically protected by OpenWRT's authentication system:

1. **Change Default Password**
   ```
   System → Administration → Router Password
   ```

2. **Enable HTTPS**
   ```bash
   opkg install luci-ssl
   /etc/init.d/uhttpd restart
   ```
   Access via: `https://192.168.1.1`

3. **Restrict Access by IP**
   Edit `/etc/config/uhttpd`:
   ```
   option listen_http '192.168.1.1:80'
   option listen_https '192.168.1.1:443'
   ```

4. **Use Strong Passwords**
   - Minimum 12 characters
   - Mix of upper/lower case, numbers, symbols
   - Change regularly

### Configuration Backup

Backup your configuration:

1. **Via LuCI**:
   - System → Backup / Flash Firmware
   - Generate archive
   - Download backup

2. **Via SSH**:
   ```bash
   sysupgrade -b /tmp/backup.tar.gz
   scp root@router:/tmp/backup.tar.gz ./
   ```

Configuration is stored in `/etc/config/remsim`.

### Firewall Considerations

If using IonMesh or remote remsim-server:

1. Allow outbound connections:
   ```
   Network → Firewall → Traffic Rules
   ```
   
2. Add rule for remsim traffic:
   - Name: `Allow remsim`
   - Protocol: TCP
   - Destination port: 9998 (server), 5000 (IonMesh)
   - Action: ACCEPT

## Advanced Tips

### Auto-Refresh Status Page

Add to browser bookmarks with JavaScript:
```javascript
javascript:(function(){setInterval(function(){window.location.reload();},30000);})();
```

Refreshes status page every 30 seconds.

### Custom Event Scripts

Configure custom event handling:

1. Create script: `/etc/remsim/custom-events.sh`
2. Add logic for events:
   ```bash
   #!/bin/sh
   case "$1" in
     request-card-insert)
       logger "Custom: vSIM activation requested"
       # Custom actions here
       ;;
   esac
   ```
3. Set in Advanced page:
   - Event Script Path: `/etc/remsim/custom-events.sh`

### Integration with Other Services

Forward status to monitoring system:

```bash
# /etc/remsim/status-webhook.sh
#!/bin/sh

STATUS=$(ubus call service list '{"name":"remsim"}')
curl -X POST https://monitor.example.com/webhook \
  -H "Content-Type: application/json" \
  -d "{\"router\":\"$(uci get system.@system[0].hostname)\",\"status\":$STATUS}"
```

Add to cron:
```bash
*/5 * * * * /etc/remsim/status-webhook.sh
```

## Mobile Access

Access LuCI from mobile devices:

1. **Responsive Design**: LuCI automatically adapts to mobile screens
2. **Mobile App**: Use OpenWRT mobile app (if available)
3. **VPN Access**: Access from anywhere via VPN:
   ```
   Services → OpenVPN / WireGuard
   ```

## API Access (Advanced)

For programmatic access, use UCI commands via SSH:

```bash
# Get current config
uci show remsim

# Update settings
uci set remsim.ionmesh.enabled=1
uci set remsim.ionmesh.host=ionmesh.example.com
uci commit remsim

# Restart service
/etc/init.d/remsim restart
```

Or use LuCI RPC:
```bash
curl -X POST http://router/cgi-bin/luci/admin/services/remsim/action_restart \
  --cookie "sysauth=$AUTH_TOKEN"
```

## Troubleshooting LuCI Installation

### Issue: Menu Not Appearing

```bash
# Clear LuCI cache
rm -rf /tmp/luci-*

# Rebuild indexes
/etc/init.d/uhttpd restart

# Check installation
opkg list-installed | grep luci-app-remsim
```

### Issue: Permission Denied

```bash
# Fix permissions
chmod 755 /usr/lib/lua/luci/controller/remsim.lua
chmod 644 /etc/config/remsim
```

### Issue: Configuration Not Saving

```bash
# Check UCI lock
rm -f /var/lock/uci.lock

# Verify config syntax
uci show remsim
```

## Future Enhancements

Planned features for future versions:

- [ ] Graphical network topology view
- [ ] Historical statistics and graphs
- [ ] Email/SMS alerts for connectivity issues
- [ ] One-click firmware updates
- [ ] Multi-language support
- [ ] Mobile app integration
- [ ] Batch configuration for multiple routers

## Support and Documentation

- **OpenWRT Forum**: https://forum.openwrt.org
- **LuCI Documentation**: https://openwrt.org/docs/guide-user/luci/luci.essentials
- **osmo-remsim Wiki**: https://osmocom.org/projects/osmo-remsim/wiki
- **Issue Tracker**: https://github.com/terminills/osmo-remsim/issues

## Related Documentation

- [OpenWRT Integration Guide](OPENWRT-INTEGRATION.md)
- [Dual-Modem Setup Guide](DUAL-MODEM-SETUP.md)
- [IonMesh Orchestrator Integration](IONMESH-INTEGRATION.md)
