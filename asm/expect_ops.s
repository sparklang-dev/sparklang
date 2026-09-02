# Spark expect equal/contains — fork spark-expect with got from vars_get.
# Missing binding, missing fixture, or mismatch → exit 1 (fail loud).

.intel_syntax noprefix
.global expect_dispatch

.extern write_stdout
.extern fork_exec_wait
.extern linebuf
.extern msg_nl
.extern sys_exit
.extern strlen
.extern vars_get
.extern extract_quote
.extern skip_ws
.extern skip_ws_from_rbx
.extern tmpbuf

.section .bss
.lcomm xp_argv, 128
.lcomm xp_name, 64
.lcomm xp_got, 65536

.section .rodata
xp_bin:
    .ascii "./spark-expect\0"
flg_dry:
    .ascii "--dry\0"
flg_stmt:
    .ascii "--stmt-file\0"
flg_gotf:
    .ascii "--got-file\0"
flg_out:
    .ascii "--out\0"
stmt_path:
    .ascii "/tmp/spark-expect-stmt.txt\0"
got_path:
    .ascii "/tmp/spark-expect-got.txt\0"
out_path:
    .ascii "/tmp/spark-expect-out.txt\0"
msg_xp:
    .ascii "[expect] "
msg_xp_len = . - msg_xp
msg_fail:
    .ascii "error: expect failed "
    .ascii "(mismatch, unknown name, or missing fixture)\n"
msg_fail_len = . - msg_fail
msg_nobind:
    .ascii "error: expect unknown name "
msg_nobind_len = . - msg_nobind

.section .text

# Save linebuf to stmt_path. rax=0 ok.
xp_save_stmt:
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
    jl      xss_fail
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
xss_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

# Write rsi/rdx bytes to got_path. rax=0 ok.
xp_write_got:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    mov     rax, 2
    lea     rdi, [rip+got_path]
    mov     rsi, 0x241
    mov     rdx, 0644
    syscall
    cmp     rax, 0
    jl      xwg_fail
    mov     rbx, rax
    mov     rax, 1
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    syscall
    mov     rax, 3
    mov     rdi, rbx
    syscall
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret
xwg_fail:
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret

# Parse mode then name into xp_name. After "expect ". rax=0 ok.
xp_parse_name:
    push    rbx
    push    r12
    lea     rbx, [rip+linebuf]
    call    skip_ws
    mov     rbx, rax
    # skip "expect"
    add     rbx, 6
    call    skip_ws_from_rbx
    mov     rbx, rax
    # skip mode token
xp_skip_mode:
    mov     al, [rbx]
    cmp     al, 0
    je      xpn_fail
    cmp     al, ' '
    je      xpn_after_mode
    cmp     al, 9
    je      xpn_after_mode
    inc     rbx
    jmp     xp_skip_mode
xpn_after_mode:
    call    skip_ws_from_rbx
    mov     rbx, rax
    lea     rdi, [rip+xp_name]
    xor     rcx, rcx
xpn_copy:
    mov     al, [rbx+rcx]
    cmp     al, 0
    je      xpn_done
    cmp     al, ' '
    je      xpn_done
    cmp     al, 9
    je      xpn_done
    cmp     rcx, 62
    jge     xpn_done
    mov     [rdi+rcx], al
    inc     rcx
    jmp     xpn_copy
xpn_done:
    mov     byte ptr [rdi+rcx], 0
    test    rcx, rcx
    jz      xpn_fail
    xor     rax, rax
    pop     r12
    pop     rbx
    ret
xpn_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

expect_dispatch:
    push    rbx
    call    xp_parse_name
    test    rax, rax
    jnz     xd_fail
    lea     rdi, [rip+xp_name]
    call    vars_get
    test    rax, rax
    jz      xd_nobind
    # rax=value rcx=len
    mov     rsi, rax
    mov     rdx, rcx
    call    xp_write_got
    test    rax, rax
    jnz     xd_fail
    call    xp_save_stmt
    test    rax, rax
    jnz     xd_fail
    lea     rax, [rip+xp_bin]
    mov     [rip+xp_argv], rax
    lea     rax, [rip+flg_dry]
    mov     [rip+xp_argv+8], rax
    lea     rax, [rip+flg_stmt]
    mov     [rip+xp_argv+16], rax
    lea     rax, [rip+stmt_path]
    mov     [rip+xp_argv+24], rax
    lea     rax, [rip+flg_gotf]
    mov     [rip+xp_argv+32], rax
    lea     rax, [rip+got_path]
    mov     [rip+xp_argv+40], rax
    lea     rax, [rip+flg_out]
    mov     [rip+xp_argv+48], rax
    lea     rax, [rip+out_path]
    mov     [rip+xp_argv+56], rax
    mov     qword ptr [rip+xp_argv+64], 0
    lea     rdi, [rip+xp_bin]
    lea     rsi, [rip+xp_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     xd_fail
    # Companion already printed [expect] pass on stdout.
    xor     rax, rax
    pop     rbx
    ret
xd_nobind:
    lea     rsi, [rip+msg_nobind]
    mov     rdx, msg_nobind_len
    call    write_stdout
    lea     rsi, [rip+xp_name]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+xp_name]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
xd_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
