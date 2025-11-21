# KI Proxy Quick Start Guide

## What is KI Proxy?

KI (Authentication Key) Proxy allows multiple virtual SIM clients to share a pool of physical SIM cards for authentication. The KI keys never leave the physical SIMs, providing security while maximizing hardware utilization.

## Use Case

**Problem**: You have 1000 IoT devices but don't want to manage 1000 physical SIM cards.

**Solution**: Use 50 physical SIMs (with carrier KI keys) in a pool, and route authentication from 1000 virtual SIMs to the pool using round-robin.

## Architecture Overview

```
[1000 Virtual SIMs] → [50 Physical SIMs with KI] → Round-Robin Auth
      (Clients)           (Bankd Pool)
```

## Quick Setup

### 1. Configure Bankd with KI Proxy Pool

```bash
osmo-remsim-bankd \
  -i remsim-server.example.com \
  -p 9998 \
  -b 1 \
  -n 1000 \
  -k \
  -S 1-50 \
  -V 900-999 \
  -C 310410
```

**Parameters:**
- `-n 1000`: Total slots (physical + virtual)
- `-k`: Enable KI proxy mode
- `-S 1-50`: Physical slots 1-50 have real SIMs with KI keys
- `-V 900-999`: Virtual slots 900-999 use KI proxy routing
- `-C 310410`: Carrier MCC-MNC (AT&T example)

### 2. Configure IonMesh

See [IONMESH-KI-PROXY.md](./IONMESH-KI-PROXY.md) for detailed IonMesh setup.

Quick summary:
```python
# Create KI proxy pool in IonMesh
{
  "pool_name": "ATT_KI_POOL_1",
  "carrier": "AT&T",
  "mcc_mnc": "310410",
  "bank_id": 1,
  "slot_range_start": 1,
  "slot_range_end": 50,
  "virtual_slot_start": 900,
  "virtual_slot_end": 999,
  "max_virtual_sims": 100
}
```

### 3. Add Physical SIM Metadata

```bash
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/sim-cards \
  -H "Content-Type: application/json" \
  -d '{
    "bank_id": 1,
    "slot_id": 1,
    "physical_iccid": "89014103211234567890",
    "physical_imsi": "310410123456789",
    "carrier": "AT&T",
    "mcc_mnc": "310410",
    "card_type": "KI_PROXY_MASTER",
    "ki_pool_name": "ATT_KI_POOL_1"
  }'
```

Repeat for slots 2-50 with actual SIM data.

### 4. Connect Clients

Clients connect normally and receive virtual slot assignments from IonMesh:

```bash
osmo-remsim-client-openwrt \
  -e /etc/remsim/ionmesh-event-script.sh
```

Client will receive:
- Virtual slot: 900
- Virtual ICCID/IMSI
- Bankd connection info

Client is **unaware** it's using KI proxy. Everything is transparent.

## How It Works

### Normal APDU (non-authentication)

```
Client (slot 900) → Bankd → Virtual slot 900 → Response
```

Virtual slot behaves like a software SIM for normal operations.

### Authentication APDU (0x88 - RUN GSM ALGORITHM)

```
Client (slot 900) sends 0x88 APDU
    ↓
Bankd detects: slot 900 is virtual (900-999 range)
    ↓
Bankd routes to physical slot pool (1-50) using round-robin
    ↓
Next physical slot: 23 (example)
    ↓
Physical SIM in slot 23 performs authentication
    ↓
Response → Client
```

Next authentication request will use slot 24, then 25, etc. (round-robin).

## Configuration Examples

### Multiple Carriers

Run separate bankd instances:

```bash
# AT&T Pool
osmo-remsim-bankd -b 1 -k -S 1-50 -V 900-999 -C 310410

# Verizon Pool
osmo-remsim-bankd -b 2 -k -S 1-50 -V 900-999 -C 311480

# T-Mobile Pool
osmo-remsim-bankd -b 3 -k -S 1-50 -V 900-999 -C 310260
```

### Mixed Physical and Virtual

```bash
# Slots 1-50: Physical KI SIMs (AT&T)
# Slots 51-100: Regular physical SIMs (testing)
# Slots 900-999: Virtual SIMs using KI proxy

osmo-remsim-bankd \
  -n 1000 \
  -k \
  -S 1-50 \
  -V 900-999
```

### Specific Slot List (Non-Contiguous)

```bash
# Only certain slots have KI SIMs
osmo-remsim-bankd \
  -k \
  -S 1,5,10,15,20,25,30,35,40,45,50 \
  -V 900-999
```

### Range Combinations

```bash
# Multiple ranges
osmo-remsim-bankd \
  -k \
  -S 1-25,76-100 \
  -V 900-999
```

## Monitoring

### Check Round-Robin Distribution

Monitor which physical slots are being used:

```bash
# Look for "KI Proxy: Response from proxy slot X" in logs
tail -f /var/log/bankd.log | grep "KI Proxy"
```

You should see fairly even distribution:
```
KI Proxy: Response from proxy slot 23
KI Proxy: Response from proxy slot 24
KI Proxy: Response from proxy slot 25
...
```

### Check Virtual Slot Activity

```bash
# See which virtual slots are active
grep "slot.*9[0-9][0-9]" /var/log/bankd.log
```

## Capacity Planning

### How Many Virtual SIMs per Physical?

- **Conservative**: 50 virtual SIMs per physical SIM
- **Moderate**: 100 virtual SIMs per physical SIM
- **Aggressive**: 200+ virtual SIMs per physical SIM

**Limiting factor**: Authentication frequency
- Low activity (IoT sensors): Higher ratio
- High activity (smartphones): Lower ratio

### Example Deployments

| Use Case | Physical SIMs | Virtual SIMs | Ratio |
|----------|---------------|--------------|-------|
| IoT sensors (hourly auth) | 50 | 5000 | 100:1 |
| IoT moderate (10min auth) | 50 | 1000 | 20:1 |
| Active devices (constant) | 50 | 100 | 2:1 |

## Troubleshooting

### "KI Proxy: proxy slot X not available"

**Cause**: Physical slot X doesn't have a SIM card or is not mapped.

**Solution**: 
1. Check physical SIM is inserted in slot X
2. Verify remsim-server has mapping for physical slot X
3. Check physical slot is in range (1-50 in example)

### "KI Proxy: No valid proxy slots available"

**Cause**: None of the slots in the pool are available.

**Solution**:
1. Check all physical SIMs are properly inserted
2. Verify bankd can read the physical SIMs
3. Check PC/SC reader connectivity
4. Verify slot range is correct (-S 1-50)

### Authentication Failures

**Symptoms**: Clients can't register on network

**Check**:
1. Physical SIMs have correct carrier KI keys
2. MCC-MNC matches carrier (-C option)
3. Physical SIMs are not locked/expired
4. Carrier allows remote SIM authentication

### Round-Robin Not Working

**Symptoms**: All auth requests go to same physical slot

**Check**:
1. Multiple physical slots configured in -S option
2. All physical slots are available and mapped
3. Check logs for round-robin slot selection messages

## Performance Tips

1. **Use SSD storage** for bankd if logging heavily
2. **Increase worker threads** if handling many concurrent auths
3. **Monitor CPU** on bankd server - auth crypto is CPU intensive
4. **Use multiple bankd instances** for horizontal scaling
5. **Load balance clients** across multiple bankd servers via IonMesh

## Security Considerations

✅ **KI keys never leave physical SIMs** - All crypto done on card

✅ **Virtual ICCIDs/IMSIs** - Real credentials stay on physical SIMs

✅ **Carrier isolation** - Separate pools per carrier (AT&T, Verizon, etc.)

✅ **Audit trail** - All auth requests logged with physical slot used

⚠️ **Physical SIM security** - Protect the 50 physical SIMs carefully

⚠️ **Network policy** - Ensure carrier allows this usage model

## Best Practices

1. **Label physical SIMs** clearly (Slot 1-50 AT&T KI Pool)
2. **Document metadata** in IonMesh JSON fields
3. **Monitor auth success rates** per physical slot
4. **Rotate physical SIMs** periodically if allowed by carrier
5. **Keep spares** of physical SIMs for hot-swap
6. **Test failover** - What happens if physical SIM fails?
7. **Backup metadata** - JSON records of all physical SIM info

## Next Steps

- Full IonMesh setup: [IONMESH-KI-PROXY.md](./IONMESH-KI-PROXY.md)
- OpenWRT integration: [OPENWRT-INTEGRATION.md](./OPENWRT-INTEGRATION.md)
- IonMesh API details: [IONMESH-INTEGRATION.md](./IONMESH-INTEGRATION.md)

## Support

For issues or questions:
- osmo-remsim: https://osmocom.org/projects/osmo-remsim
- IonMesh: https://github.com/terminills/ionmesh-fork
