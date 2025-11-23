-- Copyright (C) 2024 OpenWRT
-- Licensed under GNU General Public License v2

m = Map("remsim", translate("Advanced Settings"),
	translate("Advanced configuration options for osmo-remsim-client"))

-- IonMesh Orchestration
s = m:section(TypedSection, "ionmesh", translate("IonMesh Orchestration"),
	translate("Enable centralized SIM bank management via IonMesh orchestrator"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable IonMesh"),
	translate("Use IonMesh for automatic slot assignment and bankd discovery"))
o.default = "0"
o.rmempty = false

o = s:option(Value, "host", translate("IonMesh Host"),
	translate("IonMesh server hostname or IP address"))
o.datatype = "host"
o.placeholder = "ionmesh.example.com"
o:depends("enabled", "1")

o = s:option(Value, "port", translate("IonMesh Port"),
	translate("IonMesh API port"))
o.datatype = "port"
o.default = "5000"
o:depends("enabled", "1")

o = s:option(Value, "tenant_id", translate("Tenant ID"),
	translate("Tenant ID for multi-tenancy support"))
o.datatype = "uinteger"
o.default = "1"
o:depends("enabled", "1")

o = s:option(ListValue, "mapping_mode", translate("Mapping Mode"),
	translate("SIM slot mapping mode"))
o:value("ONE_TO_ONE_SWSIM", "One-to-One Software SIM")
o:value("ONE_TO_ONE_VSIM", "One-to-One Virtual SIM")
o:value("KI_PROXY_SWSIM", "KI Proxy Software SIM (recommended)")
o.default = "KI_PROXY_SWSIM"
o:depends("enabled", "1")

o = s:option(Value, "mcc_mnc", translate("MCC/MNC"),
	translate("Mobile Country Code and Network Code for carrier-specific routing (e.g., 310410 for AT&T USA)"))
o.placeholder = "310410"
o.rmempty = true
o:depends("enabled", "1")

-- Monitoring Configuration
s = m:section(TypedSection, "monitoring", translate("Monitoring and Statistics"),
	translate("Configure real-time monitoring and statistics collection"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "signal_monitoring", translate("Enable Signal Monitoring"),
	translate("Periodically query modem signal strength"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "signal_interval", translate("Signal Check Interval"),
	translate("How often to check signal strength (in seconds)"))
o.datatype = "range(10,600)"
o.default = "60"
o.placeholder = "60"
o:depends("signal_monitoring", "1")

o = s:option(Value, "stats_interval", translate("Statistics Print Interval"),
	translate("How often to print statistics to log (in seconds, 0=disabled)"))
o.datatype = "uinteger"
o.default = "3600"
o.placeholder = "3600"

o = s:option(Flag, "track_data_usage", translate("Track Data Usage"),
	translate("Monitor data usage per interface (requires additional processing)"))
o.default = "0"

-- Logging and Debug
s = m:section(TypedSection, "logging", translate("Logging and Debug"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "debug", translate("Enable Debug Logging"),
	translate("Enable verbose debug output (increases log size)"))
o.default = "0"

o = s:option(Value, "log_categories", translate("Log Categories"),
	translate("Debug log categories (e.g., DMAIN:DPCU:DST2)"))
o.placeholder = "DMAIN:DPCU"
o:depends("debug", "1")

o = s:option(Flag, "syslog", translate("Log to Syslog"),
	translate("Send logs to system log"))
o.default = "1"

-- Network Routing
s = m:section(TypedSection, "routing", translate("Network Routing"),
	translate("Configure how remsim traffic is routed through modems"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "force_iot_routing", translate("Force IoT Modem for Heartbeat"),
	translate("Route all remsim heartbeat traffic through IoT modem (dual-modem mode only)"))
o.default = "1"
o:depends("modems.dual_modem", "1")

o = s:option(Value, "iot_interface", translate("IoT Modem Interface"),
	translate("Network interface name for IoT modem"))
o.placeholder = "wwan1"
o:depends("force_iot_routing", "1")

-- Event Script
s = m:section(TypedSection, "advanced", translate("Event Handling"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "event_script", translate("Event Script Path"),
	translate("Path to custom event handling script"))
o.placeholder = "/etc/remsim/event-script.sh"
o.rmempty = true

o = s:option(Flag, "keep_running", translate("Keep Running on Error"),
	translate("Continue running even if connection fails"))
o.default = "1"

-- Heartbeat Configuration
s = m:section(TypedSection, "heartbeat", translate("Heartbeat Configuration"),
	translate("Configure client heartbeat settings"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "interval", translate("Heartbeat Interval"),
	translate("Time between heartbeat messages in seconds"))
o.datatype = "range(10,300)"
o.default = "60"
o.rmempty = false

o = s:option(Value, "timeout", translate("Connection Timeout"),
	translate("Maximum time to wait for connection in seconds"))
o.datatype = "range(5,60)"
o.default = "10"
o.rmempty = false

-- Security
s = m:section(TypedSection, "security", translate("Security Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "use_tls", translate("Use TLS/SSL"),
	translate("Encrypt connections to remsim-server (recommended)"))
o.default = "0"

o = s:option(Value, "ca_cert", translate("CA Certificate Path"),
	translate("Path to CA certificate for TLS verification"))
o.placeholder = "/etc/ssl/certs/ca-certificates.crt"
o:depends("use_tls", "1")

o = s:option(Value, "client_cert", translate("Client Certificate"),
	translate("Path to client certificate for mutual TLS"))
o.placeholder = "/etc/remsim/client.crt"
o:depends("use_tls", "1")

o = s:option(Value, "client_key", translate("Client Private Key"),
	translate("Path to client private key"))
o.placeholder = "/etc/remsim/client.key"
o:depends("use_tls", "1")

return m
