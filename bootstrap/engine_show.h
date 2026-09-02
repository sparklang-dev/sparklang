/* C bootstrap engine show — dry validate PPM/RGB + show.json.
 * Matches asm/engine_window.s dry path (no X11 / no invent). */
#ifndef SPARK_BOOTSTRAP_ENGINE_SHOW_H
#define SPARK_BOOTSTRAP_ENGINE_SHOW_H

#include <stddef.h>

#define ES_SHOW_JSON_CAP 512
#define ES_SHOW_JSON_PATH "out/browser/show.json"
#define ES_DEFAULT_PPM \
  "examples/fixtures/browser/engine_show.ppm"

/* Validate image at path (or ES_DEFAULT_PPM if path NULL/empty).
 * Writes ES_SHOW_JSON_PATH with GAS dry show JSON spine.
 * Fills json_out. Returns 0 ok, 1 fail (stderr matches GAS). */
int spark_bootstrap_engine_show(const char *path, char *json_out,
                                size_t json_cap);

#endif
