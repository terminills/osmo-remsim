# IonMesh KI Proxy Enhancements

## Overview

This document describes the required enhancements to the IonMesh orchestrator (https://github.com/terminills/ionmesh-fork) to support the new KI Proxy 1-to-many round-robin routing feature in osmo-remsim.

## Background

The KI (Authentication Key) is used during the initial handshake and tower changes in cellular networks. Instead of requiring a unique physical SIM for every modem, the KI Proxy feature allows multiple virtual SIMs to share a pool of physical SIMs that contain the carrier-specific KI keys.

### Key Concepts

1. **KI Proxy Mode**: Authentication requests (RUN GSM ALGORITHM - APDU 0x88) are routed to a pool of physical SIMs containing the actual KI keys
2. **1-to-Many Round-Robin**: Multiple virtual SIMs share a pool of physical KI SIMs using round-robin load balancing
3. **Carrier-Specific Pools**: Each carrier (AT&T, Verizon, T-Mobile, etc.) has its own pool of KI SIMs
4. **Slot Ranges**: Example: AT&T uses slots 1-50, Verizon uses slots 51-100

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    IonMesh Orchestrator                          │
│  (Assignment & Metadata Management)                              │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         Carrier-Specific KI Proxy Pools                │     │
│  │                                                          │     │
│  │  AT&T Pool:      Slots 1-50    (50 physical SIMs)     │     │
│  │  Verizon Pool:   Slots 51-100  (50 physical SIMs)     │     │
│  │  T-Mobile Pool:  Slots 101-150 (50 physical SIMs)     │     │
│  │                                                          │     │
│  │  Each pool can support up to 6000 virtual SIMs         │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         Physical SIM Card Metadata (JSON)              │     │
│  │                                                          │     │
│  │  {                                                       │     │
│  │    "slot_id": 1,                                        │     │
│  │    "bank_id": 1,                                        │     │
│  │    "carrier": "AT&T",                                   │     │
│  │    "mcc_mnc": "310410",                                │     │
│  │    "physical_iccid": "89014103211234567890",           │     │
│  │    "physical_imsi": "310410123456789",                 │     │
│  │    "card_type": "KI_PROXY_MASTER",                     │     │
│  │    "ki_pool_name": "ATT_KI_POOL_1"                     │     │
│  │  }                                                       │     │
│  └────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ REST API
                              │ (Assignment only)
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │ Client 1 │        │ Client 2 │        │ Client N │
    │ Virtual  │        │ Virtual  │        │ Virtual  │
    │ Slot 999 │        │ Slot 998 │        │ Slot 997 │
    └──────────┘        └──────────┘        └──────────┘
          │                   │                   │
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                              │ RSPRO Protocol
                              │ (Client knows only its virtual slot)
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    remsim-server                                 │
│  (Client-to-Bankd Mapping & Coordination)                        │
│                                                                   │
│  Maps: Client Virtual Slot → Bankd Bank/Slot                    │
│  For KI Proxy: Coordinates with bankd for KI routing            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ RSPRO Protocol
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Bankd                                    │
│  (Physical SIM Access & KI Proxy Routing)                        │
│                                                                   │
│  ┌────────────────────────────────────────────────────────┐     │
│  │              KI Proxy Round-Robin Engine               │     │
│  │                                                          │     │
│  │  When APDU 0x88 (RUN GSM ALGORITHM) detected:          │     │
│  │                                                          │     │
│  │  1. Check carrier/pool for this virtual slot           │     │
│  │  2. Select next physical slot from pool (round-robin)  │     │
│  │  3. Route authentication to physical KI slot           │     │
│  │  4. Return response to client                          │     │
│  │                                                          │     │
│  │  Pool: Slots 1-50 → Next: 23 → Next: 24 → Next: 25... │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                   │
│  Physical SIM Slots:                                             │
│  ┌─────┐ ┌─────┐ ┌─────┐     ┌──────┐ ┌──────┐                │
│  │Slot1│ │Slot2│ │Slot3│ ... │Slot50│ │Slot51│ ...             │
│  │AT&T │ │AT&T │ │AT&T │     │AT&T  │ │Vrzn  │                │
│  └─────┘ └─────┘ └─────┘     └──────┘ └──────┘                │
└─────────────────────────────────────────────────────────────────┘

Key Points:
- Client only knows: "I'm virtual slot 999 with virtual ICCID/IMSI"
- IonMesh assigns: Virtual slot + tells client which bankd to use
- remsim-server: Maps virtual slot to appropriate bankd
- Bankd: Handles all KI proxy routing internally with round-robin
- Client never knows about KI proxy pools or physical slot routing
```

## Required IonMesh Database Schema Changes

### 1. SIM Card Metadata Table

Add a new table to store physical SIM card information as JSON:

```sql
-- File: ionmesh-fork/migrations/versions/xxx_add_sim_card_metadata.py

CREATE TABLE sim_card_metadata (
    metadata_id SERIAL PRIMARY KEY,
    bank_id INTEGER NOT NULL,
    slot_id INTEGER NOT NULL,
    tenant_id INTEGER REFERENCES resellers(tenant_id),
    
    -- Physical card identifiers
    physical_iccid VARCHAR(32),
    physical_imsi VARCHAR(32),
    
    -- Carrier information
    carrier VARCHAR(50),           -- "AT&T", "Verizon", "T-Mobile", etc.
    mcc_mnc VARCHAR(10),            -- "310410" for AT&T
    
    -- KI Proxy configuration
    card_type VARCHAR(50),          -- "KI_PROXY_MASTER", "REGULAR", "VIRTUAL"
    ki_pool_name VARCHAR(100),      -- "ATT_KI_POOL_1"
    ki_pool_priority INTEGER DEFAULT 0,  -- Higher = more preferred
    
    -- Metadata JSON field for flexible storage
    card_metadata JSONB,            -- Store any additional card info
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    UNIQUE(bank_id, slot_id),
    FOREIGN KEY (bank_id, slot_id) REFERENCES sim_bank_slots(bank_id, slot_id)
);

CREATE INDEX idx_sim_card_carrier ON sim_card_metadata(carrier);
CREATE INDEX idx_sim_card_ki_pool ON sim_card_metadata(ki_pool_name);
CREATE INDEX idx_sim_card_mcc_mnc ON sim_card_metadata(mcc_mnc);
```

### 2. KI Proxy Pool Configuration Table

Add a table to define KI proxy pools:

```sql
-- File: ionmesh-fork/migrations/versions/xxx_add_ki_proxy_pools.py

CREATE TABLE ki_proxy_pools (
    pool_id SERIAL PRIMARY KEY,
    tenant_id INTEGER REFERENCES resellers(tenant_id),
    
    -- Pool identification
    pool_name VARCHAR(100) NOT NULL,    -- "ATT_KI_POOL_1"
    carrier VARCHAR(50) NOT NULL,       -- "AT&T"
    mcc_mnc VARCHAR(10),                -- "310410"
    
    -- Slot range for this pool
    bank_id INTEGER NOT NULL,
    slot_range_start INTEGER NOT NULL,  -- e.g., 1
    slot_range_end INTEGER NOT NULL,    -- e.g., 50
    
    -- Load balancing
    routing_mode VARCHAR(50) DEFAULT 'round-robin',  -- "round-robin", "least-used", "random"
    max_virtual_sims INTEGER DEFAULT 6000,           -- Max virtual SIMs per pool
    current_virtual_sims INTEGER DEFAULT 0,
    
    -- Status
    enabled BOOLEAN DEFAULT TRUE,
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(pool_name, tenant_id)
);

CREATE INDEX idx_ki_proxy_pools_carrier ON ki_proxy_pools(carrier);
CREATE INDEX idx_ki_proxy_pools_mcc_mnc ON ki_proxy_pools(mcc_mnc);
```

### 3. Update ServiceProfile Table

Enhance the existing `service_profile` table with KI proxy fields:

```sql
-- File: ionmesh-fork/migrations/versions/xxx_enhance_service_profile_ki.py

ALTER TABLE service_profile ADD COLUMN ki_proxy_pool_id INTEGER REFERENCES ki_proxy_pools(pool_id);
ALTER TABLE service_profile ADD COLUMN virtual_iccid VARCHAR(32);
ALTER TABLE service_profile ADD COLUMN virtual_imsi VARCHAR(32);
ALTER TABLE service_profile ADD COLUMN uses_ki_proxy BOOLEAN DEFAULT FALSE;
```

## Required IonMesh API Enhancements

### 1. Enhanced Registration API

**File**: `ionmesh-fork/app/routes/api/remsim_api.py`

Update the registration endpoint to support KI proxy slot pools:

```python
@remsim_api_bp.route('/api/backend/v1/remsim/register-client', methods=['POST'])
def register_remsim_client():
    """
    Register an osmo-remsim-client and assign slot or KI proxy pool
    
    Request body:
    {
        "client_id": "openwrt-router1-slot0",
        "mapping_mode": "KI_PROXY_SWSIM",  # or ONE_TO_ONE_SWSIM, ONE_TO_ONE_VSIM
        "mcc_mnc": "310410",  # Required for KI_PROXY_SWSIM
        "carrier": "AT&T",    # Optional: helps pool selection
        "tenant_id": 1
    }
    
    Response for KI_PROXY_SWSIM mode:
    {
        "status": "ok",
        "mapping_mode": "KI_PROXY_SWSIM",
        "bank_id": 1,
        "slot_id": 999,  # Virtual slot ID assigned to this client
        "iccid": "89014103299999999999",  # Virtual ICCID
        "imsi": "310410999999999",  # Virtual IMSI
        "bankd_endpoint": "http://bankd1.example.com:9999"
    }
    
    Note: Client receives a virtual slot ID. The bankd/remsim-server
    handle all KI proxy routing internally. Client is unaware of 
    physical slot pools.
    
    Response for ONE_TO_ONE modes (unchanged):
    {
        "status": "ok",
        "bank_id": 1,
        "slot_id": 42,
        "iccid": "89014103211234567890",
        "imsi": "310410123456789",
        "bankd_endpoint": "http://bankd1.example.com:9999",
        "mapping_mode": "ONE_TO_ONE_SWSIM"
    }
    """
    data = request.get_json()
    client_id = data.get('client_id')
    mapping_mode = data.get('mapping_mode', 'ONE_TO_ONE_SWSIM')
    mcc_mnc = data.get('mcc_mnc')
    carrier = data.get('carrier')
    tenant_id = data.get('tenant_id')
    
    # Validate required fields
    if not client_id or not tenant_id:
        return jsonify({"status": "error", "message": "client_id and tenant_id required"}), 400
    
    if mapping_mode == 'KI_PROXY_SWSIM':
        # KI Proxy mode: assign to a KI proxy pool
        if not mcc_mnc:
            return jsonify({"status": "error", "message": "mcc_mnc required for KI_PROXY_SWSIM mode"}), 400
        
        # Find appropriate KI proxy pool
        pool = find_ki_proxy_pool(tenant_id, mcc_mnc, carrier)
        if not pool:
            return jsonify({"status": "error", "message": "No KI proxy pool available for carrier"}), 404
        
        # Check pool capacity
        if pool.current_virtual_sims >= pool.max_virtual_sims:
            return jsonify({"status": "error", "message": "KI proxy pool at capacity"}), 503
        
        # Assign next available virtual slot from pool
        # Virtual slots are managed by the pool (e.g., 900-999)
        virtual_slot = allocate_next_virtual_slot(pool)
        if not virtual_slot:
            return jsonify({"status": "error", "message": "No virtual slots available in pool"}), 503
        
        # Create virtual profile with assigned slot
        virtual_profile = create_virtual_sim_profile(
            client_id=client_id,
            tenant_id=tenant_id,
            pool_id=pool.pool_id,
            virtual_slot_id=virtual_slot,
            carrier=carrier,
            mcc_mnc=mcc_mnc
        )
        
        # Update pool usage count
        pool.current_virtual_sims += 1
        db.session.commit()
        
        # Return simple assignment - client just knows its virtual slot
        # Bankd/remsim-server handle all routing internally
        return jsonify({
            "status": "ok",
            "mapping_mode": "KI_PROXY_SWSIM",
            "bank_id": pool.bank_id,
            "slot_id": virtual_slot,  # Virtual slot assigned to client
            "iccid": virtual_profile.virtual_iccid,
            "imsi": virtual_profile.virtual_imsi,
            "bankd_endpoint": f"http://{get_bankd_host(pool.bank_id)}:9999"
        }), 200
    else:
        # ONE_TO_ONE mode: existing logic
        result = register_client_one_to_one(
            client_id=client_id,
            mapping_mode=mapping_mode,
            mcc_mnc=mcc_mnc,
            tenant_id=tenant_id
        )
        
        if result.get('status') == 'error':
            return jsonify(result), 400
        
        return jsonify(result), 200


def find_ki_proxy_pool(tenant_id, mcc_mnc, carrier=None):
    """Find the best KI proxy pool for the given carrier/MCC-MNC"""
    query = KIProxyPool.query.filter_by(
        tenant_id=tenant_id,
        enabled=True
    )
    
    # Match by MCC-MNC first
    if mcc_mnc:
        query = query.filter_by(mcc_mnc=mcc_mnc)
    
    # Match by carrier name if provided
    if carrier:
        query = query.filter_by(carrier=carrier)
    
    # Get pool with most capacity
    pool = query.filter(
        KIProxyPool.current_virtual_sims < KIProxyPool.max_virtual_sims
    ).order_by(
        KIProxyPool.current_virtual_sims.asc()
    ).first()
    
    return pool


def create_virtual_sim_profile(client_id, tenant_id, pool_id, carrier, mcc_mnc):
    """Create a virtual SIM profile for KI proxy mode"""
    # Generate virtual ICCID and IMSI
    virtual_iccid = generate_virtual_iccid(carrier, mcc_mnc)
    virtual_imsi = generate_virtual_imsi(mcc_mnc)
    
    profile = ServiceProfile(
        client_id=client_id,
        tenant_id=tenant_id,
        ki_proxy_pool_id=pool_id,
        virtual_iccid=virtual_iccid,
        virtual_imsi=virtual_imsi,
        uses_ki_proxy=True,
        mapping_mode=MappingModeEnum.KI_PROXY_SWSIM.value,
        status=ProfileStatusEnum.ACTIVE
    )
    
    db.session.add(profile)
    db.session.commit()
    
    return profile
```

### 2. SIM Card Metadata API

**File**: `ionmesh-fork/app/routes/api/sim_card_api.py` (NEW FILE)

```python
from flask import Blueprint, request, jsonify
from app.models import SIMCardMetadata, db
from app.auth import require_api_key

sim_card_api_bp = Blueprint('sim_card_api', __name__)


@sim_card_api_bp.route('/api/backend/v1/sim-cards', methods=['GET'])
@require_api_key
def list_sim_cards():
    """
    List all physical SIM cards with their metadata
    
    Query params:
    - carrier: Filter by carrier name
    - ki_pool_name: Filter by KI pool
    - card_type: Filter by card type
    """
    carrier = request.args.get('carrier')
    ki_pool_name = request.args.get('ki_pool_name')
    card_type = request.args.get('card_type')
    
    query = SIMCardMetadata.query
    
    if carrier:
        query = query.filter_by(carrier=carrier)
    if ki_pool_name:
        query = query.filter_by(ki_pool_name=ki_pool_name)
    if card_type:
        query = query.filter_by(card_type=card_type)
    
    cards = query.all()
    
    return jsonify({
        "status": "ok",
        "cards": [card.to_dict() for card in cards]
    }), 200


@sim_card_api_bp.route('/api/backend/v1/sim-cards/<int:bank_id>/<int:slot_id>', methods=['GET'])
@require_api_key
def get_sim_card(bank_id, slot_id):
    """Get metadata for a specific SIM card"""
    card = SIMCardMetadata.query.filter_by(bank_id=bank_id, slot_id=slot_id).first()
    
    if not card:
        return jsonify({"status": "error", "message": "Card not found"}), 404
    
    return jsonify({
        "status": "ok",
        "card": card.to_dict()
    }), 200


@sim_card_api_bp.route('/api/backend/v1/sim-cards', methods=['POST'])
@require_api_key
def create_sim_card():
    """
    Create or update SIM card metadata
    
    Request body:
    {
        "bank_id": 1,
        "slot_id": 1,
        "tenant_id": 1,
        "physical_iccid": "89014103211234567890",
        "physical_imsi": "310410123456789",
        "carrier": "AT&T",
        "mcc_mnc": "310410",
        "card_type": "KI_PROXY_MASTER",
        "ki_pool_name": "ATT_KI_POOL_1",
        "card_metadata": {
            "notes": "AT&T authentication master card",
            "purchase_date": "2024-01-15",
            "vendor": "Carrier Store",
            "plan_type": "Unlimited"
        }
    }
    """
    data = request.get_json()
    
    # Validate required fields
    required = ['bank_id', 'slot_id', 'tenant_id']
    for field in required:
        if field not in data:
            return jsonify({"status": "error", "message": f"{field} is required"}), 400
    
    # Check if card already exists
    card = SIMCardMetadata.query.filter_by(
        bank_id=data['bank_id'],
        slot_id=data['slot_id']
    ).first()
    
    if card:
        # Update existing
        for key, value in data.items():
            if hasattr(card, key):
                setattr(card, key, value)
    else:
        # Create new
        card = SIMCardMetadata(**data)
        db.session.add(card)
    
    db.session.commit()
    
    return jsonify({
        "status": "ok",
        "message": "SIM card metadata saved",
        "card": card.to_dict()
    }), 200


@sim_card_api_bp.route('/api/backend/v1/sim-cards/<int:bank_id>/<int:slot_id>', methods=['DELETE'])
@require_api_key
def delete_sim_card(bank_id, slot_id):
    """Delete SIM card metadata"""
    card = SIMCardMetadata.query.filter_by(bank_id=bank_id, slot_id=slot_id).first()
    
    if not card:
        return jsonify({"status": "error", "message": "Card not found"}), 404
    
    db.session.delete(card)
    db.session.commit()
    
    return jsonify({"status": "ok", "message": "SIM card metadata deleted"}), 200
```

### 3. KI Proxy Pool Management API

**File**: `ionmesh-fork/app/routes/api/ki_proxy_pool_api.py` (NEW FILE)

```python
from flask import Blueprint, request, jsonify
from app.models import KIProxyPool, SIMCardMetadata, db
from app.auth import require_api_key

ki_proxy_pool_api_bp = Blueprint('ki_proxy_pool_api', __name__)


@ki_proxy_pool_api_bp.route('/api/backend/v1/ki-proxy-pools', methods=['GET'])
@require_api_key
def list_ki_proxy_pools():
    """List all KI proxy pools"""
    pools = KIProxyPool.query.all()
    
    return jsonify({
        "status": "ok",
        "pools": [pool.to_dict() for pool in pools]
    }), 200


@ki_proxy_pool_api_bp.route('/api/backend/v1/ki-proxy-pools', methods=['POST'])
@require_api_key
def create_ki_proxy_pool():
    """
    Create a new KI proxy pool
    
    Request body:
    {
        "pool_name": "ATT_KI_POOL_1",
        "carrier": "AT&T",
        "mcc_mnc": "310410",
        "bank_id": 1,
        "slot_range_start": 1,
        "slot_range_end": 50,
        "tenant_id": 1,
        "max_virtual_sims": 6000
    }
    """
    data = request.get_json()
    
    # Validate required fields
    required = ['pool_name', 'carrier', 'bank_id', 'slot_range_start', 'slot_range_end', 'tenant_id']
    for field in required:
        if field not in data:
            return jsonify({"status": "error", "message": f"{field} is required"}), 400
    
    # Validate slot range
    if data['slot_range_start'] > data['slot_range_end']:
        return jsonify({"status": "error", "message": "Invalid slot range"}), 400
    
    # Create pool
    pool = KIProxyPool(**data)
    db.session.add(pool)
    db.session.commit()
    
    return jsonify({
        "status": "ok",
        "message": "KI proxy pool created",
        "pool": pool.to_dict()
    }), 201


@ki_proxy_pool_api_bp.route('/api/backend/v1/ki-proxy-pools/<int:pool_id>', methods=['GET'])
@require_api_key
def get_ki_proxy_pool(pool_id):
    """Get details of a specific KI proxy pool"""
    pool = KIProxyPool.query.get(pool_id)
    
    if not pool:
        return jsonify({"status": "error", "message": "Pool not found"}), 404
    
    # Get all physical SIM cards in this pool
    cards = SIMCardMetadata.query.filter_by(ki_pool_name=pool.pool_name).all()
    
    return jsonify({
        "status": "ok",
        "pool": pool.to_dict(),
        "physical_sims": [card.to_dict() for card in cards],
        "utilization": {
            "current_virtual_sims": pool.current_virtual_sims,
            "max_virtual_sims": pool.max_virtual_sims,
            "usage_percent": (pool.current_virtual_sims / pool.max_virtual_sims * 100) if pool.max_virtual_sims > 0 else 0
        }
    }), 200


@ki_proxy_pool_api_bp.route('/api/backend/v1/ki-proxy-pools/<int:pool_id>', methods=['DELETE'])
@require_api_key
def delete_ki_proxy_pool(pool_id):
    """Delete a KI proxy pool"""
    pool = KIProxyPool.query.get(pool_id)
    
    if not pool:
        return jsonify({"status": "error", "message": "Pool not found"}), 404
    
    # Check if pool is in use
    if pool.current_virtual_sims > 0:
        return jsonify({"status": "error", "message": "Cannot delete pool with active virtual SIMs"}), 409
    
    db.session.delete(pool)
    db.session.commit()
    
    return jsonify({"status": "ok", "message": "KI proxy pool deleted"}), 200
```

## Required IonMesh Model Updates

**File**: `ionmesh-fork/app/models.py`

Add the new model classes:

```python
class SIMCardMetadata(db.Model):
    __tablename__ = 'sim_card_metadata'
    
    metadata_id = db.Column(db.Integer, primary_key=True)
    bank_id = db.Column(db.Integer, nullable=False)
    slot_id = db.Column(db.Integer, nullable=False)
    tenant_id = db.Column(db.Integer, db.ForeignKey('resellers.tenant_id'))
    
    # Physical card identifiers
    physical_iccid = db.Column(db.String(32))
    physical_imsi = db.Column(db.String(32))
    
    # Carrier information
    carrier = db.Column(db.String(50))
    mcc_mnc = db.Column(db.String(10))
    
    # KI Proxy configuration
    card_type = db.Column(db.String(50))  # "KI_PROXY_MASTER", "REGULAR", "VIRTUAL"
    ki_pool_name = db.Column(db.String(100))
    ki_pool_priority = db.Column(db.Integer, default=0)
    
    # Metadata JSON
    card_metadata = db.Column(db.JSON)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def to_dict(self):
        return {
            'metadata_id': self.metadata_id,
            'bank_id': self.bank_id,
            'slot_id': self.slot_id,
            'tenant_id': self.tenant_id,
            'physical_iccid': self.physical_iccid,
            'physical_imsi': self.physical_imsi,
            'carrier': self.carrier,
            'mcc_mnc': self.mcc_mnc,
            'card_type': self.card_type,
            'ki_pool_name': self.ki_pool_name,
            'ki_pool_priority': self.ki_pool_priority,
            'card_metadata': self.card_metadata,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }


class KIProxyPool(db.Model):
    __tablename__ = 'ki_proxy_pools'
    
    pool_id = db.Column(db.Integer, primary_key=True)
    tenant_id = db.Column(db.Integer, db.ForeignKey('resellers.tenant_id'))
    
    # Pool identification
    pool_name = db.Column(db.String(100), nullable=False)
    carrier = db.Column(db.String(50), nullable=False)
    mcc_mnc = db.Column(db.String(10))
    
    # Slot range
    bank_id = db.Column(db.Integer, nullable=False)
    slot_range_start = db.Column(db.Integer, nullable=False)
    slot_range_end = db.Column(db.Integer, nullable=False)
    
    # Load balancing
    routing_mode = db.Column(db.String(50), default='round-robin')
    max_virtual_sims = db.Column(db.Integer, default=6000)
    current_virtual_sims = db.Column(db.Integer, default=0)
    
    # Status
    enabled = db.Column(db.Boolean, default=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def to_dict(self):
        return {
            'pool_id': self.pool_id,
            'tenant_id': self.tenant_id,
            'pool_name': self.pool_name,
            'carrier': self.carrier,
            'mcc_mnc': self.mcc_mnc,
            'bank_id': self.bank_id,
            'slot_range_start': self.slot_range_start,
            'slot_range_end': self.slot_range_end,
            'slot_range': f"{self.slot_range_start}-{self.slot_range_end}",
            'routing_mode': self.routing_mode,
            'max_virtual_sims': self.max_virtual_sims,
            'current_virtual_sims': self.current_virtual_sims,
            'enabled': self.enabled,
            'utilization_percent': (self.current_virtual_sims / self.max_virtual_sims * 100) if self.max_virtual_sims > 0 else 0,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
```

## Example Usage

### 1. Create AT&T KI Proxy Pool

```bash
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/ki-proxy-pools \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{
    "pool_name": "ATT_KI_POOL_1",
    "carrier": "AT&T",
    "mcc_mnc": "310410",
    "bank_id": 1,
    "slot_range_start": 1,
    "slot_range_end": 50,
    "tenant_id": 1,
    "max_virtual_sims": 6000
  }'
```

### 2. Add Physical SIM Card Metadata

```bash
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/sim-cards \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{
    "bank_id": 1,
    "slot_id": 1,
    "tenant_id": 1,
    "physical_iccid": "89014103211234567890",
    "physical_imsi": "310410123456789",
    "carrier": "AT&T",
    "mcc_mnc": "310410",
    "card_type": "KI_PROXY_MASTER",
    "ki_pool_name": "ATT_KI_POOL_1",
    "card_metadata": {
      "notes": "AT&T authentication master card - Slot 1",
      "purchase_date": "2024-01-15",
      "vendor": "AT&T Store",
      "plan_type": "Business Unlimited"
    }
  }'
```

### 3. Register Client with KI Proxy Mode

```bash
curl -X POST http://ionmesh.example.com:5000/api/backend/v1/remsim/register-client \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "openwrt-router-001",
    "mapping_mode": "KI_PROXY_SWSIM",
    "carrier": "AT&T",
    "mcc_mnc": "310410",
    "tenant_id": 1
  }'

# Response:
{
  "status": "ok",
  "mapping_mode": "KI_PROXY_SWSIM",
  "ki_proxy_pool": {
    "pool_name": "ATT_KI_POOL_1",
    "pool_id": 1,
    "slot_range": "1-50",
    "slots": [1, 2, 3, ..., 50],
    "carrier": "AT&T",
    "mcc_mnc": "310410"
  },
  "virtual_profile": {
    "profile_id": "550e8400-e29b-41d4-a716-446655440000",
    "virtual_iccid": "89014103299999999999",
    "virtual_imsi": "310410999999999"
  },
  "bankd_endpoint": "http://bankd1.example.com:9999",
  "bank_id": 1
}
```

## Configuration Example

### bankd Configuration with KI Proxy Pool

```bash
# Start bankd with:
# - Physical KI proxy slots: 1-50 (AT&T physical SIMs with KI)
# - Virtual slot range: 900-999 (100 virtual slots for clients)
# - Round-robin routing from virtual to physical pool

osmo-remsim-bankd \
  -i remsim-server.example.com \
  -p 9998 \
  -b 1 \
  -n 1000 \
  -k \
  -S 1-50 \
  -V 900-999 \
  -C 310410

# How it works:
# - Clients get assigned virtual slots 900-999 by IonMesh
# - When client in slot 900-999 sends auth APDU (0x88)
# - Bankd routes it to physical slots 1-50 (round-robin)
# - Next auth: slot 1, next: slot 2, next: slot 3, etc.

# For multiple carriers, run separate bankd instances:
# Bankd 1: AT&T pool (bank_id=1, physical 1-50, virtual 900-999)
# Bankd 2: Verizon pool (bank_id=2, physical 1-50, virtual 900-999)
```

### OpenWRT Client with KI Proxy

```bash
# Client will receive slot pool from IonMesh
osmo-remsim-client-openwrt \
  -e /etc/remsim/ionmesh-event-script.sh \
  -V 20 -P 21
```

## Implementation Checklist for IonMesh

- [ ] **Database Schema**
  - [ ] Create `sim_card_metadata` table migration
  - [ ] Create `ki_proxy_pools` table migration
  - [ ] Update `service_profile` table with KI proxy fields
  - [ ] Add necessary indexes

- [ ] **API Endpoints**
  - [ ] Update `/api/backend/v1/remsim/register-client` for KI proxy mode
  - [ ] Create SIM card metadata API endpoints (CRUD)
  - [ ] Create KI proxy pool management API endpoints (CRUD)
  - [ ] Add API authentication/authorization

- [ ] **Business Logic**
  - [ ] Implement `find_ki_proxy_pool()` function
  - [ ] Implement `create_virtual_sim_profile()` function
  - [ ] Implement virtual ICCID/IMSI generation
  - [ ] Add pool capacity tracking
  - [ ] Implement round-robin logic (or delegate to bankd)

- [ ] **Web UI (Optional)**
  - [ ] KI proxy pool management dashboard
  - [ ] SIM card metadata editor
  - [ ] Virtual SIM assignment viewer
  - [ ] Pool utilization graphs

- [ ] **Testing**
  - [ ] Unit tests for API endpoints
  - [ ] Integration tests with osmo-remsim-bankd
  - [ ] Load testing with multiple virtual SIMs
  - [ ] Carrier-specific routing validation

- [ ] **Documentation**
  - [ ] API documentation
  - [ ] Deployment guide
  - [ ] Migration guide for existing deployments

## Notes

1. **Backward Compatibility**: The enhanced API maintains backward compatibility with ONE_TO_ONE modes
2. **Scalability**: Each physical SIM in a KI proxy pool can support up to 6000 virtual SIMs (theoretical)
3. **Security**: KI keys never leave the physical SIM cards; only authentication responses are proxied
4. **Flexibility**: Pools can be dynamically created, resized, and reassigned without service interruption
5. **Multi-tenancy**: Each tenant can have their own KI proxy pools for isolation

## Reference

- **IonMesh Fork**: https://github.com/terminills/ionmesh-fork
- **osmo-remsim**: This repository
- **RSPRO Protocol**: Osmocom Remote SIM Protocol
