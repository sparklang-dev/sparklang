/* arm64 (and other non-x86_64) stubs for engine_layout / engine_paint asm.
 * AI dry-run (ask/classify/extract) does not need layout/paint; engine ops
 * fail loud at runtime until an arm64 asm port lands.
 */
#include <stddef.h>

void spark_layout_reset(void) {}
void spark_layout_set_viewport(int w, int h) { (void)w; (void)h; }
void spark_layout_set_styles(const void *pool, int count)
{
  (void)pool;
  (void)count;
}
int spark_layout_run(void *nodes, int n, int root)
{
  (void)nodes;
  (void)n;
  (void)root;
  return 0;
}
int spark_layout_emit_table_proof(void) { return -1; }
int spark_layout_fixture_simple(void *nodes)
{
  (void)nodes;
  return 0;
}
int spark_layout_box_count(void) { return 0; }
void *spark_layout_boxes_base(void) { return NULL; }
void *spark_layout_text_blob(void) { return NULL; }

int engine_paint_init(int w, int h)
{
  (void)w;
  (void)h;
  return -1;
}
void engine_paint_clear(unsigned char r, unsigned char g, unsigned char b)
{
  (void)r;
  (void)g;
  (void)b;
}
void engine_paint_boxes(void *boxes, int n, void *text_blob)
{
  (void)boxes;
  (void)n;
  (void)text_blob;
}
int engine_paint_write_ppm(const char *path)
{
  (void)path;
  return -1;
}
int engine_paint_fixture(void) { return -1; }

void ide_paint_bind(const char *ptr, unsigned long len)
{
  (void)ptr;
  (void)len;
}
void ide_status_set(const char *ptr, unsigned long len)
{
  (void)ptr;
  (void)len;
}
void ide_ai_set(const char *ptr, unsigned long len)
{
  (void)ptr;
  (void)len;
}
int ide_paint_editor(void) { return -1; }
int ide_paint_write_ppm(const char *path)
{
  (void)path;
  return -1;
}
