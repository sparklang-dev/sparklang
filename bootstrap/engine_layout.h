/* C bootstrap engine layout — call asm/engine_layout.o dry spine.
 * Writes out/browser/engine/layout.json matching GAS stdout JSON. */
#ifndef SPARK_BOOTSTRAP_ENGINE_LAYOUT_H
#define SPARK_BOOTSTRAP_ENGINE_LAYOUT_H

#include <stddef.h>

#define EL_JSON_CAP 512
#define EL_PATH "out/browser/engine/layout.json"

/* DOM layout (needs prior engine parse). Optional css styles.
 * Writes EL_PATH + fills json_out. Returns 0 ok, 1 fail. */
int spark_bootstrap_engine_layout(char *json_out, size_t json_cap);

/* Selftest fixture (no DOM) — same spine as spark_layout_selftest. */
int spark_bootstrap_engine_layout_fixture(char *json_out,
                                          size_t json_cap);

/* Emit layout.table proof to stdout when boxes warrant it. */
int spark_bootstrap_engine_layout_emit_table(void);

#endif
