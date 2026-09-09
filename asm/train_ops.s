# Spark live model train/status — fork/exec spark-train-http
# Dry-run stays in asm/model_ops.s (SPARK_BC TRAIN 0x26 /
# TRAIN_STATUS 0x27 fixtures). This unit only when --live.
# Live HTTP is not SPARK_BC emit (emit BLOCKED in GAS).
#
# Submit: write current linebuf → --spark-line (method/dataset/base/out).
# Status: poll the quoted job id from `model status "…"`, not a hardcode.
# Methods include spark_reply_pack (voice+text overlay, no fabricate).

.intel_syntax noprefix
.global train_live_submit
.global train_live_status

.extern write_stdout
.extern fork_exec_wait
.extern flag_live
.extern msg_nl
.extern sys_exit
.extern linebuf
.extern extract_quote
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern outdir_name

.section .bss
.lcomm train_argv, 128
.lcomm train_job_id, 256

.section .rodata
train_bin:
    .ascii "./spark-train-http\0"
flg_live:
    .ascii "--live\0"
flg_submit:
    .ascii "--submit\0"
flg_status:
    .ascii "--status\0"
flg_spark_line:
    .ascii "--spark-line\0"
line_path:
    .ascii "out/train/.spark-line\0"
train_dir_parent:
    .ascii "out/train\0"
msg_fail:
    .ascii "error: spark-train-http failed "
    .ascii "(SPARK_TRAIN_BACKEND / SPARK_TRAIN_URL; "
    .ascii "local-yield needs SPARK_TRAIN_UNIT_ALLOWLIST)\n"
msg_fail_len = . - msg_fail
msg_need_live:
    .ascii "error: train live dispatch without --live\n"
msg_need_live_len = . - msg_need_live
msg_need_job:
    .ascii "error: model status requires quoted job id "
    .ascii "(got none — refuse hardcoded job-dry-001)\n"
msg_need_job_len = . - msg_need_job

.section .text

# write linebuf to out/train/.spark-line (NUL-terminated)
train_write_line:
    push    rbx
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_dir_parent]
    mov     rsi, 493
    call    sys_mkdir
    lea     rsi, [rip+linebuf]
    call    strlen
    mov     rdx, rax
    lea     rdi, [rip+line_path]
    lea     rsi, [rip+linebuf]
    call    write_bytes_path
    pop     rbx
    ret

train_live_submit:
    cmp     qword ptr [rip+flag_live], 0
    jne     tls_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tls_go:
    call    train_write_line
    lea     rax, [rip+train_bin]
    mov     qword ptr [rip+train_argv], rax
    lea     rax, [rip+flg_live]
    mov     qword ptr [rip+train_argv+8], rax
    lea     rax, [rip+flg_submit]
    mov     qword ptr [rip+train_argv+16], rax
    lea     rax, [rip+flg_spark_line]
    mov     qword ptr [rip+train_argv+24], rax
    lea     rax, [rip+line_path]
    mov     qword ptr [rip+train_argv+32], rax
    mov     qword ptr [rip+train_argv+40], 0
    lea     rdi, [rip+train_bin]
    lea     rsi, [rip+train_argv]
    call    fork_exec_wait
    test    rax, rax
    jz      tls_ok
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tls_ok:
    ret

train_live_status:
    cmp     qword ptr [rip+flag_live], 0
    jne     tlst_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tlst_go:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      tlst_nojob
    test    rcx, rcx
    jz      tlst_nojob
    cmp     rcx, 255
    ja      tlst_nojob
    # copy quoted job id → train_job_id (NUL-terminated)
    mov     rsi, rax
    lea     rdi, [rip+train_job_id]
    mov     rbx, rcx
tlst_copy:
    test    rbx, rbx
    jz      tlst_copied
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rbx
    jmp     tlst_copy
tlst_copied:
    mov     byte ptr [rdi], 0
    jmp     tlst_argv
tlst_nojob:
    lea     rsi, [rip+msg_need_job]
    mov     rdx, msg_need_job_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tlst_argv:
    lea     rax, [rip+train_bin]
    mov     qword ptr [rip+train_argv], rax
    lea     rax, [rip+flg_live]
    mov     qword ptr [rip+train_argv+8], rax
    lea     rax, [rip+flg_status]
    mov     qword ptr [rip+train_argv+16], rax
    lea     rax, [rip+train_job_id]
    mov     qword ptr [rip+train_argv+24], rax
    mov     qword ptr [rip+train_argv+32], 0
    lea     rdi, [rip+train_bin]
    lea     rsi, [rip+train_argv]
    call    fork_exec_wait
    test    rax, rax
    jz      tlst_ok
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tlst_ok:
    ret
