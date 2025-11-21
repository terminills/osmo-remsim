# Q1 2025: Prometheus Metrics Export

**Feature**: Export metrics in Prometheus format for monitoring integration  
**Priority**: HIGH  
**Effort**: 1-2 weeks  
**Status**: 🔄 Planned  

---

## Overview

Implement a Prometheus metrics exporter for osmo-remsim-client-openwrt, enabling integration with modern monitoring stacks like Prometheus, Grafana, AlertManager, and others. This provides standardized observability for fleet management and proactive monitoring.

## Architecture

```
┌────────────────────────────────────────┐
│    osmo-remsim-client-openwrt          │
│                                        │
│  ┌──────────────────────────────────┐ │
│  │   Metrics Collector              │ │
│  │   • Connection stats             │ │
│  │   • Signal strength              │ │
│  │   • Data usage                   │ │
│  │   • SIM status                   │ │
│  │   • Error counters               │ │
│  └─────────────┬────────────────────┘ │
│                │                       │
│  ┌─────────────▼────────────────────┐ │
│  │   Prometheus Exporter            │ │
│  │   HTTP Server (:9090/metrics)    │ │
│  └──────────────────────────────────┘ │
└────────────────┬───────────────────────┘
                 │ HTTP GET
                 │
┌────────────────▼───────────────────────┐
│         Prometheus Server              │
│         (Scrapes every 15s)            │
└────────────────┬───────────────────────┘
                 │
┌────────────────▼───────────────────────┐
│           Grafana                      │
│     (Visualization & Alerting)         │
└────────────────────────────────────────┘
```

## Metrics Specification

### Connection Metrics

```prometheus
# HELP remsim_connection_status Current connection status (1=connected, 0=disconnected)
# TYPE remsim_connection_status gauge
remsim_connection_status{router_id="router1",modem="primary",interface="wwan0"} 1
remsim_connection_status{router_id="router1",modem="secondary",interface="wwan1"} 1

# HELP remsim_uptime_seconds Time since last restart
# TYPE remsim_uptime_seconds counter
remsim_uptime_seconds{router_id="router1"} 86400

# HELP remsim_connection_duration_seconds Duration of current connection
# TYPE remsim_connection_duration_seconds gauge
remsim_connection_duration_seconds{router_id="router1",modem="primary"} 3600

# HELP remsim_reconnect_count_total Total number of reconnections
# TYPE remsim_reconnect_count_total counter
remsim_reconnect_count_total{router_id="router1",modem="primary"} 5

# HELP remsim_failover_count_total Number of modem failover events
# TYPE remsim_failover_count_total counter
remsim_failover_count_total{router_id="router1",from="primary",to="secondary"} 3
```

### Signal Strength Metrics

```prometheus
# HELP remsim_signal_rssi_dbm Received Signal Strength Indicator
# TYPE remsim_signal_rssi_dbm gauge
remsim_signal_rssi_dbm{router_id="router1",modem="primary",carrier="AT&T"} -75

# HELP remsim_signal_rsrp_dbm Reference Signal Received Power
# TYPE remsim_signal_rsrp_dbm gauge
remsim_signal_rsrp_dbm{router_id="router1",modem="primary",carrier="AT&T"} -95

# HELP remsim_signal_rsrq_db Reference Signal Received Quality
# TYPE remsim_signal_rsrq_db gauge
remsim_signal_rsrq_db{router_id="router1",modem="primary",carrier="AT&T"} -10

# HELP remsim_signal_sinr_db Signal-to-Interference-plus-Noise Ratio
# TYPE remsim_signal_sinr_db gauge
remsim_signal_sinr_db{router_id="router1",modem="primary",carrier="AT&T"} 15

# HELP remsim_signal_quality Signal quality (0-100)
# TYPE remsim_signal_quality gauge
remsim_signal_quality{router_id="router1",modem="primary"} 85
```

### Data Transfer Metrics

```prometheus
# HELP remsim_data_rx_bytes_total Total bytes received
# TYPE remsim_data_rx_bytes_total counter
remsim_data_rx_bytes_total{router_id="router1",interface="wwan0",modem="primary"} 1048576000

# HELP remsim_data_tx_bytes_total Total bytes transmitted
# TYPE remsim_data_tx_bytes_total counter
remsim_data_tx_bytes_total{router_id="router1",interface="wwan0",modem="primary"} 524288000

# HELP remsim_data_rx_rate_bytes_per_second Current receive rate
# TYPE remsim_data_rx_rate_bytes_per_second gauge
remsim_data_rx_rate_bytes_per_second{router_id="router1",interface="wwan0"} 1048576

# HELP remsim_data_tx_rate_bytes_per_second Current transmit rate
# TYPE remsim_data_tx_rate_bytes_per_second gauge
remsim_data_tx_rate_bytes_per_second{router_id="router1",interface="wwan0"} 262144
```

### SIM Metrics

```prometheus
# HELP remsim_sim_slot_active Currently active SIM slot (1=active, 0=inactive)
# TYPE remsim_sim_slot_active gauge
remsim_sim_slot_active{router_id="router1",modem="primary",slot="0",mode="remote"} 1
remsim_sim_slot_active{router_id="router1",modem="secondary",slot="0",mode="local"} 1

# HELP remsim_sim_authentication_success_total Successful SIM authentications
# TYPE remsim_sim_authentication_success_total counter
remsim_sim_authentication_success_total{router_id="router1",modem="primary"} 42

# HELP remsim_sim_authentication_failure_total Failed SIM authentications
# TYPE remsim_sim_authentication_failure_total counter
remsim_sim_authentication_failure_total{router_id="router1",modem="primary"} 0

# HELP remsim_sim_switch_count_total Number of SIM slot switches
# TYPE remsim_sim_switch_count_total counter
remsim_sim_switch_count_total{router_id="router1",modem="primary"} 8
```

### RSPRO Protocol Metrics

```prometheus
# HELP remsim_tpdu_rx_total Total TPDUs received
# TYPE remsim_tpdu_rx_total counter
remsim_tpdu_rx_total{router_id="router1",modem="primary"} 1234

# HELP remsim_tpdu_tx_total Total TPDUs transmitted
# TYPE remsim_tpdu_tx_total counter
remsim_tpdu_tx_total{router_id="router1",modem="primary"} 5678

# HELP remsim_tpdu_error_total TPDU transmission errors
# TYPE remsim_tpdu_error_total counter
remsim_tpdu_error_total{router_id="router1",modem="primary",error_type="timeout"} 2

# HELP remsim_bankd_connection_status Bankd connection status (1=connected, 0=disconnected)
# TYPE remsim_bankd_connection_status gauge
remsim_bankd_connection_status{router_id="router1",bank_id="1",bankd_host="192.168.1.100"} 1

# HELP remsim_bankd_latency_seconds Latency to bankd server
# TYPE remsim_bankd_latency_seconds gauge
remsim_bankd_latency_seconds{router_id="router1",bank_id="1"} 0.035
```

### System Metrics

```prometheus
# HELP remsim_system_cpu_percent CPU usage percentage
# TYPE remsim_system_cpu_percent gauge
remsim_system_cpu_percent{router_id="router1"} 5.2

# HELP remsim_system_memory_bytes Memory usage in bytes
# TYPE remsim_system_memory_bytes gauge
remsim_system_memory_bytes{router_id="router1"} 8388608

# HELP remsim_system_temperature_celsius System temperature
# TYPE remsim_system_temperature_celsius gauge
remsim_system_temperature_celsius{router_id="router1",sensor="cpu"} 45.5
remsim_system_temperature_celsius{router_id="router1",sensor="modem"} 42.0
```

## Implementation

### C Implementation (Embedded Exporter)

```c
// src/openwrt/prometheus_exporter.h

#ifndef PROMETHEUS_EXPORTER_H
#define PROMETHEUS_EXPORTER_H

#include <stdint.h>
#include <stdbool.h>

typedef struct prometheus_metric {
    char *name;
    char *help;
    char *type;  // "counter", "gauge", "histogram"
    double value;
    char *labels;  // "router_id=\"router1\",modem=\"primary\""
} prometheus_metric_t;

// Initialize exporter
int prometheus_exporter_init(int port);

// Update metrics
void prometheus_update_connection_status(const char *modem, bool connected);
void prometheus_update_signal_strength(const char *modem, int rssi, int rsrp, int rsrq, int sinr);
void prometheus_update_data_usage(const char *interface, uint64_t rx_bytes, uint64_t tx_bytes);
void prometheus_increment_counter(const char *name, const char *labels);

// Start HTTP server
int prometheus_exporter_start(void);

#endif
```

```c
// src/openwrt/prometheus_exporter.c

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <microhttpd.h>
#include "prometheus_exporter.h"

#define MAX_METRICS 256
#define EXPORTER_PORT 9090

static prometheus_metric_t metrics[MAX_METRICS];
static int metric_count = 0;
static struct MHD_Daemon *http_daemon = NULL;
static char router_id[64] = "unknown";

// HTTP request handler
static int metrics_handler(void *cls, struct MHD_Connection *connection,
                          const char *url, const char *method,
                          const char *version, const char *upload_data,
                          size_t *upload_data_size, void **con_cls) {
    if (strcmp(url, "/metrics") != 0) {
        return MHD_NO;
    }
    
    // Generate Prometheus exposition format
    char *response_text = calloc(1, 65536);
    int offset = 0;
    
    for (int i = 0; i < metric_count; i++) {
        prometheus_metric_t *m = &metrics[i];
        
        offset += snprintf(response_text + offset, 65536 - offset,
                          "# HELP %s %s\n"
                          "# TYPE %s %s\n"
                          "%s{%s} %.2f\n",
                          m->name, m->help,
                          m->name, m->type,
                          m->name, m->labels, m->value);
    }
    
    struct MHD_Response *response = MHD_create_response_from_buffer(
        strlen(response_text), response_text, MHD_RESPMEM_MUST_FREE);
    
    MHD_add_response_header(response, "Content-Type", "text/plain; version=0.0.4");
    int ret = MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);
    
    return ret;
}

int prometheus_exporter_init(int port) {
    // Get router ID from UCI or hostname
    FILE *fp = popen("uci get system.@system[0].hostname 2>/dev/null", "r");
    if (fp) {
        if (fgets(router_id, sizeof(router_id), fp)) {
            // Remove newline
            router_id[strcspn(router_id, "\n")] = 0;
        }
        pclose(fp);
    }
    
    // Start HTTP server
    http_daemon = MHD_start_daemon(MHD_USE_THREAD_PER_CONNECTION,
                                   port, NULL, NULL,
                                   &metrics_handler, NULL,
                                   MHD_OPTION_END);
    
    if (http_daemon == NULL) {
        fprintf(stderr, "Failed to start Prometheus exporter on port %d\n", port);
        return -1;
    }
    
    printf("Prometheus exporter listening on port %d\n", port);
    return 0;
}

void prometheus_update_connection_status(const char *modem, bool connected) {
    char labels[256];
    snprintf(labels, sizeof(labels), "router_id=\"%s\",modem=\"%s\"", router_id, modem);
    
    // Find or create metric
    for (int i = 0; i < metric_count; i++) {
        if (strcmp(metrics[i].name, "remsim_connection_status") == 0 &&
            strcmp(metrics[i].labels, labels) == 0) {
            metrics[i].value = connected ? 1.0 : 0.0;
            return;
        }
    }
    
    // Create new metric
    if (metric_count < MAX_METRICS) {
        prometheus_metric_t *m = &metrics[metric_count++];
        m->name = strdup("remsim_connection_status");
        m->help = strdup("Current connection status");
        m->type = strdup("gauge");
        m->labels = strdup(labels);
        m->value = connected ? 1.0 : 0.0;
    }
}

void prometheus_update_signal_strength(const char *modem, int rssi, int rsrp, int rsrq, int sinr) {
    char labels[256];
    snprintf(labels, sizeof(labels), "router_id=\"%s\",modem=\"%s\"", router_id, modem);
    
    // Update RSSI
    prometheus_set_gauge("remsim_signal_rssi_dbm", "RSSI in dBm", labels, rssi);
    
    // Update RSRP
    prometheus_set_gauge("remsim_signal_rsrp_dbm", "RSRP in dBm", labels, rsrp);
    
    // Update RSRQ
    prometheus_set_gauge("remsim_signal_rsrq_db", "RSRQ in dB", labels, rsrq);
    
    // Update SINR
    prometheus_set_gauge("remsim_signal_sinr_db", "SINR in dB", labels, sinr);
}
```

### Lua Implementation (Standalone Exporter)

```lua
-- /usr/lib/lua/prometheus_exporter.lua

local socket = require("socket")
local ubus = require("ubus")

local PrometheusExporter = {}
PrometheusExporter.__index = PrometheusExporter

function PrometheusExporter:new(port)
    local self = setmetatable({}, PrometheusExporter)
    self.port = port or 9090
    self.metrics = {}
    return self
end

function PrometheusExporter:set_gauge(name, help, labels, value)
    local key = name .. "{" .. labels .. "}"
    self.metrics[key] = {
        name = name,
        help = help,
        type = "gauge",
        labels = labels,
        value = value
    }
end

function PrometheusExporter:increment_counter(name, help, labels, value)
    local key = name .. "{" .. labels .. "}"
    if not self.metrics[key] then
        self.metrics[key] = {
            name = name,
            help = help,
            type = "counter",
            labels = labels,
            value = 0
        }
    end
    self.metrics[key].value = self.metrics[key].value + (value or 1)
end

function PrometheusExporter:render()
    local output = {}
    local seen_names = {}
    
    for _, metric in pairs(self.metrics) do
        if not seen_names[metric.name] then
            table.insert(output, string.format("# HELP %s %s", metric.name, metric.help))
            table.insert(output, string.format("# TYPE %s %s", metric.name, metric.type))
            seen_names[metric.name] = true
        end
        table.insert(output, string.format("%s{%s} %.2f", metric.name, metric.labels, metric.value))
    end
    
    return table.concat(output, "\n") .. "\n"
end

function PrometheusExporter:collect_metrics()
    local conn = ubus.connect()
    
    -- Get remsim status
    local status = conn:call("remsim", "status", {})
    if status then
        local router_id = self:get_router_id()
        
        -- Connection status
        for modem, info in pairs(status.modems or {}) do
            local labels = string.format('router_id="%s",modem="%s"', router_id, modem)
            self:set_gauge("remsim_connection_status", "Connection status", labels, 
                          info.connected and 1 or 0)
            
            -- Signal strength
            if info.signal then
                self:set_gauge("remsim_signal_rssi_dbm", "RSSI", labels, info.signal.rssi or 0)
                self:set_gauge("remsim_signal_rsrp_dbm", "RSRP", labels, info.signal.rsrp or 0)
                self:set_gauge("remsim_signal_rsrq_db", "RSRQ", labels, info.signal.rsrq or 0)
                self:set_gauge("remsim_signal_sinr_db", "SINR", labels, info.signal.sinr or 0)
            end
        end
        
        -- Data usage
        for iface, stats in pairs(status.interfaces or {}) do
            local labels = string.format('router_id="%s",interface="%s"', router_id, iface)
            self:set_gauge("remsim_data_rx_bytes_total", "RX bytes", labels, stats.rx_bytes or 0)
            self:set_gauge("remsim_data_tx_bytes_total", "TX bytes", labels, stats.tx_bytes or 0)
        end
    end
    
    conn:close()
end

function PrometheusExporter:get_router_id()
    local f = io.popen("uci get system.@system[0].hostname 2>/dev/null")
    local hostname = f:read("*l") or "unknown"
    f:close()
    return hostname
end

function PrometheusExporter:start()
    local server = socket.tcp()
    server:bind("*", self.port)
    server:listen(5)
    server:settimeout(0.1)
    
    print(string.format("Prometheus exporter listening on port %d", self.port))
    
    while true do
        local client = server:accept()
        if client then
            client:settimeout(5)
            local line = client:receive()
            
            if line and line:match("^GET /metrics") then
                self:collect_metrics()
                local metrics = self:render()
                
                local response = "HTTP/1.1 200 OK\r\n" ..
                                "Content-Type: text/plain; version=0.0.4\r\n" ..
                                "Content-Length: " .. #metrics .. "\r\n" ..
                                "\r\n" ..
                                metrics
                
                client:send(response)
            end
            
            client:close()
        end
        
        socket.sleep(0.01)
    end
end

return PrometheusExporter
```

### Integration with osmo-remsim-client

```c
// In src/remsim_client.c

#include "prometheus_exporter.h"

static void update_prometheus_metrics(struct remsim_client *client) {
    // Update connection status
    prometheus_update_connection_status("primary", client->bankd_conn.connected);
    
    // Update signal strength
    if (client->modem.signal_valid) {
        prometheus_update_signal_strength("primary",
            client->modem.rssi,
            client->modem.rsrp,
            client->modem.rsrq,
            client->modem.sinr);
    }
    
    // Update TPDU counters
    prometheus_increment_counter("remsim_tpdu_rx_total", 
                                 "router_id=\"" ROUTER_ID "\",modem=\"primary\"");
    
    // Update data usage
    uint64_t rx_bytes, tx_bytes;
    get_interface_stats("wwan0", &rx_bytes, &tx_bytes);
    prometheus_update_data_usage("wwan0", rx_bytes, tx_bytes);
}

int main(int argc, char **argv) {
    // ... existing initialization ...
    
    // Start Prometheus exporter
    if (prometheus_exporter_init(9090) < 0) {
        fprintf(stderr, "Warning: Failed to start Prometheus exporter\n");
    }
    
    // Main loop
    while (1) {
        // ... existing logic ...
        
        // Update metrics periodically (every 15 seconds)
        static time_t last_update = 0;
        if (time(NULL) - last_update >= 15) {
            update_prometheus_metrics(&g_client);
            last_update = time(NULL);
        }
    }
}
```

## Prometheus Configuration

```yaml
# /etc/prometheus/prometheus.yml

global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'osmo-remsim'
    static_configs:
      - targets:
          - 'router1.example.com:9090'
          - 'router2.example.com:9090'
          - 'router3.example.com:9090'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.*'
        replacement: '$1'
```

## Grafana Dashboard

```json
{
  "dashboard": {
    "title": "osmo-remsim Fleet Overview",
    "panels": [
      {
        "title": "Online Routers",
        "type": "stat",
        "targets": [{
          "expr": "count(remsim_connection_status == 1)"
        }]
      },
      {
        "title": "Signal Strength by Router",
        "type": "graph",
        "targets": [{
          "expr": "remsim_signal_rssi_dbm",
          "legendFormat": "{{router_id}} - {{modem}}"
        }]
      },
      {
        "title": "Data Usage (24h)",
        "type": "graph",
        "targets": [{
          "expr": "increase(remsim_data_rx_bytes_total[24h])",
          "legendFormat": "{{router_id}} RX"
        }, {
          "expr": "increase(remsim_data_tx_bytes_total[24h])",
          "legendFormat": "{{router_id}} TX"
        }]
      },
      {
        "title": "Failover Events",
        "type": "table",
        "targets": [{
          "expr": "remsim_failover_count_total",
          "format": "table"
        }]
      }
    ]
  }
}
```

## Alert Rules

```yaml
# /etc/prometheus/rules/remsim_alerts.yml

groups:
  - name: remsim
    interval: 30s
    rules:
      - alert: RouterOffline
        expr: remsim_connection_status == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Router {{ $labels.router_id }} is offline"
          description: "Router has been offline for more than 5 minutes"
      
      - alert: WeakSignal
        expr: remsim_signal_rssi_dbm < -100
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Weak signal on {{ $labels.router_id }}"
          description: "RSSI is {{ $value }} dBm (threshold: -100 dBm)"
      
      - alert: HighFailoverRate
        expr: rate(remsim_failover_count_total[1h]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High failover rate on {{ $labels.router_id }}"
          description: "Failover rate is {{ $value }} per second"
      
      - alert: AuthenticationFailures
        expr: rate(remsim_sim_authentication_failure_total[5m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "SIM authentication failures on {{ $labels.router_id }}"
          description: "Authentication is failing"
```

## Testing

```bash
# Test metrics endpoint
curl http://router1.example.com:9090/metrics

# Validate Prometheus format
promtool check metrics < metrics.txt

# Test with Prometheus
prometheus --config.file=prometheus.yml --web.listen-address=:9091

# Query metrics
curl 'http://localhost:9091/api/v1/query?query=remsim_connection_status'
```

## Performance Impact

- **CPU**: <1% additional usage
- **Memory**: ~2 MB for exporter
- **Network**: ~5 KB per scrape (every 15s)
- **Storage**: Minimal (metrics stored in RAM)

---

**Related Documents**:
- [ROADMAP.md](../../ROADMAP.md)
- [Q1 Web UI Enhancements](./Q1-WEB-UI-ENHANCEMENTS.md)

**Status**: Ready for implementation  
**Last Updated**: 2025-01-21
