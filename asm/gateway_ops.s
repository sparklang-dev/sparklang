# Spark gateway encrypt on/off — toggles encrypt-to-model path
# Exports: gateway_ops_dispatch
.intel_syntax noprefix
.global gateway_ops_dispatch

.extern linebuf
.extern write_stdout
.extern contains
.extern strlen
.extern sys_exit
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern enc_gateway_on
.extern enc_key_loaded
.extern enc_key_path
.extern ask_probe_dispatch

.section .data
msg_gateway: .ascii "[gateway] "
msg_gateway_len = . - msg_gateway
msg_arrow:   .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_nl:      .ascii "\n"

needle_encrypt: .ascii "encrypt\0"
needle_probe:   .ascii "probe\0"
needle_on:      .ascii " on\0"
needle_off:     .ascii " off\0"
# also match trailing "on" / "off" without requiring leading space only
needle_on2:     .ascii "on\0"
needle_off2:    .ascii "off\0"

msg_on:
    .ascii "{\"op\":\"gateway_encrypt\",\"enabled\":true}\n"
msg_on_len = . - msg_on
msg_off:
    .ascii "{\"op\":\"gateway_encrypt\",\"enabled\":false}\n"
msg_off_len = . - msg_off
msg_need_key:
    .ascii "error: gateway encrypt on requires a loaded key"
    .ascii " (crypto keygen / crypto load key) and"
    .ascii " encrypt gateway enable\n"
msg_need_key_len = . - msg_need_key
msg_unknown:
    .ascii "error: gateway expects: gateway encrypt on|off"
    .ascii " | gateway probe\n"
msg_unknown_len = . - msg_unknown

.section .text

gateway_ops_dispatch:
    push    rbx

    lea     rsi, [rip+msg_gateway]
    mov     rdx, msg_gateway_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_probe]
    call    contains
    test    rax, rax
    jz      gw_try_encrypt
    # gateway probe → same gateway credential check as ask probe
    call    ask_probe_dispatch
    pop     rbx
    ret

gw_try_encrypt:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_encrypt]
    call    contains
    test    rax, rax
    jz      gw_unknown

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_off]
    call    contains
    test    rax, rax
    jnz     gw_off
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_off2]
    call    contains
    test    rax, rax
    jz      gw_try_on
    # careful: "off" contains... actually "on" is substring of nothing in off
    # but "encrypt" doesn't contain off. Check last token via off first done.
    # If needle_off2 matched inside "off" only — also "off" in other words?
    # Fine for MVP.
    jmp     gw_off

gw_try_on:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_on]
    call    contains
    test    rax, rax
    jnz     gw_on
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_on2]
    call    contains
    test    rax, rax
    jnz     gw_on
    jmp     gw_unknown

gw_on:
    cmp     qword ptr [rip+enc_key_loaded], 0
    je      gw_need_key
    cmp     byte ptr [rip+enc_key_path], 0
    je      gw_need_key
    mov     qword ptr [rip+enc_gateway_on], 1
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+msg_on]
    mov     rdx, msg_on_len
    call    write_stdout
    lea     rax, [rip+msg_on]
    mov     rcx, msg_on_len
    dec     rcx
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

gw_off:
    mov     qword ptr [rip+enc_gateway_on], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+msg_off]
    mov     rdx, msg_off_len
    call    write_stdout
    lea     rax, [rip+msg_off]
    mov     rcx, msg_off_len
    dec     rcx
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

gw_need_key:
    lea     rsi, [rip+msg_need_key]
    mov     rdx, msg_need_key_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

gw_unknown:
    lea     rsi, [rip+msg_unknown]
    mov     rdx, msg_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
