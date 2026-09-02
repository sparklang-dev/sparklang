#include "dry_engine.h"

#include "engine_css.h"
#include "engine_layout.h"
#include "engine_paint.h"
#include "engine_parse.h"
#include "engine_render.h"
#include "engine_show.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern void spark_layout_reset(void);

static const char EF_JSON_FILE_PRE[] =
    "{\"op\":\"engine.fetch\",\"ok\":true,"
    "\"source\":\"file\",\"scheme\":\"file\","
    "\"fetched\":false,\"transport\":\"open\","
    "\"path\":\"out/engine/body.bin\","
    "\"bytes\":";
static const char EF_JSON_MID_URL[] = ",\"url\":\"";
static const char EF_JSON_END[] = "\"}";
static const char EF_BODY_PATH[] = "out/engine/body.bin";
static const char EF_JSON_FETCH_PARSE[] =
    "{\"op\":\"engine.fetch_parse\",\"ok\":true,"
    "\"body\":\"out/engine/body.bin\","
    "\"next\":\"engine.parse\"}";

static int bind_last(SparkDryEngineCtx *ctx, const char *bind)
{
  if (!bind || !bind[0] || !ctx->vars_put)
    return 0;
  return ctx->vars_put(ctx->frame, bind, ctx->last);
}

static int ensure_engine_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/engine", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

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

int spark_dry_engine_fetch(SparkDryEngineCtx *ctx, const char *url,
                           int want_parse, const char *bind)
{
  const char *path;
  char json[SPARK_VM_VAL_MAX];
  char pjson[EP_JSON_CAP];
  long bytes;
  int n;
  size_t print_n;

  if (!url || !url[0]) {
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
    return 1;
  }
  if (strncmp(url, "http://", 7) == 0) {
    fprintf(stderr,
            "error: engine fetch: remote http(s) blocked by default "
            "(no network dial).\n"
            "  Pass --allow-net for http:// (asm socket) or https:// "
            "(OpenSSL BIO companion), or use file:// / a local path.\n");
    return 1;
  }
  if (strncmp(url, "file://", 7) == 0)
    path = url + 7;
  else
    path = url;
  bytes = copy_to_body_bin(path);
  if (bytes < 0) {
    fprintf(stderr, "error: engine fetch: cannot open local path\n");
    return 1;
  }
  n = snprintf(json, sizeof(json), "%s%ld%s%s%s", EF_JSON_FILE_PRE, bytes,
               EF_JSON_MID_URL, url, EF_JSON_END);
  if (n < 0 || (size_t)n >= sizeof(json)) {
    fprintf(stderr, "error: engine fetch json overflow\n");
    return 1;
  }
  printf("  → %s\n", json);
  if (want_parse) {
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
    strncpy(ctx->last, json, SPARK_VM_VAL_MAX - 1);
    ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
    return bind_last(ctx, bind);
  }
  strncpy(ctx->last, json, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_parse(SparkDryEngineCtx *ctx, const char *path,
                           const char *bind)
{
  char pathbuf[SPARK_VM_VAL_MAX];
  char json[EP_JSON_CAP];
  size_t print_n;

  if (!path || !path[0])
    path = "engine/fixtures/hello.html";
  if (strncmp(path, "file://", 7) == 0)
    snprintf(pathbuf, sizeof(pathbuf), "%s", path + 7);
  else
    snprintf(pathbuf, sizeof(pathbuf), "%s", path);
  printf("[engine] ");
  if (spark_bootstrap_engine_parse(pathbuf, json, sizeof(json)) != 0)
    return 1;
  print_n = strlen(json);
  if (print_n > 512)
    print_n = 512;
  printf("  → %.*s\n", (int)print_n, json);
  if (print_n < strlen(json))
    printf("\n");
  strncpy(ctx->last, json, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_css(SparkDryEngineCtx *ctx, const char *bind)
{
  printf("[engine] ");
  if (spark_bootstrap_engine_css_attach() != 0)
    return 1;
  printf("  -> %s\n", EC_PATH);
  strncpy(ctx->last, EC_PATH, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_layout(SparkDryEngineCtx *ctx, int fixture,
                            const char *bind)
{
  char json[EL_JSON_CAP];
  size_t print_n;
  int tbl;

  printf("[engine] ");
  if (fixture) {
    if (spark_bootstrap_engine_layout_fixture(json, sizeof(json)) != 0)
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
  strncpy(ctx->last, EL_PATH, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_paint(SparkDryEngineCtx *ctx, int fixture, int boxes,
                           const char *bind)
{
  char json[EP_PAINT_JSON_CAP];
  size_t print_n;

  printf("[engine] ");
  if (fixture) {
    if (spark_bootstrap_engine_paint_fixture(json, sizeof(json)) != 0)
      return 1;
    strncpy(ctx->last, EP_FIXTURE_PPM, SPARK_VM_VAL_MAX - 1);
  } else if (boxes) {
    if (spark_bootstrap_engine_paint_boxes(json, sizeof(json)) != 0)
      return 1;
    print_n = strlen(json);
    if (print_n > 0 && json[print_n - 1] == '\n')
      print_n--;
    printf("  -> %.*s\n", (int)print_n, json);
    strncpy(ctx->last, EP_PPM_PATH, SPARK_VM_VAL_MAX - 1);
  } else {
    fprintf(stderr,
            "error: engine paint expects: engine paint fixture\n");
    return 1;
  }
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_show(SparkDryEngineCtx *ctx, const char *path,
                          const char *bind)
{
  char json[ES_SHOW_JSON_CAP];
  size_t print_n;

  printf("[engine] ");
  if (spark_bootstrap_engine_show(path, json, sizeof(json)) != 0)
    return 1;
  print_n = strlen(json);
  printf("  -> %.*s\n", (int)print_n, json);
  strncpy(ctx->last, json, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

int spark_dry_engine_render(SparkDryEngineCtx *ctx, const char *bind)
{
  char json[ER_RENDER_JSON_CAP];
  size_t print_n;

  printf("[engine] ");
  if (spark_bootstrap_engine_render(json, sizeof(json)) != 0)
    return 1;
  print_n = strlen(json);
  printf("  -> %.*s\n", (int)print_n, json);
  strncpy(ctx->last, json, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  return bind_last(ctx, bind);
}

static char *extract_quote_line(const char *line)
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
        char *nb = realloc(out, cap);
        if (!nb) {
          free(out);
          return NULL;
        }
        out = nb;
      }
    }
    out[n++] = c;
  }
  out[n] = '\0';
  return out;
}

static int contains_word(const char *hay, const char *needle)
{
  size_t nlen = strlen(needle);
  const char *p = hay;
  if (!needle[0])
    return 0;
  while ((p = strstr(p, needle)) != NULL) {
    if ((p == hay || p[-1] == ' ' || p[-1] == '\t') &&
        (p[nlen] == '\0' || p[nlen] == ' ' || p[nlen] == '\t' ||
         p[nlen] == '"'))
      return 1;
    p++;
  }
  return 0;
}

static const char *engine_subcmd(const char *line)
{
  static char tok[64];
  const char *p = line;
  size_t i = 0;
  if (strncmp(p, "engine", 6) != 0)
    return NULL;
  p += 6;
  while (*p == ' ' || *p == '\t')
    p++;
  while (*p && *p != ' ' && *p != '\t' && *p != '"' && *p != '#' &&
         i + 1 < sizeof(tok)) {
    tok[i++] = *p++;
  }
  tok[i] = '\0';
  return i ? tok : NULL;
}

int spark_dry_engine_run_line(SparkDryEngineCtx *ctx, char *line)
{
  const char *sub;
  char *quoted;
  char qbuf[SPARK_VM_VAL_MAX];
  const char *bind = "";

  if (strstr(line, "--live")) {
    fprintf(stderr,
            "[engine] error: engine fetch --live requires ./spark "
            "(C bootstrap is dry-only; never dials / forks "
            "spark-engine-fetch-tls)\n");
    return 1;
  }
  sub = engine_subcmd(line);
  if (!sub) {
    fprintf(stderr,
            "error: unknown engine op (want: fetch|parse|css|"
            "layout|paint|render|show)\n");
    return 1;
  }
  if (strcmp(sub, "fetch") == 0) {
    int want_parse = contains_word(line, "parse");
    quoted = extract_quote_line(line);
    if (!quoted) {
      fprintf(stderr,
              "error: engine fetch needs a quoted URL "
              "(engine fetch \"URL\")\n");
      return 1;
    }
    {
      int rc = spark_dry_engine_fetch(ctx, quoted, want_parse, bind);
      free(quoted);
      return rc;
    }
  }
  if (strcmp(sub, "parse") == 0) {
    quoted = extract_quote_line(line);
    if (quoted) {
      snprintf(qbuf, sizeof(qbuf), "%s", quoted);
      free(quoted);
      return spark_dry_engine_parse(ctx, qbuf, bind);
    }
    return spark_dry_engine_parse(ctx, "engine/fixtures/hello.html", bind);
  }
  if (strcmp(sub, "css") == 0)
    return spark_dry_engine_css(ctx, bind);
  if (strcmp(sub, "layout") == 0)
    return spark_dry_engine_layout(ctx, contains_word(line, "fixture"), bind);
  if (strcmp(sub, "paint") == 0)
    return spark_dry_engine_paint(ctx, contains_word(line, "fixture"),
                                  contains_word(line, "boxes") ||
                                      contains_word(line, "layout"),
                                  bind);
  if (strcmp(sub, "show") == 0) {
    quoted = extract_quote_line(line);
    int rc = spark_dry_engine_show(ctx, quoted, bind);
    free(quoted);
    return rc;
  }
  if (strcmp(sub, "render") == 0)
    return spark_dry_engine_render(ctx, bind);
  fprintf(stderr,
          "error: engine %s is GAS-only (asm engine_*; not in C "
          "bootstrap yet)\n",
          sub);
  return 1;
}

void spark_dry_engine_reset(void)
{
  static const char *stale[] = {
      "out/engine/body.bin",
      "out/browser/engine/dom.json",
      "out/browser/engine/css.json",
      "out/browser/engine/layout.json",
      NULL,
  };
  int i;

  spark_bootstrap_dom_reset();
  spark_bootstrap_engine_css_reset();
  spark_layout_reset();
  for (i = 0; stale[i]; i++)
    unlink(stale[i]);
}
