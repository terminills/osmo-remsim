/* (C) 2024 IonMesh Integration
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

/* IonMesh orchestrator integration for osmo-remsim-client
 * 
 * This module provides integration with IonMesh SIM bank orchestration system,
 * allowing OpenWRT clients to register with IonMesh and receive dynamic
 * slot assignments, bankd connections, and KI proxy configuration.
 */

#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <curl/curl.h>

#include <osmocom/core/logging.h>
#include <osmocom/core/utils.h>
#include <osmocom/core/talloc.h>

#include "client.h"
#include "debug.h"
#include "ionmesh_integration.h"

/* IonMesh API configuration */
#define IONMESH_API_VERSION "v1"
#define IONMESH_DEFAULT_PORT 5000
#define IONMESH_TIMEOUT_SEC 10

/* Response buffer for CURL */
struct response_buffer {
	char *data;
	size_t size;
};

static size_t write_callback(void *contents, size_t size, size_t nmemb, void *userp)
{
	size_t realsize = size * nmemb;
	struct response_buffer *mem = (struct response_buffer *)userp;

	char *ptr = realloc(mem->data, mem->size + realsize + 1);
	if (!ptr) {
		LOGP(DMAIN, LOGL_ERROR, "Not enough memory for response buffer\n");
		return 0;
	}

	mem->data = ptr;
	memcpy(&(mem->data[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->data[mem->size] = 0;

	return realsize;
}

/***********************************************************************
 * IonMesh API Functions
 ***********************************************************************/

/* Register client with IonMesh orchestrator and get slot assignment */
int ionmesh_register_client(struct ionmesh_config *cfg, struct ionmesh_assignment *assignment)
{
	CURL *curl;
	CURLcode res;
	struct response_buffer response = {0};
	char url[512];
	char post_data[1024];
	struct curl_slist *headers = NULL;
	int rc = -1;

	if (!cfg || !assignment) {
		LOGP(DMAIN, LOGL_ERROR, "Invalid parameters for ionmesh_register_client\n");
		return -EINVAL;
	}

	LOGP(DMAIN, LOGL_INFO, "Registering client with IonMesh: %s:%d\n", 
	     cfg->host, cfg->port);

	curl = curl_easy_init();
	if (!curl) {
		LOGP(DMAIN, LOGL_ERROR, "Failed to initialize CURL\n");
		return -ENOMEM;
	}

	/* Build API URL */
	snprintf(url, sizeof(url), "http://%s:%d/api/backend/%s/remsim/register-client",
		 cfg->host, cfg->port, IONMESH_API_VERSION);

	/* Build POST data (JSON) */
	snprintf(post_data, sizeof(post_data),
		 "{\"client_id\":\"%s\","
		 "\"mapping_mode\":\"%s\","
		 "\"mcc_mnc\":\"%s\","
		 "\"tenant_id\":%d"
		 "}",
		 cfg->client_id,
		 cfg->mapping_mode,
		 cfg->mcc_mnc ? cfg->mcc_mnc : "",
		 cfg->tenant_id);

	LOGP(DMAIN, LOGL_DEBUG, "IonMesh API request: %s\n", post_data);

	/* Set CURL options */
	headers = curl_slist_append(headers, "Content-Type: application/json");
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, post_data);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, IONMESH_TIMEOUT_SEC);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

	/* Perform request */
	res = curl_easy_perform(curl);
	if (res != CURLE_OK) {
		LOGP(DMAIN, LOGL_ERROR, "CURL request failed: %s\n", curl_easy_strerror(res));
		goto cleanup;
	}

	/* Check HTTP status */
	long http_code = 0;
	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
	if (http_code != 200) {
		LOGP(DMAIN, LOGL_ERROR, "IonMesh API returned HTTP %ld\n", http_code);
		goto cleanup;
	}

	/* Parse JSON response */
	if (response.data) {
		LOGP(DMAIN, LOGL_DEBUG, "IonMesh response: %s\n", response.data);
		rc = ionmesh_parse_assignment(response.data, assignment);
	} else {
		LOGP(DMAIN, LOGL_ERROR, "Empty response from IonMesh\n");
	}

cleanup:
	if (response.data)
		free(response.data);
	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);

	if (rc == 0) {
		LOGP(DMAIN, LOGL_INFO, "Successfully registered with IonMesh\n");
		LOGP(DMAIN, LOGL_INFO, "  Bank: %d, Slot: %d\n", 
		     assignment->bank_id, assignment->slot_id);
		LOGP(DMAIN, LOGL_INFO, "  Bankd: %s:%d\n",
		     assignment->bankd_host, assignment->bankd_port);
		LOGP(DMAIN, LOGL_INFO, "  ICCID: %s, IMSI: %s\n",
		     assignment->iccid, assignment->imsi);
	}

	return rc;
}

/* Parse JSON response from IonMesh API */
int ionmesh_parse_assignment(const char *json, struct ionmesh_assignment *assignment)
{
	/* Simple JSON parsing - in production, use a proper JSON library like jansson */
	/* For now, we'll do basic string parsing */
	
	char *ptr;
	char temp[256];

	if (!json || !assignment) {
		return -EINVAL;
	}

	/* Check for error status */
	if (strstr(json, "\"status\":\"error\"")) {
		LOGP(DMAIN, LOGL_ERROR, "IonMesh returned error status\n");
		return -EIO;
	}

	/* Parse bank_id */
	ptr = strstr(json, "\"bank_id\":");
	if (ptr) {
		sscanf(ptr + 10, "%d", &assignment->bank_id);
	}

	/* Parse slot_id - IonMesh tells us which slot to use (virtual or physical) */
	ptr = strstr(json, "\"slot_id\":");
	if (ptr) {
		sscanf(ptr + 10, "%d", &assignment->slot_id);
	}

	/* Parse ICCID - can be virtual or physical depending on mapping mode */
	ptr = strstr(json, "\"iccid\":\"");
	if (ptr) {
		ptr += 9;
		char *end = strchr(ptr, '"');
		if (end) {
			int len = end - ptr;
			if (len < sizeof(assignment->iccid)) {
				memcpy(assignment->iccid, ptr, len);
				assignment->iccid[len] = '\0';
			}
		}
	}

	/* Parse IMSI - can be virtual or physical depending on mapping mode */
	ptr = strstr(json, "\"imsi\":\"");
	if (ptr) {
		ptr += 8;
		char *end = strchr(ptr, '"');
		if (end) {
			int len = end - ptr;
			if (len < sizeof(assignment->imsi)) {
				memcpy(assignment->imsi, ptr, len);
				assignment->imsi[len] = '\0';
			}
		}
	}

	/* Parse bankd_endpoint */
	ptr = strstr(json, "\"bankd_endpoint\":\"");
	if (ptr) {
		ptr += 18;
		char *end = strchr(ptr, '"');
		if (end) {
			int len = end - ptr;
			if (len < sizeof(temp)) {
				memcpy(temp, ptr, len);
				temp[len] = '\0';
				
				/* Parse host:port from endpoint URL */
				/* Expected format: "http://host:port" or "host:port" */
				char *colon_slash = strstr(temp, "://");
				char *host_start = colon_slash ? colon_slash + 3 : temp;
				char *colon = strchr(host_start, ':');
				
				if (colon) {
					*colon = '\0';
					snprintf(assignment->bankd_host, sizeof(assignment->bankd_host),
						 "%s", host_start);
					assignment->bankd_port = atoi(colon + 1);
				} else {
					snprintf(assignment->bankd_host, sizeof(assignment->bankd_host),
						 "%s", host_start);
					assignment->bankd_port = 9999; /* Default bankd port */
				}
			}
		}
	}

	/* Parse mapping_mode */
	ptr = strstr(json, "\"mapping_mode\":\"");
	if (ptr) {
		ptr += 16;
		char *end = strchr(ptr, '"');
		if (end) {
			int len = end - ptr;
			if (len < sizeof(assignment->mapping_mode)) {
				memcpy(assignment->mapping_mode, ptr, len);
				assignment->mapping_mode[len] = '\0';
			}
		}
	}

	/* Validate we got essential fields */
	if (assignment->bank_id == 0 || assignment->slot_id == 0 ||
	    assignment->bankd_host[0] == '\0' || assignment->bankd_port == 0) {
		LOGP(DMAIN, LOGL_ERROR, "Incomplete assignment from IonMesh\n");
		return -EINVAL;
	}

	return 0;
}

/* Send heartbeat to IonMesh to maintain registration */
int ionmesh_send_heartbeat(struct ionmesh_config *cfg)
{
	CURL *curl;
	CURLcode res;
	struct response_buffer response = {0};
	char url[512];
	char post_data[512];
	struct curl_slist *headers = NULL;
	int rc = -1;

	if (!cfg) {
		return -EINVAL;
	}

	curl = curl_easy_init();
	if (!curl) {
		return -ENOMEM;
	}

	/* Build API URL */
	snprintf(url, sizeof(url), "http://%s:%d/api/backend/%s/remsim/heartbeat",
		 cfg->host, cfg->port, IONMESH_API_VERSION);

	/* Build POST data */
	snprintf(post_data, sizeof(post_data),
		 "{\"client_id\":\"%s\",\"status\":\"active\"}",
		 cfg->client_id);

	/* Set CURL options */
	headers = curl_slist_append(headers, "Content-Type: application/json");
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, post_data);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, IONMESH_TIMEOUT_SEC);
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);

	/* Perform request */
	res = curl_easy_perform(curl);
	if (res == CURLE_OK) {
		long http_code = 0;
		curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
		rc = (http_code == 200) ? 0 : -1;
	}

	if (response.data)
		free(response.data);
	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);

	return rc;
}

/* Unregister client from IonMesh */
int ionmesh_unregister_client(struct ionmesh_config *cfg)
{
	CURL *curl;
	CURLcode res;
	char url[512];
	int rc = -1;

	if (!cfg) {
		return -EINVAL;
	}

	LOGP(DMAIN, LOGL_INFO, "Unregistering client from IonMesh: %s\n", cfg->client_id);

	curl = curl_easy_init();
	if (!curl) {
		return -ENOMEM;
	}

	/* Build API URL */
	snprintf(url, sizeof(url), "http://%s:%d/api/backend/%s/remsim/unregister/%s",
		 cfg->host, cfg->port, IONMESH_API_VERSION, cfg->client_id);

	/* Set CURL options for DELETE */
	curl_easy_setopt(curl, CURLOPT_URL, url);
	curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, IONMESH_TIMEOUT_SEC);

	/* Perform request */
	res = curl_easy_perform(curl);
	if (res == CURLE_OK) {
		long http_code = 0;
		curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
		rc = (http_code == 200) ? 0 : -1;
	}

	curl_easy_cleanup(curl);

	if (rc == 0) {
		LOGP(DMAIN, LOGL_INFO, "Successfully unregistered from IonMesh\n");
	}

	return rc;
}

/***********************************************************************
 * Configuration and Initialization
 ***********************************************************************/

struct ionmesh_config *ionmesh_config_init(void *ctx)
{
	struct ionmesh_config *cfg = talloc_zero(ctx, struct ionmesh_config);
	if (!cfg)
		return NULL;

	cfg->host = talloc_strdup(cfg, "127.0.0.1");
	cfg->port = IONMESH_DEFAULT_PORT;
	cfg->tenant_id = 1;
	cfg->mapping_mode = talloc_strdup(cfg, "ONE_TO_ONE_SWSIM");
	cfg->client_id = talloc_strdup(cfg, "");
	cfg->mcc_mnc = NULL;

	return cfg;
}

void ionmesh_config_free(struct ionmesh_config *cfg)
{
	if (cfg)
		talloc_free(cfg);
}
