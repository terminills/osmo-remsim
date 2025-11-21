# IonMesh Enhancements for osmo-remsim Integration

**Repository**: https://github.com/terminills/ionmesh-fork  
**Purpose**: Enhance IonMesh orchestrator for full osmo-remsim-client-openwrt integration  
**Status**: Enhancement Recommendations  
**Date**: 2025-01-21

---

## Executive Summary

This document details recommended enhancements to the IonMesh orchestrator platform to provide complete support for osmo-remsim-client-openwrt deployments. Based on analysis of the current IonMesh codebase, these enhancements will enable seamless client registration, real-time monitoring, and advanced orchestration features.

## Current IonMesh Capabilities

**Existing Features** (Identified from codebase):
- ✅ SIM Bank management (`SIMBank`, `SIMBankSlot` models)
- ✅ Service Profile management (`ServiceProfile` model)
- ✅ Bankd Instance tracking (`BankdInstance` model)
- ✅ KI Proxy support (`KIProxyMap`, `KiProxyLog` models)
- ✅ MCC/MNC carrier routing (`MccMnc`, `Carrier` models)
- ✅ Slot mapping and health tracking (`SlotMap`, `SlotHealthLog` models)
- ✅ Multi-tenancy support (tenant_id throughout models)
- ✅ Audit logging (`GLAuditLog` model)
- ✅ RESTful API (`app/routes/api/remsim_api.py`)
- ✅ Mapping mode support (ONE_TO_ONE_SWSIM, ONE_TO_ONE_VSIM, KI_PROXY_SWSIM)

## Enhancement Categories

### 1. REQUIRED: OpenWRT Client Registration API ⚠️

**Priority**: CRITICAL  
**Effort**: 1-2 weeks  
**File**: `app/routes/api/remsim_api.py`

#### Current Gap
The existing `remsim_api.py` provides backend orchestration functions but lacks dedicated endpoints for OpenWRT client registration and lifecycle management.

#### Implementation

**New Endpoint: Register Client**
```python
# app/routes/api/remsim_api.py

from flask import Blueprint, request, jsonify
from app.extensions import db
from app.main_models import ServiceProfile, SIMBankSlot, SIMBank, BankdInstance
from app.enums import ProfileStatusEnum, MappingModeEnum, SIMSlotStatusEnum, KIProxyModeEnum
from datetime import datetime
import uuid

remsim_api_bp = Blueprint('remsim_api', __name__, url_prefix='/api/backend/v1/remsim')

# NOTE: The helper functions (_find_available_slot, _log_audit, _log_slot_health) 
# are currently defined in the existing app/routes/api/remsim_api.py.
# Consider refactoring these to app/utils/remsim_utils.py for better code organization
# and to avoid circular dependency issues.

@remsim_api_bp.route('/register-client', methods=['POST'])
def register_remsim_client():
    """
    Register an osmo-remsim-client-openwrt instance and assign SIM slot
    
    Request body:
    {
        "client_id": "openwrt-router1-slot0",
        "mapping_mode": "ONE_TO_ONE_SWSIM",  # or ONE_TO_ONE_VSIM, KI_PROXY_SWSIM
        "mcc_mnc": "310410",  # Optional: for carrier-specific assignment
        "tenant_id": 1,
        "hardware_info": {  # Optional: hardware metadata
            "modem_vendor": "Fibocom",
            "modem_model": "FM350-GL",
            "gpio_reset": 21,
            "gpio_sim_switch": 20
        },
        "preferred_bank_id": null  # Optional: prefer specific bank
    }
    
    Response (Success):
    {
        "status": "ok",
        "bank_id": 1,
        "slot_id": 42,
        "iccid": "89014103211234567890",
        "imsi": "310410123456789",
        "bankd_endpoint": "http://bankd1.example.com:9999",
        "mapping_mode": "ONE_TO_ONE_SWSIM",
        "profile_id": "550e8400-e29b-41d4-a716-446655440000",
        "heartbeat_interval": 60,  # seconds
        "ki_proxy_enabled": false
    }
    
    Response (Error):
    {
        "status": "error",
        "message": "No available slots for mapping mode",
        "available_modes": ["KI_PROXY_SWSIM"]
    }
    """
    data = request.get_json()
    
    # Validate required fields
    client_id = data.get('client_id')
    if not client_id:
        return jsonify({"status": "error", "message": "client_id required"}), 400
    
    mapping_mode = data.get('mapping_mode', 'ONE_TO_ONE_SWSIM')
    mcc_mnc = data.get('mcc_mnc')
    tenant_id = data.get('tenant_id', 1)
    hardware_info = data.get('hardware_info', {})
    preferred_bank_id = data.get('preferred_bank_id')
    
    # Check if client already registered
    existing_profile = ServiceProfile.query.filter_by(
        client_id=client_id,
        status=ProfileStatusEnum.ACTIVE
    ).first()
    
    if existing_profile:
        # Return existing assignment
        slot = SIMBankSlot.query.filter_by(
            bank_id=existing_profile.bank_id,
            slot_id=existing_profile.physical_slot_id
        ).first()
        
        bankd = BankdInstance.query.get(existing_profile.bankd_instance_id)
        
        return jsonify({
            "status": "ok",
            "bank_id": existing_profile.bank_id,
            "slot_id": existing_profile.physical_slot_id,
            "iccid": slot.iccid if slot else None,
            "imsi": slot.imsi if slot else None,
            "bankd_endpoint": bankd.endpoint if bankd else None,
            "mapping_mode": existing_profile.mapping_mode,
            "profile_id": str(existing_profile.profile_id),
            "heartbeat_interval": 60,
            "ki_proxy_enabled": existing_profile.mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value,
            "note": "Existing registration returned"
        }), 200
    
    # Find available slot using existing function
    # Note: These helper functions should be in a shared utilities module
    # For now, import from current module (will be refactored)
    from app.routes.api.remsim_api import _find_available_slot, _log_audit
    
    slot_assignment = _find_available_slot(
        mapping_mode=mapping_mode,
        mcc_mnc=mcc_mnc,
        bank_id=preferred_bank_id,
        tenant_id=tenant_id
    )
    
    if not slot_assignment:
        # No slots available in requested mode
        logger.warning(f"No available slots for client {client_id}, mode {mapping_mode}")
        
        # Check what modes have availability
        available_modes = []
        for mode in [MappingModeEnum.ONE_TO_ONE_SWSIM, 
                     MappingModeEnum.ONE_TO_ONE_VSIM,
                     MappingModeEnum.KI_PROXY_SWSIM]:
            if _find_available_slot(mode.value, mcc_mnc, preferred_bank_id, tenant_id):
                available_modes.append(mode.value)
        
        return jsonify({
            "status": "error",
            "message": "No available slots for requested mapping mode",
            "available_modes": available_modes
        }), 503
    
    bank = slot_assignment['bank']
    slot_id = slot_assignment['slot_id']
    
    # Get slot details
    slot = SIMBankSlot.query.filter_by(
        bank_id=bank.bank_id,
        slot_id=slot_id
    ).first()
    
    # Get bankd instance
    bankd = BankdInstance.query.get(bank.bankd_instance_id)
    
    # Create service profile
    profile = ServiceProfile(
        profile_id=uuid.uuid4(),
        tenant_id=tenant_id,
        client_id=client_id,
        mapping_mode=mapping_mode,
        bank_id=bank.bank_id,
        bankd_instance_id=bank.bankd_instance_id,
        physical_slot_id=slot_id,
        status=ProfileStatusEnum.ACTIVE,
        created_at=datetime.utcnow(),
        last_heartbeat=datetime.utcnow(),
        health_status='online',
        client_hardware_info=hardware_info,
        client_ip_address=request.remote_addr
    )
    
    db.session.add(profile)
    
    # Update slot status
    if mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value:
        # Increment virtual profile count for KI proxy mode
        slot.virtual_profile_count = (slot.virtual_profile_count or 0) + 1
    else:
        # Mark slot as assigned for one-to-one modes
        slot.status = SIMSlotStatusEnum.ASSIGNED
    
    db.session.commit()
    
    # Log audit event
    _log_audit("register_client", "service_profile", str(profile.profile_id),
               tenant_id, {
                   "client_id": client_id,
                   "mapping_mode": mapping_mode,
                   "bank_id": bank.bank_id,
                   "slot_id": slot_id
               })
    
    return jsonify({
        "status": "ok",
        "bank_id": bank.bank_id,
        "slot_id": slot_id,
        "iccid": slot.iccid,
        "imsi": slot.imsi,
        "bankd_endpoint": bankd.endpoint if bankd else f"http://{bank.endpoint}:9999",
        "mapping_mode": mapping_mode,
        "profile_id": str(profile.profile_id),
        "heartbeat_interval": 60,
        "ki_proxy_enabled": mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value
    }), 200


@remsim_api_bp.route('/heartbeat', methods=['POST'])
def remsim_client_heartbeat():
    """
    Receive heartbeat from osmo-remsim client
    
    Request body:
    {
        "client_id": "openwrt-router1-slot0",
        "status": "active",  # or "warning", "error"
        "stats": {
            "uptime_seconds": 3600,
            "tpdus_sent": 1234,
            "tpdus_received": 5678,
            "errors": 0,
            "signal_rssi": -75,
            "signal_rsrp": -95,
            "data_rx_bytes": 1048576,
            "data_tx_bytes": 524288
        },
        "modem_info": {
            "vendor": "Fibocom",
            "model": "FM350-GL",
            "firmware": "FM350GL-12.001.01.00",
            "imei": "861536030000000",
            "network": "AT&T"
        }
    }
    
    Response:
    {
        "status": "ok",
        "next_heartbeat_interval": 60,
        "commands": []  # Optional commands from orchestrator
    }
    """
    data = request.get_json()
    client_id = data.get('client_id')
    client_status = data.get('status', 'active')
    stats = data.get('stats', {})
    modem_info = data.get('modem_info', {})
    
    if not client_id:
        return jsonify({"status": "error", "message": "client_id required"}), 400
    
    # Find service profile
    profile = ServiceProfile.query.filter_by(client_id=client_id).first()
    
    if not profile:
        return jsonify({
            "status": "error",
            "message": "Client not registered"
        }), 404
    
    # Update profile with heartbeat data
    profile.last_heartbeat = datetime.utcnow()
    profile.health_status = client_status
    profile.client_stats = stats
    
    # Update slot health if significant changes
    slot = SIMBankSlot.query.filter_by(
        bank_id=profile.bank_id,
        slot_id=profile.physical_slot_id
    ).first()
    
    if slot:
        # Log health events if status changed
        if slot.health_status != client_status:
            # Note: Consider moving _log_slot_health to utils module
            from app.routes.api.remsim_api import _log_slot_health
            _log_slot_health(
                slot.id,
                f"status_change_{client_status}",
                f"Client {client_id} status changed from {slot.health_status} to {client_status}"
            )
        
        slot.health_status = client_status
        slot.last_health_check = datetime.utcnow()
    
    db.session.commit()
    
    # Check for pending commands (future enhancement)
    pending_commands = []
    
    return jsonify({
        "status": "ok",
        "next_heartbeat_interval": 60,
        "commands": pending_commands
    }), 200


@remsim_api_bp.route('/unregister/<client_id>', methods=['DELETE'])
def unregister_remsim_client(client_id):
    """
    Unregister osmo-remsim client and release slot assignment
    
    Response:
    {
        "status": "ok",
        "message": "Client unregistered and slot released"
    }
    """
    # Find service profile
    profile = ServiceProfile.query.filter_by(client_id=client_id).first()
    
    if not profile:
        return jsonify({
            "status": "error",
            "message": "Client not found"
        }), 404
    
    # Find slot
    slot = SIMBankSlot.query.filter_by(
        bank_id=profile.bank_id,
        slot_id=profile.physical_slot_id
    ).first()
    
    # Release slot
    if slot:
        if profile.mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value:
            # Decrement virtual profile count
            slot.virtual_profile_count = max(0, (slot.virtual_profile_count or 1) - 1)
        else:
            # Free the slot
            slot.status = SIMSlotStatusEnum.AVAILABLE
        
        from app.routes.api.remsim_api import _log_slot_health
        _log_slot_health(
            slot.id,
            "slot_released",
            f"Slot released by client {client_id}"
        )
    
    # Deactivate profile
    profile.status = ProfileStatusEnum.DEACTIVATED
    profile.deactivated_at = datetime.utcnow()
    
    db.session.commit()
    
    # Log audit
    # Note: Consider moving _log_audit to utils module
    from app.routes.api.remsim_api import _log_audit
    _log_audit("unregister_client", "service_profile", str(profile.profile_id),
               profile.tenant_id, {"client_id": client_id})
    
    return jsonify({
        "status": "ok",
        "message": "Client unregistered and slot released"
    }), 200


@remsim_api_bp.route('/discover', methods=['GET'])
def discover_ionmesh():
    """
    Discovery endpoint for auto-configuration
    
    Response:
    {
        "service": "ionmesh-orchestrator",
        "version": "1.0.0",
        "api_endpoint": "http://ionmesh.example.com:5000/api/backend/v1",
        "capabilities": [
            "slot-assignment",
            "ki-proxy",
            "multi-tenant",
            "mcc-mnc-routing",
            "health-monitoring"
        ],
        "supported_mapping_modes": [
            "ONE_TO_ONE_SWSIM",
            "ONE_TO_ONE_VSIM",
            "KI_PROXY_SWSIM"
        ]
    }
    """
    return jsonify({
        "service": "ionmesh-orchestrator",
        "version": "1.0.0",
        "api_endpoint": request.host_url.rstrip('/') + "/api/backend/v1",
        "capabilities": [
            "slot-assignment",
            "ki-proxy",
            "multi-tenant",
            "mcc-mnc-routing",
            "health-monitoring",
            "auto-failover"
        ],
        "supported_mapping_modes": [
            "ONE_TO_ONE_SWSIM",
            "ONE_TO_ONE_VSIM",
            "KI_PROXY_SWSIM"
        ],
        "heartbeat_interval": 60,
        "max_swsims_per_slot": 6000
    }), 200
```

#### Database Schema Additions

**Add fields to ServiceProfile model** (`app/main_models.py`):
```python
class ServiceProfile(db.Model):
    # ... existing fields ...
    
    # Client tracking fields (ADD THESE)
    client_id = db.Column(db.String(255), nullable=True, index=True)
    last_heartbeat = db.Column(db.DateTime, nullable=True)
    health_status = db.Column(db.String(50), nullable=True, default='unknown')
    client_stats = db.Column(db.JSON, nullable=True)  # Store client statistics
    client_hardware_info = db.Column(db.JSON, nullable=True)  # GPIO pins, modem device, etc.
    client_ip_address = db.Column(db.String(45), nullable=True)  # IPv4 or IPv6
```

**Migration Script** (`app/migrations/versions/add_client_tracking_fields.py`):
```python
"""Add client tracking fields to ServiceProfile

Revision ID: remsim_client_001
Revises: [previous_revision]
Create Date: 2025-01-21
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = 'remsim_client_001'
down_revision = '[previous_revision]'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('service_profiles', sa.Column('client_id', sa.String(255), nullable=True))
    op.add_column('service_profiles', sa.Column('last_heartbeat', sa.DateTime(), nullable=True))
    op.add_column('service_profiles', sa.Column('health_status', sa.String(50), nullable=True, server_default='unknown'))
    op.add_column('service_profiles', sa.Column('client_stats', postgresql.JSON(astext_type=sa.Text()), nullable=True))
    op.add_column('service_profiles', sa.Column('client_hardware_info', postgresql.JSON(astext_type=sa.Text()), nullable=True))
    op.add_column('service_profiles', sa.Column('client_ip_address', sa.String(45), nullable=True))
    
    # Create index for faster lookups
    op.create_index('idx_service_profiles_client_id', 'service_profiles', ['client_id'])

def downgrade():
    op.drop_index('idx_service_profiles_client_id', table_name='service_profiles')
    op.drop_column('service_profiles', 'client_ip_address')
    op.drop_column('service_profiles', 'client_hardware_info')
    op.drop_column('service_profiles', 'client_stats')
    op.drop_column('service_profiles', 'health_status')
    op.drop_column('service_profiles', 'last_heartbeat')
    op.drop_column('service_profiles', 'client_id')
```

---

### 2. RECOMMENDED: Client Management Dashboard 📊

**Priority**: HIGH  
**Effort**: 2-3 weeks  
**Files**: `app/routes/admin/openwrt_clients.py`, `app/templates/admin/openwrt_clients.html`

#### Web UI for OpenWRT Client Management

**New Admin Route** (`app/routes/admin/openwrt_clients.py`):
```python
from flask import Blueprint, render_template, request, jsonify
from flask_login import login_required, current_user
from app.extensions import db
from app.main_models import ServiceProfile, SIMBankSlot, SIMBank, BankdInstance
from app.enums import ProfileStatusEnum
from sqlalchemy import desc
from datetime import datetime, timedelta

openwrt_clients_bp = Blueprint('openwrt_clients', __name__, url_prefix='/admin/openwrt-clients')

@openwrt_clients_bp.route('/')
@login_required
def index():
    """List all registered OpenWRT clients"""
    
    # Get filter parameters
    status_filter = request.args.get('status', 'all')
    tenant_filter = request.args.get('tenant_id', type=int)
    mapping_mode_filter = request.args.get('mapping_mode')
    
    # Build query
    query = ServiceProfile.query.filter(
        ServiceProfile.client_id.isnot(None)
    )
    
    if status_filter != 'all':
        if status_filter == 'online':
            # Online = heartbeat within last 5 minutes
            cutoff = datetime.utcnow() - timedelta(minutes=5)
            query = query.filter(ServiceProfile.last_heartbeat >= cutoff)
        elif status_filter == 'offline':
            cutoff = datetime.utcnow() - timedelta(minutes=5)
            query = query.filter(
                (ServiceProfile.last_heartbeat < cutoff) |
                (ServiceProfile.last_heartbeat.is_(None))
            )
    
    if tenant_filter:
        query = query.filter(ServiceProfile.tenant_id == tenant_filter)
    
    if mapping_mode_filter:
        query = query.filter(ServiceProfile.mapping_mode == mapping_mode_filter)
    
    # Order by last heartbeat
    clients = query.order_by(desc(ServiceProfile.last_heartbeat)).all()
    
    # Enrich with slot and bank information
    client_data = []
    for client in clients:
        slot = SIMBankSlot.query.filter_by(
            bank_id=client.bank_id,
            slot_id=client.physical_slot_id
        ).first()
        
        bank = SIMBank.query.get(client.bank_id)
        bankd = BankdInstance.query.get(client.bankd_instance_id)
        
        # Determine online status
        if client.last_heartbeat:
            time_since_heartbeat = (datetime.utcnow() - client.last_heartbeat).total_seconds()
            is_online = time_since_heartbeat < 300  # 5 minutes
        else:
            is_online = False
        
        client_data.append({
            'profile_id': str(client.profile_id),
            'client_id': client.client_id,
            'tenant_id': client.tenant_id,
            'mapping_mode': client.mapping_mode,
            'bank_id': client.bank_id,
            'bank_name': bank.name if bank else 'Unknown',
            'slot_id': client.physical_slot_id,
            'iccid': slot.iccid if slot else None,
            'imsi': slot.imsi if slot else None,
            'health_status': client.health_status,
            'is_online': is_online,
            'last_heartbeat': client.last_heartbeat,
            'created_at': client.created_at,
            'stats': client.client_stats or {},
            'hardware_info': client.client_hardware_info or {},
            'ip_address': client.client_ip_address,
            'bankd_endpoint': bankd.endpoint if bankd else None
        })
    
    # Get statistics
    total_clients = len(clients)
    online_clients = sum(1 for c in client_data if c['is_online'])
    offline_clients = total_clients - online_clients
    
    return render_template('admin/openwrt_clients.html',
                          clients=client_data,
                          total_clients=total_clients,
                          online_clients=online_clients,
                          offline_clients=offline_clients,
                          status_filter=status_filter,
                          tenant_filter=tenant_filter,
                          mapping_mode_filter=mapping_mode_filter)


@openwrt_clients_bp.route('/<client_id>/details')
@login_required
def client_details(client_id):
    """Get detailed information about a specific client"""
    
    profile = ServiceProfile.query.filter_by(client_id=client_id).first_or_404()
    
    slot = SIMBankSlot.query.filter_by(
        bank_id=profile.bank_id,
        slot_id=profile.physical_slot_id
    ).first()
    
    bank = SIMBank.query.get(profile.bank_id)
    bankd = BankdInstance.query.get(profile.bankd_instance_id)
    
    # Get slot health logs
    from app.main_models import SlotHealthLog
    health_logs = SlotHealthLog.query.filter_by(
        slot_id=slot.id
    ).order_by(desc(SlotHealthLog.event_time)).limit(50).all() if slot else []
    
    # Get KI proxy logs
    from app.main_models import KiProxyLog
    ki_logs = KiProxyLog.query.filter_by(
        service_profile_id=profile.id
    ).order_by(desc(KiProxyLog.timestamp)).limit(50).all()
    
    return render_template('admin/openwrt_client_details.html',
                          profile=profile,
                          slot=slot,
                          bank=bank,
                          bankd=bankd,
                          health_logs=health_logs,
                          ki_logs=ki_logs)


@openwrt_clients_bp.route('/<client_id>/restart', methods=['POST'])
@login_required
def restart_client(client_id):
    """Send restart command to client (future: via command queue)"""
    
    # TODO: Implement command queue system
    # For now, just return success
    
    return jsonify({
        "status": "ok",
        "message": "Restart command queued (feature pending)"
    }), 200


@openwrt_clients_bp.route('/<client_id>/reassign', methods=['POST'])
@login_required
def reassign_slot(client_id):
    """Reassign client to a different slot"""
    
    data = request.get_json()
    new_bank_id = data.get('bank_id')
    new_slot_id = data.get('slot_id')
    
    profile = ServiceProfile.query.filter_by(client_id=client_id).first_or_404()
    
    # Validate new slot is available
    new_slot = SIMBankSlot.query.filter_by(
        bank_id=new_bank_id,
        slot_id=new_slot_id
    ).first()
    
    if not new_slot:
        return jsonify({"status": "error", "message": "Slot not found"}), 404
    
    if new_slot.status != SIMSlotStatusEnum.AVAILABLE and \
       profile.mapping_mode != MappingModeEnum.KI_PROXY_SWSIM.value:
        return jsonify({"status": "error", "message": "Slot not available"}), 400
    
    # Release old slot
    old_slot = SIMBankSlot.query.filter_by(
        bank_id=profile.bank_id,
        slot_id=profile.physical_slot_id
    ).first()
    
    if old_slot:
        if profile.mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value:
            old_slot.virtual_profile_count = max(0, (old_slot.virtual_profile_count or 1) - 1)
        else:
            old_slot.status = SIMSlotStatusEnum.AVAILABLE
    
    # Assign new slot
    if profile.mapping_mode == MappingModeEnum.KI_PROXY_SWSIM.value:
        new_slot.virtual_profile_count = (new_slot.virtual_profile_count or 0) + 1
    else:
        new_slot.status = SIMSlotStatusEnum.ASSIGNED
    
    # Update profile
    profile.bank_id = new_bank_id
    profile.physical_slot_id = new_slot_id
    
    db.session.commit()
    
    # Log audit
    # Note: Consider moving _log_audit to utils module
    from app.routes.api.remsim_api import _log_audit
    _log_audit("reassign_slot", "service_profile", str(profile.profile_id),
               profile.tenant_id, {
                   "client_id": client_id,
                   "old_bank_id": old_slot.bank_id if old_slot else None,
                   "old_slot_id": old_slot.slot_id if old_slot else None,
                   "new_bank_id": new_bank_id,
                   "new_slot_id": new_slot_id
               })
    
    return jsonify({
        "status": "ok",
        "message": "Slot reassigned successfully",
        "new_bank_id": new_bank_id,
        "new_slot_id": new_slot_id
    }), 200
```

**HTML Template** (`app/templates/admin/openwrt_clients.html`):
```html
{% extends "base.html" %}

{% block title %}OpenWRT Clients - IonMesh{% endblock %}

{% block content %}
<div class="container-fluid">
    <div class="row">
        <div class="col-12">
            <h1>OpenWRT Client Management</h1>
            
            <!-- Statistics Cards -->
            <div class="row mb-4">
                <div class="col-md-4">
                    <div class="card bg-primary text-white">
                        <div class="card-body">
                            <h5 class="card-title">Total Clients</h5>
                            <h2>{{ total_clients }}</h2>
                        </div>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card bg-success text-white">
                        <div class="card-body">
                            <h5 class="card-title">Online</h5>
                            <h2>{{ online_clients }}</h2>
                        </div>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card bg-danger text-white">
                        <div class="card-body">
                            <h5 class="card-title">Offline</h5>
                            <h2>{{ offline_clients }}</h2>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Filters -->
            <div class="card mb-4">
                <div class="card-body">
                    <form method="get" class="form-inline">
                        <label class="mr-2">Filter:</label>
                        <select name="status" class="form-control mr-2">
                            <option value="all" {% if status_filter == 'all' %}selected{% endif %}>All</option>
                            <option value="online" {% if status_filter == 'online' %}selected{% endif %}>Online</option>
                            <option value="offline" {% if status_filter == 'offline' %}selected{% endif %}>Offline</option>
                        </select>
                        
                        <select name="mapping_mode" class="form-control mr-2">
                            <option value="">All Modes</option>
                            <option value="ONE_TO_ONE_SWSIM">ONE_TO_ONE_SWSIM</option>
                            <option value="ONE_TO_ONE_VSIM">ONE_TO_ONE_VSIM</option>
                            <option value="KI_PROXY_SWSIM">KI_PROXY_SWSIM</option>
                        </select>
                        
                        <button type="submit" class="btn btn-primary">Apply</button>
                    </form>
                </div>
            </div>
            
            <!-- Clients Table -->
            <div class="card">
                <div class="card-body">
                    <table class="table table-striped table-hover">
                        <thead>
                            <tr>
                                <th>Status</th>
                                <th>Client ID</th>
                                <th>Bank/Slot</th>
                                <th>Mapping Mode</th>
                                <th>ICCID</th>
                                <th>Last Heartbeat</th>
                                <th>Signal</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {% for client in clients %}
                            <tr>
                                <td>
                                    {% if client.is_online %}
                                    <span class="badge badge-success">Online</span>
                                    {% else %}
                                    <span class="badge badge-danger">Offline</span>
                                    {% endif %}
                                </td>
                                <td>
                                    <a href="{{ url_for('openwrt_clients.client_details', client_id=client.client_id) }}">
                                        {{ client.client_id }}
                                    </a>
                                    <br>
                                    <small class="text-muted">{{ client.ip_address or 'N/A' }}</small>
                                </td>
                                <td>
                                    {{ client.bank_name }} ({{ client.bank_id }})<br>
                                    <small class="text-muted">Slot {{ client.slot_id }}</small>
                                </td>
                                <td>{{ client.mapping_mode }}</td>
                                <td>
                                    {{ client.iccid or 'N/A' }}<br>
                                    <small class="text-muted">{{ client.imsi or '' }}</small>
                                </td>
                                <td>
                                    {% if client.last_heartbeat %}
                                    {{ client.last_heartbeat.strftime('%Y-%m-%d %H:%M:%S') }}
                                    {% else %}
                                    <span class="text-muted">Never</span>
                                    {% endif %}
                                </td>
                                <td>
                                    {% if client.stats.signal_rssi %}
                                    {{ client.stats.signal_rssi }} dBm
                                    {% else %}
                                    <span class="text-muted">N/A</span>
                                    {% endif %}
                                </td>
                                <td>
                                    <button class="btn btn-sm btn-primary" onclick="viewDetails('{{ client.client_id }}')">
                                        <i class="fas fa-eye"></i>
                                    </button>
                                    <button class="btn btn-sm btn-warning" onclick="restartClient('{{ client.client_id }}')">
                                        <i class="fas fa-redo"></i>
                                    </button>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
function viewDetails(clientId) {
    window.location.href = '/admin/openwrt-clients/' + clientId + '/details';
}

function restartClient(clientId) {
    if (confirm('Restart client ' + clientId + '?')) {
        fetch('/admin/openwrt-clients/' + clientId + '/restart', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'}
        })
        .then(response => response.json())
        .then(data => {
            alert(data.message);
        });
    }
}
</script>
{% endblock %}
```

---

### 3. OPTIONAL: Prometheus Metrics Endpoint 📈

**Priority**: MEDIUM  
**Effort**: 1 week  
**File**: `app/routes/api/prometheus_exporter.py`

```python
from flask import Blueprint, Response
from app.extensions import db
from app.main_models import ServiceProfile, SIMBank, SIMBankSlot, BankdInstance
from app.enums import ProfileStatusEnum, SIMSlotStatusEnum, StatusEnum
from datetime import datetime, timedelta

prometheus_bp = Blueprint('prometheus', __name__, url_prefix='/metrics')

@prometheus_bp.route('/prometheus')
def prometheus_metrics():
    """
    Export metrics in Prometheus format
    """
    metrics = []
    
    # Count online clients
    cutoff = datetime.utcnow() - timedelta(minutes=5)
    online_clients = ServiceProfile.query.filter(
        ServiceProfile.client_id.isnot(None),
        ServiceProfile.last_heartbeat >= cutoff
    ).count()
    
    offline_clients = ServiceProfile.query.filter(
        ServiceProfile.client_id.isnot(None),
        (ServiceProfile.last_heartbeat < cutoff) | (ServiceProfile.last_heartbeat.is_(None))
    ).count()
    
    metrics.append('# HELP ionmesh_clients_online Number of online OpenWRT clients')
    metrics.append('# TYPE ionmesh_clients_online gauge')
    metrics.append(f'ionmesh_clients_online {online_clients}')
    
    metrics.append('# HELP ionmesh_clients_offline Number of offline OpenWRT clients')
    metrics.append('# TYPE ionmesh_clients_offline gauge')
    metrics.append(f'ionmesh_clients_offline {offline_clients}')
    
    # Bank statistics
    online_banks = SIMBank.query.filter_by(status=StatusEnum.ONLINE).count()
    metrics.append('# HELP ionmesh_banks_online Number of online SIM banks')
    metrics.append('# TYPE ionmesh_banks_online gauge')
    metrics.append(f'ionmesh_banks_online {online_banks}')
    
    # Slot statistics
    available_slots = SIMBankSlot.query.filter_by(status=SIMSlotStatusEnum.AVAILABLE).count()
    assigned_slots = SIMBankSlot.query.filter_by(status=SIMSlotStatusEnum.ASSIGNED).count()
    
    metrics.append('# HELP ionmesh_slots_available Number of available SIM slots')
    metrics.append('# TYPE ionmesh_slots_available gauge')
    metrics.append(f'ionmesh_slots_available {available_slots}')
    
    metrics.append('# HELP ionmesh_slots_assigned Number of assigned SIM slots')
    metrics.append('# TYPE ionmesh_slots_assigned gauge')
    metrics.append(f'ionmesh_slots_assigned {assigned_slots}')
    
    # Per-client metrics
    clients = ServiceProfile.query.filter(
        ServiceProfile.client_id.isnot(None),
        ServiceProfile.last_heartbeat >= cutoff
    ).all()
    
    metrics.append('# HELP ionmesh_client_uptime_seconds Client uptime in seconds')
    metrics.append('# TYPE ionmesh_client_uptime_seconds gauge')
    
    metrics.append('# HELP ionmesh_client_signal_rssi_dbm Signal strength RSSI')
    metrics.append('# TYPE ionmesh_client_signal_rssi_dbm gauge')
    
    for client in clients:
        stats = client.client_stats or {}
        
        # Uptime
        uptime = stats.get('uptime_seconds', 0)
        metrics.append(f'ionmesh_client_uptime_seconds{{client_id="{client.client_id}",tenant_id="{client.tenant_id}"}} {uptime}')
        
        # Signal strength
        rssi = stats.get('signal_rssi', 0)
        if rssi:
            metrics.append(f'ionmesh_client_signal_rssi_dbm{{client_id="{client.client_id}"}} {rssi}')
    
    return Response('\n'.join(metrics) + '\n', mimetype='text/plain; version=0.0.4')
```

---

## Implementation Timeline

### Phase 1: Critical API Endpoints (Week 1-2)
- [ ] `/register-client` endpoint
- [ ] `/heartbeat` endpoint
- [ ] `/unregister/<client_id>` endpoint
- [ ] `/discover` endpoint
- [ ] Database schema migration
- [ ] Unit tests for all endpoints

### Phase 2: Management Dashboard (Week 3-4)
- [ ] Client list view
- [ ] Client details view
- [ ] Slot reassignment UI
- [ ] Real-time status updates
- [ ] Integration tests

### Phase 3: Monitoring & Metrics (Week 5)
- [ ] Prometheus metrics endpoint
- [ ] Grafana dashboard templates
- [ ] Alert rules configuration
- [ ] Documentation

### Phase 4: Advanced Features (Week 6-8)
- [ ] Command queue system
- [ ] Webhook notifications
- [ ] Auto-scaling policies
- [ ] Load testing and optimization

## Testing Strategy

### API Testing
```python
# tests/test_remsim_api.py

def test_register_client():
    response = client.post('/api/backend/v1/remsim/register-client', json={
        'client_id': 'test-router-1',
        'mapping_mode': 'ONE_TO_ONE_SWSIM',
        'tenant_id': 1
    })
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'
    assert 'bank_id' in data
    assert 'slot_id' in data

def test_heartbeat():
    # Register client first
    # ...
    
    response = client.post('/api/backend/v1/remsim/heartbeat', json={
        'client_id': 'test-router-1',
        'status': 'active',
        'stats': {
            'uptime_seconds': 3600,
            'signal_rssi': -75
        }
    })
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'

def test_unregister():
    response = client.delete('/api/backend/v1/remsim/unregister/test-router-1')
    assert response.status_code == 200
```

## Security Considerations

### API Authentication
```python
# Add to remsim_api.py

from functools import wraps
from flask import request, jsonify

def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        api_key = request.headers.get('X-API-Key')
        if not api_key or not verify_api_key(api_key):
            return jsonify({"status": "error", "message": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated_function

@remsim_api_bp.route('/register-client', methods=['POST'])
@require_api_key
def register_remsim_client():
    # ... implementation ...
```

### TLS Configuration
```python
# config.py

class Config:
    # ... existing config ...
    
    # IonMesh API security
    REMSIM_API_KEY_REQUIRED = True
    REMSIM_TLS_VERIFY = True
    REMSIM_TLS_CA_BUNDLE = '/etc/ssl/certs/ca-bundle.crt'
```

## Success Metrics

- ✅ API response time <100ms for 95th percentile
- ✅ Support for 1000+ concurrent clients
- ✅ 99.9% API uptime
- ✅ Zero data loss on client registration
- ✅ Dashboard load time <2 seconds
- ✅ Real-time updates with <1 second latency

---

## Related Documentation

- [ROADMAP.md](../ROADMAP.md) - Overall project roadmap
- [IONMESH-INTEGRATION.md](./IONMESH-INTEGRATION.md) - Integration architecture
- [Q1-PROMETHEUS-METRICS.md](./features/Q1-PROMETHEUS-METRICS.md) - Metrics specification

## Appendix: Complete API Specification

See [IONMESH-API-SPEC.md](./IONMESH-API-SPEC.md) (to be created) for complete API documentation with request/response examples, error codes, and integration guides.

---

**Status**: Ready for Implementation  
**Maintainer**: IonMesh Team  
**Last Updated**: 2025-01-21  
**Version**: 1.0.0
