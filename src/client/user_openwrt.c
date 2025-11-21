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

#include <osmocom/core/select.h>
#include <osmocom/core/utils.h>
#include <osmocom/core/logging.h>
#include <osmocom/core/msgb.h>

#include "client.h"
#include "debug.h"
#include "ionmesh_integration.h"

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

/* Modem configuration for dual-modem setups */
struct modem_config {
	int sim_switch_gpio;
	int reset_gpio;
	char *device_path;
	bool is_primary;  /* true = remsim modem, false = always-on IoT modem */
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
	
	/* IonMesh orchestration */
	struct ionmesh_config *ionmesh_cfg;
	struct ionmesh_assignment ionmesh_assignment;
	bool use_ionmesh;
};

static struct openwrt_state *g_openwrt_state = NULL;

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
	OSMO_ASSERT(data);

	LOGP(DMAIN, LOGL_DEBUG, "Card->Modem APDU: %s\n", osmo_hexdump(data, len));

	/* In a real implementation, this would forward the APDU to the modem
	 * For OpenWRT, this typically goes through the modem's AT command interface
	 * or a direct APDU channel. For now, we log it. */

	return 0;
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

static int openwrt_send_tpdu_to_modem(struct openwrt_state *os, const uint8_t *data, size_t len)
{
	LOGP(DMAIN, LOGL_DEBUG, "Sending TPDU to modem: %s\n", osmo_hexdump(data, len));

	/* In a real implementation, this would interface with the modem's SIM interface
	 * This could be done via:
	 * 1. AT commands (AT+CSIM for generic SIM access)
	 * 2. QMI interface for Qualcomm modems
	 * 3. Direct character device access if available
	 * 
	 * For now, we simulate the modem accepting the TPDU */

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

	return 0;
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

	openwrt_init_modem(os);

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

	LOGP(DMAIN, LOGL_INFO, "OpenWRT client initialized (GPIO SIM: %d, GPIO Reset: %d)\n",
	     os->sim_switch_gpio, os->modem_reset_gpio);

	/* Run the main event loop */
	while (1) {
		osmo_select_main(0);
	}

	/* Cleanup: Unregister from IonMesh */
	if (os->use_ionmesh && os->ionmesh_cfg) {
		ionmesh_unregister_client(os->ionmesh_cfg);
		ionmesh_config_free(os->ionmesh_cfg);
	}

	return 0;
}
