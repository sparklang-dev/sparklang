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
 *      SPARK_TRAIN_METHOD=spark_distill_cpu|spark_pref_pack|
 *                          spark_playbook_fit|spark_faq_index
 *      SPARK_TRAIN_OUT (optional live out dir override)
 *
 * Language bridge: --spark-line PATH reads a `model train` /
 * `model status` statement and fills method/dataset/base/out/backend
 * (or job id for status).
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
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
		"  [--method spark_distill_cpu|spark_pref_pack|"
		"spark_playbook_fit|spark_faq_index]\n"
		"  [--spark-line PATH]  (parse model train|status line)\n"
		"  [--unit NAME]  (local-yield only)\n");
	exit(1);
}

static const char *env_or(const char *k, const char *def)
{
	const char *v = getenv(k);

	return (v && v[0]) ? v : def;
}

static int method_ok(const char *method)
{
	return strcmp(method, "spark_distill_cpu") == 0 ||
	       strcmp(method, "spark_pref_pack") == 0 ||
	       strcmp(method, "spark_playbook_fit") == 0 ||
	       strcmp(method, "spark_faq_index") == 0;
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
			   const char *out_dir, const char *method)
{
	char url[768];
	char body[1280];
	char resp[1 << 16];
	const char *root = env_or("SPARK_TRAIN_URL", "");

	if (!root[0])
		die_cfg("SPARK_TRAIN_URL required for http backend");
	if (snprintf(url, sizeof(url), "%s/jobs", root) >= (int)sizeof(url))
		die("url too long");
	if (snprintf(body, sizeof(body),
		     "{\"dataset\": \"%s\", \"base\": \"%s\", "
		     "\"out\": \"%s\", \"backend\": \"http\", "
		     "\"method\": \"%s\"}",
		     dataset, base, out_dir, method) >= (int)sizeof(body))
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

/* Extract KEYWORD "value" from a .spark statement line. */
static int kw_quoted(const char *line, const char *kw, char *out,
		     size_t cap)
{
	const char *p = line;
	size_t klen = strlen(kw);

	while (*p) {
		if (strncmp(p, kw, klen) == 0) {
			const char *q;
			size_t n;

			q = p + klen;
			while (*q && isspace((unsigned char)*q))
				q++;
			if (*q != '"')
				return 0;
			q++;
			n = 0;
			while (q[n] && q[n] != '"')
				n++;
			if (!q[n] || n + 1 > cap)
				return 0;
			memcpy(out, q, n);
			out[n] = 0;
			return 1;
		}
		p++;
	}
	return 0;
}

static int read_spark_line(const char *path, char *buf, size_t cap)
{
	FILE *f = fopen(path, "r");
	size_t n;

	if (!f)
		die_cfg("cannot open --spark-line");
	if (!fgets(buf, (int)cap, f)) {
		fclose(f);
		die_cfg("empty --spark-line");
	}
	fclose(f);
	n = strlen(buf);
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
		buf[--n] = 0;
	return 0;
}

static void job_id_from_out(const char *out_dir, char *job_id, size_t cap)
{
	const char *slash = strrchr(out_dir, '/');
	const char *base = slash ? slash + 1 : out_dir;

	if (strncmp(base, "job-", 4) == 0 && base[0]) {
		if (strlen(base) + 1 > cap)
			die("job id too long");
		memcpy(job_id, base, strlen(base) + 1);
	} else {
		if (cap < 12)
			die("job id buf");
		memcpy(job_id, "job-dry-001", 12);
	}
}

static void ensure_artifact(const char *out_dir)
{
	char path[512];
	FILE *f;

	if (mkdir("out", 0755) != 0 && errno != EEXIST)
		die("mkdir out");
	if (mkdir("out/train", 0755) != 0 && errno != EEXIST)
		die("mkdir out/train");
	if (mkdir(out_dir, 0755) != 0 && errno != EEXIST)
		die("mkdir out dir");
	if (snprintf(path, sizeof(path), "%s/ARTIFACT", out_dir) >=
	    (int)sizeof(path))
		die("artifact path");
	f = fopen(path, "w");
	if (!f)
		die("write ARTIFACT");
	fprintf(f, "spark-train-dry marker\n");
	fclose(f);
}

int main(int argc, char **argv)
{
	int dry = 0, live = 0, submit = 0, status = 0;
	const char *job_id = NULL;
	const char *dataset = "examples/fixtures/train/dataset.jsonl";
	const char *base = "fixture-base";
	const char *out_dir = "out/train/job-dry-001";
	const char *backend = NULL;
	const char *method = NULL;
	const char *unit = NULL;
	const char *spark_line = NULL;
	char line_buf[2048];
	char q_dataset[512];
	char q_base[256];
	char q_out[512];
	char q_backend[64];
	char q_method[64];
	char q_job[256];
	char job_buf[256];
	int i;

	q_dataset[0] = q_base[0] = q_out[0] = 0;
	q_backend[0] = q_method[0] = q_job[0] = 0;

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
		} else if (strcmp(argv[i], "--dataset") == 0 &&
			   i + 1 < argc)
			dataset = argv[++i];
		else if (strcmp(argv[i], "--base") == 0 && i + 1 < argc)
			base = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_dir = argv[++i];
		else if (strcmp(argv[i], "--backend") == 0 &&
			 i + 1 < argc)
			backend = argv[++i];
		else if (strcmp(argv[i], "--method") == 0 &&
			 i + 1 < argc)
			method = argv[++i];
		else if (strcmp(argv[i], "--spark-line") == 0 &&
			 i + 1 < argc)
			spark_line = argv[++i];
		else if (strcmp(argv[i], "--unit") == 0 && i + 1 < argc)
			unit = argv[++i];
		else
			usage();
	}
	if (dry == live)
		usage();
	if (submit == status)
		usage();

	if (spark_line) {
		read_spark_line(spark_line, line_buf, sizeof(line_buf));
		if (kw_quoted(line_buf, "dataset", q_dataset,
			      sizeof(q_dataset)))
			dataset = q_dataset;
		if (kw_quoted(line_buf, "base", q_base, sizeof(q_base)))
			base = q_base;
		if (kw_quoted(line_buf, "out", q_out, sizeof(q_out)))
			out_dir = q_out;
		if (kw_quoted(line_buf, "backend", q_backend,
			      sizeof(q_backend)))
			backend = q_backend;
		if (kw_quoted(line_buf, "method", q_method,
			      sizeof(q_method)))
			method = q_method;
		if (status && !job_id) {
			/* model status "job-id" — first quote on line */
			const char *q = strchr(line_buf, '"');
			size_t n;

			if (!q)
				die_cfg("model status needs quoted job id");
			q++;
			n = 0;
			while (q[n] && q[n] != '"')
				n++;
			if (!n || n >= sizeof(q_job))
				die_cfg("bad status job id");
			memcpy(q_job, q, n);
			q_job[n] = 0;
			job_id = q_job;
		}
	}

	if (!backend)
		backend = env_or("SPARK_TRAIN_BACKEND", "http");
	if (!method)
		method = env_or("SPARK_TRAIN_METHOD", "spark_distill_cpu");
	{
		const char *out_env = getenv("SPARK_TRAIN_OUT");

		if (out_env && out_env[0])
			out_dir = out_env;
	}
	if (!method_ok(method))
		die_cfg("unknown method (want spark_distill_cpu|"
			"spark_pref_pack|spark_playbook_fit|"
			"spark_faq_index)");

	if (status && !job_id)
		die_cfg("status requires job id (argv or --spark-line)");

	if (dry) {
		const char *body;

		if (submit) {
			job_id_from_out(out_dir, job_buf, sizeof(job_buf));
			body = spark_pick_train_accept(method, job_buf,
						       dataset, base,
						       out_dir);
			if (!body)
				die_cfg("dry train fixture missing for "
					"method");
			ensure_artifact(out_dir);
			puts(body);
		} else {
			body = spark_pick_train_status(job_id);
			if (!body)
				die_cfg("dry status fixture missing for "
					"job id");
			puts(body);
		}
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
		do_submit_http(dataset, base, out_dir, method);
	else
		do_status_http(job_id);
	return 0;
}
