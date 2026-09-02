/* Dry engine paint via linked asm/engine_paint.o (no invent).
 * Boxes: same sequence as asm/engine_pipeline.s ep_paint_layout_boxes. */
#include "engine_paint.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

/* asm/engine_paint.s — System V AMD64 */
extern int engine_paint_init(int w, int h);
extern void engine_paint_clear(unsigned char r, unsigned char g,
                               unsigned char b);
extern void engine_paint_boxes(void *boxes, int n, void *text_blob);
extern int engine_paint_write_ppm(const char *path);
extern int engine_paint_fixture(void);

/* asm/engine_layout.s — boxes left by prior spark_layout_run */
extern int spark_layout_box_count(void);
extern void *spark_layout_boxes_base(void);
extern void *spark_layout_text_blob(void);

static int ensure_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
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
    fprintf(stderr, "error: engine paint json overflow\n");
    return 1;
  }
  memcpy(json_out, json, len + 1);
  return 0;
}

int spark_bootstrap_engine_paint_boxes(char *json_out, size_t json_cap)
{
  int n;
  char json[EP_PAINT_JSON_CAP];

  n = spark_layout_box_count();
  if (n <= 0) {
    fprintf(stderr,
            "error: engine paint boxes needs layout"
            " (engine layout first; 0 boxes)\n");
    return 1;
  }
  if (ensure_dirs() != 0) {
    fprintf(stderr, "error: engine paint cannot mkdir out/engine\n");
    return 1;
  }
  if (engine_paint_init(640, 480) != 0) {
    fprintf(stderr, "error: engine render: layout/paint failed\n");
    return 1;
  }
  engine_paint_clear(255, 255, 255);
  engine_paint_boxes(spark_layout_boxes_base(), n,
                     spark_layout_text_blob());
  if (engine_paint_write_ppm(EP_PPM_PATH) != 0) {
    fprintf(stderr, "error: engine render: layout/paint failed\n");
    return 1;
  }
  /* Match asm/engine_pipeline.s j_paint_boxes + box_count + sfx */
  snprintf(json, sizeof(json),
           "{\"op\":\"engine.paint\",\"ok\":true,"
           "\"mode\":\"boxes\",\"abi\":\"SePaintBox\","
           "\"ppm\":\"%s\",\"box_count\":%d}\n",
           EP_PPM_PATH, n);
  return finish_json(json_out, json_cap, json);
}

int spark_bootstrap_engine_paint_fixture(char *json_out, size_t json_cap)
{
  char json[EP_PAINT_JSON_CAP];

  if (ensure_dirs() != 0) {
    fprintf(stderr, "error: engine paint cannot mkdir out/engine\n");
    return 1;
  }
  /* asm writes PPM + prints its msg_ok JSON to stdout */
  if (engine_paint_fixture() != 0) {
    fprintf(stderr, "error: engine paint fixture failed\n");
    return 1;
  }
  snprintf(json, sizeof(json),
           "{\"op\":\"engine.paint\","
           "\"ppm\":\"%s\","
           "\"w\":160,\"h\":80,\"glyphs\":true,\"rects\":true}\n",
           EP_FIXTURE_PPM);
  return finish_json(json_out, json_cap, json);
}
