/* Shared dry fixtures — asm/spark.s + bootstrap/vm.c (no inventing). */
#include "dry_ops.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static const char DRY_SUPPORT[] =
    "{\"label\":\"support\",\"confidence\":0.91,"
    "\"reasons\":[\"dry-run\"]}";
static const char DRY_SALES[] =
    "{\"label\":\"sales\",\"confidence\":0.88,"
    "\"reasons\":[\"dry-run\"]}";
static const char DRY_SPAM[] =
    "{\"label\":\"spam\",\"confidence\":0.95,"
    "\"reasons\":[\"dry-run\"]}";
static const char DRY_PERSON[] =
    "{\"name\":\"Ada Lovelace\",\"age\":36}";
static const char DRY_TRANSCRIPT[] =
    "My account is locked and I need support.";
static const char DRY_REV_HIGHER[] =
    "{\"issues\":[\"possible eval\",\"ai-authored patterns\"],"
    "\"complexity\":\"mid\",\"suggested_level\":\"higher\","
    "\"rationale\":\"web/JS surface — suggest high-level "
    "companion; never execute\"}";
static const char DRY_REV_LOWER[] =
    "{\"issues\":[\"hot path candidate\"],\"complexity\":\"low\","
    "\"suggested_level\":\"lower\",\"rationale\":\"asm/.s — keep "
    "machine-code level\"}";
static const char DRY_REV_MID[] =
    "{\"issues\":[\"glue boilerplate\"],\"complexity\":\"mid\","
    "\"suggested_level\":\"mid\",\"rationale\":\"Spark/C-like fit "
    "— stay on asm VM surface\"}";
static const char BR_DEFAULT_SCRIPT[] = "examples/browser_main.spark";
static const char BR_DEFAULT_URL[] = "https://example.com/";
static const char BR_SESS_PRE[] =
    "{\"op\":\"run\",\"ok\":true,\"mode\":\"dry-run\","
    "\"session\":\"out/browser\",\"script\":\"";
static const char BR_SESS_MID[] = "\",\"url\":\"";
static const char BR_SESS_SUF[] =
    "\",\"gui\":false,\"disable_quic\":false,"
    "\"chromium_flag\":\"--enable-quic\","
    "\"note\":\"language session; GUI only via"
    " browser gui --live; QUIC on by default\"}";
static const char BR_GOTO_PRE[] = "{\"op\":\"goto\",\"ok\":true,\"url\":\"";
static const char BR_GOTO_SUF[] = "\"}";
static const char MITM_ENABLE_DRY[] =
    "{\"op\":\"enable\",\"ok\":true,"
    "\"proxy\":\"127.0.0.1:8877\","
    "\"cdp\":\"127.0.0.1:9222\","
    "\"scope\":\"owner-local\","
    "\"owner\":\"spark-mitm-h2\","
    "\"mode\":\"dry-run-session\"}";
static const unsigned char WAV_STUB[] = {
    'R', 'I', 'F', 'F', 0x24, 0x00, 0x00, 0x00, 'W', 'A', 'V', 'E',
    'f', 'm', 't', ' ', 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x40, 0x1f, 0x00, 0x00, 0x40, 0x1f, 0x00, 0x00, 0x01, 0x00, 0x08,
    0x00, 'd', 'a', 't', 'a', 0x04, 0x00, 0x00, 0x00, 'S', 'P', 'K',
    '\n'};

static int contains_ci(const char *hay, const char *needle)
{
  size_t nlen = strlen(needle);
  size_t hlen = strlen(hay);
  size_t i;
  size_t j;
  if (!needle[0] || nlen > hlen)
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

static int ensure_parent_dir(const char *path)
{
  char dir[512];
  const char *slash;
  size_t n;
  if (!path || !path[0])
    return 0;
  slash = strrchr(path, '/');
  if (!slash || slash == path)
    return 0;
  n = (size_t)(slash - path);
  if (n >= sizeof(dir))
    return -1;
  memcpy(dir, path, n);
  dir[n] = '\0';
  if (mkdir(dir, 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

const char *spark_dry_person(void) { return DRY_PERSON; }

const char *spark_dry_transcript(void) { return DRY_TRANSCRIPT; }

const char *spark_pick_review_report(const char *heuristic)
{
  if (contains_ci(heuristic, ".js") || contains_ci(heuristic, ".py") ||
      contains_ci(heuristic, "eval"))
    return DRY_REV_HIGHER;
  if (contains_ci(heuristic, ".spark"))
    return DRY_REV_MID;
  if (contains_ci(heuristic, ".s"))
    return DRY_REV_LOWER;
  return DRY_REV_MID;
}

int spark_write_stub_wav(const char *path)
{
  FILE *f;
  if (ensure_parent_dir(path) != 0) {
    fprintf(stderr, "error: speak mkdir failed\n");
    return -1;
  }
  f = fopen(path, "wb");
  if (!f) {
    perror(path);
    return -1;
  }
  if (fwrite(WAV_STUB, 1, sizeof(WAV_STUB), f) != sizeof(WAV_STUB)) {
    fclose(f);
    fprintf(stderr, "error: speak stub write failed\n");
    return -1;
  }
  fclose(f);
  return 0;
}

const char *spark_br_default_script(void) { return BR_DEFAULT_SCRIPT; }
const char *spark_br_default_url(void) { return BR_DEFAULT_URL; }

int spark_ensure_browser_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/browser", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

int spark_write_session_json(const char *script, const char *url,
                             char *json, size_t jcap)
{
  FILE *f;
  int n;
  const char *scr = script && script[0] ? script : BR_DEFAULT_SCRIPT;
  const char *u = url && url[0] ? url : BR_DEFAULT_URL;
  n = snprintf(json, jcap, "%s%s%s%s%s", BR_SESS_PRE, scr, BR_SESS_MID, u,
               BR_SESS_SUF);
  if (n < 0 || (size_t)n >= jcap)
    return -1;
  if (spark_ensure_browser_dirs() != 0)
    return -1;
  f = fopen("out/browser/session.json", "w");
  if (!f)
    return -1;
  if (fwrite(json, 1, (size_t)n, f) != (size_t)n) {
    fclose(f);
    return -1;
  }
  fclose(f);
  return 0;
}

int spark_format_browser_goto_json(const char *url, char *json, size_t jcap)
{
  int n;
  const char *u = url && url[0] ? url : BR_DEFAULT_URL;
  n = snprintf(json, jcap, "%s%s%s", BR_GOTO_PRE, u, BR_GOTO_SUF);
  if (n < 0 || (size_t)n >= jcap)
    return -1;
  return 0;
}

const char *spark_mitm_enable_dry_json(void) { return MITM_ENABLE_DRY; }

int spark_write_mitm_json(void)
{
  FILE *f;
  size_t n;
  if (spark_ensure_browser_dirs() != 0)
    return -1;
  f = fopen("out/browser/mitm.json", "w");
  if (!f)
    return -1;
  n = strlen(MITM_ENABLE_DRY);
  if (fwrite(MITM_ENABLE_DRY, 1, n, f) != n) {
    fclose(f);
    return -1;
  }
  fclose(f);
  return 0;
}
