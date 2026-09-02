# Optional Spark VM dispatch for engine paint (wiring hooks this).
# Matches linebuf containing "paint" + "fixture" (or "engine paint").
# Does NOT edit spark.s — wiring lane calls engine_paint_dispatch.
.intel_syntax noprefix
.global engine_paint_dispatch

.extern linebuf
.extern write_stdout
.extern contains
.extern engine_paint_fixture

.section .data
needle_paint:   .asciz "paint"
needle_fixture: .asciz "fixture"
needle_engine:  .asciz "engine"
msg_paint:      .ascii "[engine.paint] "
msg_paint_len = . - msg_paint
msg_unk:
    .ascii "error: engine paint expects: engine paint fixture\n"
msg_unk_len = . - msg_unk

.section .text
engine_paint_dispatch:
    push    rbx
    lea     rsi, [rip+msg_paint]
    mov     rdx, msg_paint_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_paint]
    call    contains
    test    rax, rax
    jz      .unk

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fixture]
    call    contains
    test    rax, rax
    jz      .unk

    call    engine_paint_fixture
    pop     rbx
    ret

.unk:
    lea     rsi, [rip+msg_unk]
    mov     rdx, msg_unk_len
    call    write_stdout
    pop     rbx
    ret
