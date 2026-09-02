# Spark live embed/retrieve — fork/exec spark-rag-http
# Dry-run path stays in asm/spark.s; this unit only when --live.

.intel_syntax noprefix
.global embed_live_dispatch
.global retrieve_live_dispatch

.extern write_stdout
.extern extract_quote
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern fork_exec_wait
.extern flag_live
.extern linebuf
.extern msg_nl
.extern msg_reply
.extern msg_reply_len
.extern sys_exit

.section .bss
.lcomm rag_argv, 128
.lcomm rag_reply, 65536

.section .rodata
rag_bin:
    .ascii "./spark-rag-http\0"
flg_live:
    .ascii "--live\0"
flg_embed:
    .ascii "--embed\0"
flg_retrieve:
    .ascii "--retrieve\0"
flg_tf:
    .ascii "--text-file\0"
flg_out:
    .ascii "--out\0"
flg_project:
    .ascii "--project\0"
proj_docs:
    .ascii "docs\0"
flg_audience:
    .ascii "--audience\0"
aud_op:
    .ascii "operator\0"
text_path:
    .ascii "/tmp/spark-rag-text.txt\0"
out_path:
    .ascii "/tmp/spark-rag-out.txt\0"
msg_embed_live:
    .ascii "[embed] live "
msg_embed_live_len = . - msg_embed_live
msg_retrieve_live:
    .ascii "[retrieve] live "
msg_retrieve_live_len = . - msg_retrieve_live
msg_fail:
    .ascii "error: spark-rag-http failed "
    .ascii "(AI_GATEWAY_URL / RAG_GATEWAY_URL / SPARK_GATEWAY_KEY; "
    .ascii "401=credential unavailable)\n"
msg_fail_len = . - msg_fail
msg_need_live:
    .ascii "error: rag live dispatch without --live\n"
msg_need_live_len = . - msg_need_live

.section .text

rag_save_quote:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      rs_fail
    mov     r12, rax
    mov     r13, rcx
    mov     rax, 2
    lea     rdi, [rip+text_path]
    mov     rsi, 0x241
    mov     rdx, 0644
    syscall
    cmp     rax, 0
    jl      rs_fail
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
rs_fail:
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret

rag_read_out:
    push    rbx
    mov     rax, 2
    lea     rdi, [rip+out_path]
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      rro_fail
    mov     rbx, rax
    mov     rax, 0
    mov     rdi, rbx
    lea     rsi, [rip+rag_reply]
    mov     rdx, 65535
    syscall
    mov     rcx, rax
    push    rcx
    mov     rax, 3
    mov     rdi, rbx
    syscall
    pop     rcx
    cmp     rcx, 0
    jle     rro_fail
    lea     rdi, [rip+rag_reply]
    mov     byte ptr [rdi+rcx], 0
    lea     rax, [rip+rag_reply]
    pop     rbx
    ret
rro_fail:
    xor     rax, rax
    xor     rcx, rcx
    pop     rbx
    ret

embed_live_dispatch:
    push    rbx
    cmp     qword ptr [rip+flag_live], 0
    jne     eld_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
eld_go:
    lea     rsi, [rip+msg_embed_live]
    mov     rdx, msg_embed_live_len
    call    write_stdout
    call    rag_save_quote
    test    rax, rax
    jnz     eld_fail
    lea     rax, [rip+rag_bin]
    mov     [rip+rag_argv], rax
    lea     rax, [rip+flg_live]
    mov     [rip+rag_argv+8], rax
    lea     rax, [rip+flg_embed]
    mov     [rip+rag_argv+16], rax
    lea     rax, [rip+flg_tf]
    mov     [rip+rag_argv+24], rax
    lea     rax, [rip+text_path]
    mov     [rip+rag_argv+32], rax
    lea     rax, [rip+flg_out]
    mov     [rip+rag_argv+40], rax
    lea     rax, [rip+out_path]
    mov     [rip+rag_argv+48], rax
    mov     qword ptr [rip+rag_argv+56], 0
    lea     rdi, [rip+rag_bin]
    lea     rsi, [rip+rag_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     eld_fail
    call    rag_read_out
    test    rax, rax
    jz      eld_fail
    push    rax
    push    rcx
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
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
eld_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit

retrieve_live_dispatch:
    push    rbx
    cmp     qword ptr [rip+flag_live], 0
    jne     rld_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
rld_go:
    lea     rsi, [rip+msg_retrieve_live]
    mov     rdx, msg_retrieve_live_len
    call    write_stdout
    call    rag_save_quote
    test    rax, rax
    jnz     rld_fail
    lea     rax, [rip+rag_bin]
    mov     [rip+rag_argv], rax
    lea     rax, [rip+flg_live]
    mov     [rip+rag_argv+8], rax
    lea     rax, [rip+flg_retrieve]
    mov     [rip+rag_argv+16], rax
    lea     rax, [rip+flg_tf]
    mov     [rip+rag_argv+24], rax
    lea     rax, [rip+text_path]
    mov     [rip+rag_argv+32], rax
    lea     rax, [rip+flg_project]
    mov     [rip+rag_argv+40], rax
    lea     rax, [rip+proj_docs]
    mov     [rip+rag_argv+48], rax
    lea     rax, [rip+flg_audience]
    mov     [rip+rag_argv+56], rax
    lea     rax, [rip+aud_op]
    mov     [rip+rag_argv+64], rax
    lea     rax, [rip+flg_out]
    mov     [rip+rag_argv+72], rax
    lea     rax, [rip+out_path]
    mov     [rip+rag_argv+80], rax
    mov     qword ptr [rip+rag_argv+88], 0
    lea     rdi, [rip+rag_bin]
    lea     rsi, [rip+rag_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     rld_fail
    call    rag_read_out
    test    rax, rax
    jz      rld_fail
    push    rax
    push    rcx
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
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
rld_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
