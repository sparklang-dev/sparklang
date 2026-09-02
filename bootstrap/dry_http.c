/* Exact dry fixtures for http get/post — LANGUAGE.md.
 * Reads files from disk; never invents a response body. */
#include "dry_http.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int spark_http_load_fixture(const char *path, char **out, size_t *out_len)
{
	FILE *f;
	long n;
	char *buf;

	*out = NULL;
	if (out_len)
		*out_len = 0;
	if (!path || !path[0]) {
		fprintf(stderr,
			"error: http dry-run needs a fixture path\n");
		return 1;
	}
	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr,
			"error: http dry-run fixture missing: %s\n",
			path);
		return 1;
	}
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		fprintf(stderr, "error: http dry-run fseek %s\n", path);
		return 1;
	}
	n = ftell(f);
	if (n < 0 || n > (1 << 20)) {
		fclose(f);
		fprintf(stderr,
			"error: http dry-run fixture too large or bad: %s\n",
			path);
		return 1;
	}
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		fprintf(stderr, "error: http dry-run oom\n");
		return 1;
	}
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
		free(buf);
		fclose(f);
		fprintf(stderr, "error: http dry-run read %s\n", path);
		return 1;
	}
	buf[n] = 0;
	fclose(f);
	*out = buf;
	if (out_len)
		*out_len = (size_t)n;
	return 0;
}

int spark_http_resolve_dry_fixture(const char *url, const char *fixture,
				   char *buf, size_t buflen)
{
	const char *src = NULL;

	if (fixture && fixture[0])
		src = fixture;
	else if (url && strncmp(url, "file://", 7) == 0)
		src = url + 7;
	else if (url &&
		 strncmp(url, "examples/fixtures/http/", 23) == 0)
		src = url;
	if (!src || !src[0]) {
		fprintf(stderr,
			"error: http dry-run requires fixture \"…\" "
			"(or file:// / examples/fixtures/http/ URL); "
			"no network, no invented body\n");
		return 1;
	}
	if (strlen(src) + 1 > buflen) {
		fprintf(stderr, "error: http fixture path too long\n");
		return 1;
	}
	memcpy(buf, src, strlen(src) + 1);
	return 0;
}
