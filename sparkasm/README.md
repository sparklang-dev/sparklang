# sparkasm — Spark-native assembler (lane C)

**SoT for this tree:** Spark-asm IR (`.sasm`), not GAS `.s` syntax.

GAS (`asm/*.s` → `as`) remains the current scaffold for `./spark`.
This assembler is the path that replaces hand-authored GAS over time
(self-host A + bootstrap B). It does **not** invent a full Intel manual —
phase-1 encodes the exit vertical plus control-flow and ALU ops needed
for a self-host path (push/pop/push-imm/call/ret/jmp/cmp/test/jcc/add/sub/
and/or/xor + shl/shr imm + lea [reg+disp]|[reg+reg] + imul reg,imm +
neg/not/inc/dec/xchg reg + cqo/cdqe + mov reg,reg).

## Build

```bash
make -C sparkasm
# or from repo root:
make sparkasm
```

Binary: `sparkasm/sparkasm` (also copied to repo root as `sparkasm` optional).

## Usage

```bash
./sparkasm/sparkasm -o out/exit42.o fixtures/exit42.sasm
./sparkasm/sparkasm --format=bin -o out/exit42.bin fixtures/exit42.sasm
ld -o out/exit42 out/exit42.o   # link relocatable
./out/exit42; echo $?           # → 42
```

## Phase-1 IR

| Form | Notes |
|------|--------|
| `#` / `//` comments | line comments |
| `.text` | code section (only section today) |
| `.global name` / `.globl` | export symbol |
| `label:` | define label at current PC |
| `mov reg, imm` | 64-bit; imm decimal or `0x` hex |
| `mov reg, reg` | `89` /r; GAS-proven (`48 89 f7` for rdi←rsi) |
| `push reg` / `pop reg` | `50+rd` / `58+rd`; REX.B for r8–r15 |
| `push imm` | `6A` ib (imm8) or `68` id (imm32); GAS-proven (`6a 2a` for 42) |
| `call label` | near `E8 rel32` (same-section; assembled fixup) |
| `jmp label` | near `E9 rel32` (same-section; assembled fixup) |
| `je`/`jz` … `jge`/`jnl` | near `0F 8x rel32` (aliases paired) |
| `cmp reg, imm\|reg` | `81`/`83` /7 or `39` /r; GAS `48 39 f7` |
| `add reg, imm\|reg` | `81`/`83` /0 or `01` /r; GAS `48 01 f7` |
| `sub reg, imm\|reg` | `81`/`83` /5 or `29` /r; GAS `48 29 f7` |
| `adc reg, imm\|reg` | `81`/`83` /2 or `11` /r; GAS `48 11 f7` |
| `sbb reg, imm\|reg` | `81`/`83` /3 or `19` /r; GAS `48 19 f7` |
| `and reg, imm\|reg` | `81`/`83` /4 or `21` /r |
| `or reg, imm\|reg` | `81`/`83` /1 or `09` /r |
| `xor reg, imm\|reg` | `81`/`83` /6 or `31` /r |
| `shl reg, imm\|cl` | `D1`/`C1` /4 or `D3` /4; GAS `48 d3 e7` (cl) |
| `shr reg, imm\|cl` | `D1`/`C1` /5 or `D3` /5; GAS-proven |
| `sar reg, imm\|cl` | `D1`/`C1` /7 or `D3` /7; GAS `48 d1 ff` |
| `rol reg, imm\|cl` | `D1`/`C1` /0 or `D3` /0; GAS `48 d1 c7` |
| `ror reg, imm\|cl` | `D1`/`C1` /1 or `D3` /1; GAS `48 d1 cf` |
| `stc` | `F9`; GAS-proven (set CF) |
| `clc` | `F8`; GAS-proven (clear CF) |
| `std` | `FD`; GAS-proven (set DF) |
| `cld` | `FC`; GAS-proven (clear DF) |
| `rcl reg, imm\|cl` | `D1`/`C1` /2 or `D3` /2; GAS `48 d1 d7` |
| `rcr reg, imm\|cl` | `D1`/`C1` /3 or `D3` /3; GAS `48 d1 df` |
| `bsf reg, reg` | `0F BC` /r; GAS `48 0f bc fe` |
| `bsr reg, reg` | `0F BD` /r; GAS `48 0f bd fe` |
| `bt reg, reg` | `0F A3` /r; GAS `48 0f a3 ce` (base,offset) |
| `bts reg, reg` | `0F AB` /r; GAS `48 0f ab ce` (base,offset) |
| `btr reg, reg` | `0F B3` /r; GAS `48 0f b3 ce` (base,offset) |
| `btc reg, reg` | `0F BB` /r; GAS `48 0f bb ce` (base,offset) |
| `shld reg, reg, imm\|cl` | `0F A4`/`A5` /r; GAS `48 0f a4 f7 01` |
| `shrd reg, reg, imm\|cl` | `0F AC`/`AD` /r; GAS `48 0f ac f7 01` |
| `cmove`/`cmovz` reg, reg | `0F 44` /r; GAS `48 0f 44 fe` |
| `cmovne`/`cmovnz` reg, reg | `0F 45` /r; GAS `48 0f 45 fe` |
| `cmovl`/`cmovnge` reg, reg | `0F 4C` /r; GAS `48 0f 4c fe` |
| `cmovg`/`cmovnle` reg, reg | `0F 4F` /r; GAS `48 0f 4f fe` |
| `cmovle`/`cmovng` reg, reg | `0F 4E` /r; GAS `48 0f 4e fe` |
| `cmovge`/`cmovnl` reg, reg | `0F 4D` /r; GAS `48 0f 4d fe` |
| `cmova`/`cmovnbe` reg, reg | `0F 47` /r; GAS `48 0f 47 fe` |
| `cmovb`/`cmovnae`/`cmovc` reg, reg | `0F 42` /r; GAS `48 0f 42 fe` |
| `cmovae`/`cmovnb`/`cmovnc` reg, reg | `0F 43` /r; GAS `48 0f 43 fe` |
| `cmovbe`/`cmovna` reg, reg | `0F 46` /r; GAS `48 0f 46 fe` |
| `lea reg, [reg+disp]` | `8D` mod=01 + disp8 (GAS-proven; no rsp/rbp base) |
| `lea reg, [reg+reg]` | `8D` + SIB scale=1 (GAS-proven; no rsp index / rbp base) |
| `imul reg, imm` | `6B` /r ib or `69` /r id; also 1-op `F7` /5 |
| `mul`/`div`/`idiv` reg | `F7` /4|/6|/7; GAS `48 f7 e6` / `48 f7 fe` |
| `neg reg` | `F7` /3; GAS-proven (`48 f7 df` for rdi) |
| `not reg` | `F7` /2; GAS-proven (`48 f7 d7` for rdi) |
| `inc reg` | `FF` /0; GAS-proven (`48 ff c7` for rdi) |
| `dec reg` | `FF` /1; GAS-proven (`48 ff cf` for rdi) |
| `xchg reg, reg` | `87` /r or `90+rd` (rax); GAS `48 87 f7` / `48 97` |
| `cqo` / `cqto` | `48 99`; GAS-proven (sign-extend rax → rdx:rax) |
| `cdqe` / `cltq` | `48 98`; GAS-proven (sign-extend eax → rax) |
| `test reg, imm\|reg` | `F7` /0 id or `85` /r; GAS `48 f7 c7 01…` |
| `sete`/`setz`/`setne`/`setnz` r8 | `0F 94`/`95` /0; GAS `0f 94 c0` (al) |
| `setl`/`setg`/`setle`/`setge` r8 | `0F 9C`/`9F`/`9E`/`9D`; GAS `0f 9c c0` |
| `movzbq`/`movzx` reg, r8 | `0F B6` /r; GAS `48 0f b6 f8` (rdi←al) |
| `movsbq`/`movsx` reg, r8 | `0F BE` /r; GAS `48 0f be f8` (rdi←al) |
| `ret` | near `C3` |
| `leave` | `C9`; GAS-proven (mov rsp,rbp; pop rbp) |
| `syscall` | `0F 05` |
| `nop` | `90` |

Registers: `rax`…`rdi`, `r8`…`r15`, `rsp`, `rbp`, `rsi`.
Setcc also accepts `al`…`dil` (no `ah`/`ch`/…).

`call`/`jmp` resolve PC-relative within the unit at assemble time
(no ELF reloc yet). Forward refs OK. Reg-indirect call/jmp not in
phase-1.

## Tests

```bash
make -C sparkasm test
# or: make test-sparkasm
```

- `test_exit42` — mov/syscall → exit 42
- `test_callret` — call/ret/push/pop → exit 42
- `test_leave` — leave → exit 42
- `test_jmp` — forward jmp → exit 42
- `test_cmpjcc` — cmp/test + jcc forward refs → exit 42
- `test_cmprr` — cmp reg,reg → exit 42
- `test_addsub` — add/sub imm → exit 42
- `test_addsubrr` — add/sub reg,reg → exit 42
- `test_adc` — adc reg,reg → exit 42
- `test_sbb` — sbb reg,reg → exit 42
- `test_logic` — and/or/xor imm+reg → exit 42
- `test_shift` — shl/shr imm → exit 42
- `test_shiftcl` — shl/shr by cl → exit 42
- `test_sar` — sar imm → exit 42
- `test_rol` — rol imm → exit 42
- `test_ror` — ror imm → exit 42
- `test_stc` — stc + adc → exit 42
- `test_clc` — stc/clc + adc → exit 42
- `test_rcl` — rcl imm → exit 42
- `test_rcr` — rcr imm → exit 42
- `test_bsf` — bsf reg,reg → exit 42
- `test_bsr` — bsr reg,reg → exit 42
- `test_std` — std + exit 42
- `test_cld` — std/cld + exit 42
- `test_bt` — bt + adc → exit 42
- `test_bts` — bts → exit 42
- `test_btr` — btr → exit 42
- `test_btc` — btc → exit 42
- `test_shld` — shld imm → exit 42
- `test_shrd` — shrd imm → exit 42
- `test_cmovz` — cmove + exit 42
- `test_cmovnz` — cmovne + exit 42
- `test_cmovl` — cmovl + exit 42
- `test_cmovg` — cmovg + exit 42
- `test_cmovle` — cmovle + exit 42
- `test_cmovge` — cmovge + exit 42
- `test_cmova` — cmova + exit 42
- `test_cmovb` — cmovb + exit 42
- `test_cmovae` — cmovae + exit 42
- `test_cmovbe` — cmovbe + exit 42
- `test_lea` — lea [reg+disp]|[reg+reg] → exit 42
- `test_imul` — imul reg,imm → exit 42
- `test_mul` — mul reg → exit 42
- `test_idiv` — idiv reg → exit 42
- `test_neg` — neg reg → exit 42
- `test_movrr` — mov reg,reg → exit 42
- `test_incdec` — inc/dec reg → exit 42
- `test_pushimm` — push imm → exit 42
- `test_xchg` — xchg reg,reg → exit 42
- `test_not` — not reg → exit 42
- `test_cqo` — cqo → exit 42
- `test_cdqe` — cdqe → exit 42
- `test_sete` — sete al → exit 42
- `test_setl` — setl al → exit 42
- `test_testimm` — test reg,imm → exit 42
- `test_movzbq` — movzbq reg,r8 → exit 42
- `test_movsbq` — movsbq reg,r8 → exit 42

## Not in scope (yet)

- Full x86_64 ISA / GAS compatibility
- Relocations / `.data` / `.bss` / rip-relative
- `call`/`jmp` reg-indirect
- Spark language `assemble` op (optional later)
- Touching `asm/engine_*` or `asm/ide_*`
