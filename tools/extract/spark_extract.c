/*
 * spark-extract — typed extract companion.
 *
 * Dry: read the fixture file from disk (fail loud if missing), parse
 * the inline schema, and validate the fixture against it. No model
 * call, no network, no invented fields.
 *
 * Live is not implemented and says so rather than falling back to the
 * fixture and reporting success.
 *
 *   --dry --stmt-file PATH [--out PATH]
 *   --dry --schema TEXT --fixture PATH [--out PATH]
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../bootstrap/dry_extract.h"

#define MAX_STMT (1 << 16)

static void die(const char *msg)
{
	fprintf(stderr, "spark-extract: %s\n", msg);
	exit(1);
}

static char *read_file(const char *path)
{
	FILE *f;
	char *buf;
	long n;

	f = fopen(path, "rb");
	if (!f)
		die("cannot open --stmt-file");
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek");
	n = ftell(f);
	if (n < 0 || n > MAX_STMT)
		die("statement too large");
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

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-extract --dry --stmt-file PATH "
		"[--out PATH]\n"
		"   or: spark-extract --dry --schema TEXT "
		"--fixture PATH [--out PATH]\n");
	exit(2);
}

int main(int argc, char **argv)
{
	struct spark_extract_schema schema;
	const char *stmt_file = NULL;
	const char *schema_text = NULL;
	const char *fixture_arg = NULL;
	const char *out_path = NULL;
	char *stmt = NULL;
	char *body = NULL;
	char path[1024];
	int live = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			continue;
		else if (strcmp(argv[i], "--live") == 0)
			live = 1;
		else if (strcmp(argv[i], "--stmt-file") == 0 &&
			 i + 1 < argc)
			stmt_file = argv[++i];
		else if (strcmp(argv[i], "--schema") == 0 && i + 1 < argc)
			schema_text = argv[++i];
		else if (strcmp(argv[i], "--fixture") == 0 &&
			 i + 1 < argc)
			fixture_arg = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else
			usage();
	}

	if (live) {
		fprintf(stderr,
			"error: extract --live is not implemented. "
			"Dry-run validates a fixture; a live model "
			"call is not wired.\n");
		return 1;
	}

	if (stmt_file)
		stmt = read_file(stmt_file);
	else if (schema_text)
		stmt = strdup(schema_text);
	else
		usage();
	if (!stmt)
		die("oom");

	if (spark_extract_parse_schema(stmt, &schema) != 0) {
		free(stmt);
		return 1;
	}

	if (fixture_arg) {
		if (strlen(fixture_arg) + 1 > sizeof(path)) {
			free(stmt);
			die("fixture path too long");
		}
		memcpy(path, fixture_arg, strlen(fixture_arg) + 1);
	} else if (spark_extract_resolve_fixture(stmt, path,
						 sizeof(path)) != 0) {
		free(stmt);
		return 1;
	}

	if (spark_extract_load_fixture(path, &body, NULL) != 0) {
		free(stmt);
		return 1;
	}

	if (spark_extract_validate(&schema, body) != 0) {
		fprintf(stderr,
			"error: extract %s did not validate against "
			"%s\n", schema.name, path);
		free(body);
		free(stmt);
		return 1;
	}

	fprintf(stderr,
		"dry schema=%s fields=%zu fixture=%s\n", schema.name,
		schema.n_fields, path);
	fprintf(stderr, "dry ok (validated, no model call)\n");
	write_out(body, out_path);
	free(body);
	free(stmt);
	return 0;
}
