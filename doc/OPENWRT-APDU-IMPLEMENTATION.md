# OpenWRT Client APDU Implementation

## Overview

This document describes the APDU (Application Protocol Data Unit) implementation for the OpenWRT remsim-client. The implementation enables bidirectional communication between the remote SIM card (via remsim-bankd) and the cellular modem on the OpenWRT router.

## Architecture

```
┌──────────────────┐         ┌─────────────────┐         ┌──────────────┐
│  Remote SIM Card │◄───────►│ remsim-bankd    │◄───────►│ remsim-server│
│  (via bankd)     │  RSPRO  │                 │  RSPRO  │              │
└──────────────────┘         └─────────────────┘         └──────────────┘
                                      ▲
                                      │ RSPRO/TPDU
                                      │
                                      ▼
                             ┌─────────────────┐
                             │ remsim-client   │
                             │ (OpenWRT)       │
                             └─────────────────┘
                                      ▲
                                      │ AT+CSIM
                                      │
                                      ▼
                             ┌─────────────────┐
                             │ Cellular Modem  │
                             │ (e.g. FM350-GL) │
                             └─────────────────┘
```

## Implementation Details

### APDU Flow

1. **Card-to-Modem (C-APDU)**:
   - Remote SIM card sends APDU via bankd → client
   - Client receives TPDU via `frontend_handle_card2modem()`
   - Client converts binary APDU to hex string
   - Client sends `AT+CSIM=<length>,"<hex_apdu>"` to modem
   - Modem forwards APDU to network

2. **Modem-to-Card (R-APDU)**:
   - Modem receives response from network
   - Modem sends `+CSIM: <length>,"<hex_response>"`
   - Client parses response via `modem_fd_cb()`
   - Client converts hex string to binary APDU
   - Client forwards APDU to bankd via `MF_E_MDM_TPDU` event

### Key Functions

#### `frontend_handle_card2modem()`
Handles APDUs received from the remote SIM card (via bankd) that need to be sent to the modem.

```c
int frontend_handle_card2modem(struct bankd_client *bc, const uint8_t *data, size_t len)
{
    struct openwrt_state *os = bc->data;
    
    LOGP(DMAIN, LOGL_DEBUG, "Card->Modem APDU: %s\n", osmo_hexdump(data, len));
    
    /* Forward the APDU to the modem via AT+CSIM command */
    return openwrt_send_tpdu_to_modem(os, data, len);
}
```

#### `openwrt_send_tpdu_to_modem()`
Sends an APDU to the modem using the AT+CSIM command.

```c
static int openwrt_send_tpdu_to_modem(struct openwrt_state *os, const uint8_t *data, size_t len)
{
    char *hex_data;
    char at_cmd[2048];
    
    /* Convert APDU to hex string */
    hex_data = bin_to_hex_str(data, len);
    
    /* Build AT+CSIM command */
    snprintf(at_cmd, sizeof(at_cmd), "AT+CSIM=%zu,\"%s\"\r\n", len * 2, hex_data);
    
    /* Write to modem device */
    rc = write(os->modem_ofd.fd, at_cmd, strlen(at_cmd));
    
    return 0;
}
```

#### `modem_fd_cb()`
Callback function that handles responses from the modem. Parses AT+CSIM responses and forwards them to bankd.

```c
static int modem_fd_cb(struct osmo_fd *ofd, unsigned int what)
{
    /* Read from modem */
    rc = read(ofd->fd, buf, sizeof(buf) - 1);
    
    /* Parse AT+CSIM response: +CSIM: <length>,"<response>" */
    if (sscanf(csim_start, "+CSIM: %d,\"%[^\"]\"", &resp_len, hex_resp) == 2) {
        parsed_len = hex_str_to_bin(hex_resp, apdu_resp, sizeof(apdu_resp));
        
        /* Forward APDU response to bankd */
        osmo_fsm_inst_dispatch(bc->main_fi, MF_E_MDM_TPDU, &ftpdu);
    }
    
    return 0;
}
```

### AT+CSIM Command Format

The AT+CSIM command is used for generic SIM access on Qualcomm and compatible modems:

**Command**: `AT+CSIM=<length>,"<command>"`
- `<length>`: Length of the command in characters (hex string length)
- `<command>`: Hex string representation of the APDU

**Response**: `+CSIM: <length>,"<response>"`
- `<length>`: Length of the response in characters (hex string length)
- `<response>`: Hex string representation of the response APDU

**Example**:
```
Command:  AT+CSIM=14,"00A40000023F00"
          (SELECT FILE command for MF)

Response: +CSIM: 4,"9000"
          (Status word: Success)
```

## Modem Device Configuration

### Device Detection

The client automatically detects common modem device paths:
- `/dev/ttyUSB2` - Primary AT command port (Fibocom FM350-GL)
- `/dev/ttyUSB5` - Primary AT command port (Fibocom 850L)
- `/dev/cdc-wdm0` - QMI interface (alternative)
- `/dev/cdc-wdm1` - QMI interface (alternative)

### Manual Configuration

Set the modem device via environment variable:
```bash
export MODEM1_DEVICE=/dev/ttyUSB2
export MODEM2_DEVICE=/dev/ttyUSB5  # For dual-modem setups
```

Or via USB path configuration in the client config file.

## ZBT-Z8102AX Router Support

The implementation includes automatic detection and configuration for the Zbtlink ZBT-Z8102AX router (MediaTek MT7981 chipset).

### GPIO Mappings

From the device tree source (DTS):
- **GPIO 6** (`sim1`): SIM slot 1 control
- **GPIO 7** (`sim2`): SIM slot 2 control
- **GPIO 4** (`5g1`): 5G modem 1 power control
- **GPIO 5** (`5g2`): 5G modem 2 power control
- **GPIO 3** (`pcie_power`): PCIe power control

### Auto-Detection

The client automatically detects the ZBT-Z8102AX router by reading:
- `/tmp/sysinfo/model`
- `/proc/device-tree/model`

When detected, it automatically applies the correct GPIO mappings.

### Manual Override

Override GPIO settings via environment variables:
```bash
export MODEM1_SIM_GPIO=6
export MODEM1_RESET_GPIO=4
export MODEM2_SIM_GPIO=7
export MODEM2_RESET_GPIO=5
```

## Dual-Modem Configuration

For setups with two modems (e.g., FM350-GL + 850L):

```bash
export OPENWRT_DUAL_MODEM=1
export MODEM1_DEVICE=/dev/ttyUSB2
export MODEM1_SIM_GPIO=6
export MODEM1_RESET_GPIO=4
export MODEM2_DEVICE=/dev/ttyUSB5
export MODEM2_SIM_GPIO=7
export MODEM2_RESET_GPIO=5
```

Modem 1 is used for remote SIM (remsim), while Modem 2 maintains always-on IoT connectivity.

## Debugging

### Enable Debug Logging

```bash
# Set log level to DEBUG
export OSMO_LOG_LEVEL=DEBUG

# Run client with verbose output
./osmo-remsim-client-openwrt -v -v -v
```

### Monitor AT Commands

```bash
# Monitor modem communication
cat /dev/ttyUSB2 &
echo -e "AT+CSIM=14,\"00A40000023F00\"\r" > /dev/ttyUSB2
```

### APDU Trace

The client logs all APDUs at DEBUG level:
```
Card->Modem APDU: 00 a4 00 00 02 3f 00
Sending AT command to modem: AT+CSIM=14,"00A40000023F00"
Modem response: +CSIM: 4,"9000"
Forwarding APDU response from modem: 90 00
```

## Limitations

1. **T=0 Protocol Only**: Currently supports only T=0 protocol APDUs
2. **Standard APDUs**: Extended APDUs not yet supported
3. **AT Command Interface**: Requires modem support for AT+CSIM
4. **QMI Alternative**: QMI interface support is planned but not yet implemented

## Future Enhancements

- [ ] QMI interface support for Qualcomm modems
- [ ] Extended APDU support
- [ ] T=1 protocol support
- [ ] Multiple concurrent APDU handling
- [ ] AT+CRSM support for restricted SIM access
- [ ] Response buffering for fragmented messages

## Testing

### Test APDU Conversion

A test program is provided to verify APDU conversion logic:

```c
// Test binary to hex and back
uint8_t apdu[] = {0x00, 0xA4, 0x00, 0x00, 0x02, 0x3F, 0x00};
char *hex = bin_to_hex_str(apdu, sizeof(apdu));
// hex = "00A40000023F00"

uint8_t result[64];
int len = hex_str_to_bin(hex, result, sizeof(result));
// len = 7, result = {0x00, 0xA4, 0x00, 0x00, 0x02, 0x3F, 0x00}
```

### Manual APDU Test

Send a SELECT FILE command to the modem:

```bash
# Prepare modem
echo -e "AT\r" > /dev/ttyUSB2

# Send SELECT MF APDU
echo -e "AT+CSIM=14,\"00A40000023F00\"\r" > /dev/ttyUSB2

# Read response
timeout 1 cat /dev/ttyUSB2
# Expected: +CSIM: 4,"9000"
```

## References

- [3GPP TS 27.007](https://www.3gpp.org/DynaReport/27007.htm) - AT command set for User Equipment
- [ISO/IEC 7816-4](https://www.iso.org/standard/54550.html) - Interindustry commands for interchange
- [Fibocom FM350-GL AT Command Manual](https://www.fibocom.com/en/support/download.html)
- [OpenWRT Integration Guide](./OPENWRT-INTEGRATION.md)
- [Fibocom Modem Configuration](./FIBOCOM-MODEM-CONFIG.md)

## See Also

- [OPENWRT-INTEGRATION.md](./OPENWRT-INTEGRATION.md) - Complete OpenWRT integration guide
- [DUAL-MODEM-SETUP.md](./DUAL-MODEM-SETUP.md) - Dual-modem configuration
- [FIBOCOM-MODEM-CONFIG.md](./FIBOCOM-MODEM-CONFIG.md) - Fibocom modem specifics
