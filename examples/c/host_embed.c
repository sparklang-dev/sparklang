/* Example: run examples/hello.spark from C (dry-run). */
#include "../../host/c/sparklang.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void die(const char *msg)
{
	fprintf(stderr, "host_embed: %s\n", msg);
	exit(1);
}

int main(void)
{
	char path[4096];
	SparkRunResult r;
	int rc;

	if (!getcwd(path, sizeof(path)))
		die("getcwd");
	if (strlen(path) + 32 >= sizeof(path))
		die("path too long");
	strcat(path, "/examples/hello.spark");
	if (spark_run_path(path, 0, &r) != 0)
		die("spark_run_path failed (missing ./spark?)");
	if (r.stdout_s)
		fputs(r.stdout_s, stdout);
	if (r.stderr_s)
		fputs(r.stderr_s, stderr);
	rc = r.returncode;
	spark_run_free(&r);
	return rc;
}
