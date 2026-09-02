# Spark http get/post — fork/exec spark-http (dry reads fixture; live dials).
# Dry-run and --live both go through the companion so fixture fopen is one path.

.intel_syntax noprefix
.global http_dispatch

.extern write_stdout
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern fork_exec_wait
.extern flag_live
.extern linebuf
.extern msg_nl
.extern msg_reply
.extern sys_exit
.extern strlen

.section .bss
.lcomm http_argv, 128
.lcomm http_reply, 65536

.section .rodata
http_bin:
    .ascii "./spark-http\0"
flg_dry:
    .ascii "--dry\0"
flg_live:
    .ascii "--live\0"
flg_stmt:
    .ascii "--stmt-file\0"
flg_out:
    .ascii "--out\0"
stmt_path:
    .ascii "/tmp/spark-http-stmt.txt\0"
out_path:
    .ascii "/tmp/spark-http-out.txt\0"
msg_http:
    .ascii "[http] "
msg_http_len = . - msg_http
msg_fail:
    .ascii "error: spark-http failed "
    .ascii "(dry: missing fixture; live: curl/URL/timeout/auth/retries)\n"
msg_fail_len = . - msg_fail

.section .text

http_save_line:
    push    rbx
    push    r12
    lea     rsi, [rip+linebuf]
    call    strlen
    mov     r12, rax
    mov     rax, 2
    lea     rdi, [rip+stmt_path]
    mov     rsi, 0x241
    mov     rdx, 0644
    syscall
    cmp     rax, 0
    jl      hsl_fail
    mov     rbx, rax
    mov     rax, 1
    mov     rdi, rbx
    lea     rsi, [rip+linebuf]
    mov     rdx, r12
    syscall
    mov     rax, 3
    mov     rdi, rbx
    syscall
    xor     rax, rax
    pop     r12
    pop     rbx
    ret
hsl_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

http_read_out:
    push    rbx
    mov     rax, 2
    lea     rdi, [rip+out_path]
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      hro_fail
    mov     rbx, rax
    mov     rax, 0
    mov     rdi, rbx
    lea     rsi, [rip+http_reply]
    mov     rdx, 65535
    syscall
    mov     rcx, rax
    push    rcx
    mov     rax, 3
    mov     rdi, rbx
    syscall
    pop     rcx
    cmp     rcx, 0
    jle     hro_fail
    lea     rdi, [rip+http_reply]
    mov     byte ptr [rdi+rcx], 0
    # trim trailing newline
    cmp     rcx, 0
    jle     hro_fail
    cmp     byte ptr [rdi+rcx-1], 10
    jne     hro_ok
    dec     rcx
    mov     byte ptr [rdi+rcx], 0
hro_ok:
    lea     rax, [rip+http_reply]
    pop     rbx
    ret
hro_fail:
    xor     rax, rax
    xor     rcx, rcx
    pop     rbx
    ret

http_dispatch:
    push    rbx
    lea     rsi, [rip+msg_http]
    mov     rdx, msg_http_len
    call    write_stdout
    lea     rsi, [rip+linebuf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+linebuf]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    call    http_save_line
    test    rax, rax
    jnz     hd_fail
    lea     rax, [rip+http_bin]
    mov     [rip+http_argv], rax
    cmp     qword ptr [rip+flag_live], 0
    jne     hd_live
    lea     rax, [rip+flg_dry]
    jmp     hd_mode
hd_live:
    lea     rax, [rip+flg_live]
hd_mode:
    mov     [rip+http_argv+8], rax
    lea     rax, [rip+flg_stmt]
    mov     [rip+http_argv+16], rax
    lea     rax, [rip+stmt_path]
    mov     [rip+http_argv+24], rax
    lea     rax, [rip+flg_out]
    mov     [rip+http_argv+32], rax
    lea     rax, [rip+out_path]
    mov     [rip+http_argv+40], rax
    mov     qword ptr [rip+http_argv+48], 0
    lea     rdi, [rip+http_bin]
    lea     rsi, [rip+http_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     hd_fail
    call    http_read_out
    test    rax, rax
    jz      hd_fail
    push    rax
    push    rcx
    lea     rsi, [rip+msg_reply]
    mov     rdx, 6
    call    write_stdout
    pop     rcx
    pop     rax
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret
hd_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
