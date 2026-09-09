/* Spark C bootstrap VM — dry subset matching GAS asm/spark.s.
 * Ops: model/ask/print/let + classify/extract/tool/with/listen/speak/
 * pipeline/review/voice + browser run|goto + mitm enable +
 * engine fetch (file://) + engine parse + css + layout + paint +
 * show + render.
 * Unknown ops fail loud. Does not wrap ./spark. */
#include "vm.h"
#include "dry_ask.h"
#include "dry_classify.h"
#include "dry_extract.h"
#include "dry_expect.h"
#include "dry_http.h"
#include "dry_rag.h"
#include "dry_ops.h"
#include "engine_css.h"
#include "engine_layout.h"
#include "engine_paint.h"
#include "engine_parse.h"
#include "engine_render.h"
#include "engine_show.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Exact dry JSON from asm/browser_ops.s j_flags. */
static const char BR_FLAGS_DRY[] =
    "{\"op\":\"flags\",\"disable_quic\":false,"
    "\"default\":false,\"override\":"
    "\"mitm disable_quic on |"
    " browser gui --disable-quic\","
    "\"entrypoint\":\"spark language\"}";
/* JSON fragments from asm/engine_fetch.s (file:// dry). */
static const char EF_JSON_FILE_PRE[] =
    "{\"op\":\"engine.fetch\",\"ok\":true,"
    "\"source\":\"file\",\"scheme\":\"file\","
    "\"fetched\":false,\"transport\":\"open\","
    "\"path\":\"out/engine/body.bin\","
    "\"bytes\":";
static const char EF_JSON_MID_URL[] = ",\"url\":\"";
static const char EF_JSON_END[] = "\"}";
static const char EF_BODY_PATH[] = "out/engine/body.bin";
/* Exact spine from asm/engine_pipeline.s j_fp */
static const char EF_JSON_FETCH_PARSE[] =
    "{\"op\":\"engine.fetch_parse\",\"ok\":true,"
    "\"body\":\"out/engine/body.bin\","
    "\"next\":\"engine.parse\"}";

static char *ltrim(char *s)
{
  while (*s == ' ' || *s == '\t')
    s++;
  return s;
}

static void rtrim(char *s)
{
  size_t n = strlen(s);
  while (n > 0 &&
         (s[n - 1] == ' ' || s[n - 1] == '\t' || s[n - 1] == '\r' ||
          s[n - 1] == '\n')) {
    s[--n] = '\0';
  }
}

static int kw_at(const char *line, const char *kw)
{
  size_t klen = strlen(kw);
  if (strncmp(line, kw, klen) != 0)
    return 0;
  if (line[klen] == '\0' || line[klen] == ' ' || line[klen] == '\t' ||
      line[klen] == '"' || line[klen] == '{' || line[klen] == '(')
    return 1;
  return 0;
}

/* GAS contains: case-insensitive ASCII substring. */
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
        a = (char)(a + 32);
      if (b >= 'A' && b <= 'Z')
        b = (char)(b + 32);
      if (a != b)
        break;
    }
    if (j == nlen)
      return 1;
  }
  return 0;
}

/* Extract first "..." with \" \\n \\t; returns malloc'd or NULL. */
static char *extract_quote(const char *line)
{
  const char *p = strchr(line, '"');
  char *out;
  size_t cap;
  size_t n = 0;
  if (!p)
    return NULL;
  p++;
  cap = strlen(p) + 1;
  out = malloc(cap);
  if (!out)
    return NULL;
  while (*p && *p != '"') {
    char c = *p++;
    if (c == '\\' && *p) {
      char e = *p++;
      if (e == 'n')
        c = '\n';
      else if (e == 't')
        c = '\t';
      else if (e == '"' || e == '\\')
        c = e;
      else
        c = e;
    }
    if (n + 1 >= cap) {
      cap *= 2;
      {
        char *nbuf = realloc(out, cap);
        if (!nbuf) {
          free(out);
          return NULL;
        }
        out = nbuf;
      }
    }
    out[n++] = c;
  }
  out[n] = '\0';
  return out;
}

static const char *arrow_name(const char *line)
{
  const char *a = strstr(line, "->");
  static char name[SPARK_VM_NAME_MAX];
  size_t i = 0;
  if (!a)
    return NULL;
  a += 2;
  while (*a == ' ' || *a == '\t')
    a++;
  while (*a && *a != ' ' && *a != '\t' && *a != '#' &&
         i + 1 < sizeof(name)) {
    name[i++] = *a++;
  }
  name[i] = '\0';
  return i ? name : NULL;
}

static void set_last(SparkVM *vm, const char *val)
{
  size_t n = strlen(val);
  if (n >= SPARK_VM_VAL_MAX)
    n = SPARK_VM_VAL_MAX - 1;
  memcpy(vm->last_val, val, n);
  vm->last_val[n] = '\0';
  vm->last_val_len = n;
}

static int vars_put(SparkVM *vm, const char *name, const char *val)
{
  int i;
  size_t nlen;
  size_t vlen;
  if (!name || !name[0])
    return -1;
  nlen = strlen(name);
  vlen = strlen(val);
  if (nlen >= SPARK_VM_NAME_MAX)
    nlen = SPARK_VM_NAME_MAX - 1;
  if (vlen >= SPARK_VM_VAL_MAX)
    vlen = SPARK_VM_VAL_MAX - 1;
  for (i = 0; i < SPARK_VM_MAX_VARS; i++) {
    if (vm->vars[i].used && strcmp(vm->vars[i].name, name) == 0) {
      memcpy(vm->vars[i].value, val, vlen);
      vm->vars[i].value[vlen] = '\0';
      return 0;
    }
  }
  for (i = 0; i < SPARK_VM_MAX_VARS; i++) {
    if (!vm->vars[i].used) {
      memcpy(vm->vars[i].name, name, nlen);
      vm->vars[i].name[nlen] = '\0';
      memcpy(vm->vars[i].value, val, vlen);
      vm->vars[i].value[vlen] = '\0';
      vm->vars[i].used = 1;
      return 0;
    }
  }
  fprintf(stderr, "error: bootstrap var table full\n");
  return -1;
}

static const char *vars_get(SparkVM *vm, const char *name)
{
  int i;
  for (i = 0; i < SPARK_VM_MAX_VARS; i++) {
    if (vm->vars[i].used && strcmp(vm->vars[i].name, name) == 0)
      return vm->vars[i].value;
  }
  return NULL;
}

/* spark.toml: model = "alias" (bootstrap only; first match wins). */
static void load_spark_toml_model(SparkVM *vm)
{
  FILE *f;
  char line[512];
  f = fopen("spark.toml", "r");
  if (!f)
    return;
  while (fgets(line, sizeof(line), f)) {
    char *p = ltrim(line);
    char *q;
    size_t n;
    if (strncmp(p, "model", 5) != 0)
      continue;
    p = ltrim(p + 5);
    if (*p != '=')
      continue;
    p = ltrim(p + 1);
    if (*p != '"')
      continue;
    q = strchr(p + 1, '"');
    if (!q)
      continue;
    n = (size_t)(q - (p + 1));
    if (n == 0 || n >= SPARK_VM_NAME_MAX)
      continue;
    memcpy(vm->model_alias, p + 1, n);
    vm->model_alias[n] = '\0';
    memcpy(vm->prior_model, p + 1, n);
    vm->prior_model[n] = '\0';
    break;
  }
  fclose(f);
}

/* Replace {name} in prompt with bound let/var values. */
static char *interpolate_prompt(SparkVM *vm, const char *prompt)
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
        {
          char *nb = realloc(out, cap);
          if (!nb) {
            free(out);
            return NULL;
          }
          out = nb;
        }
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
             ((*end >= 'a' && *end <= 'z') ||
              (*end >= 'A' && *end <= 'Z') ||
              (*end >= '0' && *end <= '9') || *end == '_'))
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
      if (n == 0 || n >= SPARK_VM_NAME_MAX) {
        if (o + 2 >= cap) {
          free(out);
          return NULL;
        }
        out[o++] = *p;
        continue;
      }
      {
        char name[SPARK_VM_NAME_MAX];
        memcpy(name, start, n);
        name[n] = '\0';
        val = vars_get(vm, name);
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
          {
            char *nb = realloc(out, cap);
            if (!nb) {
              free(out);
              return NULL;
            }
            out = nb;
          }
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

static int bind_arrow(SparkVM *vm, const char *line)
{
  const char *bind = arrow_name(line);
  if (!bind)
    return 0;
  return vars_put(vm, bind, vm->last_val);
}

static int migrated_bc(const char *op)
{
  fprintf(stderr,
          "error: %s migrated to SPARK_BC (use --compile path)\n",
          op);
  return 1;
}

static int looks_like_field(const char *line)
{
  const char *p = line;
  if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')))
    return 0;
  p++;
  while ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
         (*p >= '0' && *p <= '9') || *p == '_')
    p++;
  return *p == ':';
}

static int op_model(SparkVM *vm, char *line)
{
  char *p;
  char *end;
  if (kw_at(line, "use"))
    p = ltrim(line + 3);
  else
    p = ltrim(line + 5);
  if (strncmp(p, "analyze", 7) == 0 || strncmp(p, "compare", 7) == 0 ||
      strncmp(p, "improve", 7) == 0 || strncmp(p, "build", 5) == 0 ||
      strncmp(p, "train", 5) == 0 || strncmp(p, "status", 6) == 0 ||
      strncmp(p, "plan", 4) == 0 || strncmp(p, "reverse", 7) == 0 ||
      strncmp(p, "inspect", 7) == 0 || strncmp(p, "compile", 7) == 0 ||
      strncmp(p, "modify", 6) == 0) {
    fprintf(stderr,
            "error: model analyze|compare|improve|train|status|plan|build|"
            "reverse|inspect|compile|modify "
            "is GAS-only (not in C bootstrap yet)\n");
    return 1;
  }
  end = p;
  while (*end && *end != ' ' && *end != '\t' && *end != '#')
    end++;
  *end = '\0';
  if (!p[0]) {
    fprintf(stderr,
            "error: model/use requires an explicit model id "
            "(HF id, path, or configured name)\n");
    return 1;
  }
  if (strcmp(p, "auto") == 0) {
    const char *prior = vm->prior_model[0] ? vm->prior_model
                                           : vm->model_alias;
    if (!prior[0])
      prior = "(none)";
    printf("[model] prior %s (no alias pick)\n", prior);
    return 0;
  }
  strncpy(vm->prior_model, p, SPARK_VM_NAME_MAX - 1);
  vm->prior_model[SPARK_VM_NAME_MAX - 1] = '\0';
  strncpy(vm->model_alias, p, SPARK_VM_NAME_MAX - 1);
  vm->model_alias[SPARK_VM_NAME_MAX - 1] = '\0';
  printf("[model] %s\n", vm->model_alias);
  return 0;
}

static int op_ask(SparkVM *vm, char *line)
{
  char *prompt;
  char *expanded;
  const char *reply;
  char tool_buf[SPARK_VM_VAL_MAX];
  prompt = extract_quote(line);
  if (!prompt) {
    if (strstr(line, "probe")) {
      fprintf(stderr,
              "error: ask probe is GAS-only (companion; not in C "
              "bootstrap yet)\n");
      return 1;
    }
    fprintf(stderr,
            "error: ask/? requires a quoted prompt "
            "(e.g. ask \"…\" or ? \"…\")\n");
    return 1;
  }
  expanded = interpolate_prompt(vm, prompt);
  if (!expanded) {
    free(prompt);
    return 1;
  }
  printf("[ask] %s\n", expanded);
  if (vm->tools_active && vm->tool_reg_len > 0) {
    snprintf(tool_buf, sizeof(tool_buf), "[tool:%s] stub:local",
             vm->tool_reg_name);
    reply = tool_buf;
  } else {
    reply = spark_pick_ask_reply(expanded);
  }
  printf("  → %s\n", reply);
  printf("[accounting] latency_ms=0 prompt_tokens=0 "
         "completion_tokens=0 total_tokens=0 "
         "note=dry-run\n");
  set_last(vm, reply);
  if (bind_arrow(vm, line) != 0) {
    free(prompt);
    free(expanded);
    return 1;
  }
  free(prompt);
  free(expanded);
  return 0;
}

static int op_print(SparkVM *vm, char *line)
{
  char *q;
  char *p;
  char name[SPARK_VM_NAME_MAX];
  size_t i = 0;
  const char *val;
  printf("[print] ");
  q = extract_quote(line);
  if (q) {
    printf("%s\n", q);
    free(q);
    return 0;
  }
  p = ltrim(line + 5);
  while (*p && *p != ' ' && *p != '\t' && *p != '#' &&
         i + 1 < sizeof(name)) {
    name[i++] = *p++;
  }
  name[i] = '\0';
  if (!name[0]) {
    printf("\n");
    return 0;
  }
  val = vars_get(vm, name);
  if (val)
    printf("%s\n", val);
  else
    printf("%s\n", name);
  return 0;
}

static int op_let(SparkVM *vm, char *line)
{
  char *p = ltrim(line + 3);
  char name[SPARK_VM_NAME_MAX];
  size_t i = 0;
  char *q;
  while (*p && *p != ' ' && *p != '\t' && *p != '=' &&
         i + 1 < sizeof(name)) {
    name[i++] = *p++;
  }
  name[i] = '\0';
  if (!name[0]) {
    fprintf(stderr, "error: let requires: let name = \"value\"\n");
    return 1;
  }
  p = ltrim(p);
  if (*p == '=')
    p = ltrim(p + 1);
  q = extract_quote(line);
  if (!q) {
    fprintf(stderr,
            "error: let requires: let name \"value\" "
            "or let name = \"value\"\n");
    return 1;
  }
  printf("[let] %s = %s\n", name, q);
  if (vars_put(vm, name, q) != 0) {
    free(q);
    return 1;
  }
  set_last(vm, q);
  free(q);
  (void)p;
  return 0;
}

static int op_classify(SparkVM *vm, char *line)
{
  char *q;
  const char *reply;

  printf("[classify] ");
  q = extract_quote(line);
  if (!q) {
    /* GAS cls_noq: no set_last / no bind */
    printf("\n  → %s\n", spark_pick_classify(""));
    return 0;
  }
  printf("%s\n", q);
  reply = spark_pick_classify(q);
  printf("  → %s\n", reply);
  set_last(vm, reply);
  if (bind_arrow(vm, line) != 0) {
    free(q);
    return 1;
  }
  free(q);
  return 0;
}

static int op_embed(SparkVM *vm, char *line)
{
  char *q;
  const char *reply;

  printf("[embed] ");
  q = extract_quote(line);
  if (!q) {
    printf("\n  → %s\n", spark_pick_embed(""));
    return 0;
  }
  printf("%s\n", q);
  reply = spark_pick_embed(q);
  printf("  → %s\n", reply);
  set_last(vm, reply);
  if (bind_arrow(vm, line) != 0) {
    free(q);
    return 1;
  }
  free(q);
  return 0;
}

static int op_retrieve(SparkVM *vm, char *line)
{
  char *q;
  const char *reply;

  printf("[retrieve] ");
  q = extract_quote(line);
  if (!q) {
    printf("\n  → %s\n", spark_pick_retrieve(""));
    return 0;
  }
  printf("%s\n", q);
  reply = spark_pick_retrieve(q);
  printf("  → %s\n", reply);
  set_last(vm, reply);
  if (bind_arrow(vm, line) != 0) {
    free(q);
    return 1;
  }
  free(q);
  return 0;
}


static int shell_allowlisted(const char *cmd)
{
  if (!cmd || !cmd[0])
    return 0;
  if (strncmp(cmd, "echo", 4) == 0 &&
      (cmd[4] == '\0' || cmd[4] == ' '))
    return 1;
  if (strcmp(cmd, "true") == 0 || strcmp(cmd, "false") == 0)
    return 1;
  return 0;
}

static int op_shell(SparkVM *vm, char *line)
{
  char *q;
  char fixture[SPARK_VM_VAL_MAX];
  const char *kw = kw_at(line, "run") ? "run" : "shell";

  printf("[%s] ", kw);
  q = extract_quote(line);
  if (!q) {
    fprintf(stderr,
            "error: %s requires a quoted argv "
            "(e.g. shell \"echo hello\")\n",
            kw);
    return 1;
  }
  printf("%s\n", q);
  if (!shell_allowlisted(q)) {
    fprintf(stderr,
            "error: refuses shell/run %s "
            "(allowlist: echo|true|false; live needs "
            "./spark --live --allow-shell)\n",
            q);
    free(q);
    return 1;
  }
  if (strcmp(q, "true") == 0)
    snprintf(fixture, sizeof(fixture),
             "{\"ok\":true,\"mode\":\"dry-run\",\"argv\":\"true\","
             "\"stdout\":\"\",\"note\":\"fixture — no exec\"}");
  else if (strcmp(q, "false") == 0)
    snprintf(fixture, sizeof(fixture),
             "{\"ok\":false,\"mode\":\"dry-run\",\"argv\":\"false\","
             "\"stdout\":\"\",\"note\":\"fixture — no exec\"}");
  else {
    const char *rest = q + 4;
    while (*rest == ' ')
      rest++;
    snprintf(fixture, sizeof(fixture),
             "{\"ok\":true,\"mode\":\"dry-run\",\"argv\":\"echo\","
             "\"stdout\":\"%s\",\"note\":\"fixture — no exec\"}",
             rest[0] ? rest : "");
  }
  printf("  → %s\n", fixture);
  set_last(vm, fixture);
  if (bind_arrow(vm, line) != 0) {
    free(q);
    return 1;
  }
  free(q);
  return 0;
}

/* Quote after a keyword (fixture / body). */
static char *extract_quote_after(const char *line, const char *kw)
{
  const char *p = strstr(line, kw);
  if (!p)
    return NULL;
  return extract_quote(p);
}

static int op_http(SparkVM *vm, char *line)
{
  int is_post = 0;
  char *url;
  char *fx = NULL;
  char path[1024];
  char *body = NULL;
  size_t blen = 0;
  const char *rest;

  rest = line + 4;
  while (*rest == ' ' || *rest == '\t')
    rest++;
  if (strncmp(rest, "get", 3) == 0 &&
      (rest[3] == ' ' || rest[3] == '\t' || rest[3] == '"')) {
    is_post = 0;
    printf("[http get] ");
  } else if (strncmp(rest, "post", 4) == 0 &&
             (rest[4] == ' ' || rest[4] == '\t' || rest[4] == '"')) {
    is_post = 1;
    printf("[http post] ");
  } else {
    fprintf(stderr,
            "error: http requires get or post "
            "(e.g. http get \"URL\" fixture \"path\")\n");
    return 1;
  }
  url = extract_quote(line);
  if (!url) {
    fprintf(stderr, "error: http needs a quoted URL\n");
    return 1;
  }
  printf("%s\n", url);
  fx = extract_quote_after(line, "fixture");
  if (spark_http_resolve_dry_fixture(url, fx, path, sizeof(path)) !=
      0) {
    free(url);
    free(fx);
    return 1;
  }
  if (spark_http_load_fixture(path, &body, &blen) != 0) {
    free(url);
    free(fx);
    return 1;
  }
  (void)is_post;
  printf("  → %s\n", body);
  set_last(vm, body);
  if (bind_arrow(vm, line) != 0) {
    free(url);
    free(fx);
    free(body);
    return 1;
  }
  free(url);
  free(fx);
  free(body);
  return 0;
}

/* Typed extract.
 *
 * The schema block may span lines, so lines accumulate into xt_stmt
 * until both the block has closed ('}') and the binding has arrived
 * ('->'). extract_pending() lets spark_vm_run_line route continuation
 * lines here instead of treating a lone '}' as a with-tools close.
 *
 * There is no hardcoded reply: the fixture named in the statement is the
 * only source of field values, and a missing fixture or a field that
 * does not match the schema is an error.
 */
static char xt_stmt[SPARK_VM_MAX_LINE * 8];
static size_t xt_len;
static int xt_open;

int spark_vm_extract_pending(void) { return xt_open; }

static int xt_complete(void)
{
  return strchr(xt_stmt, '}') != NULL && strstr(xt_stmt, "->") != NULL;
}

static int xt_run(SparkVM *vm, char *line)
{
  struct spark_extract_schema schema;
  char path[1024];
  char *body = NULL;

  xt_open = 0;
  if (spark_extract_parse_schema(xt_stmt, &schema) != 0)
    return 1;
  if (spark_extract_resolve_fixture(xt_stmt, path, sizeof(path)) != 0)
    return 1;
  if (spark_extract_load_fixture(path, &body, NULL) != 0)
    return 1;
  if (spark_extract_validate(&schema, body) != 0) {
    fprintf(stderr,
            "error: extract %s did not validate against %s\n",
            schema.name, path);
    free(body);
    return 1;
  }
  printf("[extract] %s\n", body);
  set_last(vm, body);
  /* The arrow is on the final line, which is what bind_arrow reads. */
  if (bind_arrow(vm, line) != 0) {
    free(body);
    return 1;
  }
  free(body);
  return 0;
}

static int xt_append(char *line)
{
  size_t n = strlen(line);

  if (xt_len + n + 2 > sizeof(xt_stmt)) {
    fprintf(stderr, "error: extract statement too long\n");
    xt_open = 0;
    return 1;
  }
  memcpy(xt_stmt + xt_len, line, n);
  xt_len += n;
  xt_stmt[xt_len++] = '\n';
  xt_stmt[xt_len] = '\0';
  return 0;
}

static int op_extract(SparkVM *vm, char *line)
{
  xt_len = 0;
  xt_stmt[0] = '\0';
  xt_open = 0;
  if (xt_append(line) != 0)
    return 1;
  if (xt_complete())
    return xt_run(vm, line);
  xt_open = 1;
  return 0;
}

static int op_extract_cont(SparkVM *vm, char *line)
{
  if (xt_append(line) != 0)
    return 1;
  if (xt_complete())
    return xt_run(vm, line);
  return 0;
}

static int op_expect(SparkVM *vm, char *line)
{
  char mode[32];
  char name[SPARK_VM_NAME_MAX];
  char *want = NULL;
  char *want_body = NULL;
  const char *got;
  int want_is_fixture = 0;
  int rc;

  if (spark_expect_parse_stmt(line, mode, sizeof(mode), name,
			      sizeof(name), &want,
			      &want_is_fixture) != 0)
    return 1;
  got = vars_get(vm, name);
  if (!got) {
    fprintf(stderr, "error: expect unknown name %s\n", name);
    free(want);
    return 1;
  }
  if (want_is_fixture) {
    if (spark_expect_load_fixture(want, &want_body, NULL) != 0) {
      free(want);
      return 1;
    }
    rc = spark_expect_check(mode, name, got, want_body);
    free(want_body);
  } else {
    rc = spark_expect_check(mode, name, got, want);
  }
  free(want);
  return rc;
}

static int op_listen(SparkVM *vm, char *line)
{
  (void)vm;
  (void)line;
  return migrated_bc("listen");
}

static int op_speak(SparkVM *vm, char *line)
{
  (void)vm;
  (void)line;
  return migrated_bc("speak");
}

static int op_pipeline(SparkVM *vm, char *line)
{
  (void)vm;
  (void)line;
  printf("[pipeline] step\n");
  return 0;
}

/* Second token after "voice" — GAS-only subs fail before migrated. */
static const char *voice_second_token(const char *line)
{
  static char tok[SPARK_VM_NAME_MAX];
  const char *p = line + 5;
  size_t i = 0;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p == '\0' || *p == '{' || *p == '#')
    return NULL;
  while (*p && *p != ' ' && *p != '\t' && *p != '{' && *p != '"' &&
         i + 1 < sizeof(tok)) {
    tok[i++] = *p++;
  }
  tok[i] = '\0';
  return i ? tok : NULL;
}

static int op_voice(SparkVM *vm, char *line)
{
  const char *sub;
  (void)vm;
  sub = voice_second_token(line);
  if (sub) {
    if (strcmp(sub, "review") == 0 || strcmp(sub, "code") == 0 ||
        strcmp(sub, "copy") == 0 || strcmp(sub, "model") == 0 ||
        strcmp(sub, "pstn") == 0) {
      fprintf(stderr,
              "error: voice %s is GAS-only (companion; not in C "
              "bootstrap yet)\n",
              sub);
      return 1;
    }
  }
  return migrated_bc("voice");
}

/* Second token after "browser" (mirrors asm browser_ops needles). */
static const char *browser_second_token(const char *line)
{
  static char tok[SPARK_VM_NAME_MAX];
  const char *p = line + 7;
  size_t i = 0;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p == '\0' || *p == '#' || *p == '"')
    return NULL;
  while (*p && *p != ' ' && *p != '\t' && *p != '"' && *p != '#' &&
         i + 1 < sizeof(tok)) {
    tok[i++] = *p++;
  }
  tok[i] = '\0';
  return i ? tok : NULL;
}

static int op_browser_show(SparkVM *vm, char *line)
{
  char *q;
  char json[ES_SHOW_JSON_CAP];
  size_t print_n;

  /* Prefix like browser_ops msg_br; dry via engine_show spine. */
  printf("[browser] ");
  q = extract_quote(line);
  if (spark_bootstrap_engine_show(q, json, sizeof(json)) != 0) {
    free(q);
    return 1;
  }
  free(q);
  print_n = strlen(json);
  printf("  → %.*s\n", (int)print_n, json);
  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_browser_flags(SparkVM *vm, char *line)
{
  /* Match asm br_flags → j_flags (no session required). */
  printf("[browser]   → %s\n", BR_FLAGS_DRY);
  set_last(vm, BR_FLAGS_DRY);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

/* Match asm br_render → engine_pipeline_render ([browser] prefix). */
static int op_browser_render(SparkVM *vm, char *line)
{
  char json[ER_RENDER_JSON_CAP];
  size_t print_n;

  printf("[browser] ");
  if (spark_bootstrap_engine_render(json, sizeof(json)) != 0)
    return 1;
  print_n = strlen(json);
  printf("  -> %.*s\n", (int)print_n, json);
  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

/* GAS contains("render") before "engine", so
 * `browser engine render` == browser render. Other engine subs stay
 * fail-loud for now. */
static int op_browser_engine(SparkVM *vm, char *line)
{
  if (strstr(line, "render"))
    return op_browser_render(vm, line);
  fprintf(stderr,
          "error: browser engine is GAS-only except render "
          "(companion/engine; not in C bootstrap yet)\n");
  return 1;
}

static int op_browser(SparkVM *vm, char *line)
{
  const char *sub;
  sub = browser_second_token(line);
  if (!sub) {
    fprintf(stderr,
            "error: unknown browser op (want: run|goto|open|start|"
            "gui|show|flags|render|engine|cdp)\n");
    return 1;
  }
  if (strcmp(sub, "run") == 0 || strcmp(sub, "open") == 0 ||
      strcmp(sub, "start") == 0)
    return migrated_bc("browser run|open|start");
  if (strcmp(sub, "goto") == 0)
    return migrated_bc("browser goto");
  if (strcmp(sub, "show") == 0)
    return op_browser_show(vm, line);
  if (strcmp(sub, "flags") == 0)
    return op_browser_flags(vm, line);
  if (strcmp(sub, "render") == 0)
    return op_browser_render(vm, line);
  if (strcmp(sub, "engine") == 0)
    return op_browser_engine(vm, line);
  if (strcmp(sub, "gui") == 0) {
    fprintf(stderr,
            "[browser] error: browser gui requires --live "
            "(dry-run never launches host GUI)\n");
    return 1;
  }
  if (strcmp(sub, "cdp") == 0) {
    fprintf(stderr,
            "error: browser %s is GAS-only (companion/engine; not in "
            "C bootstrap yet)\n",
            sub);
    return 1;
  }
  fprintf(stderr,
          "error: unknown browser op (want: run|goto|open|start|"
          "gui|show|flags|render|engine|cdp)\n");
  return 1;
}

/* Second token after "mitm" (mirrors asm browser_ops needles). */
static const char *mitm_second_token(const char *line)
{
  static char tok[SPARK_VM_NAME_MAX];
  const char *p = line + 4;
  size_t i = 0;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p == '\0' || *p == '#' || *p == '"')
    return NULL;
  while (*p && *p != ' ' && *p != '\t' && *p != '"' && *p != '#' &&
         i + 1 < sizeof(tok)) {
    tok[i++] = *p++;
  }
  tok[i] = '\0';
  return i ? tok : NULL;
}

static int op_mitm_enable(SparkVM *vm, char *line)
{
  (void)vm;
  if (strstr(line, "--live")) {
    fprintf(stderr,
            "[mitm] error: mitm enable --live requires ./spark "
            "(C bootstrap is dry-only; never forks spark-mitm-h2)\n");
    return 1;
  }
  return migrated_bc("mitm enable");
}

static int op_mitm(SparkVM *vm, char *line)
{
  const char *sub;
  sub = mitm_second_token(line);
  if (!sub) {
    fprintf(stderr,
            "error: unknown mitm op (want: enable|disable|"
            "disable_quic|filter|har|smoke|quic|ca-*)\n");
    return 1;
  }
  if (strcmp(sub, "enable") == 0)
    return op_mitm_enable(vm, line);
  /* Live / companion lanes stay GAS-only — fail loud, no invent. */
  fprintf(stderr,
          "error: mitm %s is GAS-only (companion/live; not in C "
          "bootstrap yet)\n",
          sub);
  return 1;
}

/* Second token after "engine" (mirrors engine_ops_dispatch). */
static const char *engine_second_token(const char *line)
{
  static char tok[SPARK_VM_NAME_MAX];
  const char *p = line + 6;
  size_t i = 0;
  while (*p == ' ' || *p == '\t')
    p++;
  if (*p == '\0' || *p == '#' || *p == '"')
    return NULL;
  while (*p && *p != ' ' && *p != '\t' && *p != '"' && *p != '#' &&
         i + 1 < sizeof(tok)) {
    tok[i++] = *p++;
  }
  tok[i] = '\0';
  return i ? tok : NULL;
}

static int ensure_engine_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/engine", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

/* Copy local path → out/engine/body.bin; return byte count or -1. */
static long copy_to_body_bin(const char *path)
{
  FILE *in;
  FILE *out;
  char buf[4096];
  size_t n;
  long total = 0;
  if (ensure_engine_dirs() != 0)
    return -1;
  in = fopen(path, "rb");
  if (!in)
    return -1;
  out = fopen(EF_BODY_PATH, "wb");
  if (!out) {
    fclose(in);
    return -1;
  }
  while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
    if (fwrite(buf, 1, n, out) != n) {
      fclose(in);
      fclose(out);
      return -1;
    }
    total += (long)n;
  }
  if (ferror(in)) {
    fclose(in);
    fclose(out);
    return -1;
  }
  fclose(in);
  fclose(out);
  return total;
}

static int op_engine_fetch(SparkVM *vm, char *line)
{
  char *url;
  const char *path;
  char json[SPARK_VM_VAL_MAX];
  char pjson[EP_JSON_CAP];
  long bytes;
  int n;
  int want_parse;
  size_t print_n;

  /* Bootstrap is always dry — refuse in-line --live (GAS live uses
   * --allow-net + companion/sockets; C path never dials). */
  if (strstr(line, "--live")) {
    fprintf(stderr,
            "[engine] error: engine fetch --live requires ./spark "
            "(C bootstrap is dry-only; never dials / forks "
            "spark-engine-fetch-tls)\n");
    return 1;
  }
  want_parse = contains_ci(line, "parse");

  url = extract_quote(line);
  if (!url) {
    fprintf(stderr,
            "error: engine fetch needs a quoted URL "
            "(engine fetch \"URL\")\n");
    return 1;
  }

  printf("[engine] [engine.fetch] %s\n", url);

  if (strncmp(url, "https://", 8) == 0) {
    fprintf(stderr,
            "error: engine fetch: https blocked by default "
            "(no network dial).\n"
            "  Pass --allow-net to fork ./spark-engine-fetch-tls "
            "(OpenSSL BIO), or use file://\n");
    free(url);
    return 1;
  }
  if (strncmp(url, "http://", 7) == 0) {
    fprintf(stderr,
            "error: engine fetch: remote http(s) blocked by default "
            "(no network dial).\n"
            "  Pass --allow-net for http:// (asm socket) or https:// "
            "(OpenSSL BIO companion), or use file:// / a local path.\n");
    free(url);
    return 1;
  }

  if (strncmp(url, "file://", 7) == 0)
    path = url + 7;
  else
    path = url;

  bytes = copy_to_body_bin(path);
  if (bytes < 0) {
    fprintf(stderr, "error: engine fetch: cannot open local path\n");
    free(url);
    return 1;
  }

  n = snprintf(json, sizeof(json), "%s%ld%s%s%s", EF_JSON_FILE_PRE, bytes,
               EF_JSON_MID_URL, url, EF_JSON_END);
  free(url);
  if (n < 0 || (size_t)n >= sizeof(json)) {
    fprintf(stderr, "error: engine fetch json overflow\n");
    return 1;
  }
  printf("  → %s\n", json);

  if (want_parse) {
    /* Match .do_fetch_parse: parse body.bin then j_fp */
    printf("[engine] ");
    if (spark_bootstrap_engine_parse(EF_BODY_PATH, pjson,
                                     sizeof(pjson)) != 0)
      return 1;
    print_n = strlen(pjson);
    if (print_n > 512)
      print_n = 512;
    printf("  → %.*s\n", (int)print_n, pjson);
    if (print_n < strlen(pjson))
      printf("\n");
    printf("  -> %s\n", EF_JSON_FETCH_PARSE);
    /* GAS bind/print keeps fetch JSON as last (fetch_dispatch bind). */
    set_last(vm, json);
    if (bind_arrow(vm, line) != 0)
      return 1;
    return 0;
  }

  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_parse(SparkVM *vm, char *line)
{
  char *quoted;
  const char *path;
  char pathbuf[SPARK_VM_VAL_MAX];
  char json[EP_JSON_CAP];
  size_t print_n;

  quoted = extract_quote(line);
  if (quoted) {
    strncpy(pathbuf, quoted, sizeof(pathbuf) - 1);
    pathbuf[sizeof(pathbuf) - 1] = '\0';
    free(quoted);
  } else {
    strncpy(pathbuf, "engine/fixtures/hello.html",
            sizeof(pathbuf) - 1);
    pathbuf[sizeof(pathbuf) - 1] = '\0';
  }
  if (strncmp(pathbuf, "file://", 7) == 0)
    path = pathbuf + 7;
  else
    path = pathbuf;

  printf("[engine] ");
  if (spark_bootstrap_engine_parse(path, json, sizeof(json)) != 0)
    return 1;

  print_n = strlen(json);
  if (print_n > 512)
    print_n = 512;
  printf("  → %.*s\n", (int)print_n, json);
  if (print_n < strlen(json))
    printf("\n");
  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_css(SparkVM *vm, char *line)
{
  printf("[engine] ");
  if (spark_bootstrap_engine_css_attach() != 0)
    return 1;
  printf("  -> %s\n", EC_PATH);
  set_last(vm, EC_PATH);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_layout(SparkVM *vm, char *line)
{
  char json[EL_JSON_CAP];
  size_t print_n;
  int fixture;
  int tbl;

  fixture = contains_ci(line, "fixture");
  printf("[engine] ");
  if (fixture) {
    if (spark_bootstrap_engine_layout_fixture(json, sizeof(json)) !=
        0)
      return 1;
  } else {
    if (spark_bootstrap_engine_layout(json, sizeof(json)) != 0)
      return 1;
  }
  print_n = strlen(json);
  if (print_n > 0 && json[print_n - 1] == '\n')
    print_n--;
  printf("  -> %.*s\n", (int)print_n, json);
  if (!fixture) {
    fflush(stdout);
    tbl = spark_bootstrap_engine_layout_emit_table();
    if (tbl == 0)
      printf("  -> ");
  }
  set_last(vm, EL_PATH);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_paint(SparkVM *vm, char *line)
{
  char json[EP_PAINT_JSON_CAP];
  size_t print_n;
  int fixture;
  int boxes;

  fixture = contains_ci(line, "fixture");
  boxes = contains_ci(line, "boxes") || contains_ci(line, "layout");
  printf("[engine] ");
  if (fixture) {
    /* asm fixture prints its JSON to stdout (match GAS dispatch) */
    if (spark_bootstrap_engine_paint_fixture(json, sizeof(json)) !=
        0)
      return 1;
    set_last(vm, EP_FIXTURE_PPM);
  } else if (boxes) {
    if (spark_bootstrap_engine_paint_boxes(json, sizeof(json)) != 0)
      return 1;
    print_n = strlen(json);
    if (print_n > 0 && json[print_n - 1] == '\n')
      print_n--;
    printf("  -> %.*s\n", (int)print_n, json);
    set_last(vm, EP_PPM_PATH);
  } else {
    fprintf(stderr,
            "error: engine paint expects: engine paint fixture\n");
    return 1;
  }
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_show(SparkVM *vm, char *line)
{
  char *q;
  char json[ES_SHOW_JSON_CAP];
  size_t print_n;

  printf("[engine] ");
  q = extract_quote(line);
  if (spark_bootstrap_engine_show(q, json, sizeof(json)) != 0) {
    free(q);
    return 1;
  }
  free(q);
  print_n = strlen(json);
  printf("  -> %.*s\n", (int)print_n, json);
  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine_render(SparkVM *vm, char *line)
{
  char json[ER_RENDER_JSON_CAP];
  size_t print_n;

  printf("[engine] ");
  if (spark_bootstrap_engine_render(json, sizeof(json)) != 0)
    return 1;
  print_n = strlen(json);
  printf("  -> %.*s\n", (int)print_n, json);
  set_last(vm, json);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

static int op_engine(SparkVM *vm, char *line)
{
  const char *sub;
  sub = engine_second_token(line);
  if (!sub) {
    fprintf(stderr,
            "error: unknown engine op (want: fetch|parse|css|"
            "layout|paint|render|show)\n");
    return 1;
  }
  if (strcmp(sub, "fetch") == 0)
    return op_engine_fetch(vm, line);
  if (strcmp(sub, "parse") == 0)
    return op_engine_parse(vm, line);
  if (strcmp(sub, "css") == 0)
    return op_engine_css(vm, line);
  if (strcmp(sub, "layout") == 0)
    return op_engine_layout(vm, line);
  if (strcmp(sub, "paint") == 0)
    return op_engine_paint(vm, line);
  if (strcmp(sub, "render") == 0)
    return op_engine_render(vm, line);
  if (strcmp(sub, "show") == 0)
    return op_engine_show(vm, line);
  fprintf(stderr,
          "error: engine %s is GAS-only (asm engine_*; not in C "
          "bootstrap yet)\n",
          sub);
  return 1;
}

static int op_review(SparkVM *vm, char *line)
{
  char *q;
  const char *report;
  const char *heuristic;

  if (contains_ci(line, "url")) {
    fprintf(stderr,
            "error: review url is GAS-only (companion; not in C "
            "bootstrap yet)\n");
    return 1;
  }
  printf("[review] ");
  q = extract_quote(line);
  if (!q) {
    printf("\n");
    heuristic = line;
  } else if (contains_ci(line, "path")) {
    FILE *f = fopen(q, "r");
    if (!f) {
      fprintf(stderr, "error: review path cannot open file\n");
      free(q);
      return 1;
    }
    fclose(f);
    printf("%s\n", q);
    heuristic = q;
  } else {
    printf("%s\n", q);
    heuristic = q;
  }
  report = spark_pick_review_report(heuristic);
  if (q)
    free(q);
  printf("  (static only — never eval web JS)\n");
  printf("  → %s\n", report);
  set_last(vm, report);
  if (bind_arrow(vm, line) != 0)
    return 1;
  return 0;
}

void spark_vm_init(SparkVM *vm)
{
  memset(vm, 0, sizeof(*vm));
  vm->dry_run = 1;
  /* Prior line from spark.toml only — no Bifrost alias roulette. */
  load_spark_toml_model(vm);
}

#define SPARK_INCLUDE_DEPTH_MAX 8
#define SPARK_INCLUDE_STACK_MAX 16

static int run_file_inner(SparkVM *vm, const char *path, int depth,
                          const char stack[][512], int nstack)
{
  FILE *f;
  char line[SPARK_VM_MAX_LINE];
  int rc = 0;
  int i;

  if (depth > SPARK_INCLUDE_DEPTH_MAX) {
    fprintf(stderr, "error: include depth exceeded (max %d)\n",
            SPARK_INCLUDE_DEPTH_MAX);
    return 1;
  }
  for (i = 0; i < nstack; i++) {
    if (strcmp(stack[i], path) == 0) {
      fprintf(stderr, "error: include cycle: %s\n", path);
      return 1;
    }
  }
  if (nstack >= SPARK_INCLUDE_STACK_MAX) {
    fprintf(stderr, "error: include stack full\n");
    return 1;
  }
  f = fopen(path, "r");
  if (!f) {
    perror(path);
    return 1;
  }
  if (depth == 0)
    printf("[spark] dry-run via C bootstrap VM (model=%s)\n",
           vm->model_alias);
  else
    printf("[include] %s\n", path);
  while (fgets(line, sizeof(line), f)) {
    char *inc;
    char incpath[512];
    if (kw_at(ltrim(line), "include")) {
      inc = extract_quote(line);
      if (!inc) {
        fprintf(stderr,
                "error: include requires quoted path "
                "(include \"lib/ai.spark\")\n");
        rc = 1;
        break;
      }
      strncpy(incpath, inc, sizeof(incpath) - 1);
      incpath[sizeof(incpath) - 1] = '\0';
      free(inc);
      {
        char newstack[SPARK_INCLUDE_STACK_MAX][512];
        if (nstack > 0)
          memcpy(newstack, stack, (size_t)nstack * 512);
        strncpy(newstack[nstack], path, 511);
        newstack[nstack][511] = '\0';
        if (run_file_inner(vm, incpath, depth + 1, newstack,
                           nstack + 1) != 0) {
          rc = 1;
          break;
        }
      }
      continue;
    }
    if (spark_vm_run_line(vm, line) != 0) {
      rc = 1;
      break;
    }
  }
  fclose(f);
  return rc;
}

int spark_vm_run_line(SparkVM *vm, const char *raw)
{
  char buf[SPARK_VM_MAX_LINE];
  char *line;
  size_t n;
  if (!raw)
    return 0;
  n = strlen(raw);
  if (n >= sizeof(buf)) {
    fprintf(stderr, "error: line too long\n");
    return 1;
  }
  memcpy(buf, raw, n + 1);
  rtrim(buf);
  line = ltrim(buf);
  if (line[0] == '\0' || line[0] == '#')
    return 0;
  /* An open extract schema block claims every line, including a lone
   * '}', so it is tested before the with-tools close below. */
  if (spark_vm_extract_pending())
    return op_extract_cont(vm, line);
  /* ? "prompt" -> ask sugar */
  if (line[0] == '?') {
    char tmp[SPARK_VM_MAX_LINE];
    snprintf(tmp, sizeof(tmp), "ask %s", ltrim(line + 1));
    return spark_vm_run_line(vm, tmp);
  }
  /* GAS: } clears with-tools; { alone is no-op; | prefixes next kw */
  if (line[0] == '}') {
    vm->tools_active = 0;
    return 0;
  }
  if (line[0] == '{')
    return 0;
  if (line[0] == '|') {
    line = ltrim(line + 1);
    if (line[0] == '\0')
      return 0;
  }

  if (kw_at(line, "model") || kw_at(line, "use"))
    return op_model(vm, line);
  if (kw_at(line, "ask") || kw_at(line, "generate"))
    return op_ask(vm, line);
  if (kw_at(line, "print"))
    return op_print(vm, line);
  if (kw_at(line, "let"))
    return op_let(vm, line);
  if (kw_at(line, "classify"))
    return op_classify(vm, line);
  if (kw_at(line, "embed"))
    return op_embed(vm, line);
  if (kw_at(line, "retrieve"))
    return op_retrieve(vm, line);
  if (kw_at(line, "shell") || kw_at(line, "run"))
    return op_shell(vm, line);
  if (kw_at(line, "http"))
    return op_http(vm, line);
  if (kw_at(line, "extract"))
    return op_extract(vm, line);
  if (kw_at(line, "expect"))
    return op_expect(vm, line);
  if (kw_at(line, "tool"))
    return migrated_bc("tool");
  if (kw_at(line, "with"))
    return migrated_bc("with tools");
  if (kw_at(line, "listen"))
    return op_listen(vm, line);
  if (kw_at(line, "speak") || kw_at(line, "say"))
    return op_speak(vm, line);
  if (kw_at(line, "pipeline")) {
    char *brace = strchr(line, '{');
    if (brace) *brace = '\0';
    return op_pipeline(vm, line);
  }
  if (kw_at(line, "review"))
    return op_review(vm, line);
  if (kw_at(line, "voice"))
    return op_voice(vm, line);
  if (kw_at(line, "browser"))
    return op_browser(vm, line);
  if (kw_at(line, "mitm"))
    return op_mitm(vm, line);
  if (kw_at(line, "engine"))
    return op_engine(vm, line);

  if (line[0] == '"')
    return 0;
  if (looks_like_field(line))
    return 0;

  /* Known language keywords still GAS-only — fail loud, no invent. */
  {
    static const char *gas_only[] = {
        "builder", "implement",
        "network", "os",      "cuda",      "pcie",
        "encrypt",  "memory",  "ide",     "gateway",   "set",
        NULL};
    size_t i;
    for (i = 0; gas_only[i]; i++) {
      if (kw_at(line, gas_only[i])) {
        fprintf(stderr,
                "error: op '%s' is GAS-only (not in C bootstrap yet)\n",
                gas_only[i]);
        return 1;
      }
    }
  }
  fprintf(stderr,
          "error: unknown statement: %s\n"
          "  hint: model|use|ask|?|classify|embed|retrieve|http|"
          "shell|extract|expect|pipeline|include (bootstrap)\n",
          line);
  return 1;
}

int spark_vm_run_file(SparkVM *vm, const char *path)
{
  int rc;
  rc = run_file_inner(vm, path, 0, NULL, 0);
  if (rc == 0)
    printf("[spark] ok\n");
  return rc;
}
