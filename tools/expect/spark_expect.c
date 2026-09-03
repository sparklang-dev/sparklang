/*
 * spark-expect — compare a bound value to a literal or fixture.
 *
 *   --dry --stmt-file PATH --got-file PATH [--out PATH]
 *   --dry --mode equal|contains --name NAME
 *       --got TEXT|--got-file PATH
 *       --want TEXT|--fixture PATH [--out PATH]
 *
 * Exit 0 on pass, 1 on fail / missing fixture / bad args.
 * Live is not a separate path: expect only asserts values already
 * produced (dry fixtures or prior live ops).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#include "../../bootstrap/dry_expect.h"

static void die(const char *msg)
{
	fprintf(stderr, "spark-expect: %s\n", msg);
	exit(1);
}

static char *read_all(const char *path)
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
	if (n < 0 || n > (1 << 20))
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

static char *arg_val(int *i, int argc, char **argv, const char *flag)
{
	if (*i + 1 >= argc) {
		fprintf(stderr, "spark-expect: %s needs a value\n",
			flag);
		exit(1);
	}
	(*i)++;
	return argv[*i];
}


static int is_json_mode(const char *mode)
{
	return mode &&
	       (strcmp(mode, "gte") == 0 || strcmp(mode, "lte") == 0 ||
		strcmp(mode, "eq") == 0 ||
		strcmp(mode, "histogram_min") == 0 ||
		strcmp(mode, "score") == 0);
}

static int run_json_assert(const char *stmt_file, const char *got_file,
			   const char *out_path, int live)
{
	pid_t pid;
	int status;
	char *argv[12];
	int n = 0;

	argv[n++] = "python3";
	argv[n++] = "tools/expect/json_assert.py";
	if (live)
		argv[n++] = "--live";
	else
		argv[n++] = "--dry";
	argv[n++] = "--stmt-file";
	argv[n++] = (char *)stmt_file;
	argv[n++] = "--got-file";
	argv[n++] = (char *)got_file;
	if (out_path) {
		argv[n++] = "--out";
		argv[n++] = (char *)out_path;
	}
	argv[n] = NULL;
	pid = fork();
	if (pid < 0)
		die("fork json_assert");
	if (pid == 0) {
		execvp("python3", argv);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0)
		die("wait json_assert");
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	return 1;
}

int main(int argc, char **argv)
{
	const char *mode = NULL;
	const char *name = NULL;
	const char *got_arg = NULL;
	const char *got_file = NULL;
	const char *want_arg = NULL;
	const char *fixture = NULL;
	const char *stmt_file = NULL;
	const char *out_path = NULL;
	char mode_buf[32];
	char name_buf[128];
	char *got = NULL;
	char *want = NULL;
	char *stmt = NULL;
	char *parsed_want = NULL;
	int want_is_fixture = 0;
	int i;
	int rc;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			continue;
		if (strcmp(argv[i], "--live") == 0) {
			fprintf(stderr,
				"error: expect has no live mode "
				"(assert values already produced)\n");
			return 1;
		}
		if (strcmp(argv[i], "--mode") == 0)
			mode = arg_val(&i, argc, argv, "--mode");
		else if (strcmp(argv[i], "--name") == 0)
			name = arg_val(&i, argc, argv, "--name");
		else if (strcmp(argv[i], "--got") == 0)
			got_arg = arg_val(&i, argc, argv, "--got");
		else if (strcmp(argv[i], "--got-file") == 0)
			got_file =
				arg_val(&i, argc, argv, "--got-file");
		else if (strcmp(argv[i], "--want") == 0)
			want_arg = arg_val(&i, argc, argv, "--want");
		else if (strcmp(argv[i], "--fixture") == 0)
			fixture =
				arg_val(&i, argc, argv, "--fixture");
		else if (strcmp(argv[i], "--stmt-file") == 0)
			stmt_file =
				arg_val(&i, argc, argv, "--stmt-file");
		else if (strcmp(argv[i], "--out") == 0)
			out_path = arg_val(&i, argc, argv, "--out");
		else {
			fprintf(stderr,
				"spark-expect: unknown arg %s\n",
				argv[i]);
			return 1;
		}
	}

	if (stmt_file) {
		stmt = read_all(stmt_file);
		if (spark_expect_parse_stmt(stmt, mode_buf,
					    sizeof(mode_buf), name_buf,
					    sizeof(name_buf),
					    &parsed_want,
					    &want_is_fixture) != 0) {
			free(stmt);
			return 1;
		}
		mode = mode_buf;
		name = name_buf;
		if (want_is_fixture)
			fixture = parsed_want;
		else
			want_arg = parsed_want;
	}

	if (!mode || !name) {
		fprintf(stderr,
			"error: expect needs --mode and --name "
			"(or --stmt-file)\n");
		free(stmt);
		free(parsed_want);
		return 1;
	}
	if (got_file)
		got = read_all(got_file);
	else if (got_arg) {
		got = strdup(got_arg);
		if (!got)
			die("oom");
	} else {
		fprintf(stderr,
			"error: expect needs --got or --got-file\n");
		free(stmt);
		free(parsed_want);
		return 1;
	}

	if (is_json_mode(mode)) {
		int live = 0;
		const char *sf = stmt_file;

		if (!sf) {
			fprintf(stderr,
				"error: json expect needs --stmt-file\n");
			free(got);
			free(stmt);
			free(parsed_want);
			return 1;
		}
		/* got already loaded into got_file path when provided */
		if (!got_file) {
			/* write temp got for helper */
			FILE *tf = fopen("/tmp/spark-expect-got-json.txt",
					 "wb");
			if (!tf)
				die("tmp got");
			fputs(got, tf);
			fclose(tf);
			got_file = "/tmp/spark-expect-got-json.txt";
		}
		free(got);
		free(want);
		free(stmt);
		free(parsed_want);
		return run_json_assert(sf, got_file, out_path, live);
	}

	if (fixture) {
		if (spark_expect_load_fixture(fixture, &want, NULL) !=
		    0) {
			free(got);
			free(stmt);
			free(parsed_want);
			return 1;
		}
	} else if (want_arg) {
		want = strdup(want_arg);
		if (!want)
			die("oom");
	} else {
		fprintf(stderr,
			"error: expect needs --want or --fixture\n");
		free(got);
		free(stmt);
		free(parsed_want);
		return 1;
	}

	rc = spark_expect_check(mode, name, got, want);
	if (rc == 0)
		write_out("pass", out_path);
	free(got);
	free(want);
	free(stmt);
	free(parsed_want);
	return rc;
}
