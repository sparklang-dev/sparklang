# sparkasm — isolated from engine/ide GAS tree
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11 -Iinclude
LD      ?= ld
OBJDUMP ?= objdump
NM      ?= nm

.PHONY: all clean test

all: sparkasm

sparkasm: src/main.c src/sparkasm.c include/sparkasm.h
	$(CC) $(CFLAGS) -o $@ src/main.c src/sparkasm.c

clean:
	rm -f sparkasm
	rm -rf out
	mkdir -p out

test: sparkasm
	./tests/test_exit42.sh
	./tests/test_callret.sh
	./tests/test_leave.sh
	./tests/test_jmp.sh
	./tests/test_cmpjcc.sh
	./tests/test_cmprr.sh
	./tests/test_addsub.sh
	./tests/test_addsubrr.sh
	./tests/test_adc.sh
	./tests/test_sbb.sh
	./tests/test_logic.sh
	./tests/test_shift.sh
	./tests/test_shiftcl.sh
	./tests/test_sar.sh
	./tests/test_rol.sh
	./tests/test_ror.sh
	./tests/test_stc.sh
	./tests/test_clc.sh
	./tests/test_rcl.sh
	./tests/test_rcr.sh
	./tests/test_bsf.sh
	./tests/test_bsr.sh
	./tests/test_std.sh
	./tests/test_cld.sh
	./tests/test_bt.sh
	./tests/test_bts.sh
	./tests/test_btr.sh
	./tests/test_btc.sh
	./tests/test_shld.sh
	./tests/test_shrd.sh
	./tests/test_cmovz.sh
	./tests/test_cmovnz.sh
	./tests/test_cmovl.sh
	./tests/test_cmovg.sh
	./tests/test_cmovle.sh
	./tests/test_cmovge.sh
	./tests/test_cmova.sh
	./tests/test_cmovb.sh
	./tests/test_cmovae.sh
	./tests/test_cmovbe.sh
	./tests/test_lea.sh
	./tests/test_imul.sh
	./tests/test_mul.sh
	./tests/test_idiv.sh
	./tests/test_neg.sh
	./tests/test_movrr.sh
	./tests/test_incdec.sh
	./tests/test_pushimm.sh
	./tests/test_xchg.sh
	./tests/test_not.sh
	./tests/test_cqo.sh
	./tests/test_cdqe.sh
	./tests/test_sete.sh
	./tests/test_setl.sh
	./tests/test_testimm.sh
	./tests/test_movzbq.sh
	./tests/test_movsbq.sh
	./tests/test_byte_lea.sh
