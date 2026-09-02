/* C port of asm/engine_html.s + minimal script numbers/+ hook.
 * Match GAS dry: dom.json spine, tag set, stack tokenizer. */
#include "engine_parse.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define HTML_CAP 65536
#define MAX_NODES 256
#define DATA_LEN 40
#define STACK_MAX 64

#define KIND_ELEM 1
#define KIND_TEXT 2

#define TAG_UNK 0
#define TAG_HTML 1
#define TAG_HEAD 2
#define TAG_BODY 3
#define TAG_TITLE 4
#define TAG_P 5
#define TAG_H1 6
#define TAG_H2 7
#define TAG_H3 8
#define TAG_A 9
#define TAG_DIV 10
#define TAG_SPAN 11
#define TAG_IMG 12
#define TAG_UL 13
#define TAG_LI 14
#define TAG_SCRIPT 15
#define TAG_STYLE 16
#define TAG_BR 17
#define TAG_TABLE 18
#define TAG_TR 19
#define TAG_TD 20
#define TAG_TH 21

typedef struct {
  unsigned char kind;
  unsigned char tag;
  unsigned char voidf;
  int parent;
  int fc;
  int lc;
  int ns;
  char data[DATA_LEN];
} EpNode;

static char html_buf[HTML_CAP];
static size_t html_len;
static size_t parse_pos;
static EpNode nodes[MAX_NODES];
static size_t nnodes;
static size_t nelements;
static size_t ntexts;
static int tag_stack[STACK_MAX];
static size_t stack_sp;
static long root_id;
static long body_id;
static long cnt_html, cnt_p, cnt_h1, cnt_h2, cnt_h3, cnt_a;
static long cnt_div, cnt_span, cnt_ul, cnt_li, cnt_img;
static long cnt_table, cnt_tr, cnt_td, cnt_th;

static char out_buf[EP_JSON_CAP];
static size_t out_len;

static int ensure_dom_dirs(void)
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

static int load_html(const char *path)
{
  FILE *f;
  size_t n;
  f = fopen(path, "rb");
  if (!f)
    return -1;
  n = fread(html_buf, 1, HTML_CAP - 1, f);
  if (ferror(f)) {
    fclose(f);
    return -1;
  }
  fclose(f);
  html_buf[n] = '\0';
  html_len = n;
  return 0;
}

static int tag_id_from_name(const char *name)
{
  if (strcmp(name, "html") == 0)
    return TAG_HTML;
  if (strcmp(name, "head") == 0)
    return TAG_HEAD;
  if (strcmp(name, "body") == 0)
    return TAG_BODY;
  if (strcmp(name, "title") == 0)
    return TAG_TITLE;
  if (strcmp(name, "p") == 0)
    return TAG_P;
  if (strcmp(name, "h1") == 0)
    return TAG_H1;
  if (strcmp(name, "h2") == 0)
    return TAG_H2;
  if (strcmp(name, "h3") == 0)
    return TAG_H3;
  if (strcmp(name, "a") == 0)
    return TAG_A;
  if (strcmp(name, "div") == 0)
    return TAG_DIV;
  if (strcmp(name, "span") == 0)
    return TAG_SPAN;
  if (strcmp(name, "img") == 0)
    return TAG_IMG;
  if (strcmp(name, "ul") == 0)
    return TAG_UL;
  if (strcmp(name, "li") == 0)
    return TAG_LI;
  if (strcmp(name, "script") == 0)
    return TAG_SCRIPT;
  if (strcmp(name, "style") == 0)
    return TAG_STYLE;
  if (strcmp(name, "br") == 0)
    return TAG_BR;
  if (strcmp(name, "table") == 0)
    return TAG_TABLE;
  if (strcmp(name, "tr") == 0)
    return TAG_TR;
  if (strcmp(name, "td") == 0)
    return TAG_TD;
  if (strcmp(name, "th") == 0)
    return TAG_TH;
  return TAG_UNK;
}

static const char *tag_name_str(int tag)
{
  switch (tag) {
  case TAG_HTML:
    return "html";
  case TAG_HEAD:
    return "head";
  case TAG_BODY:
    return "body";
  case TAG_TITLE:
    return "title";
  case TAG_P:
    return "p";
  case TAG_H1:
    return "h1";
  case TAG_H2:
    return "h2";
  case TAG_H3:
    return "h3";
  case TAG_A:
    return "a";
  case TAG_DIV:
    return "div";
  case TAG_SPAN:
    return "span";
  case TAG_IMG:
    return "img";
  case TAG_UL:
    return "ul";
  case TAG_LI:
    return "li";
  case TAG_SCRIPT:
    return "script";
  case TAG_STYLE:
    return "style";
  case TAG_BR:
    return "br";
  case TAG_TABLE:
    return "table";
  case TAG_TR:
    return "tr";
  case TAG_TD:
    return "td";
  case TAG_TH:
    return "th";
  default:
    return "unknown";
  }
}

static void bump_tag_count(int tag)
{
  switch (tag) {
  case TAG_HTML:
    cnt_html++;
    break;
  case TAG_P:
    cnt_p++;
    break;
  case TAG_H1:
    cnt_h1++;
    break;
  case TAG_H2:
    cnt_h2++;
    break;
  case TAG_H3:
    cnt_h3++;
    break;
  case TAG_A:
    cnt_a++;
    break;
  case TAG_DIV:
    cnt_div++;
    break;
  case TAG_SPAN:
    cnt_span++;
    break;
  case TAG_UL:
    cnt_ul++;
    break;
  case TAG_LI:
    cnt_li++;
    break;
  case TAG_IMG:
    cnt_img++;
    break;
  case TAG_TABLE:
    cnt_table++;
    break;
  case TAG_TR:
    cnt_tr++;
    break;
  case TAG_TD:
    cnt_td++;
    break;
  case TAG_TH:
    cnt_th++;
    break;
  default:
    break;
  }
}

static int alloc_element(int tag, int voidf)
{
  EpNode *n;
  int id;
  if (nnodes >= MAX_NODES)
    return -1;
  id = (int)nnodes++;
  nelements++;
  n = &nodes[id];
  memset(n, 0, sizeof(*n));
  n->kind = KIND_ELEM;
  n->tag = (unsigned char)tag;
  n->voidf = (unsigned char)voidf;
  n->parent = -1;
  n->fc = -1;
  n->lc = -1;
  n->ns = -1;
  strncpy(n->data, tag_name_str(tag), DATA_LEN - 1);
  return id;
}

static int alloc_text(size_t start, size_t len)
{
  EpNode *n;
  int id;
  size_t copy;
  if (nnodes >= MAX_NODES)
    return -1;
  id = (int)nnodes++;
  ntexts++;
  n = &nodes[id];
  memset(n, 0, sizeof(*n));
  n->kind = KIND_TEXT;
  n->parent = -1;
  n->fc = -1;
  n->lc = -1;
  n->ns = -1;
  copy = len;
  if (copy > DATA_LEN - 1)
    copy = DATA_LEN - 1;
  memcpy(n->data, html_buf + start, copy);
  n->data[copy] = '\0';
  return id;
}

static void link_child(int parent, int child)
{
  EpNode *p = &nodes[parent];
  EpNode *c = &nodes[child];
  c->parent = parent;
  if (p->fc < 0) {
    p->fc = child;
    p->lc = child;
  } else {
    nodes[p->lc].ns = child;
    p->lc = child;
  }
}

static int stack_top(void)
{
  if (stack_sp == 0)
    return -1;
  return tag_stack[stack_sp - 1];
}

static void stack_push(int id)
{
  if (stack_sp < STACK_MAX)
    tag_stack[stack_sp++] = id;
}

static void stack_pop(void)
{
  if (stack_sp > 0)
    stack_sp--;
}

static void pop_until_tag(int tag)
{
  while (stack_sp > 0) {
    int id = tag_stack[stack_sp - 1];
    stack_sp--;
    if (nodes[id].tag == (unsigned char)tag)
      break;
  }
}

static int text_is_ws(size_t start, size_t len)
{
  size_t i;
  for (i = 0; i < len; i++) {
    char c = html_buf[start + i];
    if (c != ' ' && c != '\t' && c != '\n' && c != '\r')
      return 0;
  }
  return 1;
}

static int read_tag_name(void)
{
  char tmp[64];
  size_t i = 0;
  while (parse_pos < html_len) {
    char c = html_buf[parse_pos];
    if (c == ' ' || c == '\t' || c == '>' || c == '/' || c == '\0')
      break;
    if (c >= 'A' && c <= 'Z')
      c = (char)(c + 32);
    if (i + 1 < sizeof(tmp))
      tmp[i++] = c;
    parse_pos++;
  }
  tmp[i] = '\0';
  return tag_id_from_name(tmp);
}

static void skip_to_gt(void)
{
  while (parse_pos < html_len && html_buf[parse_pos] != '>')
    parse_pos++;
  if (parse_pos < html_len)
    parse_pos++;
}

static int skip_attrs_to_gt(void)
{
  int slash = 0;
  while (parse_pos < html_len) {
    char c = html_buf[parse_pos];
    if (c == '"') {
      parse_pos++;
      while (parse_pos < html_len && html_buf[parse_pos] != '"')
        parse_pos++;
      if (parse_pos < html_len)
        parse_pos++;
      continue;
    }
    if (c == '\'') {
      parse_pos++;
      while (parse_pos < html_len && html_buf[parse_pos] != '\'')
        parse_pos++;
      if (parse_pos < html_len)
        parse_pos++;
      continue;
    }
    if (c == '/') {
      slash = 1;
      parse_pos++;
      continue;
    }
    if (c == '>') {
      parse_pos++;
      break;
    }
    parse_pos++;
  }
  return slash;
}

static void skip_comment_or_doctype(void)
{
  /* parse_pos at '!' */
  parse_pos++;
  if (parse_pos + 1 < html_len && html_buf[parse_pos] == '-' &&
      html_buf[parse_pos + 1] == '-') {
    parse_pos += 2;
    while (parse_pos + 2 < html_len) {
      if (html_buf[parse_pos] == '-' && html_buf[parse_pos + 1] == '-' &&
          html_buf[parse_pos + 2] == '>') {
        parse_pos += 3;
        return;
      }
      parse_pos++;
    }
    parse_pos = html_len;
    return;
  }
  while (parse_pos < html_len && html_buf[parse_pos] != '>')
    parse_pos++;
  if (parse_pos < html_len)
    parse_pos++;
}

static void consume_raw_until_close(int tag)
{
  size_t text_start = parse_pos;
  while (parse_pos < html_len) {
    size_t at;
    int close_tag;
    if (html_buf[parse_pos] != '<') {
      parse_pos++;
      continue;
    }
    at = parse_pos;
    if (parse_pos + 1 >= html_len)
      break;
    if (html_buf[parse_pos + 1] != '/') {
      parse_pos++;
      continue;
    }
    parse_pos = at + 2;
    close_tag = read_tag_name();
    if (close_tag == tag) {
      size_t tlen = at - text_start;
      if (tlen > 0) {
        int tid = alloc_text(text_start, tlen);
        int parent = stack_top();
        if (tid >= 0 && parent >= 0)
          link_child(parent, tid);
      }
      skip_to_gt();
      return;
    }
    parse_pos = at + 1;
  }
}

static void parse_text_run(void)
{
  size_t start = parse_pos;
  size_t len;
  int tid;
  int parent;
  while (parse_pos < html_len && html_buf[parse_pos] != '<')
    parse_pos++;
  len = parse_pos - start;
  if (len == 0 || text_is_ws(start, len))
    return;
  if (stack_sp == 0)
    return;
  tid = alloc_text(start, len);
  parent = stack_top();
  if (tid >= 0 && parent >= 0)
    link_child(parent, tid);
}

static int parse_html(void)
{
  nnodes = 0;
  nelements = 0;
  ntexts = 0;
  stack_sp = 0;
  root_id = -1;
  body_id = -1;
  parse_pos = 0;
  cnt_html = cnt_p = cnt_h1 = cnt_h2 = cnt_h3 = cnt_a = 0;
  cnt_div = cnt_span = cnt_ul = cnt_li = cnt_img = 0;
  cnt_table = cnt_tr = cnt_td = cnt_th = 0;

  while (parse_pos < html_len) {
    int tag;
    int voidf;
    int id;
    if (html_buf[parse_pos] != '<') {
      parse_text_run();
      continue;
    }
    parse_pos++;
    if (parse_pos >= html_len)
      break;
    if (html_buf[parse_pos] == '!') {
      skip_comment_or_doctype();
      continue;
    }
    if (html_buf[parse_pos] == '/') {
      parse_pos++;
      tag = read_tag_name();
      skip_to_gt();
      pop_until_tag(tag);
      continue;
    }
    tag = read_tag_name();
    voidf = skip_attrs_to_gt();
    if (tag == TAG_IMG || tag == TAG_BR)
      voidf = 1;
    id = alloc_element(tag, voidf);
    if (id < 0) {
      fprintf(stderr, "error: engine DOM node pool full\n");
      return 1;
    }
    if (root_id < 0)
      root_id = id;
    if (tag == TAG_BODY)
      body_id = id;
    bump_tag_count(tag);
    if (stack_sp > 0)
      link_child(stack_top(), id);
    if (!voidf) {
      stack_push(id);
      if (tag == TAG_SCRIPT || tag == TAG_STYLE) {
        consume_raw_until_close(tag);
        stack_pop();
      }
    }
  }
  return 0;
}

static void out_reset(void)
{
  out_len = 0;
  out_buf[0] = '\0';
}

static int out_append(const char *s, size_t n)
{
  if (out_len + n + 1 >= EP_JSON_CAP)
    return -1;
  memcpy(out_buf + out_len, s, n);
  out_len += n;
  out_buf[out_len] = '\0';
  return 0;
}

static int out_cstr(const char *s)
{
  return out_append(s, strlen(s));
}

static int out_byte(char c)
{
  return out_append(&c, 1);
}

static int out_i64(long v)
{
  char tmp[32];
  int n = snprintf(tmp, sizeof(tmp), "%ld", v);
  if (n < 0)
    return -1;
  return out_append(tmp, (size_t)n);
}

static int out_escape(const char *s)
{
  while (*s) {
    if (*s == '"' || *s == '\\') {
      if (out_byte('\\') != 0 || out_byte(*s) != 0)
        return -1;
    } else if (*s == '\n') {
      if (out_cstr("\\n") != 0)
        return -1;
    } else if (*s == '\r') {
      if (out_cstr("\\r") != 0)
        return -1;
    } else if (out_byte(*s) != 0) {
      return -1;
    }
    s++;
  }
  return 0;
}

static int emit_node(int id)
{
  EpNode *n = &nodes[id];
  if (out_byte('{') != 0)
    return -1;
  if (out_cstr("\"id\":") != 0 || out_i64(id) != 0)
    return -1;
  if (out_cstr(",\"k\":") != 0)
    return -1;
  if (n->kind == KIND_TEXT) {
    if (out_cstr("\"t\"") != 0)
      return -1;
    if (out_cstr(",\"text\":\"") != 0)
      return -1;
    if (out_escape(n->data) != 0)
      return -1;
  } else {
    if (out_cstr("\"e\"") != 0)
      return -1;
    if (out_cstr(",\"tag\":\"") != 0)
      return -1;
    if (out_cstr(n->data) != 0)
      return -1;
  }
  /* GAS em_p = "\",\"p\":" closes tag/text quote */
  if (out_cstr("\",\"p\":") != 0)
    return -1;
  if (out_i64(n->parent) != 0)
    return -1;
  if (out_cstr(",\"fc\":") != 0 || out_i64(n->fc) != 0)
    return -1;
  if (out_cstr(",\"ns\":") != 0 || out_i64(n->ns) != 0)
    return -1;
  if (out_byte('}') != 0)
    return -1;
  return 0;
}

static int write_dom_json(void)
{
  size_t i;
  FILE *f;
  out_reset();
  if (out_cstr("{\"op\":\"engine.parse\",\"ok\":true,"
               "\"engine\":\"spark-asm-html\","
               "\"nnodes\":") != 0)
    return -1;
  if (out_i64((long)nnodes) != 0)
    return -1;
  if (out_cstr(",\"nelements\":") != 0 ||
      out_i64((long)nelements) != 0)
    return -1;
  if (out_cstr(",\"ntexts\":") != 0 || out_i64((long)ntexts) != 0)
    return -1;
  if (out_cstr(",\"root\":") != 0 || out_i64(root_id) != 0)
    return -1;
  if (out_cstr(",\"body\":") != 0 || out_i64(body_id) != 0)
    return -1;
  if (out_cstr(",\"tag_counts\":{\"html\":") != 0 ||
      out_i64(cnt_html) != 0)
    return -1;
  if (out_cstr(",\"p\":") != 0 || out_i64(cnt_p) != 0)
    return -1;
  if (out_cstr(",\"h1\":") != 0 || out_i64(cnt_h1) != 0)
    return -1;
  if (out_cstr(",\"h2\":") != 0 || out_i64(cnt_h2) != 0)
    return -1;
  if (out_cstr(",\"h3\":") != 0 || out_i64(cnt_h3) != 0)
    return -1;
  if (out_cstr(",\"a\":") != 0 || out_i64(cnt_a) != 0)
    return -1;
  if (out_cstr(",\"div\":") != 0 || out_i64(cnt_div) != 0)
    return -1;
  if (out_cstr(",\"span\":") != 0 || out_i64(cnt_span) != 0)
    return -1;
  if (out_cstr(",\"ul\":") != 0 || out_i64(cnt_ul) != 0)
    return -1;
  if (out_cstr(",\"li\":") != 0 || out_i64(cnt_li) != 0)
    return -1;
  if (out_cstr(",\"img\":") != 0 || out_i64(cnt_img) != 0)
    return -1;
  if (out_cstr(",\"table\":") != 0 || out_i64(cnt_table) != 0)
    return -1;
  if (out_cstr(",\"tr\":") != 0 || out_i64(cnt_tr) != 0)
    return -1;
  if (out_cstr(",\"td\":") != 0 || out_i64(cnt_td) != 0)
    return -1;
  if (out_cstr(",\"th\":") != 0 || out_i64(cnt_th) != 0)
    return -1;
  if (out_cstr("},\"nodes\":[") != 0)
    return -1;
  for (i = 0; i < nnodes; i++) {
    if (i > 0 && out_byte(',') != 0)
      return -1;
    if (emit_node((int)i) != 0)
      return -1;
  }
  if (out_cstr("]}") != 0)
    return -1;
  f = fopen("out/browser/engine/dom.json", "wb");
  if (!f)
    return -1;
  if (fwrite(out_buf, 1, out_len, f) != out_len) {
    fclose(f);
    return -1;
  }
  fclose(f);
  return 0;
}

/* Phase-1 numbers/+ only (enough for hello.html script 1+1). */
static int eval_nums_plus(const char *src, long *out)
{
  const char *p = src;
  long acc = 0;
  int have = 0;
  while (*p) {
    long v = 0;
    int digits = 0;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
      p++;
    if (!*p)
      break;
    if (*p == '+') {
      if (!have)
        return -1;
      p++;
      while (*p == ' ' || *p == '\t')
        p++;
    } else if (have) {
      return -1;
    }
    if (!isdigit((unsigned char)*p))
      return -1;
    while (isdigit((unsigned char)*p)) {
      v = v * 10 + (*p - '0');
      p++;
      digits = 1;
    }
    if (!digits)
      return -1;
    if (!have) {
      acc = v;
      have = 1;
    } else {
      acc += v;
    }
  }
  if (!have)
    return -1;
  *out = acc;
  return 0;
}

static int run_dom_scripts(void)
{
  size_t i;
  int ran = 0;
  long last = 0;
  FILE *f;
  for (i = 0; i < nnodes; i++) {
    int ch;
    if (nodes[i].kind != KIND_ELEM || nodes[i].tag != TAG_SCRIPT)
      continue;
    for (ch = nodes[i].fc; ch >= 0; ch = nodes[ch].ns) {
      long v;
      if (nodes[ch].kind != KIND_TEXT)
        continue;
      if (nodes[ch].data[0] == '\0')
        continue;
      if (eval_nums_plus(nodes[ch].data, &v) != 0) {
        fprintf(stderr,
                "error: engine parse: <script> phase-1 "
                "eval failed (want number|string|+|"
                "console.log; not full ES)\n");
        return 1;
      }
      last = v;
      ran = 1;
    }
  }
  if (!ran)
    return 0;
  f = fopen("out/engine/js_result.txt", "wb");
  if (!f)
    return 1;
  fprintf(f, "%ld", last);
  fclose(f);
  return 0;
}

size_t spark_bootstrap_dom_nnodes(void)
{
  return nnodes;
}

int spark_bootstrap_dom_root(void)
{
  return (int)root_id;
}

const char *spark_bootstrap_dom_html(void)
{
  return html_buf;
}

unsigned char spark_bootstrap_dom_kind(size_t id)
{
  if (id >= nnodes)
    return 0;
  return nodes[id].kind;
}

unsigned char spark_bootstrap_dom_tag_id(size_t id)
{
  if (id >= nnodes)
    return 0;
  return nodes[id].tag;
}

const char *spark_bootstrap_dom_tag(size_t id)
{
  if (id >= nnodes)
    return "";
  if (nodes[id].kind != KIND_ELEM)
    return "";
  return nodes[id].data;
}

const char *spark_bootstrap_dom_data(size_t id)
{
  if (id >= nnodes)
    return "";
  return nodes[id].data;
}

int spark_bootstrap_dom_parent(size_t id)
{
  if (id >= nnodes)
    return -1;
  return nodes[id].parent;
}

int spark_bootstrap_dom_first(size_t id)
{
  if (id >= nnodes)
    return -1;
  return nodes[id].fc;
}

int spark_bootstrap_dom_last(size_t id)
{
  if (id >= nnodes)
    return -1;
  return nodes[id].lc;
}

int spark_bootstrap_dom_next(size_t id)
{
  if (id >= nnodes)
    return -1;
  return nodes[id].ns;
}

void spark_bootstrap_dom_reset(void)
{
  html_len = 0;
  html_buf[0] = '\0';
  parse_pos = 0;
  nnodes = 0;
  nelements = 0;
  ntexts = 0;
  stack_sp = 0;
  root_id = -1;
  body_id = -1;
  cnt_html = cnt_p = cnt_h1 = cnt_h2 = cnt_h3 = cnt_a = 0;
  cnt_div = cnt_span = cnt_ul = cnt_li = cnt_img = 0;
  cnt_table = cnt_tr = cnt_td = cnt_th = 0;
  out_len = 0;
  out_buf[0] = '\0';
}

int spark_bootstrap_engine_parse(const char *path, char *json_out,
                                 size_t json_cap)
{
  if (ensure_dom_dirs() != 0) {
    fprintf(stderr, "error: engine parse cannot create out dirs\n");
    return 1;
  }
  if (load_html(path) != 0) {
    fprintf(stderr, "error: engine parse cannot open HTML path\n");
    return 1;
  }
  if (parse_html() != 0)
    return 1;
  if (run_dom_scripts() != 0)
    return 1;
  if (write_dom_json() != 0) {
    fprintf(stderr, "error: engine parse cannot write dom.json\n");
    return 1;
  }
  if (!json_out || json_cap == 0)
    return 0;
  if (out_len + 1 > json_cap) {
    fprintf(stderr, "error: engine parse json overflow\n");
    return 1;
  }
  memcpy(json_out, out_buf, out_len + 1);
  return 0;
}
