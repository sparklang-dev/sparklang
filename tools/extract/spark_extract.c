/*
 * spark-extract — typed extract companion.
 *
 * Dry: read the fixture file from disk (fail loud if missing), parse
 * the inline schema, and validate the fixture against it. No model
 * call, no network, no invented fields.
 *
 * Live: call an OpenAI-compatible gateway (via ./spark-ask-http) with
 * a JSON-only instruction, validate the reply, and retry on a schema
 * miss (default --retries 2). --stub-file PATH feeds canned JSON
 * lines offline so retry is testable without a key.
 *
 *   --dry --stmt-file PATH [--out PATH]
 *   --dry --schema TEXT --fixture PATH [--out PATH]
 *   --live --stmt-file PATH --model ID [--retries N]
 *       [--stub-file PATH] [--out PATH]
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../bootstrap/dry_extract.h"

#define MAX_STMT (1 << 16)
#define MAX_FROM (1 << 16)
#define MAX_ERR (1 << 12)
#define MAX_JSON (1 << 20)

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
		"--fixture PATH [--out PATH]\n"
		"   or: spark-extract --live --stmt-file PATH "
		"--model ID [--retries N] [--stub-file PATH] "
		"[--out PATH]\n");
	exit(2);
}

static void schema_fields_line(const struct spark_extract_schema *schema,
			       char *buf, size_t cap)
{
	size_t i, n = 0;

	buf[0] = 0;
	for (i = 0; i < schema->n_fields; i++) {
		const struct spark_extract_field *f = &schema->fields[i];
		int w = snprintf(buf + n, cap > n ? cap - n : 0,
				 "%s%s%s: %s",
				 i ? ", " : "", f->name,
				 f->optional ? "?" : "",
				 spark_extract_type_name(f->type));
		if (w < 0 || (size_t)w >= (cap > n ? cap - n : 0))
			break;
		n += (size_t)w;
	}
}

/* Strip optional ```json fences; return pointer into mutable buf. */
static char *strip_json_fences(char *s)
{
	char *p = s;
	char *end;
	size_t n;

	while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
		p++;
	if (strncmp(p, "```", 3) == 0) {
		p += 3;
		if (strncmp(p, "json", 4) == 0 ||
		    strncmp(p, "JSON", 4) == 0)
			p += 4;
		while (*p == '\n' || *p == '\r')
			p++;
		end = strstr(p, "```");
		if (end)
			*end = 0;
	}
	n = strlen(p);
	while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == '\t' ||
			 p[n - 1] == '\n' || p[n - 1] == '\r'))
		p[--n] = 0;
	return p;
}

static char *stub_next_line(FILE *f)
{
	static char line[MAX_JSON];
	size_t n;

	if (!fgets(line, sizeof(line), f))
		return NULL;
	n = strlen(line);
	while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
		line[--n] = 0;
	return line;
}

static char *call_ask_http(const char *model, const char *prompt)
{
	char prompt_path[] = "/tmp/spark-extract-promptXXXXXX";
	char out_path[] = "/tmp/spark-extract-askoutXXXXXX";
	int pfd, ofd;
	pid_t pid;
	int status;
	char *argv[16];
	char *body;
	FILE *of;
	long n;

	pfd = mkstemp(prompt_path);
	ofd = mkstemp(out_path);
	if (pfd < 0 || ofd < 0)
		die("mkstemp");
	close(ofd);
	if (write(pfd, prompt, strlen(prompt)) < 0)
		die("write prompt");
	close(pfd);

	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		argv[0] = "./spark-ask-http";
		argv[1] = "--model";
		argv[2] = (char *)model;
		argv[3] = "--prompt-file";
		argv[4] = prompt_path;
		argv[5] = "--out";
		argv[6] = out_path;
		argv[7] = NULL;
		execv("./spark-ask-http", argv);
		_exit(127);
	}
	waitpid(pid, &status, 0);
	unlink(prompt_path);
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		unlink(out_path);
		if (WIFEXITED(status) && WEXITSTATUS(status) == 4)
			die("credential unavailable");
		fprintf(stderr,
			"error: extract live: spark-ask-http failed "
			"(rc=%d)\n",
			WIFEXITED(status) ? WEXITSTATUS(status) : -1);
		exit(1);
	}
	of = fopen(out_path, "rb");
	if (!of) {
		unlink(out_path);
		die("cannot read ask out");
	}
	if (fseek(of, 0, SEEK_END) != 0)
		die("fseek ask out");
	n = ftell(of);
	if (n < 0 || n > MAX_JSON)
		die("ask out too large");
	rewind(of);
	body = malloc((size_t)n + 1);
	if (!body)
		die("oom");
	if (fread(body, 1, (size_t)n, of) != (size_t)n)
		die("read ask out");
	body[n] = 0;
	fclose(of);
	unlink(out_path);
	return body;
}

static void build_prompt(const struct spark_extract_schema *schema,
			 const char *from_text, const char *prior_err,
			 char *out, size_t cap)
{
	char fields[1024];

	schema_fields_line(schema, fields, sizeof(fields));
	if (prior_err && prior_err[0]) {
		snprintf(out, cap,
			 "Extract a single JSON object for schema %s "
			 "with fields {%s}. Reply with JSON only — no "
			 "markdown, no prose. Previous attempt failed "
			 "validation:\n%s\n\nSource text:\n%s\n",
			 schema->name, fields, prior_err, from_text);
	} else {
		snprintf(out, cap,
			 "Extract a single JSON object for schema %s "
			 "with fields {%s}. Reply with JSON only — no "
			 "markdown, no prose.\n\nSource text:\n%s\n",
			 schema->name, fields, from_text);
	}
}

static int parse_retries_clause(const char *stmt, int *out)
{
	const char *p = stmt ? strstr(stmt, "retries") : NULL;
	char *end;
	long v;

	if (!p)
		return 0;
	p += 7;
	while (*p == ' ' || *p == '\t')
		p++;
	v = strtol(p, &end, 10);
	if (end == p || v < 0 || v > 8)
		return 0;
	*out = (int)v;
	return 1;
}

int main(int argc, char **argv)
{
	struct spark_extract_schema schema;
	const char *stmt_file = NULL;
	const char *schema_text = NULL;
	const char *fixture_arg = NULL;
	const char *out_path = NULL;
	const char *model = NULL;
	const char *stub_path = NULL;
	char *stmt = NULL;
	char *body = NULL;
	char path[1024];
	char from_buf[MAX_FROM];
	char errbuf[MAX_ERR];
	char prompt[MAX_STMT];
	int live = 0;
	int retries = 2;
	int i, attempt;
	FILE *stub = NULL;

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
		else if (strcmp(argv[i], "--model") == 0 && i + 1 < argc)
			model = argv[++i];
		else if (strcmp(argv[i], "--retries") == 0 &&
			 i + 1 < argc)
			retries = atoi(argv[++i]);
		else if (strcmp(argv[i], "--stub-file") == 0 &&
			 i + 1 < argc)
			stub_path = argv[++i];
		else
			usage();
	}

	if (retries < 0 || retries > 8)
		die("--retries must be 0..8");

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

	{
		int r = retries;
		if (parse_retries_clause(stmt, &r))
			retries = r;
	}

	if (!live) {
		if (fixture_arg) {
			if (strlen(fixture_arg) + 1 > sizeof(path)) {
				free(stmt);
				die("fixture path too long");
			}
			memcpy(path, fixture_arg,
			       strlen(fixture_arg) + 1);
		} else if (spark_extract_resolve_fixture(stmt, path,
							 sizeof(path)) !=
			   0) {
			free(stmt);
			return 1;
		}

		if (spark_extract_load_fixture(path, &body, NULL) != 0) {
			free(stmt);
			return 1;
		}

		if (spark_extract_validate(&schema, body) != 0) {
			fprintf(stderr,
				"error: extract %s did not validate "
				"against %s\n",
				schema.name, path);
			free(body);
			free(stmt);
			return 1;
		}

		fprintf(stderr,
			"dry schema=%s fields=%zu fixture=%s\n",
			schema.name, schema.n_fields, path);
		fprintf(stderr, "dry ok (validated, no model call)\n");
		write_out(body, out_path);
		free(body);
		free(stmt);
		return 0;
	}

	/* ---- live ---- */
	if (!model || !*model) {
		model = getenv("SPARK_MODEL");
		if (!model || !*model)
			die("live extract requires --model "
			    "(or SPARK_MODEL)");
	}
	if (strcmp(model, "auto") == 0)
		die("refuse --model auto — pass an explicit model id");

	if (spark_extract_resolve_from(stmt, from_buf,
				       sizeof(from_buf)) != 0) {
		free(stmt);
		return 1;
	}

	if (stub_path) {
		stub = fopen(stub_path, "rb");
		if (!stub)
			die("cannot open --stub-file");
		fprintf(stderr,
			"live schema=%s fields=%zu stub=%s "
			"retries=%d\n",
			schema.name, schema.n_fields, stub_path,
			retries);
	} else {
		fprintf(stderr,
			"live schema=%s fields=%zu model=%s "
			"retries=%d\n",
			schema.name, schema.n_fields, model, retries);
	}

	errbuf[0] = 0;
	for (attempt = 0; attempt <= retries; attempt++) {
		char *raw;
		char *json;

		build_prompt(&schema, from_buf,
			     attempt ? errbuf : NULL, prompt,
			     sizeof(prompt));
		if (stub) {
			raw = stub_next_line(stub);
			if (!raw) {
				fprintf(stderr,
					"error: extract live: stub "
					"exhausted on attempt %d\n",
					attempt + 1);
				free(stmt);
				fclose(stub);
				return 1;
			}
			raw = strdup(raw);
			if (!raw)
				die("oom");
		} else {
			raw = call_ask_http(model, prompt);
		}
		json = strip_json_fences(raw);
		if (spark_extract_validate_explain(&schema, json, errbuf,
						   sizeof(errbuf)) ==
		    0) {
			fprintf(stderr,
				"live ok (validated after %d "
				"attempt%s)\n",
				attempt + 1, attempt ? "s" : "");
			write_out(json, out_path);
			free(raw);
			free(stmt);
			if (stub)
				fclose(stub);
			return 0;
		}
		fprintf(stderr,
			"live attempt %d/%d: schema miss — %s\n",
			attempt + 1, retries + 1,
			attempt < retries ? "retrying" : "giving up");
		free(raw);
	}

	fprintf(stderr,
		"error: extract %s did not validate after %d "
		"attempt(s)\n",
		schema.name, retries + 1);
	free(stmt);
	if (stub)
		fclose(stub);
	return 1;
}
