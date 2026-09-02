/*
 * spark-pstn-dial — live PSTN companion for Spark `voice pstn dial`.
 *
 * Default OFF. Asm dry-run never forks this. Live path requires ALL of:
 *   1. CLI --pstn-live (Spark passes --spark-cli) OR SPARK_PSTN_CLI=1
 *   2. Env SPARK_PSTN=1
 *   3. Target on allowlist (Beaver + corp + SPARK_PSTN_ALLOW)
 * Divert/failover: refuse store DIDs in applied_dids unless
 * SPARK_PSTN_OVERRIDE_DIVERT=1 (owner-named override). Exit 4.
 *
 * When gates pass: Telnyx Call Control POST /v2/calls (dial) or
 * POST /v2/calls/{id}/actions/hangup. Fail loud if creds missing.
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define EXIT_DIVERT 4
#define EXIT_GATED 2
#define EXIT_USAGE 1
#define EXIT_OK 0
#define MAX_JSON (1 << 20)
#define MAX_DID 32

static int spark_cli;

static int env_truthy(const char *name)
{
	const char *v = getenv(name);

	if (!v || !*v)
		return 0;
	if (!strcmp(v, "1") || !strcasecmp(v, "true") ||
	    !strcasecmp(v, "yes") || !strcasecmp(v, "on"))
		return 1;
	return 0;
}

static void die(const char *msg, int code)
{
	fprintf(stderr, "spark-pstn-dial: %s\n", msg);
	exit(code);
}

static void normalize_e164(const char *in, char *out, size_t outn)
{
	size_t w = 0;
	const char *p = in;

	if (!in || !out || outn < 4)
		return;
	while (*p && isspace((unsigned char)*p))
		p++;
	if (*p == '+') {
		out[w++] = '+';
		p++;
	} else if (*p == '1' && strlen(p) == 11) {
		out[w++] = '+';
	} else if (strlen(p) == 10) {
		out[w++] = '+';
		out[w++] = '1';
	}
	while (*p && w + 1 < outn) {
		if (isdigit((unsigned char)*p))
			out[w++] = *p;
		p++;
	}
	out[w] = 0;
}

static int on_allowlist(const char *e164)
{
	const char *extra;
	static const char *builtin[] = {
		"+15555550100", /* example placeholder */
		"+15555550101", /* example placeholder */
		NULL
	};
	size_t i;

	for (i = 0; builtin[i]; i++) {
		if (!strcmp(e164, builtin[i]))
			return 1;
	}
	extra = getenv("SPARK_PSTN_ALLOW");
	if (extra && *extra) {
		char buf[512];
		char *tok, *save = NULL;
		size_t n = strlen(extra);

		if (n >= sizeof(buf))
			n = sizeof(buf) - 1;
		memcpy(buf, extra, n);
		buf[n] = 0;
		for (tok = strtok_r(buf, ", \t", &save); tok;
		     tok = strtok_r(NULL, ", \t", &save)) {
			char norm[MAX_DID];

			normalize_e164(tok, norm, sizeof(norm));
			if (!strcmp(norm, e164))
				return 1;
		}
	}
	return 0;
}

static int divert_blocks(const char *e164)
{
	const char *home;
	char path[512];
	FILE *f;
	char *json = NULL;
	long n;
	int failover = 0;
	char needle[64];

	home = getenv("HOME");
	if (!home)
		home = ".";
	{
		const char *guard;

		guard = getenv("SPARK_PSTN_GUARD_JSON");
		if (guard && guard[0])
			snprintf(path, sizeof(path), "%s", guard);
		else
			snprintf(path, sizeof(path),
				 "%s/.local/share/spark/outage-forward-state.json",
				 home);
	}
	f = fopen(path, "rb");
	if (f) {
		if (fseek(f, 0, SEEK_END) == 0) {
			n = ftell(f);
			if (n > 0 && n <= MAX_JSON) {
				rewind(f);
				json = malloc((size_t)n + 1);
				if (json &&
				    fread(json, 1, (size_t)n, f) ==
					    (size_t)n) {
					json[n] = 0;
					if (strstr(json, "failover") &&
					    strstr(json, "applied_dids"))
						failover = 1;
				}
			}
		}
		fclose(f);
	}

	if (!failover && !env_truthy("SPARK_CARRIER_DIVERT") &&
	    !env_truthy("SPARK_REFUSE_LIVE_INJECT")) {
		free(json);
		return 0;
	}

	/* DIDs under applied_dids are refused. Allowlist entries stay
	 * allowed. Env force alone: refuse only if DID appears in
	 * applied_dids when ledger present; if no ledger, refuse
	 * non-allowlist (caller already checked allowlist). */
	if (json) {
		const char *ap = strstr(json, "\"applied_dids\"");
		const char *end = json + strlen(json);
		char *section = NULL;

		if (ap) {
			const char *brace = strchr(ap, '{');
			const char *close;
			size_t slen;

			if (brace) {
				close = strchr(brace, '}');
				if (!close)
					close = end;
				slen = (size_t)(close - brace) + 1;
				section = malloc(slen + 1);
				if (section) {
					memcpy(section, brace, slen);
					section[slen] = 0;
				}
			}
		}
		free(json);
		json = NULL;
		if (section) {
			snprintf(needle, sizeof(needle), "\"%s\"", e164);
			if (strstr(section, needle)) {
				free(section);
				if (env_truthy("SPARK_PSTN_OVERRIDE_DIVERT"))
					return 0;
				return 1;
			}
			free(section);
		}
		return 0;
	}

	/* No ledger but env force: allowlist already passed — OK */
	(void)e164;
	return 0;
}

static int curl_json(const char *method, const char *url,
		     const char *body, char *resp, size_t respn)
{
	const char *key = getenv("TELNYX_API_KEY");
	char cmd[2048];
	FILE *p;
	size_t rn;

	if (!key || !*key)
		return -1;
	if (body && *body)
		snprintf(cmd, sizeof(cmd),
			 "curl -sS -X %s '%s' "
			 "-H 'Authorization: Bearer %s' "
			 "-H 'Content-Type: application/json' "
			 "-d '%s'",
			 method, url, key, body);
	else
		snprintf(cmd, sizeof(cmd),
			 "curl -sS -X %s '%s' "
			 "-H 'Authorization: Bearer %s' "
			 "-H 'Content-Type: application/json'",
			 method, url, key);
	p = popen(cmd, "r");
	if (!p)
		return -2;
	rn = fread(resp, 1, respn - 1, p);
	resp[rn] = 0;
	pclose(p);
	return 0;
}

static int extract_json_str(const char *resp, const char *key,
			    char *out, size_t outn)
{
	char pat[128];
	const char *p;
	size_t i = 0;

	snprintf(pat, sizeof(pat), "\"%s\"", key);
	p = strstr(resp, pat);
	if (!p)
		return -1;
	p = strchr(p + strlen(pat), ':');
	if (!p)
		return -1;
	p++;
	while (*p && (*p == ' ' || *p == '"'))
		p++;
	while (p[i] && p[i] != '"' && i + 1 < outn) {
		out[i] = p[i];
		i++;
	}
	out[i] = 0;
	return i ? 0 : -1;
}

static int telnyx_dial(const char *to, const char *from, char *out_id,
		       size_t out_id_n)
{
	const char *conn = getenv("TELNYX_CONNECTION_ID");
	char body[512];
	char resp[4096];
	int rc;

	if (!from || !*from)
		return -2;
	if (!conn || !*conn)
		return -3;
	snprintf(body, sizeof(body),
		 "{\"to\":\"%s\",\"from\":\"%s\","
		 "\"connection_id\":\"%s\"}",
		 to, from, conn);
	rc = curl_json("POST", "https://api.telnyx.com/v2/calls", body,
		       resp, sizeof(resp));
	if (rc != 0)
		return rc;
	if (extract_json_str(resp, "call_control_id", out_id, out_id_n) &&
	    extract_json_str(resp, "call_session_id", out_id, out_id_n)) {
		fprintf(stderr, "spark-pstn-dial: telnyx: %.200s\n", resp);
		return -5;
	}
	return 0;
}

static int telnyx_hangup(const char *call_id)
{
	char url[512];
	char resp[4096];
	int rc;

	snprintf(url, sizeof(url),
		 "https://api.telnyx.com/v2/calls/%s/actions/hangup",
		 call_id);
	rc = curl_json("POST", url, "{}", resp, sizeof(resp));
	if (rc != 0)
		return rc;
	if (strstr(resp, "\"errors\"")) {
		fprintf(stderr, "spark-pstn-dial: hangup: %.200s\n", resp);
		return -5;
	}
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-pstn-dial --spark-cli --to E164 "
		"[--from E164]\n"
		"       spark-pstn-dial --spark-cli --hangup CALL_ID\n"
		"Requires SPARK_PSTN=1.\n");
	exit(EXIT_USAGE);
}

static void require_gates(void)
{
	if (!spark_cli && !env_truthy("SPARK_PSTN_CLI"))
		die("refused: need --spark-cli / SPARK_PSTN_CLI "
		    "(from Spark --pstn-live)",
		    EXIT_GATED);
	if (!env_truthy("SPARK_PSTN"))
		die("refused: SPARK_PSTN=0/unset — enable explicitly",
		    EXIT_GATED);
}

int main(int argc, char **argv)
{
	const char *to = NULL;
	const char *from = NULL;
	const char *hangup = NULL;
	char e164[MAX_DID];
	char call_id[128];
	int i, rc;

	spark_cli = 0;
	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--spark-cli"))
			spark_cli = 1;
		else if (!strcmp(argv[i], "--to") && i + 1 < argc)
			to = argv[++i];
		else if (!strcmp(argv[i], "--from") && i + 1 < argc)
			from = argv[++i];
		else if (!strcmp(argv[i], "--hangup") && i + 1 < argc)
			hangup = argv[++i];
		else if (!strcmp(argv[i], "--help"))
			usage();
		else
			usage();
	}

	require_gates();

	if (hangup) {
		rc = telnyx_hangup(hangup);
		if (rc != 0)
			die("hangup failed (TELNYX_API_KEY / call id)",
			    EXIT_GATED);
		printf("{\"op\":\"pstn.hangup\",\"call_id\":\"%s\","
		       "\"claimed\":true,\"provider\":\"telnyx\"}\n",
		       hangup);
		return EXIT_OK;
	}

	if (!to)
		usage();
	normalize_e164(to, e164, sizeof(e164));
	if (e164[0] != '+' || strlen(e164) < 11)
		die("invalid --to E164", EXIT_USAGE);

	if (!on_allowlist(e164))
		die("refused: destination not on allowlist "
		    "(Beaver/corp or SPARK_PSTN_ALLOW)",
		    EXIT_GATED);

	if (divert_blocks(e164))
		die("refused: CARRIER_DIVERT / outage failover — "
		    "store DID live dial blocked (exit 4). "
		    "Owner override: SPARK_PSTN_OVERRIDE_DIVERT=1",
		    EXIT_DIVERT);

	if (!from)
		from = getenv("SPARK_PSTN_FROM");
	rc = telnyx_dial(e164, from, call_id, sizeof(call_id));
	if (rc != 0) {
		fprintf(stderr,
			"spark-pstn-dial: telnyx dial failed rc=%d "
			"(need TELNYX_API_KEY, TELNYX_CONNECTION_ID, "
			"SPARK_PSTN_FROM)\n",
			rc);
		return EXIT_GATED;
	}
	printf("{\"op\":\"pstn.dial\",\"to\":\"%s\",\"claimed\":true,"
	       "\"call_id\":\"%s\",\"provider\":\"telnyx\"}\n",
	       e164, call_id);
	return EXIT_OK;
}
