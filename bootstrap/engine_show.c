/* Dry engine show via GAS engine_window.s spine (no invent / no X11).
 * Validate P6 PPM or .rgb path → out/browser/show.json dry JSON. */
#include "engine_show.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static int ensure_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

/* 1=ppm, 2=rgb, 0=missing, -1=bad format — match ew_validate_image */
static int validate_image(const char *path)
{
  FILE *f;
  unsigned char hdr[16];
  size_t n;
  size_t plen;

  f = fopen(path, "rb");
  if (!f)
    return 0;
  n = fread(hdr, 1, sizeof(hdr), f);
  fclose(f);
  if (n >= 3 && hdr[0] == 'P' && hdr[1] == '6' &&
      (hdr[2] == '\n' || hdr[2] == '\r' || hdr[2] == ' ' ||
       hdr[2] == '\t'))
    return 1;
  plen = strlen(path);
  if (plen >= 4 && strcmp(path + plen - 4, ".rgb") == 0)
    return 2;
  return -1;
}

static int finish_json(char *json_out, size_t json_cap, const char *json)
{
  size_t len = strlen(json);
  if (!json_out || json_cap == 0)
    return 0;
  if (len + 1 > json_cap) {
    fprintf(stderr, "error: engine show json overflow\n");
    return 1;
  }
  memcpy(json_out, json, len + 1);
  return 0;
}

int spark_bootstrap_engine_show(const char *path, char *json_out,
                                size_t json_cap)
{
  const char *use;
  int kind;
  const char *fmt;
  char json[ES_SHOW_JSON_CAP];
  FILE *out;

  use = (path && path[0]) ? path : ES_DEFAULT_PPM;
  kind = validate_image(use);
  if (kind == 0) {
    fprintf(stderr,
            "error: browser show: cannot open image"
            " (PPM/RGB path)\n");
    return 1;
  }
  if (kind < 0) {
    fprintf(stderr,
            "error: browser show: not P6 PPM or .rgb"
            " (want P6 header or --rgb)\n");
    return 1;
  }
  fmt = (kind == 2) ? "rgb" : "ppm";
  if (ensure_dirs() != 0) {
    fprintf(stderr, "error: engine show cannot mkdir out/browser\n");
    return 1;
  }
  /* Exact spine from asm/engine_window.s j_show_dry_* (no invent) */
  snprintf(json, sizeof(json),
           "{\"op\":\"show\",\"ok\":true,\"mode\":\"dry-run\","
           "\"display\":false,\"path\":\"%s\",\"format\":\"%s\"}",
           use, fmt);
  out = fopen(ES_SHOW_JSON_PATH, "wb");
  if (!out) {
    fprintf(stderr, "error: engine show cannot write show.json\n");
    return 1;
  }
  if (fwrite(json, 1, strlen(json), out) != strlen(json)) {
    fclose(out);
    fprintf(stderr, "error: engine show cannot write show.json\n");
    return 1;
  }
  fclose(out);
  return finish_json(json_out, json_cap, json);
}
