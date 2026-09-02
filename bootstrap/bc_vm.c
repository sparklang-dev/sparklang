/* SPARK_BC VM — dry-run stdout matches bootstrap/vm.c + GAS fixtures. */
#include "bc_vm.h"
#include "bc_opcodes.h"
#include "bc_read.h"
#include "dry_ask.h"
#include "dry_auto_model.h"
#include "dry_classify.h"
#include "dry_extract.h"
#include "dry_expect.h"
#include "dry_rag.h"
#include "dry_ops.h"
#include "dry_engine.h"
#include "dry_ide.h"
#include "vm.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BC_MAX_VARS SPARK_VM_MAX_VARS
#define BC_NAME_MAX SPARK_VM_NAME_MAX
#define BC_VAL_MAX SPARK_VM_VAL_MAX

typedef struct {
  char name[BC_NAME_MAX];
  char value[BC_VAL_MAX];
  int used;
} BcVar;

typedef struct {
  BcVar vars[BC_MAX_VARS];
  char last[BC_VAL_MAX];
  char model_alias[BC_NAME_MAX];
  char tool_reg_name[BC_NAME_MAX];
  size_t tool_reg_len;
  char tools_scope[SPARK_VM_TOOL_SCOPE];
  int tools_active;
  int browser_session_on;
  char browser_script[BC_VAL_MAX];
  char browser_url[BC_VAL_MAX];
  int mitm_on;
} BcFrame;

static int contains_ci(const char *hay, const char *needle)
{
  size_t nlen;
  size_t hlen;
  size_t i;
  size_t j;
  if (!hay || !needle || !needle[0])
    return 0;
  nlen = strlen(needle);
  hlen = strlen(hay);
  if (nlen > hlen)
    return 0;
  for (i = 0; i + nlen <= hlen; i++) {
    for (j = 0; j < nlen; j++) {
      char a = hay[i + j];
      char b = needle[j];
      if (a >= 'A' && a <= 'Z')
        a = (char)(a - 'A' + 'a');
      if (b >= 'A' && b <= 'Z')
        b = (char)(b - 'A' + 'a');
      if (a != b)
        break;
    }
    if (j == nlen)
      return 1;
  }
  return 0;
}

static void frame_init(BcFrame *fr)
{
  memset(fr, 0, sizeof(*fr));
  strncpy(fr->model_alias, "fast", BC_NAME_MAX - 1);
}

static void set_last(BcFrame *fr, const char *val)
{
  size_t n = strlen(val);
  if (n >= BC_VAL_MAX)
    n = BC_VAL_MAX - 1;
  memcpy(fr->last, val, n);
  fr->last[n] = '\0';
}

/* Match vm.c vars_put / vars_get (LANGUAGE let / -> bind). */
static int vars_put(BcFrame *fr, const char *name, const char *val)
{
  int i;
  size_t nlen;
  size_t vlen;
  if (!name || !name[0])
    return -1;
  nlen = strlen(name);
  vlen = strlen(val);
  if (nlen >= BC_NAME_MAX)
    nlen = BC_NAME_MAX - 1;
  if (vlen >= BC_VAL_MAX)
    vlen = BC_VAL_MAX - 1;
  for (i = 0; i < BC_MAX_VARS; i++) {
    if (fr->vars[i].used && strcmp(fr->vars[i].name, name) == 0) {
      memcpy(fr->vars[i].value, val, vlen);
      fr->vars[i].value[vlen] = '\0';
      return 0;
    }
  }
  for (i = 0; i < BC_MAX_VARS; i++) {
    if (!fr->vars[i].used) {
      memcpy(fr->vars[i].name, name, nlen);
      fr->vars[i].name[nlen] = '\0';
      memcpy(fr->vars[i].value, val, vlen);
      fr->vars[i].value[vlen] = '\0';
      fr->vars[i].used = 1;
      return 0;
    }
  }
  fprintf(stderr, "error: bytecode var table full\n");
  return -1;
}

static const char *vars_get(BcFrame *fr, const char *name)
{
  int i;
  for (i = 0; i < BC_MAX_VARS; i++) {
    if (fr->vars[i].used && strcmp(fr->vars[i].name, name) == 0)
      return fr->vars[i].value;
  }
  return NULL;
}

static char *interpolate_prompt(BcFrame *fr, const char *prompt)
{
  char *out;
  size_t cap;
  size_t o = 0;
  const char *p;
  if (!prompt)
    return NULL;
  cap = strlen(prompt) * 2 + 64;
  out = malloc(cap);
  if (!out)
    return NULL;
  for (p = prompt; *p; p++) {
    if (*p != '{') {
      if (o + 2 >= cap) {
        cap *= 2;
        out = realloc(out, cap);
        if (!out)
          return NULL;
      }
      out[o++] = *p;
      continue;
    }
    {
      const char *start = p + 1;
      const char *end = start;
      const char *val;
      size_t n;
      while (*end && *end != '}' &&
             (isalnum((unsigned char)*end) || *end == '_'))
        end++;
      if (*end != '}') {
        if (o + 2 >= cap) {
          free(out);
          return NULL;
        }
        out[o++] = *p;
        continue;
      }
      n = (size_t)(end - start);
      if (n == 0 || n >= BC_NAME_MAX) {
        if (o + 2 >= cap) {
          free(out);
          return NULL;
        }
        out[o++] = *p;
        continue;
      }
      {
        char name[BC_NAME_MAX];
        memcpy(name, start, n);
        name[n] = '\0';
        val = vars_get(fr, name);
        if (!val) {
          fprintf(stderr,
                  "error: interpolate unknown var {%s}\n",
                  name);
          free(out);
          return NULL;
        }
        n = strlen(val);
        while (o + n + 1 >= cap) {
          cap *= 2;
          out = realloc(out, cap);
          if (!out)
            return NULL;
        }
        memcpy(out + o, val, n);
        o += n;
      }
      p = end;
    }
  }
  out[o] = '\0';
  return out;
}

static int take_u16(const SparkBc *bc, uint32_t *ip, uint16_t *out)
{
  uint32_t i = *ip;
  if (i + 2 > bc->ncode) {
    fprintf(stderr, "error: truncated SPARK_BC operand\n");
    return 1;
  }
  *out = (uint16_t)(bc->code[i] | ((uint16_t)bc->code[i + 1] << 8));
  *ip = i + 2;
  return 0;
}

static int const_str(const SparkBc *bc, uint16_t idx, const char **out)
{
  uint16_t si;
  if (idx >= bc->nconsts) {
    fprintf(stderr, "error: SPARK_BC const index out of range\n");
    return 1;
  }
  if (bc->consts[idx].kind != SPBC_CONST_STR) {
    fprintf(stderr, "error: unknown SPARK_BC const kind %u\n",
            (unsigned)bc->consts[idx].kind);
    return 1;
  }
  si = bc->consts[idx].payload;
  if (si >= bc->nstrs) {
    fprintf(stderr, "error: SPARK_BC string index out of range\n");
    return 1;
  }
  *out = (const char *)bc->strs[si].bytes;
  return 0;
}

static void bc_log_auto_pick(BcFrame *fr, const char *stmt,
                             const char *prompt)
{
  const char *picked;

  if (strcmp(fr->model_alias, "auto") != 0)
    return;
  picked = spark_resolve_auto_model(stmt, prompt);
  printf("[model] auto→%s\n", picked);
}

static int op_model(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t ci;
  const char *alias;
  if (take_u16(bc, ip, &ci) != 0)
    return 1;
  if (const_str(bc, ci, &alias) != 0)
    return 1;
  if (!alias[0]) {
    fprintf(stderr, "error: model/use requires alias "
                    "(e.g. model code or use fast)\n");
    return 1;
  }
  strncpy(fr->model_alias, alias, BC_NAME_MAX - 1);
  fr->model_alias[BC_NAME_MAX - 1] = '\0';
  printf("[model] %s\n", fr->model_alias);
  return 0;
}

static int op_ask(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *prompt;
  const char *bind;
  const char *reply;
  char *expanded;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &prompt) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  expanded = interpolate_prompt(fr, prompt);
  if (!expanded)
    return 1;
  bc_log_auto_pick(fr, prompt, expanded);
  printf("[ask] %s\n", expanded);
  if (fr->tools_active && fr->tool_reg_len > 0) {
    static char tbuf[BC_VAL_MAX];
    snprintf(tbuf, sizeof(tbuf), "[tool:%s] stub:local",
             fr->tool_reg_name);
    reply = tbuf;
  } else
    reply = spark_pick_ask_reply(expanded);
  printf("  → %s\n", reply);
  printf("[accounting] latency_ms=0 prompt_tokens=0 "
         "completion_tokens=0 total_tokens=0 "
         "note=dry-run\n");
  set_last(fr, reply);
  if (bind[0] && vars_put(fr, bind, reply) != 0) {
    free(expanded);
    return 1;
  }
  free(expanded);
  return 0;
}

static int op_tool(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t nidx;
  const char *name;
  size_t n;
  if (take_u16(bc, ip, &nidx) != 0)
    return 1;
  if (const_str(bc, nidx, &name) != 0)
    return 1;
  if (!name[0]) {
    fprintf(stderr, "error: tool requires a name\n");
    return 1;
  }
  n = strlen(name);
  if (n >= BC_NAME_MAX)
    n = BC_NAME_MAX - 1;
  memcpy(fr->tool_reg_name, name, n);
  fr->tool_reg_name[n] = '\0';
  fr->tool_reg_len = n;
  printf("[tool] registered %s\n", fr->tool_reg_name);
  return 0;
}

static int op_with(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t sidx;
  const char *scope;
  size_t n;
  if (take_u16(bc, ip, &sidx) != 0)
    return 1;
  if (const_str(bc, sidx, &scope) != 0)
    return 1;
  if (fr->tool_reg_len == 0 || !scope[0])
    goto fail;
  n = strlen(scope);
  if (n >= SPARK_VM_TOOL_SCOPE)
    n = SPARK_VM_TOOL_SCOPE - 1;
  memcpy(fr->tools_scope, scope, n);
  fr->tools_scope[n] = '\0';
  if (!contains_ci(fr->tools_scope, fr->tool_reg_name))
    goto fail;
  fr->tools_active = 1;
  printf("[with] {\"op\":\"with_tools\",\"tools\":\"%s\","
         "\"active\":true}\n",
         fr->tools_scope);
  return 0;
fail:
  fprintf(stderr,
          "error: with tools [name] requires a prior"
          " tool registration and a [list]\n");
  return 1;
}

static int op_with_end(BcFrame *fr)
{
  fr->tools_active = 0;
  return 0;
}

static int op_print(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t ci;
  const char *name;
  const char *val;
  if (take_u16(bc, ip, &ci) != 0)
    return 1;
  if (const_str(bc, ci, &name) != 0)
    return 1;
  printf("[print] ");
  if (!name[0]) {
    printf("\n");
    return 0;
  }
  val = vars_get(fr, name);
  if (val)
    printf("%s\n", val);
  else
    printf("%s\n", name);
  return 0;
}

static int op_let(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t nidx;
  uint16_t vidx;
  const char *name;
  const char *val;
  if (take_u16(bc, ip, &nidx) != 0 || take_u16(bc, ip, &vidx) != 0)
    return 1;
  if (const_str(bc, nidx, &name) != 0)
    return 1;
  if (const_str(bc, vidx, &val) != 0)
    return 1;
  if (!name[0]) {
    fprintf(stderr, "error: let requires: let name = \"value\"\n");
    return 1;
  }
  printf("[let] %s = %s\n", name, val);
  if (vars_put(fr, name, val) != 0)
    return 1;
  set_last(fr, val);
  return 0;
}

static int bc_vars_put(void *frame, const char *name, const char *val)
{
  return vars_put((BcFrame *)frame, name, val);
}

static int op_engine_fetch(BcFrame *fr, const SparkBc *bc, uint32_t *ip,
                           int want_parse)
{
  uint16_t uidx;
  uint16_t bidx;
  const char *url;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &uidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, uidx, &url) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_fetch(&ctx, url, want_parse, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_parse(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *path;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_parse(&ctx, path, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_css(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_css(&ctx, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_layout(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_layout(&ctx, 0, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_paint(BcFrame *fr, const SparkBc *bc, uint32_t *ip,
                           int fixture)
{
  uint16_t bidx;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_paint(&ctx, fixture, !fixture, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_show(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *path;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_show(&ctx, path, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_engine_render(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  SparkDryEngineCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_engine_render(&ctx, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_ide_open(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *path;
  const char *bind;
  SparkDryIdeCtx ctx;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_ide_open(&ctx, path, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_ide_run(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  SparkDryIdeCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_ide_run(&ctx, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_ide_ask(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  SparkDryIdeCtx ctx;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_ide_ask(&ctx, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}

static int op_ide_show(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *path;
  const char *bind;
  SparkDryIdeCtx ctx;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  ctx.frame = fr;
  ctx.vars_put = bc_vars_put;
  ctx.last[0] = '\0';
  if (spark_dry_ide_show(&ctx, path, bind) != 0)
    return 1;
  set_last(fr, ctx.last);
  return 0;
}


static int op_classify(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t tidx;
  uint16_t bidx;
  const char *text;
  const char *bind;
  const char *reply;
  if (take_u16(bc, ip, &tidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, tidx, &text) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  printf("[classify] %s\n", text);
  reply = spark_pick_classify(text);
  printf("  → %s\n", reply);
  set_last(fr, reply);
  if (bind[0] && vars_put(fr, bind, reply) != 0)
    return 1;
  return 0;
}

static int op_embed(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t tidx;
  uint16_t bidx;
  const char *text;
  const char *bind;
  const char *reply;
  if (take_u16(bc, ip, &tidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, tidx, &text) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  printf("[embed] %s\n", text);
  reply = spark_pick_embed(text);
  printf("  → %s\n", reply);
  set_last(fr, reply);
  if (bind[0] && vars_put(fr, bind, reply) != 0)
    return 1;
  return 0;
}

static int op_retrieve(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t tidx;
  uint16_t bidx;
  const char *text;
  const char *bind;
  const char *reply;
  if (take_u16(bc, ip, &tidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, tidx, &text) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  printf("[retrieve] %s\n", text);
  reply = spark_pick_retrieve(text);
  printf("  → %s\n", reply);
  set_last(fr, reply);
  if (bind[0] && vars_put(fr, bind, reply) != 0)
    return 1;
  return 0;
}

static int bind_if_any(BcFrame *fr, const char *bind)
{
  if (bind && bind[0])
    return vars_put(fr, bind, fr->last);
  return 0;
}

/* EXTRACT carries the schema declaration, the fixture path, and the bind
 * name. The fixture on disk is the only source of field values, and the
 * same validator runs here as in the GAS and bootstrap interpreters, so
 * all three engines accept and reject exactly the same inputs. */
static int op_extract(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  struct spark_extract_schema schema;
  uint16_t sidx, fidx, bidx;
  const char *schema_text;
  const char *fixture;
  const char *bind;
  char *body = NULL;

  if (take_u16(bc, ip, &sidx) != 0)
    return 1;
  if (take_u16(bc, ip, &fidx) != 0)
    return 1;
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, sidx, &schema_text) != 0)
    return 1;
  if (const_str(bc, fidx, &fixture) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  if (spark_extract_parse_schema(schema_text, &schema) != 0)
    return 1;
  if (spark_extract_load_fixture(fixture, &body, NULL) != 0)
    return 1;
  if (spark_extract_validate(&schema, body) != 0) {
    fprintf(stderr,
            "error: extract %s did not validate against %s\n",
            schema.name, fixture);
    free(body);
    return 1;
  }
  printf("[extract] %s\n", body);
  set_last(fr, body);
  if (bind[0] && vars_put(fr, bind, body) != 0) {
    free(body);
    return 1;
  }
  free(body);
  return 0;
}

/* EXPECT: mode, name, want — want may be "@fixture:path" for file want. */
static int op_expect(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t midx, nidx, widx;
  const char *mode;
  const char *name;
  const char *want_raw;
  const char *got;
  char *want_body = NULL;
  int rc;

  if (take_u16(bc, ip, &midx) != 0)
    return 1;
  if (take_u16(bc, ip, &nidx) != 0)
    return 1;
  if (take_u16(bc, ip, &widx) != 0)
    return 1;
  if (const_str(bc, midx, &mode) != 0)
    return 1;
  if (const_str(bc, nidx, &name) != 0)
    return 1;
  if (const_str(bc, widx, &want_raw) != 0)
    return 1;
  got = vars_get(fr, name);
  if (!got) {
    fprintf(stderr, "error: expect unknown name %s\n", name);
    return 1;
  }
  if (strncmp(want_raw, "@fixture:", 9) == 0) {
    if (spark_expect_load_fixture(want_raw + 9, &want_body, NULL) !=
	0)
      return 1;
    rc = spark_expect_check(mode, name, got, want_body);
    free(want_body);
    return rc;
  }
  return spark_expect_check(mode, name, got, want_raw);
}

static int op_pipeline(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  (void)fr;
  (void)bc;
  (void)ip;
  printf("[pipeline] step\n");
  return 0;
}

static int op_listen(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  const char *transcript = spark_dry_transcript();
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  printf("[listen] %s\n", transcript);
  set_last(fr, transcript);
  if (bind[0] && vars_put(fr, bind, transcript) != 0)
    return 1;
  return 0;
}

static int op_speak(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  const char *path;
  (void)fr;
  if (take_u16(bc, ip, &pidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (!path[0])
    path = "spark-out.wav";
  if (spark_write_stub_wav(path) != 0)
    return 1;
  printf("[speak] wrote %s\n", path);
  return 0;
}

static int op_voice(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  (void)fr;
  (void)bc;
  (void)ip;
  printf("[voice] session\n");
  return 0;
}

static int op_review_path(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t pidx;
  uint16_t bidx;
  const char *path;
  const char *bind;
  const char *report;
  FILE *f;
  if (take_u16(bc, ip, &pidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, pidx, &path) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  f = fopen(path, "r");
  if (!f) {
    fprintf(stderr, "error: review path cannot open file\n");
    return 1;
  }
  fclose(f);
  printf("[review] %s\n", path);
  report = spark_pick_review_report(path);
  printf("  (static only — never eval web JS)\n");
  printf("  → %s\n", report);
  set_last(fr, report);
  if (bind[0] && vars_put(fr, bind, report) != 0)
    return 1;
  return 0;
}

static int op_review_text(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t tidx;
  uint16_t bidx;
  const char *text;
  const char *bind;
  const char *report;
  if (take_u16(bc, ip, &tidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, tidx, &text) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  printf("[review] %s\n", text);
  report = spark_pick_review_report(text);
  printf("  (static only — never eval web JS)\n");
  printf("  → %s\n", report);
  set_last(fr, report);
  if (bind[0] && vars_put(fr, bind, report) != 0)
    return 1;
  return 0;
}

static int op_browser_run(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t sidx;
  uint16_t bidx;
  const char *script;
  const char *bind;
  char json[BC_VAL_MAX];
  if (take_u16(bc, ip, &sidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, sidx, &script) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  if (script[0]) {
    strncpy(fr->browser_script, script, sizeof(fr->browser_script) - 1);
    fr->browser_script[sizeof(fr->browser_script) - 1] = '\0';
  } else if (!fr->browser_script[0]) {
    strncpy(fr->browser_script, spark_br_default_script(),
            sizeof(fr->browser_script) - 1);
  }
  if (!fr->browser_url[0]) {
    strncpy(fr->browser_url, spark_br_default_url(),
            sizeof(fr->browser_url) - 1);
  }
  fr->browser_session_on = 1;
  if (spark_write_session_json(
          fr->browser_script[0] ? fr->browser_script : NULL,
          fr->browser_url[0] ? fr->browser_url : NULL, json,
          sizeof(json)) != 0) {
    fprintf(stderr, "error: browser run cannot write session.json\n");
    return 1;
  }
  printf("[browser]   → %s\n", json);
  set_last(fr, json);
  if (bind_if_any(fr, bind) != 0)
    return 1;
  return 0;
}

static int op_browser_goto(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t uidx;
  uint16_t bidx;
  const char *url;
  const char *bind;
  char json[BC_VAL_MAX];
  if (take_u16(bc, ip, &uidx) != 0 || take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, uidx, &url) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  if (!fr->browser_session_on) {
    fprintf(stderr,
            "[browser] error: browser session required "
            "(browser run|open first)\n");
    return 1;
  }
  if (url[0]) {
    strncpy(fr->browser_url, url, sizeof(fr->browser_url) - 1);
    fr->browser_url[sizeof(fr->browser_url) - 1] = '\0';
  } else if (!fr->browser_url[0]) {
    strncpy(fr->browser_url, spark_br_default_url(),
            sizeof(fr->browser_url) - 1);
  }
  if (spark_write_session_json(
          fr->browser_script[0] ? fr->browser_script : NULL,
          fr->browser_url, json, sizeof(json)) != 0) {
    fprintf(stderr, "error: browser goto cannot write session.json\n");
    return 1;
  }
  if (spark_format_browser_goto_json(fr->browser_url, json,
                                     sizeof(json)) != 0) {
    fprintf(stderr, "error: browser goto json overflow\n");
    return 1;
  }
  printf("[browser]   → %s\n", json);
  set_last(fr, fr->browser_url);
  if (bind_if_any(fr, bind) != 0)
    return 1;
  return 0;
}

static int op_mitm_enable(BcFrame *fr, const SparkBc *bc, uint32_t *ip)
{
  uint16_t bidx;
  const char *bind;
  const char *json = spark_mitm_enable_dry_json();
  if (take_u16(bc, ip, &bidx) != 0)
    return 1;
  if (const_str(bc, bidx, &bind) != 0)
    return 1;
  if (!fr->browser_session_on) {
    if (!fr->browser_script[0]) {
      strncpy(fr->browser_script, spark_br_default_script(),
              sizeof(fr->browser_script) - 1);
    }
    if (!fr->browser_url[0]) {
      strncpy(fr->browser_url, spark_br_default_url(),
              sizeof(fr->browser_url) - 1);
    }
    fr->browser_session_on = 1;
  }
  fr->mitm_on = 1;
  if (spark_write_mitm_json() != 0) {
    fprintf(stderr, "error: mitm enable cannot write mitm.json\n");
    return 1;
  }
  printf("[mitm]   → %s\n", json);
  set_last(fr, json);
  if (bind_if_any(fr, bind) != 0)
    return 1;
  return 0;
}

int spark_bc_run_file(const char *path)
{
  SparkBc bc;
  BcFrame fr;
  uint32_t ip = 0;
  int rc;

  if (spark_bc_load(path, &bc) != 0)
    return 1;
  spark_dry_engine_reset();
  frame_init(&fr);
  printf("[spark] dry-run via bytecode VM\n");
  rc = 0;
  while (ip < bc.ncode) {
    uint8_t op = bc.code[ip++];
    if (op == SPBC_OP_HALT)
      break;
    if (op == SPBC_OP_MODEL)
      rc = op_model(&fr, &bc, &ip);
    else if (op == SPBC_OP_ASK)
      rc = op_ask(&fr, &bc, &ip);
    else if (op == SPBC_OP_PRINT)
      rc = op_print(&fr, &bc, &ip);
    else if (op == SPBC_OP_LET)
      rc = op_let(&fr, &bc, &ip);
    else if (op == SPBC_OP_CLASSIFY)
      rc = op_classify(&fr, &bc, &ip);
    else if (op == SPBC_OP_EMBED)
      rc = op_embed(&fr, &bc, &ip);
    else if (op == SPBC_OP_RETRIEVE)
      rc = op_retrieve(&fr, &bc, &ip);
    else if (op == SPBC_OP_EXTRACT)
      rc = op_extract(&fr, &bc, &ip);
    else if (op == SPBC_OP_EXPECT)
      rc = op_expect(&fr, &bc, &ip);
    else if (op == SPBC_OP_PIPELINE)
      rc = op_pipeline(&fr, &bc, &ip);
    else if (op == SPBC_OP_LISTEN)
      rc = op_listen(&fr, &bc, &ip);
    else if (op == SPBC_OP_SPEAK)
      rc = op_speak(&fr, &bc, &ip);
    else if (op == SPBC_OP_VOICE)
      rc = op_voice(&fr, &bc, &ip);
    else if (op == SPBC_OP_REVIEW_PATH)
      rc = op_review_path(&fr, &bc, &ip);
    else if (op == SPBC_OP_REVIEW_TEXT)
      rc = op_review_text(&fr, &bc, &ip);
    else if (op == SPBC_OP_BROWSER_RUN)
      rc = op_browser_run(&fr, &bc, &ip);
    else if (op == SPBC_OP_BROWSER_GOTO)
      rc = op_browser_goto(&fr, &bc, &ip);
    else if (op == SPBC_OP_MITM_ENABLE)
      rc = op_mitm_enable(&fr, &bc, &ip);
    else if (op == SPBC_OP_ENGINE_FETCH)
      rc = op_engine_fetch(&fr, &bc, &ip, 0);
    else if (op == SPBC_OP_ENGINE_FETCH_PARSE)
      rc = op_engine_fetch(&fr, &bc, &ip, 1);
    else if (op == SPBC_OP_ENGINE_PARSE)
      rc = op_engine_parse(&fr, &bc, &ip);
    else if (op == SPBC_OP_ENGINE_CSS)
      rc = op_engine_css(&fr, &bc, &ip);
    else if (op == SPBC_OP_ENGINE_LAYOUT)
      rc = op_engine_layout(&fr, &bc, &ip);
    else if (op == SPBC_OP_ENGINE_PAINT_BOXES)
      rc = op_engine_paint(&fr, &bc, &ip, 0);
    else if (op == SPBC_OP_ENGINE_PAINT_FIXTURE)
      rc = op_engine_paint(&fr, &bc, &ip, 1);
    else if (op == SPBC_OP_ENGINE_SHOW)
      rc = op_engine_show(&fr, &bc, &ip);
    else if (op == SPBC_OP_ENGINE_RENDER)
      rc = op_engine_render(&fr, &bc, &ip);
    else if (op == SPBC_OP_IDE_OPEN)
      rc = op_ide_open(&fr, &bc, &ip);
    else if (op == SPBC_OP_IDE_RUN)
      rc = op_ide_run(&fr, &bc, &ip);
    else if (op == SPBC_OP_IDE_ASK)
      rc = op_ide_ask(&fr, &bc, &ip);
    else if (op == SPBC_OP_IDE_SHOW)
      rc = op_ide_show(&fr, &bc, &ip);
    else if (op == SPBC_OP_TOOL)
      rc = op_tool(&fr, &bc, &ip);
    else if (op == SPBC_OP_WITH)
      rc = op_with(&fr, &bc, &ip);
    else if (op == SPBC_OP_WITH_END)
      rc = op_with_end(&fr);
    else {
      fprintf(stderr, "error: unknown SPARK_BC opcode 0x%02x\n",
              (unsigned)op);
      rc = 1;
    }
    if (rc != 0)
      break;
  }
  if (rc == 0)
    printf("[spark] ok\n");
  spark_bc_free(&bc);
  return rc;
}
