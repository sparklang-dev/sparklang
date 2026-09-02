/* Dry engine render via layout + paint + show (no invent / no X11).
 * Spine: asm/engine_pipeline.s engine_pipeline_render. */
#include "engine_render.h"

#include "engine_layout.h"
#include "engine_paint.h"
#include "engine_parse.h"
#include "engine_show.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static const char J_RENDER[] =
    "{\"op\":\"engine.render\",\"ok\":true,"
    "\"stages\":[\"layout\",\"paint_boxes\",\"show\"],"
    "\"ppm\":\"out/engine/pipeline.ppm\","
    "\"abi\":\"SePaintBox\"}";

static int ensure_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser/engine", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/engine", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

static int finish_json(char *json_out, size_t json_cap, const char *json)
{
  size_t len = strlen(json);
  if (!json_out || json_cap == 0)
    return 0;
  if (len + 1 > json_cap) {
    fprintf(stderr, "error: engine render json overflow\n");
    return 1;
  }
  memcpy(json_out, json, len + 1);
  return 0;
}

int spark_bootstrap_engine_render(char *json_out, size_t json_cap)
{
  char lay_json[EL_JSON_CAP];
  char paint_json[EP_PAINT_JSON_CAP];
  char show_json[ES_SHOW_JSON_CAP];
  FILE *out;

  if (spark_bootstrap_dom_nnodes() == 0) {
    fprintf(stderr,
            "error: engine render needs DOM"
            " (engine parse first; no fixture fallback)\n");
    return 1;
  }
  if (ensure_dirs() != 0) {
    fprintf(stderr, "error: engine render cannot mkdir out dirs\n");
    return 1;
  }
  /* layout → paint_boxes (silent stages; GAS prints show then render) */
  if (spark_bootstrap_engine_layout(lay_json, sizeof(lay_json)) != 0)
    return 1;
  if (spark_bootstrap_engine_paint_boxes(paint_json,
                                         sizeof(paint_json)) != 0)
    return 1;
  /* Write render.json before show (match engine_pipeline_render) */
  out = fopen(ER_RENDER_JSON_PATH, "wb");
  if (!out) {
    fprintf(stderr, "error: engine render cannot write render.json\n");
    return 1;
  }
  if (fwrite(J_RENDER, 1, strlen(J_RENDER), out) != strlen(J_RENDER)) {
    fclose(out);
    fprintf(stderr, "error: engine render cannot write render.json\n");
    return 1;
  }
  fclose(out);
  if (spark_bootstrap_engine_show(ER_PPM_PATH, show_json,
                                  sizeof(show_json)) != 0)
    return 1;
  /* GAS prints show JSON (→) then render JSON (  -> ) from caller */
  printf("  → %s\n", show_json);
  return finish_json(json_out, json_cap, J_RENDER);
}
