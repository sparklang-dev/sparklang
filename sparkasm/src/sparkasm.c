/* sparkasm encode + assemble + ELF ET_REL writer (phase 1) */
#include "sparkasm.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- registers ---- */

static int reg_num(const char *s) {
	static const char *names[] = {
		"rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
		"r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
		NULL
	};
	int i;
	for (i = 0; names[i]; i++) {
		if (strcmp(s, names[i]) == 0)
			return i;
	}
	return -1;
}

/* 8-bit regs for setcc: al..dil (no ah/ch/… in phase-1) */
static int reg8_num(const char *s) {
	static const char *names[] = {
		"al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil",
		NULL
	};
	int i;
	for (i = 0; names[i]; i++) {
		if (strcmp(s, names[i]) == 0)
			return i;
	}
	return -1;
}

/* ---- emit helpers ---- */

static int emit(sa_unit_t *u, uint8_t b) {
	if (u->code_len >= SA_MAX_CODE) {
		snprintf(u->err, sizeof(u->err), "code buffer full");
		return -1;
	}
	u->code[u->code_len++] = b;
	return 0;
}

static int emit_u32(sa_unit_t *u, uint32_t v) {
	return emit(u, (uint8_t)(v)) ||
	       emit(u, (uint8_t)(v >> 8)) ||
	       emit(u, (uint8_t)(v >> 16)) ||
	       emit(u, (uint8_t)(v >> 24));
}

static int emit_u64(sa_unit_t *u, uint64_t v) {
	int i;
	for (i = 0; i < 8; i++) {
		if (emit(u, (uint8_t)(v >> (8 * i))))
			return -1;
	}
	return 0;
}

/* mov r64, imm — prefer sign-extended imm32 when it fits */
static int enc_mov_imm(sa_unit_t *u, int rd, int64_t imm) {
	uint8_t rex = 0x48; /* W=1 */
	if (rd >= 8)
		rex |= 0x01; /* B */
	if (imm >= (int64_t)INT32_MIN && imm <= (int64_t)INT32_MAX) {
		/* REX.W C7 /0 rd : mov r/m64, imm32 */
		if (emit(u, rex) || emit(u, 0xC7) ||
		    emit(u, (uint8_t)(0xC0 | (rd & 7))) ||
		    emit_u32(u, (uint32_t)(int32_t)imm))
			return -1;
		return 0;
	}
	/* REX.W B8+rd : mov r64, imm64 */
	if (emit(u, rex) || emit(u, (uint8_t)(0xB8 + (rd & 7))) ||
	    emit_u64(u, (uint64_t)imm))
		return -1;
	return 0;
}

static int enc_syscall(sa_unit_t *u) {
	return emit(u, 0x0F) || emit(u, 0x05);
}

static int enc_nop(sa_unit_t *u) {
	return emit(u, 0x90);
}

/* push/pop r64 — 50+rd / 58+rd; REX.B for r8–r15 */
static int enc_push_reg(sa_unit_t *u, int rd) {
	if (rd >= 8) {
		if (emit(u, 0x41))
			return -1;
	}
	return emit(u, (uint8_t)(0x50 + (rd & 7)));
}

/* push imm — GAS: pushq $42 → 6a 2a; pushq $0x100 → 68 00 01 00 00
 * Intel 6A ib (imm8 sign-extended) or 68 id (imm32).
 */
static int enc_push_imm(sa_unit_t *u, int64_t imm) {
	if (imm >= -128 && imm <= 127) {
		if (emit(u, 0x6A) || emit(u, (uint8_t)(int8_t)imm))
			return -1;
		return 0;
	}
	if (imm < (int64_t)INT32_MIN || imm > (int64_t)INT32_MAX) {
		snprintf(u->err, sizeof(u->err),
			 "push imm out of imm32 range");
		return -1;
	}
	if (emit(u, 0x68) || emit_u32(u, (uint32_t)(int32_t)imm))
		return -1;
	return 0;
}

static int enc_pop_reg(sa_unit_t *u, int rd) {
	if (rd >= 8) {
		if (emit(u, 0x41))
			return -1;
	}
	return emit(u, (uint8_t)(0x58 + (rd & 7)));
}

static int enc_ret(sa_unit_t *u) {
	return emit(u, 0xC3);
}

/* leave — GAS: leave → c9 (mov rsp,rbp; pop rbp) */
static int enc_leave(sa_unit_t *u) {
	return emit(u, 0xC9);
}

/* stc — GAS: stc → f9 (set CF); clc → f8 (clear CF) */
static int enc_stc(sa_unit_t *u) {
	return emit(u, 0xF9);
}

static int enc_clc(sa_unit_t *u) {
	return emit(u, 0xF8);
}

/* std — GAS: std → fd (set DF); cld → fc (clear DF) */
static int enc_std(sa_unit_t *u) {
	return emit(u, 0xFD);
}

static int enc_cld(sa_unit_t *u) {
	return emit(u, 0xFC);
}

/* cqo / cqto — GAS: cqo → 48 99 (sign-extend rax into rdx:rax) */
static int enc_cqo(sa_unit_t *u) {
	return emit(u, 0x48) || emit(u, 0x99);
}

/* cdqe / cltq — GAS: cdqe → 48 98 (sign-extend eax into rax) */
static int enc_cdqe(sa_unit_t *u) {
	return emit(u, 0x48) || emit(u, 0x98);
}

/* Same-section near call/jmp — patch rel32 at end of assemble */
enum { SA_MAX_FIXUPS = 512 };

typedef struct {
	uint32_t patch_off; /* offset of rel32 in code[] */
	uint32_t next_pc;   /* PC after the insn */
	char name[64];
} sa_fixup_t;

static sa_fixup_t g_fixups[SA_MAX_FIXUPS];
static int g_nfixups;

static sa_sym_t *sym_find(sa_unit_t *u, const char *name);
static sa_sym_t *sym_get(sa_unit_t *u, const char *name);

static int enc_call_label(sa_unit_t *u, const char *name) {
	uint32_t patch;
	if (g_nfixups >= SA_MAX_FIXUPS) {
		snprintf(u->err, sizeof(u->err), "too many fixups");
		return -1;
	}
	if (emit(u, 0xE8))
		return -1;
	patch = (uint32_t)u->code_len;
	if (emit_u32(u, 0))
		return -1;
	g_fixups[g_nfixups].patch_off = patch;
	g_fixups[g_nfixups].next_pc = (uint32_t)u->code_len;
	snprintf(g_fixups[g_nfixups].name,
		 sizeof(g_fixups[g_nfixups].name), "%s", name);
	g_nfixups++;
	return 0;
}

static int enc_jmp_label(sa_unit_t *u, const char *name) {
	uint32_t patch;
	if (g_nfixups >= SA_MAX_FIXUPS) {
		snprintf(u->err, sizeof(u->err), "too many fixups");
		return -1;
	}
	if (emit(u, 0xE9))
		return -1;
	patch = (uint32_t)u->code_len;
	if (emit_u32(u, 0))
		return -1;
	g_fixups[g_nfixups].patch_off = patch;
	g_fixups[g_nfixups].next_pc = (uint32_t)u->code_len;
	snprintf(g_fixups[g_nfixups].name,
		 sizeof(g_fixups[g_nfixups].name), "%s", name);
	g_nfixups++;
	return 0;
}

/* near jcc — 0F xx rel32; same fixup path as jmp */
static int enc_jcc_label(sa_unit_t *u, uint8_t op, const char *name) {
	uint32_t patch;
	if (g_nfixups >= SA_MAX_FIXUPS) {
		snprintf(u->err, sizeof(u->err), "too many fixups");
		return -1;
	}
	if (emit(u, 0x0F) || emit(u, op))
		return -1;
	patch = (uint32_t)u->code_len;
	if (emit_u32(u, 0))
		return -1;
	g_fixups[g_nfixups].patch_off = patch;
	g_fixups[g_nfixups].next_pc = (uint32_t)u->code_len;
	snprintf(g_fixups[g_nfixups].name,
		 sizeof(g_fixups[g_nfixups].name), "%s", name);
	g_nfixups++;
	return 0;
}

/* ALU r64, imm — 81/83 /digit
 * 0=add 1=or 4=and 5=sub 6=xor 7=cmp
 */
static int enc_alu_imm(sa_unit_t *u, int rd, int64_t imm, int digit) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (rd >= 8)
		rex |= 0x01;
	modrm = (uint8_t)(0xC0 | ((digit & 7) << 3) | (rd & 7));
	if (imm >= -128 && imm <= 127) {
		if (emit(u, rex) || emit(u, 0x83) || emit(u, modrm) ||
		    emit(u, (uint8_t)(int8_t)imm))
			return -1;
		return 0;
	}
	if (emit(u, rex) || emit(u, 0x81) || emit(u, modrm) ||
	    emit_u32(u, (uint32_t)(int32_t)imm))
		return -1;
	return 0;
}

static int enc_cmp_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 7);
}

static int enc_add_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 0);
}

static int enc_sub_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 5);
}

static int enc_adc_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 2);
}

static int enc_sbb_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 3);
}

static int enc_and_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 4);
}

static int enc_or_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 1);
}

static int enc_xor_imm(sa_unit_t *u, int rd, int64_t imm) {
	return enc_alu_imm(u, rd, imm, 6);
}

/* shl/shr/sar/rol/ror/rcl/rcr r64, imm — Intel D1 /digit (imm==1)
 * or C1 /digit ib
 * digit: 0=rol 1=ror 2=rcl 3=rcr 4=shl 5=shr 7=sar
 */
static int enc_shift_imm(sa_unit_t *u, int rd, int64_t imm, int digit) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (imm < 0 || imm > 255) {
		snprintf(u->err, sizeof(u->err),
			 "shift imm out of range (0..255)");
		return -1;
	}
	if (rd >= 8)
		rex |= 0x01;
	modrm = (uint8_t)(0xC0 | ((digit & 7) << 3) | (rd & 7));
	if (imm == 1) {
		if (emit(u, rex) || emit(u, 0xD1) || emit(u, modrm))
			return -1;
		return 0;
	}
	if (emit(u, rex) || emit(u, 0xC1) || emit(u, modrm) ||
	    emit(u, (uint8_t)imm))
		return -1;
	return 0;
}

/* shl/shr/sar/rol/ror/rcl/rcr r64, cl — GAS: rcl $1,%rdi → 48 d1 d7
 * Intel D3 /0|/1|/2|/3|/4|/5|/7
 */
static int enc_shift_cl(sa_unit_t *u, int rd, int digit) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (rd >= 8)
		rex |= 0x01;
	modrm = (uint8_t)(0xC0 | ((digit & 7) << 3) | (rd & 7));
	if (emit(u, rex) || emit(u, 0xD3) || emit(u, modrm))
		return -1;
	return 0;
}

/* shld/shrd r64, r64, imm8 — GAS: shld $1,%rsi,%rdi → 48 0f a4 f7 01
 * Intel 0F A4/AC /r ib; src in /r, dest in r/m; REX.W.
 */
static int enc_shxd_imm(sa_unit_t *u, int dest, int src, int64_t imm,
			uint8_t op) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (imm < 0 || imm > 255) {
		snprintf(u->err, sizeof(u->err),
			 "shxd imm out of range (0..255)");
		return -1;
	}
	if (src >= 8)
		rex |= 0x04; /* R */
	if (dest >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((src & 7) << 3) | (dest & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, op) ||
	    emit(u, modrm) || emit(u, (uint8_t)imm))
		return -1;
	return 0;
}

/* shld/shrd r64, r64, cl — GAS: 0F A5 / 0F AD */
static int enc_shxd_cl(sa_unit_t *u, int dest, int src, uint8_t op) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (src >= 8)
		rex |= 0x04; /* R */
	if (dest >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((src & 7) << 3) | (dest & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, op) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

/* lea r64, label — RIP-relative (same rel32 fixup as call/jmp). */
static int enc_lea_label(sa_unit_t *u, int dst, const char *name)
{
	uint8_t rex = 0x48;
	uint8_t modrm;
	uint32_t patch;

	if (g_nfixups >= SA_MAX_FIXUPS) {
		snprintf(u->err, sizeof(u->err), "too many fixups");
		return -1;
	}
	if (dst >= 8)
		rex |= 0x04;
	modrm = (uint8_t)(0x05 | ((dst & 7) << 3));
	if (emit(u, rex) || emit(u, 0x8D) || emit(u, modrm))
		return -1;
	patch = (uint32_t)u->code_len;
	if (emit_u32(u, 0))
		return -1;
	g_fixups[g_nfixups].patch_off = patch;
	g_fixups[g_nfixups].next_pc = (uint32_t)u->code_len;
	snprintf(g_fixups[g_nfixups].name,
		 sizeof(g_fixups[g_nfixups].name), "%s", name);
	g_nfixups++;
	return 0;
}

/* movzx r64, byte [base+disp8] — 0F B6. */
static int enc_movzx_byte_mem(sa_unit_t *u, int dst, int base, int64_t disp)
{
	uint8_t rex = 0x48;
	uint8_t modrm;

	if (base == 4) {
		snprintf(u->err, sizeof(u->err),
			 "movzx byte [rsp+disp] not in phase-1");
		return -1;
	}
	if (disp != 0 && (disp < -128 || disp > 127)) {
		snprintf(u->err, sizeof(u->err),
			 "movzx disp out of imm8 range");
		return -1;
	}
	if (dst >= 8)
		rex |= 0x04;
	if (base >= 8)
		rex |= 0x01;
	if (disp == 0)
		modrm = (uint8_t)(((dst & 7) << 3) | (base & 7));
	else
		modrm = (uint8_t)(0x40 | ((dst & 7) << 3) | (base & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xB6) || emit(u, modrm))
		return -1;
	if (disp != 0 && emit(u, (uint8_t)(int8_t)disp))
		return -1;
	return 0;
}

/* movzx r64, word [base+disp8] — 0F B7. */
static int enc_movzx_word_mem(sa_unit_t *u, int dst, int base, int64_t disp)
{
	uint8_t rex = 0x48;
	uint8_t modrm;

	if (base == 4) {
		snprintf(u->err, sizeof(u->err),
			 "movzx word [rsp+disp] not in phase-1");
		return -1;
	}
	if (disp != 0 && (disp < -128 || disp > 127)) {
		snprintf(u->err, sizeof(u->err),
			 "movzx disp out of imm8 range");
		return -1;
	}
	if (dst >= 8)
		rex |= 0x04;
	if (base >= 8)
		rex |= 0x01;
	if (disp == 0)
		modrm = (uint8_t)(((dst & 7) << 3) | (base & 7));
	else
		modrm = (uint8_t)(0x40 | ((dst & 7) << 3) | (base & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xB7) || emit(u, modrm))
		return -1;
	if (disp != 0 && emit(u, (uint8_t)(int8_t)disp))
		return -1;
	return 0;
}

/* lea r64, [base+disp8] — GAS: lea 2(%rsi),%rdi → 48 8d 7e 02
 * REX.W (+R/+B); 8D; ModRM mod=01 reg=dst r/m=base; disp8.
 * Refuse rsp/rbp base (SIB / mod=00 specials — not proven here).
 */
static int enc_lea_base_disp(sa_unit_t *u, int dst, int base,
			     int64_t disp) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (base == 4 || base == 5) {
		snprintf(u->err, sizeof(u->err),
			 "lea [rsp|rbp+disp] not in phase-1");
		return -1;
	}
	if (disp < -128 || disp > 127) {
		snprintf(u->err, sizeof(u->err),
			 "lea disp out of imm8 range");
		return -1;
	}
	if (dst >= 8)
		rex |= 0x04; /* R */
	if (base >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0x40 | ((dst & 7) << 3) | (base & 7));
	if (emit(u, rex) || emit(u, 0x8D) || emit(u, modrm) ||
	    emit(u, (uint8_t)(int8_t)disp))
		return -1;
	return 0;
}

/* lea r64, [base+index] scale=1 — GAS: lea (%rax,%rcx,1),%rdi
 * → 48 8d 3c 08. ModRM mod=00 r/m=4 (SIB); SIB ss=00.
 * Refuse index=rsp (SIB none); base=rbp (mod=00+SIB base=5
 * means no base + disp32 — not this form).
 */
static int enc_lea_base_index(sa_unit_t *u, int dst, int base,
			      int index) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	uint8_t sib;
	if (index == 4) {
		snprintf(u->err, sizeof(u->err),
			 "lea [reg+rsp] not in phase-1");
		return -1;
	}
	if (base == 5) {
		snprintf(u->err, sizeof(u->err),
			 "lea [rbp+reg] not in phase-1");
		return -1;
	}
	if (dst >= 8)
		rex |= 0x04; /* R */
	if (index >= 8)
		rex |= 0x02; /* X */
	if (base >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0x00 | ((dst & 7) << 3) | 0x04);
	sib = (uint8_t)(((index & 7) << 3) | (base & 7));
	if (emit(u, rex) || emit(u, 0x8D) || emit(u, modrm) ||
	    emit(u, sib))
		return -1;
	return 0;
}

/* imul r64, imm — GAS: imul $2,%rdi → 48 6b ff 02
 * Intel 6B /r ib (imm8) or 69 /r id (imm32); ModRM reg=r/m=dst.
 * (2-op form is 3-op with same register twice.)
 */
static int enc_imul_imm(sa_unit_t *u, int rd, int64_t imm) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (rd >= 8)
		rex |= 0x05; /* R|B — same reg in /r and r/m */
	modrm = (uint8_t)(0xC0 | ((rd & 7) << 3) | (rd & 7));
	if (imm >= -128 && imm <= 127) {
		if (emit(u, rex) || emit(u, 0x6B) || emit(u, modrm) ||
		    emit(u, (uint8_t)(int8_t)imm))
			return -1;
		return 0;
	}
	if (imm < (int64_t)INT32_MIN || imm > (int64_t)INT32_MAX) {
		snprintf(u->err, sizeof(u->err),
			 "imul imm out of imm32 range");
		return -1;
	}
	if (emit(u, rex) || emit(u, 0x69) || emit(u, modrm) ||
	    emit_u32(u, (uint32_t)(int32_t)imm))
		return -1;
	return 0;
}

/* unary F7 /digit r64 — GAS: neg %rdi → 48 f7 df; not %rdi → 48 f7 d7
 * Intel F7 /3 (neg) /2 (not); REX.W (+B for r8–r15).
 */
static int enc_unary_f7_reg(sa_unit_t *u, int rd, int digit) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (rd >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((digit & 7) << 3) | (rd & 7));
	if (emit(u, rex) || emit(u, 0xF7) || emit(u, modrm))
		return -1;
	return 0;
}

static int enc_neg_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 3);
}

static int enc_not_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 2);
}

/* mul/imul/div/idiv r64 — GAS: mul %rsi → 48 f7 e6; idiv %rsi → 48 f7 fe
 * Intel F7 /4|/5|/6|/7; rdx:rax implicit.
 */
static int enc_mul_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 4);
}

static int enc_imul1_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 5);
}

static int enc_div_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 6);
}

static int enc_idiv_reg(sa_unit_t *u, int rd) {
	return enc_unary_f7_reg(u, rd, 7);
}

/* inc/dec r64 — GAS: inc %rdi → 48 ff c7; dec %rdi → 48 ff cf
 * Intel FF /0 (inc) /1 (dec); REX.W (+B for r8–r15).
 */
static int enc_incdec_reg(sa_unit_t *u, int rd, int digit) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (rd >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((digit & 7) << 3) | (rd & 7));
	if (emit(u, rex) || emit(u, 0xFF) || emit(u, modrm))
		return -1;
	return 0;
}

static int enc_inc_reg(sa_unit_t *u, int rd) {
	return enc_incdec_reg(u, rd, 0);
}

static int enc_dec_reg(sa_unit_t *u, int rd) {
	return enc_incdec_reg(u, rd, 1);
}

/* ALU r64, r64 — Intel dst,src → opcode with src in /r, dst in r/m
 * and=21 or=09 xor=31 mov=89 (also used by test=85)
 */
static int enc_alu_reg(sa_unit_t *u, int dst, int src, uint8_t op) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (src >= 8)
		rex |= 0x04; /* R */
	if (dst >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((src & 7) << 3) | (dst & 7));
	if (emit(u, rex) || emit(u, op) || emit(u, modrm))
		return -1;
	return 0;
}

/* mov r64, r64 — GAS: mov %rsi,%rdi → 48 89 f7
 * Intel 89 /r; src in /r, dst in r/m.
 */
static int enc_mov_reg(sa_unit_t *u, int dst, int src) {
	return enc_alu_reg(u, dst, src, 0x89);
}

/* xchg r64, r64 — GAS: xchg %rsi,%rdi → 48 87 f7;
 * xchg %rax,%rdi → 48 97 (90+rd); xchg %rax,%rax → 90.
 * Intel 87 /r (r1 in /r, r2 in r/m) or 90+rd when either is rax.
 */
static int enc_xchg_reg(sa_unit_t *u, int r1, int r2) {
	uint8_t rex;
	int other;

	if (r1 == 0 && r2 == 0)
		return emit(u, 0x90);

	if (r1 == 0 || r2 == 0) {
		other = (r1 == 0) ? r2 : r1;
		rex = 0x48;
		if (other >= 8)
			rex |= 0x01; /* B */
		return emit(u, rex) ||
		       emit(u, (uint8_t)(0x90 + (other & 7)));
	}

	/* 87 /r: r1 in /r, r2 in r/m */
	return enc_alu_reg(u, r2, r1, 0x87);
}

/* test r64, r64 — 85 /r */
static int enc_test_reg_reg(sa_unit_t *u, int r1, int r2) {
	return enc_alu_reg(u, r1, r2, 0x85);
}

/* test r64, imm32 — GAS: testq $1,%rdi → 48 f7 c7 01 00 00 00
 * Intel F7 /0 id (no imm8 form for test).
 */
static int enc_test_imm(sa_unit_t *u, int rd, int64_t imm) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (imm < (int64_t)INT32_MIN || imm > (int64_t)INT32_MAX) {
		snprintf(u->err, sizeof(u->err),
			 "test imm out of imm32 range");
		return -1;
	}
	if (rd >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | (0 << 3) | (rd & 7));
	if (emit(u, rex) || emit(u, 0xF7) || emit(u, modrm) ||
	    emit_u32(u, (uint32_t)(int32_t)imm))
		return -1;
	return 0;
}

/* setcc r8 — GAS: sete %al → 0f 94 c0; sete %dil → 40 0f 94 c7
 * Intel 0F 9x /0; REX 0x40 when targeting sil/dil/bpl/spl.
 */
static int enc_setcc_r8(sa_unit_t *u, uint8_t op, int r8) {
	uint8_t modrm = (uint8_t)(0xC0 | (r8 & 7));
	if (r8 >= 4) {
		if (emit(u, 0x40))
			return -1;
	}
	if (emit(u, 0x0F) || emit(u, op) || emit(u, modrm))
		return -1;
	return 0;
}

/* movzbq/movzx r64, r8 — GAS: movzbq %al,%rdi → 48 0f b6 f8
 * Intel 0F B6 /r; dest in /r, src r8 in r/m; REX.W.
 */
static int enc_movzbq(sa_unit_t *u, int dst, int src8) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (dst >= 8)
		rex |= 0x04; /* R */
	modrm = (uint8_t)(0xC0 | ((dst & 7) << 3) | (src8 & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xB6) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

/* movsbq/movsx r64, r8 — GAS: movsbq %al,%rdi → 48 0f be f8
 * Intel 0F BE /r; dest in /r, src r8 in r/m; REX.W.
 */
static int enc_movsbq(sa_unit_t *u, int dst, int src8) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (dst >= 8)
		rex |= 0x04; /* R */
	modrm = (uint8_t)(0xC0 | ((dst & 7) << 3) | (src8 & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xBE) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

/* bsf/bsr r64, r64 — GAS: bsf %rsi,%rdi → 48 0f bc fe
 * Intel 0F BC/BD /r; dest in /r, src in r/m; REX.W.
 */
static int enc_bsf_reg(sa_unit_t *u, int dst, int src) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (dst >= 8)
		rex |= 0x04; /* R */
	if (src >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((dst & 7) << 3) | (src & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xBC) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

static int enc_bsr_reg(sa_unit_t *u, int dst, int src) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (dst >= 8)
		rex |= 0x04; /* R */
	if (src >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((dst & 7) << 3) | (src & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, 0xBD) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

/* cmovcc r64, r64 — GAS: cmove %rsi,%rdi → 48 0f 44 fe
 * Intel 0F 4x /r; dest in /r, src in r/m; REX.W.
 */
static int enc_cmov_reg(sa_unit_t *u, int dst, int src, uint8_t op) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (dst >= 8)
		rex |= 0x04; /* R */
	if (src >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((dst & 7) << 3) | (src & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, op) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

/* bt/bts/btr/btc r64, r64 — GAS: bt %rcx,%rsi → 48 0f a3 ce
 * Intel 0F A3/AB/B3/BB /r; offset in /r, base in r/m; REX.W.
 */
static int enc_bt_family(sa_unit_t *u, int base, int offset,
			 uint8_t op) {
	uint8_t rex = 0x48;
	uint8_t modrm;
	if (offset >= 8)
		rex |= 0x04; /* R */
	if (base >= 8)
		rex |= 0x01; /* B */
	modrm = (uint8_t)(0xC0 | ((offset & 7) << 3) | (base & 7));
	if (emit(u, rex) || emit(u, 0x0F) || emit(u, op) ||
	    emit(u, modrm))
		return -1;
	return 0;
}

static int enc_bt_reg(sa_unit_t *u, int base, int offset) {
	return enc_bt_family(u, base, offset, 0xA3);
}

static int enc_bts_reg(sa_unit_t *u, int base, int offset) {
	return enc_bt_family(u, base, offset, 0xAB);
}

static int enc_btr_reg(sa_unit_t *u, int base, int offset) {
	return enc_bt_family(u, base, offset, 0xB3);
}

static int enc_btc_reg(sa_unit_t *u, int base, int offset) {
	return enc_bt_family(u, base, offset, 0xBB);
}

static int jcc_opcode(const char *mnem, uint8_t *op) {
	static const struct {
		const char *name;
		uint8_t op;
	} map[] = {
		{ "je", 0x84 }, { "jz", 0x84 },
		{ "jne", 0x85 }, { "jnz", 0x85 },
		{ "jl", 0x8C }, { "jnge", 0x8C },
		{ "jle", 0x8E }, { "jng", 0x8E },
		{ "jg", 0x8F }, { "jnle", 0x8F },
		{ "jge", 0x8D }, { "jnl", 0x8D },
		{ NULL, 0 }
	};
	int i;
	for (i = 0; map[i].name; i++) {
		if (strcmp(mnem, map[i].name) == 0) {
			*op = map[i].op;
			return 0;
		}
	}
	return -1;
}

static int resolve_fixups(sa_unit_t *u) {
	int i;
	for (i = 0; i < g_nfixups; i++) {
		sa_sym_t *s = sym_find(u, g_fixups[i].name);
		int64_t rel;
		uint32_t off;
		uint32_t v;
		if (!s || !s->defined) {
			snprintf(u->err, sizeof(u->err),
				 "undefined symbol '%s'",
				 g_fixups[i].name);
			return -1;
		}
		rel = (int64_t)s->offset - (int64_t)g_fixups[i].next_pc;
		if (rel < (int64_t)INT32_MIN ||
		    rel > (int64_t)INT32_MAX) {
			snprintf(u->err, sizeof(u->err),
				 "rel32 out of range for '%s'",
				 g_fixups[i].name);
			return -1;
		}
		off = g_fixups[i].patch_off;
		v = (uint32_t)(int32_t)rel;
		u->code[off] = (uint8_t)v;
		u->code[off + 1] = (uint8_t)(v >> 8);
		u->code[off + 2] = (uint8_t)(v >> 16);
		u->code[off + 3] = (uint8_t)(v >> 24);
	}
	return 0;
}

/* ---- symbols ---- */

static sa_sym_t *sym_find(sa_unit_t *u, const char *name) {
	int i;
	for (i = 0; i < u->nsyms; i++) {
		if (strcmp(u->syms[i].name, name) == 0)
			return &u->syms[i];
	}
	return NULL;
}

static sa_sym_t *sym_get(sa_unit_t *u, const char *name) {
	sa_sym_t *s = sym_find(u, name);
	if (s)
		return s;
	if (u->nsyms >= SA_MAX_SYMS) {
		snprintf(u->err, sizeof(u->err), "too many symbols");
		return NULL;
	}
	s = &u->syms[u->nsyms++];
	memset(s, 0, sizeof(*s));
	snprintf(s->name, sizeof(s->name), "%s", name);
	return s;
}

/* ---- tokenize line ---- */

static void skip_ws(char **p) {
	while (**p && isspace((unsigned char)**p))
		(*p)++;
}

static void strip_comment(char *line) {
	char *p = line;
	while (*p) {
		if (*p == '#' ||
		    (p[0] == '/' && p[1] == '/')) {
			*p = '\0';
			return;
		}
		p++;
	}
}

static int parse_imm(const char *s, int64_t *out) {
	char *end = NULL;
	long long v;
	errno = 0;
	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		v = strtoll(s, &end, 16);
	else
		v = strtoll(s, &end, 10);
	if (errno || end == s || *end != '\0')
		return -1;
	*out = (int64_t)v;
	return 0;
}

static int take_word(char **p, char *buf, size_t n) {
	size_t i = 0;
	skip_ws(p);
	if (!**p)
		return 0;
	while (**p && !isspace((unsigned char)**p) && **p != ',' &&
	       **p != ':') {
		if (i + 1 >= n)
			return -1;
		buf[i++] = *(*p)++;
	}
	buf[i] = '\0';
	return i > 0 ? 1 : 0;
}

static int expect_comma(char **p) {
	skip_ws(p);
	if (**p != ',')
		return -1;
	(*p)++;
	return 0;
}

/* Parse [base+disp] or [base+index] (no spaces required; strip if any).
 * form: 1=base+disp, 2=base+index. Returns 0 on success.
 */
static int parse_lea_mem(char **p, int *base, int *index, int64_t *disp,
			 int *form) {
	char inner[96];
	char left[64], right[64];
	size_t n = 0;
	size_t ln;
	char *plus;
	int lb, rb;

	skip_ws(p);
	if (**p != '[')
		return -1;
	(*p)++;
	while (**p && **p != ']') {
		if (n + 1 >= sizeof(inner))
			return -1;
		if (!isspace((unsigned char)**p))
			inner[n++] = **p;
		(*p)++;
	}
	if (**p != ']')
		return -1;
	(*p)++;
	inner[n] = '\0';
	plus = strchr(inner, '+');
	if (!plus) {
		lb = reg_num(inner);
		if (lb < 0)
			return -1;
		*base = lb;
		*disp = 0;
		*form = 1;
		return 0;
	}
	if (plus == inner || !plus[1])
		return -1;
	*plus = '\0';
	ln = (size_t)(plus - inner);
	if (ln >= sizeof(left) || strlen(plus + 1) >= sizeof(right))
		return -1;
	memcpy(left, inner, ln);
	left[ln] = '\0';
	snprintf(right, sizeof(right), "%s", plus + 1);
	lb = reg_num(left);
	if (lb < 0)
		return -1;
	*base = lb;
	rb = reg_num(right);
	if (rb >= 0) {
		*index = rb;
		*form = 2;
		return 0;
	}
	if (parse_imm(right, disp))
		return -1;
	*form = 1;
	return 0;
}

/* ---- assemble one line ---- */

static int assemble_line(sa_unit_t *u, char *line, int lineno) {
	char *p = line;
	char w0[64], w1[64], w2[64], w3[64];
	int n0;

	strip_comment(line);
	skip_ws(&p);
	if (!*p)
		return 0;

	n0 = take_word(&p, w0, sizeof(w0));
	if (n0 < 0) {
		snprintf(u->err, sizeof(u->err),
			 "line %d: token too long", lineno);
		return -1;
	}
	skip_ws(&p);
	if (*p == ':') {
		sa_sym_t *s;
		p++;
		s = sym_get(u, w0);
		if (!s)
			return -1;
		if (s->defined) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: redefinition of '%s'",
				 lineno, w0);
			return -1;
		}
		s->defined = 1;
		s->offset = (uint32_t)u->code_len;
		skip_ws(&p);
		if (!*p)
			return 0;
		/* fall through: label + insn on same line */
		n0 = take_word(&p, w0, sizeof(w0));
		if (n0 <= 0)
			return 0;
	}

	if (strcmp(w0, ".text") == 0 || strcmp(w0, ".section") == 0)
		return 0; /* only .text exists in phase 1 */

	if (strcmp(w0, ".global") == 0 || strcmp(w0, ".globl") == 0) {
		sa_sym_t *s;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: .global needs a name", lineno);
			return -1;
		}
		s = sym_get(u, w1);
		if (!s)
			return -1;
		s->is_global = 1;
		return 0;
	}

	if (strcmp(w0, ".byte") == 0) {
		for (;;) {
			int64_t imm;

			skip_ws(&p);
			if (!*p)
				break;
			if (take_word(&p, w1, sizeof(w1)) <= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: .byte value", lineno);
				return -1;
			}
			if (parse_imm(w1, &imm)) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: bad .byte '%s'", lineno, w1);
				return -1;
			}
			if (imm < 0 || imm > 255) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: .byte out of range", lineno);
				return -1;
			}
			if (emit(u, (uint8_t)imm))
				return -1;
			skip_ws(&p);
			if (*p == ',') {
				p++;
				continue;
			}
			if (*p)
				break;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after .byte", lineno);
			return -1;
		}
		return 0;
	}

	if (strcmp(w0, "nop") == 0)
		return enc_nop(u);

	if (strcmp(w0, "syscall") == 0)
		return enc_syscall(u);

	if (strcmp(w0, "ret") == 0)
		return enc_ret(u);

	if (strcmp(w0, "leave") == 0) {
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after leave",
				 lineno);
			return -1;
		}
		return enc_leave(u);
	}

	if (strcmp(w0, "stc") == 0 || strcmp(w0, "clc") == 0 ||
	    strcmp(w0, "std") == 0 || strcmp(w0, "cld") == 0) {
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "stc") == 0)
			return enc_stc(u);
		if (strcmp(w0, "clc") == 0)
			return enc_clc(u);
		if (strcmp(w0, "std") == 0)
			return enc_std(u);
		return enc_cld(u);
	}

	if (strcmp(w0, "cqo") == 0 || strcmp(w0, "cqto") == 0) {
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		return enc_cqo(u);
	}

	if (strcmp(w0, "cdqe") == 0 || strcmp(w0, "cltq") == 0) {
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		return enc_cdqe(u);
	}

	if (strcmp(w0, "push") == 0) {
		int rd;
		int64_t imm;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: push reg|imm", lineno);
			return -1;
		}
		rd = reg_num(w1);
		if (rd >= 0)
			return enc_push_reg(u, rd);
		if (parse_imm(w1, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: push needs reg|imm", lineno);
			return -1;
		}
		return enc_push_imm(u, imm);
	}

	if (strcmp(w0, "pop") == 0) {
		int rd;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: pop reg", lineno);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		return enc_pop_reg(u, rd);
	}

	if (strcmp(w0, "call") == 0) {
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: call label", lineno);
			return -1;
		}
		if (reg_num(w1) >= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: call reg not in phase-1",
				 lineno);
			return -1;
		}
		if (!sym_get(u, w1))
			return -1;
		return enc_call_label(u, w1);
	}

	if (strcmp(w0, "jmp") == 0) {
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: jmp label", lineno);
			return -1;
		}
		if (reg_num(w1) >= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: jmp reg not in phase-1",
				 lineno);
			return -1;
		}
		if (!sym_get(u, w1))
			return -1;
		return enc_jmp_label(u, w1);
	}

	{
		uint8_t jcc_op;
		if (jcc_opcode(w0, &jcc_op) == 0) {
			if (take_word(&p, w1, sizeof(w1)) <= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: %s label", lineno, w0);
				return -1;
			}
			if (!sym_get(u, w1))
				return -1;
			return enc_jcc_label(u, jcc_op, w1);
		}
	}

	if (strcmp(w0, "shl") == 0 || strcmp(w0, "shr") == 0 ||
	    strcmp(w0, "sar") == 0 || strcmp(w0, "rol") == 0 ||
	    strcmp(w0, "ror") == 0 || strcmp(w0, "rcl") == 0 ||
	    strcmp(w0, "rcr") == 0) {
		int rd;
		int64_t imm;
		int digit;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, imm|cl", lineno, w0);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		if (strcmp(w0, "rol") == 0)
			digit = 0;
		else if (strcmp(w0, "ror") == 0)
			digit = 1;
		else if (strcmp(w0, "rcl") == 0)
			digit = 2;
		else if (strcmp(w0, "rcr") == 0)
			digit = 3;
		else if (strcmp(w0, "shl") == 0)
			digit = 4;
		else if (strcmp(w0, "shr") == 0)
			digit = 5;
		else
			digit = 7;
		if (strcmp(w2, "cl") == 0)
			return enc_shift_cl(u, rd, digit);
		if (parse_imm(w2, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: bad imm|cl '%s'", lineno, w2);
			return -1;
		}
		return enc_shift_imm(u, rd, imm, digit);
	}

	if (strcmp(w0, "shld") == 0 || strcmp(w0, "shrd") == 0) {
		int dest, src;
		int64_t imm;
		uint8_t op_imm = (strcmp(w0, "shld") == 0) ? 0xA4 : 0xAC;
		uint8_t op_cl = (strcmp(w0, "shld") == 0) ? 0xA5 : 0xAD;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w3, sizeof(w3)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, reg, imm|cl",
				 lineno, w0);
			return -1;
		}
		dest = reg_num(w1);
		src = reg_num(w2);
		if (dest < 0 || src < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s needs two regs",
				 lineno, w0);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w3, "cl") == 0)
			return enc_shxd_cl(u, dest, src, op_cl);
		if (parse_imm(w3, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: bad imm|cl '%s'",
				 lineno, w3);
			return -1;
		}
		return enc_shxd_imm(u, dest, src, imm, op_imm);
	}

	if (strcmp(w0, "imul") == 0) {
		int rd;
		int64_t imm;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: imul reg[, imm]", lineno);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (!*p)
			return enc_imul1_reg(u, rd);
		if (expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: imul reg, imm", lineno);
			return -1;
		}
		if (reg_num(w2) >= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: imul reg,reg not in phase-1",
				 lineno);
			return -1;
		}
		if (parse_imm(w2, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: bad imm '%s'", lineno, w2);
			return -1;
		}
		return enc_imul_imm(u, rd, imm);
	}

	if (strcmp(w0, "mul") == 0 || strcmp(w0, "div") == 0 ||
	    strcmp(w0, "idiv") == 0) {
		int rd;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg", lineno, w0);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "mul") == 0)
			return enc_mul_reg(u, rd);
		if (strcmp(w0, "div") == 0)
			return enc_div_reg(u, rd);
		return enc_idiv_reg(u, rd);
	}

	if (strcmp(w0, "neg") == 0 || strcmp(w0, "not") == 0) {
		int rd;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg", lineno, w0);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "not") == 0)
			return enc_not_reg(u, rd);
		return enc_neg_reg(u, rd);
	}

	if (strcmp(w0, "xchg") == 0) {
		int r1, r2;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: xchg reg, reg", lineno);
			return -1;
		}
		r1 = reg_num(w1);
		r2 = reg_num(w2);
		if (r1 < 0 || r2 < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: xchg needs two regs", lineno);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after xchg",
				 lineno);
			return -1;
		}
		return enc_xchg_reg(u, r1, r2);
	}

	if (strcmp(w0, "bsf") == 0 || strcmp(w0, "bsr") == 0) {
		int dst, src;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, reg", lineno, w0);
			return -1;
		}
		dst = reg_num(w1);
		src = reg_num(w2);
		if (dst < 0 || src < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s needs two regs",
				 lineno, w0);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "bsf") == 0)
			return enc_bsf_reg(u, dst, src);
		return enc_bsr_reg(u, dst, src);
	}

	if (strcmp(w0, "bt") == 0 || strcmp(w0, "bts") == 0 ||
	    strcmp(w0, "btr") == 0 || strcmp(w0, "btc") == 0) {
		int base, offset;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, reg", lineno, w0);
			return -1;
		}
		base = reg_num(w1);
		offset = reg_num(w2);
		if (base < 0 || offset < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s needs two regs",
				 lineno, w0);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "bt") == 0)
			return enc_bt_reg(u, base, offset);
		if (strcmp(w0, "bts") == 0)
			return enc_bts_reg(u, base, offset);
		if (strcmp(w0, "btr") == 0)
			return enc_btr_reg(u, base, offset);
		return enc_btc_reg(u, base, offset);
	}

	if (strcmp(w0, "inc") == 0 || strcmp(w0, "dec") == 0) {
		int rd;
		if (take_word(&p, w1, sizeof(w1)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg", lineno, w0);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		if (strcmp(w0, "inc") == 0)
			return enc_inc_reg(u, rd);
		return enc_dec_reg(u, rd);
	}

	if (strcmp(w0, "movzx") == 0) {
		int dst, base, index, form;
		int64_t disp;
		int szbyte;

		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: movzx reg, byte|word [mem]",
				 lineno);
			return -1;
		}
		dst = reg_num(w1);
		if (dst < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (strncmp(p, "byte", 4) == 0 &&
		    isspace((unsigned char)p[4])) {
			p += 4;
			szbyte = 1;
		} else if (strncmp(p, "word", 4) == 0 &&
			   isspace((unsigned char)p[4])) {
		 p += 4;
		 szbyte = 0;
		} else {
			snprintf(u->err, sizeof(u->err),
				 "line %d: movzx needs byte|word [mem]",
				 lineno);
			return -1;
		}
		if (parse_lea_mem(&p, &base, &index, &disp, &form)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: movzx needs [reg+disp]|[reg+reg]",
				 lineno);
			return -1;
		}
		if (form == 2) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: movzx [reg+reg] not in phase-1",
				 lineno);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after movzx",
				 lineno);
			return -1;
		}
		if (szbyte)
			return enc_movzx_byte_mem(u, dst, base, disp);
		return enc_movzx_word_mem(u, dst, base, disp);
	}

	if (strcmp(w0, "lea") == 0) {
		int dst, base, index, form;
		int64_t disp;

		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: lea reg, [mem]|label", lineno);
			return -1;
		}
		dst = reg_num(w1);
		if (dst < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		skip_ws(&p);
		if (*p != '[') {
			if (take_word(&p, w2, sizeof(w2)) <= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: lea reg, label", lineno);
				return -1;
			}
			if (reg_num(w2) >= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: lea label expected",
					 lineno);
				return -1;
			}
			if (!sym_get(u, w2))
				return -1;
			skip_ws(&p);
			if (*p) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: trailing junk after lea",
					 lineno);
				return -1;
			}
			return enc_lea_label(u, dst, w2);
		}
		if (parse_lea_mem(&p, &base, &index, &disp, &form)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: lea needs [reg+disp]|[reg+reg]",
				 lineno);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after lea",
				 lineno);
			return -1;
		}
		if (form == 1)
			return enc_lea_base_disp(u, dst, base, disp);
		return enc_lea_base_index(u, dst, base, index);
	}

	if (strcmp(w0, "add") == 0 || strcmp(w0, "sub") == 0 ||
	    strcmp(w0, "adc") == 0 || strcmp(w0, "sbb") == 0 ||
	    strcmp(w0, "cmp") == 0 || strcmp(w0, "and") == 0 ||
	    strcmp(w0, "or") == 0 || strcmp(w0, "xor") == 0) {
		int rd, rs;
		int64_t imm;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, imm|reg", lineno, w0);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		rs = reg_num(w2);
		if (rs >= 0) {
			/* reg,reg — and/or/xor/add/sub/adc/sbb/cmp */
			if (strcmp(w0, "and") == 0)
				return enc_alu_reg(u, rd, rs, 0x21);
			if (strcmp(w0, "or") == 0)
				return enc_alu_reg(u, rd, rs, 0x09);
			if (strcmp(w0, "xor") == 0)
				return enc_alu_reg(u, rd, rs, 0x31);
			if (strcmp(w0, "add") == 0)
				return enc_alu_reg(u, rd, rs, 0x01);
			if (strcmp(w0, "sub") == 0)
				return enc_alu_reg(u, rd, rs, 0x29);
			if (strcmp(w0, "adc") == 0)
				return enc_alu_reg(u, rd, rs, 0x11);
			if (strcmp(w0, "sbb") == 0)
				return enc_alu_reg(u, rd, rs, 0x19);
			if (strcmp(w0, "cmp") == 0)
				return enc_alu_reg(u, rd, rs, 0x39);
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg,reg not in phase-1",
				 lineno, w0);
			return -1;
		}
		if (parse_imm(w2, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: bad imm '%s'", lineno, w2);
			return -1;
		}
		if (strcmp(w0, "add") == 0)
			return enc_add_imm(u, rd, imm);
		if (strcmp(w0, "sub") == 0)
			return enc_sub_imm(u, rd, imm);
		if (strcmp(w0, "adc") == 0)
			return enc_adc_imm(u, rd, imm);
		if (strcmp(w0, "sbb") == 0)
			return enc_sbb_imm(u, rd, imm);
		if (strcmp(w0, "and") == 0)
			return enc_and_imm(u, rd, imm);
		if (strcmp(w0, "or") == 0)
			return enc_or_imm(u, rd, imm);
		if (strcmp(w0, "xor") == 0)
			return enc_xor_imm(u, rd, imm);
		return enc_cmp_imm(u, rd, imm);
	}

	if (strcmp(w0, "test") == 0) {
		int r1, r2;
		int64_t imm;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: test reg, imm|reg", lineno);
			return -1;
		}
		r1 = reg_num(w1);
		if (r1 < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		r2 = reg_num(w2);
		if (r2 >= 0)
			return enc_test_reg_reg(u, r1, r2);
		if (parse_imm(w2, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: test needs imm|reg", lineno);
			return -1;
		}
		return enc_test_imm(u, r1, imm);
	}

	{
		uint8_t cmov_op = 0;
		int is_cmov = 0;
		if (strcmp(w0, "cmove") == 0 ||
		    strcmp(w0, "cmovz") == 0) {
			cmov_op = 0x44;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovne") == 0 ||
			   strcmp(w0, "cmovnz") == 0) {
			cmov_op = 0x45;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovl") == 0 ||
			   strcmp(w0, "cmovnge") == 0) {
			cmov_op = 0x4C;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovg") == 0 ||
			   strcmp(w0, "cmovnle") == 0) {
			cmov_op = 0x4F;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovle") == 0 ||
			   strcmp(w0, "cmovng") == 0) {
			cmov_op = 0x4E;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovge") == 0 ||
			   strcmp(w0, "cmovnl") == 0) {
			cmov_op = 0x4D;
			is_cmov = 1;
		} else if (strcmp(w0, "cmova") == 0 ||
			   strcmp(w0, "cmovnbe") == 0) {
			cmov_op = 0x47;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovb") == 0 ||
			   strcmp(w0, "cmovnae") == 0 ||
			   strcmp(w0, "cmovc") == 0) {
			cmov_op = 0x42;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovae") == 0 ||
			   strcmp(w0, "cmovnb") == 0 ||
			   strcmp(w0, "cmovnc") == 0) {
			cmov_op = 0x43;
			is_cmov = 1;
		} else if (strcmp(w0, "cmovbe") == 0 ||
			   strcmp(w0, "cmovna") == 0) {
			cmov_op = 0x46;
			is_cmov = 1;
		}
		if (is_cmov) {
			int dst, src;
			if (take_word(&p, w1, sizeof(w1)) <= 0 ||
			    expect_comma(&p) ||
			    take_word(&p, w2, sizeof(w2)) <= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: %s reg, reg",
					 lineno, w0);
				return -1;
			}
			dst = reg_num(w1);
			src = reg_num(w2);
			if (dst < 0 || src < 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: %s needs two regs",
					 lineno, w0);
				return -1;
			}
			skip_ws(&p);
			if (*p) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: trailing junk after %s",
					 lineno, w0);
				return -1;
			}
			return enc_cmov_reg(u, dst, src, cmov_op);
		}
	}

	{
		uint8_t set_op = 0;
		int is_set = 0;
		if (strcmp(w0, "sete") == 0 || strcmp(w0, "setz") == 0) {
			set_op = 0x94;
			is_set = 1;
		} else if (strcmp(w0, "setne") == 0 ||
			   strcmp(w0, "setnz") == 0) {
			set_op = 0x95;
			is_set = 1;
		} else if (strcmp(w0, "setl") == 0 ||
			   strcmp(w0, "setnge") == 0) {
			set_op = 0x9C;
			is_set = 1;
		} else if (strcmp(w0, "setle") == 0 ||
			   strcmp(w0, "setng") == 0) {
			set_op = 0x9E;
			is_set = 1;
		} else if (strcmp(w0, "setg") == 0 ||
			   strcmp(w0, "setnle") == 0) {
			set_op = 0x9F;
			is_set = 1;
		} else if (strcmp(w0, "setge") == 0 ||
			   strcmp(w0, "setnl") == 0) {
			set_op = 0x9D;
			is_set = 1;
		}
		if (is_set) {
			int r8;
			if (take_word(&p, w1, sizeof(w1)) <= 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: %s r8", lineno, w0);
				return -1;
			}
			r8 = reg8_num(w1);
			if (r8 < 0) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: %s needs al..dil",
					 lineno, w0);
				return -1;
			}
			skip_ws(&p);
			if (*p) {
				snprintf(u->err, sizeof(u->err),
					 "line %d: trailing junk after %s",
					 lineno, w0);
				return -1;
			}
			return enc_setcc_r8(u, set_op, r8);
		}
	}

	if (strcmp(w0, "movzbq") == 0 || strcmp(w0, "movzx") == 0) {
		int dst, src8;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, r8", lineno, w0);
			return -1;
		}
		dst = reg_num(w1);
		src8 = reg8_num(w2);
		if (dst < 0 || src8 < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s needs reg, al..dil",
				 lineno, w0);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		return enc_movzbq(u, dst, src8);
	}

	if (strcmp(w0, "movsbq") == 0 || strcmp(w0, "movsx") == 0) {
		int dst, src8;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s reg, r8", lineno, w0);
			return -1;
		}
		dst = reg_num(w1);
		src8 = reg8_num(w2);
		if (dst < 0 || src8 < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: %s needs reg, al..dil",
				 lineno, w0);
			return -1;
		}
		skip_ws(&p);
		if (*p) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: trailing junk after %s",
				 lineno, w0);
			return -1;
		}
		return enc_movsbq(u, dst, src8);
	}

	if (strcmp(w0, "mov") == 0) {
		int rd, rs;
		int64_t imm;
		if (take_word(&p, w1, sizeof(w1)) <= 0 ||
		    expect_comma(&p) ||
		    take_word(&p, w2, sizeof(w2)) <= 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: mov reg, imm|reg", lineno);
			return -1;
		}
		rd = reg_num(w1);
		if (rd < 0) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: unknown reg '%s'", lineno, w1);
			return -1;
		}
		rs = reg_num(w2);
		if (rs >= 0)
			return enc_mov_reg(u, rd, rs);
		if (parse_imm(w2, &imm)) {
			snprintf(u->err, sizeof(u->err),
				 "line %d: bad imm '%s'", lineno, w2);
			return -1;
		}
		return enc_mov_imm(u, rd, imm);
	}

	snprintf(u->err, sizeof(u->err),
		 "line %d: unknown opcode/directive '%s'", lineno, w0);
	return -1;
}

int sa_assemble_file(const char *path, sa_unit_t *u) {
	FILE *f;
	char line[SA_MAX_LINE];
	int lineno = 0;
	int i;

	memset(u, 0, sizeof(*u));
	g_nfixups = 0;
	f = fopen(path, "r");
	if (!f) {
		snprintf(u->err, sizeof(u->err), "open %s: %s", path,
			 strerror(errno));
		return -1;
	}
	while (fgets(line, sizeof(line), f)) {
		lineno++;
		if (assemble_line(u, line, lineno)) {
			fclose(f);
			return -1;
		}
	}
	fclose(f);
	for (i = 0; i < u->nsyms; i++) {
		if (!u->syms[i].defined) {
			snprintf(u->err, sizeof(u->err),
				 "undefined symbol '%s'", u->syms[i].name);
			return -1;
		}
	}
	if (resolve_fixups(u))
		return -1;
	if (u->code_len == 0) {
		snprintf(u->err, sizeof(u->err), "empty .text");
		return -1;
	}
	return 0;
}

/* ---- ELF64 ET_REL ---- */

#pragma pack(push, 1)
typedef struct {
	unsigned char e_ident[16];
	uint16_t e_type;
	uint16_t e_machine;
	uint32_t e_version;
	uint64_t e_entry;
	uint64_t e_phoff;
	uint64_t e_shoff;
	uint32_t e_flags;
	uint16_t e_ehsize;
	uint16_t e_phentsize;
	uint16_t e_phnum;
	uint16_t e_shentsize;
	uint16_t e_shnum;
	uint16_t e_shstrndx;
} Elf64_Ehdr;

typedef struct {
	uint32_t sh_name;
	uint32_t sh_type;
	uint64_t sh_flags;
	uint64_t sh_addr;
	uint64_t sh_offset;
	uint64_t sh_size;
	uint32_t sh_link;
	uint32_t sh_info;
	uint64_t sh_addralign;
	uint64_t sh_entsize;
} Elf64_Shdr;

typedef struct {
	uint32_t st_name;
	unsigned char st_info;
	unsigned char st_other;
	uint16_t st_shndx;
	uint64_t st_value;
	uint64_t st_size;
} Elf64_Sym;
#pragma pack(pop)

#define ET_REL 1
#define EM_X86_64 62
#define SHT_NULL 0
#define SHT_PROGBITS 1
#define SHT_SYMTAB 2
#define SHT_STRTAB 3
#define SHF_ALLOC 0x2
#define SHF_EXECINSTR 0x4
#define STB_LOCAL 0
#define STB_GLOBAL 1
#define STT_NOTYPE 0
#define STT_SECTION 3
#define ELF64_ST_INFO(b, t) (((b) << 4) + ((t)&0xf))

static size_t strtab_add(char *tab, size_t *len, size_t cap,
			 const char *s) {
	size_t off = *len;
	size_t n = strlen(s) + 1;
	if (off + n > cap)
		return (size_t)-1;
	memcpy(tab + off, s, n);
	*len += n;
	return off;
}

int sa_write_bin(const char *path, const sa_unit_t *u) {
	FILE *f = fopen(path, "wb");
	if (!f)
		return -1;
	if (fwrite(u->code, 1, u->code_len, f) != u->code_len) {
		fclose(f);
		return -1;
	}
	fclose(f);
	return 0;
}

int sa_write_elf_o(const char *path, const sa_unit_t *u) {
	/* sections: 0 null, 1 .text, 2 .shstrtab, 3 .symtab, 4 .strtab */
	enum { SH_NULL = 0, SH_TEXT = 1, SH_SHSTR = 2, SH_SYM = 3,
	       SH_STR = 4, SH_NUM = 5 };
	char shstr[64];
	size_t shstr_len = 1; /* leading NUL */
	char strtab[4096];
	size_t str_len = 1;
	Elf64_Sym syms[SA_MAX_SYMS + 4];
	int nsym = 0;
	Elf64_Ehdr eh;
	Elf64_Shdr sh[SH_NUM];
	size_t off;
	size_t text_off, shstr_off, sym_off, str_off, shoff;
	size_t i;
	FILE *f;
	uint32_t name_text, name_shstr, name_sym, name_str;

	memset(shstr, 0, sizeof(shstr));
	memset(strtab, 0, sizeof(strtab));
	memset(syms, 0, sizeof(syms));
	memset(&eh, 0, sizeof(eh));
	memset(sh, 0, sizeof(sh));

	name_text = (uint32_t)strtab_add(shstr, &shstr_len, sizeof(shstr),
					 ".text");
	name_shstr = (uint32_t)strtab_add(shstr, &shstr_len, sizeof(shstr),
					  ".shstrtab");
	name_sym = (uint32_t)strtab_add(shstr, &shstr_len, sizeof(shstr),
					".symtab");
	name_str = (uint32_t)strtab_add(shstr, &shstr_len, sizeof(shstr),
					".strtab");
	if (name_text == (uint32_t)-1 || name_shstr == (uint32_t)-1 ||
	    name_sym == (uint32_t)-1 || name_str == (uint32_t)-1)
		return -1;

	/* UND + section + locals then globals (ELF binding order) */
	syms[nsym++] = (Elf64_Sym){0}; /* NULL */
	{
		Elf64_Sym sec = {0};
		sec.st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION);
		sec.st_shndx = SH_TEXT;
		syms[nsym++] = sec;
	}
	for (i = 0; i < (size_t)u->nsyms; i++) {
		Elf64_Sym s;
		size_t noff;
		if (u->syms[i].is_global)
			continue;
		memset(&s, 0, sizeof(s));
		noff = strtab_add(strtab, &str_len, sizeof(strtab),
				  u->syms[i].name);
		if (noff == (size_t)-1)
			return -1;
		s.st_name = (uint32_t)noff;
		s.st_value = u->syms[i].offset;
		s.st_size = 0;
		s.st_shndx = SH_TEXT;
		s.st_info = ELF64_ST_INFO(STB_LOCAL, STT_NOTYPE);
		syms[nsym++] = s;
	}
	for (i = 0; i < (size_t)u->nsyms; i++) {
		Elf64_Sym s;
		size_t noff;
		if (!u->syms[i].is_global)
			continue;
		memset(&s, 0, sizeof(s));
		noff = strtab_add(strtab, &str_len, sizeof(strtab),
				  u->syms[i].name);
		if (noff == (size_t)-1)
			return -1;
		s.st_name = (uint32_t)noff;
		s.st_value = u->syms[i].offset;
		s.st_size = 0;
		s.st_shndx = SH_TEXT;
		s.st_info = ELF64_ST_INFO(STB_GLOBAL, STT_NOTYPE);
		syms[nsym++] = s;
	}

	off = sizeof(Elf64_Ehdr);
	text_off = off;
	off += u->code_len;
	shstr_off = off;
	off += shstr_len;
	sym_off = off;
	off += (size_t)nsym * sizeof(Elf64_Sym);
	str_off = off;
	off += str_len;
	shoff = (off + 7) & ~(size_t)7;

	eh.e_ident[0] = 0x7f;
	eh.e_ident[1] = 'E';
	eh.e_ident[2] = 'L';
	eh.e_ident[3] = 'F';
	eh.e_ident[4] = 2; /* ELFCLASS64 */
	eh.e_ident[5] = 1; /* ELFDATA2LSB */
	eh.e_ident[6] = 1; /* EV_CURRENT */
	eh.e_type = ET_REL;
	eh.e_machine = EM_X86_64;
	eh.e_version = 1;
	eh.e_ehsize = sizeof(Elf64_Ehdr);
	eh.e_shentsize = sizeof(Elf64_Shdr);
	eh.e_shnum = SH_NUM;
	eh.e_shstrndx = SH_SHSTR;
	eh.e_shoff = shoff;

	sh[SH_TEXT].sh_name = name_text;
	sh[SH_TEXT].sh_type = SHT_PROGBITS;
	sh[SH_TEXT].sh_flags = SHF_ALLOC | SHF_EXECINSTR;
	sh[SH_TEXT].sh_offset = text_off;
	sh[SH_TEXT].sh_size = u->code_len;
	sh[SH_TEXT].sh_addralign = 16;

	sh[SH_SHSTR].sh_name = name_shstr;
	sh[SH_SHSTR].sh_type = SHT_STRTAB;
	sh[SH_SHSTR].sh_offset = shstr_off;
	sh[SH_SHSTR].sh_size = shstr_len;
	sh[SH_SHSTR].sh_addralign = 1;

	sh[SH_SYM].sh_name = name_sym;
	sh[SH_SYM].sh_type = SHT_SYMTAB;
	sh[SH_SYM].sh_offset = sym_off;
	sh[SH_SYM].sh_size = (uint64_t)nsym * sizeof(Elf64_Sym);
	sh[SH_SYM].sh_link = SH_STR;
	sh[SH_SYM].sh_info = 2; /* one past last local (NULL+section) */
	sh[SH_SYM].sh_addralign = 8;
	sh[SH_SYM].sh_entsize = sizeof(Elf64_Sym);

	sh[SH_STR].sh_name = name_str;
	sh[SH_STR].sh_type = SHT_STRTAB;
	sh[SH_STR].sh_offset = str_off;
	sh[SH_STR].sh_size = str_len;
	sh[SH_STR].sh_addralign = 1;

	/* If any locals after section, sh_info must be correct.
	 * Phase-1: all user symbols are typically global (_start).
	 * Count locals for sh_info. */
	{
		int last_local = 1; /* index of last local + 1 */
		int si;
		for (si = 1; si < nsym; si++) {
			int bind = (syms[si].st_info >> 4) & 0xf;
			if (bind == STB_LOCAL)
				last_local = si + 1;
		}
		sh[SH_SYM].sh_info = (uint32_t)last_local;
	}

	f = fopen(path, "wb");
	if (!f)
		return -1;
	if (fwrite(&eh, 1, sizeof(eh), f) != sizeof(eh))
		goto fail;
	if (fwrite(u->code, 1, u->code_len, f) != u->code_len)
		goto fail;
	if (fwrite(shstr, 1, shstr_len, f) != shstr_len)
		goto fail;
	if (fwrite(syms, sizeof(Elf64_Sym), (size_t)nsym, f) !=
	    (size_t)nsym)
		goto fail;
	if (fwrite(strtab, 1, str_len, f) != str_len)
		goto fail;
	while ((size_t)ftell(f) < shoff) {
		if (fputc(0, f) == EOF)
			goto fail;
	}
	if (fwrite(sh, sizeof(Elf64_Shdr), SH_NUM, f) != SH_NUM)
		goto fail;
	fclose(f);
	return 0;
fail:
	fclose(f);
	return -1;
}
