/*
 * spark-ask-http — OpenAI-compatible ask companion.
 * Requires an explicit --model id (HF / path / configured name).
 * --model auto is rejected (no Bifrost-style alias pick).
 * --dry: print model plan, exit 0 — no network, no key required.
 */

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>


#define MAX_BODY (1 << 20)
#define MAX_PROMPT (1 << 18)
#define MAX_RESP (1 << 20)

static void die(const char *msg)
{
	fprintf(stderr, "spark-ask-http: %s\n", msg);
	exit(1);
}

static void die_cred(void)
{
	fprintf(stderr, "spark-ask-http: credential unavailable\n");
	exit(4);
}

static char *read_file(const char *path, size_t *out_len)
{
	FILE *f = fopen(path, "rb");
	char *buf;
	long n;

	if (!f)
		die("cannot open --prompt-file");
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek prompt");
	n = ftell(f);
	if (n < 0 || n > MAX_PROMPT)
		die("prompt too large");
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf)
		die("oom");
	if (fread(buf, 1, (size_t)n, f) != (size_t)n)
		die("read prompt");
	buf[n] = 0;
	fclose(f);
	if (out_len)
		*out_len = (size_t)n;
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
		} else
			*w++ = *p;
	}
	*w = 0;
	return out;
}

/* Extract first message.content string (naive; good enough for chat). */
static int extract_content(const char *json, char *out, size_t out_cap)
{
	const char *p = strstr(json, "\"content\"");
	const char *q;
	size_t i = 0;

	if (!p)
		return -1;
	p = strchr(p + 9, ':');
	if (!p)
		return -1;
	p++;
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p != '"')
		return -1;
	p++;
	while (*p && i + 1 < out_cap) {
		if (*p == '\\' && p[1]) {
			p++;
			if (*p == 'n')
				out[i++] = '\n';
			else if (*p == 'r')
				out[i++] = '\r';
			else if (*p == 't')
				out[i++] = '\t';
			else if (*p == '"' || *p == '\\' || *p == '/')
				out[i++] = *p;
			else if (*p == 'u') {
				/* skip \uXXXX */
				int k;
				for (k = 0; k < 4 && p[1]; k++)
					p++;
			} else
				out[i++] = *p;
			p++;
			continue;
		}
		if (*p == '"')
			break;
		out[i++] = *p++;
	}
	out[i] = 0;
	(void)q;
	return (int)i;
}

static int parse_http_status(const char *resp)
{
	const char *p = resp;
	int code = 0;

	if (strncmp(p, "HTTP/", 5) != 0)
		return -1;
	p = strchr(p, ' ');
	if (!p)
		return -1;
	p++;
	while (*p >= '0' && *p <= '9') {
		code = code * 10 + (*p - '0');
		p++;
	}
	return code;
}

static const char *body_after_headers(const char *resp)
{
	const char *p = strstr(resp, "\r\n\r\n");

	if (p)
		return p + 4;
	p = strstr(resp, "\n\n");
	if (p)
		return p + 2;
	return resp;
}

struct url_parts {
	int https;
	char host[256];
	char port[16];
	char path[512];
};

static int parse_url(const char *url, struct url_parts *u)
{
	const char *p = url;
	const char *slash;
	const char *colon;
	size_t hlen;

	memset(u, 0, sizeof(*u));
	strcpy(u->path, "/v1/chat/completions");
	if (strncmp(p, "https://", 8) == 0) {
		u->https = 1;
		p += 8;
		strcpy(u->port, "443");
	} else if (strncmp(p, "http://", 7) == 0) {
		u->https = 0;
		p += 7;
		strcpy(u->port, "80");
	} else
		return -1;
	slash = strchr(p, '/');
	colon = strchr(p, ':');
	if (colon && (!slash || colon < slash)) {
		hlen = (size_t)(colon - p);
		if (hlen >= sizeof(u->host))
			return -1;
		memcpy(u->host, p, hlen);
		u->host[hlen] = 0;
		{
			size_t plen = 0;
			colon++;
			while (*colon && *colon != '/' && plen + 1 <
			       sizeof(u->port))
				u->port[plen++] = *colon++;
			u->port[plen] = 0;
		}
		p = colon;
	} else {
		hlen = slash ? (size_t)(slash - p) : strlen(p);
		if (hlen >= sizeof(u->host))
			return -1;
		memcpy(u->host, p, hlen);
		u->host[hlen] = 0;
		p = slash ? slash : p + hlen;
	}
	if (*p == '/' && p[1] != '\0') {
		if (strlen(p) >= sizeof(u->path))
			return -1;
		strcpy(u->path, p);
	}
	/* bare host or trailing "/" → default chat completions path */
	return 0;
}

static int http_post_socket(const struct url_parts *u, const char *auth,
			    const char *json_body, char *resp, size_t resp_cap)
{
	struct addrinfo hints, *res = NULL, *rp;
	int fd = -1, rc;
	char header[2048];
	char host_hdr[280];
	size_t blen = strlen(json_body);
	size_t got = 0;
	ssize_t n;

	if (strcmp(u->port, "80") == 0 || strcmp(u->port, "443") == 0)
		snprintf(host_hdr, sizeof(host_hdr), "%s", u->host);
	else
		snprintf(host_hdr, sizeof(host_hdr), "%s:%s", u->host,
			 u->port);

	memset(&hints, 0, sizeof(hints));
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_family = AF_UNSPEC;
	rc = getaddrinfo(u->host, u->port, &hints, &res);
	if (rc != 0)
		die("getaddrinfo failed");
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
		die("connect failed");

	snprintf(header, sizeof(header),
		 "POST %s HTTP/1.1\r\n"
		 "Host: %s\r\n"
		 "Content-Type: application/json\r\n"
		 "Authorization: Bearer %s\r\n"
		 "Content-Length: %zu\r\n"
		 "Connection: close\r\n"
		 "\r\n",
		 u->path, host_hdr, auth, blen);

	if (write(fd, header, strlen(header)) < 0 ||
	    write(fd, json_body, blen) < 0) {
		close(fd);
		die("write request failed");
	}
	while (got + 1 < resp_cap) {
		n = read(fd, resp + got, resp_cap - 1 - got);
		if (n <= 0)
			break;
		got += (size_t)n;
	}
	resp[got] = 0;
	close(fd);
	return (int)got;
}

static int https_post_curl(const char *base_url, const char *auth,
			   const char *json_body, char *resp, size_t resp_cap)
{
	char url[768];
	char hdr[640];
	int pipefd[2];
	pid_t pid;
	size_t got = 0;
	ssize_t n;
	int status;

	snprintf(url, sizeof(url), "%s/v1/chat/completions", base_url);
	/* strip trailing slash on base */
	{
		size_t L = strlen(url);
		/* if base already had path, parse_url set path — rebuild */
		if (strstr(base_url, "/v1/") != NULL)
			snprintf(url, sizeof(url), "%s", base_url);
		else {
			L = strlen(base_url);
			while (L > 0 && base_url[L - 1] == '/')
				L--;
			snprintf(url, sizeof(url), "%.*s/v1/chat/completions",
				 (int)L, base_url);
		}
	}
	snprintf(hdr, sizeof(hdr), "Authorization: Bearer %s", auth);
	if (pipe(pipefd) != 0)
		die("pipe");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		char *argv[] = {
			"curl", "-sS", "-w", "\n__HTTP__%{http_code}",
			"-X", "POST", url,
			"-H", "Content-Type: application/json",
			"-H", hdr,
			"-d", (char *)json_body,
			NULL
		};
		dup2(pipefd[1], 1);
		dup2(pipefd[1], 2);
		close(pipefd[0]);
		close(pipefd[1]);
		execvp("curl", argv);
		_exit(127);
	}
	close(pipefd[1]);
	while (got + 1 < resp_cap) {
		n = read(pipefd[0], resp + got, resp_cap - 1 - got);
		if (n <= 0)
			break;
		got += (size_t)n;
	}
	resp[got] = 0;
	close(pipefd[0]);
	waitpid(pid, &status, 0);
	if (WIFEXITED(status) && WEXITSTATUS(status) == 127)
		die("curl not found (needed for https://)");
	return (int)got;
}

static void usage(void)
{
	fprintf(stderr,
		"Usage: spark-ask-http [--dry] --model MODEL "
		"[--prompt TEXT | --prompt-file PATH] [--out PATH]\n"
		"MODEL: explicit HF id / path / configured model string\n"
		"(--model auto is rejected; no alias pick)\n"
		"Env: AI_GATEWAY_URL SPARK_GATEWAY_KEY SPARK_MODEL "
		"(OPENAI_API_KEY = wire-compat only)\n"
		"--dry: no network; print model; no key\n");
	exit(2);
}


static void print_accounting(const char *json, int dry, long latency_ms)
{
	long pt = 0, ct = 0, tt = 0;
	const char *u, *p;

	if (dry) {
		printf("[accounting] latency_ms=0 prompt_tokens=0 "
		       "completion_tokens=0 total_tokens=0 "
		       "note=dry-run\n");
		return;
	}
	if (json) {
		u = strstr(json, "\"usage\"");
		if (u) {
			p = strstr(u, "\"prompt_tokens\"");
			if (p)
				pt = strtol(p + 16, NULL, 10);
			p = strstr(u, "\"completion_tokens\"");
			if (p)
				ct = strtol(p + 20, NULL, 10);
			p = strstr(u, "\"total_tokens\"");
			if (p)
				tt = strtol(p + 15, NULL, 10);
		}
	}
	printf("[accounting] latency_ms=%ld prompt_tokens=%ld "
	       "completion_tokens=%ld total_tokens=%ld\n",
	       latency_ms, pt, ct, tt);
	if (!json || !strstr(json, "\"usage\""))
		printf("[accounting] note=no usage field in gateway "
		       "response\n");
}

static const char *resolve_model(const char *model, const char *prompt)
{
	(void)prompt;
	if (!model || !*model) {
		const char *env = getenv("SPARK_MODEL");
		if (env && *env)
			return env;
		die("missing --model <explicit-id> (or SPARK_MODEL)");
	}
	if (strcmp(model, "auto") == 0)
		die("refuse --model auto — pass an explicit model id "
		    "(no Bifrost-style alias pick from task text)");
	return model;
}

int main(int argc, char **argv)
{
	const char *model = "";
	const char *prompt = NULL;
	const char *prompt_file = NULL;
	const char *out_path = NULL;
	const char *base;
	const char *key;
	const char *resolved;
	char *prompt_owned = NULL;
	char *esc = NULL;
	char *body = NULL;
	char *resp = NULL;
	char content[MAX_RESP];
	struct url_parts u;
	int i, status, n, dry = 0;
	const char *json_part;
	FILE *of;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--model") == 0 && i + 1 < argc)
			model = argv[++i];
		else if (strcmp(argv[i], "--prompt") == 0 && i + 1 < argc)
			prompt = argv[++i];
		else if (strcmp(argv[i], "--prompt-file") == 0 &&
			 i + 1 < argc)
			prompt_file = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else if (strcmp(argv[i], "--dry") == 0)
			dry = 1;
		else if (strcmp(argv[i], "--help") == 0)
			usage();
		else
			usage();
	}
	if (prompt_file) {
		prompt_owned = read_file(prompt_file, NULL);
		prompt = prompt_owned;
	}
	if (!prompt || !*prompt)
		die("empty prompt");

	resolved = resolve_model(model, prompt);

	if (dry) {
		printf("[ask-http] dry model=%s", resolved);
		printf(" gateway=%s\n",
		       (getenv("AI_GATEWAY_URL") &&
			*getenv("AI_GATEWAY_URL"))
			       ? getenv("AI_GATEWAY_URL")
			       : "http://127.0.0.1:4000");
		printf("[ask-http] dry prompt_bytes=%zu\n",
		       strlen(prompt));
		printf("[ask-http] dry ok (no network)\n");
		print_accounting(NULL, 1, 0);
		free(prompt_owned);
		return 0;
	}

	base = getenv("AI_GATEWAY_URL");
	if (!base || !*base)
		base = "http://127.0.0.1:4000";
	/* Prefer SPARK_GATEWAY_KEY — Bifrost virtual key. OPENAI_API_KEY
	 * is only the OpenAI-compatible Bearer wire name. */
	key = getenv("SPARK_GATEWAY_KEY");
	if (!key || !*key)
		key = getenv("OPENAI_API_KEY");
	if (!key || !*key)
		die_cred();

	if (parse_url(base, &u) != 0)
		die("bad AI_GATEWAY_URL");

	esc = json_escape(prompt);
	body = malloc(strlen(esc) + strlen(resolved) + 256);
	resp = malloc(MAX_RESP);
	if (!body || !resp)
		die("oom");
	snprintf(body, strlen(esc) + strlen(resolved) + 256,
		 "{\"model\":\"%s\",\"messages\":[{\"role\":\"user\","
		 "\"content\":\"%s\"}],\"max_tokens\":256}",
		 resolved, esc);

	if (u.https) {
		n = https_post_curl(base, key, body, resp, MAX_RESP);
		/* curl body + \n__HTTP__CODE */
		{
			char *mark = strstr(resp, "\n__HTTP__");
			int code = -1;

			if (mark) {
				*mark = 0;
				code = atoi(mark + 9);
			}
			if (code == 401)
				die_cred();
			if (code > 0 && (code < 200 || code >= 300)) {
				fprintf(stderr,
					"spark-ask-http: HTTP %d\n", code);
				exit(1);
			}
			json_part = resp;
		}
	} else {
		n = http_post_socket(&u, key, body, resp, MAX_RESP);
		(void)n;
		status = parse_http_status(resp);
		if (status == 401)
			die_cred();
		if (status < 200 || status >= 300) {
			fprintf(stderr, "spark-ask-http: HTTP %d\n", status);
			exit(1);
		}
		json_part = body_after_headers(resp);
	}

	if (extract_content(json_part, content, sizeof(content)) < 0) {
		fprintf(stderr, "spark-ask-http: no content in response\n");
		exit(1);
	}

	fputs(content, stdout);
	if (content[0] && content[strlen(content) - 1] != '\n')
		fputc('\n', stdout);
	print_accounting(json_part, 0, 0);

	if (out_path) {
		of = fopen(out_path, "wb");
		if (!of)
			die("cannot write --out");
		fputs(content, of);
		if (content[0] && content[strlen(content) - 1] != '\n')
			fputc('\n', of);
		fclose(of);
	}

	free(prompt_owned);
	free(esc);
	free(body);
	free(resp);
	return 0;
}
