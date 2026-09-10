# Spark voice-agent-loop ops — fork ./spark-voice-loop for dry/CPU.
# Handles: model pairs | model serve helper | expect score |
#          ground | bench | schedule
# Linked with asm/spark.s. No SPARK_BC opcodes (language + companion).

.intel_syntax noprefix
.global voice_loop_run
.global voice_loop_dispatch
.global voice_loop_model_hook
.global voice_loop_expect_hook

.extern write_stdout
.extern fork_exec_wait
.extern linebuf
.extern msg_nl
.extern sys_exit
.extern strlen
.extern contains
.extern flag_live
.extern set_last_from_rcx
.extern bind_arrow_from_line

.section .bss
.lcomm vl_argv, 128

.section .rodata
vl_bin:
    .ascii "./spark-voice-loop\0"
flg_dry:
    .ascii "--dry\0"
flg_live:
    .ascii "--live\0"
flg_stmt:
    .ascii "--stmt-file\0"
stmt_path:
    .ascii "/tmp/spark-voice-loop-stmt.txt\0"

needle_pairs:   .ascii "pairs\0"
needle_serve:   .ascii "serve helper\0"
needle_score:   .ascii "score\0"
needle_ground:  .ascii "ground\0"
needle_bench:   .ascii "bench\0"
needle_sched:   .ascii "schedule\0"

msg_fail:
    .ascii "error: spark-voice-loop failed "
    .ascii "(pairs/expect score/serve/ground/bench/schedule)\n"
msg_fail_len = . - msg_fail
msg_vl:
    .ascii "[voice-loop] "
msg_vl_len = . - msg_vl

.section .text

# Save linebuf → stmt_path. rax=0 ok.
vl_save_stmt:
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
    jl      vss_fail
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
vss_fail:
    mov     rax, 1
    pop     r12
    pop     rbx
    ret

# Fork companion. rax=0 ok.
vl_fork:
    push    rbx
    call    vl_save_stmt
    test    rax, rax
    jnz     vf_fail
    lea     rax, [rip+vl_bin]
    mov     qword ptr [rip+vl_argv], rax
    cmp     qword ptr [rip+flag_live], 0
    jne     vf_live
    lea     rax, [rip+flg_dry]
    jmp     vf_flag
vf_live:
    lea     rax, [rip+flg_live]
vf_flag:
    mov     qword ptr [rip+vl_argv+8], rax
    lea     rax, [rip+flg_stmt]
    mov     qword ptr [rip+vl_argv+16], rax
    lea     rax, [rip+stmt_path]
    mov     qword ptr [rip+vl_argv+24], rax
    mov     qword ptr [rip+vl_argv+32], 0
    lea     rdi, [rip+vl_bin]
    lea     rsi, [rip+vl_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     vf_fail
    xor     rax, rax
    pop     rbx
    ret
vf_fail:
    mov     rax, 1
    pop     rbx
    ret

# voice_loop_run — always fork companion for current linebuf
voice_loop_run:
    push    rbx
    call    vl_fork
    test    rax, rax
    jnz     vlr_fail
    lea     rax, [rip+msg_vl]
    mov     rcx, msg_vl_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    xor     rax, rax
    pop     rbx
    ret
vlr_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit

# voice_loop_dispatch — top-level ground|bench|schedule (alias)
voice_loop_dispatch:
    jmp     voice_loop_run

# voice_loop_model_hook — model pairs | model serve helper
# rax=1 handled, 0 not ours
voice_loop_model_hook:
    push    rbx
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_pairs]
    call    contains
    test    rax, rax
    jnz     vmh_go
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_serve]
    call    contains
    test    rax, rax
    jnz     vmh_go
    xor     rax, rax
    pop     rbx
    ret
vmh_go:
    call    vl_fork
    test    rax, rax
    jnz     vmh_fail
    # bind last from a short ok marker
    lea     rax, [rip+msg_vl]
    mov     rcx, msg_vl_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    mov     rax, 1
    pop     rbx
    ret
vmh_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit

# voice_loop_expect_hook — expect score …
# rax=1 handled, 0 not ours
voice_loop_expect_hook:
    push    rbx
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_score]
    call    contains
    test    rax, rax
    jz      veh_no
    call    vl_fork
    test    rax, rax
    jnz     veh_fail
    mov     rax, 1
    pop     rbx
    ret
veh_no:
    xor     rax, rax
    pop     rbx
    ret
veh_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
