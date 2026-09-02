/* dry_train.h — offline model train/status fixtures (no GPU / no net). */
#ifndef SPARK_DRY_TRAIN_H
#define SPARK_DRY_TRAIN_H

const char *spark_pick_train_accept(void);
const char *spark_pick_train_status(const char *job_id);

#endif
