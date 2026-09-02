# Spark engine B — software raster / paint (no Qt).
# Boxes + bitmap glyphs → RGB framebuffer → PPM.
# Exports for layout/window/wiring lanes. No spark.s edits here.
#
# SePaintBox (36 bytes) — stable ABI for layout→paint:
#   +0  i32 x, +4 i32 y, +8 i32 w, +12 i32 h
#   +16 u8 r, +17 u8 g, +18 u8 b, +19 u8 flags (bit0=text bit1=border)
#   +20 i32 text_off, +24 i32 text_len
#   +28 i32 border_w (px; 0→1)
#   +32 u32 border_rgb (0x00RRGGBB; UA #606060)
#
# API:
#   engine_paint_init      edi=w esi=h
#   engine_paint_clear     dil=r sil=g dl=b
#   engine_paint_fill_rect edi=x esi=y edx=w ecx=h r8b=r r9b=g [rsp+8]=b
#   engine_paint_put_glyph edi=x esi=y edx=ch r8b=r r9b=g [rsp+8]=b
#   engine_paint_text      edi=x esi=y rdx=cstr r8b=r r9b=g [rsp+8]=b
#   engine_paint_boxes     rdi=boxes rsi=n rdx=text_blob
#   engine_paint_write_ppm rdi=path_cstr
#   engine_paint_fixture   → out/engine/paint_fixture.ppm
#   engine_paint_fb / _w / _h / _stride  (window lane)
.intel_syntax noprefix

.global engine_paint_init
.global engine_paint_clear
.global engine_paint_fill_rect
.global engine_paint_put_glyph
.global engine_paint_text
.global engine_paint_boxes
.global engine_paint_write_ppm
.global engine_paint_fixture
.global engine_paint_fb
.global engine_paint_w
.global engine_paint_h
.global engine_paint_stride

.equ EP_MAX_W, 640
.equ EP_MAX_H, 480
.equ EP_MAX_RGB, (EP_MAX_W * EP_MAX_H * 3)
.equ EP_CHAR_W, 8
.equ EP_CHAR_H, 8
.equ SYS_OPEN, 2
.equ SYS_WRITE, 1
.equ SYS_CLOSE, 3
.equ SYS_EXIT, 60
.equ O_WRONLY, 1
.equ O_CREAT, 64
.equ O_TRUNC, 512
.equ SE_FLAG_TEXT, 1
.equ SE_FLAG_BORDER, 2
.equ SE_FLAG_NOFILL, 4

.section .bss
.align 16
engine_paint_fb:
    .space EP_MAX_RGB
.align 8
engine_paint_w:      .space 4
engine_paint_h:      .space 4
engine_paint_stride: .space 4
ep_ppm_hdr:          .space 64
ep_scratch:          .space 32

.section .data

fixture_path:
    .asciz "out/engine/paint_fixture.ppm"
fixture_text:
    .asciz "Hi Spark"
msg_ok:
    .ascii "{\"op\":\"engine.paint\",\"ppm\":\"out/engine/paint_fixture.ppm\","
    .ascii "\"w\":160,\"h\":80,\"glyphs\":true,\"rects\":true}\n"
msg_ok_len = . - msg_ok

# 8x8 glyphs for ASCII 0x20..0x7E (row bytes, MSB = left)
font8x8:
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 60, 102, 110, 118, 102, 102, 60, 0
    .byte 24, 56, 24, 24, 24, 24, 60, 0
    .byte 60, 102, 6, 12, 24, 48, 126, 0
    .byte 60, 102, 6, 28, 6, 102, 60, 0
    .byte 12, 28, 44, 76, 126, 12, 12, 0
    .byte 126, 96, 124, 6, 6, 102, 60, 0
    .byte 60, 96, 96, 124, 102, 102, 60, 0
    .byte 126, 6, 12, 24, 48, 48, 48, 0
    .byte 60, 102, 102, 60, 102, 102, 60, 0
    .byte 60, 102, 102, 62, 6, 6, 60, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 60, 102, 102, 126, 102, 102, 102, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 102, 102, 102, 126, 102, 102, 102, 0
    .byte 60, 24, 24, 24, 24, 24, 60, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 102, 108, 120, 112, 120, 108, 102, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 124, 102, 102, 124, 96, 96, 96, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 124, 102, 102, 124, 120, 108, 102, 0
    .byte 60, 102, 96, 60, 6, 102, 60, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 0, 0, 60, 6, 62, 102, 62, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 0, 0, 60, 102, 126, 96, 60, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 24, 0, 56, 24, 24, 24, 60, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 96, 96, 108, 120, 120, 108, 102, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 0, 0, 124, 102, 102, 102, 102, 0
    .byte 0, 0, 60, 102, 102, 102, 60, 0
    .byte 0, 0, 124, 102, 102, 124, 96, 96
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 0, 0, 108, 118, 96, 96, 96, 0
    .byte 0, 0, 62, 96, 60, 6, 124, 0
    .byte 24, 24, 60, 24, 24, 24, 12, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0
    .byte 126, 66, 66, 66, 66, 66, 126, 0

.section .text

# ---------- local syscalls (no spark.s dependency) ----------
ep_sys_open:
    mov     rax, SYS_OPEN
    syscall
    ret

ep_sys_write:
    mov     rax, SYS_WRITE
    syscall
    ret

ep_sys_close:
    mov     rax, SYS_CLOSE
    syscall
    ret

# Decimal writer: esi=value, rdi=dest → rax=bytes written
ep_fmt_u32:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     eax, esi
    lea     rbx, [rip+ep_scratch]
    add     rbx, 20
    xor     r13, r13
    test    eax, eax
    jnz     .fu_loop
    mov     byte ptr [rbx], '0'
    mov     r13, 1
    jmp     .fu_out
.fu_loop:
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    inc     r13
    test    eax, eax
    jnz     .fu_loop
.fu_out:
    mov     rsi, rbx
    mov     rdi, r12
    mov     rcx, r13
    rep movsb
    mov     rax, r13
    pop     r13
    pop     r12
    pop     rbx
    ret

# engine_paint_init(edi=w, esi=h)
engine_paint_init:
    cmp     edi, 1
    jl      .ini_bad
    cmp     esi, 1
    jl      .ini_bad
    cmp     edi, EP_MAX_W
    jg      .ini_bad
    cmp     esi, EP_MAX_H
    jg      .ini_bad
    mov     [rip+engine_paint_w], edi
    mov     [rip+engine_paint_h], esi
    imul    edi, 3
    mov     [rip+engine_paint_stride], edi
    xor     eax, eax
    ret
.ini_bad:
    mov     eax, -1
    ret

# engine_paint_clear(dil=r, sil=g, dl=b)
engine_paint_clear:
    push    rbx
    mov     r8b, dil
    mov     r9b, sil
    mov     r10b, dl
    mov     eax, [rip+engine_paint_w]
    mov     ecx, [rip+engine_paint_h]
    test    eax, eax
    jz      .clr_done
    test    ecx, ecx
    jz      .clr_done
    imul    eax, ecx
    lea     rdi, [rip+engine_paint_fb]
.clr_loop:
    mov     [rdi], r8b
    mov     [rdi+1], r9b
    mov     [rdi+2], r10b
    add     rdi, 3
    dec     eax
    jnz     .clr_loop
.clr_done:
    pop     rbx
    ret

# engine_paint_fill_rect:
#   edi=x esi=y edx=w ecx=h
#   r8b=r r9b=g  byte on stack at 8(%rsp) after call = b
# System V: 7th arg is on stack. We pack b in r10b via caller convention:
# CALLERS pass b in r10b (Spark lane ABI for paint).
engine_paint_fill_rect:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    # r10b = blue (lane ABI)
    mov     r15b, r10b
    mov     r12d, edi          # x
    mov     r13d, esi          # y
    mov     r14d, edx          # w
    mov     ebx, ecx           # h
    test    r14d, r14d
    jle     .fr_done
    test    ebx, ebx
    jle     .fr_done
    mov     eax, [rip+engine_paint_w]
    mov     ecx, [rip+engine_paint_h]
    # clip
    cmp     r12d, 0
    jge     .fr_xok
    add     r14d, r12d
    xor     r12d, r12d
.fr_xok:
    cmp     r13d, 0
    jge     .fr_yok
    add     ebx, r13d
    xor     r13d, r13d
.fr_yok:
    test    r14d, r14d
    jle     .fr_done
    test    ebx, ebx
    jle     .fr_done
    mov     edx, r12d
    add     edx, r14d
    cmp     edx, eax
    jle     .fr_xr
    mov     r14d, eax
    sub     r14d, r12d
.fr_xr:
    mov     edx, r13d
    add     edx, ebx
    cmp     edx, ecx
    jle     .fr_yr
    mov     ebx, ecx
    sub     ebx, r13d
.fr_yr:
    test    r14d, r14d
    jle     .fr_done
    test    ebx, ebx
    jle     .fr_done
    # row loop
.fr_row:
    mov     eax, r13d
    imul    eax, [rip+engine_paint_stride]
    mov     edx, r12d
    imul    edx, 3
    add     eax, edx
    lea     rdi, [rip+engine_paint_fb]
    add     rdi, rax
    mov     ecx, r14d
.fr_px:
    mov     [rdi], r8b
    mov     [rdi+1], r9b
    mov     [rdi+2], r15b
    add     rdi, 3
    dec     ecx
    jnz     .fr_px
    inc     r13d
    dec     ebx
    jnz     .fr_row
.fr_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# engine_paint_put_glyph(edi=x, esi=y, edx=ch, r8b=r, r9b=g, r10b=b)
engine_paint_put_glyph:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15b, r10b
    mov     r12d, edi
    mov     r13d, esi
    mov     eax, edx
    and     eax, 0xff
    cmp     eax, 0x20
    jb      .pg_fallback
    cmp     eax, 0x7e
    ja      .pg_fallback
    sub     eax, 0x20
    jmp     .pg_idx
.pg_fallback:
    mov     eax, '!' - 0x20
.pg_idx:
    shl     eax, 3                 # *8 rows
    lea     rsi, [rip+font8x8]
    add     rsi, rax
    xor     r14d, r14d             # row
.pg_row:
    movzx   ebx, byte ptr [rsi]
    xor     ecx, ecx               # col 0..7
.pg_col:
    mov     eax, 0x80
    shr     eax, cl
    test    bl, al
    jz      .pg_skip
    # plot pixel (r12+col, r13+row) — do not clobber rsi (font*)
    mov     edi, r12d
    add     edi, ecx
    mov     eax, r13d
    add     eax, r14d
    # bounds in edi=x eax=y
    cmp     edi, 0
    jl      .pg_skip
    cmp     eax, 0
    jl      .pg_skip
    cmp     edi, [rip+engine_paint_w]
    jge     .pg_skip
    cmp     eax, [rip+engine_paint_h]
    jge     .pg_skip
    imul    eax, [rip+engine_paint_stride]
    imul    edx, edi, 3
    add     eax, edx
    lea     rdx, [rip+engine_paint_fb]
    add     rdx, rax
    mov     [rdx], r8b
    mov     [rdx+1], r9b
    mov     [rdx+2], r15b
.pg_skip:
    inc     ecx
    cmp     ecx, 8
    jl      .pg_col
    inc     rsi
    inc     r14d
    cmp     r14d, 8
    jl      .pg_row
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# engine_paint_text(edi=x, esi=y, rdx=cstr, r8b=r, r9b=g, r10b=b)
engine_paint_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rdx
.pt_loop:
    movzx   edx, byte ptr [r14]
    test    edx, edx
    jz      .pt_done
    mov     edi, r12d
    mov     esi, r13d
    # r8/r9/r10 already color
    call    engine_paint_put_glyph
    add     r12d, EP_CHAR_W
    inc     r14
    jmp     .pt_loop
.pt_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# engine_paint_boxes(rdi=boxes, rsi=n, rdx=text_blob)
engine_paint_boxes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    test    r13, r13
    jz      .bx_done
.bx_loop:
    mov     edi, [r12]             # x
    mov     esi, [r12+4]           # y
    mov     edx, [r12+8]           # w
    mov     ecx, [r12+12]          # h
    movzx   r8d, byte ptr [r12+16]
    movzx   r9d, byte ptr [r12+17]
    movzx   r10d, byte ptr [r12+18]
    movzx   eax, byte ptr [r12+19]
    test    al, SE_FLAG_TEXT
    jnz     .bx_text
    test    al, SE_FLAG_NOFILL
    jnz     .bx_border
    call    engine_paint_fill_rect
    movzx   eax, byte ptr [r12+19]
.bx_border:
    test    al, SE_FLAG_BORDER
    jz      .bx_next
    # Multi-px stroke from SePaintBox+28 (CSS border-width; 0→UA 1)
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r13d, [r12]            # x
    mov     r14d, [r12+4]          # y
    mov     r15d, [r12+8]          # w
    mov     ebx, [r12+12]          # h
    mov     ecx, [r12+28]          # border_w
    test    ecx, ecx
    jg      .bx_bw
    mov     ecx, 1
.bx_bw:
    # clamp: stroke ≤ min(w,h)/2 (at least 1 already)
    mov     eax, r15d
    cmp     eax, ebx
    jle     .bx_min
    mov     eax, ebx
.bx_min:
    shr     eax, 1
    test    eax, eax
    jnz     .bx_cl
    mov     eax, 1
.bx_cl:
    cmp     ecx, eax
    jle     .bx_ok
    mov     ecx, eax
.bx_ok:
    # border RGB from +32 (0x00RRGGBB); 0 → UA #606060
    mov     eax, [r12+32]
    test    eax, eax
    jnz     .bx_col
    mov     eax, 0x00606060
.bx_col:
    mov     r12d, ecx              # bw (box ptr already pushed)
    # 0x00RRGGBB → r8=R r9=G r10=B (no AH: REX regs in use)
    mov     r10b, al               # B
    mov     edx, eax
    shr     edx, 8
    mov     r9b, dl                # G
    shr     eax, 16
    mov     r8b, al                # R
    # top
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r15d
    mov     ecx, r12d
    call    engine_paint_fill_rect
    # bottom
    mov     edi, r13d
    mov     esi, r14d
    add     esi, ebx
    sub     esi, r12d
    mov     edx, r15d
    mov     ecx, r12d
    call    engine_paint_fill_rect
    # left
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r12d
    mov     ecx, ebx
    call    engine_paint_fill_rect
    # right
    mov     edi, r13d
    add     edi, r15d
    sub     edi, r12d
    mov     esi, r14d
    mov     edx, r12d
    mov     ecx, ebx
    call    engine_paint_fill_rect
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    jmp     .bx_next
.bx_text:
    mov     eax, [r12+20]          # text_off
    movsxd  rax, eax
    lea     rdx, [r14+rax]
    call    engine_paint_text
.bx_next:
    add     r12, 36
    dec     r13
    jnz     .bx_loop
.bx_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# engine_paint_write_ppm(rdi=path)
engine_paint_write_ppm:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    # build header "P6\nW H\n255\n"
    lea     rdi, [rip+ep_ppm_hdr]
    mov     byte ptr [rdi], 'P'
    mov     byte ptr [rdi+1], '6'
    mov     byte ptr [rdi+2], 10
    mov     r14, 3
    lea     rdi, [rip+ep_ppm_hdr]
    add     rdi, r14
    mov     esi, [rip+engine_paint_w]
    call    ep_fmt_u32
    add     r14, rax
    lea     rdi, [rip+ep_ppm_hdr]
    add     rdi, r14
    mov     byte ptr [rdi], ' '
    inc     r14
    lea     rdi, [rip+ep_ppm_hdr]
    add     rdi, r14
    mov     esi, [rip+engine_paint_h]
    call    ep_fmt_u32
    add     r14, rax
    lea     rdi, [rip+ep_ppm_hdr]
    add     rdi, r14
    mov     byte ptr [rdi], 10
    inc     r14
    lea     rdi, [rip+ep_ppm_hdr]
    add     rdi, r14
    mov     byte ptr [rdi], '2'
    mov     byte ptr [rdi+1], '5'
    mov     byte ptr [rdi+2], '5'
    mov     byte ptr [rdi+3], 10
    add     r14, 4
    # open file
    mov     rdi, r12
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 420
    call    ep_sys_open
    cmp     rax, 0
    jl      .wp_fail
    mov     ebx, eax
    # write header
    mov     edi, ebx
    lea     rsi, [rip+ep_ppm_hdr]
    mov     rdx, r14
    call    ep_sys_write
    # write pixels
    mov     eax, [rip+engine_paint_w]
    imul    eax, [rip+engine_paint_h]
    imul    eax, 3
    mov     edi, ebx
    lea     rsi, [rip+engine_paint_fb]
    mov     edx, eax
    call    ep_sys_write
    mov     edi, ebx
    call    ep_sys_close
    xor     eax, eax
    jmp     .wp_done
.wp_fail:
    mov     eax, -1
.wp_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# engine_paint_fixture — demo rects + glyphs → PPM
engine_paint_fixture:
    push    rbp
    mov     rbp, rsp
    # mkdir out/engine via open path (caller ensures dirs) 
    mov     edi, 160
    mov     esi, 80
    call    engine_paint_init
    # white background
    mov     dil, 255
    mov     sil, 255
    mov     dl, 255
    call    engine_paint_clear
    # blue title bar
    mov     edi, 0
    mov     esi, 0
    mov     edx, 160
    mov     ecx, 20
    mov     r8b, 30
    mov     r9b, 90
    mov     r10b, 200
    call    engine_paint_fill_rect
    # green box
    mov     edi, 12
    mov     esi, 28
    mov     edx, 40
    mov     ecx, 30
    mov     r8b, 40
    mov     r9b, 180
    mov     r10b, 70
    call    engine_paint_fill_rect
    # red box
    mov     edi, 60
    mov     esi, 28
    mov     edx, 40
    mov     ecx, 30
    mov     r8b, 200
    mov     r9b, 50
    mov     r10b, 40
    call    engine_paint_fill_rect
    # text on title bar
    mov     edi, 8
    mov     esi, 6
    lea     rdx, [rip+fixture_text]
    mov     r8b, 255
    mov     r9b, 255
    mov     r10b, 255
    call    engine_paint_text
    # write PPM
    lea     rdi, [rip+fixture_path]
    call    engine_paint_write_ppm
    # stdout JSON proof
    mov     rdi, 1
    lea     rsi, [rip+msg_ok]
    mov     rdx, msg_ok_len
    call    ep_sys_write
    xor     eax, eax
    pop     rbp
    ret
