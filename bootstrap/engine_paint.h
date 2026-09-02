/* C bootstrap engine paint — call asm/engine_paint.o dry spine.
 * Boxes path: layout SePaintBox[] → out/engine/pipeline.ppm (GAS). */
#ifndef SPARK_BOOTSTRAP_ENGINE_PAINT_H
#define SPARK_BOOTSTRAP_ENGINE_PAINT_H

#include <stddef.h>

#define EP_PAINT_JSON_CAP 256
#define EP_PPM_PATH "out/engine/pipeline.ppm"
#define EP_FIXTURE_PPM "out/engine/paint_fixture.ppm"

/* Paint current layout boxes → EP_PPM_PATH. Needs prior layout.
 * Fills json_out with GAS j_paint_boxes spine. Returns 0 ok, 1 fail. */
int spark_bootstrap_engine_paint_boxes(char *json_out, size_t json_cap);

/* SePaintBox demo → EP_FIXTURE_PPM (asm engine_paint_fixture). */
int spark_bootstrap_engine_paint_fixture(char *json_out, size_t json_cap);

#endif
