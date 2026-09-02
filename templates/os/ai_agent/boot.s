# AgentOS educational boot sector (BIOS, 16-bit)
# Assembles to 512 bytes with 0x55AA signature.
# NOT a this host install image — owner-driven media only.
.intel_syntax noprefix
.code16
.global _boot_start
_boot_start:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00
    sti
    mov     si, offset msg
print:
    lodsb
    test    al, al
    jz      hang
    mov     ah, 0x0E
    int     0x10
    jmp     print
hang:
    hlt
    jmp     hang
msg:
    .asciz "AgentOS stub — blueprint only\r\n"
.space 510 - (. - _boot_start)
.byte 0x55, 0xAA
