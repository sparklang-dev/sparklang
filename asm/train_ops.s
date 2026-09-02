# Spark live model train/status — fork/exec spark-train-http
# Dry-run stays in asm/model_ops.s; this unit only when --live.

.intel_syntax noprefix
.global train_live_submit
.global train_live_status

.extern write_stdout
.extern fork_exec_wait
.extern flag_live
.extern msg_nl
.extern sys_exit

.section .bss
.lcomm train_argv, 64

.section .rodata
train_bin:
    .ascii "./spark-train-http\0"
flg_live:
    .ascii "--live\0"
flg_submit:
    .ascii "--submit\0"
flg_status:
    .ascii "--status\0"
job_dry:
    .ascii "job-dry-001\0"
msg_fail:
    .ascii "error: spark-train-http failed "
    .ascii "(SPARK_TRAIN_BACKEND / SPARK_TRAIN_URL; "
    .ascii "local-yield needs SPARK_TRAIN_UNIT_ALLOWLIST)\n"
msg_fail_len = . - msg_fail
msg_need_live:
    .ascii "error: train live dispatch without --live\n"
msg_need_live_len = . - msg_need_live

.section .text

train_live_submit:
    cmp     qword ptr [rip+flag_live], 0
    jne     tls_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
tls_go:
    lea     rax, [rip+train_bin]
    mov     qword ptr [rip+train_argv], rax
    lea     rax, [rip+flg_live]
    mov     qword ptr [rip+train_argv+8], rax
    lea     rax, [rip+flg_submit]
    mov     qword ptr [rip+train_argv+16], rax
    mov     qword ptr [rip+train_argv+24], 0
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
    lea     rax, [rip+train_bin]
    mov     qword ptr [rip+train_argv], rax
    lea     rax, [rip+flg_live]
    mov     qword ptr [rip+train_argv+8], rax
    lea     rax, [rip+flg_status]
    mov     qword ptr [rip+train_argv+16], rax
    lea     rax, [rip+job_dry]
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
