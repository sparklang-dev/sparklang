# Spark IDE — editor presentation (no Electron, no Qt).
# Paints text-buffer lines + gutter numbers + cursor via engine_paint.
#
# Stable ABI (core owns buffer; paint owns presentation):
#
# SeIdeCursor (8 bytes) — paint-owned global `ide_cursor`:
#   +0  i32 row   (0-based)
#   +4  i32 col   (0-based)
#
# Core buffer (ide_ops.s — exported):
#   ide_buf       u8[IDE_BUF_CAP]
#   ide_buf_len   u64 byte count
# Core calls ide_paint_bind(ide_buf, ide_buf_len) after mutate.
#
# Paint view bind (no BSS fight with core):
#   ide_paint_bind(rdi=ptr, rsi=len)  — view for next paint
#   ide_paint_bind(0,0)               — use paint fixture local store
#
# API:
#   ide_cursor_set       edi=row esi=col
#   ide_paint_bind       rdi=ptr rsi=len
#   ide_paint_load_cstr  rdi=cstr → local store + bind
#   ide_status_set       rdi=ptr rsi=len → top status strip (path)
#   ide_ai_set           rdi=ptr rsi=len → AI strip text
#   ide_paint_editor     paints status + view + AI into engine_paint FB
#   ide_paint_fixture    demo → out/ide/editor.ppm
#   ide_paint_write_ppm  rdi=path
.intel_syntax noprefix

.global ide_cursor
.global ide_cursor_set
.global ide_paint_bind
.global ide_paint_load_cstr
.global ide_paint_editor
.global ide_paint_fixture
.global ide_paint_write_ppm
.global ide_ai_set
.global ide_status_set

.extern engine_paint_init
.extern engine_paint_clear
.extern engine_paint_fill_rect
.extern engine_paint_text
.extern engine_paint_write_ppm

.equ IDE_LOCAL_MAX, 4096
.equ IDE_AI_MAX, 128
.equ IDE_STATUS_MAX, 40
.equ IDE_W, 320
.equ IDE_H, 160
.equ IDE_PANEL_H, 24
.equ IDE_STATUS_H, 16
.equ IDE_CHAR_W, 8
.equ IDE_CHAR_H, 8
.equ IDE_GUTTER_W, 40
.equ IDE_TEXT_X, 44
.equ IDE_LINE_MAX, 80
.equ SYS_WRITE, 1

.section .bss
.align 16
ide_local_bytes:
    .space IDE_LOCAL_MAX
.align 8
ide_view_ptr:
    .space 8
ide_view_len:
    .space 8
.align 4
ide_cursor:
    .space 8
ide_nlines:
    .space 4
ide_line_scratch:
    .space IDE_LINE_MAX + 1
ide_num_scratch:
    .space 16
ide_ai_bytes:
    .space IDE_AI_MAX
ide_ai_len:
    .space 4
ide_status_bytes:
    .space IDE_STATUS_MAX
ide_status_len:
    .space 4

.section .data

fixture_path:
    .asciz "out/ide/editor.ppm"
fixture_text:
    .ascii "model code\n"
    .ascii "print \"hi\"\n"
    .ascii "# spark ide\n"
    .byte 0
fixture_ai:
    .ascii "AI · Gravity pulls masses together."
    .byte 0
fixture_status:
    .ascii "examples/hello.spark"
    .byte 0

msg_ok:
    .ascii "{\"op\":\"ide.paint\",\"ppm\":\"out/ide/editor.ppm\","
    .ascii "\"w\":320,\"h\":160,\"gutter\":true,\"cursor\":true,"
    .ascii "\"status_strip\":true,\"ai_panel\":true}\n"
msg_ok_len = . - msg_ok
ai_idle:
    .ascii "AI · idle"
    .byte 0
status_idle:
    .ascii "untitled"
    .byte 0

.section .text

ide_sys_write:
    mov     rax, SYS_WRITE
    syscall
    ret

# ide_cursor_set(edi=row, esi=col)
ide_cursor_set:
    mov     [rip+ide_cursor], edi
    mov     [rip+ide_cursor+4], esi
    xor     eax, eax
    ret

# ide_status_set(rdi=ptr, rsi=len) — top status strip (path / untitled)
ide_status_set:
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rbx, rsi
    test    r12, r12
    jz      .st_idle
    test    rbx, rbx
    jz      .st_idle
    cmp     rbx, IDE_STATUS_MAX - 1
    jl      .st_len_ok
    mov     rbx, IDE_STATUS_MAX - 1
.st_len_ok:
    lea     rdi, [rip+ide_status_bytes]
    xor     ecx, ecx
.st_copy:
    cmp     rcx, rbx
    jge     .st_term
    mov     al, [r12+rcx]
    cmp     al, 10
    je      .st_sp
    cmp     al, 13
    je      .st_sp
    mov     [rdi+rcx], al
    jmp     .st_next
.st_sp:
    mov     byte ptr [rdi+rcx], ' '
.st_next:
    inc     rcx
    jmp     .st_copy
.st_term:
    mov     byte ptr [rdi+rcx], 0
    mov     [rip+ide_status_len], ecx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
.st_idle:
    lea     rsi, [rip+status_idle]
    lea     rdi, [rip+ide_status_bytes]
    xor     ecx, ecx
.st_idle_copy:
    mov     al, [rsi+rcx]
    mov     [rdi+rcx], al
    test    al, al
    jz      .st_idle_done
    inc     rcx
    cmp     rcx, IDE_STATUS_MAX - 1
    jl      .st_idle_copy
    mov     byte ptr [rdi+rcx], 0
.st_idle_done:
    mov     [rip+ide_status_len], ecx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

# ide_ai_set(rdi=ptr, rsi=len) — AI strip text (teal panel)
ide_ai_set:
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rbx, rsi
    test    r12, r12
    jz      .ai_idle
    test    rbx, rbx
    jz      .ai_idle
    cmp     rbx, IDE_AI_MAX - 1
    jl      .ai_len_ok
    mov     rbx, IDE_AI_MAX - 1
.ai_len_ok:
    lea     rdi, [rip+ide_ai_bytes]
    xor     ecx, ecx
.ai_copy:
    cmp     rcx, rbx
    jge     .ai_term
    mov     al, [r12+rcx]
    cmp     al, 10
    je      .ai_sp
    cmp     al, 13
    je      .ai_sp
    mov     [rdi+rcx], al
    jmp     .ai_next
.ai_sp:
    mov     byte ptr [rdi+rcx], ' '
.ai_next:
    inc     rcx
    jmp     .ai_copy
.ai_term:
    mov     byte ptr [rdi+rcx], 0
    mov     [rip+ide_ai_len], ecx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
.ai_idle:
    lea     rsi, [rip+ai_idle]
    lea     rdi, [rip+ide_ai_bytes]
    xor     ecx, ecx
.ai_idle_copy:
    mov     al, [rsi+rcx]
    mov     [rdi+rcx], al
    test    al, al
    jz      .ai_idle_done
    inc     rcx
    cmp     rcx, IDE_AI_MAX - 1
    jl      .ai_idle_copy
    mov     byte ptr [rdi+rcx], 0
.ai_idle_done:
    mov     [rip+ide_ai_len], ecx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

# Count lines in view → ide_nlines
ide_recount_lines:
    push    rbx
    push    r12
    mov     r12, [rip+ide_view_ptr]
    mov     rbx, [rip+ide_view_len]
    xor     ecx, ecx
    test    r12, r12
    jz      .rc_zero
    test    rbx, rbx
    jz      .rc_zero
    xor     edx, edx
.rc_loop:
    cmp     rdx, rbx
    jge     .rc_tail
    movzx   eax, byte ptr [r12+rdx]
    cmp     al, 10
    jne     .rc_next
    inc     ecx
.rc_next:
    inc     rdx
    jmp     .rc_loop
.rc_tail:
    movzx   eax, byte ptr [r12+rbx-1]
    cmp     al, 10
    je      .rc_store
    inc     ecx
.rc_store:
    test    ecx, ecx
    jnz     .rc_ok
    mov     ecx, 1
.rc_ok:
    mov     [rip+ide_nlines], ecx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
.rc_zero:
    mov     dword ptr [rip+ide_nlines], 0
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

# ide_paint_bind(rdi=ptr, rsi=len) — 0,0 clears to empty local
ide_paint_bind:
    test    rdi, rdi
    jnz     .pb_set
    lea     rdi, [rip+ide_local_bytes]
    xor     esi, esi
.pb_set:
    mov     [rip+ide_view_ptr], rdi
    mov     [rip+ide_view_len], rsi
    call    ide_recount_lines
    xor     eax, eax
    ret

# ide_paint_load_cstr(rdi=cstr) → copy into local + bind
ide_paint_load_cstr:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rip+ide_local_bytes]
    xor     ebx, ebx
    test    r12, r12
    jz      .pl_bind
.pl_loop:
    movzx   eax, byte ptr [r12]
    test    eax, eax
    jz      .pl_bind
    cmp     ebx, IDE_LOCAL_MAX
    jge     .pl_bind
    mov     [r13+rbx], al
    inc     ebx
    inc     r12
    jmp     .pl_loop
.pl_bind:
    mov     rdi, r13
    mov     rsi, rbx
    call    ide_paint_bind
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

# Copy line L (0-based) into ide_line_scratch. edi=line → eax 0/-1
ide_copy_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14d, edi
    mov     r12, [rip+ide_view_ptr]
    mov     r13, [rip+ide_view_len]
    xor     ebx, ebx
    xor     ecx, ecx
    test    r12, r12
    jz      .cl_bad
    cmp     r14d, 0
    jl      .cl_bad
.find_start:
    cmp     ebx, r14d
    je      .cl_copy
    cmp     rcx, r13
    jge     .cl_bad
    movzx   eax, byte ptr [r12+rcx]
    inc     rcx
    cmp     al, 10
    jne     .find_start
    inc     ebx
    jmp     .find_start
.cl_copy:
    xor     edx, edx
    lea     rbx, [rip+ide_line_scratch]
.cl_chars:
    cmp     rcx, r13
    jge     .cl_term
    cmp     edx, IDE_LINE_MAX
    jge     .cl_term
    movzx   eax, byte ptr [r12+rcx]
    cmp     al, 10
    je      .cl_term
    mov     [rbx+rdx], al
    inc     edx
    inc     rcx
    jmp     .cl_chars
.cl_term:
    mov     byte ptr [rbx+rdx], 0
    xor     eax, eax
    jmp     .cl_done
.cl_bad:
    lea     rax, [rip+ide_line_scratch]
    mov     byte ptr [rax], 0
    mov     eax, -1
.cl_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# Format 1-based line number, width 4, into ide_num_scratch
ide_fmt_gutter:
    push    rbx
    push    r12
    mov     eax, edi
    lea     r12, [rip+ide_num_scratch]
    mov     byte ptr [r12], ' '
    mov     byte ptr [r12+1], ' '
    mov     byte ptr [r12+2], ' '
    mov     byte ptr [r12+3], ' '
    mov     byte ptr [r12+4], 0
    mov     ebx, 3
    test    eax, eax
    jnz     .fg_div
    mov     byte ptr [r12+3], '0'
    jmp     .fg_done
.fg_div:
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     dl, '0'
    mov     [r12+rbx], dl
    dec     ebx
    cmp     ebx, 0
    jl      .fg_done
    test    eax, eax
    jnz     .fg_div
.fg_done:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

# ide_paint_editor — status + gutter + lines + cursor + AI → paint FB
ide_paint_editor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     edi, IDE_W
    mov     esi, IDE_H
    call    engine_paint_init
    test    eax, eax
    jnz     .pe_fail
    # editor chrome — deep teal (not VS Code purple sludge)
    mov     dil, 12
    mov     sil, 28
    mov     dl, 32
    call    engine_paint_clear
    # top status strip — path / untitled (dark band)
    mov     edi, 0
    mov     esi, 0
    mov     edx, IDE_W
    mov     ecx, IDE_STATUS_H
    mov     r8b, 6
    mov     r9b, 40
    mov     r10b, 44
    call    engine_paint_fill_rect
    cmp     dword ptr [rip+ide_status_len], 0
    jne     .pe_status_text
    xor     edi, edi
    xor     esi, esi
    call    ide_status_set
.pe_status_text:
    mov     edi, 4
    mov     esi, 4
    lea     rdx, [rip+ide_status_bytes]
    mov     r8b, 160
    mov     r9b, 220
    mov     r10b, 200
    call    engine_paint_text
    # gutter between status and AI panel
    mov     edi, 0
    mov     esi, IDE_STATUS_H
    mov     edx, IDE_GUTTER_W
    mov     ecx, IDE_H - IDE_PANEL_H - IDE_STATUS_H
    mov     r8b, 20
    mov     r9b, 48
    mov     r10b, 52
    call    engine_paint_fill_rect
    # text rows fit between status + AI panel
    mov     eax, IDE_H
    sub     eax, IDE_PANEL_H
    sub     eax, IDE_STATUS_H
    xor     edx, edx
    mov     ecx, IDE_CHAR_H
    div     ecx
    mov     r15d, eax
    mov     r14d, [rip+ide_nlines]
    cmp     r14d, r15d
    jle     .pe_rows_ok
    mov     r14d, r15d
.pe_rows_ok:
    xor     r12d, r12d
.pe_line:
    cmp     r12d, r14d
    jge     .pe_cursor
    mov     r13d, r12d
    imul    r13d, IDE_CHAR_H
    add     r13d, IDE_STATUS_H
    mov     edi, r12d
    inc     edi
    call    ide_fmt_gutter
    mov     edi, 4
    mov     esi, r13d
    lea     rdx, [rip+ide_num_scratch]
    mov     r8b, 120
    mov     r9b, 180
    mov     r10b, 170
    call    engine_paint_text
    mov     edi, r12d
    call    ide_copy_line
    mov     edi, IDE_TEXT_X
    mov     esi, r13d
    lea     rdx, [rip+ide_line_scratch]
    mov     r8b, 210
    mov     r9b, 230
    mov     r10b, 220
    call    engine_paint_text
    inc     r12d
    jmp     .pe_line
.pe_cursor:
    mov     eax, [rip+ide_cursor]
    mov     ebx, [rip+ide_cursor+4]
    cmp     eax, 0
    jl      .pe_panel
    cmp     eax, r15d
    jge     .pe_panel
    cmp     ebx, 0
    jl      .pe_panel
    imul    esi, eax, IDE_CHAR_H
    add     esi, IDE_STATUS_H
    imul    edi, ebx, IDE_CHAR_W
    add     edi, IDE_TEXT_X
    mov     edx, 2
    mov     ecx, IDE_CHAR_H
    mov     r8b, 40
    mov     r9b, 220
    mov     r10b, 200
    call    engine_paint_fill_rect
.pe_panel:
    # bottom AI strip — hot teal band
    mov     edi, 0
    mov     esi, IDE_H - IDE_PANEL_H
    mov     edx, IDE_W
    mov     ecx, IDE_PANEL_H
    mov     r8b, 8
    mov     r9b, 72
    mov     r10b, 68
    call    engine_paint_fill_rect
    cmp     dword ptr [rip+ide_ai_len], 0
    jne     .pe_ai_text
    lea     rdi, [rip+ai_idle]
    xor     esi, esi
    call    ide_ai_set
.pe_ai_text:
    mov     edi, 8
    mov     esi, IDE_H - IDE_PANEL_H + 8
    lea     rdx, [rip+ide_ai_bytes]
    mov     r8b, 80
    mov     r9b, 255
    mov     r10b, 220
    call    engine_paint_text
.pe_ok:
    xor     eax, eax
    jmp     .pe_done
.pe_fail:
    mov     eax, -1
.pe_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

ide_paint_write_ppm:
    call    engine_paint_write_ppm
    ret

ide_paint_fixture:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [rip+fixture_text]
    call    ide_paint_load_cstr
    mov     edi, 1
    xor     esi, esi
    call    ide_cursor_set
    lea     rdi, [rip+fixture_status]
    xor     ecx, ecx
.pf_st_len:
    cmp     byte ptr [rdi+rcx], 0
    je      .pf_st_set
    inc     ecx
    jmp     .pf_st_len
.pf_st_set:
    mov     esi, ecx
    call    ide_status_set
    lea     rdi, [rip+fixture_ai]
    mov     esi, 0
    # len via strlen-ish
    xor     ecx, ecx
.pf_ai_len:
    cmp     byte ptr [rdi+rcx], 0
    je      .pf_ai_set
    inc     ecx
    jmp     .pf_ai_len
.pf_ai_set:
    mov     esi, ecx
    call    ide_ai_set
    call    ide_paint_editor
    test    eax, eax
    jnz     .pf_fail
    lea     rdi, [rip+fixture_path]
    call    engine_paint_write_ppm
    test    eax, eax
    jnz     .pf_fail
    mov     rdi, 1
    lea     rsi, [rip+msg_ok]
    mov     rdx, msg_ok_len
    call    ide_sys_write
    xor     eax, eax
    pop     rbp
    ret
.pf_fail:
    mov     eax, -1
    pop     rbp
    ret
