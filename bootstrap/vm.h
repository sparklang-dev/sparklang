/* Spark C bootstrap VM — thin dry-run subset (path B). */
#ifndef SPARK_BOOTSTRAP_VM_H
#define SPARK_BOOTSTRAP_VM_H

#include <stddef.h>

#define SPARK_VM_MAX_LINE 4096
#define SPARK_VM_MAX_VARS 64
#define SPARK_VM_NAME_MAX 64
/* DOM JSON from engine parse can exceed 1k (hello.html ~1.7k). */
#define SPARK_VM_VAL_MAX 8192
#define SPARK_VM_TOOL_SCOPE 128

typedef struct {
  char name[SPARK_VM_NAME_MAX];
  char value[SPARK_VM_VAL_MAX];
  int used;
} SparkVar;

typedef struct {
  SparkVar vars[SPARK_VM_MAX_VARS];
  char last_val[SPARK_VM_VAL_MAX];
  size_t last_val_len;
  char model_alias[SPARK_VM_NAME_MAX];
  char prior_model[SPARK_VM_NAME_MAX];
  int dry_run; /* always 1 in bootstrap MVP */
  /* tool / with tools — matches asm tools_active + tool_reg_* */
  int tools_active;
  char tool_reg_name[SPARK_VM_NAME_MAX];
  size_t tool_reg_len;
  char tools_scope[SPARK_VM_TOOL_SCOPE];
  /* browser run|open|start → session; goto needs session_on */
  int browser_session_on;
  char browser_script[SPARK_VM_VAL_MAX];
  char browser_url[SPARK_VM_VAL_MAX];
  /* mitm enable dry stub → mitm.json (matches j_mitm_on) */
  int mitm_on;
} SparkVM;

void spark_vm_init(SparkVM *vm);
int spark_vm_run_file(SparkVM *vm, const char *path);
int spark_vm_run_line(SparkVM *vm, const char *line);

#endif
