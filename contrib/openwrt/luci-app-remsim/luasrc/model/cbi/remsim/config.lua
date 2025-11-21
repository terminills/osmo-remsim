-- Copyright (C) 2024 OpenWRT
-- Licensed under GNU General Public License v2

local sys = require "luci.sys"
local util = require "luci.util"

m = Map("remsim", translate("Remote SIM Configuration"),
	translate("Configure osmo-remsim-client for remote SIM card management. " ..
	"This allows your router to use virtual SIM cards (vSIM) managed by a " ..
	"central remsim-server and SIM bank infrastructure."))

-- Service Control Section
s = m:section(TypedSection, "service", translate("Service Control"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable Service"),
	translate("Start osmo-remsim-client service on boot"))
o.default = "0"
o.rmempty = false

-- Client Configuration Section
s = m:section(TypedSection, "client", translate("Client Configuration"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "client_id", translate("Client ID"),
	translate("Unique identifier for this client (0-1023). " ..
	"Leave empty for auto-generation from hostname."))
o.datatype = "range(0,1023)"
o.placeholder = "auto"
o.rmempty = true

o = s:option(Value, "client_slot", translate("Client Slot"),
	translate("Slot number for this client (0-1023)"))
o.datatype = "range(0,1023)"
o.default = "0"
o.rmempty = false

-- Server Configuration Section
s = m:section(TypedSection, "server", translate("Server Configuration"),
	translate("Note: When IonMesh orchestration is enabled, server settings " ..
	"will be automatically configured from IonMesh assignment."))
s.anonymous = true
s.addremove = false

o = s:option(Value, "host", translate("Server Host"),
	translate("remsim-server hostname or IP address"))
o.datatype = "host"
o.placeholder = "remsim.example.com"
o.rmempty = false

o = s:option(Value, "port", translate("Server Port"),
	translate("remsim-server TCP port"))
o.datatype = "port"
o.default = "9998"
o.rmempty = false

-- ATR Configuration
o = s:option(Value, "atr", translate("Default ATR"),
	translate("Answer-To-Reset in hex format (optional). " ..
	"Example: 3B9F95801FC78031E073FE211B66D00090004831"))
o.placeholder = "3B00"
o.rmempty = true

o = s:option(Flag, "atr_ignore_rspro", translate("Ignore RSPRO ATR"),
	translate("Ignore ATR from bankd and only use configured default ATR"))
o.default = "0"

return m
