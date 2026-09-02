/*
 * spark-ask-probe — public gateway probe credential check.
 *
 * --dry (default): no network. Report secret-manager/project readiness.
 * --live: secret-manager probe path + curl BIFROST_URL; model=fast.
 *
 * HTTP 401 / secret-manager miss → "credential unavailable", exit 4.
 * Never echo/log/write probe credential. Never ask to mint PAT/GitHub.
 * Do not invent routing conclusions from 401.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define DEFAULT_URL "https://ai-gateway.example"

static void resolve_secret_path(char *out, size_t out_sz, const char *leaf)
{
	const char *home;
	const char *override;

	override = getenv("SPARK_ASK_PROBE_SECRETS_DIR");
	if (override && override[0]) {
		snprintf(out, out_sz, "%s/%s", override, leaf);
		return;
	}
	home = getenv("HOME");
	if (!home || !home[0])
		home = ".";
	snprintf(out, out_sz, "%s/.config/spark/secrets/%s", home, leaf);
}

static int file_nonempty(const char *path)
{
	struct stat st;

	if (stat(path, &st) != 0)
		return 0;
	return st.st_size > 0;
}

static int project_id_ready(char *out, size_t out_sz)
{
	const char *env;
	FILE *f;
	size_t n;
	char pid_path[512];

	env = getenv("INFISICAL_BIFROST_PROBES_PROJECT_ID");
	if (env && env[0] && strcmp(env, "<PROJECT_ID>") != 0) {
		snprintf(out, out_sz, "%s", env);
		return 1;
	}
	resolve_secret_path(pid_path, sizeof(pid_path),
			    "gateway-probes-project-id.txt");
	f = fopen(pid_path, "r");
	if (!f)
		return 0;
	if (!fgets(out, (int)out_sz, f)) {
		fclose(f);
		return 0;
	}
	fclose(f);
	n = strlen(out);
	while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r'))
		out[--n] = 0;
	return n > 0 && strcmp(out, "<PROJECT_ID>") != 0;
}

static void print_json(const char *status, int project_set, int mi_set,
		       int infisical_bin, const char *mode, int http)
{
	printf("{\"op\":\"ask_probe\",\"mode\":\"%s\","
	       "\"gateway_url\":\"%s\","
	       "\"secrets_path\":\"probe-credentials\","
	       "\"project_id_set\":%s,\"machine_identity_set\":%s,"
	       "\"secrets_cli\":%s,\"http\":%s,"
	       "\"status\":\"%s\","
	       "\"never\":[\"echo probe credential\",\"mint GitHub PAT\","
	       "\"reuse cursor-ide\",\"invent routing from 401\"]}\n",
	       mode, DEFAULT_URL,
	       project_set ? "true" : "false",
	       mi_set ? "true" : "false",
	       infisical_bin ? "true" : "false",
	       http >= 0 ? (http == 200 ? "200" : (http == 401 ? "401" : "other"))
			: "null",
	       status);
}

static int cmd_dry(void)
{
	char pid[128];
	char mi_path[512];
	int project_set;
	int mi_set;
	int has_cli;
	int force;

	resolve_secret_path(mi_path, sizeof(mi_path),
			    "gateway-probe-machine-identity.env");
	force = getenv("SPARK_ASK_PROBE_FORCE_UNAVAILABLE") != NULL;
	project_set = !force && project_id_ready(pid, sizeof(pid));
	mi_set = !force && file_nonempty(mi_path);
	has_cli = access("/usr/bin/infisical", X_OK) == 0 ||
		  access("/usr/local/bin/infisical", X_OK) == 0;

	if (force) {
		print_json("credential unavailable", 0, 0, has_cli, "dry",
			   -1);
		fprintf(stderr,
			"spark-ask-probe: credential unavailable\n");
		return 4;
	}
	if (!project_set || !mi_set || !has_cli) {
		/* Dry reports status without failing — offline make test
		 * must not require live secrets on disk. */
		print_json("credential unavailable", project_set, mi_set,
			   has_cli, "dry", -1);
		return 0;
	}
	print_json("ready (dry — no network)", 1, 1, 1, "dry", -1);
	return 0;
}

static int cmd_live(void)
{
	char pid[128];
	char mi_path[512];
	pid_t child;
	int status;
	int code;

	resolve_secret_path(mi_path, sizeof(mi_path),
			    "gateway-probe-machine-identity.env");
	if (!project_id_ready(pid, sizeof(pid))) {
		print_json("credential unavailable", 0,
			   file_nonempty(mi_path), 1, "live", -1);
		fprintf(stderr,
			"spark-ask-probe: credential unavailable\n");
		return 4;
	}
	if (!file_nonempty(mi_path)) {
		print_json("credential unavailable", 1, 0, 1, "live", -1);
		fprintf(stderr,
			"spark-ask-probe: credential unavailable\n");
		return 4;
	}

	/* Delegate to probe_public.sh (secret-manager wrap + curl). */
	child = fork();
	if (child < 0) {
		fprintf(stderr, "spark-ask-probe: fork failed\n");
		return 1;
	}
	if (child == 0) {
		setenv("INFISICAL_BIFROST_PROBES_PROJECT_ID", pid, 1);
		setenv("BIFROST_URL", DEFAULT_URL, 0);
		execl("/bin/bash", "bash",
		      "tools/ask/probe_public.sh", (char *)NULL);
		_exit(127);
	}
	if (waitpid(child, &status, 0) < 0)
		return 1;
	if (!WIFEXITED(status))
		return 1;
	code = WEXITSTATUS(status);
	if (code == 4) {
		print_json("credential unavailable", 1, 1, 1, "live", 401);
		return 4;
	}
	if (code == 0) {
		print_json("ok", 1, 1, 1, "live", 200);
		return 0;
	}
	print_json("http_non_200 (no routing conclusion)", 1, 1, 1,
		   "live", -1);
	return code ? code : 1;
}

int main(int argc, char **argv)
{
	int live = 0;
	int i;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--live"))
			live = 1;
		else if (!strcmp(argv[i], "--dry"))
			live = 0;
		else if (!strcmp(argv[i], "-h") ||
			 !strcmp(argv[i], "--help")) {
			fprintf(stderr,
				"usage: spark-ask-probe [--dry|--live]\n");
			return 0;
		}
	}
	if (getenv("SPARK_ASK_PROBE_LIVE") &&
	    strcmp(getenv("SPARK_ASK_PROBE_LIVE"), "0") != 0)
		live = 1;

	return live ? cmd_live() : cmd_dry();
}
