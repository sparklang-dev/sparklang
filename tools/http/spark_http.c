/*
 * spark-http — generic HTTP GET/POST companion (not Bifrost-specific).
 *
 * Dry: read fixture file from disk (fail loud if missing). No network.
 * Live: real HTTP via curl (-m timeout). Auth headers + retries on
 * documented failure classes. ./spark --live forks this.
 *
 *   --dry|--live --get|--post --url URL [--fixture PATH]
 *     [--timeout SECS] [--body TEXT|--body-file PATH]
 *     [--bearer TOKEN] [--header "Name: value"]
 *     [--retries N] [--backoff MS] [--out PATH]
 *   --dry|--live --stmt-file PATH --out PATH
 *     (parse a LANGUAGE http get/post line)
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../bootstrap/dry_http.h"

#define MAX_BODY (1 << 20)
#define MAX_RESP (1 << 20)
#define MAX_HDR 512
#define MAX_ATTEMPTS 9

static void die(const char *msg)
{
	fprintf(stderr, "spark-http: %s\n", msg);
	exit(1);
}

static char *read_file(const char *path)
{
	FILE *f;
	char *buf;
	long n;

	f = fopen(path, "rb");
	if (!f)
		die("cannot open file");
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek");
	n = ftell(f);
	if (n < 0 || n > MAX_BODY)
		die("file too large");
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf)
		die("oom");
	if (fread(buf, 1, (size_t)n, f) != (size_t)n)
		die("read");
	buf[n] = 0;
	fclose(f);
	return buf;
}

static void write_out(const char *text, const char *out_path)
{
	FILE *of;

	if (!out_path) {
		fputs(text, stdout);
		if (text[0] && text[strlen(text) - 1] != '\n')
			fputc('\n', stdout);
		return;
	}
	of = fopen(out_path, "wb");
	if (!of)
		die("cannot write --out");
	fputs(text, of);
	if (text[0] && text[strlen(text) - 1] != '\n')
		fputc('\n', of);
	fclose(of);
}

static char *json_escape(const char *s)
{
	size_t need = 1;
	const char *p;
	char *out, *w;

	for (p = s; *p; p++) {
		if (*p == '"' || *p == '\\' || *p == '\n' || *p == '\r' ||
		    *p == '\t')
			need += 2;
		else
			need += 1;
	}
	out = malloc(need + 8);
	if (!out)
		die("oom");
	w = out;
	for (p = s; *p; p++) {
		if (*p == '"') {
			*w++ = '\\';
			*w++ = '"';
		} else if (*p == '\\') {
			*w++ = '\\';
			*w++ = '\\';
		} else if (*p == '\n') {
			*w++ = '\\';
			*w++ = 'n';
		} else if (*p == '\r') {
			*w++ = '\\';
			*w++ = 'r';
		} else if (*p == '\t') {
			*w++ = '\\';
			*w++ = 't';
		} else {
			*w++ = *p;
		}
	}
	*w = 0;
	return out;
}

/* Extract quote after keyword (or first quote if kw NULL). */
static char *quote_after(const char *line, const char *kw)
{
	const char *p = line;
	char *out;
	size_t cap, n = 0;

	if (kw && kw[0]) {
		p = strstr(line, kw);
		if (!p)
			return NULL;
		p += strlen(kw);
		while (*p == ' ' || *p == '\t')
			p++;
	}
	p = strchr(p, '"');
	if (!p)
		return NULL;
	p++;
	cap = strlen(p) + 1;
	out = malloc(cap);
	if (!out)
		return NULL;
	while (*p && *p != '"') {
		char c = *p++;
		if (c == '\\' && *p) {
			char e = *p++;
			if (e == 'n')
				c = '\n';
			else if (e == 't')
				c = '\t';
			else if (e == '"' || e == '\\')
				c = e;
			else
				c = e;
		}
		if (n + 1 >= cap) {
			char *nb;
			cap *= 2;
			nb = realloc(out, cap);
			if (!nb) {
				free(out);
				return NULL;
			}
			out = nb;
		}
		out[n++] = c;
	}
	out[n] = 0;
	return out;
}

static int parse_int_kw(const char *line, const char *kw, int lo, int hi,
			int *out)
{
	const char *p = strstr(line, kw);
	int v;

	if (!p)
		return 0;
	p += strlen(kw);
	while (*p == ' ' || *p == '\t')
		p++;
	if (!isdigit((unsigned char)*p))
		return -1;
	v = atoi(p);
	if (v < lo || v > hi)
		return -1;
	*out = v;
	return 1;
}

static int parse_timeout(const char *line, int *out)
{
	return parse_int_kw(line, "timeout", 1, 600, out);
}

static int parse_retries(const char *line, int *out)
{
	return parse_int_kw(line, "retries", 0, 8, out);
}

static int parse_backoff(const char *line, int *out)
{
	return parse_int_kw(line, "backoff", 0, 60000, out);
}

struct http_opts {
	int is_post;
	char *url;
	char *fixture;
	char *body;
	char *bearer;
	char *header;
	int timeout_s;
	int retries;
	int backoff_ms;
};

static int parse_stmt(const char *line, struct http_opts *o)
{
	const char *p = line;
	int tr;

	memset(o, 0, sizeof(*o));
	o->timeout_s = 30;
	o->retries = 0;
	o->backoff_ms = 0;

	while (*p == ' ' || *p == '\t')
		p++;
	if (strncmp(p, "http", 4) != 0)
		return -1;
	p += 4;
	while (*p == ' ' || *p == '\t')
		p++;
	o->is_post = 0;
	if (strncmp(p, "get", 3) == 0 &&
	    (p[3] == ' ' || p[3] == '\t' || p[3] == '"')) {
		o->is_post = 0;
	} else if (strncmp(p, "post", 4) == 0 &&
		   (p[4] == ' ' || p[4] == '\t' || p[4] == '"')) {
		o->is_post = 1;
	} else {
		return -1;
	}
	o->url = quote_after(line, NULL);
	if (!o->url || !o->url[0])
		return -1;
	o->fixture = quote_after(line, "fixture");
	o->body = quote_after(line, "body");
	o->bearer = quote_after(line, "bearer");
	o->header = quote_after(line, "header");
	tr = parse_timeout(line, &o->timeout_s);
	if (tr < 0)
		return -1;
	tr = parse_retries(line, &o->retries);
	if (tr < 0)
		return -1;
	tr = parse_backoff(line, &o->backoff_ms);
	if (tr < 0)
		return -1;
	if (o->retries > 0 && o->backoff_ms == 0 &&
	    !strstr(line, "backoff"))
		o->backoff_ms = 100;
	return 0;
}

static const char *auth_kind(const char *bearer, const char *header)
{
	if (bearer && bearer[0])
		return "bearer";
	if (header && header[0])
		return "header";
	return "none";
}

static void build_auth_hdr(const char *bearer, char *buf, size_t buflen)
{
	if (!bearer || !bearer[0]) {
		buf[0] = 0;
		return;
	}
	if (strlen(bearer) + 32 > buflen)
		die("bearer too long");
	snprintf(buf, buflen, "Authorization: Bearer %s", bearer);
}

static int header_is_authorization(const char *header)
{
	return header &&
	       strncasecmp(header, "Authorization:", 14) == 0;
}

static void run_dry(const struct http_opts *o, const char *out_path)
{
	char path[1024];
	char *body = NULL;
	size_t blen = 0;

	if (o->bearer && o->bearer[0] && o->header && o->header[0] &&
	    header_is_authorization(o->header))
		die("bearer and Authorization header conflict");
	if (spark_http_resolve_dry_fixture(o->url, o->fixture, path,
					   sizeof(path)) != 0)
		exit(1);
	if (spark_http_load_fixture(path, &body, &blen) != 0)
		exit(1);
	fprintf(stderr,
		"dry mode=%s url=%s fixture=%s timeout_s=%d "
		"auth=%s retries=%d backoff_ms=%d\n",
		o->is_post ? "post" : "get", o->url, path, o->timeout_s,
		auth_kind(o->bearer, o->header), o->retries,
		o->backoff_ms);
	fprintf(stderr, "dry ok (no network)\n");
	write_out(body, out_path);
	free(body);
}

static int curl_exit_retryable(int code)
{
	/* Documented transport classes (curl man exit codes). */
	return code == 7 || code == 28 || code == 35 || code == 52 ||
	       code == 56;
}

static int http_status_retryable(int status)
{
	return status == 408 || status == 429 || status == 500 ||
	       status == 502 || status == 503 || status == 504;
}

static int sleep_ms(int ms)
{
	if (ms <= 0)
		return 0;
	return usleep((useconds_t)ms * 1000u);
}

/*
 * One curl attempt. Writes body+status marker to tmp_path.
 * Returns curl process exit status (or 127 if missing).
 */
static int curl_once(int is_post, const char *url, const char *body,
		     int timeout_s, const char *auth_hdr,
		     const char *extra_hdr, const char *tmp_path)
{
	char tflag[32];
	pid_t pid;
	int st;
	char *argv[24];
	int n = 0;
	int fd;

	snprintf(tflag, sizeof(tflag), "%d", timeout_s);
	fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0)
		die("open tmp");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		if (dup2(fd, 1) < 0)
			_exit(127);
		close(fd);
		argv[n++] = "curl";
		argv[n++] = "-sS";
		argv[n++] = "-m";
		argv[n++] = tflag;
		argv[n++] = "-X";
		argv[n++] = is_post ? "POST" : "GET";
		if (auth_hdr && auth_hdr[0]) {
			argv[n++] = "-H";
			argv[n++] = (char *)auth_hdr;
		}
		if (extra_hdr && extra_hdr[0]) {
			argv[n++] = "-H";
			argv[n++] = (char *)extra_hdr;
		}
		if (is_post) {
			argv[n++] = "-H";
			argv[n++] = "Content-Type: text/plain";
			argv[n++] = "-d";
			argv[n++] = (char *)(body ? body : "");
		}
		argv[n++] = (char *)url;
		argv[n++] = "-w";
		argv[n++] = "\n__HTTP__%{http_code}";
		argv[n] = NULL;
		execvp("curl", argv);
		_exit(127);
	}
	close(fd);
	if (waitpid(pid, &st, 0) < 0)
		die("waitpid");
	if (!WIFEXITED(st))
		return 1;
	return WEXITSTATUS(st);
}

static void run_live(const struct http_opts *o, const char *out_path)
{
	char tmp[] = "/tmp/spark-http-XXXXXX";
	char auth_buf[MAX_HDR];
	char *resp;
	char *esc;
	char *envelope;
	int fd;
	FILE *f;
	size_t n;
	int status = 0;
	char *marker;
	char status_buf[16];
	int attempt;
	int max_try;
	int curl_rc = 0;
	int delay;
	const char *extra;

	if (!o->url ||
	    (strncmp(o->url, "http://", 7) != 0 &&
	     strncmp(o->url, "https://", 8) != 0))
		die("live needs http:// or https:// URL");
	if (o->bearer && o->bearer[0] && o->header && o->header[0] &&
	    header_is_authorization(o->header))
		die("bearer and Authorization header conflict");
	build_auth_hdr(o->bearer, auth_buf, sizeof(auth_buf));
	extra = o->header;
	fd = mkstemp(tmp);
	if (fd < 0)
		die("mkstemp");
	close(fd);

	max_try = 1 + o->retries;
	if (max_try > MAX_ATTEMPTS)
		max_try = MAX_ATTEMPTS;
	delay = o->backoff_ms;

	for (attempt = 1; attempt <= max_try; attempt++) {
		fprintf(stderr,
			"live attempt=%d/%d auth=%s timeout_s=%d\n",
			attempt, max_try, auth_kind(o->bearer, o->header),
			o->timeout_s);
		curl_rc = curl_once(o->is_post, o->url, o->body,
				    o->timeout_s,
				    auth_buf[0] ? auth_buf : NULL, extra,
				    tmp);
		if (curl_rc == 127)
			die("curl missing or failed");

		f = fopen(tmp, "rb");
		if (!f)
			die("read curl out");
		resp = malloc(MAX_RESP);
		if (!resp)
			die("oom");
		n = fread(resp, 1, MAX_RESP - 1, f);
		resp[n] = 0;
		fclose(f);
		status = 0;
		marker = strstr(resp, "\n__HTTP__");
		if (marker) {
			*marker = 0;
			snprintf(status_buf, sizeof(status_buf), "%s",
				 marker + 9);
			status = atoi(status_buf);
		}

		if (status >= 200 && status < 400) {
			fprintf(stderr, "live ok status=%d attempts=%d\n",
				status, attempt);
			break;
		}
		if (attempt < max_try &&
		    (curl_exit_retryable(curl_rc) ||
		     http_status_retryable(status))) {
			fprintf(stderr,
				"live retryable curl_rc=%d status=%d "
				"backoff_ms=%d\n",
				curl_rc, status, delay);
			sleep_ms(delay);
			if (delay > 0 && delay < 30000)
				delay *= 2;
			free(resp);
			resp = NULL;
			continue;
		}
		fprintf(stderr,
			"live stop curl_rc=%d status=%d attempts=%d\n",
			curl_rc, status, attempt);
		break;
	}
	unlink(tmp);
	if (!resp)
		die("no response");

	esc = json_escape(resp);
	envelope = malloc(strlen(esc) + strlen(o->url) + 256);
	if (!envelope)
		die("oom");
	snprintf(envelope, strlen(esc) + strlen(o->url) + 256,
		 "{\"op\":\"http.%s\",\"ok\":%s,\"status\":%d,"
		 "\"url\":\"%s\",\"timeout_s\":%d,\"mode\":\"live\","
		 "\"auth\":\"%s\",\"retries\":%d,\"backoff_ms\":%d,"
		 "\"attempts\":%d,\"body\":\"%s\"}",
		 o->is_post ? "post" : "get",
		 status >= 200 && status < 400 ? "true" : "false", status,
		 o->url, o->timeout_s, auth_kind(o->bearer, o->header),
		 o->retries, o->backoff_ms, attempt, esc);
	write_out(envelope, out_path);
	free(esc);
	free(envelope);
	free(resp);
	if (status == 0 && curl_rc != 0)
		exit(1);
	if (status != 0 && !(status >= 200 && status < 400))
		exit(1);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-http [--dry|--live] --get|--post "
		"--url URL [--fixture PATH] [--timeout N] "
		"[--bearer TOKEN] [--header \"Name: value\"] "
		"[--retries N] [--backoff MS] "
		"[--body TEXT] [--out PATH]\n"
		"   or: spark-http [--dry|--live] --stmt-file PATH "
		"--out PATH\n");
	exit(2);
}

static void free_opts(struct http_opts *o)
{
	free(o->url);
	free(o->fixture);
	free(o->body);
	free(o->bearer);
	free(o->header);
}

int main(int argc, char **argv)
{
	int dry = 0;
	int live = 0;
	int mode_get = 0;
	int mode_post = 0;
	const char *url = NULL;
	const char *fixture = NULL;
	const char *body = NULL;
	const char *body_file = NULL;
	const char *out_path = NULL;
	const char *stmt_file = NULL;
	const char *bearer = NULL;
	const char *header = NULL;
	char *owned_body = NULL;
	char *stmt = NULL;
	struct http_opts o;
	int timeout_s = 30;
	int retries = 0;
	int backoff_ms = 0;
	int backoff_set = 0;
	int i;

	memset(&o, 0, sizeof(o));

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			dry = 1;
		else if (strcmp(argv[i], "--live") == 0)
			live = 1;
		else if (strcmp(argv[i], "--get") == 0)
			mode_get = 1;
		else if (strcmp(argv[i], "--post") == 0)
			mode_post = 1;
		else if (strcmp(argv[i], "--url") == 0 && i + 1 < argc)
			url = argv[++i];
		else if (strcmp(argv[i], "--fixture") == 0 &&
			 i + 1 < argc)
			fixture = argv[++i];
		else if (strcmp(argv[i], "--timeout") == 0 &&
			 i + 1 < argc)
			timeout_s = atoi(argv[++i]);
		else if (strcmp(argv[i], "--retries") == 0 &&
			 i + 1 < argc)
			retries = atoi(argv[++i]);
		else if (strcmp(argv[i], "--backoff") == 0 &&
			 i + 1 < argc) {
			backoff_ms = atoi(argv[++i]);
			backoff_set = 1;
		} else if (strcmp(argv[i], "--bearer") == 0 &&
			   i + 1 < argc)
			bearer = argv[++i];
		else if (strcmp(argv[i], "--header") == 0 &&
			 i + 1 < argc)
			header = argv[++i];
		else if (strcmp(argv[i], "--body") == 0 && i + 1 < argc)
			body = argv[++i];
		else if (strcmp(argv[i], "--body-file") == 0 &&
			 i + 1 < argc)
			body_file = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else if (strcmp(argv[i], "--stmt-file") == 0 &&
			 i + 1 < argc)
			stmt_file = argv[++i];
		else
			usage();
	}

	if (!live)
		dry = 1;
	if (timeout_s < 1 || timeout_s > 600)
		die("timeout must be 1..600");
	if (retries < 0 || retries > 8)
		die("retries must be 0..8");
	if (backoff_ms < 0 || backoff_ms > 60000)
		die("backoff must be 0..60000");
	if (retries > 0 && !backoff_set)
		backoff_ms = 100;

	if (stmt_file) {
		stmt = read_file(stmt_file);
		if (parse_stmt(stmt, &o) != 0) {
			free(stmt);
			die("bad http statement");
		}
		free(stmt);
	} else {
		if (mode_get == mode_post)
			die("need exactly one of --get or --post");
		o.is_post = mode_post;
		if (!url)
			die("need --url");
		o.url = strdup(url);
		o.fixture = fixture ? strdup(fixture) : NULL;
		o.bearer = bearer ? strdup(bearer) : NULL;
		o.header = header ? strdup(header) : NULL;
		o.timeout_s = timeout_s;
		o.retries = retries;
		o.backoff_ms = backoff_ms;
		if (body_file)
			owned_body = read_file(body_file);
		if (!body && owned_body)
			body = owned_body;
		o.body = body ? strdup(body) : NULL;
	}

	if (dry)
		run_dry(&o, out_path);
	else
		run_live(&o, out_path);

	free(owned_body);
	free_opts(&o);
	return 0;
}
