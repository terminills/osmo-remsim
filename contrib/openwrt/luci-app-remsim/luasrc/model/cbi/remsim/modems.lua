-- Copyright (C) 2024 OpenWRT
-- Licensed under GNU General Public License v2

m = Map("remsim", translate("Modem Configuration"),
	translate("Configure physical modem settings for SIM switching and control."))

-- Dual-Modem Mode
s = m:section(TypedSection, "modems", translate("Modem Mode"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "dual_modem", translate("Enable Dual-Modem Mode"),
	translate("Use two modems: one for remote SIM (primary) and one with always-on IoT SIM for connectivity heartbeat"))
o.default = "0"
o.rmempty = false

-- Single Modem Configuration
s = m:section(TypedSection, "modems", translate("Single Modem Settings"),
	translate("Configuration for single modem mode"))
s.anonymous = true
s:depends("dual_modem", "0")

o = s:option(Value, "device", translate("Modem Device"),
	translate("Path to modem device"))
o.placeholder = "/dev/ttyUSB2"
o.rmempty = true

o = s:option(Value, "sim_switch_gpio", translate("SIM Switch GPIO"),
	translate("GPIO pin number for SIM switching (0=local, 1=remote)"))
o.datatype = "uinteger"
o.default = "20"

o = s:option(Value, "reset_gpio", translate("Reset GPIO"),
	translate("GPIO pin number for modem reset"))
o.datatype = "uinteger"
o.default = "21"

-- Modem 1 (Primary/Remote SIM)
s = m:section(TypedSection, "modem1", translate("Modem 1 - Primary (Remote SIM)"),
	translate("Primary modem that will use the remote SIM via remsim"))
s.anonymous = true
s:depends("modems.dual_modem", "1")

o = s:option(Value, "device", translate("Device Path"),
	translate("Path to modem 1 device"))
o.placeholder = "/dev/ttyUSB2"
o.rmempty = true

o = s:option(Value, "sim_switch_gpio", translate("SIM Switch GPIO"),
	translate("GPIO pin for modem 1 SIM switching"))
o.datatype = "uinteger"
o.default = "20"

o = s:option(Value, "reset_gpio", translate("Reset GPIO"),
	translate("GPIO pin for modem 1 reset"))
o.datatype = "uinteger"
o.default = "21"

-- Modem 2 (Always-On IoT)
s = m:section(TypedSection, "modem2", translate("Modem 2 - Always-On IoT SIM"),
	translate("Secondary modem with local IoT SIM for maintaining remsim heartbeat"))
s.anonymous = true
s:depends("modems.dual_modem", "1")

o = s:option(Value, "device", translate("Device Path"),
	translate("Path to modem 2 device"))
o.placeholder = "/dev/ttyUSB5"
o.rmempty = true

o = s:option(Value, "sim_switch_gpio", translate("SIM Switch GPIO"),
	translate("GPIO pin for modem 2 SIM switching (always uses local SIM)"))
o.datatype = "uinteger"
o.default = "22"

o = s:option(Value, "reset_gpio", translate("Reset GPIO"),
	translate("GPIO pin for modem 2 reset"))
o.datatype = "uinteger"
o.default = "23"

o = s:option(DummyValue, "_note", translate("Important Note"))
o.rawhtml = true
o.value = [[<div class="alert-message warning">
<strong>⚠️ Critical:</strong> Modem 2 must have a local IoT SIM card installed 
for always-on connectivity. This ensures the remsim heartbeat continues even if 
the primary modem loses signal, preventing vSIM deactivation.
</div>]]

return m
