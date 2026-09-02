# Standalone harness for engine layout selftests.
.intel_syntax noprefix
.global _start
.extern spark_layout_selftest
.extern spark_layout_selftest_table

.section .text
_start:
    call    spark_layout_selftest
    test    eax, eax
    jnz     1f
    call    spark_layout_selftest_table
1:  mov     edi, eax
    mov     rax, 60
    syscall
