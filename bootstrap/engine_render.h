/* C bootstrap engine render — layout→paint_boxes→show spine.
 * Matches asm/engine_pipeline.s engine_pipeline_render (dry). */
#ifndef SPARK_BOOTSTRAP_ENGINE_RENDER_H
#define SPARK_BOOTSTRAP_ENGINE_RENDER_H

#include <stddef.h>

#define ER_RENDER_JSON_CAP 256
#define ER_RENDER_JSON_PATH "out/browser/engine/render.json"
#define ER_PPM_PATH "out/engine/pipeline.ppm"

/* Needs prior engine parse (DOM). Fail closed — no fixture fallback.
 * Writes render.json + pipeline.ppm + show.json.
 * Fills json_out with GAS j_render spine. Returns 0 ok, 1 fail. */
int spark_bootstrap_engine_render(char *json_out, size_t json_cap);

#endif
