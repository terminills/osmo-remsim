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
	entry({"admin", "services", "remsim", "action_get_stats"}, call("action_get_stats"))
	entry({"admin", "services", "remsim", "action_get_signal"}, call("action_get_signal"))
	entry({"admin", "services", "remsim", "action_print_stats"}, call("action_print_stats"))
end

function action_status()
	local util = require "luci.util"
	local sys = require "luci.sys"
	
	luci.template.render("remsim/status", {
		service_status = get_service_status(),
		client_info = get_client_info(),
		modem_status = get_modem_status(),
		ionmesh_status = get_ionmesh_status(),
		statistics = get_statistics(),
		signal_status = get_signal_status()
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

function get_statistics()
	-- Try to read statistics from syslog (last occurrence)
	local stats = {
		uptime = "N/A",
		tpdus_sent = 0,
		tpdus_received = 0,
		errors = 0,
		reconnections = 0,
		sim_switches = 0,
		available = false
	}
	
	-- Try to parse from logread output
	local log_output = luci.sys.exec("logread | grep 'OpenWRT Client Statistics' -A 7 | tail -8")
	
	if log_output and log_output ~= "" then
		stats.available = true
		
		-- Parse uptime
		local uptime = log_output:match("Uptime: (%d+h %d+m %d+s)")
		if uptime then stats.uptime = uptime end
		
		-- Parse counters
		local tpdus_sent = log_output:match("TPDUs sent: (%d+)")
		if tpdus_sent then stats.tpdus_sent = tonumber(tpdus_sent) end
		
		local tpdus_received = log_output:match("TPDUs received: (%d+)")
		if tpdus_received then stats.tpdus_received = tonumber(tpdus_received) end
		
		local errors = log_output:match("Errors: (%d+)")
		if errors then stats.errors = tonumber(errors) end
		
		local reconnections = log_output:match("Reconnections: (%d+)")
		if reconnections then stats.reconnections = tonumber(reconnections) end
		
		local sim_switches = log_output:match("SIM switches: (%d+)")
		if sim_switches then stats.sim_switches = tonumber(sim_switches) end
	end
	
	-- Try to get process uptime from /proc if PID is available
	local pid_str = luci.sys.exec("pidof osmo-remsim-client-openwrt"):match("%d+")
	local pid = tonumber(pid_str)
	-- Validate PID is numeric and reasonable (1-65535)
	if pid and pid > 0 and pid < 65536 then
		-- Use nixio for safe file reading to avoid command injection
		local nixio = require "nixio"
		local proc_stat_path = "/proc/" .. tostring(pid) .. "/stat"
		local proc_stat_file = nixio.open(proc_stat_path, "r")
		local proc_stat = nil
		if proc_stat_file then
			proc_stat = proc_stat_file:read(2048)
			proc_stat_file:close()
		end
		if proc_stat and proc_stat ~= "" then
			local starttime = proc_stat:match("%d+%s+%S+%s+%S+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
			if starttime then
				local system_uptime = luci.sys.exec("cat /proc/uptime"):match("^(%S+)")
				if system_uptime then
					local hz = 100  -- Typical HZ value
					local uptime_sec = tonumber(system_uptime) - (tonumber(starttime) / hz)
					local hours = math.floor(uptime_sec / 3600)
					local minutes = math.floor((uptime_sec % 3600) / 60)
					local seconds = math.floor(uptime_sec % 60)
					stats.uptime = string.format("%dh %dm %ds", hours, minutes, seconds)
					stats.uptime_seconds = uptime_sec
				end
			end
		end
	end
	
	return stats
end

function get_signal_status()
	local uci = require "luci.model.uci".cursor()
	local signal_enabled = uci:get("remsim", "monitoring", "signal_monitoring") ~= "0"
	local signal_interval = tonumber(uci:get("remsim", "monitoring", "signal_interval")) or 60
	
	local status = {
		enabled = signal_enabled,
		interval = signal_interval,
		last_rssi = nil,
		last_check = nil
	}
	
	-- Try to parse signal strength from recent logs
	local signal_log = luci.sys.exec("logread | grep 'Signal strength: RSSI=' | tail -1")
	if signal_log and signal_log ~= "" then
		local rssi = signal_log:match("RSSI=([%-]?%d+) dBm")
		if rssi then
			status.last_rssi = tonumber(rssi)
		end
		
		-- Try to extract timestamp (syslog format varies)
		local timestamp = signal_log:match("^%w+%s+%d+%s+(%d+:%d+:%d+)")
		if timestamp then
			status.last_check = timestamp
		end
	end
	
	return status
end

function action_get_stats()
	luci.http.prepare_content("application/json")
	local json = require "luci.jsonc"
	luci.http.write(json.stringify(get_statistics()))
end

function action_get_signal()
	luci.http.prepare_content("application/json")
	local json = require "luci.jsonc"
	luci.http.write(json.stringify(get_signal_status()))
end

function action_print_stats()
	-- Send SIGUSR2 signal to print statistics
	local pid_str = luci.sys.exec("pidof osmo-remsim-client-openwrt"):match("%d+")
	local pid = tonumber(pid_str)
	-- Validate PID is numeric and reasonable (1-65535)
	if pid and pid > 0 and pid < 65536 then
		-- Use posix.signal if available, fallback to kill command with validated PID
		local has_posix, posix = pcall(require, "posix.signal")
		if has_posix and posix.kill then
			-- Use posix.kill for safer signal sending
			local ok, err = pcall(posix.kill, pid, posix.SIGUSR2)
			if not ok then
				LOGP(DMAIN, LOGL_ERROR, "Failed to send signal via posix: %s\n", err)
			end
		else
			-- Fallback to shell command with validated numeric PID only
			luci.sys.call("kill -USR2 " .. tostring(pid))
		end
		luci.http.prepare_content("text/plain")
		luci.http.write("Statistics print signal sent. Check logs with: logread | tail -20")
	else
		luci.http.prepare_content("text/plain")
		luci.http.status(503, "Service Not Running")
		luci.http.write("Service is not running")
	end
end
