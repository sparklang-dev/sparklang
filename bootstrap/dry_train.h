/* dry_train.h — offline model train/status fixtures (no GPU / no net). */
#ifndef SPARK_DRY_TRAIN_H
#define SPARK_DRY_TRAIN_H

/* NULL = missing / unknown method or job (caller must fail loud). */
const char *spark_pick_train_accept(const char *method, const char *job_id,
				    const char *dataset, const char *base,
				    const char *out_dir);
const char *spark_pick_train_status(const char *job_id);

#endif
