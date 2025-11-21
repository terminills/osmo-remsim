-- Copyright (C) 2024 OpenWRT
-- Licensed under GNU General Public License v2

module("luci.controller.remsim", package.seeall)

function index()
	-- Check if user has admin rights
	if not nixio.fs.access("/etc/config/remsim") then
		return
	end

	-- Main menu entry
	entry({"admin", "services", "remsim"}, alias("admin", "services", "remsim", "config"), _("Remote SIM"), 60).dependent = false
	
	-- Configuration page
	entry({"admin", "services", "remsim", "config"}, cbi("remsim/config"), _("Configuration"), 1)
	
	-- Status page
	entry({"admin", "services", "remsim", "status"}, call("action_status"), _("Status"), 2)
	
	-- Modem configuration
	entry({"admin", "services", "remsim", "modems"}, cbi("remsim/modems"), _("Modems"), 3)
	
	-- Advanced settings
	entry({"admin", "services", "remsim", "advanced"}, cbi("remsim/advanced"), _("Advanced"), 4)
	
	-- Actions
	entry({"admin", "services", "remsim", "action_restart"}, call("action_restart"))
	entry({"admin", "services", "remsim", "action_test"}, call("action_test"))
end

function action_status()
	local util = require "luci.util"
	local sys = require "luci.sys"
	
	luci.template.render("remsim/status", {
		service_status = get_service_status(),
		client_info = get_client_info(),
		modem_status = get_modem_status(),
		ionmesh_status = get_ionmesh_status()
	})
end

function action_restart()
	luci.sys.call("/etc/init.d/remsim restart >/dev/null 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "remsim", "status"))
end

function action_test()
	local result = luci.sys.exec("/usr/bin/remsim-test-connection.sh 2>&1")
	luci.http.prepare_content("text/plain")
	luci.http.write(result)
end

function get_service_status()
	local running = luci.sys.call("pidof osmo-remsim-client-openwrt >/dev/null 2>&1") == 0
	local enabled = luci.sys.call("/etc/init.d/remsim enabled") == 0
	
	return {
		running = running,
		enabled = enabled,
		pid = running and luci.sys.exec("pidof osmo-remsim-client-openwrt"):match("%d+") or nil
	}
end

function get_client_info()
	local uci = require "luci.model.uci".cursor()
	
	return {
		client_id = uci:get("remsim", "client", "client_id") or "unknown",
		client_slot = uci:get("remsim", "client", "client_slot") or "0",
		mapping_mode = uci:get("remsim", "ionmesh", "mapping_mode") or "ONE_TO_ONE_SWSIM",
		dual_modem = uci:get("remsim", "modems", "dual_modem") == "1"
	}
end

function get_modem_status()
	local status = {}
	local uci = require "luci.model.uci".cursor()
	local dual_modem = uci:get("remsim", "modems", "dual_modem") == "1"
	
	if dual_modem then
		status.modem1 = check_modem_device(uci:get("remsim", "modem1", "device"))
		status.modem2 = check_modem_device(uci:get("remsim", "modem2", "device"))
	else
		status.single = check_modem_device(uci:get("remsim", "modems", "device"))
	end
	
	return status
end

function check_modem_device(device)
	if not device or device == "" then
		return { present = false, device = "not configured" }
	end
	
	local present = nixio.fs.access(device)
	local info = "N/A"
	
	if present then
		-- Try to get modem info via AT commands
		local cmd = string.format("echo 'ATI' > %s 2>/dev/null && timeout 1 cat %s 2>/dev/null | head -3", device, device)
		info = luci.sys.exec(cmd) or "Unknown"
	end
	
	return {
		present = present,
		device = device,
		info = info:match("%S") and info or "No response"
	}
end

function get_ionmesh_status()
	local uci = require "luci.model.uci".cursor()
	local enabled = uci:get("remsim", "ionmesh", "enabled") == "1"
	
	if not enabled then
		return { enabled = false }
	end
	
	local host = uci:get("remsim", "ionmesh", "host")
	local port = uci:get("remsim", "ionmesh", "port") or "5000"
	
	-- Try to ping IonMesh API
	local reachable = false
	if host and host ~= "" then
		local cmd = string.format("curl -s -m 2 http://%s:%s/api/backend/v1/remsim/discover >/dev/null 2>&1", host, port)
		reachable = luci.sys.call(cmd) == 0
	end
	
	return {
		enabled = true,
		host = host,
		port = port,
		reachable = reachable
	}
end
