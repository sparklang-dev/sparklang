# Standalone entry for spark-engine-paint fixture (no spark.s).
.intel_syntax noprefix
.global _start
.extern engine_paint_fixture

.equ SYS_EXIT, 60
.equ SYS_MKDIR, 83

.section .data
path_out:        .asciz "out"
path_out_engine: .asciz "out/engine"

.section .text
_start:
    # mkdir -p out/engine (ignore EEXIST)
    lea     rdi, [rip+path_out]
    mov     rsi, 0755
    mov     rax, SYS_MKDIR
    syscall
    lea     rdi, [rip+path_out_engine]
    mov     rsi, 0755
    mov     rax, SYS_MKDIR
    syscall
    call    engine_paint_fixture
    test    eax, eax
    jz      .ok
    mov     edi, 1
    jmp     .die
.ok:
    xor     edi, edi
.die:
    mov     rax, SYS_EXIT
    syscall
