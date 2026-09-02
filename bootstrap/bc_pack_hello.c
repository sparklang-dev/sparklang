/* Pack golden hello.sparkbc — encoding only, not a compiler.
 * Strings/ops from examples/hello.spark + docs/SPARK_BC.md. */
#include "bc_opcodes.h"
#include "bc_read.h"
#include "bc_write.h"

#include <stdio.h>
#include <string.h>

static void set_str(SparkBcStr *s, const char *lit)
{
  s->bytes = (uint8_t *)lit;
  s->len = (uint16_t)strlen(lit);
}

int main(int argc, char **argv)
{
  const char *path = "selfhost/fixtures/hello.sparkbc";
  SparkBcStr strs[3];
  SparkBcConst consts[3];
  uint8_t code[12];
  SparkBc bc;

  if (argc > 1)
    path = argv[1];

  /* hello.spark: model code / ask "Explain gravity…" -> text / print */
  set_str(&strs[0], "code");
  set_str(&strs[1], "Explain gravity in one sentence");
  set_str(&strs[2], "text");

  consts[0].kind = SPBC_CONST_STR;
  consts[0].payload = 0;
  consts[1].kind = SPBC_CONST_STR;
  consts[1].payload = 1;
  consts[2].kind = SPBC_CONST_STR;
  consts[2].payload = 2;

  /* MODEL 0; ASK 1 2; PRINT 2; HALT — docs/SPARK_BC.md */
  code[0] = SPBC_OP_MODEL;
  code[1] = 0x00;
  code[2] = 0x00;
  code[3] = SPBC_OP_ASK;
  code[4] = 0x01;
  code[5] = 0x00;
  code[6] = 0x02;
  code[7] = 0x00;
  code[8] = SPBC_OP_PRINT;
  code[9] = 0x02;
  code[10] = 0x00;
  code[11] = SPBC_OP_HALT;

  memset(&bc, 0, sizeof(bc));
  bc.strs = strs;
  bc.nstrs = 3;
  bc.consts = consts;
  bc.nconsts = 3;
  bc.code = code;
  bc.ncode = 12;

  if (spark_bc_write(path, &bc) != 0)
    return 1;
  fprintf(stderr, "wrote %s\n", path);
  return 0;
}
