# Standalone entry for spark-ide-paint (editor PPM fixture).
.intel_syntax noprefix
.global _start
.extern ide_paint_fixture

.equ SYS_EXIT, 60
.equ SYS_MKDIR, 83

.section .data
path_out:     .asciz "out"
path_out_ide: .asciz "out/ide"

.section .text
_start:
    lea     rdi, [rip+path_out]
    mov     rsi, 0755
    mov     rax, SYS_MKDIR
    syscall
    lea     rdi, [rip+path_out_ide]
    mov     rsi, 0755
    mov     rax, SYS_MKDIR
    syscall
    call    ide_paint_fixture
    test    eax, eax
    jz      .ok
    mov     edi, 1
    jmp     .die
.ok:
    xor     edi, edi
.die:
    mov     rax, SYS_EXIT
    syscall
