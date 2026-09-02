/* Load SPARK_BC (docs/SPARK_BC.md). Fail loud. */
#include "bc_read.h"
#include "bc_opcodes.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail_trunc(const char *what)
{
  fprintf(stderr, "error: truncated SPARK_BC (%s)\n", what);
}

static int need(const uint8_t *p, const uint8_t *end, size_t n,
                const char *what)
{
  if ((size_t)(end - p) < n) {
    fail_trunc(what);
    return 1;
  }
  return 0;
}

static uint16_t u16le(const uint8_t *p)
{
  return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t u32le(const uint8_t *p)
{
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

void spark_bc_free(SparkBc *bc)
{
  uint16_t i;
  if (!bc)
    return;
  if (bc->strs) {
    for (i = 0; i < bc->nstrs; i++)
      free(bc->strs[i].bytes);
    free(bc->strs);
  }
  free(bc->consts);
  free(bc->code);
  memset(bc, 0, sizeof(*bc));
}

int spark_bc_load(const char *path, SparkBc *out)
{
  FILE *f;
  uint8_t *buf = NULL;
  long flen;
  const uint8_t *p;
  const uint8_t *end;
  uint16_t i;
  int rc = 1;

  memset(out, 0, sizeof(*out));
  f = fopen(path, "rb");
  if (!f) {
    perror(path);
    return 1;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    perror(path);
    fclose(f);
    return 1;
  }
  flen = ftell(f);
  if (flen < 0 || fseek(f, 0, SEEK_SET) != 0) {
    perror(path);
    fclose(f);
    return 1;
  }
  buf = malloc((size_t)flen + 1);
  if (!buf) {
    fprintf(stderr, "error: SPARK_BC OOM\n");
    fclose(f);
    return 1;
  }
  if (flen > 0 &&
      fread(buf, 1, (size_t)flen, f) != (size_t)flen) {
    fail_trunc("read");
    fclose(f);
    free(buf);
    return 1;
  }
  fclose(f);
  p = buf;
  end = buf + flen;

  if (need(p, end, 5, "magic") != 0)
    goto done;
  if (p[0] != SPBC_MAGIC0 || p[1] != SPBC_MAGIC1 ||
      p[2] != SPBC_MAGIC2 || p[3] != SPBC_MAGIC3) {
    fprintf(stderr, "error: bad SPARK_BC magic (want SPBC)\n");
    goto done;
  }
  if (p[4] != SPBC_VERSION) {
    fprintf(stderr, "error: SPARK_BC version %u (want 1)\n",
            (unsigned)p[4]);
    goto done;
  }
  p += 5;

  if (need(p, end, 2, "nstrings") != 0)
    goto done;
  out->nstrs = u16le(p);
  p += 2;
  if (out->nstrs > 0) {
    out->strs = calloc(out->nstrs, sizeof(SparkBcStr));
    if (!out->strs) {
      fprintf(stderr, "error: SPARK_BC OOM\n");
      goto done;
    }
  }
  for (i = 0; i < out->nstrs; i++) {
    uint16_t n;
    if (need(p, end, 2, "str len") != 0)
      goto done;
    n = u16le(p);
    p += 2;
    if (need(p, end, n, "str bytes") != 0)
      goto done;
    out->strs[i].bytes = malloc((size_t)n + 1);
    if (!out->strs[i].bytes) {
      fprintf(stderr, "error: SPARK_BC OOM\n");
      goto done;
    }
    memcpy(out->strs[i].bytes, p, n);
    out->strs[i].bytes[n] = '\0';
    out->strs[i].len = n;
    p += n;
  }

  if (need(p, end, 2, "nconsts") != 0)
    goto done;
  out->nconsts = u16le(p);
  p += 2;
  if (out->nconsts > 0) {
    out->consts = calloc(out->nconsts, sizeof(SparkBcConst));
    if (!out->consts) {
      fprintf(stderr, "error: SPARK_BC OOM\n");
      goto done;
    }
  }
  for (i = 0; i < out->nconsts; i++) {
    if (need(p, end, 3, "const") != 0)
      goto done;
    out->consts[i].kind = p[0];
    out->consts[i].payload = u16le(p + 1);
    if (out->consts[i].kind != SPBC_CONST_STR) {
      fprintf(stderr, "error: unknown SPARK_BC const kind %u\n",
              (unsigned)out->consts[i].kind);
      goto done;
    }
    if (out->consts[i].payload >= out->nstrs) {
      fprintf(stderr,
              "error: SPARK_BC string index out of range\n");
      goto done;
    }
    p += 3;
  }

  if (need(p, end, 4, "ncode") != 0)
    goto done;
  out->ncode = u32le(p);
  p += 4;
  if (need(p, end, out->ncode, "code") != 0)
    goto done;
  if (out->ncode > 0) {
    out->code = malloc(out->ncode);
    if (!out->code) {
      fprintf(stderr, "error: SPARK_BC OOM\n");
      goto done;
    }
    memcpy(out->code, p, out->ncode);
  }
  p += out->ncode;
  if (p != end) {
    fprintf(stderr, "error: SPARK_BC trailing bytes\n");
    goto done;
  }
  rc = 0;

done:
  free(buf);
  if (rc != 0)
    spark_bc_free(out);
  return rc;
}
