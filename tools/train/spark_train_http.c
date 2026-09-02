/*
 * spark-train-http — training job submit / status companion.
 *
 * Dry: fixtures only (no GPU, no network).
 * Live http: POST/GET SPARK_TRAIN_URL jobs API.
 * Live local-yield: systemctl start train@UNIT when allowlisted.
 *
 * Env: SPARK_TRAIN_BACKEND=http|local-yield|huggingface
 *      SPARK_TRAIN_URL, SPARK_TRAIN_TOKEN (optional),
 *      SPARK_TRAIN_UNIT_ALLOWLIST (local-yield only)
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../bootstrap/dry_train.h"

static void die(const char *msg)
{
	fprintf(stderr, "spark-train-http: %s\n", msg);
	exit(1);
}

static void die_cfg(const char *msg)
{
	fprintf(stderr, "spark-train-http: %s\n", msg);
	exit(2);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-train-http --dry|--live "
		"--submit|--status <job_id>\n"
		"  [--dataset PATH] [--base ID] [--out DIR]\n"
		"  [--backend http|local-yield|huggingface]\n"
		"  [--unit NAME]  (local-yield only)\n");
	exit(1);
}

static const char *env_or(const char *k, const char *def)
{
	const char *v = getenv(k);

	return (v && v[0]) ? v : def;
}

static int unit_allowlisted(const char *unit)
{
	const char *list = getenv("SPARK_TRAIN_UNIT_ALLOWLIST");
	char buf[512];
	char *tok;
	char *save = NULL;
	size_t n;

	if (!list || !list[0] || !unit || !unit[0])
		return 0;
	n = strlen(list);
	if (n >= sizeof(buf))
		return 0;
	memcpy(buf, list, n + 1);
	for (tok = strtok_r(buf, ",", &save); tok;
	     tok = strtok_r(NULL, ",", &save)) {
		while (*tok && isspace((unsigned char)*tok))
			tok++;
		if (strcmp(tok, unit) == 0)
			return 1;
	}
	return 0;
}

static int run_systemctl_start(const char *unit)
{
	char name[256];
	pid_t pid;
	int st;

	if (snprintf(name, sizeof(name), "train@%s", unit) >=
	    (int)sizeof(name))
		die("unit name too long");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		execlp("systemctl", "systemctl", "start", name,
		       (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		die("waitpid");
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
		return 1;
	return 0;
}

struct url_parts {
	int https;
	char host[256];
	char port[16];
	char path[512];
};

static int parse_url(const char *base, struct url_parts *u)
{
	const char *p = base;
	const char *slash;
	const char *colon;
	size_t hlen;

	memset(u, 0, sizeof(*u));
	u->https = 0;
	strcpy(u->port, "80");
	if (strncmp(p, "https://", 8) == 0) {
		u->https = 1;
		strcpy(u->port, "443");
		p += 8;
	} else if (strncmp(p, "http://", 7) == 0) {
		p += 7;
	} else {
		return -1;
	}
	slash = strchr(p, '/');
	colon = strchr(p, ':');
	if (colon && (!slash || colon < slash)) {
		hlen = (size_t)(colon - p);
		if (hlen >= sizeof(u->host))
			return -1;
		memcpy(u->host, p, hlen);
		u->host[hlen] = 0;
		{
			size_t plen;
			const char *pe = slash ? slash : p + strlen(p);

			plen = (size_t)(pe - (colon + 1));
			if (plen >= sizeof(u->port))
				return -1;
			memcpy(u->port, colon + 1, plen);
			u->port[plen] = 0;
		}
		p = slash ? slash : p + strlen(p);
	} else {
		hlen = slash ? (size_t)(slash - p) : strlen(p);
		if (hlen >= sizeof(u->host))
			return -1;
		memcpy(u->host, p, hlen);
		u->host[hlen] = 0;
		p = slash ? slash : p + strlen(p);
	}
	if (!p || !*p)
		strcpy(u->path, "/");
	else {
		if (strlen(p) >= sizeof(u->path))
			return -1;
		strcpy(u->path, p);
	}
	return 0;
}

static int http_exchange(const char *method, const char *url,
			 const char *body, char *resp, size_t resp_cap)
{
	struct url_parts u;
	struct addrinfo hints, *ai = NULL;
	int fd = -1;
	char req[8192];
	char path[640];
	const char *token = getenv("SPARK_TRAIN_TOKEN");
	ssize_t n;
	size_t off = 0;
	int rc = -1;

	if (parse_url(url, &u) != 0)
		die_cfg("bad SPARK_TRAIN_URL");
	if (u.https)
		die_cfg("https SPARK_TRAIN_URL needs a TLS helper "
			"— use http:// for MVP or terminate TLS upstream");
	if (snprintf(path, sizeof(path), "%s", u.path) >= (int)sizeof(path))
		die("path too long");
	memset(&hints, 0, sizeof(hints));
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_family = AF_UNSPEC;
	if (getaddrinfo(u.host, u.port, &hints, &ai) != 0)
		die("getaddrinfo");
	fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
	if (fd < 0)
		die("socket");
	if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
		freeaddrinfo(ai);
		close(fd);
		die("connect");
	}
	freeaddrinfo(ai);
	if (body) {
		if (snprintf(req, sizeof(req),
			     "%s %s HTTP/1.1\r\n"
			     "Host: %s\r\n"
			     "Content-Type: application/json\r\n"
			     "Content-Length: %zu\r\n"
			     "%s%s%s"
			     "Connection: close\r\n\r\n"
			     "%s",
			     method, path, u.host, strlen(body),
			     token && token[0] ? "Authorization: Bearer "
						: "",
			     token && token[0] ? token : "",
			     token && token[0] ? "\r\n" : "", body) >=
		    (int)sizeof(req))
			die("request too large");
	} else {
		if (snprintf(req, sizeof(req),
			     "%s %s HTTP/1.1\r\n"
			     "Host: %s\r\n"
			     "%s%s%s"
			     "Connection: close\r\n\r\n",
			     method, path, u.host,
			     token && token[0] ? "Authorization: Bearer "
						: "",
			     token && token[0] ? token : "",
			     token && token[0] ? "\r\n" : "") >=
		    (int)sizeof(req))
			die("request too large");
	}
	if (write(fd, req, strlen(req)) < 0)
		die("write");
	while (off + 1 < resp_cap) {
		n = read(fd, resp + off, resp_cap - 1 - off);
		if (n <= 0)
			break;
		off += (size_t)n;
	}
	resp[off] = 0;
	close(fd);
	{
		char *bodyp = strstr(resp, "\r\n\r\n");

		if (!bodyp)
			die("no HTTP body");
		bodyp += 4;
		fputs(bodyp, stdout);
		if (bodyp[0] && bodyp[strlen(bodyp) - 1] != '\n')
			fputc('\n', stdout);
		rc = 0;
	}
	return rc;
}

static void do_submit_http(const char *dataset, const char *base,
			   const char *out_dir)
{
	char url[768];
	char body[1024];
	char resp[1 << 16];
	const char *root = env_or("SPARK_TRAIN_URL", "");

	if (!root[0])
		die_cfg("SPARK_TRAIN_URL required for http backend");
	if (snprintf(url, sizeof(url), "%s/jobs", root) >= (int)sizeof(url))
		die("url too long");
	if (snprintf(body, sizeof(body),
		     "{\"dataset\": \"%s\", \"base\": \"%s\", "
		     "\"out\": \"%s\", \"backend\": \"http\"}",
		     dataset, base, out_dir) >= (int)sizeof(body))
		die("body too long");
	if (http_exchange("POST", url, body, resp, sizeof(resp)) != 0)
		die("http submit failed");
}

static void do_status_http(const char *job_id)
{
	char url[768];
	char resp[1 << 16];
	const char *root = env_or("SPARK_TRAIN_URL", "");

	if (!root[0])
		die_cfg("SPARK_TRAIN_URL required for http backend");
	if (snprintf(url, sizeof(url), "%s/jobs/%s", root, job_id) >=
	    (int)sizeof(url))
		die("url too long");
	if (http_exchange("GET", url, NULL, resp, sizeof(resp)) != 0)
		die("http status failed");
}

static void do_submit_yield(const char *unit, const char *out_dir)
{
	char job_id[128];

	if (!unit || !unit[0])
		die_cfg("--unit required for local-yield");
	if (!unit_allowlisted(unit))
		die_cfg("unit not in SPARK_TRAIN_UNIT_ALLOWLIST");
	if (run_systemctl_start(unit) != 0)
		die("systemctl start train@ failed");
	snprintf(job_id, sizeof(job_id), "yield-%s", unit);
	printf("{\"op\":\"train\",\"mode\":\"live\","
	       "\"job_id\":\"%s\",\"backend\":\"local-yield\","
	       "\"status\":\"accepted\",\"unit\":\"train@%s\","
	       "\"out\":\"%s\","
	       "\"note\":\"started allowlisted yield unit — "
	       "owner train-grant is external to Spark\"}\n",
	       job_id, unit, out_dir);
}

int main(int argc, char **argv)
{
	int dry = 0, live = 0, submit = 0, status = 0;
	const char *job_id = NULL;
	const char *dataset = "examples/fixtures/train/dataset.jsonl";
	const char *base = "fixture-base";
	const char *out_dir = "out/train/job-dry-001";
	const char *backend = NULL;
	const char *unit = NULL;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			dry = 1;
		else if (strcmp(argv[i], "--live") == 0)
			live = 1;
		else if (strcmp(argv[i], "--submit") == 0)
			submit = 1;
		else if (strcmp(argv[i], "--status") == 0) {
			status = 1;
			if (i + 1 < argc && argv[i + 1][0] != '-')
				job_id = argv[++i];
			else
				job_id = "job-dry-001";
		} else if (strcmp(argv[i], "--dataset") == 0 && i + 1 < argc)
			dataset = argv[++i];
		else if (strcmp(argv[i], "--base") == 0 && i + 1 < argc)
			base = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_dir = argv[++i];
		else if (strcmp(argv[i], "--backend") == 0 && i + 1 < argc)
			backend = argv[++i];
		else if (strcmp(argv[i], "--unit") == 0 && i + 1 < argc)
			unit = argv[++i];
		else
			usage();
	}
	if (dry == live)
		usage();
	if (submit == status)
		usage();
	if (!backend)
		backend = env_or("SPARK_TRAIN_BACKEND", "http");

	if (dry) {
		if (submit)
			puts(spark_pick_train_accept());
		else
			puts(spark_pick_train_status(job_id));
		return 0;
	}

	if (strcmp(backend, "huggingface") == 0)
		die_cfg("huggingface backend not wired in MVP");
	if (strcmp(backend, "local-yield") == 0) {
		if (status)
			die_cfg("local-yield status: use systemctl status "
				"train@UNIT (not invented here)");
		do_submit_yield(unit, out_dir);
		return 0;
	}
	if (strcmp(backend, "http") != 0)
		die_cfg("unknown SPARK_TRAIN_BACKEND");
	if (submit)
		do_submit_http(dataset, base, out_dir);
	else
		do_status_http(job_id);
	return 0;
}
