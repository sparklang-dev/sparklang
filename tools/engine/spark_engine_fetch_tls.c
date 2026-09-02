/*
 * spark-engine-fetch-tls — HTTPS GET via OpenSSL BIO (companion).
 *
 * Forked by asm `engine fetch "https://…"` when --allow-net is set.
 * Not Python urllib. Not TLS-in-asm.
 *
 * Usage:
 *   ./spark-engine-fetch-tls --url URL --out PATH --allow-net
 *       [--insecure]
 *
 * Policy:
 *   https without --allow-net → refuse, no dial (exit 1)
 *   https + --allow-net → BIO_new_ssl_connect GET; body → --out
 *   --insecure → skip cert verify (loopback self-signed tests only)
 *
 * Exit: 0 ok, 1 error
 */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/ssl.h>

#define MAX_BODY 65536
#define MAX_RAW (MAX_BODY + 8192)

static void die(const char *msg)
{
	fprintf(stderr, "spark-engine-fetch-tls: %s\n", msg);
	exit(1);
}

static void refuse_net(const char *url)
{
	fprintf(stderr,
		"spark-engine-fetch-tls: remote https blocked by"
		" default (no network dial).\n"
		"  url: %s\n"
		"  Pass --allow-net for OpenSSL BIO fetch,"
		" or use file:// / http://127.0.0.1.\n",
		url ? url : "(none)");
	exit(1);
}

/* Parse https://host[:port]/path] → host, port, path. */
static int parse_https_url(const char *url, char *host, size_t host_cap,
			   char *path, size_t path_cap, int *port_out)
{
	const char *p;
	const char *slash;
	const char *colon;
	size_t hlen;

	if (strncmp(url, "https://", 8) != 0)
		return -1;
	p = url + 8;
	if (!*p)
		return -1;
	slash = strchr(p, '/');
	colon = strchr(p, ':');
	if (colon && (!slash || colon < slash)) {
		hlen = (size_t)(colon - p);
		if (hlen == 0 || hlen >= host_cap)
			return -1;
		memcpy(host, p, hlen);
		host[hlen] = 0;
		*port_out = atoi(colon + 1);
		if (*port_out <= 0 || *port_out > 65535)
			return -1;
		if (slash)
			snprintf(path, path_cap, "%s", slash);
		else
			snprintf(path, path_cap, "/");
	} else {
		if (slash)
			hlen = (size_t)(slash - p);
		else
			hlen = strlen(p);
		if (hlen == 0 || hlen >= host_cap)
			return -1;
		memcpy(host, p, hlen);
		host[hlen] = 0;
		*port_out = 443;
		if (slash)
			snprintf(path, path_cap, "%s", slash);
		else
			snprintf(path, path_cap, "/");
	}
	return 0;
}

static void write_body_file(const char *path, const char *body, size_t n)
{
	FILE *f;
	char dir[512];
	char *slash;

	snprintf(dir, sizeof(dir), "%s", path);
	slash = strrchr(dir, '/');
	if (slash && slash != dir) {
		*slash = 0;
		mkdir(dir, 0755);
		/* best-effort parents: out/ and out/engine */
		{
			char *p2 = strrchr(dir, '/');
			if (p2 && p2 != dir) {
				*p2 = 0;
				mkdir(dir, 0755);
				*p2 = '/';
			}
		}
	}
	f = fopen(path, "wb");
	if (!f) {
		fprintf(stderr,
			"spark-engine-fetch-tls: cannot write %s: %s\n",
			path, strerror(errno));
		exit(1);
	}
	if (fwrite(body, 1, n, f) != n) {
		fclose(f);
		die("short write");
	}
	fclose(f);
}

static int https_get(const char *url, const char *out_path, int insecure)
{
	char host[256];
	char path[1024];
	char conn[320];
	char req[1536];
	char raw[MAX_RAW];
	int port = 443;
	SSL_CTX *ctx = NULL;
	BIO *bio = NULL;
	SSL *ssl = NULL;
	size_t total = 0;
	ssize_t n;
	char *body;
	size_t body_len;
	int ok = 0;

	if (parse_https_url(url, host, sizeof(host), path, sizeof(path),
			    &port) != 0)
		die("bad https URL (need https://host[/path])");

	SSL_library_init();
	SSL_load_error_strings();
	OpenSSL_add_all_algorithms();

	ctx = SSL_CTX_new(TLS_client_method());
	if (!ctx)
		die("SSL_CTX_new failed");

	if (insecure) {
		SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
	} else {
		if (SSL_CTX_set_default_verify_paths(ctx) != 1) {
			SSL_CTX_free(ctx);
			die("SSL_CTX_set_default_verify_paths failed");
		}
		SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
	}

	bio = BIO_new_ssl_connect(ctx);
	if (!bio) {
		SSL_CTX_free(ctx);
		die("BIO_new_ssl_connect failed");
	}
	BIO_get_ssl(bio, &ssl);
	if (!ssl) {
		BIO_free_all(bio);
		SSL_CTX_free(ctx);
		die("BIO_get_ssl failed");
	}
	SSL_set_mode(ssl, SSL_MODE_AUTO_RETRY);
	if (SSL_set_tlsext_host_name(ssl, host) != 1) {
		BIO_free_all(bio);
		SSL_CTX_free(ctx);
		die("SNI (SSL_set_tlsext_host_name) failed");
	}

	snprintf(conn, sizeof(conn), "%s:%d", host, port);
	BIO_set_conn_hostname(bio, conn);

	if (BIO_do_connect(bio) <= 0) {
		fprintf(stderr,
			"spark-engine-fetch-tls: BIO_do_connect failed"
			" for %s\n",
			conn);
		ERR_print_errors_fp(stderr);
		goto out;
	}
	if (BIO_do_handshake(bio) <= 0) {
		fprintf(stderr,
			"spark-engine-fetch-tls: TLS handshake failed"
			" for %s\n",
			conn);
		ERR_print_errors_fp(stderr);
		goto out;
	}

	snprintf(req, sizeof(req),
		 "GET %s HTTP/1.0\r\n"
		 "Host: %s\r\n"
		 "Connection: close\r\n"
		 "User-Agent: spark-engine-fetch-tls/0.1\r\n"
		 "\r\n",
		 path, host);
	if (BIO_write(bio, req, (int)strlen(req)) <= 0) {
		fprintf(stderr, "spark-engine-fetch-tls: BIO_write failed\n");
		ERR_print_errors_fp(stderr);
		goto out;
	}

	while (total < sizeof(raw) - 1) {
		n = BIO_read(bio, raw + total, (int)(sizeof(raw) - 1 - total));
		if (n > 0) {
			total += (size_t)n;
			continue;
		}
		if (BIO_should_retry(bio))
			continue;
		break;
	}
	raw[total] = 0;

	body = strstr(raw, "\r\n\r\n");
	if (!body) {
		fprintf(stderr,
			"spark-engine-fetch-tls: no HTTP header/body"
			" split\n");
		goto out;
	}
	body += 4;
	body_len = total - (size_t)(body - raw);
	if (body_len > MAX_BODY) {
		fprintf(stderr,
			"spark-engine-fetch-tls: body exceeds %d bytes\n",
			MAX_BODY);
		goto out;
	}
	if (strncmp(raw, "HTTP/1.", 7) != 0) {
		fprintf(stderr,
			"spark-engine-fetch-tls: not an HTTP response\n");
		goto out;
	}
	/* Accept 2xx only */
	{
		const char *sp = strchr(raw, ' ');
		int code = sp ? atoi(sp + 1) : 0;
		if (code < 200 || code > 299) {
			fprintf(stderr,
				"spark-engine-fetch-tls: HTTP status %d"
				" for %s\n",
				code, url);
			goto out;
		}
	}

	write_body_file(out_path, body, body_len);
	/* asm emits language JSON; companion stays quiet on success */
	ok = 1;

out:
	if (bio)
		BIO_free_all(bio);
	if (ctx)
		SSL_CTX_free(ctx);
	return ok ? 0 : 1;
}

int main(int argc, char **argv)
{
	const char *url = NULL;
	const char *out_path = "out/engine/body.bin";
	int allow_net = 0;
	int insecure = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--url") == 0 && i + 1 < argc)
			url = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else if (strcmp(argv[i], "--allow-net") == 0)
			allow_net = 1;
		else if (strcmp(argv[i], "--insecure") == 0)
			insecure = 1;
		else if (strcmp(argv[i], "--help") == 0) {
			fprintf(stderr,
				"usage: %s --url https://… --out PATH"
				" --allow-net [--insecure]\n",
				argv[0]);
			return 0;
		} else {
			fprintf(stderr,
				"spark-engine-fetch-tls: unknown arg %s\n",
				argv[i]);
			return 1;
		}
	}

	if (!url)
		die("missing --url");
	if (strncmp(url, "https://", 8) != 0)
		die("only https:// URLs (use asm socket for http://)");
	if (!allow_net)
		refuse_net(url);

	return https_get(url, out_path, insecure);
}
