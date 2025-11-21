# IonMesh Orchestrator Integration Guide

## Overview

This document describes the integration between osmo-remsim-client-openwrt and the IonMesh orchestrator system. IonMesh provides centralized SIM bank management, dynamic slot assignment, and KI (Authentication Key) proxy orchestration for remote SIM deployments.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        IonMesh Orchestrator                      │
│  (https://github.com/terminills/ionmesh-fork)                  │
│                                                                   │
│  ┌────────────────┐    ┌────────────────┐   ┌───────────────┐  │
│  │  SIM Bank DB   │    │  Slot Manager  │   │  KI Proxy Mgr │  │
│  │  (Multi-tenant)│    │  (Assignment)  │   │  (Auth Proxy) │  │
│  └────────────────┘    └────────────────┘   └───────────────┘  │
│                                                                   │
│  API: /api/backend/v1/remsim/*                                  │
└───────────────────────────┬───────────────────────────────────┘
                            │ REST API
                            │
    ┌───────────────────────┼───────────────────────┐
    │                       │                       │
    ▼                       ▼                       ▼
┌─────────┐           ┌─────────┐           ┌─────────┐
│OpenWRT  │           │OpenWRT  │           │OpenWRT  │
│Client 1 │           │Client 2 │           │Client N │
│         │           │         │           │         │
│remsim-  │           │remsim-  │           │remsim-  │
│client-  │           │client-  │           │client-  │
│openwrt  │           │openwrt  │           │openwrt  │
└────┬────┘           └────┬────┘           └────┬────┘
     │                     │                     │
     │  RSPRO Protocol     │                     │
     └─────────────────────┼─────────────────────┘
                           │
                    ┌──────┴──────┐
                    │             │
                    ▼             ▼
            ┌───────────┐   ┌───────────┐
            │  Bankd 1  │   │  Bankd 2  │
            │(SIM Bank) │   │(SIM Bank) │
            └───────────┘   └───────────┘
```

## Features

### Current Implementation

✅ **Client Registration API**: OpenWRT clients can register with IonMesh
✅ **Dynamic Slot Assignment**: IonMesh assigns available SIM slots to clients
✅ **Bankd Discovery**: Clients receive bankd connection information
✅ **Multi-tenancy Support**: Tenant isolation for reseller environments
✅ **Mapping Mode Support**: ONE_TO_ONE_SWSIM, ONE_TO_ONE_VSIM, KI_PROXY_SWSIM
✅ **MCC/MNC Based Assignment**: Carrier-specific slot assignment

### Integration Points

The osmo-remsim-client-openwrt communicates with IonMesh via REST API:

1. **Registration**: `POST /api/backend/v1/remsim/register-client`
2. **Heartbeat**: `POST /api/backend/v1/remsim/heartbeat`
3. **Unregistration**: `DELETE /api/backend/v1/remsim/unregister/{client_id}`

## Required IonMesh Enhancements

The following enhancements are needed in the IonMesh orchestrator to fully support osmo-remsim-client-openwrt:

### 1. RSPRO Client Registration API Endpoint ⚠️ **REQUIRED**

**File**: `ionmesh-fork/app/routes/api/remsim_api.py`

**Enhancement**: Add REST API endpoints for osmo-remsim client registration

```python
@remsim_api_bp.route('/api/backend/v1/remsim/register-client', methods=['POST'])
def register_remsim_client():
    """
    Register an osmo-remsim-client-openwrt instance and assign SIM slot
    
    Request body:
    {
        "client_id": "openwrt-router1-slot0",
        "mapping_mode": "ONE_TO_ONE_SWSIM",
        "mcc_mnc": "310410",  # Optional: for carrier-specific assignment
        "tenant_id": 1
    }
    
    Response:
    {
        "status": "ok",
        "bank_id": 1,
        "slot_id": 42,
        "iccid": "89014103211234567890",
        "imsi": "310410123456789",
        "bankd_endpoint": "http://bankd1.example.com:9999",
        "mapping_mode": "ONE_TO_ONE_SWSIM",
        "profile_id": "uuid-of-service-profile"
    }
    """
    data = request.get_json()
    client_id = data.get('client_id')
    mapping_mode = data.get('mapping_mode', 'ONE_TO_ONE_SWSIM')
    mcc_mnc = data.get('mcc_mnc')
    tenant_id = data.get('tenant_id')
    
    # Call existing register_client function from remsim_api.py
    result = register_client(
        client_id=client_id,
        mapping_mode=mapping_mode,
        mcc_mnc=mcc_mnc,
        tenant_id=tenant_id
    )
    
    if result.get('status') == 'error':
        return jsonify(result), 400
    
    return jsonify(result), 200
```

### 2. Client Heartbeat and Health Monitoring ⚠️ **REQUIRED**

**Enhancement**: Add heartbeat endpoint to track client health

```python
@remsim_api_bp.route('/api/backend/v1/remsim/heartbeat', methods=['POST'])
def remsim_client_heartbeat():
    """
    Receive heartbeat from osmo-remsim client
    
    Request body:
    {
        "client_id": "openwrt-router1-slot0",
        "status": "active",
        "stats": {
            "uptime_seconds": 3600,
            "tpdus_sent": 1234,
            "tpdus_received": 5678,
            "errors": 0
        }
    }
    
    Response:
    {
        "status": "ok",
        "next_heartbeat_interval": 60
    }
    """
    data = request.get_json()
    client_id = data.get('client_id')
    client_status = data.get('status')
    stats = data.get('stats', {})
    
    # Update client health status in database
    profile = ServiceProfile.query.filter_by(client_id=client_id).first()
    if profile:
        profile.last_heartbeat = datetime.utcnow()
        profile.health_status = client_status
        db.session.commit()
        
        return jsonify({"status": "ok", "next_heartbeat_interval": 60}), 200
    
    return jsonify({"status": "error", "message": "Client not found"}), 404
```

### 3. Client Unregistration and Cleanup ⚠️ **REQUIRED**

**Enhancement**: Add unregistration endpoint to clean up assignments

```python
@remsim_api_bp.route('/api/backend/v1/remsim/unregister/<client_id>', methods=['DELETE'])
def unregister_remsim_client(client_id):
    """
    Unregister osmo-remsim client and release slot assignment
    
    Response:
    {
        "status": "ok",
        "message": "Client unregistered and slot released"
    }
    """
    # Find and deactivate service profile
    profile = ServiceProfile.query.filter_by(client_id=client_id).first()
    if not profile:
        return jsonify({"status": "error", "message": "Client not found"}), 404
    
    # Release the slot
    slot = SIMBankSlot.query.filter_by(
        bank_id=profile.bank_id,
        slot_id=profile.physical_slot_id
    ).first()
    
    if slot:
        if profile.mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value:
            # Decrement virtual profile count for KI proxy mode
            slot.virtual_profile_count = max(0, slot.virtual_profile_count - 1)
        else:
            # Free the slot for one-to-one modes
            slot.status = SIMSlotStatusEnum.AVAILABLE
        db.session.commit()
    
    # Mark profile as deactivated
    profile.status = ProfileStatusEnum.DEACTIVATED
    profile.deactivated_at = datetime.utcnow()
    db.session.commit()
    
    _log_audit("unregister_client", "service_profile", str(profile.profile_id), 
               profile.tenant_id, {"client_id": client_id})
    
    return jsonify({"status": "ok", "message": "Client unregistered"}), 200
```

### 4. Database Schema Additions 📝 **RECOMMENDED**

**Enhancement**: Add fields to track client-specific data

```python
# In app/main_models.py, add to ServiceProfile model:

class ServiceProfile(db.Model):
    # ... existing fields ...
    
    # Client tracking fields
    client_id = db.Column(db.String(255), nullable=True, index=True)
    last_heartbeat = db.Column(db.DateTime, nullable=True)
    health_status = db.Column(db.String(50), nullable=True, default='unknown')
    client_stats = db.Column(JSON, nullable=True)  # Store client statistics
    
    # Hardware information from OpenWRT
    client_hardware_info = db.Column(JSON, nullable=True)  # GPIO pins, modem device, etc.
    client_ip_address = db.Column(db.String(45), nullable=True)  # IPv4 or IPv6
```

### 5. Client Management Dashboard 📝 **RECOMMENDED**

**Enhancement**: Add web UI for monitoring OpenWRT clients

**File**: Create `ionmesh-fork/app/routes/admin/openwrt_clients.py`

Features to implement:
- List all registered OpenWRT clients
- View client status and health metrics
- Force slot reassignment
- View real-time TPDU statistics
- Remote client configuration updates
- Client log streaming

### 6. Auto-Discovery and Zero-Config 💡 **OPTIONAL**

**Enhancement**: Allow OpenWRT clients to discover IonMesh via mDNS/DNS-SD

```python
# Add discovery endpoint
@remsim_api_bp.route('/api/backend/v1/remsim/discover', methods=['GET'])
def discover_ionmesh():
    """
    Discovery endpoint for auto-configuration
    
    Response:
    {
        "service": "ionmesh-orchestrator",
        "version": "1.0.0",
        "api_endpoint": "http://ionmesh.local:5000/api/backend/v1",
        "capabilities": [
            "slot-assignment",
            "ki-proxy",
            "multi-tenant",
            "mcc-mnc-routing"
        ]
    }
    """
    return jsonify({
        "service": "ionmesh-orchestrator",
        "version": "1.0.0",
        "api_endpoint": request.host_url + "api/backend/v1",
        "capabilities": ["slot-assignment", "ki-proxy", "multi-tenant", "mcc-mnc-routing"]
    })
```

### 7. Webhook Support for Client Events 💡 **OPTIONAL**

**Enhancement**: Send webhook notifications for client lifecycle events

```python
# Add webhook configuration to IonMesh config
class WebhookConfig(db.Model):
    webhook_id = db.Column(Integer, primary_key=True)
    tenant_id = db.Column(Integer, db.ForeignKey('resellers.tenant_id'))
    event_type = db.Column(String(50))  # 'client_registered', 'client_disconnected', etc.
    webhook_url = db.Column(String(255))
    enabled = db.Column(Boolean, default=True)

# Trigger webhooks on client events
def trigger_webhook(event_type, data):
    webhooks = WebhookConfig.query.filter_by(event_type=event_type, enabled=True).all()
    for webhook in webhooks:
        try:
            requests.post(webhook.webhook_url, json=data, timeout=5)
        except Exception as e:
            logger.error(f"Webhook failed: {e}")
```

### 8. Advanced Slot Assignment Policies 💡 **OPTIONAL**

**Enhancement**: Implement policy-based slot assignment

```python
class SlotAssignmentPolicy(db.Model):
    """Define rules for slot assignment"""
    policy_id = db.Column(Integer, primary_key=True)
    tenant_id = db.Column(Integer, db.ForeignKey('resellers.tenant_id'))
    priority = db.Column(Integer, default=100)
    
    # Policy conditions
    carrier_mcc_mnc = db.Column(String(10), nullable=True)
    client_location = db.Column(String(100), nullable=True)  # Geographic region
    time_of_day_start = db.Column(Time, nullable=True)
    time_of_day_end = db.Column(Time, nullable=True)
    
    # Policy action
    preferred_bank_id = db.Column(Integer, db.ForeignKey('sim_banks.bank_id'))
    load_balancing_mode = db.Column(String(50))  # 'round-robin', 'least-loaded', etc.
```

## Configuration

### OpenWRT Client Configuration

Enable IonMesh orchestration by setting the event script:

```bash
osmo-remsim-client-openwrt \
  -e /etc/remsim/ionmesh-event-script.sh \
  -i 192.168.1.100 \
  -c 1 -n 0
```

### Environment Variables

The OpenWRT client supports the following IonMesh environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `IONMESH_HOST` | IonMesh server hostname/IP | 127.0.0.1 |
| `IONMESH_PORT` | IonMesh API port | 5000 |
| `IONMESH_TENANT_ID` | Tenant ID for multi-tenancy | 1 |
| `IONMESH_MAPPING_MODE` | Slot mapping mode | ONE_TO_ONE_SWSIM |
| `IONMESH_MCC_MNC` | Carrier MCC/MNC for routing | (auto-detect) |

### Example Configuration

```bash
#!/bin/sh
# /etc/remsim/ionmesh-event-script.sh

export IONMESH_HOST="ionmesh.example.com"
export IONMESH_PORT="5000"
export IONMESH_TENANT_ID="1"
export IONMESH_MAPPING_MODE="KI_PROXY_SWSIM"
export IONMESH_MCC_MNC="310410"

# Enable IonMesh by including "ionmesh" in script path
```

## Mapping Modes

### ONE_TO_ONE_SWSIM (Software SIM)
- One physical slot per client
- Software-based SIM emulation
- Best for: Standard deployments

### ONE_TO_ONE_VSIM (Virtual SIM)
- One physical slot per client
- Virtual SIM profiles
- Best for: eSIM deployments

### KI_PROXY_SWSIM (KI Proxy Mode) ⭐
- Multiple virtual profiles per physical slot
- Authentication proxy via IonMesh
- KI keys never leave the bankd
- Best for: High-density deployments, security-sensitive environments
- Supports up to 6000 virtual SIMs per physical slot

## Testing

### Test IonMesh Registration

```bash
# Test registration API
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/remsim/register-client \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "test-router-1",
    "mapping_mode": "ONE_TO_ONE_SWSIM",
    "tenant_id": 1
  }'

# Expected response:
{
  "status": "ok",
  "bank_id": 1,
  "slot_id": 42,
  "iccid": "89014103211234567890",
  "imsi": "310410123456789",
  "bankd_endpoint": "http://bankd1.example.com:9999",
  "mapping_mode": "ONE_TO_ONE_SWSIM"
}
```

### Test Client with IonMesh

```bash
# On OpenWRT router
export IONMESH_HOST="ionmesh.example.com"
export IONMESH_PORT="5000"
export IONMESH_TENANT_ID="1"

osmo-remsim-client-openwrt \
  -e /etc/remsim/ionmesh-event-script.sh \
  -V 20 -P 21 \
  -d DMAIN:DPCU
```

Expected log output:
```
IonMesh orchestration enabled
  Host: ionmesh.example.com:5000
  Tenant: 1, Client: router1-slot0
  Mapping mode: ONE_TO_ONE_SWSIM
Registering client with IonMesh: ionmesh.example.com:5000
Successfully registered with IonMesh
  Bank: 1, Slot: 42
  Bankd: bankd1.example.com:9999
  ICCID: 89014103211234567890, IMSI: 310410123456789
```

## Security Considerations

### API Authentication

⚠️ **REQUIRED**: Implement API authentication for production deployments

```python
# Add API key authentication
@remsim_api_bp.before_request
def verify_api_key():
    api_key = request.headers.get('X-API-Key')
    if not api_key or not verify_key(api_key):
        return jsonify({"status": "error", "message": "Unauthorized"}), 401
```

### TLS/SSL Support

- Use HTTPS for IonMesh API communication
- Implement certificate validation in osmo-remsim-client-openwrt
- Support client certificates for mutual TLS

### Multi-Tenancy Isolation

- Enforce tenant_id validation on all API calls
- Prevent cross-tenant slot assignment
- Audit all tenant-crossing operations

## Troubleshooting

### Client Cannot Register

```bash
# Check IonMesh API is accessible
curl http://ionmesh.example.com:5000/api/backend/v1/remsim/discover

# Check client logs
logread | grep remsim

# Verify tenant_id exists in IonMesh database
# Verify available slots in SIM bank
```

### No Available Slots

```bash
# Check slot availability in IonMesh
curl http://ionmesh.example.com:5000/api/backend/v1/simbank/slots?status=available

# Release unused slots
curl -X DELETE http://ionmesh.example.com:5000/api/backend/v1/remsim/unregister/old-client-id
```

### Heartbeat Failures

```bash
# Check network connectivity
ping ionmesh.example.com

# Verify API endpoint
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/remsim/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"client_id": "test", "status": "active"}'
```

## Implementation Status

| Component | Status | Priority |
|-----------|--------|----------|
| Client Registration API | ⚠️ Required | HIGH |
| Heartbeat Endpoint | ⚠️ Required | HIGH |
| Unregistration Endpoint | ⚠️ Required | HIGH |
| Database Schema Updates | 📝 Recommended | MEDIUM |
| Client Dashboard UI | 📝 Recommended | MEDIUM |
| Auto-Discovery | 💡 Optional | LOW |
| Webhook Support | 💡 Optional | LOW |
| Advanced Policies | 💡 Optional | LOW |

## Next Steps

1. **Implement Required Endpoints** in IonMesh (register, heartbeat, unregister)
2. **Test Integration** with real OpenWRT hardware
3. **Add Dashboard UI** for client management
4. **Security Hardening** (API keys, TLS, tenant isolation)
5. **Performance Testing** at scale (100+ clients)
6. **Documentation** for deployment and operations

## References

- [IonMesh Fork Repository](https://github.com/terminills/ionmesh-fork)
- [osmo-remsim Documentation](https://osmocom.org/projects/osmo-remsim/wiki)
- [OpenWRT Integration Guide](OPENWRT-INTEGRATION.md)
- [RSPRO Protocol Specification](https://osmocom.org/projects/osmo-remsim)
