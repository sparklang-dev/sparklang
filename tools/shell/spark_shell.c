/*
 * spark-shell — gated argv exec for language shell/run.
 *
 * Allowlist: echo | true | false (basename only). Never system().
 * Never /bin/sh -c. Live is execve(2) of the resolved binary.
 *
 *   ./spark-shell --dry -- echo hello
 *   ./spark-shell --live -- echo hello
 *   ./spark-shell --live --argv-file PATH [--out PATH]
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_TOKENS 16
#define MAX_TOKEN 256
#define MAX_LINE 4096
#define MAX_CAPTURE (1 << 16)

static void die(const char *msg)
{
	fprintf(stderr, "spark-shell: %s\n", msg);
	exit(1);
}

static int has_meta(const char *s)
{
	const char *p;

	if (!s)
		return 1;
	for (p = s; *p; p++) {
		unsigned char c = (unsigned char)*p;
		if (c < 32 || c == 127)
			return 1;
		if (strchr(";|&$<>`(){}[]!*?\\\"'", *p))
			return 1;
	}
	return 0;
}

static int allowlisted_cmd(const char *cmd)
{
	if (!cmd || !*cmd)
		return 0;
	if (strchr(cmd, '/') || strchr(cmd, '.'))
		return 0;
	if (strcmp(cmd, "echo") == 0)
		return 1;
	if (strcmp(cmd, "true") == 0)
		return 1;
	if (strcmp(cmd, "false") == 0)
		return 1;
	return 0;
}

static const char *resolve_bin(const char *cmd)
{
	static const char *echo_c[] = {
		"/bin/echo", "/usr/bin/echo", NULL
	};
	static const char *true_c[] = {
		"/bin/true", "/usr/bin/true", NULL
	};
	static const char *false_c[] = {
		"/bin/false", "/usr/bin/false", NULL
	};
	const char **cands = NULL;
	int i;

	if (strcmp(cmd, "echo") == 0)
		cands = echo_c;
	else if (strcmp(cmd, "true") == 0)
		cands = true_c;
	else if (strcmp(cmd, "false") == 0)
		cands = false_c;
	else
		return NULL;
	for (i = 0; cands[i]; i++) {
		if (access(cands[i], X_OK) == 0)
			return cands[i];
	}
	return NULL;
}

static int tokenize(char *line, char **argv, int max)
{
	int n = 0;
	char *p = line;

	while (*p) {
		while (*p == ' ' || *p == '\t' || *p == '\n' ||
		       *p == '\r')
			p++;
		if (!*p)
			break;
		if (n >= max)
			return -1;
		argv[n++] = p;
		while (*p && *p != ' ' && *p != '\t' && *p != '\n' &&
		       *p != '\r')
			p++;
		if (*p) {
			*p = '\0';
			p++;
		}
	}
	return n;
}

static char *json_escape(const char *s)
{
	size_t need = 1;
	const char *p;
	char *out, *w;

	if (!s)
		s = "";
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
	*w = '\0';
	return out;
}

static void emit_json(FILE *of, const char *mode, const char *cmd,
		      const char *stdout_s, int ok, const char *note)
{
	char *esc_out;
	char *esc_note;

	esc_out = json_escape(stdout_s ? stdout_s : "");
	esc_note = json_escape(note ? note : "");
	fprintf(of,
		"{\"ok\":%s,\"mode\":\"%s\",\"argv\":\"%s\","
		"\"stdout\":\"%s\",\"note\":\"%s\"}\n",
		ok ? "true" : "false", mode, cmd, esc_out, esc_note);
	free(esc_out);
	free(esc_note);
}

static int run_execve(char *const argv[], char *capture, size_t cap,
		      int *child_rc)
{
	int pipefd[2];
	pid_t pid;
	ssize_t n, total = 0;
	int status;

	if (pipe(pipefd) != 0)
		die("pipe");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0) {
		close(pipefd[0]);
		if (dup2(pipefd[1], STDOUT_FILENO) < 0)
			_exit(127);
		if (dup2(pipefd[1], STDERR_FILENO) < 0)
			_exit(127);
		close(pipefd[1]);
		execve(argv[0], argv, environ);
		_exit(127);
	}
	close(pipefd[1]);
	while (total + 1 < (ssize_t)cap) {
		n = read(pipefd[0], capture + total,
			 cap - 1 - (size_t)total);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (n == 0)
			break;
		total += n;
	}
	capture[total] = '\0';
	close(pipefd[0]);
	if (waitpid(pid, &status, 0) < 0)
		die("waitpid");
	if (WIFEXITED(status))
		*child_rc = WEXITSTATUS(status);
	else
		*child_rc = 1;
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: spark-shell --dry|--live "
		"[--argv-file PATH] [--out PATH] [-- argv...]\n"
		"allowlist: echo | true | false (no path, no shell)\n");
	exit(2);
}

int main(int argc, char **argv)
{
	int dry = 0, live = 0, i, ntok, child_rc = 0, ok;
	const char *argv_file = NULL;
	const char *out_path = NULL;
	const char *resolved;
	char line[MAX_LINE];
	char *toks[MAX_TOKENS];
	char *exec_argv[MAX_TOKENS + 1];
	char capture[MAX_CAPTURE];
	FILE *of = stdout;
	FILE *f;
	size_t nread;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--dry") == 0)
			dry = 1;
		else if (strcmp(argv[i], "--live") == 0)
			live = 1;
		else if (strcmp(argv[i], "--argv-file") == 0 &&
			 i + 1 < argc)
			argv_file = argv[++i];
		else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc)
			out_path = argv[++i];
		else if (strcmp(argv[i], "--help") == 0)
			usage();
		else if (strcmp(argv[i], "--") == 0) {
			i++;
			break;
		} else
			usage();
	}
	if (dry == live)
		die("pass exactly one of --dry or --live");

	memset(line, 0, sizeof(line));
	if (argv_file) {
		f = fopen(argv_file, "rb");
		if (!f)
			die("cannot open --argv-file");
		nread = fread(line, 1, sizeof(line) - 1, f);
		fclose(f);
		line[nread] = '\0';
		ntok = tokenize(line, toks, MAX_TOKENS);
	} else {
		ntok = 0;
		for (; i < argc && ntok < MAX_TOKENS; i++) {
			if (strlen(argv[i]) >= MAX_TOKEN)
				die("token too long");
			toks[ntok++] = argv[i];
		}
		if (i < argc)
			die("too many argv tokens");
	}
	if (ntok <= 0)
		die("empty argv");
	for (i = 0; i < ntok; i++) {
		if (!toks[i][0] || strlen(toks[i]) >= MAX_TOKEN)
			die("bad token");
		if (has_meta(toks[i]))
			die("refused: metacharacter in argv "
			    "(not open system())");
	}
	if (!allowlisted_cmd(toks[0]))
		die("refused: argv[0] not on allowlist "
		    "(echo|true|false; no path)");

	if (out_path) {
		of = fopen(out_path, "wb");
		if (!of)
			die("cannot write --out");
	}

	if (dry) {
		const char *rest = (ntok > 1) ? toks[1] : "";
		char fixture[MAX_LINE];

		if (strcmp(toks[0], "echo") == 0) {
			snprintf(fixture, sizeof(fixture), "%s", rest);
			ok = 1;
		} else if (strcmp(toks[0], "true") == 0) {
			fixture[0] = '\0';
			ok = 1;
		} else {
			fixture[0] = '\0';
			ok = 0;
		}
		emit_json(of, "dry-run", toks[0], fixture, ok,
			  "fixture — no exec");
		if (of != stdout)
			fclose(of);
		return 0;
	}

	resolved = resolve_bin(toks[0]);
	if (!resolved)
		die("allowlisted binary not found on disk");
	exec_argv[0] = (char *)resolved;
	for (i = 1; i < ntok; i++)
		exec_argv[i] = toks[i];
	exec_argv[ntok] = NULL;

	capture[0] = '\0';
	run_execve(exec_argv, capture, sizeof(capture), &child_rc);
	ok = (child_rc == 0);
	{
		char note[80];

		snprintf(note, sizeof(note),
			 "execve allowlist rc=%d", child_rc);
		emit_json(of, "live", toks[0], capture, ok, note);
	}
	if (of != stdout)
		fclose(of);
	/* Companion exits 0 when execve ran; false(1) is in JSON. */
	return 0;
}
