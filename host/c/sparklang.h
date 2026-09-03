/* SparkLang C host embed — run a .spark file via the spark ELF. */
#ifndef SPARK_HOST_C_H
#define SPARK_HOST_C_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
	int returncode;
	char *stdout_s;
	char *stderr_s;
	char mode[16];
} SparkRunResult;

/* Locate spark ELF. Returns malloc'd path or NULL. */
char *spark_find_bin(const char *explicit_path);

/* Run path with --dry-run (live=0) or --live (live=1).
 * Fills *out (caller spark_run_free). Returns 0 on invoke, -1 on error. */
int spark_run_path(const char *program, int live, SparkRunResult *out);

void spark_run_free(SparkRunResult *r);

#ifdef __cplusplus
}
#endif

#endif
