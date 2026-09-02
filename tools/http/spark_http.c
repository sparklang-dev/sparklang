/*
 * spark-http — generic HTTP GET/POST companion (not Bifrost-specific).
 *
 * Dry: read fixture file from disk (fail loud if missing). No network.
 * Live: real HTTP via curl (-m timeout). ./spark --live forks this.
 *
 *   --dry|--live --get|--post --url URL [--fixture PATH]
 *     [--timeout SECS] [--body TEXT|--body-file PATH] [--out PATH]
 *   --dry|--live --stmt-file PATH --out PATH
 *     (parse a LANGUAGE http get/post line)
 */

#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../bootstrap/dry_http.h"

#define MAX_BODY (1 << 20)
#define MAX_RESP (1 << 20)

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

static int parse_timeout(const char *line, int *out)
{
	const char *p = strstr(line, "timeout");
	int v;

	if (!p)
		return 0;
	p += 7;
	while (*p == ' ' || *p == '\t')
		p++;
	if (!isdigit((unsigned char)*p))
		return -1;
	v = atoi(p);
	if (v < 1 || v > 600)
		return -1;
	*out = v;
	return 1;
}

static int parse_stmt(const char *line, int *is_post, char **url,
		      char **fixture, char **body, int *timeout_s)
{
	const char *p = line;

	while (*p == ' ' || *p == '\t')
		p++;
	if (strncmp(p, "http", 4) != 0)
		return -1;
	p += 4;
	while (*p == ' ' || *p == '\t')
		p++;
	*is_post = 0;
	if (strncmp(p, "get", 3) == 0 &&
	    (p[3] == ' ' || p[3] == '\t' || p[3] == '"')) {
		*is_post = 0;
	} else if (strncmp(p, "post", 4) == 0 &&
		   (p[4] == ' ' || p[4] == '\t' || p[4] == '"')) {
		*is_post = 1;
	} else {
		return -1;
	}
	*url = quote_after(line, NULL);
	if (!*url || !(*url)[0])
		return -1;
	*fixture = quote_after(line, "fixture");
	*body = quote_after(line, "body");
	{
		int tr = parse_timeout(line, timeout_s);
		if (tr < 0)
			return -1;
	}
	return 0;
}

static void run_dry(int is_post, const char *url, const char *fixture,
		    int timeout_s, const char *out_path)
{
	char path[1024];
	char *body = NULL;
	size_t blen = 0;

	if (spark_http_resolve_dry_fixture(url, fixture, path,
					   sizeof(path)) != 0)
		exit(1);
	if (spark_http_load_fixture(path, &body, &blen) != 0)
		exit(1);
	fprintf(stderr, "dry mode=%s url=%s fixture=%s timeout_s=%d\n",
		is_post ? "post" : "get", url, path, timeout_s);
	fprintf(stderr, "dry ok (no network)\n");
	write_out(body, out_path);
	free(body);
}

static void run_live(int is_post, const char *url, const char *body,
		     int timeout_s, const char *out_path)
{
	char tmp[] = "/tmp/spark-http-XXXXXX";
	char tflag[32];
	char *resp;
	char *esc;
	char *envelope;
	int fd;
	pid_t pid;
	int st;
	FILE *f;
	size_t n;
	int status = 0;
	char *marker;
	char status_buf[16];

	if (!url ||
	    (strncmp(url, "http://", 7) != 0 &&
	     strncmp(url, "https://", 8) != 0))
		die("live needs http:// or https:// URL");
	snprintf(tflag, sizeof(tflag), "%d", timeout_s);
	fd = mkstemp(tmp);
	if (fd < 0)
		die("mkstemp");
	close(fd);
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		/* Body + -w status both on stdout → tmp (no -o). */
		if (!freopen(tmp, "w", stdout))
			_exit(127);
		if (is_post) {
			const char *b = body ? body : "";
			execlp("curl", "curl", "-sS", "-m", tflag, "-X",
			       "POST", url, "-H",
			       "Content-Type: text/plain", "-d", b, "-w",
			       "\n__HTTP__%{http_code}", (char *)NULL);
		} else {
			execlp("curl", "curl", "-sS", "-m", tflag, "-X",
			       "GET", url, "-w", "\n__HTTP__%{http_code}",
			       (char *)NULL);
		}
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		die("waitpid");
	if (!WIFEXITED(st) || WEXITSTATUS(st) == 127)
		die("curl missing or failed");
	if (WIFEXITED(st) && WEXITSTATUS(st) != 0 &&
	    WEXITSTATUS(st) != 22) {
		/* curl 28 = timeout, etc. — still try to read body */
		fprintf(stderr, "spark-http: curl exit %d\n",
			WEXITSTATUS(st));
	}
	f = fopen(tmp, "rb");
	if (!f)
		die("read curl out");
	resp = malloc(MAX_RESP);
	if (!resp)
		die("oom");
	n = fread(resp, 1, MAX_RESP - 1, f);
	resp[n] = 0;
	fclose(f);
	unlink(tmp);
	marker = strstr(resp, "\n__HTTP__");
	if (marker) {
		*marker = 0;
		snprintf(status_buf, sizeof(status_buf), "%s",
			 marker + 9);
		status = atoi(status_buf);
	}
	esc = json_escape(resp);
	envelope = malloc(strlen(esc) + strlen(url) + 128);
	if (!envelope)
		die("oom");
	snprintf(envelope, strlen(esc) + strlen(url) + 128,
		 "{\"op\":\"http.%s\",\"ok\":%s,\"status\":%d,"
		 "\"url\":\"%s\",\"timeout_s\":%d,\"mode\":\"live\","
		 "\"body\":\"%s\"}",
		 is_post ? "post" : "get", status >= 200 && status < 400
						   ? "true"
						   : "false",
		 status, url, timeout_s, esc);
	write_out(envelope, out_path);
	free(esc);
	free(envelope);
	free(resp);
	if (status == 0 && WIFEXITED(st) && WEXITSTATUS(st) != 0)
		exit(1);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-http [--dry|--live] --get|--post "
		"--url URL [--fixture PATH] [--timeout N] "
		"[--body TEXT] [--out PATH]\n"
		"   or: spark-http [--dry|--live] --stmt-file PATH "
		"--out PATH\n");
	exit(2);
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
	char *owned_body = NULL;
	char *owned_url = NULL;
	char *owned_fix = NULL;
	char *owned_stmt_body = NULL;
	char *stmt = NULL;
	int timeout_s = 30;
	int i;
	int is_post = 0;

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

	if (stmt_file) {
		stmt = read_file(stmt_file);
		if (parse_stmt(stmt, &is_post, &owned_url, &owned_fix,
			       &owned_stmt_body, &timeout_s) != 0) {
			free(stmt);
			die("bad http statement");
		}
		url = owned_url;
		fixture = owned_fix;
		body = owned_stmt_body;
		free(stmt);
	} else {
		if (mode_get == mode_post)
			die("need exactly one of --get or --post");
		is_post = mode_post;
		if (!url)
			die("need --url");
		if (body_file)
			owned_body = read_file(body_file);
		if (!body && owned_body)
			body = owned_body;
	}

	if (dry)
		run_dry(is_post, url, fixture, timeout_s, out_path);
	else
		run_live(is_post, url, body, timeout_s, out_path);

	free(owned_body);
	free(owned_url);
	free(owned_fix);
	free(owned_stmt_body);
	return 0;
}
