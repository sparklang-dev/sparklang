/* dry_train.c — fixture strings for model train / status dry-run. */
#include "dry_train.h"

#include <stdio.h>
#include <string.h>

static char accept_buf[1536];
static char status_buf[1024];

static int method_ok(const char *method)
{
	return method &&
	       (strcmp(method, "spark_distill_cpu") == 0 ||
		strcmp(method, "spark_pref_pack") == 0 ||
		strcmp(method, "spark_playbook_fit") == 0 ||
		strcmp(method, "spark_faq_index") == 0);
}

static int dry_job_ok(const char *job_id)
{
	return job_id &&
	       (strcmp(job_id, "job-dry-001") == 0 ||
		strcmp(job_id, "job-pref-001") == 0 ||
		strcmp(job_id, "job-play-001") == 0 ||
		strcmp(job_id, "job-faq-001") == 0);
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
