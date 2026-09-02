/*
 * spark-review-url — fetch (gated) + static review of script bytes.
 *
 * Never eval / exec / Function-constructor run. Companion only.
 *
 * Usage:
 *   ./spark-review-url --url URL [--out path] [--allow-net]
 *
 * Policy (owner A+B, 2026-08-31):
 *   B default: file:// or bare path → open/read + static scan
 *   A opt-in:  http(s):// + --allow-net → curl fetch + scan
 *   http(s) without --allow-net → clear error (exit 1), no dial,
 *   no permanent QUESTION menu
 *
 * Exit: 0 ok, 1 error (incl. remote without --allow-net), 4 unused
 */

#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_BODY (1 << 20)

static void die(const char *msg)
{
	fprintf(stderr, "spark-review-url: %s\n", msg);
	exit(1);
}

/* B default: refuse remote dial; instruct --allow-net (A). */
static void refuse_remote(const char *url)
{
	fprintf(stderr,
		"spark-review-url: remote http(s) blocked by default"
		" (no network dial).\n"
		"  url: %s\n"
		"  Pass --allow-net to fetch + static-scan"
		" (never eval), or use file:// / a local path.\n",
		url ? url : "(none)");
	exit(1);
}

static char *slurp_file(const char *path, size_t *out_len)
{
	FILE *f = fopen(path, "rb");
	char *buf;
	long n;

	if (!f) {
		fprintf(stderr, "spark-review-url: cannot open %s: %s\n",
			path, strerror(errno));
		exit(1);
	}
	if (fseek(f, 0, SEEK_END) != 0)
		die("fseek");
	n = ftell(f);
	if (n < 0 || n > MAX_BODY)
		die("body too large");
	rewind(f);
	buf = malloc((size_t)n + 1);
	if (!buf)
		die("oom");
	if (fread(buf, 1, (size_t)n, f) != (size_t)n)
		die("read");
	buf[n] = 0;
	fclose(f);
	if (out_len)
		*out_len = (size_t)n;
	return buf;
}

static char *fetch_http(const char *url, size_t *out_len)
{
	char tmp[] = "/tmp/spark-review-url-XXXXXX";
	int fd;
	pid_t pid;
	int st;
	char *body;

	fd = mkstemp(tmp);
	if (fd < 0)
		die("mkstemp");
	close(fd);

	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		execlp("curl", "curl", "-fsSL", "--max-time", "30",
		       "--max-filesize", "1048576", "-o", tmp, url,
		       (char *)NULL);
		_exit(127);
	}
	if (waitpid(pid, &st, 0) < 0)
		die("waitpid");
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		unlink(tmp);
		fprintf(stderr,
			"spark-review-url: curl fetch failed"
			" (rc=%d) for %s\n"
			"  Fix network/DNS, or use file:// fixture.\n",
			WIFEXITED(st) ? WEXITSTATUS(st) : -1, url);
		exit(1);
	}
	body = slurp_file(tmp, out_len);
	unlink(tmp);
	return body;
}

static int has_ci(const char *hay, const char *needle)
{
	return strcasestr(hay, needle) != NULL;
}

static void emit_report(FILE *out, const char *url, const char *body,
			size_t len, const char *source)
{
	int has_eval = has_ci(body, "eval(") || has_ci(body, "eval (");
	int has_fn = has_ci(body, "Function(") ||
		     has_ci(body, "new Function");
	int has_doc = has_ci(body, "document.write");
	int has_inner = has_ci(body, "innerHTML");
	const char *level = "mid";
	const char *complexity = "mid";
	char issues[512];
	size_t n = 0;

	issues[0] = 0;
	if (has_eval)
		n += (size_t)snprintf(issues + n, sizeof(issues) - n,
				      "%s\"possible eval\"",
				      n ? "," : "");
	if (has_fn)
		n += (size_t)snprintf(issues + n, sizeof(issues) - n,
				      "%s\"Function constructor\"",
				      n ? "," : "");
	if (has_doc)
		n += (size_t)snprintf(issues + n, sizeof(issues) - n,
				      "%s\"document.write\"",
				      n ? "," : "");
	if (has_inner)
		n += (size_t)snprintf(issues + n, sizeof(issues) - n,
				      "%s\"innerHTML assign\"",
				      n ? "," : "");
	if (n == 0)
		snprintf(issues, sizeof(issues), "\"none detected\"");

	if (has_eval || has_fn) {
		level = "higher";
		complexity = "mid";
	} else if (strstr(url, ".s") || strstr(url, ".asm")) {
		level = "lower";
		complexity = "low";
	}

	fprintf(out,
		"{\"op\":\"review.url\",\"source\":\"%s\","
		"\"url\":\"%s\",\"bytes\":%zu,\"fetched\":%s,"
		"\"eval\":false,\"issues\":[%s],"
		"\"complexity\":\"%s\","
		"\"suggested_level\":\"%s\","
		"\"rationale\":\"static byte scan only —"
		" never eval web JS\"}\n",
		source, url, len,
		strcmp(source, "http") == 0 ? "true" : "false", issues,
		complexity, level);
}

static int is_remote(const char *url)
{
	return strncmp(url, "http://", 7) == 0 ||
	       strncmp(url, "https://", 8) == 0;
}

static const char *local_path(const char *url)
{
	if (strncmp(url, "file://", 7) == 0)
		return url + 7;
	return url;
}

int main(int argc, char **argv)
{
	const char *url = NULL;
	const char *out_path = NULL;
	int allow_net = 0;
	int i;
	char *body;
	size_t len = 0;
	const char *source;
	FILE *out;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--url") == 0 && i + 1 < argc)
			url = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else if (strcmp(argv[i], "--allow-net") == 0)
			allow_net = 1;
		else if (strcmp(argv[i], "--help") == 0) {
			fputs("spark-review-url --url URL"
			      " [--out path] [--allow-net]\n"
			      "  file:// always; http(s) needs"
			      " --allow-net (default: no dial)\n",
			      stdout);
			return 0;
		} else
			die("unknown arg");
	}
	if (!url || !url[0])
		die("need --url");

	if (is_remote(url)) {
		if (!allow_net)
			refuse_remote(url);
		body = fetch_http(url, &len);
		source = "http";
	} else {
		body = slurp_file(local_path(url), &len);
		source = "file";
	}

	out = out_path ? fopen(out_path, "wb") : stdout;
	if (!out)
		die("cannot open --out");
	emit_report(out, url, body, len, source);
	if (out_path)
		fclose(out);
	free(body);
	return 0;
}
