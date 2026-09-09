/* dry_train.h — offline model train/status fixtures (no GPU / no net). */
#ifndef SPARK_DRY_TRAIN_H
#define SPARK_DRY_TRAIN_H

/* NULL = missing / unknown method or job (caller must fail loud). */
const char *spark_pick_train_accept(const char *method, const char *job_id,
				    const char *dataset, const char *base,
				    const char *out_dir);
const char *spark_pick_train_status(const char *job_id);
const char *spark_pick_train_step(const char *job_id, int step_n);

/* Dry ARTIFACT under out_dir. Not SGD. Not trained weights. */
int spark_write_train_marker(const char *out_dir, const char *job_id,
			     const char *method);
/* Bump step_n on ARTIFACT (dry loop). Not SGD. */
int spark_bump_train_step(const char *out_dir, const char *job_id,
			  int step_n);

#endif
