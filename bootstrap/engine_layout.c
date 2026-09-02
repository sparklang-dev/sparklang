/* Dry engine layout via linked asm/engine_layout.o (no invent).
 * Packs C DOM into GAS 64B nodes; emits layout.json = GAS JSON spine. */
#include "engine_layout.h"

#include "engine_css.h"
#include "engine_parse.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define GAS_NODE_SIZE 64
#define GAS_NODE_MAX 256
#define DATA_CAP 40
#define NODE_NONE (-1)

/* asm/engine_layout.s — System V AMD64 */
extern void spark_layout_reset(void);
extern void spark_layout_set_viewport(int w, int h);
extern void spark_layout_set_styles(const void *pool, int count);
extern int spark_layout_run(void *nodes, int n, int root);
extern int spark_layout_emit_table_proof(void);
extern int spark_layout_fixture_simple(void *nodes);

static unsigned char gas_nodes[GAS_NODE_MAX * GAS_NODE_SIZE];

static int ensure_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser/engine", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

static void pack_node(size_t id)
{
  unsigned char *n = gas_nodes + id * GAS_NODE_SIZE;
  const char *data;
  size_t i;
  int parent, first, last, next;

  memset(n, 0, GAS_NODE_SIZE);
  n[0] = spark_bootstrap_dom_kind(id);
  n[1] = spark_bootstrap_dom_tag_id(id);
  parent = spark_bootstrap_dom_parent(id);
  first = spark_bootstrap_dom_first(id);
  last = spark_bootstrap_dom_last(id);
  next = spark_bootstrap_dom_next(id);
  memcpy(n + 4, &parent, 4);
  memcpy(n + 8, &first, 4);
  memcpy(n + 12, &last, 4);
  memcpy(n + 16, &next, 4);
  data = spark_bootstrap_dom_data(id);
  for (i = 0; i < DATA_CAP - 1 && data[i]; i++)
    n[24 + i] = (unsigned char)data[i];
  n[24 + i] = 0;
}

static int pack_dom(size_t *out_n, int *out_root)
{
  size_t n;
  size_t i;
  n = spark_bootstrap_dom_nnodes();
  if (n == 0)
    return -1;
  if (n > GAS_NODE_MAX)
    n = GAS_NODE_MAX;
  for (i = 0; i < n; i++)
    pack_node(i);
  *out_n = n;
  *out_root = spark_bootstrap_dom_root();
  return 0;
}

static int write_layout_json(const char *json)
{
  FILE *f;
  size_t len;
  if (ensure_dirs() != 0)
    return -1;
  f = fopen(EL_PATH, "wb");
  if (!f)
    return -1;
  len = strlen(json);
  if (fwrite(json, 1, len, f) != len) {
    fclose(f);
    return -1;
  }
  fclose(f);
  return 0;
}

static int finish_json(char *json_out, size_t json_cap, const char *json)
{
  size_t len = strlen(json);
  if (write_layout_json(json) != 0) {
    fprintf(stderr, "error: engine layout cannot write layout.json\n");
    return 1;
  }
  if (!json_out || json_cap == 0)
    return 0;
  if (len + 1 > json_cap) {
    fprintf(stderr, "error: engine layout json overflow\n");
    return 1;
  }
  memcpy(json_out, json, len + 1);
  return 0;
}

int spark_bootstrap_engine_layout(char *json_out, size_t json_cap)
{
  size_t nnodes;
  int root;
  int boxes;
  char json[EL_JSON_CAP];
  size_t style_n;
  const void *styles;

  if (spark_bootstrap_dom_nnodes() == 0) {
    fprintf(stderr,
            "error: engine layout needs DOM"
            " (engine parse first; or: engine layout fixture)\n");
    return 1;
  }
  if (pack_dom(&nnodes, &root) != 0) {
    fprintf(stderr,
            "error: engine layout needs DOM"
            " (engine parse first; or: engine layout fixture)\n");
    return 1;
  }

  spark_layout_reset();
  spark_layout_set_viewport(640, 480);
  styles = spark_bootstrap_css_styles();
  style_n = spark_bootstrap_css_style_count();
  if (styles && style_n > 0)
    spark_layout_set_styles(styles, (int)style_n);
  else
    spark_layout_set_styles(NULL, 0);

  boxes = spark_layout_run(gas_nodes, (int)nnodes, root);
  if (boxes <= 0) {
    fprintf(stderr, "error: engine layout produced 0 boxes\n");
    return 1;
  }

  /* Match asm/engine_pipeline.s j_layout_pfx / j_layout_sfx */
  snprintf(json, sizeof(json),
           "{\"op\":\"engine.layout\",\"ok\":true,"
           "\"abi\":\"SePaintBox\",\"box_stride\":36,"
           "\"box_count\":%d}\n",
           boxes);
  return finish_json(json_out, json_cap, json);
}

int spark_bootstrap_engine_layout_emit_table(void)
{
  return spark_layout_emit_table_proof();
}

int spark_bootstrap_engine_layout_fixture(char *json_out,
                                          size_t json_cap)
{
  int n;
  int root;
  int boxes;
  char json[EL_JSON_CAP];

  /* fixture_simple returns eax=count, edx=root — only eax in C.
   * selftest hardcodes root 0; pack via fixture_simple then run. */
  memset(gas_nodes, 0, sizeof(gas_nodes));
  n = spark_layout_fixture_simple(gas_nodes);
  root = 0;
  spark_layout_reset();
  spark_layout_set_viewport(640, 480);
  spark_layout_set_styles(NULL, 0);
  boxes = spark_layout_run(gas_nodes, n, root);
  if (boxes != 8) {
    fprintf(stderr, "error: engine layout fixture expected 8 boxes\n");
    return 1;
  }
  /* Match spark_layout_selftest msg_ok…msg_ok2 spine */
  snprintf(json, sizeof(json),
           "{\"op\":\"layout\",\"box_count\":%d,\"expect\":8,"
           "\"box_stride\":36,\"abi\":\"SePaintBox\","
           "\"viewport\":[640,480],\"ok\":true}\n",
           boxes);
  return finish_json(json_out, json_cap, json);
}
