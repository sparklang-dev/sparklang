# Spark typed extract — fork/exec spark-extract to validate a fixture
# against the inline schema. The schema block may sit on one line or
# span several, so lines accumulate into xt_stmt until the closing }.
#
# extract_pending is read by interpret_line: while non-zero, every
# source line is routed here instead of the keyword dispatch, so a
# `}` on its own line closes the schema rather than a with-tools scope.

.intel_syntax noprefix
.global extract_dispatch
.global extract_feed
.global extract_pending

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
.extern current_model

XT_MAX = 8192

.section .bss
.lcomm xt_argv, 128
.lcomm xt_reply, 65536
.lcomm xt_stmt, XT_MAX
.lcomm xt_len, 8
.lcomm extract_pending, 8

.section .rodata
xt_bin:
    .ascii "./spark-extract\0"
flg_dry:
    .ascii "--dry\0"
flg_live:
    .ascii "--live\0"
flg_stmt:
    .ascii "--stmt-file\0"
flg_out:
    .ascii "--out\0"
flg_model:
    .ascii "--model\0"
xt_default_model:
    .ascii "fast\0"
stmt_path:
    .ascii "/tmp/spark-extract-stmt.txt\0"
out_path:
    .ascii "/tmp/spark-extract-out.txt\0"
msg_xt:
    .ascii "[extract] "
msg_xt_len = . - msg_xt
msg_fail:
    .ascii "error: extract failed "
    .ascii "(schema, missing fixture, or field validation)\n"
msg_fail_len = . - msg_fail
msg_long:
    .ascii "error: extract statement too long\n"
msg_long_len = . - msg_long

.section .text

# Append linebuf + '\n' to xt_stmt. Returns rax=0 ok, 1 overflow.
xt_append:
    push    rbx
    push    r12
    push    r13
    lea     rsi, [rip+linebuf]
    call    strlen
    mov     r12, rax                # line length
    mov     r13, [rip+xt_len]
    lea     rax, [r13+r12]
    add     rax, 2
    cmp     rax, XT_MAX
    jge     xa_over
    lea     rdi, [rip+xt_stmt]
    add     rdi, r13
    lea     rsi, [rip+linebuf]
    xor     rbx, rbx
xa_copy:
    cmp     rbx, r12
    jge     xa_nl
    mov     al, [rsi+rbx]
    mov     [rdi+rbx], al
    inc     rbx
    jmp     xa_copy
xa_nl:
    mov     byte ptr [rdi+rbx], 10
    inc     rbx
    mov     byte ptr [rdi+rbx], 0
    add     r13, rbx
    mov     [rip+xt_len], r13
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret
xa_over:
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret

# Is the accumulated statement complete? rax=1 yes, 0 keep reading.
#
# Complete means both the schema block has closed ('}') and the result
# binding has arrived ('->'). Requiring both matters: '}' alone fires the
# run before `from`/`fixture` are read when the closer sits on its own
# line, and the arrow alone would fire mid-schema if a field default ever
# contained one. The arrow must also land on the final line, because
# bind_arrow_from_line reads linebuf rather than this buffer.
xt_stmt_complete:
    lea     rdi, [rip+xt_stmt]
    xor     rcx, rcx
    xor     r8, r8                  # saw '}'
    xor     r9, r9                  # saw '->'
xsc_loop:
    mov     al, [rdi+rcx]
    test    al, al
    je      xsc_done
    cmp     al, '}'
    jne     xsc_arrow
    mov     r8, 1
    jmp     xsc_next
xsc_arrow:
    cmp     al, '-'
    jne     xsc_next
    cmp     byte ptr [rdi+rcx+1], '>'
    jne     xsc_next
    mov     r9, 1
xsc_next:
    inc     rcx
    jmp     xsc_loop
xsc_done:
    test    r8, r8
    jz      xsc_no
    test    r9, r9
    jz      xsc_no
    mov     rax, 1
    ret
xsc_no:
    xor     rax, rax
    ret

# Write xt_stmt to stmt_path. rax=0 ok, 1 fail.
xt_save:
    push    rbx
    push    r12
    mov     r12, [rip+xt_len]
    mov     rax, 2
    lea     rdi, [rip+stmt_path]
    mov     rsi, 0x241              # O_WRONLY|O_CREAT|O_TRUNC
    mov     rdx, 0644
    syscall
    cmp     rax, 0
    jl      xs_fail
    mov     rbx, rax
    mov     rax, 1
    mov     rdi, rbx
    lea     rsi, [rip+xt_stmt]
    mov     rdx, r12
    syscall
    mov     rax, 3
    mov     rdi, rbx
    syscall
    xor     rax, rax
    pop     r12
    pop     rbx
    ret
xs_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

# Read out_path into xt_reply. rax=buf, rcx=len; rax=0 on failure.
xt_read_out:
    push    rbx
    mov     rax, 2
    lea     rdi, [rip+out_path]
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      xro_fail
    mov     rbx, rax
    mov     rax, 0
    mov     rdi, rbx
    lea     rsi, [rip+xt_reply]
    mov     rdx, 65535
    syscall
    mov     rcx, rax
    push    rcx
    mov     rax, 3
    mov     rdi, rbx
    syscall
    pop     rcx
    cmp     rcx, 0
    jle     xro_fail
    lea     rdi, [rip+xt_reply]
    mov     byte ptr [rdi+rcx], 0
    cmp     byte ptr [rdi+rcx-1], 10
    jne     xro_ok
    dec     rcx
    mov     byte ptr [rdi+rcx], 0
xro_ok:
    lea     rax, [rip+xt_reply]
    pop     rbx
    ret
xro_fail:
    xor     rax, rax
    xor     rcx, rcx
    pop     rbx
    ret

# First line of an extract statement.
extract_dispatch:
    push    rbx
    mov     qword ptr [rip+xt_len], 0
    mov     qword ptr [rip+extract_pending], 0
    call    xt_append
    test    rax, rax
    jnz     xd_toolong
    call    xt_stmt_complete
    test    rax, rax
    jnz     xt_run
    # Schema block still open — take the following lines.
    mov     qword ptr [rip+extract_pending], 1
    pop     rbx
    ret

# Continuation line while extract_pending is set.
extract_feed:
    push    rbx
    call    xt_append
    test    rax, rax
    jnz     xd_toolong
    call    xt_stmt_complete
    test    rax, rax
    jnz     xt_run
    pop     rbx
    ret

xt_run:
    mov     qword ptr [rip+extract_pending], 0
    call    xt_save
    test    rax, rax
    jnz     xd_fail
    lea     rax, [rip+xt_bin]
    mov     [rip+xt_argv], rax
    cmp     qword ptr [rip+flag_live], 0
    jne     xt_live
    lea     rax, [rip+flg_dry]
    jmp     xt_mode
xt_live:
    lea     rax, [rip+flg_live]
xt_mode:
    mov     [rip+xt_argv+8], rax
    lea     rax, [rip+flg_stmt]
    mov     [rip+xt_argv+16], rax
    lea     rax, [rip+stmt_path]
    mov     [rip+xt_argv+24], rax
    lea     rax, [rip+flg_out]
    mov     [rip+xt_argv+32], rax
    lea     rax, [rip+out_path]
    mov     [rip+xt_argv+40], rax
    # Live needs --model (current_model from `model …`, else fast)
    cmp     qword ptr [rip+flag_live], 0
    je      xt_argv_done
    lea     rax, [rip+flg_model]
    mov     [rip+xt_argv+48], rax
    cmp     byte ptr [rip+current_model], 0
    jne     xt_have_model
    lea     rax, [rip+xt_default_model]
    jmp     xt_set_model
xt_have_model:
    lea     rax, [rip+current_model]
xt_set_model:
    mov     [rip+xt_argv+56], rax
    mov     qword ptr [rip+xt_argv+64], 0
    jmp     xt_exec
xt_argv_done:
    mov     qword ptr [rip+xt_argv+48], 0
xt_exec:
    lea     rdi, [rip+xt_bin]
    lea     rsi, [rip+xt_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     xd_fail
    call    xt_read_out
    test    rax, rax
    jz      xd_fail
    push    rax
    push    rcx
    lea     rsi, [rip+msg_xt]
    mov     rdx, msg_xt_len
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

xd_toolong:
    lea     rsi, [rip+msg_long]
    mov     rdx, msg_long_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit

xd_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
