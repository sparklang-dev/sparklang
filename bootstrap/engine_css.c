/* C port of asm/engine_css.s + engine_style.inc.
 * Match GAS dry: css.json spine for style_basic.html. */
#include "engine_css.h"
#include "engine_parse.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Match asm/engine_style.inc SeComputedStyle (72B). */
#define SE_STYLE_SIZE 72
#define SE_STYLE_MAX 256
#define SE_RULE_MAX 32
#define SE_TAG_MAX 20

#define SE_DISP_NONE 0
#define SE_DISP_BLOCK 1
#define SE_DISP_INLINE 2
#define SE_DISP_INLINE_BLOCK 3
#define SE_DISP_TABLE 4
#define SE_DISP_TABLE_ROW 5
#define SE_DISP_TABLE_CELL 6

#define SE_BORDER_NONE 0
#define SE_BORDER_SOLID 1

#define SE_VIS_VISIBLE 0
#define SE_VIS_HIDDEN 1

#define SE_FLAG_COLOR 1
#define SE_FLAG_FONT 2
#define SE_FLAG_MARGIN 4
#define SE_FLAG_DISPLAY 8
#define SE_FLAG_PADDING 16
#define SE_FLAG_BORDER_W 32
#define SE_FLAG_BG 64
#define SE_FLAG_WIDTH 128
#define SE_FLAG_HEIGHT 256
#define SE_FLAG_MAX_HEIGHT 512
#define SE_FLAG_MIN_HEIGHT 1024
#define SE_FLAG_MAX_WIDTH 2048
#define SE_FLAG_MIN_WIDTH 4096
#define SE_FLAG_BORDER_C 8192
#define SE_FLAG_BORDER_S 16384
#define SE_FLAG_VIS 32768
#define SE_FLAG_OPACITY 65536
#define SE_BG_TRANSPARENT 0xFFFFFFFFu

typedef struct {
  int display;
  unsigned int color_rgb;
  int font_size_px;
  int margin_px;
  int flags;
  int padding_px;
  int border_w_px;
  unsigned int bg_rgb;
  int width_px;
  int height_px;
  int max_height_px;
  int min_height_px;
  int max_width_px;
  int min_width_px;
  unsigned int border_rgb;
  int border_style;
  int visibility;
  int opacity;
} SeStyle;

_Static_assert(sizeof(SeStyle) == SE_STYLE_SIZE,
               "SeStyle must match SE_STYLE_SIZE");

typedef struct {
  char tag[SE_TAG_MAX];
  SeStyle style;
} SeRule;

static SeStyle se_style_pool[SE_STYLE_MAX];
static size_t se_style_count;
static SeRule se_rules[SE_RULE_MAX];
static size_t se_rule_count;
static char tmp_tag[SE_TAG_MAX];
static char tmp_decls[512];
static size_t scan_pos;
static char out_buf[EC_JSON_CAP];

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

static void se_css_reset(void)
{
  memset(se_style_pool, 0, sizeof(se_style_pool));
  memset(se_rules, 0, sizeof(se_rules));
  se_style_count = 0;
  se_rule_count = 0;
}

static int tag_eq(const char *a, const char *b)
{
  while (*a || *b) {
    unsigned char ca = (unsigned char)*a;
    unsigned char cb = (unsigned char)*b;
    if (ca >= 'A' && ca <= 'Z')
      ca = (unsigned char)(ca + 32);
    if (cb >= 'A' && cb <= 'Z')
      cb = (unsigned char)(cb + 32);
    if (ca != cb)
      return 0;
    if (!ca)
      return 1;
    a++;
    b++;
  }
  return 1;
}

static const char *skip_ws(const char *p)
{
  while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
    p++;
  return p;
}

static const char *find_ci(const char *hay, const char *needle)
{
  size_t nlen = strlen(needle);
  if (nlen == 0)
    return hay;
  for (; *hay; hay++) {
    size_t i;
    for (i = 0; i < nlen; i++) {
      unsigned char a = (unsigned char)hay[i];
      unsigned char b = (unsigned char)needle[i];
      if (!a)
        return NULL;
      if (a >= 'A' && a <= 'Z')
        a = (unsigned char)(a + 32);
      if (b >= 'A' && b <= 'Z')
        b = (unsigned char)(b + 32);
      if (a != b)
        break;
    }
    if (i == nlen)
      return hay;
  }
  return NULL;
}

static unsigned hex_nibble(char c)
{
  if (c >= '0' && c <= '9')
    return (unsigned)(c - '0');
  if (c >= 'a' && c <= 'f')
    return (unsigned)(c - 'a' + 10);
  if (c >= 'A' && c <= 'F')
    return (unsigned)(c - 'A' + 10);
  return 0;
}

static unsigned parse_hex_rgb(const char *s)
{
  size_t n = strlen(s);
  unsigned r, g, b;
  if (n == 3) {
    r = hex_nibble(s[0]);
    r = (r << 4) | r;
    g = hex_nibble(s[1]);
    g = (g << 4) | g;
    b = hex_nibble(s[2]);
    b = (b << 4) | b;
    return (r << 16) | (g << 8) | b;
  }
  if (n == 6) {
    r = (hex_nibble(s[0]) << 4) | hex_nibble(s[1]);
    g = (hex_nibble(s[2]) << 4) | hex_nibble(s[3]);
    b = (hex_nibble(s[4]) << 4) | hex_nibble(s[5]);
    return (r << 16) | (g << 8) | b;
  }
  return 0;
}

static unsigned parse_color(const char *s)
{
  s = skip_ws(s);
  if (*s == '#')
    return parse_hex_rgb(s + 1);
  if (tag_eq(s, "transparent"))
    return SE_BG_TRANSPARENT;
  if (tag_eq(s, "red"))
    return 0x00FF0000;
  if (tag_eq(s, "green"))
    return 0x00008000;
  if (tag_eq(s, "blue"))
    return 0x000000FF;
  if (tag_eq(s, "black"))
    return 0;
  if (tag_eq(s, "white"))
    return 0x00FFFFFF;
  if (tag_eq(s, "yellow"))
    return 0x00FFFF00;
  if (tag_eq(s, "cyan"))
    return 0x0000FFFF;
  if (tag_eq(s, "magenta"))
    return 0x00FF00FF;
  /* asm/engine_css.s n_orange / n_lime — style_basic.html */
  if (tag_eq(s, "orange"))
    return 0x00FFA500;
  if (tag_eq(s, "lime"))
    return 0x0000FF00;
  if (tag_eq(s, "gray") || tag_eq(s, "grey"))
    return 0x00808080;
  return 0;
}

static int parse_px(const char *s)
{
  int v = 0;
  s = skip_ws(s);
  while (*s >= '0' && *s <= '9') {
    v = v * 10 + (*s - '0');
    s++;
  }
  return v;
}

static int parse_display(const char *s)
{
  s = skip_ws(s);
  if (tag_eq(s, "none"))
    return SE_DISP_NONE;
  if (tag_eq(s, "block"))
    return SE_DISP_BLOCK;
  if (tag_eq(s, "inline-block"))
    return SE_DISP_INLINE_BLOCK;
  if (tag_eq(s, "inline"))
    return SE_DISP_INLINE;
  if (tag_eq(s, "table-row"))
    return SE_DISP_TABLE_ROW;
  if (tag_eq(s, "table-cell"))
    return SE_DISP_TABLE_CELL;
  if (tag_eq(s, "table"))
    return SE_DISP_TABLE;
  return SE_DISP_INLINE;
}

/* Match asm css_parse_border_style: solid → 1, else none. */
static int parse_border_style(const char *s)
{
  s = skip_ws(s);
  if (tag_eq(s, "solid"))
    return SE_BORDER_SOLID;
  return SE_BORDER_NONE;
}

/* Match asm css_parse_visibility: hidden → 1, else visible. */
static int parse_visibility(const char *s)
{
  s = skip_ws(s);
  if (tag_eq(s, "hidden"))
    return SE_VIS_HIDDEN;
  return SE_VIS_VISIBLE;
}

/* Match asm css_parse_opacity: leading '0' → 0; else 1. */
static int parse_opacity(const char *s)
{
  s = skip_ws(s);
  if (*s == '0')
    return 0;
  return 1;
}

static void rtrim_tmp_decls(void)
{
  size_t n = strlen(tmp_decls);
  while (n > 0 &&
         (tmp_decls[n - 1] == ' ' || tmp_decls[n - 1] == '\t')) {
    tmp_decls[n - 1] = '\0';
    n--;
  }
}

static void se_css_parse_decls(const char *decls, SeStyle *st)
{
  const char *p = decls;
  while (*p) {
    size_t ti = 0;
    size_t vi = 0;
    p = skip_ws(p);
    if (!*p)
      break;
    while (*p && *p != ':' && *p != ';') {
      char c = *p;
      if (ti < SE_TAG_MAX - 1) {
        if (c >= 'A' && c <= 'Z')
          c = (char)(c + 32);
        tmp_tag[ti++] = c;
      }
      p++;
    }
    tmp_tag[ti] = '\0';
    if (*p == ';') {
      p++;
      continue;
    }
    if (*p != ':')
      break;
    p++;
    p = skip_ws(p);
    while (*p && *p != ';') {
      if (vi < 510)
        tmp_decls[vi++] = *p;
      p++;
    }
    tmp_decls[vi] = '\0';
    rtrim_tmp_decls();
    if (tag_eq(tmp_tag, "color")) {
      st->color_rgb = parse_color(tmp_decls);
      st->flags |= SE_FLAG_COLOR;
    } else if (tag_eq(tmp_tag, "background-color")) {
      st->bg_rgb = parse_color(tmp_decls);
      st->flags |= SE_FLAG_BG;
    } else if (tag_eq(tmp_tag, "font-size")) {
      st->font_size_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_FONT;
    } else if (tag_eq(tmp_tag, "margin")) {
      st->margin_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_MARGIN;
    } else if (tag_eq(tmp_tag, "padding")) {
      st->padding_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_PADDING;
    } else if (tag_eq(tmp_tag, "border-width")) {
      st->border_w_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_BORDER_W;
    } else if (tag_eq(tmp_tag, "width")) {
      st->width_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_WIDTH;
    } else if (tag_eq(tmp_tag, "height")) {
      st->height_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_HEIGHT;
    } else if (tag_eq(tmp_tag, "max-height")) {
      st->max_height_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_MAX_HEIGHT;
    } else if (tag_eq(tmp_tag, "min-height")) {
      st->min_height_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_MIN_HEIGHT;
    } else if (tag_eq(tmp_tag, "max-width")) {
      st->max_width_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_MAX_WIDTH;
    } else if (tag_eq(tmp_tag, "min-width")) {
      st->min_width_px = parse_px(tmp_decls);
      st->flags |= SE_FLAG_MIN_WIDTH;
    } else if (tag_eq(tmp_tag, "border-color")) {
      st->border_rgb = parse_color(tmp_decls);
      st->flags |= SE_FLAG_BORDER_C;
    } else if (tag_eq(tmp_tag, "border-style")) {
      st->border_style = parse_border_style(tmp_decls);
      st->flags |= SE_FLAG_BORDER_S;
    } else if (tag_eq(tmp_tag, "visibility")) {
      st->visibility = parse_visibility(tmp_decls);
      st->flags |= SE_FLAG_VIS;
    } else if (tag_eq(tmp_tag, "opacity")) {
      st->opacity = parse_opacity(tmp_decls);
      st->flags |= SE_FLAG_OPACITY;
    } else if (tag_eq(tmp_tag, "display")) {
      st->display = parse_display(tmp_decls);
      st->flags |= SE_FLAG_DISPLAY;
    }
    if (*p == ';')
      p++;
  }
}

static void se_css_add_rule(const char *tag, const char *decls)
{
  SeRule *r;
  size_t i;
  if (se_rule_count >= SE_RULE_MAX)
    return;
  r = &se_rules[se_rule_count];
  memset(r, 0, sizeof(*r));
  for (i = 0; tag[i] && i < SE_TAG_MAX - 1; i++) {
    char c = tag[i];
    if (c >= 'A' && c <= 'Z')
      c = (char)(c + 32);
    r->tag[i] = c;
  }
  r->tag[i] = '\0';
  se_css_parse_decls(decls, &r->style);
  se_rule_count++;
}

static void css_merge_style(const SeStyle *src, SeStyle *dst)
{
  if (src->flags & SE_FLAG_COLOR) {
    dst->color_rgb = src->color_rgb;
    dst->flags |= SE_FLAG_COLOR;
  }
  if (src->flags & SE_FLAG_FONT) {
    dst->font_size_px = src->font_size_px;
    dst->flags |= SE_FLAG_FONT;
  }
  if (src->flags & SE_FLAG_MARGIN) {
    dst->margin_px = src->margin_px;
    dst->flags |= SE_FLAG_MARGIN;
  }
  if (src->flags & SE_FLAG_DISPLAY) {
    dst->display = src->display;
    dst->flags |= SE_FLAG_DISPLAY;
  }
  if (src->flags & SE_FLAG_PADDING) {
    dst->padding_px = src->padding_px;
    dst->flags |= SE_FLAG_PADDING;
  }
  if (src->flags & SE_FLAG_BORDER_W) {
    dst->border_w_px = src->border_w_px;
    dst->flags |= SE_FLAG_BORDER_W;
  }
  if (src->flags & SE_FLAG_BG) {
    dst->bg_rgb = src->bg_rgb;
    dst->flags |= SE_FLAG_BG;
  }
  if (src->flags & SE_FLAG_WIDTH) {
    dst->width_px = src->width_px;
    dst->flags |= SE_FLAG_WIDTH;
  }
  if (src->flags & SE_FLAG_HEIGHT) {
    dst->height_px = src->height_px;
    dst->flags |= SE_FLAG_HEIGHT;
  }
  if (src->flags & SE_FLAG_MAX_HEIGHT) {
    dst->max_height_px = src->max_height_px;
    dst->flags |= SE_FLAG_MAX_HEIGHT;
  }
  if (src->flags & SE_FLAG_MIN_HEIGHT) {
    dst->min_height_px = src->min_height_px;
    dst->flags |= SE_FLAG_MIN_HEIGHT;
  }
  if (src->flags & SE_FLAG_MAX_WIDTH) {
    dst->max_width_px = src->max_width_px;
    dst->flags |= SE_FLAG_MAX_WIDTH;
  }
  if (src->flags & SE_FLAG_MIN_WIDTH) {
    dst->min_width_px = src->min_width_px;
    dst->flags |= SE_FLAG_MIN_WIDTH;
  }
  if (src->flags & SE_FLAG_BORDER_C) {
    dst->border_rgb = src->border_rgb;
    dst->flags |= SE_FLAG_BORDER_C;
  }
  if (src->flags & SE_FLAG_BORDER_S) {
    dst->border_style = src->border_style;
    dst->flags |= SE_FLAG_BORDER_S;
  }
  if (src->flags & SE_FLAG_VIS) {
    dst->visibility = src->visibility;
    dst->flags |= SE_FLAG_VIS;
  }
  if (src->flags & SE_FLAG_OPACITY) {
    dst->opacity = src->opacity;
    dst->flags |= SE_FLAG_OPACITY;
  }
}

static void se_css_compute(size_t node_id, const char *tag,
                           const char *inline_decls)
{
  SeStyle *st;
  size_t i;
  if (node_id >= SE_STYLE_MAX)
    return;
  st = &se_style_pool[node_id];
  memset(st, 0, sizeof(*st));
  for (i = 0; i < se_rule_count; i++) {
    if (tag_eq(tag, se_rules[i].tag))
      css_merge_style(&se_rules[i].style, st);
  }
  if (inline_decls && inline_decls[0])
    se_css_parse_decls(inline_decls, st);
}

static void css_parse_stylesheet(const char *sheet)
{
  const char *p = sheet;
  while (*p) {
    size_t ti = 0;
    size_t vi = 0;
    p = skip_ws(p);
    if (!*p)
      break;
    while (*p && *p != '{') {
      char c = *p;
      if (c != ' ' && c != '\t' && c != '\n' && c != '\r') {
        if (ti < SE_TAG_MAX - 1) {
          if (c >= 'A' && c <= 'Z')
            c = (char)(c + 32);
          tmp_tag[ti++] = c;
        }
      }
      p++;
    }
    tmp_tag[ti] = '\0';
    if (*p != '{')
      break;
    p++;
    while (*p && *p != '}') {
      if (vi < 510)
        tmp_decls[vi++] = *p;
      p++;
    }
    tmp_decls[vi] = '\0';
    if (*p == '}')
      p++;
    se_css_add_rule(tmp_tag, tmp_decls);
  }
}

static const char *css_tag_gt(const char *p)
{
  while (*p && *p != '>')
    p++;
  return *p == '>' ? p : NULL;
}

static const char *css_next_open_tag(const char *html)
{
  const char *p = html + scan_pos;
  while (*p) {
    const char *gt;
    if (*p != '<') {
      p++;
      continue;
    }
    if (p[1] == '/' || p[1] == '!' || p[1] == '?') {
      gt = css_tag_gt(p);
      if (!gt)
        return NULL;
      p = gt + 1;
      continue;
    }
    return p;
  }
  return NULL;
}

/* Extract style= between tag start and '>' into tmp_decls.
 * Returns 1 if found. Temporarily zeros '>' like GAS. */
static int css_extract_style_attr(char *tag_start, char *gt)
{
  char *found;
  char q;
  size_t vi = 0;
  *gt = '\0';
  found = (char *)find_ci(tag_start, "style=");
  *gt = '>';
  if (!found || found >= gt)
    return 0;
  found += 6;
  q = *found;
  if (q != '"' && q != '\'')
    return 0;
  found++;
  while (*found && *found != q) {
    if (vi < 510)
      tmp_decls[vi++] = *found;
    found++;
  }
  tmp_decls[vi] = '\0';
  return 1;
}

static void se_css_attach(void)
{
  const char *html = spark_bootstrap_dom_html();
  char *mutable_html;
  size_t html_len;
  size_t id;
  char *scan;

  se_css_reset();
  se_style_count = spark_bootstrap_dom_nnodes();
  if (se_style_count > SE_STYLE_MAX)
    se_style_count = SE_STYLE_MAX;

  /* Pass 1: <style> bodies — mutate a copy (GAS zeros </style>). */
  html_len = strlen(html);
  mutable_html = malloc(html_len + 1);
  if (!mutable_html)
    return;
  memcpy(mutable_html, html, html_len + 1);
  scan = mutable_html;
  for (;;) {
    char *st = (char *)find_ci(scan, "<style");
    char *gt;
    char *end;
    if (!st)
      break;
    gt = (char *)css_tag_gt(st);
    if (!gt)
      break;
    st = gt + 1;
    end = (char *)find_ci(st, "</style>");
    if (!end)
      break;
    *end = '\0';
    css_parse_stylesheet(st);
    *end = '<';
    scan = end + 1;
  }

  /* Pass 2: elements + inline style= from live html_buf order. */
  scan_pos = 0;
  /* Use original html for open-tag scan (GAS uses html_buf). */
  for (id = 0; id < se_style_count; id++) {
    const char *tag;
    char *open;
    char *gt;
    const char *inl = NULL;
    if (spark_bootstrap_dom_kind(id) != EP_KIND_ELEM)
      continue;
    tag = spark_bootstrap_dom_tag(id);
    open = (char *)css_next_open_tag(html);
    if (!open) {
      se_css_compute(id, tag, NULL);
      continue;
    }
    /* Need mutable for style= extract bound — copy slice into
     * a scratch via cast on original? GAS mutates html_buf '>'.
     * Use mutable_html with same scan_pos offsets. */
    open = mutable_html + (size_t)(open - html);
    gt = (char *)css_tag_gt(open);
    if (!gt) {
      se_css_compute(id, tag, NULL);
      continue;
    }
    if (css_extract_style_attr(open, gt))
      inl = tmp_decls;
    se_css_compute(id, tag, inl);
    scan_pos = (size_t)(gt + 1 - mutable_html);
  }
  free(mutable_html);
}

static int emit_hex6(char *dst, unsigned rgb)
{
  static const char *hexd = "0123456789abcdef";
  int i;
  for (i = 5; i >= 0; i--) {
    dst[5 - i] = hexd[(rgb >> (i * 4)) & 0xf];
  }
  return 6;
}

/* Match GAS: transparent → literal; else 6 hex digits. */
static void emit_color_str(char *dst, unsigned rgb)
{
  if (rgb == SE_BG_TRANSPARENT) {
    memcpy(dst, "transparent", 12);
    return;
  }
  emit_hex6(dst, rgb);
  dst[6] = '\0';
}

static int css_emit_json(void)
{
  size_t i;
  size_t n;
  FILE *f;
  char *p = out_buf;
  char *end = out_buf + EC_JSON_CAP;

  n = (size_t)snprintf(p, (size_t)(end - p),
                       "{\"op\":\"engine.css\",\"ok\":true,\"nodes\":%zu,"
                       "\"styles\":[",
                       se_style_count);
  if (n >= (size_t)(end - p))
    return -1;
  p += n;
  for (i = 0; i < se_style_count; i++) {
    SeStyle *st = &se_style_pool[i];
    char hex[16];
    char bghex[16];
    char bdrhex[16];
    emit_color_str(hex, st->color_rgb);
    emit_color_str(bghex, st->bg_rgb);
    emit_color_str(bdrhex, st->border_rgb);
    if (i > 0) {
      if (p >= end)
        return -1;
      *p++ = ',';
    }
    n = (size_t)snprintf(
        p, (size_t)(end - p),
        "{\"id\":%zu,\"display\":%d,\"color\":\"%s\","
        "\"font_size\":%d,\"margin\":%d,\"padding\":%d,"
        "\"border_width\":%d,\"background_color\":\"%s\","
        "\"width\":%d,\"height\":%d,\"max_height\":%d,"
        "\"min_height\":%d,\"max_width\":%d,\"min_width\":%d,"
        "\"border_color\":\"%s\",\"border_style\":%d,"
        "\"visibility\":%d,\"opacity\":%d,\"flags\":%d}",
        i, st->display, hex, st->font_size_px, st->margin_px,
        st->padding_px, st->border_w_px, bghex, st->width_px,
        st->height_px, st->max_height_px, st->min_height_px,
        st->max_width_px, st->min_width_px, bdrhex, st->border_style,
        st->visibility, st->opacity, st->flags);
    if (n >= (size_t)(end - p))
      return -1;
    p += n;
  }
  if (p + 3 >= end)
    return -1;
  *p++ = ']';
  *p++ = '}';
  *p++ = '\n';
  *p = '\0';

  if (ensure_dirs() != 0)
    return -1;
  f = fopen(EC_PATH, "wb");
  if (!f)
    return -1;
  if (fwrite(out_buf, 1, (size_t)(p - out_buf), f) !=
      (size_t)(p - out_buf)) {
    fclose(f);
    return -1;
  }
  fclose(f);
  return 0;
}

static int css_selftest(void)
{
  size_t i;
  if (se_style_count < 3)
    return 0;
  for (i = 0; i < se_style_count; i++) {
    SeStyle *st = &se_style_pool[i];
    if ((st->flags & SE_FLAG_FONT) && st->font_size_px == 20 &&
        (st->flags & SE_FLAG_COLOR) &&
        st->color_rgb == 0x00C80000)
      return 1;
  }
  return 0;
}

int spark_bootstrap_engine_css_attach(void)
{
  if (spark_bootstrap_dom_nnodes() == 0) {
    fprintf(stderr,
            "error: engine css attach needs DOM"
            " (engine parse first)\n");
    return 1;
  }
  se_css_attach();
  if (css_emit_json() != 0) {
    fprintf(stderr, "error: engine css cannot write css.json\n");
    return 1;
  }
  if (!css_selftest()) {
    fprintf(stderr, "error: engine css selftest failed\n");
    return 1;
  }
  return 0;
}

const void *spark_bootstrap_css_styles(void)
{
  return se_style_pool;
}

size_t spark_bootstrap_css_style_count(void)
{
  return se_style_count;
}

void spark_bootstrap_engine_css_reset(void)
{
  se_css_reset();
}
