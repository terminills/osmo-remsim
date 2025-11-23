/* (C) 2024 OpenWRT Integration
 *
 * All Rights Reserved
 *
 * SPDX-License-Identifier: GPL-2.0+
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

/* OpenWRT-specific remsim-client implementation that integrates with
 * OpenWRT routers, bypasses the router SIM slot, and communicates with
 * the remsim server to handle authentication and SIM traffic including
 * KI proxy support. */

#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#include <signal.h>

#include <osmocom/core/select.h>
#include <osmocom/core/utils.h>
#include <osmocom/core/logging.h>
#include <osmocom/core/msgb.h>
#include <osmocom/core/timer.h>

#include "client.h"
#include "debug.h"
#ifdef ENABLE_IONMESH
#include "ionmesh_integration.h"
#endif

/* OpenWRT GPIO control paths */
#define GPIO_EXPORT_PATH "/sys/class/gpio/export"
#define GPIO_UNEXPORT_PATH "/sys/class/gpio/unexport"
#define GPIO_BASE_PATH "/sys/class/gpio/gpio%d"
#define GPIO_DIRECTION_PATH "/sys/class/gpio/gpio%d/direction"
#define GPIO_VALUE_PATH "/sys/class/gpio/gpio%d/value"

/* Default GPIO pins for SIM switching (can be overridden via config) */
#define DEFAULT_SIM_SWITCH_GPIO 20
#define DEFAULT_MODEM_RESET_GPIO 21

/* Dual-modem configuration defaults */
#define DEFAULT_MODEM1_SIM_SWITCH_GPIO 20
#define DEFAULT_MODEM1_RESET_GPIO 21
#define DEFAULT_MODEM2_SIM_SWITCH_GPIO 22
#define DEFAULT_MODEM2_RESET_GPIO 23

/* Zbtlink ZBT-Z8102AX specific GPIO mappings (MT7981 chipset)
 * Reference: Device Tree Source (DTS) file
 * These can be used via environment variables:
 *   MODEM1_SIM_GPIO=6 MODEM1_RESET_GPIO=4 (for 5G modem 1)
 *   MODEM2_SIM_GPIO=7 MODEM2_RESET_GPIO=5 (for 5G modem 2)
 *   PCIE_POWER_GPIO=3 (PCIe power control for modems)
 */
#define ZBT_Z8102AX_SIM1_GPIO 6
#define ZBT_Z8102AX_SIM2_GPIO 7
#define ZBT_Z8102AX_5G1_POWER_GPIO 4
#define ZBT_Z8102AX_5G2_POWER_GPIO 5
#define ZBT_Z8102AX_PCIE_POWER_GPIO 3

/* Modem configuration for dual-modem setups */
struct modem_config {
	int sim_switch_gpio;
	int reset_gpio;
	char *device_path;
	bool is_primary;  /* true = remsim modem, false = always-on IoT modem */
};

/* Statistics tracking */
struct openwrt_stats {
	time_t start_time;
	uint64_t tpdus_sent;
	uint64_t tpdus_received;
	uint64_t errors;
	uint32_t reconnections;
	uint32_t sim_switches;
	time_t last_signal_check;
	int last_rssi;
	int last_rsrp;
	int last_rsrq;
	int last_sinr;
};

/* OpenWRT-specific state */
struct openwrt_state {
	struct bankd_client *bc;
	
	/* Legacy single modem support */
	int sim_switch_gpio;
	int modem_reset_gpio;
	char *modem_device;
	bool gpio_initialized;
	
	/* Dual-modem configuration */
	bool dual_modem_mode;
	struct modem_config modem1;  /* Primary remsim modem */
	struct modem_config modem2;  /* Always-on IoT modem for connectivity */
	
	/* ATR buffer for SIM card */
	uint8_t atr_buf[ATR_SIZE_MAX];
	uint8_t atr_len;
	
#ifdef ENABLE_IONMESH
	/* IonMesh orchestration */
	struct ionmesh_config *ionmesh_cfg;
	struct ionmesh_assignment ionmesh_assignment;
	bool use_ionmesh;
#endif
	
	/* Modem communication */
	struct osmo_fd modem_ofd;
	bool modem_fd_registered;
	
	/* Statistics and monitoring */
	struct openwrt_stats stats;
	bool signal_monitoring_enabled;
	int signal_check_interval;  /* seconds, 0 = disabled */
	struct osmo_timer_list signal_timer;
};

static struct openwrt_state *g_openwrt_state = NULL;

/* Forward declarations */
static int openwrt_send_tpdu_to_modem(struct openwrt_state *os, const uint8_t *data, size_t len);
static void openwrt_signal_timer_cb(void *data);
static int openwrt_query_signal_strength(struct openwrt_state *os);
static void openwrt_parse_csq_response(struct openwrt_state *os, const char *response);
static void openwrt_print_statistics(struct openwrt_state *os);
static void openwrt_handle_shutdown(int sig);
static void openwrt_handle_print_stats(int sig);

/***********************************************************************
 * GPIO Control Functions
 ***********************************************************************/

static int gpio_export(int gpio)
{
	int fd, rc;
	char buf[16];

	fd = open(GPIO_EXPORT_PATH, O_WRONLY);
	if (fd < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to open GPIO export: %s\n", strerror(errno));
		return -errno;
	}

	snprintf(buf, sizeof(buf), "%d", gpio);
	rc = write(fd, buf, strlen(buf));
	close(fd);

	if (rc < 0 && errno != EBUSY) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to export GPIO %d: %s\n", gpio, strerror(errno));
		return -errno;
	}

	return 0;
}

static int gpio_set_direction(int gpio, const char *direction)
{
	int fd, rc;
	char path[256];

	snprintf(path, sizeof(path), GPIO_DIRECTION_PATH, gpio);
	fd = open(path, O_WRONLY);
	if (fd < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to open GPIO %d direction: %s\n", gpio, strerror(errno));
		return -errno;
	}

	rc = write(fd, direction, strlen(direction));
	close(fd);

	if (rc < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to set GPIO %d direction: %s\n", gpio, strerror(errno));
		return -errno;
	}

	return 0;
}

static int gpio_set_value(int gpio, int value)
{
	int fd, rc;
	char path[256];
	char val_str[2];

	snprintf(path, sizeof(path), GPIO_VALUE_PATH, gpio);
	fd = open(path, O_WRONLY);
	if (fd < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to open GPIO %d value: %s\n", gpio, strerror(errno));
		return -errno;
	}

	snprintf(val_str, sizeof(val_str), "%d", value ? 1 : 0);
	rc = write(fd, val_str, 1);
	close(fd);

	if (rc < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to set GPIO %d value: %s\n", gpio, strerror(errno));
		return -errno;
	}

	LOGP(DMAIN, LOGL_DEBUG, "Set GPIO %d to %d\n", gpio, value);
	return 0;
}

static int openwrt_gpio_init(struct openwrt_state *os)
{
	int rc;

	if (os->gpio_initialized)
		return 0;

	/* Export and configure SIM switch GPIO */
	rc = gpio_export(os->sim_switch_gpio);
	if (rc < 0 && rc != -EBUSY)
		return rc;

	rc = gpio_set_direction(os->sim_switch_gpio, "out");
	if (rc < 0)
		return rc;

	/* Export and configure modem reset GPIO */
	rc = gpio_export(os->modem_reset_gpio);
	if (rc < 0 && rc != -EBUSY)
		return rc;

	rc = gpio_set_direction(os->modem_reset_gpio, "out");
	if (rc < 0)
		return rc;

	os->gpio_initialized = true;
	LOGP(DMAIN, LOGL_INFO, "OpenWRT GPIO initialized (SIM switch: %d, Modem reset: %d)\n",
	     os->sim_switch_gpio, os->modem_reset_gpio);

	return 0;
}

/***********************************************************************
 * Frontend API Implementation
 ***********************************************************************/

int frontend_request_card_insert(struct bankd_client *bc)
{
	struct openwrt_state *os = bc->data;
	int rc;

	LOGP(DMAIN, LOGL_INFO, "Requesting card insert (switching to remote SIM)\n");

	rc = openwrt_gpio_init(os);
	if (rc < 0)
		return rc;

	/* Track SIM switch */
	os->stats.sim_switches++;

	/* Set GPIO to switch to remote SIM (value 1 = remote) */
	return gpio_set_value(os->sim_switch_gpio, 1);
}

int frontend_request_card_remove(struct bankd_client *bc)
{
	struct openwrt_state *os = bc->data;
	int rc;

	LOGP(DMAIN, LOGL_INFO, "Requesting card remove (switching to local SIM)\n");

	rc = openwrt_gpio_init(os);
	if (rc < 0)
		return rc;

	/* Track SIM switch */
	os->stats.sim_switches++;

	/* Set GPIO to switch to local SIM (value 0 = local) */
	return gpio_set_value(os->sim_switch_gpio, 0);
}

int frontend_request_sim_remote(struct bankd_client *bc)
{
	LOGP(DMAIN, LOGL_INFO, "Switching to remote SIM mode\n");
	return frontend_request_card_insert(bc);
}

int frontend_request_sim_local(struct bankd_client *bc)
{
	LOGP(DMAIN, LOGL_INFO, "Switching to local SIM mode\n");
	return frontend_request_card_remove(bc);
}

int frontend_request_modem_reset(struct bankd_client *bc)
{
	struct openwrt_state *os = bc->data;
	int rc;

	LOGP(DMAIN, LOGL_INFO, "Resetting modem\n");

	rc = openwrt_gpio_init(os);
	if (rc < 0)
		return rc;

	/* Pulse reset GPIO: high -> wait -> low */
	rc = gpio_set_value(os->modem_reset_gpio, 1);
	if (rc < 0)
		return rc;

	usleep(500000); /* 500ms */

	rc = gpio_set_value(os->modem_reset_gpio, 0);
	if (rc < 0)
		return rc;

	LOGP(DMAIN, LOGL_INFO, "Modem reset complete\n");
	return 0;
}

int frontend_handle_card2modem(struct bankd_client *bc, const uint8_t *data, size_t len)
{
	struct openwrt_state *os = bc->data;
	int rc;
	
	OSMO_ASSERT(data);
	OSMO_ASSERT(os);

	LOGP(DMAIN, LOGL_DEBUG, "Card->Modem APDU: %s\n", osmo_hexdump(data, len));

	/* Forward the APDU to the modem via AT+CSIM command */
	rc = openwrt_send_tpdu_to_modem(os, data, len);
	
	if (rc == 0) {
		os->stats.tpdus_sent++;
	} else {
		os->stats.errors++;
	}
	
	return rc;
}

int frontend_handle_set_atr(struct bankd_client *bc, const uint8_t *data, size_t len)
{
	struct openwrt_state *os = bc->data;

	OSMO_ASSERT(data);

	if (len > sizeof(os->atr_buf)) {
		LOGP(DMAIN, LOGL_ERROR, "ATR too long: %zu bytes\n", len);
		return -EINVAL;
	}

	memcpy(os->atr_buf, data, len);
	os->atr_len = len;

	LOGP(DMAIN, LOGL_INFO, "SET_ATR: %s\n", osmo_hexdump(data, len));

	/* In a real implementation, this ATR would be provided to the modem
	 * when it requests the SIM card ATR */

	return 0;
}

int frontend_handle_slot_status(struct bankd_client *bc, const SlotPhysStatus_t *sts)
{
	LOGP(DMAIN, LOGL_DEBUG, "Received slot status update\n");
	/* Status updates from the remote SIM slot */
	return 0;
}

int frontend_append_script_env(struct bankd_client *bc, char **env, int idx, size_t max_env)
{
	struct openwrt_state *os = bc->data;

	if (idx >= max_env - 1)
		return idx;

	if (os->modem_device) {
		env[idx] = talloc_asprintf(bc, "OPENWRT_MODEM_DEVICE=%s", os->modem_device);
		if (env[idx])
			idx++;
	}

	return idx;
}

/***********************************************************************
 * Modem Interface Functions
 ***********************************************************************/

/* Convert binary data to hex string for AT+CSIM command
 * Caller must free returned string with talloc_free() */
static char *bin_to_hex_str(void *ctx, const uint8_t *data, size_t len)
{
	char *hex_str;
	size_t i;
	
	if (len > 512) {
		LOGP(DMAIN, LOGL_ERROR, "Data too long for hex conversion: %zu bytes\n", len);
		return NULL;
	}
	
	hex_str = talloc_zero_size(ctx, len * 2 + 1);
	if (!hex_str) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to allocate hex string buffer\n");
		return NULL;
	}
	
	for (i = 0; i < len; i++) {
		snprintf(&hex_str[i * 2], 3, "%02X", data[i]);
	}
	hex_str[len * 2] = '\0';
	
	return hex_str;
}

/* Parse hex string response from AT+CSIM into binary */
static int hex_str_to_bin(const char *hex_str, uint8_t *buf, size_t buf_len)
{
	size_t len = strlen(hex_str);
	size_t i;
	
	if (len % 2 != 0) {
		LOGP(DMAIN, LOGL_ERROR, "Invalid hex string length: %zu\n", len);
		return -EINVAL;
	}
	
	if (len / 2 > buf_len) {
		LOGP(DMAIN, LOGL_ERROR, "Buffer too small for hex string: %zu > %zu\n", len / 2, buf_len);
		return -ENOSPC;
	}
	
	for (i = 0; i < len / 2; i++) {
		if (sscanf(&hex_str[i * 2], "%2hhx", &buf[i]) != 1) {
			LOGP(DMAIN, LOGL_ERROR, "Failed to parse hex string at position %zu\n", i);
			return -EINVAL;
		}
	}
	
	return len / 2;
}

/* Callback for modem file descriptor - handles responses from modem */
static int modem_fd_cb(struct osmo_fd *ofd, unsigned int what)
{
	struct openwrt_state *os = ofd->data;
	struct bankd_client *bc = os->bc;
	char buf[2048];
	int rc;
	
	if (!(what & OSMO_FD_READ))
		return 0;
	
	rc = read(ofd->fd, buf, sizeof(buf) - 1);
	if (rc < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to read from modem: %s\n", strerror(errno));
		return rc;
	}
	
	if (rc == 0) {
		LOGP(DMAIN, LOGL_NOTICE, "Modem device closed\n");
		return 0;
	}
	
	/* Ensure buffer is null-terminated, accounting for possible full read */
	if (rc >= sizeof(buf)) {
		rc = sizeof(buf) - 1;
	}
	buf[rc] = '\0';
	
	LOGP(DMAIN, LOGL_DEBUG, "Modem response: %s\n", buf);
	
	/* Parse AT+CSQ response for signal strength */
	char *csq_start = strstr(buf, "+CSQ:");
	if (csq_start) {
		openwrt_parse_csq_response(os, csq_start);
	}
	
	/* Parse AT+CSIM response: +CSIM: <length>,"<response>" */
	char *csim_start = strstr(buf, "+CSIM:");
	if (csim_start) {
		int resp_len;
		char hex_resp[1024];
		
		/* Use limited width in sscanf to prevent buffer overflow */
		if (sscanf(csim_start, "+CSIM: %d,\"%1023[^\"]\"", &resp_len, hex_resp) == 2) {
			uint8_t apdu_resp[512];
			int parsed_len;
			
			LOGP(DMAIN, LOGL_DEBUG, "Parsed CSIM response: len=%d, data=%s\n", 
			     resp_len, hex_resp);
			
			parsed_len = hex_str_to_bin(hex_resp, apdu_resp, sizeof(apdu_resp));
			if (parsed_len > 0) {
				struct frontend_tpdu ftpdu = {
					.buf = apdu_resp,
					.len = parsed_len
				};
				
				LOGP(DMAIN, LOGL_INFO, "Forwarding APDU response from modem: %s\n",
				     osmo_hexdump(apdu_resp, parsed_len));
				
				/* Track statistics */
				os->stats.tpdus_received++;
				
				/* Forward APDU response to bankd via main FSM */
				osmo_fsm_inst_dispatch(bc->main_fi, MF_E_MDM_TPDU, &ftpdu);
			}
		}
	}
	
	return 0;
}

static int openwrt_send_tpdu_to_modem(struct openwrt_state *os, const uint8_t *data, size_t len)
{
	char *hex_data;
	char at_cmd[2048];
	size_t at_cmd_len;
	int rc;
	
	LOGP(DMAIN, LOGL_DEBUG, "Sending TPDU to modem: %s\n", osmo_hexdump(data, len));
	
	if (!os->modem_fd_registered) {
		LOGP(DMAIN, LOGL_ERROR, "Modem device not opened, cannot send APDU\n");
		return -ENOTCONN;
	}
	
	/* Convert APDU to hex string */
	hex_data = bin_to_hex_str(os, data, len);
	if (!hex_data) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to convert APDU to hex string\n");
		return -EINVAL;
	}
	
	/* Build AT+CSIM command
	 * Format: AT+CSIM=<length>,"<command>"
	 * Length is the number of characters in the hex string */
	at_cmd_len = snprintf(at_cmd, sizeof(at_cmd), "AT+CSIM=%zu,\"%s\"\r\n", len * 2, hex_data);
	
	/* Free the hex string buffer */
	talloc_free(hex_data);
	
	/* Verify the command fits in the buffer */
	if (at_cmd_len >= sizeof(at_cmd)) {
		LOGP(DMAIN, LOGL_ERROR, "AT command too long: %zu bytes (max %zu)\n", 
		     at_cmd_len, sizeof(at_cmd));
		return -ENOSPC;
	}
	
	LOGP(DMAIN, LOGL_DEBUG, "Sending AT command to modem: %s", at_cmd);
	
	/* Write with retry for partial writes */
	size_t written = 0;
	while (written < at_cmd_len) {
		rc = write(os->modem_ofd.fd, at_cmd + written, at_cmd_len - written);
		if (rc < 0) {
			if (errno == EINTR || errno == EAGAIN) {
				continue;  /* Retry on interrupt or would-block */
			}
			LOGP(DMAIN, LOGL_ERROR, "Failed to write to modem: %s\n", strerror(errno));
			return -errno;
		}
		written += rc;
	}
	
	if (written != at_cmd_len) {
		LOGP(DMAIN, LOGL_ERROR, "Incomplete write to modem: %zu/%zu\n", written, at_cmd_len);
		return -EIO;
	}
	
	LOGP(DMAIN, LOGL_INFO, "Sent APDU to modem via AT+CSIM (length=%zu)\n", len);
	return 0;
}

static int openwrt_open_modem_device(struct openwrt_state *os)
{
	int fd;
	
	if (!os->modem_device) {
		LOGP(DMAIN, LOGL_NOTICE, "No modem device configured, APDU forwarding disabled\n");
		return -ENODEV;
	}
	
	LOGP(DMAIN, LOGL_INFO, "Opening modem device: %s\n", os->modem_device);
	
	fd = open(os->modem_device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to open modem device %s: %s\n",
		     os->modem_device, strerror(errno));
		return -errno;
	}
	
	/* Set up the file descriptor for osmocom select loop */
	osmo_fd_setup(&os->modem_ofd, fd, OSMO_FD_READ, modem_fd_cb, os, 0);
	
	if (osmo_fd_register(&os->modem_ofd) < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to register modem fd with osmocom select\n");
		/* Clean up the osmo_fd structure before closing */
		memset(&os->modem_ofd, 0, sizeof(os->modem_ofd));
		close(fd);
		return -EIO;
	}
	
	os->modem_fd_registered = true;
	LOGP(DMAIN, LOGL_INFO, "Modem device opened successfully: %s (fd=%d)\n",
	     os->modem_device, fd);
	
	return 0;
}

static int openwrt_init_modem(struct openwrt_state *os)
{
	LOGP(DMAIN, LOGL_INFO, "Initializing OpenWRT modem interface\n");

	if (os->dual_modem_mode) {
		LOGP(DMAIN, LOGL_INFO, "Dual-modem mode enabled\n");
		
		/* Initialize modem 1 (primary remsim modem) */
		if (!os->modem1.device_path) {
			if (access("/dev/ttyUSB2", F_OK) == 0) {
				os->modem1.device_path = talloc_strdup(os, "/dev/ttyUSB2");
			} else if (access("/dev/cdc-wdm0", F_OK) == 0) {
				os->modem1.device_path = talloc_strdup(os, "/dev/cdc-wdm0");
			}
		}
		
		/* Initialize modem 2 (always-on IoT modem) */
		if (!os->modem2.device_path) {
			if (access("/dev/ttyUSB5", F_OK) == 0) {
				os->modem2.device_path = talloc_strdup(os, "/dev/ttyUSB5");
			} else if (access("/dev/cdc-wdm1", F_OK) == 0) {
				os->modem2.device_path = talloc_strdup(os, "/dev/cdc-wdm1");
			}
		}
		
		LOGP(DMAIN, LOGL_INFO, "Modem 1 (remsim): %s (GPIO SIM:%d RST:%d)\n",
		     os->modem1.device_path ? os->modem1.device_path : "not detected",
		     os->modem1.sim_switch_gpio, os->modem1.reset_gpio);
		LOGP(DMAIN, LOGL_INFO, "Modem 2 (IoT/heartbeat): %s (GPIO SIM:%d RST:%d)\n",
		     os->modem2.device_path ? os->modem2.device_path : "not detected",
		     os->modem2.sim_switch_gpio, os->modem2.reset_gpio);
		
		/* Ensure IoT modem is using local SIM for connectivity */
		if (os->modem2.sim_switch_gpio > 0) {
			gpio_export(os->modem2.sim_switch_gpio);
			gpio_set_direction(os->modem2.sim_switch_gpio, "out");
			gpio_set_value(os->modem2.sim_switch_gpio, 0);  /* 0 = local IoT SIM */
			LOGP(DMAIN, LOGL_INFO, "IoT modem set to use local SIM for always-on connectivity\n");
		}
		
	} else {
		/* Single modem mode */
		if (!os->modem_device) {
			/* Try to auto-detect modem device */
			if (access("/dev/ttyUSB2", F_OK) == 0) {
				os->modem_device = talloc_strdup(os, "/dev/ttyUSB2");
			} else if (access("/dev/cdc-wdm0", F_OK) == 0) {
				os->modem_device = talloc_strdup(os, "/dev/cdc-wdm0");
			} else {
				LOGP(DMAIN, LOGL_NOTICE, "No modem device auto-detected\n");
			}
		}

		if (os->modem_device) {
			LOGP(DMAIN, LOGL_INFO, "Using modem device: %s\n", os->modem_device);
		}
	}

	/* Open modem device for APDU communication */
	if (os->modem_device) {
		int rc = openwrt_open_modem_device(os);
		if (rc < 0) {
			LOGP(DMAIN, LOGL_NOTICE, "Failed to open modem device for APDU: %d\n", rc);
			LOGP(DMAIN, LOGL_NOTICE, "APDU forwarding will be disabled\n");
		}
	}

	return 0;
}

/***********************************************************************
 * Router-specific configuration
 ***********************************************************************/

/* Detect if running on Zbtlink ZBT-Z8102AX router */
static bool is_zbt_z8102ax(void)
{
	FILE *fp;
	char model[256];
	bool is_zbt = false;
	
	fp = fopen("/tmp/sysinfo/model", "r");
	if (!fp)
		fp = fopen("/proc/device-tree/model", "r");
	
	if (fp) {
		if (fgets(model, sizeof(model), fp)) {
			if (strstr(model, "ZBT-Z8102AX") || strstr(model, "zbt-z8102ax")) {
				is_zbt = true;
			}
		}
		fclose(fp);
	}
	
	return is_zbt;
}

/* Apply ZBT-Z8102AX specific GPIO configuration */
static void apply_zbt_z8102ax_config(struct openwrt_state *os)
{
	LOGP(DMAIN, LOGL_INFO, "Detected Zbtlink ZBT-Z8102AX router - applying specific GPIO configuration\n");
	
	if (os->dual_modem_mode) {
		/* Use ZBT-Z8102AX GPIO mappings for dual-modem setup */
		LOGP(DMAIN, LOGL_INFO, "Applying ZBT-Z8102AX dual-modem GPIO mappings:\n");
		LOGP(DMAIN, LOGL_INFO, "  Modem 1: SIM GPIO=%d, Power GPIO=%d\n",
		     ZBT_Z8102AX_SIM1_GPIO, ZBT_Z8102AX_5G1_POWER_GPIO);
		LOGP(DMAIN, LOGL_INFO, "  Modem 2: SIM GPIO=%d, Power GPIO=%d\n",
		     ZBT_Z8102AX_SIM2_GPIO, ZBT_Z8102AX_5G2_POWER_GPIO);
		
		/* Apply if not overridden by environment */
		if (!getenv("MODEM1_SIM_GPIO"))
			os->modem1.sim_switch_gpio = ZBT_Z8102AX_SIM1_GPIO;
		if (!getenv("MODEM1_RESET_GPIO"))
			os->modem1.reset_gpio = ZBT_Z8102AX_5G1_POWER_GPIO;
		if (!getenv("MODEM2_SIM_GPIO"))
			os->modem2.sim_switch_gpio = ZBT_Z8102AX_SIM2_GPIO;
		if (!getenv("MODEM2_RESET_GPIO"))
			os->modem2.reset_gpio = ZBT_Z8102AX_5G2_POWER_GPIO;
			
		/* Update legacy variables for compatibility */
		os->sim_switch_gpio = os->modem1.sim_switch_gpio;
		os->modem_reset_gpio = os->modem1.reset_gpio;
	} else {
		/* Single modem mode - use modem 1 GPIOs */
		LOGP(DMAIN, LOGL_INFO, "Applying ZBT-Z8102AX single-modem GPIO mappings:\n");
		LOGP(DMAIN, LOGL_INFO, "  SIM GPIO=%d, Power GPIO=%d\n",
		     ZBT_Z8102AX_SIM1_GPIO, ZBT_Z8102AX_5G1_POWER_GPIO);
		
		os->sim_switch_gpio = ZBT_Z8102AX_SIM1_GPIO;
		os->modem_reset_gpio = ZBT_Z8102AX_5G1_POWER_GPIO;
	}
	
	/* Enable PCIe power for modems if not already done by system */
	int pcie_power_gpio = ZBT_Z8102AX_PCIE_POWER_GPIO;
	gpio_export(pcie_power_gpio);
	gpio_set_direction(pcie_power_gpio, "out");
	gpio_set_value(pcie_power_gpio, 1);  /* Enable PCIe power */
	LOGP(DMAIN, LOGL_INFO, "Enabled PCIe power (GPIO %d) for modems\n", pcie_power_gpio);
}

/***********************************************************************
 * Signal Strength Monitoring
 ***********************************************************************/

/* Query modem signal strength using AT+CSQ command */
static int openwrt_query_signal_strength(struct openwrt_state *os)
{
	char at_cmd[] = "AT+CSQ\r\n";
	int rc;
	
	if (!os->modem_fd_registered) {
		LOGP(DMAIN, LOGL_DEBUG, "Modem device not opened, skipping signal check\n");
		return -ENOTCONN;
	}
	
	LOGP(DMAIN, LOGL_DEBUG, "Querying modem signal strength\n");
	
	rc = write(os->modem_ofd.fd, at_cmd, strlen(at_cmd));
	if (rc < 0) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to query signal strength: %s\n", strerror(errno));
		return -errno;
	}
	
	/* Response will be handled by modem_fd_cb */
	return 0;
}

/* Timer callback for periodic signal strength checks */
static void openwrt_signal_timer_cb(void *data)
{
	struct openwrt_state *os = data;
	
	if (!os->signal_monitoring_enabled)
		return;
	
	/* Query signal strength */
	openwrt_query_signal_strength(os);
	
	/* Reschedule timer */
	if (os->signal_check_interval > 0) {
		osmo_timer_schedule(&os->signal_timer, os->signal_check_interval, 0);
	}
}

/* Parse AT+CSQ response: +CSQ: <rssi>,<ber> */
static void openwrt_parse_csq_response(struct openwrt_state *os, const char *response)
{
	int rssi, ber;
	
	if (sscanf(response, "+CSQ: %d,%d", &rssi, &ber) == 2) {
		/* Convert AT+CSQ rssi (0-31, 99=unknown) to dBm */
		if (rssi >= 0 && rssi <= 31) {
			os->stats.last_rssi = -113 + (rssi * 2);
			LOGP(DMAIN, LOGL_INFO, "Signal strength: RSSI=%d dBm (CSQ=%d, BER=%d)\n",
			     os->stats.last_rssi, rssi, ber);
		} else if (rssi == 99) {
			LOGP(DMAIN, LOGL_DEBUG, "Signal strength unknown\n");
		}
		os->stats.last_signal_check = time(NULL);
	}
}

/***********************************************************************
 * Statistics and Monitoring
 ***********************************************************************/

static void openwrt_print_statistics(struct openwrt_state *os)
{
	time_t uptime = time(NULL) - os->stats.start_time;
	int hours = uptime / 3600;
	int minutes = (uptime % 3600) / 60;
	int seconds = uptime % 60;
	
	LOGP(DMAIN, LOGL_NOTICE, "=== OpenWRT Client Statistics ===\n");
	LOGP(DMAIN, LOGL_NOTICE, "Uptime: %dh %dm %ds\n", hours, minutes, seconds);
	LOGP(DMAIN, LOGL_NOTICE, "TPDUs sent: %lu\n", (unsigned long)os->stats.tpdus_sent);
	LOGP(DMAIN, LOGL_NOTICE, "TPDUs received: %lu\n", (unsigned long)os->stats.tpdus_received);
	LOGP(DMAIN, LOGL_NOTICE, "Errors: %lu\n", (unsigned long)os->stats.errors);
	LOGP(DMAIN, LOGL_NOTICE, "Reconnections: %u\n", os->stats.reconnections);
	LOGP(DMAIN, LOGL_NOTICE, "SIM switches: %u\n", os->stats.sim_switches);
	
	if (os->stats.last_signal_check > 0) {
		LOGP(DMAIN, LOGL_NOTICE, "Last signal RSSI: %d dBm\n", os->stats.last_rssi);
	}
	
	LOGP(DMAIN, LOGL_NOTICE, "=================================\n");
}

/* Signal handler for graceful shutdown */
static struct openwrt_state *g_os_for_signal = NULL;

static void openwrt_handle_shutdown(int sig)
{
	LOGP(DMAIN, LOGL_NOTICE, "Received signal %d, shutting down gracefully\n", sig);
	
	if (g_os_for_signal) {
		openwrt_print_statistics(g_os_for_signal);
		
		/* Switch back to local SIM if in remote mode */
		if (g_os_for_signal->bc) {
			LOGP(DMAIN, LOGL_INFO, "Switching back to local SIM before exit\n");
			frontend_request_sim_local(g_os_for_signal->bc);
		}
	}
	
	exit(0);
}

/* Signal handler for printing statistics on demand */
static void openwrt_handle_print_stats(int sig)
{
	(void)sig;  /* Unused parameter */
	
	if (g_os_for_signal) {
		openwrt_print_statistics(g_os_for_signal);
	}
}

/***********************************************************************
 * Main entry point
 ***********************************************************************/

int client_user_main(struct bankd_client *g_client)
{
	struct openwrt_state *os;

	LOGP(DMAIN, LOGL_INFO, "Starting OpenWRT remsim-client\n");

	os = talloc_zero(g_client, struct openwrt_state);
	if (!os) {
		LOGP(DMAIN, LOGL_FATAL, "Failed to allocate OpenWRT state\n");
		return -ENOMEM;
	}

	os->bc = g_client;
	g_client->data = os;
	g_openwrt_state = os;
	g_os_for_signal = os;

	/* Initialize statistics */
	os->stats.start_time = time(NULL);
	os->stats.tpdus_sent = 0;
	os->stats.tpdus_received = 0;
	os->stats.errors = 0;
	os->stats.reconnections = 0;
	os->stats.sim_switches = 0;
	os->stats.last_signal_check = 0;
	os->stats.last_rssi = 0;

	/* Initialize signal monitoring (can be configured via environment) */
	char *signal_interval = getenv("OPENWRT_SIGNAL_INTERVAL");
	if (signal_interval) {
		os->signal_check_interval = atoi(signal_interval);
		os->signal_monitoring_enabled = (os->signal_check_interval > 0);
	} else {
		/* Default: check signal every 60 seconds */
		os->signal_check_interval = 60;
		os->signal_monitoring_enabled = true;
	}
	
	if (os->signal_monitoring_enabled) {
		LOGP(DMAIN, LOGL_INFO, "Signal monitoring enabled (interval: %d seconds)\n",
		     os->signal_check_interval);
		osmo_timer_setup(&os->signal_timer, openwrt_signal_timer_cb, os);
	}

	/* Set up signal handlers for graceful shutdown
	 * NOTE: signal() is used here for simplicity. For production use,
	 * sigaction() would be more portable and reliable. */
	signal(SIGINT, openwrt_handle_shutdown);
	signal(SIGTERM, openwrt_handle_shutdown);
	
	/* SIGUSR2 for printing statistics on demand */
	signal(SIGUSR2, openwrt_handle_print_stats);

	/* Check for dual-modem mode via environment variable */
	char *dual_modem = getenv("OPENWRT_DUAL_MODEM");
	if (dual_modem && strcmp(dual_modem, "1") == 0) {
		os->dual_modem_mode = true;
		
		/* Configure modem 1 (primary remsim modem) */
		os->modem1.is_primary = true;
		char *m1_sim_gpio = getenv("MODEM1_SIM_GPIO");
		os->modem1.sim_switch_gpio = m1_sim_gpio ? atoi(m1_sim_gpio) : DEFAULT_MODEM1_SIM_SWITCH_GPIO;
		char *m1_rst_gpio = getenv("MODEM1_RESET_GPIO");
		os->modem1.reset_gpio = m1_rst_gpio ? atoi(m1_rst_gpio) : DEFAULT_MODEM1_RESET_GPIO;
		char *m1_dev = getenv("MODEM1_DEVICE");
		if (m1_dev) {
			os->modem1.device_path = talloc_strdup(os, m1_dev);
		}
		
		/* Configure modem 2 (always-on IoT modem) */
		os->modem2.is_primary = false;
		char *m2_sim_gpio = getenv("MODEM2_SIM_GPIO");
		os->modem2.sim_switch_gpio = m2_sim_gpio ? atoi(m2_sim_gpio) : DEFAULT_MODEM2_SIM_SWITCH_GPIO;
		char *m2_rst_gpio = getenv("MODEM2_RESET_GPIO");
		os->modem2.reset_gpio = m2_rst_gpio ? atoi(m2_rst_gpio) : DEFAULT_MODEM2_RESET_GPIO;
		char *m2_dev = getenv("MODEM2_DEVICE");
		if (m2_dev) {
			os->modem2.device_path = talloc_strdup(os, m2_dev);
		}
		
		LOGP(DMAIN, LOGL_INFO, "Dual-modem configuration detected\n");
		LOGP(DMAIN, LOGL_INFO, "  Modem 1 (remsim): GPIO SIM=%d RST=%d DEV=%s\n",
		     os->modem1.sim_switch_gpio, os->modem1.reset_gpio,
		     os->modem1.device_path ? os->modem1.device_path : "auto");
		LOGP(DMAIN, LOGL_INFO, "  Modem 2 (IoT): GPIO SIM=%d RST=%d DEV=%s\n",
		     os->modem2.sim_switch_gpio, os->modem2.reset_gpio,
		     os->modem2.device_path ? os->modem2.device_path : "auto");
		
		/* Copy modem1 settings to legacy variables for compatibility */
		os->sim_switch_gpio = os->modem1.sim_switch_gpio;
		os->modem_reset_gpio = os->modem1.reset_gpio;
		if (os->modem1.device_path) {
			os->modem_device = os->modem1.device_path;
		}
		
	} else {
		/* Single modem mode (legacy) */
		os->dual_modem_mode = false;
		
		/* Initialize GPIO pins from config or use defaults */
		if (g_client->cfg->usb.vendor_id > 0) {
			/* If USB vendor_id is set, use it as GPIO pin for SIM switch */
			os->sim_switch_gpio = g_client->cfg->usb.vendor_id;
		} else {
			os->sim_switch_gpio = DEFAULT_SIM_SWITCH_GPIO;
		}

		if (g_client->cfg->usb.product_id > 0) {
			/* If USB product_id is set, use it as GPIO pin for modem reset */
			os->modem_reset_gpio = g_client->cfg->usb.product_id;
		} else {
			os->modem_reset_gpio = DEFAULT_MODEM_RESET_GPIO;
		}

		/* Use USB path as modem device if specified */
		if (g_client->cfg->usb.path) {
			os->modem_device = talloc_strdup(os, g_client->cfg->usb.path);
		}
	}

	/* Auto-detect and apply router-specific configuration */
	if (is_zbt_z8102ax()) {
		apply_zbt_z8102ax_config(os);
	}

	openwrt_init_modem(os);

#ifdef ENABLE_IONMESH
	/* Check if IonMesh orchestration is enabled */
	if (g_client->cfg->event_script && strstr(g_client->cfg->event_script, "ionmesh")) {
		os->use_ionmesh = true;
		
		/* Initialize IonMesh configuration */
		os->ionmesh_cfg = ionmesh_config_init(os);
		if (!os->ionmesh_cfg) {
			LOGP(DMAIN, LOGL_ERROR, "Failed to initialize IonMesh config\n");
			return -ENOMEM;
		}
		
		/* Configure IonMesh from environment or defaults */
		char *ionmesh_host = getenv("IONMESH_HOST");
		if (ionmesh_host) {
			talloc_free(os->ionmesh_cfg->host);
			os->ionmesh_cfg->host = talloc_strdup(os->ionmesh_cfg, ionmesh_host);
		}
		
		char *ionmesh_port = getenv("IONMESH_PORT");
		if (ionmesh_port) {
			os->ionmesh_cfg->port = atoi(ionmesh_port);
		}
		
		char *ionmesh_tenant = getenv("IONMESH_TENANT_ID");
		if (ionmesh_tenant) {
			os->ionmesh_cfg->tenant_id = atoi(ionmesh_tenant);
		}
		
		/* Generate client ID from hostname and slot */
		char hostname[256];
		gethostname(hostname, sizeof(hostname));
		os->ionmesh_cfg->client_id = talloc_asprintf(os->ionmesh_cfg, "%s-slot%d",
							     hostname, g_client->cfg->client_slot);
		
		/* Set mapping mode from config or default to ONE_TO_ONE_SWSIM */
		char *mapping_mode = getenv("IONMESH_MAPPING_MODE");
		if (mapping_mode) {
			talloc_free(os->ionmesh_cfg->mapping_mode);
			os->ionmesh_cfg->mapping_mode = talloc_strdup(os->ionmesh_cfg, mapping_mode);
		}
		
		/* Set MCC/MNC if specified */
		char *mcc_mnc = getenv("IONMESH_MCC_MNC");
		if (mcc_mnc) {
			os->ionmesh_cfg->mcc_mnc = talloc_strdup(os->ionmesh_cfg, mcc_mnc);
		}
		
		LOGP(DMAIN, LOGL_INFO, "IonMesh orchestration enabled\n");
		LOGP(DMAIN, LOGL_INFO, "  Host: %s:%d\n", os->ionmesh_cfg->host, os->ionmesh_cfg->port);
		LOGP(DMAIN, LOGL_INFO, "  Tenant: %d, Client: %s\n", 
		     os->ionmesh_cfg->tenant_id, os->ionmesh_cfg->client_id);
		LOGP(DMAIN, LOGL_INFO, "  Mapping mode: %s\n", os->ionmesh_cfg->mapping_mode);
		
		/* Register with IonMesh to get slot assignment */
		int rc = ionmesh_register_client(os->ionmesh_cfg, &os->ionmesh_assignment);
		if (rc < 0) {
			LOGP(DMAIN, LOGL_ERROR, "Failed to register with IonMesh: %d\n", rc);
			LOGP(DMAIN, LOGL_NOTICE, "Falling back to configured server connection\n");
			os->use_ionmesh = false;
		} else {
			/* Update client configuration with IonMesh assignment */
			LOGP(DMAIN, LOGL_INFO, "IonMesh assigned: Bank %d, Slot %d\n",
			     os->ionmesh_assignment.bank_id, os->ionmesh_assignment.slot_id);
			
			/* Override server host with bankd from IonMesh */
			talloc_free(g_client->cfg->server_host);
			g_client->cfg->server_host = talloc_strdup(g_client->cfg, 
								   os->ionmesh_assignment.bankd_host);
			g_client->cfg->server_port = os->ionmesh_assignment.bankd_port;
			
			/* Update client slot from IonMesh assignment */
			remsim_client_set_clslot(g_client, 
						 os->ionmesh_assignment.bank_id,
						 os->ionmesh_assignment.slot_id);
		}
	}
#endif

	LOGP(DMAIN, LOGL_INFO, "OpenWRT client initialized (GPIO SIM: %d, GPIO Reset: %d)\n",
	     os->sim_switch_gpio, os->modem_reset_gpio);

	/* Start signal monitoring timer if enabled */
	if (os->signal_monitoring_enabled && os->signal_check_interval > 0) {
		osmo_timer_schedule(&os->signal_timer, os->signal_check_interval, 0);
	}

	/* Statistics are printed on-demand via SIGUSR2 signal.
	 * Automatic periodic printing can be added if needed in the future. */
	LOGP(DMAIN, LOGL_INFO, "Statistics available on demand via SIGUSR2 signal\n");

	/* Run the main event loop */
	while (1) {
		osmo_select_main(0);
	}

#ifdef ENABLE_IONMESH
	/* Cleanup: Unregister from IonMesh */
	if (os->use_ionmesh && os->ionmesh_cfg) {
		ionmesh_unregister_client(os->ionmesh_cfg);
		ionmesh_config_free(os->ionmesh_cfg);
	}
#endif

	return 0;
}
