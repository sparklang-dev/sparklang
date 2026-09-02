/* C bootstrap engine css — match asm/engine_css.s dry css.json.
 * No inventing: same props, cascade, style= + <style> sheets. */
#ifndef SPARK_BOOTSTRAP_ENGINE_CSS_H
#define SPARK_BOOTSTRAP_ENGINE_CSS_H

#include <stddef.h>

#define EC_JSON_CAP 16384
#define EC_PATH "out/browser/engine/css.json"
#define EC_STYLE_SIZE 68

/* Attach styles to live DOM from spark_bootstrap_engine_parse.
 * Writes EC_PATH. Returns 0 ok, 1 fail (stderr already written). */
int spark_bootstrap_engine_css_attach(void);

/* Style pool after attach (SeComputedStyle ABI, 68B). May be empty. */
const void *spark_bootstrap_css_styles(void);
size_t spark_bootstrap_css_style_count(void);

void spark_bootstrap_engine_css_reset(void);

#endif
