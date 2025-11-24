
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#define _GNU_SOURCE
#include <getopt.h>

#include <osmocom/core/msgb.h>
#include <osmocom/core/logging.h>
#include <osmocom/core/fsm.h>
#include <osmocom/core/application.h>

#include "client.h"

static void *g_tall_ctx;
void __thread *talloc_asn1_ctx;
int asn_debug;

static void handle_sig_usr1(int signal)
{
	OSMO_ASSERT(signal == SIGUSR1);
	talloc_report_full(g_tall_ctx, stderr);
}

static void printf_help()
{
	printf(
		"  -h --help                  Print this help message\n"
		"  -v --version               Print program version\n"
		"  -d --debug option          Enable debug logging (e.g. DMAIN:DST2)\n"
		"  -i --server-ip A.B.C.D     remsim-server IP address\n"
		"  -p --server-port 13245     remsim-server TCP port\n"
		"  -c --client-id <0-1023>    RSPRO ClientId of this client\n"
		"  -n --client-slot <0-1023>  RSPRO SlotNr of this client\n"
		"  -a --atr HEXSTRING         default ATR to simulate (until bankd overrides it)\n"
		"  -r --atr-ignore-rspro      Ignore any ATR from bankd; use only ATR given by -a)\n"
		"  -e --event-script <path>   event script to be called by client\n"
		"  -L --disable-color         Disable colors for logging to stderr\n"
#ifdef SIMTRACE_SUPPORT
		"  -Z --set-sim-presence <0-1> Define the presence pin behaviour (only supported on some boards)\n"
#endif
#ifdef USB_SUPPORT
		"  -V --usb-vendor VENDOR_ID\n"
		"  -P --usb-product PRODUCT_ID\n"
		"  -C --usb-config CONFIG_ID\n"
		"  -I --usb-interface INTERFACE_ID\n"
		"  -S --usb-altsetting ALTSETTING_ID\n"
		"  -A --usb-address ADDRESS\n"
		"  -H --usb-path PATH\n"
#endif
	      );
}

static void handle_options(struct client_config *cfg, int argc, char **argv)
{
	int rc;

	while (1) {
		int option_index = 0, c;
		static const struct option long_options[] = {
			{ "help", 0, 0, 'h' },
			{ "version", 0, 0, 'v' },
			{ "debug", 1, 0, 'd' },
			{ "server-ip", 1, 0, 'i' },
			{ "server-port", 1, 0, 'p' },
			{ "client-id", 1, 0, 'c' },
			{ "client-slot", 1, 0, 'n' },
			{ "atr", 1, 0, 'a' },
			{ "atr-ignore-rspro", 0, 0, 'r' },
			{ "event-script", 1, 0, 'e' },
			{" disable-color", 0, 0, 'L' },
#ifdef USB_SUPPORT
			{ "usb-vendor", 1, 0, 'V' },
			{ "usb-product", 1, 0, 'P' },
			{ "usb-config", 1, 0, 'C' },
			{ "usb-interface", 1, 0, 'I' },
			{ "usb-altsetting", 1, 0, 'S' },
			{ "usb-address", 1, 0, 'A' },
			{ "usb-path", 1, 0, 'H' },
#endif
			{ 0, 0, 0, 0 }
		};

		c = getopt_long(argc, argv, "hvd:i:p:c:n:a:re:L"
#ifdef SIMTRACE_SUPPORT
						"Z:"
#endif
#ifdef USB_SUPPORT
						"V:P:C:I:S:A:H:"
#endif
				,
				long_options, &option_index);
		if (c == -1)
			break;

		switch (c) {
		case 'h':
			printf_help();
			exit(0);
			break;
		case 'v':
			printf("osmo-remsim-client version %s\n", VERSION);
			exit(0);
			break;
		case 'd':
			log_parse_category_mask(osmo_stderr_target, optarg);
			break;
		case 'i':
			osmo_talloc_replace_string(cfg, &cfg->server_host, optarg);
			break;
		case 'p':
			cfg->server_port = atoi(optarg);
			break;
		case 'c':
			cfg->client_id = atoi(optarg);
			break;
		case 'n':
			cfg->client_slot = atoi(optarg);
			break;
		case 'a':
			rc = osmo_hexparse(optarg, cfg->atr.data, ARRAY_SIZE(cfg->atr.data));
			if (rc < 2 || rc > ARRAY_SIZE(cfg->atr.data)) {
				fprintf(stderr, "ATR malformed\n");
				exit(2);
			}
			cfg->atr.len = rc;
			break;
		case 'r':
			cfg->atr_ignore_rspro = true;
			break;
		case 'e':
			osmo_talloc_replace_string(cfg, &cfg->event_script, optarg);
			break;
		case 'L':
			log_set_use_color(osmo_stderr_target, 0);
			break;
#ifdef SIMTRACE_SUPPORT
		case 'Z':
			cfg->simtrace.presence_valid = true;
			cfg->simtrace.presence_pol = atoi(optarg);
			break;
#endif
#ifdef USB_SUPPORT
		case 'V':
			cfg->usb.vendor_id = strtol(optarg, NULL, 16);
			break;
		case 'P':
			cfg->usb.product_id = strtol(optarg, NULL, 16);
			break;
		case 'C':
			cfg->usb.config_id = atoi(optarg);
			break;
		case 'I':
			cfg->usb.if_num = atoi(optarg);
			break;
		case 'S':
			cfg->usb.altsetting = atoi(optarg);
			break;
		case 'A':
			cfg->usb.addr = atoi(optarg);
			break;
		case 'H':
			cfg->usb.path = optarg;
			break;
#endif
		default:
			break;
		}
	}
}


/* Parse OpenWRT UCI config file /etc/config/remsim
 * This is a simple parser for UCI format without using libuci
 * 
 * The parser reads configuration values from the UCI file and applies them
 * to the client config. Command-line arguments will override these settings.
 */
static void parse_openwrt_config(struct client_config *cfg, const char *config_file)
{
	FILE *f;
	char line[1024];
	char *section = NULL;  /* Current config section, talloc-allocated */
	
	f = fopen(config_file, "r");
	if (!f) {
		/* Config file doesn't exist or can't be opened - not an error */
		return;
	}
	
	while (fgets(line, sizeof(line), f)) {
		char *p = line;
		
		/* Skip leading whitespace */
		while (*p == ' ' || *p == '\t')
			p++;
		
		/* Skip empty lines and comments */
		if (*p == '\0' || *p == '\n' || *p == '#')
			continue;
		
		/* Parse config section: config <type> '<name>' */
		if (strncmp(p, "config ", 7) == 0) {
			char type[64], name[64];
			if (sscanf(p, "config %63s '%63[^']'", type, name) == 2) {
				if (section)
					talloc_free(section);
				section = talloc_strdup(cfg, name);
			}
			continue;
		}
		
		/* Parse option: option <key> '<value>' or option <key> <value> */
		if (strncmp(p, "option ", 7) == 0) {
			char key[64], value[512];
			int n;
			
			/* Try quoted value first */
			n = sscanf(p, "option %63s '%511[^']'", key, value);
			if (n != 2) {
				/* Try unquoted value */
				n = sscanf(p, "option %63s %511s", key, value);
			}
			
			if (n == 2 && section) {
				/* Remove trailing newline from value */
				char *nl = strchr(value, '\n');
				if (nl)
					*nl = '\0';
				
				/* Apply configuration based on section */
				if (strcmp(section, "server") == 0) {
					if (strcmp(key, "host") == 0) {
						/* Trim leading and trailing spaces from host */
						char *start = value;
						char *end;
						
						while (*start == ' ' || *start == '\t')
							start++;
						
						end = start + strlen(start) - 1;
						while (end > start && (*end == ' ' || *end == '\t' || *end == '\n'))
							*end-- = '\0';
						
						osmo_talloc_replace_string(cfg, &cfg->server_host, start);
					} else if (strcmp(key, "port") == 0) {
						char *endptr;
						long port = strtol(value, &endptr, 10);
						if (*endptr == '\0' && port > 0 && port <= 65535)
							cfg->server_port = (int)port;
					}
				} else if (strcmp(section, "client") == 0) {
					if (strcmp(key, "client_id") == 0) {
						char *endptr;
						long id = strtol(value, &endptr, 10);
						if (*endptr == '\0' && id >= 0 && id <= 1023)
							cfg->client_id = (int)id;
					} else if (strcmp(key, "client_slot") == 0) {
						char *endptr;
						long slot = strtol(value, &endptr, 10);
						if (*endptr == '\0' && slot >= 0 && slot <= 1023)
							cfg->client_slot = (int)slot;
					}
				}
			}
			continue;
		}
	}
	
	if (section)
		talloc_free(section);
	fclose(f);
}

static int avoid_zombies(void)
{
	static struct sigaction sa_chld;

	sa_chld.sa_handler = SIG_IGN;
	sigemptyset(&sa_chld.sa_mask);
	sa_chld.sa_flags = SA_NOCLDWAIT;
	sa_chld.sa_restorer = NULL;

	return sigaction(SIGCHLD, &sa_chld, NULL);
}

int main(int argc, char **argv)
{
	struct bankd_client *g_client;
	struct client_config *cfg;
	char hostname[256];

	gethostname(hostname, sizeof(hostname));

	g_tall_ctx = talloc_named_const(NULL, 0, "global");
	talloc_asn1_ctx = talloc_named_const(g_tall_ctx, 0, "asn1");
	msgb_talloc_ctx_init(g_tall_ctx, 0);

	osmo_init_logging2(g_tall_ctx, &log_info);
	log_set_print_level(osmo_stderr_target, 1);
	log_set_print_category(osmo_stderr_target, 1);
	log_set_print_category_hex(osmo_stderr_target, 0);
	osmo_fsm_log_addr(0);

	cfg = client_config_init(g_tall_ctx);
	OSMO_ASSERT(cfg);
	
	/* For OpenWRT client, try to read config from /etc/config/remsim first.
	 * Command-line arguments will override config file settings. */
	if (strstr(argv[0], "openwrt")) {
		parse_openwrt_config(cfg, "/etc/config/remsim");
	}
	
	handle_options(cfg, argc, argv);

	g_client = remsim_client_create(g_tall_ctx, hostname, "remsim-client",cfg);

	osmo_fsm_inst_dispatch(g_client->srv_conn.fi, SRVC_E_ESTABLISH, NULL);

	signal(SIGUSR1, handle_sig_usr1);

	/* Silently (and portably) reap children. */
	if (avoid_zombies() < 0) {
		LOGP(DMAIN, LOGL_FATAL, "Unable to silently reap children: %s\n", strerror(errno));
		exit(1);
	}

	asn_debug = 0;

	client_user_main(g_client);
}
