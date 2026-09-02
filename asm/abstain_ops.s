# Spark head abstain/train/attach/ask — fork ./spark-abstain
# Dry fixtures or live CPU head train/attach (no invented weights).

.intel_syntax noprefix
.global abstain_dispatch

.extern write_stdout
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern fork_exec_wait
.extern flag_live
.extern linebuf
.extern msg_nl
.extern sys_exit
.extern strlen

.section .bss
.lcomm ab_argv, 128
.lcomm ab_reply, 2048

.section .rodata
ab_bin:
    .ascii "./spark-abstain\0"
flg_dry:
    .ascii "--dry\0"
flg_live:
    .ascii "--live\0"
flg_stmt:
    .ascii "--stmt-file\0"
flg_out:
    .ascii "--out\0"
stmt_path:
    .ascii "/tmp/spark-abstain-stmt.txt\0"
out_path:
    .ascii "/tmp/spark-abstain-out.txt\0"
msg_ab:
    .ascii "[head] "
msg_ab_len = . - msg_ab
msg_fail:
    .ascii "error: head failed "
    .ascii "(parse, missing weights, or companion)\n"
msg_fail_len = . - msg_fail

.section .text

# Save linebuf to stmt_path. rax=0 ok.
ab_save_stmt:
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
    jl      ass_fail
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
ass_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

# Read --out into ab_reply. rax=ptr rcx=len, or rax=0 fail.
ab_read_out:
    push    rbx
    mov     rax, 2
    lea     rdi, [rip+out_path]
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      aro_fail
    mov     rbx, rax
    mov     rax, 0
    mov     rdi, rbx
    lea     rsi, [rip+ab_reply]
    mov     rdx, 2047
    syscall
    mov     rcx, rax
    push    rcx
    mov     rax, 3
    mov     rdi, rbx
    syscall
    pop     rcx
    cmp     rcx, 0
    jle     aro_fail
    lea     rdi, [rip+ab_reply]
    mov     byte ptr [rdi+rcx], 0
    cmp     byte ptr [rdi+rcx-1], 10
    jne     aro_ok
    dec     rcx
    mov     byte ptr [rdi+rcx], 0
aro_ok:
    lea     rax, [rip+ab_reply]
    pop     rbx
    ret
aro_fail:
    xor     rax, rax
    xor     rcx, rcx
    pop     rbx
    ret

abstain_dispatch:
    push    rbx
    call    ab_save_stmt
    test    rax, rax
    jnz     ad_fail
    lea     rax, [rip+ab_bin]
    mov     [rip+ab_argv], rax
    cmp     qword ptr [rip+flag_live], 0
    jne     ad_live
    lea     rax, [rip+flg_dry]
    jmp     ad_mode
ad_live:
    lea     rax, [rip+flg_live]
ad_mode:
    mov     [rip+ab_argv+8], rax
    lea     rax, [rip+flg_stmt]
    mov     [rip+ab_argv+16], rax
    lea     rax, [rip+stmt_path]
    mov     [rip+ab_argv+24], rax
    lea     rax, [rip+flg_out]
    mov     [rip+ab_argv+32], rax
    lea     rax, [rip+out_path]
    mov     [rip+ab_argv+40], rax
    mov     qword ptr [rip+ab_argv+48], 0
    lea     rdi, [rip+ab_bin]
    lea     rsi, [rip+ab_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     ad_fail
    call    ab_read_out
    test    rax, rax
    jz      ad_fail
    push    rax
    push    rcx
    lea     rsi, [rip+msg_ab]
    mov     rdx, msg_ab_len
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

ad_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
