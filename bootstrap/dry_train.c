/* dry_train.c — fixture strings for model train / status / step. */
#include "dry_train.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static char accept_buf[1536];
static char status_buf[1024];
static char step_buf[1024];

static int method_ok(const char *method)
{
	return method &&
	       (strcmp(method, "spark_distill_cpu") == 0 ||
		strcmp(method, "spark_pref_pack") == 0 ||
		strcmp(method, "spark_playbook_fit") == 0 ||
		strcmp(method, "spark_faq_index") == 0 ||
		strcmp(method, "spark_reply_pack") == 0);
}

static int dry_job_ok(const char *job_id)
{
	return job_id &&
	       (strcmp(job_id, "job-dry-001") == 0 ||
		strcmp(job_id, "job-pref-001") == 0 ||
		strcmp(job_id, "job-play-001") == 0 ||
		strcmp(job_id, "job-faq-001") == 0 ||
		strcmp(job_id, "job-reply-001") == 0);
}

const char *spark_pick_train_accept(const char *method, const char *job_id,
				    const char *dataset, const char *base,
				    const char *out_dir)
{
	if (!method_ok(method))
		return NULL;
	if (!job_id || !job_id[0])
		job_id = "job-dry-001";
	if (!dry_job_ok(job_id) && strncmp(job_id, "job-", 4) != 0)
		return NULL;
	if (!dataset)
		dataset = "examples/fixtures/train/dataset.jsonl";
	if (!base)
		base = "fixture-base";
	if (!out_dir)
		out_dir = "out/train/job-dry-001";
	if (snprintf(accept_buf, sizeof(accept_buf),
		     "{\"op\":\"train\",\"mode\":\"dry-run\","
		     "\"job_id\":\"%s\",\"backend\":\"http\","
		     "\"method\":\"%s\",\"status\":\"accepted\","
		     "\"dataset\":\"%s\",\"base\":\"%s\",\"out\":\"%s\","
		     "\"artifacts\":{"
		     "\"adapter\":\"%s/adapter.bin\","
		     "\"checkpoint\":\"%s/checkpoint.json\","
		     "\"marker\":\"%s/ARTIFACT\"},"
		     "\"note\":\"dry-run — method planned; no train on "
		     "this host\"}",
		     job_id, method, dataset, base, out_dir, out_dir,
		     out_dir, out_dir) >= (int)sizeof(accept_buf))
		return NULL;
	return accept_buf;
}

const char *spark_pick_train_status(const char *job_id)
{
	if (!job_id || !job_id[0])
		job_id = "job-dry-001";
	if (!dry_job_ok(job_id))
		return NULL;
	if (snprintf(status_buf, sizeof(status_buf),
		     "{\"op\":\"status\",\"mode\":\"dry-run\","
		     "\"job_id\":\"%s\",\"state\":\"succeeded\","
		     "\"backend\":\"http\","
		     "\"artifacts\":{"
		     "\"adapter\":\"out/train/%s/adapter.bin\","
		     "\"checkpoint\":\"out/train/%s/checkpoint.json\","
		     "\"marker\":\"out/train/%s/ARTIFACT\"},"
		     "\"note\":\"dry-run fixture — weights not trained "
		     "on this host\"}",
		     job_id, job_id, job_id, job_id) >=
	    (int)sizeof(status_buf))
		return NULL;
	return status_buf;
}

const char *spark_pick_train_step(const char *job_id, int step_n)
{
	if (!job_id || !job_id[0])
		job_id = "job-dry-001";
	if (!dry_job_ok(job_id))
		return NULL;
	if (step_n < 1)
		step_n = 1;
	if (snprintf(step_buf, sizeof(step_buf),
		     "{\"op\":\"step\",\"mode\":\"cpu-sgd\","
		     "\"job_id\":\"%s\",\"step\":%d,"
		     "\"state\":\"stepped\",\"backend\":\"http\","
		     "\"artifacts\":{"
		     "\"marker\":\"out/train/%s/ARTIFACT\","
		     "\"weights\":\"out/train/%s/weights.safetensors\"},"
		     "\"note\":\"CPU multi-outer SGD STEP — real grads "
		     "on Spark tensors; tiny; no frontier-parity claim\"}",
		     job_id, step_n, job_id, job_id) >=
	    (int)sizeof(step_buf))
		return NULL;
	return step_buf;
}

static int mkdir_p(const char *path)
{
	char buf[512];
	size_t i;
	size_t n;

	if (!path || !path[0])
		return -1;
	n = strlen(path);
	if (n >= sizeof(buf))
		return -1;
	memcpy(buf, path, n + 1);
	for (i = 1; i < n; i++) {
		if (buf[i] != '/')
			continue;
		buf[i] = '\0';
		if (mkdir(buf, 0755) != 0 && errno != EEXIST)
			return -1;
		buf[i] = '/';
	}
	if (mkdir(buf, 0755) != 0 && errno != EEXIST)
		return -1;
	return 0;
}

int spark_write_train_marker(const char *out_dir, const char *job_id,
			     const char *method)
{
	char path[512];
	char body[640];
	int n;
	FILE *f;

	if (!out_dir || !out_dir[0])
		return 1;
	if (!job_id || !job_id[0])
		job_id = "job-dry-001";
	if (!method || !method[0])
		method = "spark_distill_cpu";
	if (mkdir_p(out_dir) != 0) {
		fprintf(stderr, "error: train mkdir failed %s\n",
			out_dir);
		return 1;
	}
	n = snprintf(path, sizeof(path), "%s/ARTIFACT", out_dir);
	if (n < 0 || n >= (int)sizeof(path))
		return 1;
	n = snprintf(body, sizeof(body),
		     "spark-train-dry %s\n"
		     "method=%s\n"
		     "mode=dry-run-fixture\n"
		     "not_sgd=true\n"
		     "trained=false\n"
		     "adapter=%s/adapter.bin\n"
		     "checkpoint=%s/checkpoint.json\n"
		     "note=dry fixture -- not SGD; not a trained model\n",
		     job_id, method, out_dir, out_dir);
	if (n < 0 || n >= (int)sizeof(body))
		return 1;
	f = fopen(path, "w");
	if (!f) {
		perror(path);
		return 1;
	}
	if (fwrite(body, 1, (size_t)n, f) != (size_t)n) {
		fclose(f);
		fprintf(stderr, "error: train marker write failed\n");
		return 1;
	}
	fclose(f);
	return 0;
}

int spark_bump_train_step(const char *out_dir, const char *job_id,
			  int step_n)
{
	char path[512];
	char body[704];
	int n;
	FILE *f;

	if (!out_dir || !out_dir[0])
		return 1;
	if (!job_id || !job_id[0])
		job_id = "job-dry-001";
	if (step_n < 1)
		step_n = 1;
	if (mkdir_p(out_dir) != 0) {
		fprintf(stderr, "error: train step mkdir failed %s\n",
			out_dir);
		return 1;
	}
	n = snprintf(path, sizeof(path), "%s/ARTIFACT", out_dir);
	if (n < 0 || n >= (int)sizeof(path))
		return 1;
	n = snprintf(body, sizeof(body),
		     "spark-train-sgd %s\n"
		     "mode=cpu-sgd\n"
		     "not_sgd=false\n"
		     "trained=true\n"
		     "step_n=%d\n"
		     "op=step\n"
		     "weights=%s/weights.safetensors\n"
		     "checkpoint=%s/checkpoint.json\n"
		     "note=CPU multi-outer SGD -- real grads; "
		     "tiny; no frontier-parity claim\n",
		     job_id, step_n, out_dir, out_dir);
	if (n < 0 || n >= (int)sizeof(body))
		return 1;
	f = fopen(path, "w");
	if (!f) {
		perror(path);
		return 1;
	}
	if (fwrite(body, 1, (size_t)n, f) != (size_t)n) {
		fclose(f);
		fprintf(stderr, "error: train step marker write failed\n");
		return 1;
	}
	fclose(f);
	return 0;
}

int spark_bump_train_weights(const char *out_dir, const char *job_id,
			     const char *sparkbc_path, int step_n)
{
	char weights[512];
	char cmd[2048];
	int n;
	int st;
	FILE *probe;

	(void)job_id;
	if (!out_dir || !out_dir[0])
		return 1;
	if (!sparkbc_path || !sparkbc_path[0]) {
		fprintf(stderr,
			"error: STEP weights need SPARK_BC path\n");
		return 1;
	}
	if (step_n < 1)
		step_n = 1;
	if (mkdir_p(out_dir) != 0) {
		fprintf(stderr, "error: train weights mkdir failed %s\n",
			out_dir);
		return 1;
	}
	n = snprintf(weights, sizeof(weights), "%s/weights.safetensors",
		     out_dir);
	if (n < 0 || n >= (int)sizeof(weights))
		return 1;
	probe = fopen("tools/spark-bc-dump/apply_step.py", "r");
	if (!probe) {
		fprintf(stderr,
			"error: missing tools/spark-bc-dump/apply_step.py "
			"(run from repo root)\n");
		return 1;
	}
	fclose(probe);
	/* Paths from this repo have no spaces; fail loud if spawn fails. */
	n = snprintf(cmd, sizeof(cmd),
		     "PYTHONPATH=python python3 "
		     "tools/spark-bc-dump/apply_step.py "
		     "--sparkbc %s --weights %s --step %d "
		     "--dataset examples/fixtures/train/dataset.jsonl "
		     "--outer 4 --inner 8 "
		     "--checkpoint %s/checkpoint.json "
		     "--command './spark-bootstrap --run-bc %s'",
		     sparkbc_path, weights, step_n, out_dir,
		     sparkbc_path);
	if (n < 0 || n >= (int)sizeof(cmd))
		return 1;
	st = system(cmd);
	if (st != 0) {
		fprintf(stderr,
			"error: SGD STEP weight write failed "
			"(status %d)\n",
			st);
		return 1;
	}
	probe = fopen(weights, "rb");
	if (!probe) {
		fprintf(stderr, "error: missing STEP weights %s\n",
			weights);
		return 1;
	}
	fclose(probe);
	return 0;
}
