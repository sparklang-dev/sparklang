/* Parse + compile hello/mini (LANGUAGE.md model/ask/print). */
#include "spark_parse.h"

#include "../selfhost/lex.h"
#include "bc_opcodes.h"
#include "bc_vm.h"
#include "bc_write.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define TOK_MAX 4096
#define LEX_MAX 512
#define KIND_MAX 16

typedef struct {
  char kind[KIND_MAX];
  char lexeme[LEX_MAX];
  long line;
  long col;
} Tok;

static Tok toks[TOK_MAX];
static size_t ntoks;

static int json_unescape(const char *in, char *out, size_t out_cap)
{
  size_t oi = 0;
  for (; *in && oi + 1 < out_cap; in++) {
    if (*in == '\\' && in[1]) {
      in++;
      if (*in == 'n')
        out[oi++] = '\n';
      else if (*in == 't')
        out[oi++] = '\t';
      else if (*in == 'u') {
        /* skip \uXXXX — not in hello goldens */
        in += 4;
      } else
        out[oi++] = *in;
    } else {
      out[oi++] = *in;
    }
  }
  out[oi] = '\0';
  return 0;
}

static int parse_jsonl_line(const char *line, Tok *t)
{
  const char *p;
  const char *kstart;
  const char *kend;
  const char *lstart;
  const char *lend;
  char kind_raw[KIND_MAX];
  char lex_raw[LEX_MAX * 2];

  p = strstr(line, "\"kind\":\"");
  if (!p)
    return -1;
  kstart = p + 8;
  kend = strchr(kstart, '"');
  if (!kend || (size_t)(kend - kstart) >= KIND_MAX)
    return -1;
  memcpy(kind_raw, kstart, (size_t)(kend - kstart));
  kind_raw[kend - kstart] = '\0';

  p = strstr(line, "\"lexeme\":\"");
  if (!p)
    return -1;
  lstart = p + 10;
  lend = lstart;
  while (*lend) {
    if (*lend == '\\' && lend[1]) {
      lend += 2;
      continue;
    }
    if (*lend == '"')
      break;
    lend++;
  }
  if ((size_t)(lend - lstart) >= sizeof(lex_raw))
    return -1;
  memcpy(lex_raw, lstart, (size_t)(lend - lstart));
  lex_raw[lend - lstart] = '\0';

  p = strstr(line, "\"line\":");
  if (!p || sscanf(p + 7, "%ld", &t->line) != 1)
    return -1;
  p = strstr(line, "\"col\":");
  if (!p || sscanf(p + 6, "%ld", &t->col) != 1)
    return -1;

  strncpy(t->kind, kind_raw, KIND_MAX - 1);
  t->kind[KIND_MAX - 1] = '\0';
  json_unescape(lex_raw, t->lexeme, LEX_MAX);
  return 0;
}

static int load_tokens(const char *path)
{
  FILE *tmp;
  char line[4096];
  ntoks = 0;
  tmp = tmpfile();
  if (!tmp)
    return -1;
  if (spark_lex_file(path, tmp) != 0) {
    fclose(tmp);
    return -1;
  }
  rewind(tmp);
  while (fgets(line, sizeof(line), tmp)) {
    if (ntoks >= TOK_MAX)
      break;
    if (parse_jsonl_line(line, &toks[ntoks]) != 0)
      continue;
    ntoks++;
  }
  fclose(tmp);
  return (ntoks > 0) ? 0 : -1;
}

static size_t cur;

static Tok *peek(void)
{
  while (cur < ntoks && strcmp(toks[cur].kind, "COMMENT") == 0)
    cur++;
  if (cur >= ntoks)
    return NULL;
  return &toks[cur];
}

static Tok *take(void)
{
  Tok *t = peek();
  if (t)
    cur++;
  return t;
}

static int emit_ast(FILE *out, const char *kind, long line, const char *fmt,
                    ...)
{
  va_list ap;
  int n;
  va_start(ap, fmt);
  n = fprintf(out, "{\"kind\":\"%s\",\"line\":%ld,", kind, line);
  if (n < 0) {
    va_end(ap);
    return -1;
  }
  n = vfprintf(out, fmt, ap);
  va_end(ap);
  if (n < 0)
    return -1;
  if (fputc('}', out) == EOF || fputc('\n', out) == EOF)
    return -1;
  return 0;
}

int spark_parse_ast_file(const char *path, FILE *out)
{
  size_t i;
  long end_line = 1;

  if (!path || !out)
    return 1;
  if (load_tokens(path) != 0) {
    fprintf(stderr, "error: parse cannot lex %s\n", path);
    return 1;
  }
  cur = 0;
  for (i = 0; i < ntoks; i++)
    if (strcmp(toks[i].kind, "EOF") == 0)
      end_line = toks[i].line;

  while (peek() && strcmp(peek()->kind, "EOF") != 0) {
    Tok *kw = take();
    if (!kw)
      break;
    if (strcmp(kw->kind, "COMMENT") == 0)
      continue;
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        (strcmp(kw->lexeme, "model") == 0 ||
         strcmp(kw->lexeme, "use") == 0)) {
      Tok *alias = take();
      if (!alias || strcmp(alias->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: model/use needs alias\n",
                kw->line);
        return 1;
      }
      if (emit_ast(out, "Model", kw->line, "\"alias\":\"%s\"",
                   alias->lexeme) != 0)
        return 1;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "ask") == 0) {
      Tok *prompt = take();
      Tok *arrow;
      Tok *bind;
      char prompt_buf[256];
      if (!prompt || strcmp(prompt->kind, "STRING") != 0) {
        fprintf(stderr, "error:%ld: ask needs string\n", kw->line);
        return 1;
      }
      if (prompt->lexeme[0] == '"')
        snprintf(prompt_buf, sizeof(prompt_buf), "%.*s",
                 (int)(strlen(prompt->lexeme) - 2), prompt->lexeme + 1);
      else
        snprintf(prompt_buf, sizeof(prompt_buf), "%.*s",
                 (int)sizeof(prompt_buf) - 1, prompt->lexeme);
      arrow = take();
      bind = take();
      if (!arrow || strcmp(arrow->kind, "ARROW") != 0 || !bind ||
          strcmp(bind->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: ask needs -> ident\n", kw->line);
        return 1;
      }
      if (emit_ast(out, "Ask", kw->line,
                   "\"prompt\":\"%s\",\"bind\":\"%s\"", prompt_buf,
                   bind->lexeme) != 0)
        return 1;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "print") == 0) {
      Tok *ident = take();
      if (!ident || strcmp(ident->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: print needs ident\n", kw->line);
        return 1;
      }
      if (emit_ast(out, "Print", kw->line, "\"ident\":\"%s\"",
                   ident->lexeme) != 0)
        return 1;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "let") == 0) {
      Tok *name = take();
      Tok *val = take();
      char val_buf[256];
      if (!name || strcmp(name->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: let needs name\n", kw->line);
        return 1;
      }
      if (!val) {
        fprintf(stderr, "error:%ld: let needs value\n", kw->line);
        return 1;
      }
      if (val->lexeme[0] == '"')
        snprintf(val_buf, sizeof(val_buf), "%.*s",
                 (int)(strlen(val->lexeme) - 2), val->lexeme + 1);
      else
        snprintf(val_buf, sizeof(val_buf), "%.*s",
                 (int)sizeof(val_buf) - 1, val->lexeme);
      if (emit_ast(out, "Let", kw->line, "\"name\":\"%s\",\"value\":\"%s\"",
                   name->lexeme, val_buf) != 0)
        return 1;
      continue;
    }
    /* Non-hello statements: emit opaque Stmt for AST golden only. */
    if (emit_ast(out, "Stmt", kw->line, "\"lexeme\":\"%s\"",
                 kw->lexeme) != 0)
      return 1;
    while (peek() && strcmp(peek()->kind, "EOF") != 0 &&
           !(strcmp(peek()->kind, "KEYWORD") == 0)) {
      Tok *skip = take();
      if (!skip)
        break;
      if (strcmp(skip->kind, "EOF") == 0)
        break;
    }
  }
  if (fprintf(out, "{\"kind\":\"ProgramEnd\",\"line\":%ld}\n", end_line) < 0)
    return 1;
  return 0;
}

typedef struct {
  char *bytes;
  uint16_t len;
} StrSlot;

static StrSlot str_slots[64];
static size_t nstrs;
static SparkBcConst consts[64];
static size_t nconsts;
static uint8_t code[4096];
static size_t ncode;

static uint16_t intern_str(const char *lit)
{
  size_t i;
  size_t len = strlen(lit);
  for (i = 0; i < nstrs; i++) {
    if (str_slots[i].len == len &&
        memcmp(str_slots[i].bytes, lit, len) == 0)
      return (uint16_t)i;
  }
  if (nstrs >= 64)
    return 0;
  str_slots[nstrs].bytes = malloc(len + 1);
  if (!str_slots[nstrs].bytes)
    return 0;
  memcpy(str_slots[nstrs].bytes, lit, len + 1);
  str_slots[nstrs].len = (uint16_t)len;
  return (uint16_t)nstrs++;
}

static uint16_t add_str_const(const char *lit)
{
  uint16_t si = intern_str(lit);
  uint16_t ci;
  size_t i;
  for (i = 0; i < nconsts; i++) {
    if (consts[i].kind == SPBC_CONST_STR && consts[i].payload == si)
      return (uint16_t)i;
  }
  if (nconsts >= 64)
    return 0;
  ci = (uint16_t)nconsts++;
  consts[ci].kind = SPBC_CONST_STR;
  consts[ci].payload = si;
  return ci;
}

static void emit_op0(uint8_t op) { code[ncode++] = op; }

static void emit_op(uint8_t op, uint16_t a, uint16_t b, int two)
{
  code[ncode++] = op;
  code[ncode++] = (uint8_t)(a & 0xff);
  code[ncode++] = (uint8_t)((a >> 8) & 0xff);
  if (two) {
    code[ncode++] = (uint8_t)(b & 0xff);
    code[ncode++] = (uint8_t)((b >> 8) & 0xff);
  }
}

static int strip_quotes(const char *lex, char *out, size_t cap)
{
  if (lex[0] == '"') {
    snprintf(out, cap, "%.*s", (int)(strlen(lex) - 2), lex + 1);
    return 0;
  }
  snprintf(out, cap, "%s", lex);
  return 0;
}

static int take_arrow_bind(char *bind, size_t bind_cap, long line, int optional)
{
  Tok *arrow;
  Tok *b;
  arrow = peek();
  if (!arrow || strcmp(arrow->kind, "ARROW") != 0) {
    if (optional) {
      bind[0] = '\0';
      return 0;
    }
    fprintf(stderr, "error:%ld: compile needs -> ident\n", line);
    return 1;
  }
  take();
  b = take();
  if (!b || strcmp(b->kind, "IDENT") != 0) {
    fprintf(stderr, "error:%ld: compile needs -> ident\n", line);
    return 1;
  }
  snprintf(bind, bind_cap, "%s", b->lexeme);
  return 0;
}

static int compile_engine_stmt(Tok *engine_kw)
{
  Tok *sub;
  char bind[128];
  char sbuf[512];
  long line = engine_kw->line;

  sub = take();
  if (!sub) {
    fprintf(stderr, "error:%ld: compile engine needs subcommand\n", line);
    return 1;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "fetch") == 0) {
    Tok *maybe = peek();
    int fetch_parse = 0;
    Tok *url;
    if (maybe && strcmp(maybe->kind, "IDENT") == 0 &&
        strcmp(maybe->lexeme, "parse") == 0) {
      fetch_parse = 1;
      take();
    }
    url = take();
    if (!url || strcmp(url->kind, "STRING") != 0) {
      fprintf(stderr, "error:%ld: compile engine fetch needs url\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    strip_quotes(url->lexeme, sbuf, sizeof(sbuf));
    emit_op(fetch_parse ? SPBC_OP_ENGINE_FETCH_PARSE : SPBC_OP_ENGINE_FETCH,
            add_str_const(sbuf), add_str_const(bind), 1);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "parse") == 0) {
    Tok *path = take();
    if (!path || strcmp(path->kind, "STRING") != 0) {
      fprintf(stderr, "error:%ld: compile engine parse needs path\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    strip_quotes(path->lexeme, sbuf, sizeof(sbuf));
    emit_op(SPBC_OP_ENGINE_PARSE, add_str_const(sbuf),
            add_str_const(bind), 1);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 && strcmp(sub->lexeme, "css") == 0) {
    Tok *attach = take();
    if (!attach || strcmp(attach->kind, "IDENT") != 0 ||
        strcmp(attach->lexeme, "attach") != 0) {
      fprintf(stderr, "error:%ld: compile engine css needs attach\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_ENGINE_CSS, add_str_const(bind), 0, 0);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "layout") == 0) {
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_ENGINE_LAYOUT, add_str_const(bind), 0, 0);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "paint") == 0) {
    Tok *mode = take();
    if (!mode || strcmp(mode->kind, "IDENT") != 0) {
      fprintf(stderr, "error:%ld: compile engine paint needs mode\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    if (strcmp(mode->lexeme, "boxes") == 0)
      emit_op(SPBC_OP_ENGINE_PAINT_BOXES, add_str_const(bind), 0, 0);
    else if (strcmp(mode->lexeme, "fixture") == 0)
      emit_op(SPBC_OP_ENGINE_PAINT_FIXTURE, add_str_const(bind), 0, 0);
    else {
      fprintf(stderr, "error:%ld: compile engine paint: %s\n", line,
              mode->lexeme);
      return 1;
    }
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "show") == 0) {
    Tok *path = take();
    char empty[] = "";
    uint16_t pc;
    if (!path || strcmp(path->kind, "STRING") != 0) {
      fprintf(stderr, "error:%ld: compile engine show needs path\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    strip_quotes(path->lexeme, sbuf, sizeof(sbuf));
    pc = add_str_const(sbuf);
    emit_op(SPBC_OP_ENGINE_SHOW, pc, add_str_const(bind), 1);
    (void)empty;
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "render") == 0) {
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_ENGINE_RENDER, add_str_const(bind), 0, 0);
    return 0;
  }
  fprintf(stderr, "error:%ld: compile unsupported engine %s\n", line,
          sub->lexeme);
  return 1;
}

static int compile_ide_stmt(Tok *ide_kw)
{
  Tok *sub;
  char bind[128];
  char sbuf[512];
  char empty[] = "";
  long line = ide_kw->line;

  sub = take();
  if (!sub) {
    fprintf(stderr, "error:%ld: compile ide needs subcommand\n", line);
    return 1;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "open") == 0) {
    Tok *path = take();
    if (!path || strcmp(path->kind, "STRING") != 0) {
      fprintf(stderr, "error:%ld: compile ide open needs path\n", line);
      return 1;
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    strip_quotes(path->lexeme, sbuf, sizeof(sbuf));
    emit_op(SPBC_OP_IDE_OPEN, add_str_const(sbuf), add_str_const(bind), 1);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 && strcmp(sub->lexeme, "run") == 0) {
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_IDE_RUN, add_str_const(bind), 0, 0);
    return 0;
  }
  if ((strcmp(sub->kind, "IDENT") == 0 &&
       strcmp(sub->lexeme, "ask") == 0) ||
      (strcmp(sub->kind, "KEYWORD") == 0 &&
       strcmp(sub->lexeme, "ask") == 0)) {
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_IDE_ASK, add_str_const(bind), 0, 0);
    return 0;
  }
  if (strcmp(sub->kind, "IDENT") == 0 &&
      strcmp(sub->lexeme, "show") == 0) {
    Tok *path = peek();
    uint16_t pc;
    if (path && strcmp(path->kind, "STRING") == 0) {
      take();
      strip_quotes(path->lexeme, sbuf, sizeof(sbuf));
      pc = add_str_const(sbuf);
    } else {
      pc = add_str_const(empty);
    }
    if (take_arrow_bind(bind, sizeof(bind), line, 1) != 0)
      return 1;
    emit_op(SPBC_OP_IDE_SHOW, pc, add_str_const(bind), 1);
    return 0;
  }
  fprintf(stderr, "error:%ld: compile unsupported ide %s\n", line,
          sub->lexeme);
  return 1;
}

static int compile_classify(long line)
{
  Tok *t;
  char tbuf[512];
  char bbuf[128];
  uint16_t tc;
  uint16_t bc_idx;

  t = peek();
  if (t && strcmp(t->kind, "IDENT") == 0 &&
      strcmp(t->lexeme, "multi") == 0)
    take();
  t = take();
  if (!t || strcmp(t->kind, "IDENT") != 0) {
    fprintf(stderr, "error:%ld: compile classify needs schema\n", line);
    return 1;
  }
  t = take();
  if (!t || strcmp(t->kind, "PUNCT") != 0 || strcmp(t->lexeme, "{") != 0) {
    fprintf(stderr, "error:%ld: compile classify needs {labels}\n", line);
    return 1;
  }
  for (;;) {
    t = peek();
    if (!t) {
      fprintf(stderr, "error:%ld: compile classify unclosed {\n", line);
      return 1;
    }
    if (strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "}") == 0) {
      take();
      break;
    }
    if (strcmp(t->kind, "IDENT") != 0) {
      fprintf(stderr, "error:%ld: compile classify needs label\n", line);
      return 1;
    }
    take();
    t = peek();
    if (t && strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, ",") == 0)
      take();
  }
  t = take();
  if (!t || strcmp(t->kind, "IDENT") != 0 ||
      strcmp(t->lexeme, "from") != 0) {
    fprintf(stderr, "error:%ld: compile classify needs from\n", line);
    return 1;
  }
  t = take();
  if (!t) {
    fprintf(stderr, "error:%ld: compile classify needs from\n", line);
    return 1;
  }
  if (strcmp(t->kind, "STRING") == 0) {
    strip_quotes(t->lexeme, tbuf, sizeof(tbuf));
  } else if (strcmp(t->kind, "IDENT") == 0) {
    tbuf[0] = '\0';
  } else {
    fprintf(stderr, "error:%ld: compile classify needs from string\n", line);
    return 1;
  }
  t = peek();
  if (t && strcmp(t->kind, "IDENT") == 0 &&
      strcmp(t->lexeme, "min_confidence") == 0) {
    take();
    t = take();
    if (!t || strcmp(t->kind, "NUMBER") != 0) {
      fprintf(stderr,
              "error:%ld: compile classify min_confidence needs number\n",
              line);
      return 1;
    }
  }
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  tc = add_str_const(tbuf);
  bc_idx = add_str_const(bbuf);
  emit_op(SPBC_OP_CLASSIFY, tc, bc_idx, 1);
  return 0;
}

static int compile_ask(long line)
{
  Tok *prompt;
  char pbuf[512];
  char bbuf[128];
  uint16_t pc;
  uint16_t bc_idx;

  prompt = take();
  if (!prompt || strcmp(prompt->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile ask needs string\n", line);
    return 1;
  }
  strip_quotes(prompt->lexeme, pbuf, sizeof(pbuf));
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  pc = add_str_const(pbuf);
  bc_idx = add_str_const(bbuf);
  emit_op(SPBC_OP_ASK, pc, bc_idx, 1);
  return 0;
}

static int compile_embed(long line)
{
  Tok *text;
  Tok *t;
  char tbuf[512];
  char bbuf[128];

  text = take();
  if (!text || strcmp(text->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile embed needs string\n", line);
    return 1;
  }
  strip_quotes(text->lexeme, tbuf, sizeof(tbuf));
  t = peek();
  if (t && strcmp(t->kind, "IDENT") == 0 &&
      strcmp(t->lexeme, "model") == 0) {
    take();
    t = take();
    if (!t || (strcmp(t->kind, "IDENT") != 0 &&
               strcmp(t->kind, "KEYWORD") != 0)) {
      fprintf(stderr, "error:%ld: compile embed model needs alias\n",
              line);
      return 1;
    }
  }
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_EMBED, add_str_const(tbuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_retrieve(long line)
{
  Tok *text;
  Tok *t;
  char tbuf[512];
  char bbuf[128];

  text = take();
  if (!text || strcmp(text->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile retrieve needs string\n", line);
    return 1;
  }
  strip_quotes(text->lexeme, tbuf, sizeof(tbuf));
  for (;;) {
    t = peek();
    if (!t || strcmp(t->kind, "ARROW") == 0)
      break;
    if (strcmp(t->kind, "IDENT") == 0 || strcmp(t->kind, "KEYWORD") == 0 ||
        strcmp(t->kind, "STRING") == 0 || strcmp(t->kind, "NUMBER") == 0) {
      take();
      continue;
    }
    break;
  }
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_RETRIEVE, add_str_const(tbuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_listen(long line)
{
  char bbuf[128];
  Tok *t = peek();
  if (t && strcmp(t->kind, "STRING") == 0)
    take();
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_LISTEN, add_str_const(bbuf), 0, 0);
  return 0;
}

static int compile_speak(long line)
{
  char pbuf[512];
  Tok *t;
  Tok *arrow;
  Tok *path;

  pbuf[0] = '\0';
  t = peek();
  if (t && (strcmp(t->kind, "STRING") == 0 ||
            strcmp(t->kind, "IDENT") == 0)) {
    take();
    if (strcmp(t->kind, "STRING") == 0)
      strip_quotes(t->lexeme, pbuf, sizeof(pbuf));
    else
      snprintf(pbuf, sizeof(pbuf), "%s", t->lexeme);
  }
  arrow = peek();
  if (arrow && strcmp(arrow->kind, "ARROW") == 0) {
    take();
    path = take();
    if (path && strcmp(path->kind, "STRING") == 0)
      strip_quotes(path->lexeme, pbuf, sizeof(pbuf));
  }
  if (!pbuf[0])
    snprintf(pbuf, sizeof(pbuf), "spark-out.wav");
  emit_op(SPBC_OP_SPEAK, add_str_const(pbuf), 0, 0);
  (void)line;
  return 0;
}

static int compile_review_path(long line)
{
  Tok *path;
  char pbuf[512];
  char bbuf[128];

  path = take();
  if (!path || strcmp(path->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile review path needs string\n", line);
    return 1;
  }
  strip_quotes(path->lexeme, pbuf, sizeof(pbuf));
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_REVIEW_PATH, add_str_const(pbuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_review_text(long line)
{
  Tok *text;
  char tbuf[512];
  char bbuf[128];

  text = take();
  if (!text || strcmp(text->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile review text needs string\n", line);
    return 1;
  }
  strip_quotes(text->lexeme, tbuf, sizeof(tbuf));
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_REVIEW_TEXT, add_str_const(tbuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_browser_run(long line)
{
  Tok *script = peek();
  char sbuf[512];
  char bbuf[128];

  sbuf[0] = '\0';
  if (script && strcmp(script->kind, "STRING") == 0) {
    take();
    strip_quotes(script->lexeme, sbuf, sizeof(sbuf));
  }
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_BROWSER_RUN, add_str_const(sbuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_browser_goto(long line)
{
  Tok *url;
  char ubuf[512];
  char bbuf[128];

  url = take();
  if (!url || strcmp(url->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile browser goto needs url\n", line);
    return 1;
  }
  strip_quotes(url->lexeme, ubuf, sizeof(ubuf));
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 1) != 0)
    return 1;
  emit_op(SPBC_OP_BROWSER_GOTO, add_str_const(ubuf), add_str_const(bbuf), 1);
  return 0;
}

static int compile_extract(long line)
{
  Tok *t;
  char bbuf[128];
  char fbuf[512];
  int depth = 0;

  t = take();
  if (!t || strcmp(t->kind, "IDENT") != 0) {
    fprintf(stderr, "error:%ld: compile extract needs schema\n", line);
    return 1;
  }
  t = take();
  if (!t || strcmp(t->kind, "PUNCT") != 0 || strcmp(t->lexeme, "{") != 0) {
    fprintf(stderr, "error:%ld: compile extract needs {\n", line);
    return 1;
  }
  depth = 1;
  while (depth > 0) {
    t = take();
    if (!t) {
      fprintf(stderr, "error:%ld: compile extract unclosed {\n", line);
      return 1;
    }
    if (strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "{") == 0)
      depth++;
    if (strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "}") == 0)
      depth--;
  }
  t = take();
  if (!t || strcmp(t->kind, "IDENT") != 0 ||
      strcmp(t->lexeme, "from") != 0) {
    fprintf(stderr, "error:%ld: compile extract needs from\n", line);
    return 1;
  }
  t = take();
  if (!t || strcmp(t->kind, "STRING") != 0) {
    fprintf(stderr, "error:%ld: compile extract needs from string\n", line);
    return 1;
  }
  strip_quotes(t->lexeme, fbuf, sizeof(fbuf));
  (void)fbuf;
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_EXTRACT, add_str_const(bbuf), 0, 0);
  return 0;
}

static int compile_pipeline_inner(void)
{
  for (;;) {
    Tok *t = peek();
    if (!t)
      return 1;
    if (strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "}") == 0) {
      take();
      return 0;
    }
    if ((strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "|") == 0) ||
        strcmp(t->kind, "PIPE") == 0) {
      take();
      continue;
    }
    if (strcmp(t->kind, "KEYWORD") == 0 &&
        strcmp(t->lexeme, "ask") == 0) {
      take();
      if (compile_ask(t->line) != 0)
        return 1;
      continue;
    }
    fprintf(stderr, "error:%ld: compile unsupported pipeline stmt\n",
            t->line);
    return 1;
  }
}

static int compile_pipeline_block(long line)
{
  Tok *brace = take();
  if (!brace || strcmp(brace->kind, "PUNCT") != 0 ||
      strcmp(brace->lexeme, "{") != 0) {
    fprintf(stderr, "error:%ld: compile pipeline needs {\n", line);
    return 1;
  }
  emit_op0(SPBC_OP_PIPELINE);
  return compile_pipeline_inner();
}

static int compile_mitm_enable(long line)
{
  char bbuf[128];
  Tok *t;
  for (t = peek(); t && strcmp(t->kind, "ARROW") != 0; t = peek()) {
    if (strcmp(t->kind, "IDENT") == 0 &&
        strcmp(t->lexeme, "--live") == 0) {
      fprintf(stderr,
              "error:%ld: compile mitm enable --live unsupported\n",
              line);
      return 1;
    }
    take();
  }
  if (take_arrow_bind(bbuf, sizeof(bbuf), line, 0) != 0)
    return 1;
  emit_op(SPBC_OP_MITM_ENABLE, add_str_const(bbuf), 0, 0);
  return 0;
}

static int compile_voice_inner(void)
{
  for (;;) {
    Tok *t = peek();
    if (!t)
      return 1;
    if (strcmp(t->kind, "PUNCT") == 0 && strcmp(t->lexeme, "}") == 0) {
      take();
      return 0;
    }
    if (strcmp(t->kind, "KEYWORD") == 0 &&
        strcmp(t->lexeme, "listen") == 0) {
      take();
      if (compile_listen(t->line) != 0)
        return 1;
      continue;
    }
    if ((strcmp(t->kind, "KEYWORD") == 0 &&
         strcmp(t->lexeme, "speak") == 0) ||
        (strcmp(t->kind, "KEYWORD") == 0 &&
         strcmp(t->lexeme, "say") == 0)) {
      take();
      if (compile_speak(t->line) != 0)
        return 1;
      continue;
    }
    if (strcmp(t->kind, "KEYWORD") == 0 &&
        strcmp(t->lexeme, "classify") == 0) {
      take();
      if (compile_classify(t->line) != 0)
        return 1;
      continue;
    }
    if (strcmp(t->kind, "KEYWORD") == 0 &&
        strcmp(t->lexeme, "ask") == 0) {
      take();
      if (compile_ask(t->line) != 0)
        return 1;
      continue;
    }
    fprintf(stderr, "error:%ld: compile unsupported voice stmt\n", t->line);
    return 1;
  }
}

static int compile_voice_block(long line)
{
  Tok *brace = take();
  if (!brace || strcmp(brace->kind, "PUNCT") != 0 ||
      strcmp(brace->lexeme, "{") != 0) {
    fprintf(stderr, "error:%ld: compile voice needs {\n", line);
    return 1;
  }
  emit_op0(SPBC_OP_VOICE);
  return compile_voice_inner();
}

static void reset_bc(void)
{
  size_t i;
  for (i = 0; i < nstrs; i++)
    free(str_slots[i].bytes);
  memset(str_slots, 0, sizeof(str_slots));
  nstrs = 0;
  nconsts = 0;
  ncode = 0;
}

int spark_compile_file(const char *path, const char *out_bc)
{
  SparkBc bc;
  SparkBcStr out_strs[64];
  size_t i;
  int rc = 1;

  if (!path || !out_bc)
    return 1;
  reset_bc();
  if (load_tokens(path) != 0) {
    fprintf(stderr, "error: compile cannot lex %s\n", path);
    return 1;
  }
  cur = 0;
  while (peek() && strcmp(peek()->kind, "EOF") != 0) {
    Tok *kw = take();
    if (!kw)
      break;
    if (strcmp(kw->kind, "COMMENT") == 0)
      continue;
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        (strcmp(kw->lexeme, "model") == 0 ||
         strcmp(kw->lexeme, "use") == 0)) {
      Tok *alias = take();
      char abuf[128];
      if (!alias || strcmp(alias->kind, "IDENT") != 0) {
        fprintf(stderr,
                "error:%ld: compile model/use needs alias\n",
                kw->line);
        goto done;
      }
      snprintf(abuf, sizeof(abuf), "%s", alias->lexeme);
      emit_op(SPBC_OP_MODEL, add_str_const(abuf), 0, 0);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "ask") == 0) {
      Tok *prompt = take();
      Tok *arrow;
      Tok *bind;
      char pbuf[512];
      char bbuf[128];
      uint16_t pc;
      uint16_t bc;
      if (!prompt || strcmp(prompt->kind, "STRING") != 0) {
        fprintf(stderr, "error:%ld: compile ask needs string\n",
                kw->line);
        goto done;
      }
      if (prompt->lexeme[0] == '"')
        snprintf(pbuf, sizeof(pbuf), "%.*s",
                 (int)(strlen(prompt->lexeme) - 2), prompt->lexeme + 1);
      else
        snprintf(pbuf, sizeof(pbuf), "%s", prompt->lexeme);
      arrow = take();
      bind = take();
      if (!arrow || strcmp(arrow->kind, "ARROW") != 0 || !bind ||
          strcmp(bind->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile ask needs -> ident\n",
                kw->line);
        goto done;
      }
      snprintf(bbuf, sizeof(bbuf), "%s", bind->lexeme);
      pc = add_str_const(pbuf);
      bc = add_str_const(bbuf);
      emit_op(SPBC_OP_ASK, pc, bc, 1);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "print") == 0) {
      Tok *ident = take();
      char ibuf[128];
      if (!ident || strcmp(ident->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile print needs ident\n",
                kw->line);
        goto done;
      }
      snprintf(ibuf, sizeof(ibuf), "%s", ident->lexeme);
      emit_op(SPBC_OP_PRINT, add_str_const(ibuf), 0, 0);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "let") == 0) {
      Tok *name = take();
      Tok *val = take();
      char nbuf[128];
      char vbuf[512];
      uint16_t nc;
      uint16_t vc;
      if (!name || strcmp(name->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile let needs name\n", kw->line);
        goto done;
      }
      if (!val) {
        fprintf(stderr, "error:%ld: compile let needs value\n", kw->line);
        goto done;
      }
      snprintf(nbuf, sizeof(nbuf), "%s", name->lexeme);
      if (val->lexeme[0] == '"')
        snprintf(vbuf, sizeof(vbuf), "%.*s",
                 (int)(strlen(val->lexeme) - 2), val->lexeme + 1);
      else
        snprintf(vbuf, sizeof(vbuf), "%s", val->lexeme);
      nc = add_str_const(nbuf);
      vc = add_str_const(vbuf);
      emit_op(SPBC_OP_LET, nc, vc, 1);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "classify") == 0) {
      Tok *t;
      char tbuf[512];
      char bbuf[128];
      uint16_t tc;
      uint16_t bc_idx;
      t = peek();
      if (t && strcmp(t->kind, "IDENT") == 0 &&
          strcmp(t->lexeme, "multi") == 0)
        take();
      t = take();
      if (!t || strcmp(t->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs schema\n",
                kw->line);
        goto done;
      }
      t = take();
      if (!t || strcmp(t->kind, "PUNCT") != 0 ||
          strcmp(t->lexeme, "{") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs {labels}\n",
                kw->line);
        goto done;
      }
      for (;;) {
        t = peek();
        if (!t) {
          fprintf(stderr, "error:%ld: compile classify unclosed {\n",
                  kw->line);
          goto done;
        }
        if (strcmp(t->kind, "PUNCT") == 0 &&
            strcmp(t->lexeme, "}") == 0) {
          take();
          break;
        }
        if (strcmp(t->kind, "IDENT") != 0) {
          fprintf(stderr, "error:%ld: compile classify needs label\n",
                  kw->line);
          goto done;
        }
        take();
        t = peek();
        if (t && strcmp(t->kind, "PUNCT") == 0 &&
            strcmp(t->lexeme, ",") == 0)
          take();
      }
      t = take();
      if (!t || strcmp(t->kind, "IDENT") != 0 ||
          strcmp(t->lexeme, "from") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs from\n",
                kw->line);
        goto done;
      }
      t = take();
      if (!t || strcmp(t->kind, "STRING") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs from "
                "string\n", kw->line);
        goto done;
      }
      strip_quotes(t->lexeme, tbuf, sizeof(tbuf));
      t = peek();
      if (t && strcmp(t->kind, "IDENT") == 0 &&
          strcmp(t->lexeme, "min_confidence") == 0) {
        take();
        t = take();
        if (!t || strcmp(t->kind, "NUMBER") != 0) {
          fprintf(stderr,
                  "error:%ld: compile classify min_confidence "
                  "needs number\n", kw->line);
          goto done;
        }
      }
      t = take();
      if (!t || strcmp(t->kind, "ARROW") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs ->\n",
                kw->line);
        goto done;
      }
      t = take();
      if (!t || strcmp(t->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile classify needs bind\n",
                kw->line);
        goto done;
      }
      snprintf(bbuf, sizeof(bbuf), "%s", t->lexeme);
      tc = add_str_const(tbuf);
      bc_idx = add_str_const(bbuf);
      emit_op(SPBC_OP_CLASSIFY, tc, bc_idx, 1);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "embed") == 0) {
      if (compile_embed(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "retrieve") == 0) {
      if (compile_retrieve(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "extract") == 0) {
      if (compile_extract(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "pipeline") == 0) {
      if (compile_pipeline_block(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "listen") == 0) {
      if (compile_listen(kw->line) != 0)
        goto done;
      continue;
    }
    if ((strcmp(kw->kind, "KEYWORD") == 0 &&
         strcmp(kw->lexeme, "speak") == 0) ||
        (strcmp(kw->kind, "KEYWORD") == 0 &&
         strcmp(kw->lexeme, "say") == 0)) {
      if (compile_speak(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "voice") == 0) {
      if (compile_voice_block(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "review") == 0) {
      Tok *sub = take();
      if (!sub || strcmp(sub->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile review needs path|text\n",
                kw->line);
        goto done;
      }
      if (strcmp(sub->lexeme, "path") == 0) {
        if (compile_review_path(kw->line) != 0)
          goto done;
        continue;
      }
      if (strcmp(sub->lexeme, "text") == 0) {
        if (compile_review_text(kw->line) != 0)
          goto done;
        continue;
      }
      fprintf(stderr, "error:%ld: compile review url unsupported\n",
              kw->line);
      goto done;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "browser") == 0) {
      Tok *sub = take();
      if (!sub || strcmp(sub->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile browser needs subcommand\n",
                kw->line);
        goto done;
      }
      if (strcmp(sub->lexeme, "run") == 0 ||
          strcmp(sub->lexeme, "open") == 0 ||
          strcmp(sub->lexeme, "start") == 0) {
        if (compile_browser_run(kw->line) != 0)
          goto done;
        continue;
      }
      if (strcmp(sub->lexeme, "goto") == 0) {
        if (compile_browser_goto(kw->line) != 0)
          goto done;
        continue;
      }
      fprintf(stderr, "error:%ld: compile browser %s unsupported\n",
              kw->line, sub->lexeme);
      goto done;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "mitm") == 0) {
      Tok *sub = take();
      if (!sub || strcmp(sub->kind, "IDENT") != 0 ||
          strcmp(sub->lexeme, "enable") != 0) {
        fprintf(stderr, "error:%ld: compile mitm enable only\n", kw->line);
        goto done;
      }
      if (compile_mitm_enable(kw->line) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "PIPE") == 0)
      continue;
    if (strcmp(kw->kind, "PUNCT") == 0 && kw->lexeme[0] == '{')
      continue;
    if (strcmp(kw->kind, "PUNCT") == 0 && kw->lexeme[0] == '}') {
      emit_op0(SPBC_OP_WITH_END);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "tool") == 0) {
      Tok *name = take();
      Tok *t;
      int depth;
      if (!name || strcmp(name->kind, "IDENT") != 0) {
        fprintf(stderr, "error:%ld: compile tool needs a name\n",
                kw->line);
        goto done;
      }
      t = peek();
      if (t && strcmp(t->kind, "PUNCT") == 0 &&
          strcmp(t->lexeme, "(") == 0) {
        take();
        depth = 0;
        for (;;) {
          t = take();
          if (!t) {
            fprintf(stderr, "error:%ld: compile tool unclosed (\n",
                    kw->line);
            goto done;
          }
          if (strcmp(t->kind, "PUNCT") == 0 &&
              strcmp(t->lexeme, "(") == 0)
            depth++;
          else if (strcmp(t->kind, "PUNCT") == 0 &&
                   strcmp(t->lexeme, ")") == 0) {
            if (depth == 0)
              break;
            depth--;
          }
        }
      }
      t = peek();
      if (t && strcmp(t->kind, "ARROW") == 0) {
        take();
        t = take();
        if (!t || strcmp(t->kind, "IDENT") != 0) {
          fprintf(stderr,
                  "error:%ld: compile tool needs return type\n",
                  kw->line);
          goto done;
        }
      }
      t = peek();
      if (t && strcmp(t->kind, "PUNCT") == 0 &&
          strcmp(t->lexeme, "{") == 0) {
        take();
        depth = 0;
        for (;;) {
          t = take();
          if (!t) {
            fprintf(stderr, "error:%ld: compile tool unclosed {\n",
                    kw->line);
            goto done;
          }
          if (strcmp(t->kind, "PUNCT") == 0 &&
              strcmp(t->lexeme, "{") == 0)
            depth++;
          else if (strcmp(t->kind, "PUNCT") == 0 &&
                   strcmp(t->lexeme, "}") == 0) {
            if (depth == 0)
              break;
            depth--;
          }
        }
      }
      emit_op(SPBC_OP_TOOL, add_str_const(name->lexeme), 0, 0);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "with") == 0) {
      Tok *t;
      char scope[128];
      size_t slen = 0;
      t = take();
      if (!t || strcmp(t->kind, "IDENT") != 0 ||
          strcmp(t->lexeme, "tools") != 0) {
        fprintf(stderr,
                "error:%ld: compile with needs tools [name]\n",
                kw->line);
        goto done;
      }
      t = take();
      if (!t || strcmp(t->kind, "PUNCT") != 0 ||
          strcmp(t->lexeme, "[") != 0) {
        fprintf(stderr,
                "error:%ld: compile with tools needs [list]\n",
                kw->line);
        goto done;
      }
      scope[0] = '\0';
      for (;;) {
        t = peek();
        if (!t) {
          fprintf(stderr, "error:%ld: compile with unclosed [\n",
                  kw->line);
          goto done;
        }
        if (strcmp(t->kind, "PUNCT") == 0 &&
            strcmp(t->lexeme, "]") == 0) {
          take();
          break;
        }
        if (strcmp(t->kind, "PUNCT") == 0 &&
            strcmp(t->lexeme, ",") == 0) {
          take();
          continue;
        }
        if (strcmp(t->kind, "IDENT") != 0) {
          fprintf(stderr,
                  "error:%ld: compile with needs tool name\n",
                  kw->line);
          goto done;
        }
        take();
        if (slen > 0) {
          fprintf(stderr,
                  "error:%ld: compile with encodes one name\n",
                  kw->line);
          goto done;
        }
        snprintf(scope, sizeof(scope), "%s", t->lexeme);
        slen = strlen(scope);
      }
      if (!slen) {
        fprintf(stderr,
                "error:%ld: compile with tools needs [list]\n",
                kw->line);
        goto done;
      }
      t = peek();
      if (t && strcmp(t->kind, "PUNCT") == 0 &&
          strcmp(t->lexeme, "{") == 0)
        take();
      emit_op(SPBC_OP_WITH, add_str_const(scope), 0, 0);
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "engine") == 0) {
      if (compile_engine_stmt(kw) != 0)
        goto done;
      continue;
    }
    if (strcmp(kw->kind, "KEYWORD") == 0 &&
        strcmp(kw->lexeme, "ide") == 0) {
      if (compile_ide_stmt(kw) != 0)
        goto done;
      continue;
    }
    fprintf(stderr,
            "error:%ld: compile unsupported statement '%s'"
            " (hello/mini/let/classify/tool/with/extract/pipeline/"
            "voice/review/browser/mitm/engine/ide subset only)\n",
            kw->line, kw->lexeme);
    goto done;
  }
  code[ncode++] = SPBC_OP_HALT;

  memset(&bc, 0, sizeof(bc));
  bc.nstrs = nstrs;
  bc.nconsts = nconsts;
  bc.ncode = ncode;
  for (i = 0; i < nstrs; i++) {
    out_strs[i].bytes = (uint8_t *)str_slots[i].bytes;
    out_strs[i].len = str_slots[i].len;
  }
  bc.strs = out_strs;
  bc.consts = consts;
  bc.code = code;

  if (spark_bc_write(out_bc, &bc) != 0) {
    fprintf(stderr, "error: compile cannot write %s\n", out_bc);
    goto done;
  }
  rc = 0;

done:
  reset_bc();
  return rc;
}

int spark_bc_compile_and_run(const char *path, int *compiled)
{
  char tmpl[] = "/tmp/spark-bc-run-XXXXXX";
  int fd;
  int rc;

  if (compiled)
    *compiled = 0;
  fd = mkstemp(tmpl);
  if (fd < 0) {
    perror("mkstemp");
    return 1;
  }
  close(fd);
  if (spark_compile_file(path, tmpl) != 0) {
    unlink(tmpl);
    return 1;
  }
  if (compiled)
    *compiled = 1;
  rc = spark_bc_run_file(tmpl);
  unlink(tmpl);
  return rc;
}
