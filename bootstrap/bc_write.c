/* Write SPARK_BC (docs/SPARK_BC.md). Packer helper, not a compiler. */
#include "bc_write.h"
#include "bc_opcodes.h"

#include <stdio.h>
#include <stdint.h>

static int wr_u8(FILE *f, uint8_t v)
{
  return fwrite(&v, 1, 1, f) == 1 ? 0 : 1;
}

static int wr_u16le(FILE *f, uint16_t v)
{
  uint8_t b[2];
  b[0] = (uint8_t)(v & 0xff);
  b[1] = (uint8_t)((v >> 8) & 0xff);
  return fwrite(b, 1, 2, f) == 2 ? 0 : 1;
}

static int wr_u32le(FILE *f, uint32_t v)
{
  uint8_t b[4];
  b[0] = (uint8_t)(v & 0xff);
  b[1] = (uint8_t)((v >> 8) & 0xff);
  b[2] = (uint8_t)((v >> 16) & 0xff);
  b[3] = (uint8_t)((v >> 24) & 0xff);
  return fwrite(b, 1, 4, f) == 4 ? 0 : 1;
}

int spark_bc_write(const char *path, const SparkBc *bc)
{
  FILE *f;
  uint16_t i;

  if (!path || !bc)
    return 1;
  f = fopen(path, "wb");
  if (!f) {
    perror(path);
    return 1;
  }
  if (wr_u8(f, SPBC_MAGIC0) || wr_u8(f, SPBC_MAGIC1) ||
      wr_u8(f, SPBC_MAGIC2) || wr_u8(f, SPBC_MAGIC3) ||
      wr_u8(f, SPBC_VERSION) || wr_u16le(f, bc->nstrs)) {
    fprintf(stderr, "error: SPARK_BC write header\n");
    fclose(f);
    return 1;
  }
  for (i = 0; i < bc->nstrs; i++) {
    if (wr_u16le(f, bc->strs[i].len) ||
        (bc->strs[i].len > 0 &&
         fwrite(bc->strs[i].bytes, 1, bc->strs[i].len, f) !=
             bc->strs[i].len)) {
      fprintf(stderr, "error: SPARK_BC write string\n");
      fclose(f);
      return 1;
    }
  }
  if (wr_u16le(f, bc->nconsts)) {
    fclose(f);
    return 1;
  }
  for (i = 0; i < bc->nconsts; i++) {
    if (wr_u8(f, bc->consts[i].kind) ||
        wr_u16le(f, bc->consts[i].payload)) {
      fprintf(stderr, "error: SPARK_BC write const\n");
      fclose(f);
      return 1;
    }
  }
  if (wr_u32le(f, bc->ncode)) {
    fclose(f);
    return 1;
  }
  if (bc->ncode > 0 &&
      fwrite(bc->code, 1, bc->ncode, f) != bc->ncode) {
    fprintf(stderr, "error: SPARK_BC write code\n");
    fclose(f);
    return 1;
  }
  if (fclose(f) != 0) {
    perror(path);
    return 1;
  }
  return 0;
}
