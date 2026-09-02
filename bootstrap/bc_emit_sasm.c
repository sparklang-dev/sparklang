/* BC → sparkasm lowering — docs/SPARK_BC.md opcodes only.
 * Emits bc_vm dispatch loop + MODEL/ASK/PRINT/HALT/LET/CLASSIFY +
 * EXTRACT + PIPELINE + LISTEN + SPEAK + VOICE + review/browser/mitm +
 * TOOL/WITH/WITH_END. Engine/IDE families use linear capture (popen
 * bc_vm body) — sparkasm lea [r14+r15] needs disp32; bc base is r14. */
#include "bc_opcodes.h"
#include "bc_read.h"
#include "dry_ask.h"
#include "dry_auto_model.h"
#include "dry_classify.h"
#include "dry_ops.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define EMIT_VARS_MAX 32
#define EMIT_NAME_MAX 64
#define EMIT_VAL_LABEL 96
#define EMIT_TOOL_REPLY 64
#define EMIT_LINE_MAX 4096
#define EMIT_BODY_LINES 128
#define EMIT_JSON_MAX 2048

static char g_body_lines[EMIT_BODY_LINES][EMIT_LINE_MAX];
static int g_nbody_lines;

typedef struct {
  char name[EMIT_NAME_MAX];
  char val_label[EMIT_VAL_LABEL];
  size_t val_len;
  int used;
} EmitVar;

static EmitVar g_vars[EMIT_VARS_MAX];
static int g_nvars;

static void var_bind(const char *name, const char *val_label, size_t val_len)
{
  int i;

  if (!name || !name[0])
    return;
  for (i = 0; i < g_nvars; i++) {
    if (g_vars[i].used && strcmp(g_vars[i].name, name) == 0) {
      strncpy(g_vars[i].val_label, val_label,
              EMIT_VAL_LABEL - 1);
      g_vars[i].val_label[EMIT_VAL_LABEL - 1] = '\0';
      g_vars[i].val_len = val_len;
      return;
    }
  }
  if (g_nvars >= EMIT_VARS_MAX)
    return;
  strncpy(g_vars[g_nvars].name, name, EMIT_NAME_MAX - 1);
  g_vars[g_nvars].name[EMIT_NAME_MAX - 1] = '\0';
  strncpy(g_vars[g_nvars].val_label, val_label,
          EMIT_VAL_LABEL - 1);
  g_vars[g_nvars].val_label[EMIT_VAL_LABEL - 1] = '\0';
  g_vars[g_nvars].val_len = val_len;
  g_vars[g_nvars].used = 1;
  g_nvars++;
}

static const EmitVar *var_find(const char *name)
{
  int i;

  for (i = 0; i < g_nvars; i++) {
    if (g_vars[i].used && strcmp(g_vars[i].name, name) == 0)
      return &g_vars[i];
  }
  return NULL;
}

static int const_str(const SparkBc *bc, uint16_t idx, const char **out)
{
  uint16_t si;

  if (idx >= bc->nconsts)
    return 1;
  if (bc->consts[idx].kind != SPBC_CONST_STR)
    return 1;
  si = bc->consts[idx].payload;
  if (si >= bc->nstrs)
    return 1;
  *out = (const char *)bc->strs[si].bytes;
  return 0;
}

static uint16_t read_u16le(const SparkBc *bc, uint32_t off)
{
  return (uint16_t)(bc->code[off] | ((uint16_t)bc->code[off + 1] << 8));
}

static void emit_bytes(FILE *out, const uint8_t *bytes, size_t len)
{
  size_t i;

  fprintf(out, "\t.byte");
  for (i = 0; i < len; i++) {
    if (i)
      fprintf(out, ",");
    fprintf(out, " 0x%02x", bytes[i]);
  }
  fprintf(out, "\n");
}

static void emit_cstring(FILE *out, const char *label, const char *s)
{
  size_t i;
  size_t n;
  size_t chunk;

  fprintf(out, "%s:\n", label);
  n = strlen(s);
  for (i = 0; i < n || i == 0; i += chunk) {
    size_t j;

    chunk = n - i;
    if (chunk > 16)
      chunk = 16;
    if (i == 0 && n == 0)
      chunk = 0;
    fprintf(out, "\t.byte");
    for (j = 0; j < chunk; j++) {
      if (j)
        fprintf(out, ",");
      fprintf(out, " 0x%02x", (unsigned char)s[i + j]);
    }
    if (chunk == 0)
      fprintf(out, " 0x00");
    else if (i + chunk >= n)
      fprintf(out, ", 0x00");
    fprintf(out, "\n");
    if (n == 0)
      break;
  }
}

static void emit_writestr_call(FILE *out, const char *label, size_t len)
{
  fprintf(out, "\tlea\trsi, %s\n", label);
  fprintf(out, "\tmov\trdx, %zu\n", len);
  fprintf(out, "\tcall\twritestr\n");
}

static void emit_prefix_model(FILE *out)
{
  emit_writestr_call(out, "txt_model_banner", 8);
}

static void emit_prefix_ask(FILE *out)
{
  emit_writestr_call(out, "txt_ask_banner", 6);
}

static void emit_prefix_classify(FILE *out)
{
  emit_writestr_call(out, "txt_classify_banner", 11);
}

static void emit_prefix_arrow(FILE *out)
{
  emit_writestr_call(out, "txt_arrow", 6);
}

static void emit_prefix_print(FILE *out)
{
  emit_writestr_call(out, "txt_print_banner", 8);
}

static void emit_prefix_let(FILE *out)
{
  emit_writestr_call(out, "txt_let_banner", 6);
}

static void emit_prefix_extract(FILE *out)
{
  emit_writestr_call(out, "txt_extract_banner", 10);
}

static void emit_prefix_listen(FILE *out)
{
  emit_writestr_call(out, "txt_listen_banner", 9);
}

static void emit_prefix_speak(FILE *out)
{
  emit_writestr_call(out, "txt_speak_banner", 14);
}

static void emit_prefix_tool(FILE *out)
{
  emit_writestr_call(out, "txt_tool_banner", 18);
}

static void emit_prefix_with(FILE *out)
{
  emit_writestr_call(out, "txt_with_banner", 7);
}

static int opcode_size(uint8_t op);

static int bc_has_engine_ide(const SparkBc *bc)
{
  uint32_t ip = 0;

  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];
    int sz;

    if (op == SPBC_OP_HALT)
      break;
    if (op >= SPBC_OP_ENGINE_FETCH && op <= SPBC_OP_IDE_SHOW)
      return 1;
    sz = opcode_size(op);
    if (!sz)
      return 0;
    ip += (uint32_t)sz;
  }
  return 0;
}

static int capture_bc_body(const char *bc_path)
{
  char cmd[512];
  FILE *p;
  char line[EMIT_LINE_MAX];
  int in_body = 0;

  g_nbody_lines = 0;
  snprintf(cmd, sizeof(cmd), "./spark-bootstrap --run-bc %s 2>/dev/null",
           bc_path);
  p = popen(cmd, "r");
  if (!p)
    return 1;
  while (fgets(line, sizeof(line), p)) {
    size_t n = strlen(line);

    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
      line[--n] = '\0';
    if (!in_body) {
      if (strncmp(line, "[spark] dry-run via bytecode VM", 29) == 0)
        in_body = 1;
      continue;
    }
    if (strcmp(line, "[spark] ok") == 0)
      break;
    if (g_nbody_lines >= EMIT_BODY_LINES)
      break;
    strncpy(g_body_lines[g_nbody_lines], line, EMIT_LINE_MAX - 1);
    g_body_lines[g_nbody_lines][EMIT_LINE_MAX - 1] = '\0';
    g_nbody_lines++;
  }
  pclose(p);
  return g_nbody_lines > 0 ? 0 : 1;
}

static int emit_linear_sasm(FILE *out)
{
  int i;

  fprintf(out, "# emitted SPARK_BC linear capture (engine/IDE)\n");
  fprintf(out, ".global _start\n.text\n");
  emit_cstring(out, "txt_nl", "\n");
  for (i = 0; i < g_nbody_lines; i++) {
    char label[32];

    snprintf(label, sizeof(label), "body_%d", i);
    emit_cstring(out, label, g_body_lines[i]);
  }
  fprintf(out, "sys_write:\n\tmov\trax, 1\n\tsyscall\n\tret\n");
  fprintf(out, "writestr:\n\tmov\trdi, 1\n\tcall\tsys_write\n\tret\n");
  fprintf(out, "writestr_nl:\n\tpush\trax\n");
  fprintf(out, "\tlea\trsi, txt_nl\n\tmov\trdx, 1\n");
  fprintf(out, "\tcall\twritestr\n\tpop\trax\n\tret\n");
  fprintf(out, "_start:\n");
  for (i = 0; i < g_nbody_lines; i++) {
    char label[32];

    snprintf(label, sizeof(label), "body_%d", i);
    fprintf(out, "\tlea\trsi, %s\n", label);
    fprintf(out, "\tmov\trdx, %zu\n", strlen(g_body_lines[i]));
    fprintf(out, "\tcall\twritestr\n");
    fprintf(out, "\tmov\trax, 1\n");
    fprintf(out, "\tcall\twritestr_nl\n");
  }
  fprintf(out, "\tmov\trax, 60\n");
  fprintf(out, "\txor\trdi, rdi\n");
  fprintf(out, "\tsyscall\n");
  return 0;
}

static void emit_prefix_review(FILE *out)
{
  emit_writestr_call(out, "txt_review_banner", 9);
}

static void emit_prefix_browser(FILE *out)
{
  emit_writestr_call(out, "txt_browser_banner", 16);
}

static void emit_prefix_mitm(FILE *out)
{
  emit_writestr_call(out, "txt_mitm_banner", 13);
}

static void emit_prefix_voice(FILE *out)
{
  emit_writestr_call(out, "txt_voice_line", 15);
}

static void emit_prefix_review_static(FILE *out)
{
  emit_writestr_call(out, "txt_review_static", 37);
}

static void emit_prefix_eq(FILE *out)
{
  emit_writestr_call(out, "txt_eq_sp", 3);
}

static void emit_resolve_const(FILE *out, const SparkBc *bc)
{
  uint16_t i;

  fprintf(out, "resolve_const:\n");
  for (i = 0; i < bc->nconsts; i++) {
    fprintf(out, "\tcmp\trcx, %u\n", (unsigned)i);
    fprintf(out, "\tje\trs_c%u\n", (unsigned)i);
  }
  fprintf(out, "\tcall\temit_fail\n");
  for (i = 0; i < bc->nconsts; i++) {
    const char *lit;
    size_t n;

    if (const_str(bc, i, &lit) != 0)
      continue;
    n = strlen(lit);
    fprintf(out, "rs_c%u:\n", (unsigned)i);
    fprintf(out, "\tlea\trsi, str_c%u\n", (unsigned)i);
    fprintf(out, "\tmov\trdx, %zu\n", n);
    fprintf(out, "\tret\n");
  }
}

static void emit_pools(FILE *out, const SparkBc *bc)
{
  uint16_t i;

  for (i = 0; i < bc->nstrs; i++) {
    char label[32];
    const char *lit;

    snprintf(label, sizeof(label), "str_c%u", (unsigned)i);
    lit = (const char *)bc->strs[i].bytes;
    emit_cstring(out, label, lit);
  }

  fprintf(out, "bc_code:\n");
  emit_bytes(out, bc->code, bc->ncode);
}

static int opcode_size(uint8_t op)
{
  switch (op) {
  case SPBC_OP_HALT:
  case SPBC_OP_PIPELINE:
  case SPBC_OP_WITH_END:
  case SPBC_OP_VOICE:
    return 1;
  case SPBC_OP_MODEL:
  case SPBC_OP_PRINT:
  case SPBC_OP_LISTEN:
  case SPBC_OP_SPEAK:
  case SPBC_OP_TOOL:
  case SPBC_OP_WITH:
  case SPBC_OP_ENGINE_CSS:
  case SPBC_OP_ENGINE_LAYOUT:
  case SPBC_OP_ENGINE_PAINT_BOXES:
  case SPBC_OP_ENGINE_PAINT_FIXTURE:
  case SPBC_OP_ENGINE_RENDER:
  case SPBC_OP_IDE_RUN:
  case SPBC_OP_IDE_ASK:
  case SPBC_OP_MITM_ENABLE:
    return 3;
  case SPBC_OP_EXTRACT:
  case SPBC_OP_EXPECT:
    return 7;
  case SPBC_OP_ASK:
  case SPBC_OP_LET:
  case SPBC_OP_CLASSIFY:
  case SPBC_OP_EMBED:
  case SPBC_OP_RETRIEVE:
  case SPBC_OP_ENGINE_FETCH:
  case SPBC_OP_ENGINE_FETCH_PARSE:
  case SPBC_OP_ENGINE_PARSE:
  case SPBC_OP_ENGINE_SHOW:
  case SPBC_OP_IDE_OPEN:
  case SPBC_OP_IDE_SHOW:
  case SPBC_OP_REVIEW_PATH:
  case SPBC_OP_REVIEW_TEXT:
  case SPBC_OP_BROWSER_RUN:
  case SPBC_OP_BROWSER_GOTO:
    return 5;
  default:
    return 0;
  }
}

static int emit_browser_run_json(const SparkBc *bc, uint32_t ip,
                                 char *json, size_t jcap)
{
  uint16_t sidx;

  if (ip + 3 > bc->ncode)
    return 1;
  sidx = read_u16le(bc, ip + 1);
  {
    const char *script;

    if (const_str(bc, sidx, &script) != 0)
      return 1;
    return spark_write_session_json(
        script[0] ? script : spark_br_default_script(),
        spark_br_default_url(), json, jcap);
  }
}

static int emit_browser_goto_json(const SparkBc *bc, uint32_t ip,
                                  char *json, size_t jcap)
{
  uint16_t uidx;

  if (ip + 3 > bc->ncode)
    return 1;
  uidx = read_u16le(bc, ip + 1);
  {
    const char *url;

    if (const_str(bc, uidx, &url) != 0)
      return 1;
    if (!url[0])
      url = spark_br_default_url();
    return spark_format_browser_goto_json(url, json, jcap);
  }
}

static int emit_review_pool(FILE *out, const SparkBc *bc)
{
  uint32_t ip = 0;
  int nrev = 0;
  int br_run_i = 0;
  int br_goto_i = 0;

  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];

    if (op == SPBC_OP_HALT)
      break;
    if (op == SPBC_OP_REVIEW_PATH || op == SPBC_OP_REVIEW_TEXT) {
      uint16_t tidx = read_u16le(bc, ip + 1);
      uint16_t bidx = read_u16le(bc, ip + 3);
      const char *text;
      const char *bind;
      const char *report;
      char rlabel[32];

      if (const_str(bc, tidx, &text) != 0)
        return 1;
      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      report = spark_pick_review_report(text);
      snprintf(rlabel, sizeof(rlabel), "review_r_%d", nrev);
      emit_cstring(out, rlabel, report);
      if (bind[0])
        var_bind(bind, rlabel, strlen(report));
      nrev++;
    } else if (op == SPBC_OP_BROWSER_RUN) {
      char json[EMIT_JSON_MAX];
      char jlabel[32];

      if (emit_browser_run_json(bc, ip, json, sizeof(json)) != 0)
        return 1;
      snprintf(jlabel, sizeof(jlabel), "br_json_%d", br_run_i);
      emit_cstring(out, jlabel, json);
      {
        uint16_t bidx = read_u16le(bc, ip + 3);
        const char *bind;

        if (const_str(bc, bidx, &bind) == 0 && bind[0])
          var_bind(bind, jlabel, strlen(json));
      }
      br_run_i++;
    } else if (op == SPBC_OP_BROWSER_GOTO) {
      char json[EMIT_JSON_MAX];
      char jlabel[32];
      char urlabel[32];
      uint16_t uidx = read_u16le(bc, ip + 1);
      uint16_t bidx = read_u16le(bc, ip + 3);
      const char *bind;
      const char *url;

      if (emit_browser_goto_json(bc, ip, json, sizeof(json)) != 0)
        return 1;
      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      if (const_str(bc, uidx, &url) != 0)
        return 1;
      snprintf(jlabel, sizeof(jlabel), "bg_json_%d", br_goto_i);
      emit_cstring(out, jlabel, json);
      if (url[0]) {
        snprintf(urlabel, sizeof(urlabel), "goto_url_%d", br_goto_i);
        emit_cstring(out, urlabel, url);
        if (bind[0])
          var_bind(bind, urlabel, strlen(url));
      } else if (bind[0]) {
        var_bind(bind, jlabel, strlen(json));
      }
      br_goto_i++;
    } else if (op == SPBC_OP_MITM_ENABLE) {
      uint16_t bidx = read_u16le(bc, ip + 1);
      const char *bind;
      const char *json = spark_mitm_enable_dry_json();

      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      if (bind[0])
        var_bind(bind, "mitm_json", strlen(json));
    }
    if (!opcode_size(op))
      return 1;
    ip += (uint32_t)opcode_size(op);
  }
  return 0;
}


static const char *model_alias_before_ip(const SparkBc *bc,
                                         uint32_t target_ip)
{
  uint32_t ip = 0;
  const char *alias = "fast";

  while (ip < bc->ncode && ip < target_ip) {
    uint8_t op = bc->code[ip];

    if (op == SPBC_OP_HALT)
      break;
    if (op == SPBC_OP_MODEL) {
      uint16_t ci = read_u16le(bc, ip + 1);
      const char *a;

      if (const_str(bc, ci, &a) == 0 && a[0])
        alias = a;
    }
    if (!opcode_size(op))
      break;
    ip += (uint32_t)opcode_size(op);
  }
  return alias;
}

static const char *ask_reply_at_ip(const SparkBc *bc, uint32_t target_ip,
                                   char *tbuf, size_t tbuf_sz)
{
  uint32_t ip = 0;
  char tool_name[EMIT_NAME_MAX];
  size_t tool_len = 0;
  int tools_active = 0;

  tool_name[0] = '\0';
  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];

    if (op == SPBC_OP_HALT)
      break;
    if (ip == target_ip) {
      uint16_t tidx;

      if (op != SPBC_OP_ASK)
        return NULL;
      tidx = read_u16le(bc, ip + 1);
      {
        const char *text;

        if (const_str(bc, tidx, &text) != 0)
          return NULL;
        if (tools_active && tool_len > 0) {
          snprintf(tbuf, tbuf_sz, "[tool:%s] stub:local", tool_name);
          return tbuf;
        }
        return spark_pick_ask_reply(text);
      }
    }
    if (op == SPBC_OP_TOOL) {
      uint16_t nidx = read_u16le(bc, ip + 1);
      const char *name;

      if (const_str(bc, nidx, &name) == 0) {
        strncpy(tool_name, name, EMIT_NAME_MAX - 1);
        tool_name[EMIT_NAME_MAX - 1] = '\0';
        tool_len = strlen(tool_name);
      }
    } else if (op == SPBC_OP_WITH) {
      if (tool_len > 0)
        tools_active = 1;
    } else if (op == SPBC_OP_WITH_END) {
      tools_active = 0;
    }
    if (!opcode_size(op))
      return NULL;
    ip += (uint32_t)opcode_size(op);
  }
  return NULL;
}

static int emit_with_pool(FILE *out, const SparkBc *bc)
{
  uint32_t ip = 0;
  int nwith = 0;

  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];

    if (op == SPBC_OP_HALT)
      break;
    if (op == SPBC_OP_WITH) {
      uint16_t sidx = read_u16le(bc, ip + 1);
      const char *scope;
      char line[256];
      char wlabel[32];

      if (const_str(bc, sidx, &scope) != 0)
        return 1;
      snprintf(line, sizeof(line),
               "{\"op\":\"with_tools\",\"tools\":\"%s\","
               "\"active\":true}",
               scope);
      snprintf(wlabel, sizeof(wlabel), "with_body_%d", nwith);
      emit_cstring(out, wlabel, line);
      nwith++;
    }
    if (!opcode_size(op))
      return 1;
    ip += (uint32_t)opcode_size(op);
  }
  return 0;
}

static int emit_reply_pool(FILE *out, const SparkBc *bc)
{
  uint32_t ip = 0;
  int nreply = 0;

  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];
    if (op == SPBC_OP_HALT)
      break;
    if (op == SPBC_OP_ASK || op == SPBC_OP_CLASSIFY ||
        op == SPBC_OP_EMBED || op == SPBC_OP_RETRIEVE) {
      uint16_t tidx = read_u16le(bc, ip + 1);
      uint16_t bidx = read_u16le(bc, ip + 3);
      const char *text;
      const char *bind;
      const char *reply;
      char rlabel[32];
      char tbuf[EMIT_TOOL_REPLY];

      if (const_str(bc, tidx, &text) != 0)
        return 1;
      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      if (op == SPBC_OP_CLASSIFY)
        reply = spark_pick_classify(text);
      else {
        reply = ask_reply_at_ip(bc, ip, tbuf, sizeof(tbuf));
        if (!reply)
          return 1;
      }
      snprintf(rlabel, sizeof(rlabel), "reply_%d", nreply);
      emit_cstring(out, rlabel, reply);
      if (bind[0])
        var_bind(bind, rlabel, strlen(reply));
      nreply++;
    } else if (op == SPBC_OP_EXTRACT) {
      uint16_t bidx = read_u16le(bc, ip + 5);
      const char *bind;
      const char *person = spark_dry_person();

      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      if (bind[0])
        var_bind(bind, "dry_person", strlen(person));
    } else if (op == SPBC_OP_EXPECT) {
      /* Assert only — no new binding. Runtime is bc_vm / GAS. */
      (void)0;
    } else if (op == SPBC_OP_LISTEN) {
      uint16_t bidx = read_u16le(bc, ip + 1);
      const char *bind;
      const char *transcript = spark_dry_transcript();

      if (const_str(bc, bidx, &bind) != 0)
        return 1;
      if (bind[0])
        var_bind(bind, "dry_transcript", strlen(transcript));
    } else if (op == SPBC_OP_LET) {
      uint16_t nidx = read_u16le(bc, ip + 1);
      uint16_t vidx = read_u16le(bc, ip + 3);
      const char *name;
      const char *val;
      char vlabel[32];

      if (const_str(bc, nidx, &name) != 0)
        return 1;
      if (const_str(bc, vidx, &val) != 0)
        return 1;
      snprintf(vlabel, sizeof(vlabel), "str_c%u",
               (unsigned)bc->consts[vidx].payload);
      var_bind(name, vlabel, strlen(val));
    }
    if (!opcode_size(op))
      return 1;
    ip += (uint32_t)opcode_size(op);
  }
  return 0;
}

static void emit_handlers(FILE *out, const SparkBc *bc)
{
  fprintf(out, "op_model:\n");
  fprintf(out, "\tcall\temit_prefix_model\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_ask:\n");
  {
    uint32_t scan = 0;
    int ask_i = 0;
    int any_auto = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];

      if (op == SPBC_OP_ASK) {
        const char *alias = model_alias_before_ip(bc, scan);
        const char *prompt;
        uint16_t tidx = read_u16le(bc, scan + 1);

        if (strcmp(alias, "auto") == 0 &&
            const_str(bc, tidx, &prompt) == 0) {
          fprintf(out, "\tcmp\tr15, %u\n", scan);
          fprintf(out, "\tje\task_auto_%d\n", ask_i);
          any_auto = 1;
        }
        ask_i++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    if (any_auto) {
      fprintf(out, "\tjmp\task_auto_done\n");
      scan = 0;
      ask_i = 0;
      while (scan < bc->ncode) {
        uint8_t op = bc->code[scan];

        if (op == SPBC_OP_ASK) {
          const char *alias = model_alias_before_ip(bc, scan);
          const char *prompt;
          uint16_t tidx = read_u16le(bc, scan + 1);

          if (strcmp(alias, "auto") == 0 &&
              const_str(bc, tidx, &prompt) == 0) {
            const char *picked =
                spark_resolve_auto_model(prompt, prompt);
            int is_code = (strcmp(picked, "code") == 0);

            fprintf(out, "ask_auto_%d:\n", ask_i);
            fprintf(out, "\tlea\trsi, %s\n",
                    is_code ? "txt_auto_code" : "txt_auto_fast");
            fprintf(out, "\tmov\trdx, 20\n");
            fprintf(out, "\tcall\twritestr\n");
            fprintf(out, "\tjmp\task_auto_done\n");
          }
          ask_i++;
          scan += 5;
          continue;
        }
        if (!opcode_size(op))
          break;
        scan += (uint32_t)opcode_size(op);
      }
      fprintf(out, "ask_auto_done:\n");
    }
  }
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tpush\trsi\n");
  fprintf(out, "\tpush\trdx\n");
  fprintf(out, "\tcall\temit_prefix_ask\n");
  fprintf(out, "\tpop\trdx\n");
  fprintf(out, "\tpop\trsi\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tcall\temit_prefix_arrow\n");
  {
    uint32_t scan = 0;
    int ask_i = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_ASK) {
        uint16_t tidx = read_u16le(bc, scan + 1);
        const char *text;
        char rlabel[32];

        if (const_str(bc, tidx, &text) != 0)
          return;
        snprintf(rlabel, sizeof(rlabel), "reply_%d", ask_i);
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\task_r%d\n", ask_i);
        ask_i++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    ask_i = 0;
    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_ASK) {
        const char *reply;
        char tbuf[EMIT_TOOL_REPLY];
        char rlabel[32];

        reply = ask_reply_at_ip(bc, scan, tbuf, sizeof(tbuf));
        if (!reply)
          return;
        snprintf(rlabel, sizeof(rlabel), "reply_%d", ask_i);
        fprintf(out, "ask_r%d:\n", ask_i);
        fprintf(out, "\tlea\trsi, %s\n", rlabel);
        fprintf(out, "\tmov\trdx, %zu\n", strlen(reply));
        fprintf(out, "\tjmp\task_done\n");
        ask_i++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "ask_done:\n");
  }
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tlea\trsi, txt_accounting\n");
  fprintf(out, "\tmov\trdx, 90\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tadd\tr15, 5\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_classify:\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tpush\trsi\n");
  fprintf(out, "\tpush\trdx\n");
  fprintf(out, "\tcall\temit_prefix_classify\n");
  fprintf(out, "\tpop\trdx\n");
  fprintf(out, "\tpop\trsi\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tcall\temit_prefix_arrow\n");
  {
    uint32_t scan = 0;
    int cls_i = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_CLASSIFY) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\tclassify_r%d\n", cls_i);
        cls_i++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    cls_i = 0;
    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_CLASSIFY) {
        uint16_t tidx = read_u16le(bc, scan + 1);
        const char *text;
        const char *reply;
        char rlabel[32];

        if (const_str(bc, tidx, &text) != 0)
          return;
        reply = spark_pick_classify(text);
        snprintf(rlabel, sizeof(rlabel), "reply_%d", cls_i);
        fprintf(out, "classify_r%d:\n", cls_i);
        fprintf(out, "\tlea\trsi, %s\n", rlabel);
        fprintf(out, "\tmov\trdx, %zu\n", strlen(reply));
        fprintf(out, "\tjmp\tclassify_done\n");
        cls_i++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "classify_done:\n");
  }
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 5\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_extract:\n");
  fprintf(out, "\tcall\temit_prefix_extract\n");
  fprintf(out, "\tlea\trsi, dry_person\n");
  fprintf(out, "\tmov\trdx, %zu\n", strlen(spark_dry_person()));
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_pipeline:\n");
  fprintf(out, "\tlea\trsi, txt_pipeline_step\n");
  fprintf(out, "\tmov\trdx, %zu\n", strlen("[pipeline] step"));
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 1\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_listen:\n");
  fprintf(out, "\tcall\temit_prefix_listen\n");
  fprintf(out, "\tlea\trsi, dry_transcript\n");
  fprintf(out, "\tmov\trdx, %zu\n", strlen(spark_dry_transcript()));
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_speak:\n");
  fprintf(out, "\tcall\temit_prefix_speak\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_voice:\n");
  fprintf(out, "\tcall\temit_prefix_voice\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 1\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_review:\n");
  fprintf(out, "\tcall\temit_prefix_review\n");
  {
    uint32_t scan = 0;
    int ri = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_REVIEW_PATH || op == SPBC_OP_REVIEW_TEXT) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\treview_body_%d\n", ri);
        ri++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    ri = 0;
    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_REVIEW_PATH || op == SPBC_OP_REVIEW_TEXT) {
        uint16_t tidx = read_u16le(bc, scan + 1);
        const char *text;
        const char *report;
        char rlabel[32];

        if (const_str(bc, tidx, &text) != 0)
          return;
        report = spark_pick_review_report(text);
        snprintf(rlabel, sizeof(rlabel), "review_r_%d", ri);
        fprintf(out, "review_body_%d:\n", ri);
        fprintf(out, "\tlea\trsi, str_c%u\n",
                (unsigned)bc->consts[tidx].payload);
        fprintf(out, "\tmov\trdx, %zu\n", strlen(text));
        fprintf(out, "\tcall\twritestr\n");
        fprintf(out, "\tmov\trax, 1\n");
        fprintf(out, "\tcall\twritestr_nl\n");
        fprintf(out, "\tcall\temit_prefix_review_static\n");
        fprintf(out, "\tmov\trax, 1\n");
        fprintf(out, "\tcall\twritestr_nl\n");
        fprintf(out, "\tcall\temit_prefix_arrow\n");
        fprintf(out, "\tlea\trsi, %s\n", rlabel);
        fprintf(out, "\tmov\trdx, %zu\n", strlen(report));
        fprintf(out, "\tjmp\treview_done\n");
        ri++;
        scan += 5;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "review_done:\n");
  }
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 5\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_browser_run:\n");
  fprintf(out, "\tcall\temit_prefix_browser\n");
  {
    uint32_t scan = 0;
    int bi = 0;

    while (scan < bc->ncode) {
      if (bc->code[scan] == SPBC_OP_BROWSER_RUN) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\tbr_h_%d\n", bi);
        bi++;
        scan += 5;
        continue;
      }
      if (!opcode_size(bc->code[scan]))
        break;
      scan += (uint32_t)opcode_size(bc->code[scan]);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    bi = 0;
    while (scan < bc->ncode) {
      if (bc->code[scan] == SPBC_OP_BROWSER_RUN) {
        fprintf(out, "br_h_%d:\n", bi);
        fprintf(out, "\tlea\trsi, br_json_%d\n", bi);
        {
          char json[EMIT_JSON_MAX];
          if (emit_browser_run_json(bc, scan, json, sizeof(json)) != 0)
            return;
          fprintf(out, "\tmov\trdx, %zu\n", strlen(json));
        }
        fprintf(out, "\tcall\twritestr\n");
        fprintf(out, "\tmov\trax, 1\n");
        fprintf(out, "\tcall\twritestr_nl\n");
        fprintf(out, "\tadd\tr15, 5\n");
        fprintf(out, "\tjmp\tvm_loop\n");
        bi++;
        scan += 5;
        continue;
      }
      if (!opcode_size(bc->code[scan]))
        break;
      scan += (uint32_t)opcode_size(bc->code[scan]);
    }
  }

  fprintf(out, "op_browser_goto:\n");
  fprintf(out, "\tcall\temit_prefix_browser\n");
  {
    uint32_t scan = 0;
    int gi = 0;

    while (scan < bc->ncode) {
      if (bc->code[scan] == SPBC_OP_BROWSER_GOTO) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\tbg_h_%d\n", gi);
        gi++;
        scan += 5;
        continue;
      }
      if (!opcode_size(bc->code[scan]))
        break;
      scan += (uint32_t)opcode_size(bc->code[scan]);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    gi = 0;
    while (scan < bc->ncode) {
      if (bc->code[scan] == SPBC_OP_BROWSER_GOTO) {
        fprintf(out, "bg_h_%d:\n", gi);
        fprintf(out, "\tlea\trsi, bg_json_%d\n", gi);
        {
          char json[EMIT_JSON_MAX];
          if (emit_browser_goto_json(bc, scan, json, sizeof(json)) != 0)
            return;
          fprintf(out, "\tmov\trdx, %zu\n", strlen(json));
        }
        fprintf(out, "\tcall\twritestr\n");
        fprintf(out, "\tmov\trax, 1\n");
        fprintf(out, "\tcall\twritestr_nl\n");
        fprintf(out, "\tadd\tr15, 5\n");
        fprintf(out, "\tjmp\tvm_loop\n");
        gi++;
        scan += 5;
        continue;
      }
      if (!opcode_size(bc->code[scan]))
        break;
      scan += (uint32_t)opcode_size(bc->code[scan]);
    }
  }

  fprintf(out, "op_mitm_enable:\n");
  fprintf(out, "\tcall\temit_prefix_mitm\n");
  fprintf(out, "\tlea\trsi, mitm_json\n");
  fprintf(out, "\tmov\trdx, %zu\n", strlen(spark_mitm_enable_dry_json()));
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_print:\n");
  fprintf(out, "\tcall\temit_prefix_print\n");
  {
    uint32_t scan = 0;
    int pri = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_PRINT) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\tprint_r%d\n", pri);
        pri++;
        scan += 3;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    pri = 0;
    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_PRINT) {
        uint16_t cidx = read_u16le(bc, scan + 1);
        const char *name;
        const EmitVar *bound;

        if (const_str(bc, cidx, &name) != 0)
          return;
        bound = var_find(name);
        fprintf(out, "print_r%d:\n", pri);
        if (bound) {
          fprintf(out, "\tlea\trsi, %s\n", bound->val_label);
          fprintf(out, "\tmov\trdx, %zu\n", bound->val_len);
        } else {
          fprintf(out, "\tlea\trsi, str_c%u\n",
                  (unsigned)bc->consts[cidx].payload);
          fprintf(out, "\tmov\trdx, %zu\n", strlen(name));
        }
        fprintf(out, "\tjmp\tprint_done\n");
        pri++;
        scan += 3;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "print_done:\n");
  }
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_let:\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tpush\trsi\n");
  fprintf(out, "\tpush\trdx\n");
  fprintf(out, "\tcall\temit_prefix_let\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tcall\temit_prefix_eq\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 3]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tpop\trdx\n");
  fprintf(out, "\tpop\trsi\n");
  fprintf(out, "\tadd\tr15, 5\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_tool:\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trcx, word [rax + 1]\n");
  fprintf(out, "\tcall\tresolve_const\n");
  fprintf(out, "\tcall\temit_prefix_tool\n");
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_with:\n");
  fprintf(out, "\tcall\temit_prefix_with\n");
  {
    uint32_t scan = 0;
    int wi = 0;

    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_WITH) {
        fprintf(out, "\tcmp\tr15, %u\n", scan);
        fprintf(out, "\tje\twith_r%d\n", wi);
        wi++;
        scan += 3;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "\tcall\temit_fail\n");
    scan = 0;
    wi = 0;
    while (scan < bc->ncode) {
      uint8_t op = bc->code[scan];
      if (op == SPBC_OP_WITH) {
        uint16_t sidx = read_u16le(bc, scan + 1);
        const char *scope;
        char wlabel[32];
        char line[256];

        if (const_str(bc, sidx, &scope) != 0)
          return;
        snprintf(line, sizeof(line),
                 "{\"op\":\"with_tools\",\"tools\":\"%s\","
                 "\"active\":true}",
                 scope);
        snprintf(wlabel, sizeof(wlabel), "with_body_%d", wi);
        fprintf(out, "with_r%d:\n", wi);
        fprintf(out, "\tlea\trsi, %s\n", wlabel);
        fprintf(out, "\tmov\trdx, %zu\n", strlen(line));
        fprintf(out, "\tjmp\twith_done\n");
        wi++;
        scan += 3;
        continue;
      }
      if (!opcode_size(op))
        break;
      scan += (uint32_t)opcode_size(op);
    }
    fprintf(out, "with_done:\n");
  }
  fprintf(out, "\tcall\twritestr\n");
  fprintf(out, "\tmov\trax, 1\n");
  fprintf(out, "\tcall\twritestr_nl\n");
  fprintf(out, "\tadd\tr15, 3\n");
  fprintf(out, "\tjmp\tvm_loop\n");

  fprintf(out, "op_with_end:\n");
  fprintf(out, "\tadd\tr15, 1\n");
  fprintf(out, "\tjmp\tvm_loop\n");
}

static void emit_vm_loop(FILE *out, const SparkBc *bc)
{
  fprintf(out, "vm_loop:\n");
  fprintf(out, "\tcmp\tr15, %u\n", (unsigned)bc->ncode);
  fprintf(out, "\tjge\tvm_done\n");
  fprintf(out, "\tlea\trax, [r14 + r15]\n");
  fprintf(out, "\tmovzx\trbx, byte [rax]\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_HALT);
  fprintf(out, "\tje\tvm_done\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_MODEL);
  fprintf(out, "\tje\top_model\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_ASK);
  fprintf(out, "\tje\top_ask\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_PRINT);
  fprintf(out, "\tje\top_print\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_LET);
  fprintf(out, "\tje\top_let\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_CLASSIFY);
  fprintf(out, "\tje\top_classify\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_EXTRACT);
  fprintf(out, "\tje\top_extract\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_PIPELINE);
  fprintf(out, "\tje\top_pipeline\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_LISTEN);
  fprintf(out, "\tje\top_listen\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_SPEAK);
  fprintf(out, "\tje\top_speak\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_VOICE);
  fprintf(out, "\tje\top_voice\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_REVIEW_PATH);
  fprintf(out, "\tje\top_review\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_REVIEW_TEXT);
  fprintf(out, "\tje\top_review\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_BROWSER_RUN);
  fprintf(out, "\tje\top_browser_run\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_BROWSER_GOTO);
  fprintf(out, "\tje\top_browser_goto\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_MITM_ENABLE);
  fprintf(out, "\tje\top_mitm_enable\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_TOOL);
  fprintf(out, "\tje\top_tool\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_WITH);
  fprintf(out, "\tje\top_with\n");
  fprintf(out, "\tcmp\trbx, %u\n", (unsigned)SPBC_OP_WITH_END);
  fprintf(out, "\tje\top_with_end\n");
  fprintf(out, "\tcall\temit_fail\n");
  emit_handlers(out, bc);
  fprintf(out, "vm_done:\n");
  fprintf(out, "\tret\n");
}

static int validate_bc(const SparkBc *bc)
{
  uint32_t ip = 0;

  while (ip < bc->ncode) {
    uint8_t op = bc->code[ip];
    int sz = opcode_size(op);

    if (op == SPBC_OP_HALT)
      return (ip + 1 == bc->ncode) ? 0 : 1;
    if (!sz || ip + (uint32_t)sz > bc->ncode)
      return 1;
    ip += (uint32_t)sz;
  }
  return 1;
}

static int emit_sasm(FILE *out, const SparkBc *bc, const char *bc_path)
{
  if (validate_bc(bc) != 0) {
    fprintf(stderr, "error: unsupported or truncated SPARK_BC program\n");
    return 1;
  }

  if (bc_has_engine_ide(bc)) {
    if (!bc_path || capture_bc_body(bc_path) != 0) {
      fprintf(stderr,
              "error: engine/IDE bc_emit needs spark-bootstrap capture\n");
      return 1;
    }
    return emit_linear_sasm(out);
  }

  fprintf(out, "# emitted SPARK_BC → sparkasm (Phase 5)\n");
  fprintf(out, ".global _start\n.text\n");

  emit_cstring(out, "txt_model_banner", "[model] ");
  emit_cstring(out, "txt_auto_fast", "[model] auto→fast\n");
  emit_cstring(out, "txt_auto_code", "[model] auto→code\n");
  emit_cstring(out, "txt_ask_banner", "[ask] ");
  emit_cstring(out, "txt_accounting",
               "[accounting] latency_ms=0 prompt_tokens=0 "
               "completion_tokens=0 total_tokens=0 "
               "note=dry-run\n");
  emit_cstring(out, "txt_classify_banner", "[classify] ");
  emit_cstring(out, "txt_extract_banner", "[extract] ");
  emit_cstring(out, "txt_listen_banner", "[listen] ");
  emit_cstring(out, "txt_speak_banner", "[speak] wrote ");
  emit_cstring(out, "txt_voice_line", "[voice] session");
  emit_cstring(out, "txt_review_banner", "[review] ");
  emit_cstring(out, "txt_review_static",
               "  (static only — never eval web JS)");
  emit_cstring(out, "txt_browser_banner", "[browser]   → ");
  emit_cstring(out, "txt_mitm_banner", "[mitm]   → ");
  emit_cstring(out, "txt_arrow", "  → ");
  emit_cstring(out, "txt_print_banner", "[print] ");
  emit_cstring(out, "txt_let_banner", "[let] ");
  emit_cstring(out, "txt_eq_sp", " = ");
  emit_cstring(out, "txt_tool_banner", "[tool] registered ");
  emit_cstring(out, "txt_with_banner", "[with] ");
  emit_cstring(out, "txt_nl", "\n");

  if (emit_reply_pool(out, bc) != 0)
    return 1;
  if (emit_with_pool(out, bc) != 0)
    return 1;
  if (emit_review_pool(out, bc) != 0)
    return 1;
  emit_cstring(out, "dry_person", spark_dry_person());
  emit_cstring(out, "dry_transcript", spark_dry_transcript());
  emit_cstring(out, "txt_pipeline_step", "[pipeline] step");
  emit_cstring(out, "mitm_json", spark_mitm_enable_dry_json());
  emit_pools(out, bc);

  fprintf(out, "sys_write:\n\tmov\trax, 1\n\tsyscall\n\tret\n");
  fprintf(out, "writestr:\n\tmov\trdi, 1\n\tcall\tsys_write\n\tret\n");
  fprintf(out, "writestr_nl:\n\tpush\trax\n");
  fprintf(out, "\tlea\trsi, txt_nl\n\tmov\trdx, 1\n");
  fprintf(out, "\tcall\twritestr\n\tpop\trax\n\tret\n");
  fprintf(out, "emit_prefix_model:\n");
  emit_prefix_model(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_ask:\n");
  emit_prefix_ask(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_classify:\n");
  emit_prefix_classify(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_extract:\n");
  emit_prefix_extract(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_listen:\n");
  emit_prefix_listen(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_speak:\n");
  emit_prefix_speak(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_voice:\n");
  emit_prefix_voice(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_review:\n");
  emit_prefix_review(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_review_static:\n");
  emit_prefix_review_static(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_browser:\n");
  emit_prefix_browser(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_mitm:\n");
  emit_prefix_mitm(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_arrow:\n");
  emit_prefix_arrow(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_print:\n");
  emit_prefix_print(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_let:\n");
  emit_prefix_let(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_eq:\n");
  emit_prefix_eq(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_tool:\n");
  emit_prefix_tool(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_prefix_with:\n");
  emit_prefix_with(out);
  fprintf(out, "\tret\n");
  fprintf(out, "emit_fail:\n\tmov\trax, 60\n\tmov\trdi, 1\n\tsyscall\n");

  emit_resolve_const(out, bc);
  emit_vm_loop(out, bc);

  fprintf(out, "_start:\n");
  fprintf(out, "\tlea\tr14, bc_code\n");
  fprintf(out, "\txor\tr15, r15\n");
  fprintf(out, "\tcall\tvm_loop\n");
  fprintf(out, "\tmov\trax, 60\n");
  fprintf(out, "\txor\trdi, rdi\n");
  fprintf(out, "\tsyscall\n");
  return 0;
}

int main(int argc, char **argv)
{
  SparkBc bc;
  const char *path;
  int rc;

  if (argc != 2) {
    fprintf(stderr, "usage: %s <file.sparkbc>\n", argv[0]);
    return 2;
  }
  path = argv[1];
  g_nvars = 0;
  rc = spark_bc_load(path, &bc);
  if (rc != 0)
    return 1;
  rc = emit_sasm(stdout, &bc, path);
  spark_bc_free(&bc);
  return rc;
}
