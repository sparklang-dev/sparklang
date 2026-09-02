#include "dry_ide.h"

#include "dry_ask.h"
#include "engine_show.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define IDE_BUF_CAP 65536
#define IDE_PATH_CAP 512
#define IDE_ASK_CAP 4096
#define IDE_STATUS_SCR 64

static char ide_buf[IDE_BUF_CAP];
static size_t ide_buf_len;
static char ide_path[IDE_PATH_CAP];
static int ide_path_set;
static int ide_dirty;
static char ide_status_scr[IDE_STATUS_SCR];
static char ide_ask_prompt[IDE_ASK_CAP];

static const char J_OPEN[] =
    "{\"op\":\"ide.open\",\"ok\":true,\"dirty\":false}\n";
static const char J_RUN_DRY[] =
    "{\"op\":\"ide.run\",\"ok\":true,\"mode\":\"dry-run\"}\n";
static const char J_ASK[] =
    "{\"op\":\"ide.ask\",\"ok\":true,\"via\":\"ask_run_prompt\"}\n";
static const char J_SHOW[] =
    "{\"op\":\"ide.show\",\"ok\":true,\"via\":\"spark-engine-show\"}\n";
static const char PATH_EDITOR_PPM[] = "out/ide/editor.ppm";

extern void ide_paint_bind(const char *ptr, unsigned long len);
extern int ide_paint_editor(void);
extern int ide_paint_write_ppm(const char *path);
extern void ide_status_set(const char *ptr, unsigned long len);
extern void ide_ai_set(const char *ptr, unsigned long len);

static int bind_last(SparkDryIdeCtx *ctx, const char *bind)
{
  if (!bind || !bind[0] || !ctx->vars_put)
    return 0;
  return ctx->vars_put(ctx->frame, bind, ctx->last);
}

static int ensure_ide_dirs(void)
{
  if (mkdir("out", 0755) != 0 && errno != EEXIST)
    return -1;
  if (mkdir("out/ide", 0755) != 0 && errno != EEXIST)
    return -1;
  return 0;
}

static void ide_rebind_paint(void)
{
  size_t n;
  if (ide_path_set) {
    n = strnlen(ide_path, IDE_STATUS_SCR - 2);
    memcpy(ide_status_scr, ide_path, n);
  } else {
    const char *u = "untitled";
    n = strlen(u);
    memcpy(ide_status_scr, u, n);
  }
  if (ide_dirty && n + 1 < IDE_STATUS_SCR) {
    ide_status_scr[n] = '*';
    n++;
  }
  ide_status_scr[n] = '\0';
  ide_status_set(ide_status_scr, n);
  ide_paint_bind(ide_buf, ide_buf_len);
  if (ensure_ide_dirs() != 0)
    return;
  if (ide_paint_editor() == 0)
    ide_paint_write_ppm(PATH_EDITOR_PPM);
}

static int fork_spark_dry(const char *script_path)
{
  pid_t pid;
  int status;
  if (access("./spark", X_OK) != 0) {
    fprintf(stderr, "error: ide run: ./spark missing (run make spark)\n");
    return 1;
  }
  pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid == 0) {
    execl("./spark", "spark", "--dry-run", script_path, (char *)NULL);
    perror("execl ./spark");
    _exit(127);
  }
  if (waitpid(pid, &status, 0) < 0) {
    perror("waitpid");
    return 1;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    fprintf(stderr, "error: ide run: ./spark child failed\n");
    return 1;
  }
  return 0;
}

int spark_dry_ide_open(SparkDryIdeCtx *ctx, const char *path,
                       const char *bind)
{
  FILE *f;
  long n;

  if (!path || !path[0]) {
    fprintf(stderr, "error: ide open needs \"path\"\n");
    return 1;
  }
  printf("[ide] open\n");
  printf("  → %s\n", path);
  strncpy(ide_path, path, IDE_PATH_CAP - 1);
  ide_path[IDE_PATH_CAP - 1] = '\0';
  ide_path_set = 1;
  f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "error: ide open: cannot read path\n");
    return 1;
  }
  n = (long)fread(ide_buf, 1, IDE_BUF_CAP - 1, f);
  if (n < 0) {
    fclose(f);
    fprintf(stderr, "error: ide open: cannot read path\n");
    return 1;
  }
  ide_buf[n] = '\0';
  ide_buf_len = (size_t)n;
  fclose(f);
  ide_dirty = 0;
  ide_rebind_paint();
  strncpy(ctx->last, J_OPEN, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  {
    size_t ln = strlen(ctx->last);
    if (ln > 0 && ctx->last[ln - 1] == '\n')
      ctx->last[ln - 1] = '\0';
  }
  fputs(J_OPEN, stdout);
  return bind_last(ctx, bind);
}

int spark_dry_ide_run(SparkDryIdeCtx *ctx, const char *bind)
{
  FILE *f;

  if (ide_buf_len == 0) {
    fprintf(stderr,
            "error: ide run: empty buffer"
            " (ide open or write first)\n");
    return 1;
  }
  if (ensure_ide_dirs() != 0)
    return 1;
  if (!ide_path_set) {
    strncpy(ide_path, "out/ide/buffer.spark", IDE_PATH_CAP - 1);
    ide_path[IDE_PATH_CAP - 1] = '\0';
    ide_path_set = 1;
  }
  f = fopen(ide_path, "wb");
  if (!f || fwrite(ide_buf, 1, ide_buf_len, f) != ide_buf_len) {
    if (f)
      fclose(f);
    fprintf(stderr, "error: ide run: cannot write buffer path\n");
    return 1;
  }
  fclose(f);
  printf("[ide] run\n");
  printf("  → %s\n", ide_path);
  if (fork_spark_dry(ide_path) != 0)
    return 1;
  strncpy(ctx->last, J_RUN_DRY, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  {
    size_t ln = strlen(ctx->last);
    if (ln > 0 && ctx->last[ln - 1] == '\n')
      ctx->last[ln - 1] = '\0';
  }
  fputs(J_RUN_DRY, stdout);
  return bind_last(ctx, bind);
}

int spark_dry_ide_ask(SparkDryIdeCtx *ctx, const char *bind)
{
  const char *reply;
  size_t n;

  if (ide_buf_len == 0) {
    fprintf(stderr,
            "error: ide ask: empty buffer"
            " (ide open first)\n");
    return 1;
  }
  printf("[ide] ask\n");
  n = ide_buf_len;
  if (n >= IDE_ASK_CAP - 64)
    n = IDE_ASK_CAP - 64;
  memcpy(ide_ask_prompt, ide_buf, n);
  ide_ask_prompt[n] = '\0';
  reply = spark_pick_ask_reply(ide_ask_prompt);
  printf("[ask] %s\n", ide_ask_prompt);
  printf("  → %s\n", reply);
  ide_ai_set(reply, strlen(reply));
  ide_rebind_paint();
  strncpy(ctx->last, reply, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  fputs(J_ASK, stdout);
  return bind_last(ctx, bind);
}

int spark_dry_ide_show(SparkDryIdeCtx *ctx, const char *path,
                       const char *bind)
{
  char json[ES_SHOW_JSON_CAP];
  const char *ppm;

  if (ide_buf_len > 0)
    ide_rebind_paint();
  ppm = (path && path[0]) ? path : PATH_EDITOR_PPM;
  printf("[ide] show\n");
  if (spark_bootstrap_engine_show(ppm, json, sizeof(json)) != 0)
    return 1;
  printf("  → %s\n", json);
  strncpy(ctx->last, J_SHOW, SPARK_VM_VAL_MAX - 1);
  ctx->last[SPARK_VM_VAL_MAX - 1] = '\0';
  {
    size_t ln = strlen(ctx->last);
    if (ln > 0 && ctx->last[ln - 1] == '\n')
      ctx->last[ln - 1] = '\0';
  }
  fputs(J_SHOW, stdout);
  return bind_last(ctx, bind);
}
