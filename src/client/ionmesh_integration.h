/* (C) 2024 IonMesh Integration
 *
 * All Rights Reserved
 *
 * SPDX-License-Identifier: GPL-2.0+
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>

/* IonMesh orchestrator configuration */
struct ionmesh_config {
	char *host;                /* IonMesh server hostname/IP */
	int port;                  /* IonMesh API port */
	int tenant_id;             /* Tenant ID for multi-tenancy */
	char *client_id;           /* Unique client identifier */
	char *mapping_mode;        /* Mapping mode: ONE_TO_ONE_SWSIM, ONE_TO_ONE_VSIM, KI_PROXY_SWSIM */
	char *mcc_mnc;             /* Optional MCC/MNC for carrier-specific slot assignment */
	bool enabled;              /* Enable IonMesh orchestration */
};

/* IonMesh slot assignment response */
struct ionmesh_assignment {
	int bank_id;               /* Assigned SIM bank ID */
	int slot_id;               /* Assigned slot ID within bank */
	char iccid[32];            /* Assigned ICCID */
	char imsi[32];             /* Assigned IMSI */
	char bankd_host[256];      /* Bankd server hostname/IP */
	int bankd_port;            /* Bankd server port */
	char mapping_mode[32];     /* Confirmed mapping mode */
};

/***********************************************************************
 * IonMesh API Functions
 ***********************************************************************/

/**
 * Initialize IonMesh configuration with defaults
 * @param ctx Talloc context
 * @return Allocated config structure or NULL on error
 */
struct ionmesh_config *ionmesh_config_init(void *ctx);

/**
 * Free IonMesh configuration
 * @param cfg Configuration to free
 */
void ionmesh_config_free(struct ionmesh_config *cfg);

/**
 * Register client with IonMesh orchestrator
 * @param cfg IonMesh configuration
 * @param assignment Output parameter for slot assignment
 * @return 0 on success, negative on error
 */
int ionmesh_register_client(struct ionmesh_config *cfg, struct ionmesh_assignment *assignment);

/**
 * Parse IonMesh API JSON response into assignment structure
 * @param json JSON response string
 * @param assignment Output parameter for parsed assignment
 * @return 0 on success, negative on error
 */
int ionmesh_parse_assignment(const char *json, struct ionmesh_assignment *assignment);

/**
 * Send heartbeat to IonMesh to maintain registration
 * @param cfg IonMesh configuration
 * @return 0 on success, negative on error
 */
int ionmesh_send_heartbeat(struct ionmesh_config *cfg);

/**
 * Unregister client from IonMesh
 * @param cfg IonMesh configuration
 * @return 0 on success, negative on error
 */
int ionmesh_unregister_client(struct ionmesh_config *cfg);
