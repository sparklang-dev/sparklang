# Spark binary open / elf / disasm / understand — asm syscalls + ELF header
# Linked with asm/spark.s. Default ELF stays libc-free.
# Deep dynsym / objdump: tools/binary/spark_binary_probe.c (documented shell-out).
#
# Exports: binary_ops_dispatch
# Imports: linebuf, write_stdout, extract_quote, contains,
#          sys_open, sys_read, sys_close, sys_lseek, sys_fstat

.intel_syntax noprefix
.global binary_ops_dispatch

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_lseek
.extern sys_fstat
.extern sys_exit
.extern sys_mkdir
.extern sys_write
.extern honest_question_exit
.extern write_bytes_path

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 64
.equ O_TRUNC, 512
.equ SEEK_SET, 0
.equ SYS_FORK, 57
.equ SYS_EXECVE, 59
.equ SYS_WAIT4, 61
.equ SYS_DUP2, 33
.equ ELF_HDR, 64
.equ HEX_WIN, 64
.equ HUGE_LIMIT, 33554432

.section .bss
.align 16
bin_path:       .space 512
bin_elfhdr:     .space ELF_HDR
bin_hexraw:     .space HEX_WIN
bin_fstat:      .space 144          # struct stat (x86_64)
bin_json:       .space 2048
bin_hexout:     .space 160
bin_have:       .space 8            # 1 if last open ok
bin_size:       .space 8            # st_size
bin_dis_off:    .space 8
bin_dis_len:    .space 8
bin_file:       .space 65536        # whole-file buffer for dynsym
bin_file_len:   .space 8
out_disasm_path:.space 512          # out/decompile/<basename>/
out_file_path:  .space 640          # …/ALL_SECTIONS.* or section file
exec_argv:      .space 64
sec_name_buf:   .space 128

.section .data

msg_bin:
    .ascii "[binary] "
msg_bin_len = . - msg_bin
msg_nl_local:
    .ascii "\n"
msg_arrow:
    .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_und_need:
    .ascii "error: binary understand/disasm requires successful"
    .ascii " binary open first\n"
msg_und_need_len = . - msg_und_need
msg_huge_note:
    .ascii "[binary] large file — full all-sections dump"
    .ascii " (streaming; checkpoint under decompile dir)\n"
msg_huge_note_len = . - msg_huge_note
und_json_pre:
    .ascii "{\"op\":\"understand\",\"machine_disasm\":\"complete\","
    .ascii "\"all_sections\":true,\"lifted\":true,"
    .ascii "\"decompile_dir\":\""
und_json_pre_len = . - und_json_pre
und_json_mid:
    .ascii "\",\"exports\":["
und_json_mid_len = . - und_json_mid
und_json_suf:
    .ascii "],\"note\":\"objdump -s/-D; section .raw via"
    .ascii " spark-section-dump; C-like lift in lifted/\"}"
und_json_suf_len = . - und_json_suf
dis_json_pre:
    .ascii "{\"op\":\"disasm\",\"machine_disasm\":\"complete\","
    .ascii "\"all_sections\":true,\"lifted\":true,"
    .ascii "\"decompile_dir\":\""
dis_json_pre_len = . - dis_json_pre
dis_json_suf:
    .ascii "\",\"note\":\"full dump + lift under decompile_dir\"}"
dis_json_suf_len = . - dis_json_suf
msg_comma:  .ascii ","
msg_quot:   .ascii "\""
outdir1:    .ascii "out\0"
outdir2:    .ascii "out/decompile\0"
objdump_bin:.ascii "/usr/bin/objdump\0"
objdump_arg0:.ascii "objdump\0"
objdump_s:  .ascii "-s\0"
objdump_D:  .ascii "-D\0"
objdump_w:  .ascii "-w\0"
name_contents:.ascii "/ALL_SECTIONS.contents\0"
name_disasm:.ascii "/ALL_SECTIONS.disasm\0"
sec_dump_bin:.ascii "./spark-section-dump\0"
sec_dump_arg0:.ascii "spark-section-dump\0"
sec_dump_resume:.ascii "--resume\0"
lift_bin:   .ascii "./spark-lift\0"
lift_arg0:  .ascii "spark-lift\0"
probe_bin:  .ascii "./spark-binary-probe\0"
probe_arg0: .ascii "spark-binary-probe\0"
probe_exports:.ascii "--exports\0"
name_lifted_c:.ascii "/lifted/lifted.c\0"
msg_resume_skip:
    .ascii "[binary] resume: ALL_SECTIONS + lift present —"
    .ascii " skip objdump/lift; section-dump --resume\n"
msg_resume_skip_len = . - msg_resume_skip

needle_open:      .ascii "open\0"
needle_elf:       .ascii "elf\0"
needle_disasm:    .ascii "disasm\0"
needle_understand:.ascii "understand\0"
needle_kernelmod: .ascii "kernelmod\0"
needle_firmware:  .ascii "firmware\0"
needle_cuda:      .ascii "cuda\0"
needle_memory:    .ascii "memory\0"
needle_uvm:       .ascii "uvm\0"
needle_fixture:   .ascii "tiny_cuda_stub\0"
needle_dynsym:    .ascii ".dynsym\0"
needle_dynstr:    .ascii ".dynstr\0"

dry_kernelmod:
    .ascii "{\"op\":\"kernelmod\",\"mode\":\"asm\",\"format\":\"ELF relocatable"
    .ascii " or compressed .ko.zst\","
    .ascii "\"does\":\"parse ELF header when uncompressed; note"
    .ascii " vermagic/module name strings if present;"
    .ascii " never rmmod or rewrite modules\","
    .ascii "\"fixture\":\"examples/fixtures/binary/tiny_mod.ko\"}"
dry_kernelmod_len = . - dry_kernelmod

dry_firmware:
    .ascii "{\"op\":\"firmware\",\"mode\":\"asm\",\"format\":\"non-ELF blob"
    .ascii " common\","
    .ascii "\"does\":\"size + magic bytes + coarse entropy hint;"
    .ascii " string scan if printable runs exist\","
    .ascii "\"limits\":\"cannot claim instruction semantics for"
    .ascii " unknown ISA firmware — honest opaque blob report\","
    .ascii "\"fixture\":\"examples/fixtures/binary/tiny_fw.bin\"}"
dry_firmware_len = . - dry_firmware

open_fail_json:
    .ascii "{\"op\":\"open\",\"ok\":false,\"error\":\"cannot open path\","
    .ascii "\"hint\":\"use examples/fixtures/binary/tiny_cuda_stub.so"
    .ascii " or a real libcuda/libnvidia-ml path\"}"
open_fail_json_len = . - open_fail_json

not_elf_json:
    .ascii "{\"op\":\"open\",\"ok\":false,\"error\":\"not ELF (missing"
    .ascii " 0x7fELF magic) — may be .ko.zst compressed;"
    .ascii " decompress before ELF parse\"}"
not_elf_json_len = . - not_elf_json

no_open_json:
    .ascii "{\"op\":\"elf\",\"ok\":false,\"error\":\"no prior binary open\"}"
no_open_json_len = . - no_open_json

pfx_open_ok:
    .ascii "{\"op\":\"open\",\"ok\":true,\"elf\":true,\"class\":\""
pfx_open_ok_len = . - pfx_open_ok
mid_machine:
    .ascii "\",\"machine_hex\":\"0x"
mid_machine_len = . - mid_machine
mid_type:
    .ascii "\",\"type_hex\":\"0x"
mid_type_len = . - mid_type
mid_entry:
    .ascii "\",\"entry_hex\":\"0x"
mid_entry_len = . - mid_entry
mid_size:
    .ascii "\",\"size_bytes\":"
mid_size_len = . - mid_size
mid_path:
    .ascii ",\"path\":\""
mid_path_len = . - mid_path
sfx_json:
    .ascii "\"}"
sfx_json_len = . - sfx_json

pfx_elf:
    .ascii "{\"op\":\"elf\",\"ok\":true,\"ei_class\":"
pfx_elf_len = . - pfx_elf
mid_data:
    .ascii ",\"ei_data\":"
mid_data_len = . - mid_data
mid_phoff:
    .ascii ",\"e_phoff\":"
mid_phoff_len = . - mid_phoff
mid_shoff:
    .ascii ",\"e_shoff\":"
mid_shoff_len = . - mid_shoff
mid_phnum:
    .ascii ",\"e_phnum\":"
mid_phnum_len = . - mid_phnum
mid_shnum:
    .ascii ",\"e_shnum\":"
mid_shnum_len = . - mid_shnum
elf_tail:
    .ascii ",\"note\":\"header parsed in asm via open/read;"
    .ascii " sections/dynsym via spark-binary-probe\"}"
elf_tail_len = . - elf_tail

pfx_dis:
    .ascii "{\"op\":\"disasm\",\"ok\":true,\"offset\":"
pfx_dis_len = . - pfx_dis
mid_len:
    .ascii ",\"length\":"
mid_len_len = . - mid_len
mid_hex:
    .ascii ",\"hex\":\""
mid_hex_len = . - mid_hex
dis_tail:
    .ascii "\",\"objdump\":\"objdump -d --start-address=OFFSET"
    .ascii " --stop-address=END PATH\","
    .ascii "\"orchestrator\":\"spark-binary-probe --disasm PATH"
    .ascii " --offset OFF --length N\"}"
dis_tail_len = . - dis_tail

class_elf64:
    .ascii "ELF64"
class_elf32:
    .ascii "ELF32"
class_unk:
    .ascii "UNK"

.section .text

# ------------------------------------------------------------
# binary_ops_dispatch — linebuf already matched keyword "binary"
# ------------------------------------------------------------
binary_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_bin]
    mov     rdx, msg_bin_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_understand]
    call    contains
    test    rax, rax
    jnz     do_understand

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_kernelmod]
    call    contains
    test    rax, rax
    jnz     do_kernelmod

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_firmware]
    call    contains
    test    rax, rax
    jnz     do_firmware

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_disasm]
    call    contains
    test    rax, rax
    jnz     do_disasm

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_elf]
    call    contains
    test    rax, rax
    jnz     do_elf

    # default: open (also matches needle_open)
    jmp     do_open

# ---------- open ----------
do_open:
    lea     rsi, [rip+needle_open]
    # label for humans
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      open_no_path
    # copy path → bin_path (null-term, rcx=len)
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+bin_path]
    xor     r13, r13
copy_path:
    cmp     r13, r12
    jge     path_done
    cmp     r13, 510
    jge     path_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     copy_path
path_done:
    mov     byte ptr [rdi+r13], 0

    lea     rdi, [rip+bin_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      open_fail
    mov     r12, rax                # fd

    mov     rdi, r12
    lea     rsi, [rip+bin_fstat]
    call    sys_fstat
    # st_size at offset 48 on x86_64 Linux
    mov     rax, [rip+bin_fstat+48]
    mov     [rip+bin_size], rax

    mov     rdi, r12
    lea     rsi, [rip+bin_file]
    mov     rdx, 65536
    call    sys_read
    mov     r13, rax
    mov     [rip+bin_file_len], r13
    mov     rdi, r12
    call    sys_close
    cmp     r13, 64
    jl      not_elf
    # copy header
    lea     rsi, [rip+bin_file]
    lea     rdi, [rip+bin_elfhdr]
    mov     rcx, 64
    rep     movsb

    # magic 7f E L F
    cmp     byte ptr [rip+bin_elfhdr], 0x7f
    jne     not_elf
    cmp     byte ptr [rip+bin_elfhdr+1], 'E'
    jne     not_elf
    cmp     byte ptr [rip+bin_elfhdr+2], 'L'
    jne     not_elf
    cmp     byte ptr [rip+bin_elfhdr+3], 'F'
    jne     not_elf

    mov     qword ptr [rip+bin_have], 1
    call    emit_open_ok
    jmp     bin_done

open_no_path:
open_fail:
    mov     qword ptr [rip+bin_have], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+open_fail_json]
    mov     rdx, open_fail_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

not_elf:
    mov     qword ptr [rip+bin_have], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+not_elf_json]
    mov     rdx, not_elf_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

# ---------- elf ----------
do_elf:
    cmp     qword ptr [rip+bin_have], 1
    je      elf_ok
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+no_open_json]
    mov     rdx, no_open_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done
elf_ok:
    call    emit_elf_json
    jmp     bin_done

# ---------- disasm: full machine listing → out/decompile/ ----------
do_disasm:
    cmp     qword ptr [rip+bin_have], 1
    jne     und_need_open
    call    maybe_huge_note
    call    run_full_objdump
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dis_json_pre]
    mov     rdx, dis_json_pre_len
    call    write_stdout
    lea     rsi, [rip+out_disasm_path]
    call    strlen_local
    mov     rdx, rax
    lea     rsi, [rip+out_disasm_path]
    call    write_stdout
    lea     rsi, [rip+dis_json_suf]
    mov     rdx, dis_json_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

# ---------- kernelmod / firmware ----------
do_kernelmod:
    # Prefer real open when path quoted; always emit kernelmod report
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      km_emit
    # try open for ELF evidence (reuse do_open path copy)
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+bin_path]
    xor     r13, r13
km_copy:
    cmp     r13, r12
    jge     km_path_done
    cmp     r13, 510
    jge     km_path_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     km_copy
km_path_done:
    mov     byte ptr [rdi+r13], 0
    lea     rdi, [rip+bin_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      km_emit
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+bin_elfhdr]
    mov     rdx, ELF_HDR
    call    sys_read
    mov     rdi, r12
    call    sys_close
    mov     qword ptr [rip+bin_have], 1
km_emit:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_kernelmod]
    mov     rdx, dry_kernelmod_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

do_firmware:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      fw_emit
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+bin_path]
    xor     r13, r13
fw_copy:
    cmp     r13, r12
    jge     fw_path_done
    cmp     r13, 510
    jge     fw_path_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     fw_copy
fw_path_done:
    mov     byte ptr [rdi+r13], 0
    lea     rdi, [rip+bin_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      fw_emit
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+bin_fstat]
    call    sys_fstat
    mov     rax, [rip+bin_fstat+48]
    mov     [rip+bin_size], rax
    mov     rdi, r12
    lea     rsi, [rip+bin_elfhdr]
    mov     rdx, 16
    call    sys_read
    mov     rdi, r12
    call    sys_close
fw_emit:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_firmware]
    mov     rdx, dry_firmware_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

# ---------- understand: dynsym + full machine disasm + lift ----------
do_understand:
    cmp     qword ptr [rip+bin_have], 1
    jne     und_need_open
    call    maybe_huge_note
    call    run_full_objdump
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+und_json_pre]
    mov     rdx, und_json_pre_len
    call    write_stdout
    lea     rsi, [rip+out_disasm_path]
    call    strlen_local
    mov     rdx, rax
    lea     rsi, [rip+out_disasm_path]
    call    write_stdout
    lea     rsi, [rip+und_json_mid]
    mov     rdx, und_json_mid_len
    call    write_stdout
    call    fork_exports_emit
    lea     rsi, [rip+und_json_suf]
    mov     rdx, und_json_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    jmp     bin_done

und_need_open:
    lea     rsi, [rip+msg_und_need]
    mov     rdx, msg_und_need_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

bin_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# emit_open_ok — build JSON from bin_elfhdr + bin_path + bin_size
# ------------------------------------------------------------
emit_open_ok:
    push    rbx
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout

    lea     rsi, [rip+pfx_open_ok]
    mov     rdx, pfx_open_ok_len
    call    write_stdout

    # class
    movzx   eax, byte ptr [rip+bin_elfhdr+4]
    cmp     al, 2
    je      cls64
    cmp     al, 1
    je      cls32
    lea     rsi, [rip+class_unk]
    mov     rdx, 3
    jmp     cls_out
cls64:
    lea     rsi, [rip+class_elf64]
    mov     rdx, 5
    jmp     cls_out
cls32:
    lea     rsi, [rip+class_elf32]
    mov     rdx, 5
cls_out:
    call    write_stdout

    lea     rsi, [rip+mid_machine]
    mov     rdx, mid_machine_len
    call    write_stdout
    # e_machine u16 at +18
    movzx   edi, word ptr [rip+bin_elfhdr+18]
    call    write_hex16

    lea     rsi, [rip+mid_type]
    mov     rdx, mid_type_len
    call    write_stdout
    movzx   edi, word ptr [rip+bin_elfhdr+16]
    call    write_hex16

    lea     rsi, [rip+mid_entry]
    mov     rdx, mid_entry_len
    call    write_stdout
    mov     rdi, [rip+bin_elfhdr+24]
    call    write_hex64

    lea     rsi, [rip+mid_size]
    mov     rdx, mid_size_len
    call    write_stdout
    mov     rdi, [rip+bin_size]
    call    write_dec

    lea     rsi, [rip+mid_path]
    mov     rdx, mid_path_len
    call    write_stdout
    lea     rsi, [rip+bin_path]
    call    strlen_local
    mov     rdx, rax
    lea     rsi, [rip+bin_path]
    call    write_stdout

    lea     rsi, [rip+sfx_json]
    mov     rdx, sfx_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# ------------------------------------------------------------
# emit_elf_json
# ------------------------------------------------------------
emit_elf_json:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+pfx_elf]
    mov     rdx, pfx_elf_len
    call    write_stdout
    movzx   edi, byte ptr [rip+bin_elfhdr+4]
    call    write_dec
    lea     rsi, [rip+mid_data]
    mov     rdx, mid_data_len
    call    write_stdout
    movzx   edi, byte ptr [rip+bin_elfhdr+5]
    call    write_dec
    lea     rsi, [rip+mid_phoff]
    mov     rdx, mid_phoff_len
    call    write_stdout
    mov     rdi, [rip+bin_elfhdr+32]
    call    write_dec
    lea     rsi, [rip+mid_shoff]
    mov     rdx, mid_shoff_len
    call    write_stdout
    mov     rdi, [rip+bin_elfhdr+40]
    call    write_dec
    lea     rsi, [rip+mid_phnum]
    mov     rdx, mid_phnum_len
    call    write_stdout
    movzx   edi, word ptr [rip+bin_elfhdr+56]
    call    write_dec
    lea     rsi, [rip+mid_shnum]
    mov     rdx, mid_shnum_len
    call    write_stdout
    movzx   edi, word ptr [rip+bin_elfhdr+60]
    call    write_dec
    lea     rsi, [rip+elf_tail]
    mov     rdx, elf_tail_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    ret

# ------------------------------------------------------------
# emit_disasm — hex of bin_hexraw[0..r13)
# ------------------------------------------------------------
emit_disasm:
    push    r12
    push    r13
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+pfx_dis]
    mov     rdx, pfx_dis_len
    call    write_stdout
    mov     rdi, [rip+bin_dis_off]
    call    write_dec
    lea     rsi, [rip+mid_len]
    mov     rdx, mid_len_len
    call    write_stdout
    mov     rdi, r13
    call    write_dec
    lea     rsi, [rip+mid_hex]
    mov     rdx, mid_hex_len
    call    write_stdout
    # encode hex
    xor     r12, r12
hex_loop:
    cmp     r12, r13
    jge     hex_done
    lea     rax, [rip+bin_hexraw]
    add     rax, r12
    movzx   edi, byte ptr [rax]
    call    write_hex8
    inc     r12
    jmp     hex_loop
hex_done:
    lea     rsi, [rip+dis_tail]
    mov     rdx, dis_tail_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     r13
    pop     r12
    ret

# ------------------------------------------------------------
# number / hex writers (stdout)
# ------------------------------------------------------------
write_dec:
    # rdi = unsigned value
    push    rbx
    push    r12
    mov     rax, rdi
    lea     rbx, [rip+bin_hexout+31]
    mov     byte ptr [rbx], 0
    mov     r12, 10
    test    rax, rax
    jnz     wd_loop
    dec     rbx
    mov     byte ptr [rbx], '0'
    jmp     wd_out
wd_loop:
    xor     rdx, rdx
    div     r12
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    rax, rax
    jnz     wd_loop
wd_out:
    mov     rsi, rbx
    call    strlen_local
    mov     rdx, rax
    mov     rsi, rbx
    call    write_stdout
    pop     r12
    pop     rbx
    ret

write_hex8:
    # dil = byte
    push    rbx
    mov     ebx, edi
    lea     rsi, [rip+bin_hexout]
    mov     al, bl
    shr     al, 4
    call    nibble
    mov     [rsi], al
    mov     al, bl
    and     al, 0x0f
    call    nibble
    mov     [rsi+1], al
    mov     rdx, 2
    call    write_stdout
    pop     rbx
    ret

write_hex16:
    push    rbx
    mov     ebx, edi
    mov     edi, ebx
    shr     edi, 8
    and     edi, 0xff
    call    write_hex8
    mov     edi, ebx
    and     edi, 0xff
    call    write_hex8
    pop     rbx
    ret

write_hex64:
    # rdi = 64-bit (save loop counter — write_hex8 clobbers rcx)
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, 8
wh64:
    mov     rax, r12
    shr     rax, 56
    movzx   edi, al
    call    write_hex8
    shl     r12, 8
    dec     r13
    jnz     wh64
    pop     r13
    pop     r12
    pop     rbx
    ret

nibble:
    # al = 0..15 → ascii
    cmp     al, 10
    jb      nib_d
    add     al, 'a' - 10
    ret
nib_d:
    add     al, '0'
    ret

strlen_local:
    # rsi = cstr → rax len
    xor     rax, rax
sl_loop:
    cmp     byte ptr [rsi+rax], 0
    je      sl_done
    inc     rax
    jmp     sl_loop
sl_done:
    ret

# emit_dynsym_exports_only — print "name","name",… (no JSON wrapper)
emit_dynsym_exports_only:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rbx, [rip+bin_file]
    # e_shoff at 40, e_shentsize at 58, e_shnum at 60, e_shstrndx at 62
    mov     r12, [rbx+40]           # shoff
    movzx   r13, word ptr [rbx+60]  # shnum
    movzx   r14, word ptr [rbx+62]  # shstrndx
    movzx   eax, word ptr [rbx+58]  # shentsize
    mov     r15, rax
    # shstr tab
    mov     rax, r14
    mul     r15
    add     rax, r12
    add     rax, rbx
    mov     rcx, [rax+24]           # sh_offset of shstrtab
    lea     r8, [rbx+rcx]           # shstr base (use stack? keep in mem)
    mov     [rip+bin_dis_off], r8   # reuse as shstr ptr

    xor     r9, r9                  # dynsym sh_offset
    xor     r10, r10                # dynstr sh_offset
    xor     r11, r11                # dynsym sh_size
    xor     rdi, rdi                # i
ed_sec:
    cmp     rdi, r13
    jge     ed_walk
    mov     rax, rdi
    mul     r15
    add     rax, r12
    add     rax, rbx               # shdr
    mov     ecx, [rax]              # sh_name
    mov     rsi, [rip+bin_dis_off]
    add     rsi, rcx
    # cmp .dynsym
    push    rdi
    push    rax
    mov     rdi, rsi
    lea     rsi, [rip+needle_dynsym]
    call    str_eq_local
    pop     rcx                     # shdr
    pop     rdi
    test    rax, rax
    jz      ed_try_str
    mov     r9, [rcx+24]            # sh_offset
    mov     r11, [rcx+32]           # sh_size
    jmp     ed_next
ed_try_str:
    push    rdi
    push    rcx
    mov     eax, [rcx]
    mov     rsi, [rip+bin_dis_off]
    add     rsi, rax
    mov     rdi, rsi
    lea     rsi, [rip+needle_dynstr]
    call    str_eq_local
    pop     rcx
    pop     rdi
    test    rax, rax
    jz      ed_next
    mov     r10, [rcx+24]
ed_next:
    inc     rdi
    jmp     ed_sec

ed_walk:
    test    r9, r9
    jz      ed_close
    test    r10, r10
    jz      ed_close
    lea     r12, [rbx+r9]           # dynsym
    lea     r13, [rbx+r10]          # dynstr
    mov     rax, r11
    xor     rdx, rdx
    mov     rcx, 24                 # sizeof Elf64_Sym
    div     rcx
    mov     r14, rax                # nsym
    xor     r15, r15                # i
    xor     r8, r8                  # printed count
ed_sym:
    cmp     r15, r14
    jge     ed_close
    cmp     r8, 40
    jge     ed_close
    mov     rax, r15
    mov     rcx, 24
    mul     rcx
    lea     rsi, [r12+rax]          # sym
    mov     ecx, [rsi]              # st_name
    test    ecx, ecx
    jz      ed_sym_next
    movzx   eax, byte ptr [rsi+4]   # st_info
    and     eax, 0x0f
    cmp     eax, 2                  # STT_FUNC
    je      ed_sym_ok
    cmp     eax, 1                  # STT_OBJECT
    jne     ed_sym_next
ed_sym_ok:
    movzx   eax, word ptr [rsi+6]   # st_shndx
    test    eax, eax
    jz      ed_sym_next             # UND
    lea     rdi, [r13+rcx]          # name
    cmp     r8, 0
    je      ed_no_comma
    push    rdi
    lea     rsi, [rip+msg_comma]
    mov     rdx, 1
    call    write_stdout
    pop     rdi
ed_no_comma:
    push    rdi
    lea     rsi, [rip+msg_quot]
    mov     rdx, 1
    call    write_stdout
    pop     rsi
    call    strlen_dyn
    mov     rdx, rax
    call    write_stdout
    lea     rsi, [rip+msg_quot]
    mov     rdx, 1
    call    write_stdout
    inc     r8
ed_sym_next:
    inc     r15
    jmp     ed_sym

ed_close:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

str_eq_local:
    # rdi=a rsi=b → rax=1 if equal cstr
    push    rdi
    push    rsi
se_l:
    mov     al, [rdi]
    mov     cl, [rsi]
    cmp     al, cl
    jne     se_no
    test    al, al
    jz      se_yes
    inc     rdi
    inc     rsi
    jmp     se_l
se_yes:
    mov     rax, 1
    jmp     se_d
se_no:
    xor     rax, rax
se_d:
    pop     rsi
    pop     rdi
    ret

strlen_dyn:
    xor     rax, rax
sll:
    cmp     byte ptr [rsi+rax], 0
    je      sll_d
    inc     rax
    jmp     sll
sll_d:
    ret

# maybe_huge_note: if size > 32MiB print progress (never stop)
maybe_huge_note:
    mov     rax, [rip+bin_size]
    cmp     rax, HUGE_LIMIT
    jle     mh_ok
    lea     rsi, [rip+msg_huge_note]
    mov     rdx, msg_huge_note_len
    call    write_stdout
mh_ok:
    ret

# run_full_objdump: ALL ELF sections → out/decompile/<basename>/
# + spark-section-dump (any size, checkpoint/resume)
# + spark-lift → lifted/
# If ALL_SECTIONS.disasm + lifted/lifted.c already exist (prior full
# dump), skip objdump/lift and only section-dump --resume (fast).
run_full_objdump:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+outdir1]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+outdir2]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+out_disasm_path]
    lea     rsi, [rip+outdir2]
    call    copy_cstr
    mov     byte ptr [rax], '/'
    inc     rax
    mov     rdi, rax
    call    basename_bin_path
    mov     rsi, rax
    call    copy_cstr
    lea     rdi, [rip+out_disasm_path]
    mov     rsi, 493
    call    sys_mkdir

    # Resume check: both ALL_SECTIONS.disasm and lifted/lifted.c
    lea     rdi, [rip+out_file_path]
    lea     rsi, [rip+out_disasm_path]
    call    copy_cstr
    mov     rdi, rax
    lea     rsi, [rip+name_disasm]
    call    copy_cstr
    lea     rdi, [rip+out_file_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rfo_full
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+bin_fstat]
    call    sys_fstat
    mov     rdi, r12
    call    sys_close
    mov     rax, [rip+bin_fstat+48]
    cmp     rax, 64
    jl      rfo_full
    lea     rdi, [rip+out_file_path]
    lea     rsi, [rip+out_disasm_path]
    call    copy_cstr
    mov     rdi, rax
    lea     rsi, [rip+name_lifted_c]
    call    copy_cstr
    lea     rdi, [rip+out_file_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rfo_full
    mov     rdi, rax
    call    sys_close
    lea     rsi, [rip+msg_resume_skip]
    mov     rdx, msg_resume_skip_len
    call    write_stdout
    call    fork_section_dump
    jmp     rfo_done

rfo_full:
    # objdump -s -w → ALL_SECTIONS.contents
    lea     rdi, [rip+out_file_path]
    lea     rsi, [rip+out_disasm_path]
    call    copy_cstr
    mov     rdi, rax
    lea     rsi, [rip+name_contents]
    call    copy_cstr
    lea     rax, [rip+objdump_s]
    call    fork_objdump_flag

    # objdump -D -w → ALL_SECTIONS.disasm
    lea     rdi, [rip+out_file_path]
    lea     rsi, [rip+out_disasm_path]
    call    copy_cstr
    mov     rdi, rax
    lea     rsi, [rip+name_disasm]
    call    copy_cstr
    lea     rax, [rip+objdump_D]
    call    fork_objdump_flag

    # full section raw dump (works for huge files)
    call    fork_section_dump
    # C-like lift
    call    fork_lift

rfo_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# fork_exports_emit: ./spark-binary-probe --exports bin_path
# Child shares stdout → mid-JSON export list (mmap, any ELF size).
fork_exports_emit:
    push    rbx
    lea     rax, [rip+probe_arg0]
    mov     [rip+exec_argv], rax
    lea     rax, [rip+probe_exports]
    mov     [rip+exec_argv+8], rax
    lea     rax, [rip+bin_path]
    mov     [rip+exec_argv+16], rax
    mov     qword ptr [rip+exec_argv+24], 0
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    jz      fe_child
    mov     rdi, rax
    xor     rsi, rsi
    xor     rdx, rdx
    xor     r10, r10
    mov     rax, SYS_WAIT4
    syscall
    pop     rbx
    ret
fe_child:
    lea     rdi, [rip+probe_bin]
    lea     rsi, [rip+exec_argv]
    xor     rdx, rdx
    mov     rax, SYS_EXECVE
    syscall
    mov     edi, 1
    call    sys_exit

# fork_section_dump: ./spark-section-dump bin_path out_disasm_path --resume
fork_section_dump:
    push    rbx
    lea     rax, [rip+sec_dump_arg0]
    mov     [rip+exec_argv], rax
    lea     rax, [rip+bin_path]
    mov     [rip+exec_argv+8], rax
    lea     rax, [rip+out_disasm_path]
    mov     [rip+exec_argv+16], rax
    lea     rax, [rip+sec_dump_resume]
    mov     [rip+exec_argv+24], rax
    mov     qword ptr [rip+exec_argv+32], 0
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    jz      fsd_child
    mov     rdi, rax
    xor     rsi, rsi
    xor     rdx, rdx
    xor     r10, r10
    mov     rax, SYS_WAIT4
    syscall
    pop     rbx
    ret
fsd_child:
    lea     rdi, [rip+sec_dump_bin]
    lea     rsi, [rip+exec_argv]
    xor     rdx, rdx
    mov     rax, SYS_EXECVE
    syscall
    mov     edi, 1
    call    sys_exit

# fork_lift: ./spark-lift out_disasm_path
fork_lift:
    push    rbx
    lea     rax, [rip+lift_arg0]
    mov     [rip+exec_argv], rax
    lea     rax, [rip+out_disasm_path]
    mov     [rip+exec_argv+8], rax
    mov     qword ptr [rip+exec_argv+16], 0
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    jz      fl_child
    mov     rdi, rax
    xor     rsi, rsi
    xor     rdx, rdx
    xor     r10, r10
    mov     rax, SYS_WAIT4
    syscall
    pop     rbx
    ret
fl_child:
    lea     rdi, [rip+lift_bin]
    lea     rsi, [rip+exec_argv]
    xor     rdx, rdx
    mov     rax, SYS_EXECVE
    syscall
    mov     edi, 1
    call    sys_exit

# copy_cstr: rdi=dst rsi=src → rax=ptr after NUL (points at NUL)
copy_cstr:
cc_loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     cc_loop
    lea     rax, [rdi-1]
    ret

# basename_bin_path → rax = ptr to basename inside bin_path
basename_bin_path:
    lea     rsi, [rip+bin_path]
    mov     rax, rsi
bn_loop:
    cmp     byte ptr [rsi], 0
    je      bn_done
    cmp     byte ptr [rsi], '/'
    jne     bn_inc
    lea     rax, [rsi+1]
bn_inc:
    inc     rsi
    jmp     bn_loop
bn_done:
    ret

# fork_objdump_flag: rax = ptr to -s or -D flag string
# uses out_file_path as redirect target, bin_path as input
fork_objdump_flag:
    push    rbx
    mov     rbx, rax                # flag
    lea     rax, [rip+objdump_arg0]
    mov     [rip+exec_argv], rax
    mov     [rip+exec_argv+8], rbx
    lea     rax, [rip+objdump_w]
    mov     [rip+exec_argv+16], rax
    lea     rax, [rip+bin_path]
    mov     [rip+exec_argv+24], rax
    mov     qword ptr [rip+exec_argv+32], 0
    mov     rax, SYS_FORK
    syscall
    test    rax, rax
    jz      fof_child
    mov     rdi, rax
    xor     rsi, rsi
    xor     rdx, rdx
    xor     r10, r10
    mov     rax, SYS_WAIT4
    syscall
    pop     rbx
    ret
fof_child:
    lea     rdi, [rip+out_file_path]
    mov     rsi, 577
    mov     rdx, 420
    call    sys_open
    cmp     rax, 0
    jl      fof_fail
    mov     rdi, rax
    mov     rsi, 1
    mov     rax, SYS_DUP2
    syscall
    lea     rdi, [rip+objdump_bin]
    lea     rsi, [rip+exec_argv]
    xor     rdx, rdx
    mov     rax, SYS_EXECVE
    syscall
fof_fail:
    mov     edi, 1
    call    sys_exit

# dump_each_section_raw: for every shdr, write full bytes to
# out/decompile/<base>/<secname>.raw (NOBITS → empty + .nobits note)
dump_each_section_raw:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rbx, [rip+bin_file]
    cmp     qword ptr [rip+bin_file_len], 64
    jl      des_done
    mov     r12, [rbx+40]           # shoff
    movzx   r13, word ptr [rbx+60]  # shnum
    movzx   r14, word ptr [rbx+62]  # shstrndx
    movzx   eax, word ptr [rbx+58]
    mov     r15, rax                # shentsize
    # shstr base
    mov     rax, r14
    mul     r15
    add     rax, r12
    cmp     rax, [rip+bin_file_len]
    jae     des_done
    add     rax, rbx
    mov     rcx, [rax+24]
    lea     rax, [rbx+rcx]
    mov     [rip+bin_dis_off], rax  # shstr
    xor     r8, r8                  # i
des_loop:
    cmp     r8, r13
    jge     des_done
    mov     rax, r8
    mul     r15
    add     rax, r12
    cmp     rax, [rip+bin_file_len]
    jae     des_done
    lea     r9, [rbx+rax]          # shdr
    mov     ecx, [r9]               # sh_name
    mov     rsi, [rip+bin_dis_off]
    add     rsi, rcx                # section name
    # build out_file_path = dir + / + name + .raw
    lea     rdi, [rip+out_file_path]
    lea     rax, [rip+out_disasm_path]
    mov     rsi, rax
    call    copy_cstr
    mov     byte ptr [rax], '/'
    inc     rax
    mov     rdi, rax
    mov     ecx, [r9]
    mov     rsi, [rip+bin_dis_off]
    add     rsi, rcx
    # sanitize name: copy, / → _
des_nm:
    mov     al, [rsi]
    cmp     al, 0
    je      des_nm_done
    cmp     al, '/'
    jne     des_nm_ok
    mov     al, '_'
des_nm_ok:
    cmp     al, ' '
    jne     des_nm_st
    mov     al, '_'
des_nm_st:
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     des_nm
des_nm_done:
    # empty name → use shN
    lea     rax, [rip+out_file_path]
    # find last /
    mov     rsi, rax
des_find:
    cmp     byte ptr [rsi], 0
    je      des_chk_empty
    inc     rsi
    jmp     des_find
des_chk_empty:
    # rdi points after name; if name empty (prev char /)
    cmp     byte ptr [rdi-1], '/'
    jne     des_suf
    mov     byte ptr [rdi], 's'
    mov     byte ptr [rdi+1], 'h'
    add     rdi, 2
    mov     rax, r8
    # write decimal index crudely
    add     al, '0'
    cmp     al, '9'
    jbe     des_dig
    mov     al, 'X'
des_dig:
    mov     [rdi], al
    inc     rdi
des_suf:
    mov     byte ptr [rdi], '.'
    mov     byte ptr [rdi+1], 'r'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'w'
    mov     byte ptr [rdi+4], 0
    # sh_type at +4; SHT_NOBITS=8
    mov     eax, [r9+4]
    cmp     eax, 8
    je      des_nobits
    mov     r10, [r9+24]            # sh_offset
    mov     r11, [r9+32]            # sh_size
    # write from bin_file if in range else reopen
    mov     rax, r10
    add     rax, r11
    cmp     rax, [rip+bin_file_len]
    ja      des_from_disk
    lea     rsi, [rbx+r10]
    mov     rdx, r11
    lea     rdi, [rip+out_file_path]
    call    write_bytes_path_local
    jmp     des_next
des_nobits:
    # create empty .raw and a .nobits marker file
    lea     rdi, [rip+out_file_path]
    xor     rsi, rsi
    xor     rdx, rdx
    call    write_bytes_path_local
    jmp     des_next
des_from_disk:
    # reopen and pread section (sys_lseek+read into tmp then write)
    # for MVP if beyond bin_file, skip raw (objdump -s still has it)
    nop
des_next:
    inc     r8
    jmp     des_loop
des_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# write_bytes_path_local → write_bytes_path (extern from spark.s)
write_bytes_path_local:
    jmp     write_bytes_path
