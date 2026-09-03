# Spark live shell/run — fork/exec spark-shell (argv allowlist).
# Dry-run fixtures stay in asm/spark.s. This unit runs when
# --live --allow-shell. Never system(). Never /bin/sh -c.
#
# Exports: shell_live_dispatch
# Imports: linebuf, extract_quote, write_bytes_path, fork_exec_wait,
#          write_stdout, set_last_from_rcx, bind_arrow_from_line,
#          sys_open, sys_read, sys_close, sys_exit, msg_nl

.intel_syntax noprefix
.global shell_live_dispatch

.extern linebuf
.extern extract_quote
.extern write_bytes_path
.extern fork_exec_wait
.extern write_stdout
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern msg_nl

.equ O_RDONLY, 0

.section .bss
.align 16
sh_argv:    .space 80
sh_reply:   .space 4096

.section .data
sh_bin:
    .ascii "./spark-shell\0"
flg_live:
    .ascii "--live\0"
flg_argvf:
    .ascii "--argv-file\0"
flg_out:
    .ascii "--out\0"
sh_argv_path:
    .ascii "/tmp/spark-shell-argv.txt\0"
sh_out_path:
    .ascii "/tmp/spark-shell-out.txt\0"
msg_fail:
    .ascii "error: spark-shell failed "
    .ascii "(allowlist echo|true|false; not open system())\n"
msg_fail_len = . - msg_fail
msg_empty:
    .ascii "error: live shell/run missing quoted argv\n"
msg_empty_len = . - msg_empty
sh_arrow:
    .ascii "  \xe2\x86\x92 "
sh_arrow_len = . - sh_arrow

.section .text

# shell_live_dispatch: linebuf already holds `shell "…"`.
# Writes argv file, forks companion --live, binds --out JSON.
shell_live_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      sh_empty
    mov     rsi, rax
    mov     rdx, rcx
    lea     rdi, [rip+sh_argv_path]
    call    write_bytes_path

    lea     rax, [rip+sh_bin]
    mov     [rip+sh_argv], rax
    lea     rax, [rip+flg_live]
    mov     [rip+sh_argv+8], rax
    lea     rax, [rip+flg_argvf]
    mov     [rip+sh_argv+16], rax
    lea     rax, [rip+sh_argv_path]
    mov     [rip+sh_argv+24], rax
    lea     rax, [rip+flg_out]
    mov     [rip+sh_argv+32], rax
    lea     rax, [rip+sh_out_path]
    mov     [rip+sh_argv+40], rax
    mov     qword ptr [rip+sh_argv+48], 0

    lea     rdi, [rip+sh_bin]
    lea     rsi, [rip+sh_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     sh_fail

    lea     rdi, [rip+sh_out_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      sh_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+sh_reply]
    mov     rdx, 4095
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jle     sh_fail

    lea     rbx, [rip+sh_reply]
sh_trim:
    cmp     r13, 0
    je      sh_trim_done
    lea     rsi, [rbx+r13]
    mov     al, [rsi-1]
    cmp     al, 10
    je      sh_trim_one
    cmp     al, 13
    jne     sh_trim_done
sh_trim_one:
    dec     r13
    jmp     sh_trim
sh_trim_done:
    mov     byte ptr [rbx+r13], 0

    lea     rsi, [rip+sh_arrow]
    mov     rdx, sh_arrow_len
    call    write_stdout
    lea     rsi, [rip+sh_reply]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+sh_reply]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     r13
    pop     r12
    pop     rbx
    ret

sh_empty:
    lea     rsi, [rip+msg_empty]
    mov     rdx, msg_empty_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

sh_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
