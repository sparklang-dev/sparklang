/* dry_train.c — fixture strings for model train / status dry-run. */
#include "dry_train.h"

#include <string.h>

static const char DRY_TRAIN_ACCEPT[] =
    "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    "\"backend\":\"http\",\"status\":\"accepted\","
    "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    "\"base\":\"fixture-base\",\"out\":\"out/train/job-dry-001\","
    "\"artifacts\":{"
    "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    "\"note\":\"dry-run — no GPU, no network; artifact paths are "
    "planned stubs\"}";

static const char DRY_TRAIN_STATUS[] =
    "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    "\"state\":\"succeeded\",\"backend\":\"http\","
    "\"artifacts\":{"
    "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    "\"note\":\"dry-run fixture — weights not trained on this host\"}";

const char *spark_pick_train_accept(void)
{
	return DRY_TRAIN_ACCEPT;
}

const char *spark_pick_train_status(const char *job_id)
{
	(void)job_id;
	return DRY_TRAIN_STATUS;
}
