/* Expect equal / contains — LANGUAGE.md. Fail loud; no invented want. */
#include "dry_expect.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int spark_expect_load_fixture(const char *path, char **out,
			      size_t *out_len)
{
	FILE *f;
	long n;
	char *buf;

	*out = NULL;
	if (out_len)
		*out_len = 0;
	if (!path || !path[0]) {
		fprintf(stderr,
			"error: expect fixture needs a path\n");
		return 1;
	}
	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr,
			"error: expect fixture missing: %s\n", path);
		return 1;
	}
	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		fprintf(stderr, "error: expect fixture fseek %s\n",
			path);
		return 1;
	}
	n = ftell(f);
	if (n < 0 || n > (1 << 20)) {
		fclose(f);
		fprintf(stderr,
			"error: expect fixture too large or bad: %s\n",
			path);
		return 1;
	}
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		fprintf(stderr, "error: expect fixture oom\n");
		return 1;
	}
	if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
		free(buf);
		fclose(f);
		fprintf(stderr, "error: expect fixture read %s\n",
			path);
		return 1;
	}
	buf[n] = 0;
	fclose(f);
	/* Trim a single trailing newline so text fixtures match
	 * bound values that do not carry the file's final NL. */
	if (n > 0 && buf[n - 1] == '\n') {
		buf[n - 1] = 0;
		n--;
		if (n > 0 && buf[n - 1] == '\r') {
			buf[n - 1] = 0;
			n--;
		}
	}
	*out = buf;
	if (out_len)
		*out_len = (size_t)n;
	return 0;
}

int spark_expect_check(const char *mode, const char *name,
		       const char *got, const char *want)
{
	int pass = 0;

	if (!mode || !name || !got || !want) {
		fprintf(stderr, "error: expect needs mode, name, "
				"got, and want\n");
		return 1;
	}
	if (strcmp(mode, "equal") == 0)
		pass = strcmp(got, want) == 0;
	else if (strcmp(mode, "contains") == 0)
		pass = strstr(got, want) != NULL;
	else {
		fprintf(stderr,
			"error: expect mode must be equal or "
			"contains, got \"%s\"\n",
			mode);
		return 1;
	}
	if (pass) {
		printf("[expect] pass %s %s\n", mode, name);
		return 0;
	}
	fprintf(stderr,
		"error: expect %s %s: got \"%s\" want \"%s\"\n",
		mode, name, got, want);
	return 1;
}

static const char *skip_ws(const char *p)
{
	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
		p++;
	return p;
}

static int copy_ident(const char **pp, char *buf, size_t buflen)
{
	const char *p = skip_ws(*pp);
	size_t n = 0;

	if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
	      *p == '_'))
		return 1;
	while ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
	       (*p >= '0' && *p <= '9') || *p == '_') {
		if (n + 1 >= buflen)
			return 1;
		buf[n++] = *p++;
	}
	buf[n] = 0;
	*pp = p;
	return n == 0 ? 1 : 0;
}

static char *copy_quote(const char **pp)
{
	const char *p = skip_ws(*pp);
	const char *start;
	size_t n;
	char *out;
	size_t i;
	size_t o;

	if (*p != '"')
		return NULL;
	p++;
	start = p;
	while (*p && *p != '"') {
		if (*p == '\\' && p[1])
			p += 2;
		else
			p++;
	}
	if (*p != '"')
		return NULL;
	n = (size_t)(p - start);
	out = malloc(n + 1);
	if (!out)
		return NULL;
	o = 0;
	for (i = 0; i < n; i++) {
		if (start[i] == '\\' && i + 1 < n) {
			char c = start[i + 1];
			if (c == 'n')
				out[o++] = '\n';
			else if (c == 't')
				out[o++] = '\t';
			else
				out[o++] = c;
			i++;
		} else {
			out[o++] = start[i];
		}
	}
	out[o] = 0;
	*pp = p + 1;
	return out;
}

int spark_expect_parse_stmt(const char *stmt, char *mode, size_t mode_n,
			    char *name, size_t name_n, char **want_out,
			    int *want_is_fixture)
{
	const char *p;

	*want_out = NULL;
	*want_is_fixture = 0;
	if (!stmt) {
		fprintf(stderr, "error: expect needs a statement\n");
		return 1;
	}
	p = skip_ws(stmt);
	if (strncmp(p, "expect", 6) != 0 ||
	    (p[6] != ' ' && p[6] != '\t')) {
		fprintf(stderr,
			"error: expect statement must start with "
			"expect\n");
		return 1;
	}
	p = skip_ws(p + 6);
	if (copy_ident(&p, mode, mode_n) != 0) {
		fprintf(stderr, "error: expect needs a mode\n");
		return 1;
	}
	{
		int json_mode =
			strcmp(mode, "gte") == 0 ||
			strcmp(mode, "lte") == 0 ||
			strcmp(mode, "eq") == 0 ||
			strcmp(mode, "histogram_min") == 0 ||
			strcmp(mode, "score") == 0;
		if (strcmp(mode, "equal") != 0 &&
		    strcmp(mode, "contains") != 0 && !json_mode) {
			fprintf(stderr,
				"error: expect mode must be equal|"
				"contains|gte|lte|eq|histogram_min|"
				"score, got \"%s\"\n",
				mode);
			return 1;
		}
		if (copy_ident(&p, name, name_n) != 0) {
			fprintf(stderr,
				"error: expect needs a bound name\n");
			return 1;
		}
		p = skip_ws(p);
		if (json_mode) {
			/* Remainder is path/threshold; helper re-parses
			 * the full statement from --stmt-file. */
			size_t n = strlen(p);
			while (n > 0 &&
			       (p[n - 1] == '\n' || p[n - 1] == '\r' ||
				p[n - 1] == ' ' || p[n - 1] == '\t'))
				n--;
			*want_out = malloc(n + 1);
			if (!*want_out) {
				fprintf(stderr, "error: expect oom\n");
				return 1;
			}
			memcpy(*want_out, p, n);
			(*want_out)[n] = 0;
			return 0;
		}
	}
	if (strncmp(p, "fixture", 7) == 0 &&
	    (p[7] == ' ' || p[7] == '\t' || p[7] == '"')) {
		p = skip_ws(p + 7);
		*want_out = copy_quote(&p);
		if (!*want_out) {
			fprintf(stderr,
				"error: expect fixture needs "
				"\"path\"\n");
			return 1;
		}
		*want_is_fixture = 1;
	} else {
		*want_out = copy_quote(&p);
		if (!*want_out) {
			fprintf(stderr,
				"error: expect needs \"want\" or "
				"fixture \"path\"\n");
			return 1;
		}
	}
	p = skip_ws(p);
	if (*p && *p != '#') {
		fprintf(stderr,
			"error: expect: unexpected trailing text\n");
		free(*want_out);
		*want_out = NULL;
		return 1;
	}
	return 0;
}
