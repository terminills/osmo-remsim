#!/bin/sh
# OpenWRT event script for osmo-remsim-client-openwrt
# This script handles hardware-specific operations on OpenWRT routers

# Environment variables available:
#	REMSIM_CLIENT_VERSION
#	REMSIM_SERVER_ADDR
#	REMSIM_SERVER_STATE
#	REMSIM_BANKD_ADDR
#	REMSIM_BANKD_STATE
#	REMSIM_CLIENT_SLOT
#	REMSIM_BANKD_SLOT
#	REMSIM_SIM_VCC
#	REMSIM_SIM_RST
#	REMSIM_CAUSE
#	OPENWRT_MODEM_DEVICE

CAUSE="$1"

# Configuration - adjust these for your OpenWRT hardware
SIM_SWITCH_GPIO="${SIM_SWITCH_GPIO:-20}"
MODEM_RESET_GPIO="${MODEM_RESET_GPIO:-21}"
MODEM_DEVICE="${OPENWRT_MODEM_DEVICE:-/dev/ttyUSB2}"

# Logging function
log_message() {
	logger -t remsim-client-openwrt "$1"
	echo "[$(date)] $1"
}

# GPIO control functions
gpio_set() {
	local gpio=$1
	local value=$2
	
	if [ ! -d "/sys/class/gpio/gpio${gpio}" ]; then
		echo "${gpio}" > /sys/class/gpio/export 2>/dev/null || true
		sleep 0.1
	fi
	
	echo "out" > "/sys/class/gpio/gpio${gpio}/direction" 2>/dev/null
	echo "${value}" > "/sys/class/gpio/gpio${gpio}/value" 2>/dev/null
	
	log_message "Set GPIO ${gpio} to ${value}"
}

# Modem control via AT commands
modem_send_at() {
	local cmd="$1"
	if [ -c "${MODEM_DEVICE}" ]; then
		echo -e "${cmd}\r" > "${MODEM_DEVICE}"
		log_message "Sent AT command: ${cmd}"
	else
		log_message "Warning: Modem device ${MODEM_DEVICE} not available"
	fi
}

# Main event handling
case "${CAUSE}" in
	event-server-connect)
		log_message "Connected to remsim-server at ${REMSIM_SERVER_ADDR}"
		;;
		
	event-bankd-connect)
		log_message "Connected to bankd at ${REMSIM_BANKD_ADDR}"
		;;
		
	event-config-bankd)
		log_message "Configured: Client slot ${REMSIM_CLIENT_SLOT} -> Bankd slot ${REMSIM_BANKD_SLOT}"
		;;
		
	event-modem-status)
		log_message "Modem status update: VCC=${REMSIM_SIM_VCC} RST=${REMSIM_SIM_RST}"
		;;
		
	request-card-insert)
		log_message "Switching to remote SIM"
		gpio_set "${SIM_SWITCH_GPIO}" 1
		# Give the modem time to detect the SIM change
		sleep 1
		# Optionally reset modem to force SIM detection
		# modem_send_at "AT+CFUN=1,1"
		;;
		
	request-card-remove)
		log_message "Switching to local SIM"
		gpio_set "${SIM_SWITCH_GPIO}" 0
		sleep 1
		;;
		
	request-modem-reset)
		log_message "Resetting modem"
		# Hardware reset via GPIO
		gpio_set "${MODEM_RESET_GPIO}" 1
		sleep 1
		gpio_set "${MODEM_RESET_GPIO}" 0
		sleep 2
		
		# Or software reset via AT command
		modem_send_at "AT+CFUN=1,1"
		;;
		
	request-sim-remote)
		log_message "Remote SIM mode requested"
		gpio_set "${SIM_SWITCH_GPIO}" 1
		;;
		
	request-sim-local)
		log_message "Local SIM mode requested"
		gpio_set "${SIM_SWITCH_GPIO}" 0
		;;
		
	*)
		log_message "Unknown event: ${CAUSE}"
		;;
esac

exit 0
