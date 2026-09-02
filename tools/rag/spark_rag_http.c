/*
 * spark-rag-http — Bifrost embeddings + rag-gateway retrieve.
 *
 * Live companion for Spark `embed` / `retrieve`. Offline CI: --dry.
 *
 *   --embed     POST {AI_GATEWAY_URL}/v1/embeddings (embed-rag|embed)
 *   --retrieve  POST {RAG_GATEWAY_URL}/v1/retrieve
 *
 * Env: AI_GATEWAY_URL (default :4000), RAG_GATEWAY_URL (default :4620),
 * SPARK_GATEWAY_KEY preferred, RAG_GATEWAY_API_KEY for retrieve override,
 * OPENAI_API_KEY wire-compat only (not OpenAI.com CTA).
 */

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../bootstrap/dry_rag.h"

#define MAX_TEXT (1 << 18)
#define MAX_RESP (1 << 20)

static void die(const char *msg)
{
	fprintf(stderr, "spark-rag-http: %s\n", msg);
	exit(1);
}

static void die_cred(void)
{
	fprintf(stderr, "spark-rag-http: credential unavailable\n");
	exit(4);
}

static char *read_file(const char *path)
{
	FILE *f = fopen(path, "rb");
	char *buf;
	long n;

	if (!f)
		die("cannot open --text-file");
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek");
	n = ftell(f);
	if (n < 0 || n > MAX_TEXT)
		die("text too large");
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
	snprintf(u->path, sizeof(u->path), "/");
	if (strncmp(p, "https://", 8) == 0) {
		u->https = 1;
		p += 8;
		snprintf(u->port, sizeof(u->port), "443");
	} else if (strncmp(p, "http://", 7) == 0) {
		u->https = 0;
		p += 7;
		snprintf(u->port, sizeof(u->port), "80");
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
			const char *pe = slash ? slash : p + strlen(p);
			size_t plen = (size_t)(pe - (colon + 1));

			if (plen >= sizeof(u->port))
				return -1;
			memcpy(u->port, colon + 1, plen);
			u->port[plen] = 0;
		}
		p = slash ? slash : "";
	} else {
		hlen = slash ? (size_t)(slash - p) : strlen(p);
		if (hlen >= sizeof(u->host))
			return -1;
		memcpy(u->host, p, hlen);
		u->host[hlen] = 0;
		p = slash ? slash : "";
	}
	if (p[0])
		snprintf(u->path, sizeof(u->path), "%s", p);
	return 0;
}

static int parse_http_status(const char *resp)
{
	const char *p = resp;

	if (strncmp(p, "HTTP/", 5) != 0)
		return -1;
	while (*p && *p != ' ')
		p++;
	while (*p == ' ')
		p++;
	return atoi(p);
}

static const char *body_after_headers(const char *resp)
{
	const char *p = strstr(resp, "\r\n\r\n");

	if (p)
		return p + 4;
	p = strstr(resp, "\n\n");
	return p ? p + 2 : resp;
}

static void write_out(const char *text, const char *out_path)
{
	FILE *of;

	fputs(text, stdout);
	if (text[0] && text[strlen(text) - 1] != '\n')
		fputc('\n', stdout);
	if (!out_path)
		return;
	of = fopen(out_path, "wb");
	if (!of)
		die("cannot write --out");
	fputs(text, of);
	if (text[0] && text[strlen(text) - 1] != '\n')
		fputc('\n', of);
	fclose(of);
}

static const char *bearer_key(void)
{
	const char *key = getenv("SPARK_GATEWAY_KEY");

	if (key && *key)
		return key;
	key = getenv("OPENAI_API_KEY");
	if (key && *key)
		return key;
	return NULL;
}

static const char *rag_key(void)
{
	const char *key = getenv("RAG_GATEWAY_API_KEY");

	if (key && *key)
		return key;
	return bearer_key();
}

static ssize_t http_post(struct url_parts *u, const char *hdr_name,
			 const char *hdr_val, const char *body, char *resp,
			 size_t resp_cap)
{
	struct addrinfo hints, *res = NULL, *rp;
	int fd = -1;
	char req[8192];
	size_t blen = strlen(body);
	size_t off = 0;
	ssize_t r;
	int n;

	memset(&hints, 0, sizeof(hints));
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_family = AF_UNSPEC;
	if (getaddrinfo(u->host, u->port, &hints, &res) != 0)
		die("getaddrinfo");
	for (rp = res; rp; rp = rp->ai_next) {
		fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
		if (fd < 0)
			continue;
		if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0)
			break;
		close(fd);
		fd = -1;
	}
	freeaddrinfo(res);
	if (fd < 0)
		die("connect");
	n = snprintf(req, sizeof(req),
		     "POST %s HTTP/1.1\r\nHost: %s\r\n"
		     "Content-Type: application/json\r\n"
		     "%s: %s\r\nContent-Length: %zu\r\n"
		     "Connection: close\r\n\r\n",
		     u->path, u->host, hdr_name, hdr_val, blen);
	if (n < 0 || (size_t)n >= sizeof(req))
		die("request too large");
	if (write(fd, req, (size_t)n) != (ssize_t)n)
		die("write headers");
	if (write(fd, body, blen) != (ssize_t)blen)
		die("write body");
	while (off + 1 < resp_cap) {
		r = read(fd, resp + off, resp_cap - 1 - off);
		if (r <= 0)
			break;
		off += (size_t)r;
	}
	resp[off] = 0;
	close(fd);
	return (ssize_t)off;
}

static ssize_t https_post(const char *base, const char *path,
			  const char *hdr_name, const char *hdr_val,
			  const char *body, char *resp, size_t resp_cap)
{
	char url[1024];
	char hdr[640];
	char tmp[] = "/tmp/spark-rag-XXXXXX";
	int fd;
	pid_t pid;
	int st;
	FILE *f;
	size_t n;

	snprintf(url, sizeof(url), "%s%s", base, path);
	snprintf(hdr, sizeof(hdr), "%s: %s", hdr_name, hdr_val);
	fd = mkstemp(tmp);
	if (fd < 0)
		die("mkstemp");
	close(fd);
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		execlp("curl", "curl", "-sS", "-m", "30", "-X", "POST", url,
		       "-H", "Content-Type: application/json", "-H", hdr,
		       "-d", body, "-o", tmp, "-w", "\n__HTTP__%{http_code}",
		       (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		die("waitpid");
	f = fopen(tmp, "rb");
	if (!f)
		die("read curl out");
	n = fread(resp, 1, resp_cap - 1, f);
	resp[n] = 0;
	fclose(f);
	unlink(tmp);
	return (ssize_t)n;
}

static void check_http_body(char *resp, int https, const char **json_out)
{
	if (https) {
		char *mark = strstr(resp, "\n__HTTP__");
		int code = -1;

		if (mark) {
			*mark = 0;
			code = atoi(mark + 9);
		}
		if (code == 401)
			die_cred();
		if (code > 0 && (code < 200 || code >= 300)) {
			fprintf(stderr, "spark-rag-http: HTTP %d\n", code);
			exit(1);
		}
		*json_out = resp;
		return;
	}
	{
		int status = parse_http_status(resp);

		if (status == 401)
			die_cred();
		if (status < 200 || status >= 300) {
			fprintf(stderr, "spark-rag-http: HTTP %d\n", status);
			exit(1);
		}
		*json_out = body_after_headers(resp);
	}
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-rag-http [--dry|--live] --embed|--retrieve "
		"[options]\n"
		"  --text / --text-file   input\n"
		"  --model embed-rag|embed\n"
		"  --project NAME (default docs)\n"
		"  --audience operator|cursor|customer\n"
		"  --top-k N (default 8)\n"
		"  --out PATH\n");
	exit(2);
}

int main(int argc, char **argv)
{
	int dry = 0;
	int live = 0;
	int mode_embed = 0;
	int mode_retrieve = 0;
	const char *text = NULL;
	const char *text_file = NULL;
	const char *model = "embed-rag";
	const char *project = "docs";
	const char *audience = "operator";
	const char *out_path = NULL;
	char *owned = NULL;
	int top_k = 8;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			dry = 1;
		else if (strcmp(argv[i], "--live") == 0)
			live = 1;
		else if (strcmp(argv[i], "--embed") == 0)
			mode_embed = 1;
		else if (strcmp(argv[i], "--retrieve") == 0)
			mode_retrieve = 1;
		else if (strcmp(argv[i], "--text") == 0 && i + 1 < argc)
			text = argv[++i];
		else if (strcmp(argv[i], "--text-file") == 0 &&
			 i + 1 < argc)
			text_file = argv[++i];
		else if (strcmp(argv[i], "--model") == 0 && i + 1 < argc)
			model = argv[++i];
		else if (strcmp(argv[i], "--project") == 0 && i + 1 < argc)
			project = argv[++i];
		else if (strcmp(argv[i], "--audience") == 0 && i + 1 < argc)
			audience = argv[++i];
		else if (strcmp(argv[i], "--top-k") == 0 && i + 1 < argc)
			top_k = atoi(argv[++i]);
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else
			usage();
	}

	if (!live)
		dry = 1;
	if (mode_embed == mode_retrieve)
		die("need exactly one of --embed or --retrieve");
	if (text_file)
		owned = read_file(text_file);
	if (!text && owned)
		text = owned;
	if (!text || !*text)
		die("need --text or --text-file");
	if (strcmp(audience, "operator") != 0 &&
	    strcmp(audience, "cursor") != 0 &&
	    strcmp(audience, "customer") != 0)
		die("bad audience");
	if (strcmp(model, "embed-rag") != 0 && strcmp(model, "embed") != 0)
		die("model must be embed-rag or embed");
	if (top_k < 1 || top_k > 64)
		die("top_k out of range");

	if (dry) {
		const char *fix;

		if (mode_embed) {
			printf("dry mode=embed model=%s\n", model);
			fix = spark_pick_embed(text);
		} else {
			printf("dry mode=retrieve project=%s audience=%s "
			       "top_k=%d\n",
			       project, audience, top_k);
			fix = spark_pick_retrieve(text);
		}
		printf("dry ok (no network)\n");
		write_out(fix, out_path);
		free(owned);
		return 0;
	}

	if (mode_embed) {
		const char *base = getenv("AI_GATEWAY_URL");
		const char *key = bearer_key();
		struct url_parts u;
		char *esc, *body, *resp;
		const char *json_part;
		char auth[640];

		if (!base || !*base)
			base = "http://127.0.0.1:4000";
		if (!key)
			die_cred();
		if (parse_url(base, &u) != 0)
			die("bad AI_GATEWAY_URL");
		snprintf(u.path, sizeof(u.path), "/v1/embeddings");
		esc = json_escape(text);
		body = malloc(strlen(esc) + strlen(model) + 128);
		resp = malloc(MAX_RESP);
		if (!body || !resp)
			die("oom");
		snprintf(body, strlen(esc) + strlen(model) + 128,
			 "{\"model\":\"%s\",\"input\":\"%s\"}", model, esc);
		snprintf(auth, sizeof(auth), "Bearer %s", key);
		if (u.https)
			https_post(base, "/v1/embeddings", "Authorization",
				   auth, body, resp, MAX_RESP);
		else
			http_post(&u, "Authorization", auth, body, resp,
				  MAX_RESP);
		check_http_body(resp, u.https, &json_part);
		write_out(json_part, out_path);
		free(esc);
		free(body);
		free(resp);
		free(owned);
		return 0;
	}

	{
		const char *base = getenv("RAG_GATEWAY_URL");
		const char *key = rag_key();
		struct url_parts u;
		char *esc, *body, *resp;
		const char *json_part;

		if (!base || !*base)
			base = "http://127.0.0.1:4620";
		if (!key)
			die_cred();
		if (parse_url(base, &u) != 0)
			die("bad RAG_GATEWAY_URL");
		snprintf(u.path, sizeof(u.path), "/v1/retrieve");
		esc = json_escape(text);
		body = malloc(strlen(esc) + strlen(project) +
			      strlen(audience) + 160);
		resp = malloc(MAX_RESP);
		if (!body || !resp)
			die("oom");
		snprintf(body,
			 strlen(esc) + strlen(project) + strlen(audience) +
				 160,
			 "{\"query\":\"%s\",\"project\":\"%s\","
			 "\"audience\":\"%s\",\"top_k\":%d}",
			 esc, project, audience, top_k);
		if (u.https)
			https_post(base, "/v1/retrieve", "X-RAG-API-Key",
				   key, body, resp, MAX_RESP);
		else
			http_post(&u, "X-RAG-API-Key", key, body, resp,
				  MAX_RESP);
		check_http_body(resp, u.https, &json_part);
		write_out(json_part, out_path);
		free(esc);
		free(body);
		free(resp);
		free(owned);
		return 0;
	}
}
