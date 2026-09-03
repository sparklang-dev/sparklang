/* SparkLang C host embed — fork/exec ./spark --dry-run|--live. */
#define _GNU_SOURCE
#include "sparklang.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int is_exec(const char *p)
{
	struct stat st;

	if (!p || access(p, X_OK) != 0)
		return 0;
	if (stat(p, &st) != 0)
		return 0;
	return S_ISREG(st.st_mode);
}

static char *xstrdup(const char *s)
{
	size_t n;
	char *o;

	if (!s)
		s = "";
	n = strlen(s);
	o = malloc(n + 1);
	if (!o)
		return NULL;
	memcpy(o, s, n + 1);
	return o;
}

char *spark_find_bin(const char *explicit_path)
{
	char cand[4096];
	const char *env;
	char *pathenv;
	char *tok;
	char *save;
	char *copy;

	if (explicit_path && is_exec(explicit_path))
		return xstrdup(explicit_path);
	env = getenv("SPARK_BIN");
	if (env && is_exec(env))
		return xstrdup(env);
	if (getcwd(cand, sizeof(cand))) {
		size_t n = strlen(cand);
		if (n + 7 < sizeof(cand)) {
			memcpy(cand + n, "/spark", 7);
			if (is_exec(cand))
				return xstrdup(cand);
		}
	}
	pathenv = getenv("PATH");
	if (!pathenv)
		return NULL;
	copy = xstrdup(pathenv);
	if (!copy)
		return NULL;
	for (tok = strtok_r(copy, ":", &save); tok;
	     tok = strtok_r(NULL, ":", &save)) {
		snprintf(cand, sizeof(cand), "%s/spark", tok);
		if (is_exec(cand)) {
			free(copy);
			return xstrdup(cand);
		}
	}
	free(copy);
	return NULL;
}

static int read_fd(int fd, char **out)
{
	size_t cap = 4096, n = 0;
	char *buf = malloc(cap);
	ssize_t r;

	if (!buf)
		return -1;
	for (;;) {
		if (n + 512 > cap) {
			char *nb;
			cap *= 2;
			nb = realloc(buf, cap);
			if (!nb) {
				free(buf);
				return -1;
			}
			buf = nb;
		}
		r = read(fd, buf + n, cap - n - 1);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			free(buf);
			return -1;
		}
		if (r == 0)
			break;
		n += (size_t)r;
	}
	buf[n] = '\0';
	*out = buf;
	return 0;
}

int spark_run_path(const char *program, int live, SparkRunResult *out)
{
	char *bin;
	int outp[2], errp[2];
	pid_t pid;
	int status;
	const char *flag;

	if (!program || !out)
		return -1;
	memset(out, 0, sizeof(*out));
	flag = live ? "--live" : "--dry-run";
	snprintf(out->mode, sizeof(out->mode), "%s",
		 live ? "live" : "dry-run");
	bin = spark_find_bin(NULL);
	if (!bin)
		return -1;
	if (pipe(outp) != 0 || pipe(errp) != 0) {
		free(bin);
		return -1;
	}
	pid = fork();
	if (pid < 0) {
		free(bin);
		return -1;
	}
	if (pid == 0) {
		char *argv[4];

		dup2(outp[1], STDOUT_FILENO);
		dup2(errp[1], STDERR_FILENO);
		close(outp[0]);
		close(outp[1]);
		close(errp[0]);
		close(errp[1]);
		argv[0] = bin;
		argv[1] = (char *)flag;
		argv[2] = (char *)program;
		argv[3] = NULL;
		execve(bin, argv, environ);
		_exit(127);
	}
	close(outp[1]);
	close(errp[1]);
	if (read_fd(outp[0], &out->stdout_s) != 0)
		out->stdout_s = xstrdup("");
	if (read_fd(errp[0], &out->stderr_s) != 0)
		out->stderr_s = xstrdup("");
	close(outp[0]);
	close(errp[0]);
	if (waitpid(pid, &status, 0) < 0) {
		free(bin);
		return -1;
	}
	if (WIFEXITED(status))
		out->returncode = WEXITSTATUS(status);
	else
		out->returncode = 1;
	free(bin);
	return 0;
}

void spark_run_free(SparkRunResult *r)
{
	if (!r)
		return;
	free(r->stdout_s);
	free(r->stderr_s);
	r->stdout_s = NULL;
	r->stderr_s = NULL;
}
