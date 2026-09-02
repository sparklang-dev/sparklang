/* Engine dry ops — shared by bc_vm (SPARK_BC). Uses engine_*.c spine. */
#ifndef SPARK_DRY_ENGINE_H
#define SPARK_DRY_ENGINE_H

#include "vm.h"

typedef struct {
  void *frame;
  int (*vars_put)(void *frame, const char *name, const char *val);
  char last[SPARK_VM_VAL_MAX];
} SparkDryEngineCtx;

int spark_dry_engine_fetch(SparkDryEngineCtx *ctx, const char *url,
                           int want_parse, const char *bind);
int spark_dry_engine_parse(SparkDryEngineCtx *ctx, const char *path,
                           const char *bind);
int spark_dry_engine_css(SparkDryEngineCtx *ctx, const char *bind);
int spark_dry_engine_layout(SparkDryEngineCtx *ctx, int fixture,
                            const char *bind);
int spark_dry_engine_paint(SparkDryEngineCtx *ctx, int fixture, int boxes,
                           const char *bind);
int spark_dry_engine_show(SparkDryEngineCtx *ctx, const char *path,
                          const char *bind);
int spark_dry_engine_render(SparkDryEngineCtx *ctx, const char *bind);

/* Tree-walk fallback when compile fails (gas_only negative fixtures). */
int spark_dry_engine_run_line(SparkDryEngineCtx *ctx, char *line);

void spark_dry_engine_reset(void);

#endif
