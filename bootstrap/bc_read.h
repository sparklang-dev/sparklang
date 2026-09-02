/* Load .sparkbc (docs/SPARK_BC.md). Fail loud on bad magic. */
#ifndef SPARK_BC_READ_H
#define SPARK_BC_READ_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint8_t *bytes;
  uint16_t len;
} SparkBcStr;

typedef struct {
  uint8_t kind;
  uint16_t payload;
} SparkBcConst;

typedef struct {
  SparkBcStr *strs;
  uint16_t nstrs;
  SparkBcConst *consts;
  uint16_t nconsts;
  uint8_t *code;
  uint32_t ncode;
} SparkBc;

int spark_bc_load(const char *path, SparkBc *out);
void spark_bc_free(SparkBc *bc);

#endif
