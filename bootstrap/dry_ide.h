/* IDE dry ops — shared by bc_vm (SPARK_BC). Parity with asm/ide_ops.s. */
#ifndef SPARK_DRY_IDE_H
#define SPARK_DRY_IDE_H

#include "vm.h"

typedef struct {
  void *frame;
  int (*vars_put)(void *frame, const char *name, const char *val);
  char last[SPARK_VM_VAL_MAX];
} SparkDryIdeCtx;

int spark_dry_ide_open(SparkDryIdeCtx *ctx, const char *path,
                       const char *bind);
int spark_dry_ide_run(SparkDryIdeCtx *ctx, const char *bind);
int spark_dry_ide_ask(SparkDryIdeCtx *ctx, const char *bind);
int spark_dry_ide_show(SparkDryIdeCtx *ctx, const char *path,
                       const char *bind);

#endif
