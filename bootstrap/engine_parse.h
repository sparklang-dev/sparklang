/* C bootstrap engine parse — match asm/engine_html.s dry DOM.
 * No inventing: same tags, stack parse, dom.json spine. */
#ifndef SPARK_BOOTSTRAP_ENGINE_PARSE_H
#define SPARK_BOOTSTRAP_ENGINE_PARSE_H

#include <stddef.h>

#define EP_JSON_CAP 49152
#define EP_KIND_ELEM 1
#define EP_KIND_TEXT 2

/* Parse HTML at path (file:// stripped by caller).
 * Writes out/browser/engine/dom.json.
 * Fills json_out with the same JSON (NUL-terminated).
 * Runs phase-1 numbers/+ script texts (hello.html 1+1 →
 * out/engine/js_result.txt); other script syntax fails loud.
 * Returns 0 ok, 1 fail (stderr already written). */
int spark_bootstrap_engine_parse(const char *path, char *json_out,
                                 size_t json_cap);

/* Live DOM after a successful parse (engine css / layout). */
size_t spark_bootstrap_dom_nnodes(void);
int spark_bootstrap_dom_root(void);
const char *spark_bootstrap_dom_html(void);
unsigned char spark_bootstrap_dom_kind(size_t id);
unsigned char spark_bootstrap_dom_tag_id(size_t id);
/* Element tag name in node data[] (empty for text). */
const char *spark_bootstrap_dom_tag(size_t id);
/* Text / tag name payload (40B GAS data[]). */
const char *spark_bootstrap_dom_data(size_t id);
int spark_bootstrap_dom_parent(size_t id);
int spark_bootstrap_dom_first(size_t id);
int spark_bootstrap_dom_last(size_t id);
int spark_bootstrap_dom_next(size_t id);

/* Clear in-memory DOM/CSS/layout inputs between bc_vm runs. */
void spark_bootstrap_dom_reset(void);

#endif
