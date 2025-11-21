# Q1 2025: Web UI Enhancements

**Feature**: Real-time graphs, historical data, and improved monitoring dashboard  
**Priority**: HIGH  
**Effort**: 2-3 weeks  
**Status**: 🔄 Planned  

---

## Overview

Enhance the LuCI web interface with modern visualization capabilities, including real-time graphs, historical data analysis, and an improved user experience for monitoring osmo-remsim deployments.

## Goals

1. **Real-time Visualization**: Live graphs updating without page refresh
2. **Historical Analysis**: 7-30 day data retention with trend analysis
3. **Better UX**: Responsive design, intuitive navigation, mobile-friendly
4. **Actionable Insights**: Alerts, anomaly detection, predictive warnings
5. **Export Capabilities**: Download data for offline analysis

## Technical Architecture

### Component Stack

```
┌──────────────────────────────────────────┐
│         LuCI Web Interface               │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  Frontend (Lua + JavaScript)       │ │
│  │                                    │ │
│  │  ┌──────────┐    ┌──────────────┐ │ │
│  │  │ Chart.js │    │ Real-time    │ │ │
│  │  │ Graphs   │    │ WebSocket    │ │ │
│  │  └──────────┘    └──────────────┘ │ │
│  └────────────────────────────────────┘ │
│                    │                     │
│                    ▼                     │
│  ┌────────────────────────────────────┐ │
│  │  Backend (uhttpd + Lua)            │ │
│  │  • REST API endpoints              │ │
│  │  • WebSocket server                │ │
│  │  • Data aggregation                │ │
│  └────────────────────────────────────┘ │
└──────────────────┬───────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────┐
│      Data Storage Layer                  │
│                                          │
│  ┌────────────┐      ┌────────────────┐ │
│  │ RRDtool    │      │ SQLite         │ │
│  │ (Time      │      │ (Events &      │ │
│  │  series)   │      │  Config)       │ │
│  └────────────┘      └────────────────┘ │
└──────────────────────────────────────────┘
```

### Data Flow

```
Modem/Router Events
       │
       ▼
osmo-remsim-client
       │
       ▼
Event Handler Script ──> RRDtool Update ──> Time-series Database
       │                                            │
       │                                            │
       └────> SQLite Insert ──> Event Log          │
                                     │              │
                                     └──────┬───────┘
                                            │
                                            ▼
                                    Web UI Queries
                                            │
                                            ▼
                                    Render Graphs/Tables
```

## Feature Details

### 1. Real-time Signal Strength Graph

**Display**:
- RSSI (Received Signal Strength Indicator)
- RSRQ (Reference Signal Received Quality)
- SINR (Signal-to-Interference-plus-Noise Ratio)

**Implementation**:
```lua
-- /usr/lib/lua/luci/controller/remsim/graphs.lua

function signal_strength_data()
    local uci = require "luci.model.uci".cursor()
    local rrd = require "rrdtool"
    
    -- Fetch last 1 hour of data
    local data = rrd.fetch({
        file = "/var/lib/remsim/signal.rrd",
        start = os.time() - 3600,
        resolution = 60
    })
    
    return json.encode({
        timestamps = data.timestamps,
        rssi = data.rssi,
        rsrq = data.rsrq,
        sinr = data.sinr
    })
end
```

**JavaScript Chart**:
```javascript
// /www/luci-static/resources/view/remsim/graphs.js

const signalChart = new Chart(ctx, {
    type: 'line',
    data: {
        labels: timestamps,
        datasets: [{
            label: 'RSSI (dBm)',
            data: rssi_data,
            borderColor: 'rgb(255, 99, 132)',
            tension: 0.1
        }, {
            label: 'RSRQ (dB)',
            data: rsrq_data,
            borderColor: 'rgb(54, 162, 235)',
            tension: 0.1
        }, {
            label: 'SINR (dB)',
            data: sinr_data,
            borderColor: 'rgb(75, 192, 192)',
            tension: 0.1
        }]
    },
    options: {
        responsive: true,
        animation: false,
        scales: {
            y: {
                beginAtZero: false
            }
        }
    }
});

// Update every 5 seconds via WebSocket
ws.onmessage = function(event) {
    const newData = JSON.parse(event.data);
    signalChart.data.labels.push(newData.timestamp);
    signalChart.data.datasets[0].data.push(newData.rssi);
    signalChart.data.datasets[1].data.push(newData.rsrq);
    signalChart.data.datasets[2].data.push(newData.sinr);
    
    // Keep only last 60 data points
    if (signalChart.data.labels.length > 60) {
        signalChart.data.labels.shift();
        signalChart.data.datasets.forEach(dataset => dataset.data.shift());
    }
    
    signalChart.update();
};
```

### 2. Data Usage Graphs

**Metrics**:
- Upload/download bandwidth (real-time)
- Daily/weekly/monthly totals
- Per-interface breakdown
- Cost estimation (if configured)

**RRD Database Schema**:
```bash
# Create RRD database for data usage
rrdtool create /var/lib/remsim/data_usage.rrd \
    --start now --step 60 \
    DS:rx_bytes:COUNTER:120:0:U \
    DS:tx_bytes:COUNTER:120:0:U \
    RRA:AVERAGE:0.5:1:1440 \
    RRA:AVERAGE:0.5:5:2016 \
    RRA:AVERAGE:0.5:60:8760 \
    RRA:MAX:0.5:1:1440 \
    RRA:MAX:0.5:5:2016
```

**Update Script**:
```bash
#!/bin/sh
# /usr/lib/remsim/update_data_usage.sh

INTERFACE="wwan0"
RRD_FILE="/var/lib/remsim/data_usage.rrd"

# Get current byte counts from /sys
RX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

# Update RRD
rrdtool update $RRD_FILE N:$RX_BYTES:$TX_BYTES
```

**Cron Job**:
```
* * * * * /usr/lib/remsim/update_data_usage.sh
```

### 3. Connection History Timeline

**Features**:
- Connection/disconnection events
- Modem failover events
- SIM slot switches
- Authentication success/failure
- Color-coded by event type

**Database Schema** (SQLite):
```sql
CREATE TABLE connection_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    event_type TEXT NOT NULL, -- 'connected', 'disconnected', 'failover', 'sim_switch', 'auth_success', 'auth_failure'
    modem TEXT NOT NULL, -- 'primary', 'secondary'
    interface TEXT, -- 'wwan0', 'wwan1'
    details TEXT, -- JSON with additional info
    severity TEXT DEFAULT 'info' -- 'info', 'warning', 'error', 'critical'
);

CREATE INDEX idx_timestamp ON connection_events(timestamp);
CREATE INDEX idx_event_type ON connection_events(event_type);
```

**Event Logging**:
```lua
-- /usr/lib/lua/luci/model/remsim/events.lua

local sqlite3 = require("lsqlite3")

function log_event(event_type, modem, interface, details, severity)
    local db = sqlite3.open("/var/lib/remsim/events.db")
    
    local stmt = db:prepare([[
        INSERT INTO connection_events (timestamp, event_type, modem, interface, details, severity)
        VALUES (?, ?, ?, ?, ?, ?)
    ]])
    
    stmt:bind_values(os.time(), event_type, modem, interface, json.encode(details), severity)
    stmt:step()
    stmt:finalize()
    db:close()
end
```

**Timeline Visualization**:
```javascript
// Timeline using vis.js library
const timeline = new vis.Timeline(container, items, options);

// Fetch events from API
fetch('/cgi-bin/luci/admin/services/remsim/events')
    .then(response => response.json())
    .then(events => {
        const items = events.map(event => ({
            id: event.id,
            content: event.event_type,
            start: new Date(event.timestamp * 1000),
            className: 'event-' + event.severity,
            title: event.details
        }));
        timeline.setItems(items);
    });
```

### 4. Multi-Modem Dashboard

**Layout**:
```
┌────────────────────────────────────────────────────┐
│  Primary Modem (FM350-GL)  │  IoT Modem (850L)    │
├────────────────────────────────────────────────────┤
│  Status: Connected          │  Status: Connected   │
│  Signal: -75 dBm            │  Signal: -82 dBm     │
│  Carrier: AT&T              │  Carrier: T-Mobile   │
│  Data: 1.2 GB / 10 GB       │  Data: 45 MB / 100 MB│
│                             │                      │
│  [Signal Graph]             │  [Signal Graph]      │
│                             │                      │
│  [Switch to Backup]         │  [Force Restart]     │
└────────────────────────────────────────────────────┘
```

**Implementation**:
```html
<!-- /usr/lib/lua/luci/view/remsim/dashboard.htm -->

<div class="cbi-section">
    <div class="cbi-section-node">
        <div class="modem-grid">
            <div class="modem-card primary">
                <h3><%:Primary Modem%></h3>
                <div class="status-indicator <%=primary_status%>">
                    <span class="status-text"><%=primary_status_text%></span>
                </div>
                
                <div class="metric-row">
                    <span class="metric-label"><%:Signal Strength%>:</span>
                    <span class="metric-value"><%=primary_rssi%> dBm</span>
                </div>
                
                <canvas id="primary-signal-chart"></canvas>
                
                <div class="action-buttons">
                    <button class="cbi-button" onclick="switchModem('primary')">
                        <%:Switch to Backup%>
                    </button>
                    <button class="cbi-button" onclick="restartModem('primary')">
                        <%:Restart%>
                    </button>
                </div>
            </div>
            
            <div class="modem-card secondary">
                <!-- Similar structure for secondary modem -->
            </div>
        </div>
    </div>
</div>
```

### 5. Historical Data Analysis

**Features**:
- Selectable time ranges (1h, 6h, 24h, 7d, 30d)
- Comparison mode (compare two time periods)
- Statistical summary (min, max, avg, 95th percentile)
- Anomaly highlighting
- Export to CSV

**Time Range Selector**:
```javascript
const timeRanges = {
    '1h': { duration: 3600, resolution: 60 },
    '6h': { duration: 21600, resolution: 300 },
    '24h': { duration: 86400, resolution: 600 },
    '7d': { duration: 604800, resolution: 3600 },
    '30d': { duration: 2592000, resolution: 14400 }
};

function updateTimeRange(range) {
    const config = timeRanges[range];
    fetchData(config.duration, config.resolution)
        .then(data => updateChart(data));
}
```

**Statistics Panel**:
```javascript
function calculateStats(data) {
    const sorted = [...data].sort((a, b) => a - b);
    
    return {
        min: Math.min(...data),
        max: Math.max(...data),
        avg: data.reduce((a, b) => a + b, 0) / data.length,
        median: sorted[Math.floor(sorted.length / 2)],
        percentile_95: sorted[Math.floor(sorted.length * 0.95)]
    };
}
```

### 6. Alert Configuration

**Features**:
- Configurable thresholds
- Email/SMS/webhook notifications
- Alert history
- Automatic acknowledgment

**Configuration UI**:
```lua
-- Alert configuration
config alert
    option enabled '1'
    option type 'signal_strength'
    option threshold '-90'
    option comparison 'less_than'
    option action 'notify'
    option notify_email 'admin@example.com'
    option notify_webhook 'https://example.com/webhook'
```

## WebSocket Real-time Updates

**Server (uhttpd + Lua)**:
```lua
-- /usr/lib/lua/luci/controller/remsim/websocket.lua

local websocket = require "websocket"
local ubus = require "ubus"

function websocket_handler()
    local conn = ubus.connect()
    
    -- Subscribe to remsim events
    conn:subscribe("remsim", function(msg)
        -- Broadcast to all connected WebSocket clients
        websocket.broadcast(json.encode(msg))
    end)
    
    while true do
        -- Keep connection alive and process events
        conn:poll(1000)
    end
end
```

**Client (JavaScript)**:
```javascript
const ws = new WebSocket('ws://' + window.location.host + '/ws/remsim');

ws.onmessage = function(event) {
    const data = JSON.parse(event.data);
    
    switch(data.type) {
        case 'signal_update':
            updateSignalChart(data);
            break;
        case 'connection_event':
            addEventToTimeline(data);
            break;
        case 'data_usage':
            updateDataUsage(data);
            break;
    }
};

ws.onerror = function(error) {
    console.error('WebSocket error:', error);
    // Fall back to polling
    startPolling();
};
```

## Mobile Responsive Design

**CSS Framework**: Bootstrap or custom responsive CSS

```css
/* /www/luci-static/resources/view/remsim/style.css */

@media (max-width: 768px) {
    .modem-grid {
        grid-template-columns: 1fr;
    }
    
    .metric-row {
        flex-direction: column;
    }
    
    canvas {
        max-height: 200px;
    }
}

@media (min-width: 769px) {
    .modem-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 20px;
    }
}
```

## Export Functionality

**CSV Export**:
```lua
function export_data(start_time, end_time, metrics)
    local csv = "timestamp," .. table.concat(metrics, ",") .. "\n"
    
    local data = fetch_historical_data(start_time, end_time, metrics)
    
    for _, row in ipairs(data) do
        csv = csv .. row.timestamp
        for _, metric in ipairs(metrics) do
            csv = csv .. "," .. row[metric]
        end
        csv = csv .. "\n"
    end
    
    return csv
end
```

**Download Trigger**:
```javascript
function downloadCSV() {
    const range = document.getElementById('time-range').value;
    const metrics = getSelectedMetrics();
    
    fetch(`/cgi-bin/luci/admin/services/remsim/export?range=${range}&metrics=${metrics.join(',')}`)
        .then(response => response.blob())
        .then(blob => {
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `remsim-data-${Date.now()}.csv`;
            a.click();
        });
}
```

## Testing Plan

### Unit Tests
- RRD database operations
- Data aggregation functions
- Alert threshold checking
- Export format validation

### Integration Tests
- WebSocket connection stability
- Real-time update accuracy
- Historical data retrieval
- Multi-client handling

### UI Tests
- Chart rendering performance
- Responsive layout on different devices
- Real-time update smoothness
- Export functionality

### Load Tests
- 100+ concurrent WebSocket connections
- High-frequency data updates (1/second)
- Large historical data queries (30 days)

## Performance Considerations

**Optimization Strategies**:
1. **Data Sampling**: Reduce resolution for older data
2. **Client-side Caching**: Cache historical data in browser
3. **Lazy Loading**: Load graphs only when visible
4. **Compression**: Gzip compress API responses
5. **Database Indexing**: Index frequently queried columns

**Resource Usage Targets**:
- Memory: <10 MB for web UI
- CPU: <5% average utilization
- Disk: <50 MB for 30 days of data
- Network: <100 KB/s per client

## Implementation Checklist

- [ ] Set up RRDtool database schema
- [ ] Create SQLite event database
- [ ] Implement data collection scripts
- [ ] Set up cron jobs for periodic updates
- [ ] Develop Lua backend API endpoints
- [ ] Implement WebSocket server
- [ ] Create Chart.js visualizations
- [ ] Build responsive dashboard layout
- [ ] Add time range selector
- [ ] Implement statistics panel
- [ ] Create event timeline view
- [ ] Add alert configuration UI
- [ ] Implement export functionality
- [ ] Write comprehensive tests
- [ ] Optimize performance
- [ ] Document user guide
- [ ] Create video tutorial

## Dependencies

**Required Packages**:
```bash
opkg install rrdtool
opkg install sqlite3-cli
opkg install luasocket
opkg install lua-cjson
```

**Optional Packages**:
```bash
opkg install node  # For advanced JS bundling
opkg install nginx  # Alternative to uhttpd for WebSockets
```

## Documentation

### User Guide Topics
1. Navigating the enhanced dashboard
2. Reading signal strength graphs
3. Interpreting connection events
4. Setting up alerts
5. Exporting data for analysis
6. Troubleshooting WebSocket issues

### Developer Guide Topics
1. RRDtool database structure
2. Adding new metrics
3. Creating custom graphs
4. Extending the API
5. WebSocket message protocol
6. Theming and customization

## Future Enhancements

- **Predictive Graphs**: Show predicted values based on trends
- **Comparison Mode**: Compare current vs. previous week
- **Custom Dashboards**: User-configurable widget layout
- **Dark Mode**: Alternative color scheme
- **Multiple Language Support**: i18n for different languages
- **Graph Annotations**: Add notes to specific time points
- **Drill-down Views**: Click on graph to see detailed data

## Success Metrics

- **Adoption Rate**: >80% of users enable enhanced UI
- **Performance**: Page load <2 seconds
- **Reliability**: <1% WebSocket disconnections
- **User Satisfaction**: >4.5/5 rating
- **Bug Reports**: <5 critical bugs per month

---

**Related Documents**:
- [ROADMAP.md](../../ROADMAP.md)
- [LuCI Web Interface Guide](../LUCI-WEB-INTERFACE.md)
- [Q1 Prometheus Metrics](./Q1-PROMETHEUS-METRICS.md)

**Status**: Ready for implementation  
**Last Updated**: 2025-01-21
