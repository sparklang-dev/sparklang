/* sparkasm — Spark-native assembler (x86_64 Linux), phase 1
 * (exit + push/pop/push-imm/call/ret/jmp/cmp/test/jcc/add/sub/
 *  and/or/xor + shl/shr imm + lea [reg+disp]|[reg+reg] +
 *  imul reg,imm + neg/not/inc/dec/xchg + add/sub reg,reg +
 *  cqo/cdqe + cmp/test imm + sete/setl + movzbq/movsbq + shl-cl/sar/leave/mul/idiv/adc/sbb/rol/ror/stc/clc/rcl/rcr/bsf/bsr/std/cld/bt/bts/btr/btc/shld/shrd/cmovz/cmovnz/cmovl/cmovg/cmovle/cmovge/cmova/cmovb/cmovae/cmovbe + mov reg,reg)
 */
#ifndef SPARKASM_H
#define SPARKASM_H

#include <stddef.h>
#include <stdint.h>

enum { SA_MAX_SYMS = 256, SA_MAX_CODE = 65536, SA_MAX_LINE = 512 };

typedef enum {
	SA_FMT_ELF_O = 0,
	SA_FMT_BIN = 1
} sa_format_t;

typedef struct {
	char name[64];
	uint32_t offset;
	int is_global;
	int defined;
} sa_sym_t;

typedef struct {
	uint8_t code[SA_MAX_CODE];
	size_t code_len;
	sa_sym_t syms[SA_MAX_SYMS];
	int nsyms;
	char err[256];
} sa_unit_t;

int sa_assemble_file(const char *path, sa_unit_t *u);
int sa_write_elf_o(const char *path, const sa_unit_t *u);
int sa_write_bin(const char *path, const sa_unit_t *u);

#endif
