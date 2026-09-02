# Spark engine B — layout: parse DOM → SePaintBox[]
# DOM: engine_html nodes[] (64B). Styles: se_style_pool via set_styles.
# Out: SePaintBox 36B (engine_paint.s). No spark.s edits.
.intel_syntax noprefix
.include "asm/engine_style.inc"

.global spark_layout_reset
.global spark_layout_set_viewport
.global spark_layout_set_styles
.global spark_layout_run
.global spark_layout_box_count
.global spark_layout_box_at
.global spark_layout_boxes_base
.global spark_layout_text_blob
.global spark_layout_box_stride
.global spark_layout_fixture_simple
.global spark_layout_fixture_table
.global spark_layout_selftest
.global spark_layout_selftest_table
.global spark_layout_emit_table_proof

.equ NODE_SIZE, 64
.equ KIND_ELEM, 1
.equ KIND_TEXT, 2
.equ TAG_HTML, 1
.equ TAG_HEAD, 2
.equ TAG_TITLE, 4
.equ TAG_SPAN, 11
.equ TAG_A, 9
.equ TAG_IMG, 12
.equ TAG_SCRIPT, 15
.equ TAG_STYLE, 16
.equ TAG_TABLE, 18
.equ TAG_TR, 19
.equ TAG_TD, 20
.equ TAG_TH, 21
.equ OFF_KIND, 0
.equ OFF_TAG, 1
.equ OFF_PARENT, 4
.equ OFF_FIRST, 8
.equ OFF_NEXT, 16
.equ OFF_DATA, 24
.equ DATA_CAP, 40
.equ SE_PAINT_BOX, 36
.equ SE_FLAG_TEXT, 1
.equ SE_FLAG_BORDER, 2
.equ SE_FLAG_NOFILL, 4
.equ BOX_MAX, 1024
.equ TEXT_BLOB_MAX, 8192
.equ NODE_NONE, -1
.equ CHAR_W, 8
.equ LINE_H, 16
.equ IB_MIN_W, 24
.equ IB_IMG_W, 32

.section .bss
.align 16
lay_boxes:      .space BOX_MAX * SE_PAINT_BOX
lay_box_count:  .space 8
lay_vp_w:       .space 4
lay_vp_h:       .space 4
lay_dom_base:   .space 8
lay_dom_count:  .space 4
lay_styles:     .space 8
lay_style_n:    .space 4
lay_line_x:     .space 4
lay_line_y:     .space 4
lay_line_h:     .space 4
lay_cx:         .space 4
lay_cw:         .space 4
lay_ox:         .space 4
lay_text_blob:  .space TEXT_BLOB_MAX
lay_text_len:   .space 4
fix_dom:       .space 16 * NODE_SIZE
# layout.table proof scratch (syscall clobbers r11)
tbl_cell0_x:    .space 4
tbl_cell1_x:    .space 4
tbl_cell_y:     .space 4
tbl_cell_h:     .space 4
tbl_band_end:   .space 4
tbl_borders:    .space 4
tbl_texts:      .space 4

.section .data
lay_def_w: .long 640
lay_def_h: .long 480
lay_expect: .long 8
msg_ok: .ascii "{\"op\":\"layout\",\"box_count\":"
msg_ok_len = . - msg_ok
msg_ex: .ascii ",\"expect\":"
msg_ex_len = . - msg_ex
msg_abi: .ascii ",\"box_stride\":36,\"abi\":\"SePaintBox\","
msg_abi_len = . - msg_abi
msg_ok2: .ascii "\"viewport\":[640,480],\"ok\":true}\n"
msg_ok2_len = . - msg_ok2
msg_bad: .ascii "\"ok\":false}\n"
msg_bad_len = . - msg_bad
msg_tbl: .ascii "{\"op\":\"layout.table\",\"box_count\":"
msg_tbl_len = . - msg_tbl
msg_tbl2: .ascii ",\"cell0_x\":"
msg_tbl2_len = . - msg_tbl2
msg_tbl3: .ascii ",\"cell1_x\":"
msg_tbl3_len = . - msg_tbl3
msg_tbl4: .ascii ",\"cell_y\":"
msg_tbl4_len = . - msg_tbl4
msg_tbl5: .ascii ",\"border_cells\":"
msg_tbl5_len = . - msg_tbl5
msg_tbl5b: .ascii ",\"cell_text\":"
msg_tbl5b_len = . - msg_tbl5b
msg_tbl6: .ascii ",\"ok\":true}\n"
msg_tbl6_len = . - msg_tbl6
dec_buf: .space 16
fx_hello: .asciz "Hello"
fx_para:  .asciz "ABCDEFGHIJabcdefghij"
fx_aa:    .asciz "aa"
fx_bb:    .asciz "bb"
fx_th:    .asciz "A"
fx_td:    .asciz "B"

.section .text

lay_write:
    # syscall clobbers rcx + r11; keep callers' band regs safe.
    push    rcx
    push    r11
    mov     rax, 1
    mov     rdi, 1
    syscall
    pop     r11
    pop     rcx
    ret

lay_print_u32:
    push    rbx
    push    rcx
    push    rdx
    lea     rbx, [rip+dec_buf+15]
    mov     ecx, 10
    test    eax, eax
    jnz     1f
    dec     rbx
    mov     byte ptr [rbx], '0'
    jmp     2f
1:  xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    eax, eax
    jnz     1b
2:  lea     rdx, [rip+dec_buf+15]
    sub     rdx, rbx
    mov     rsi, rbx
    call    lay_write
    pop     rdx
    pop     rcx
    pop     rbx
    ret

spark_layout_box_stride:
    mov     eax, SE_PAINT_BOX
    ret

spark_layout_reset:
    mov     qword ptr [rip+lay_box_count], 0
    mov     dword ptr [rip+lay_line_x], 0
    mov     dword ptr [rip+lay_line_y], 0
    mov     dword ptr [rip+lay_line_h], 0
    mov     dword ptr [rip+lay_text_len], 0
    mov     dword ptr [rip+lay_ox], 0
    mov     dword ptr [rip+lay_cx], 0
    xor     eax, eax
    mov     ecx, (BOX_MAX * SE_PAINT_BOX) / 8
    lea     rdi, [rip+lay_boxes]
    rep     stosq
    ret

spark_layout_set_viewport:
    test    edi, edi
    jg      1f
    mov     edi, [rip+lay_def_w]
1:  test    esi, esi
    jg      2f
    mov     esi, [rip+lay_def_h]
2:  mov     [rip+lay_vp_w], edi
    mov     [rip+lay_vp_h], esi
    ret

# rdi = SeComputedStyle* (se_style_pool), esi = count
spark_layout_set_styles:
    mov     [rip+lay_styles], rdi
    mov     [rip+lay_style_n], esi
    ret

spark_layout_box_count:
    mov     eax, [rip+lay_box_count]
    ret

spark_layout_boxes_base:
    lea     rax, [rip+lay_boxes]
    ret

spark_layout_text_blob:
    lea     rax, [rip+lay_text_blob]
    ret

spark_layout_box_at:
    cmp     edi, 0
    jl      1f
    cmp     edi, [rip+lay_box_count]
    jge     1f
    mov     eax, edi
    imul    rax, SE_PAINT_BOX
    lea     rcx, [rip+lay_boxes]
    add     rax, rcx
    ret
1:  xor     eax, eax
    ret

lay_alloc:
    mov     eax, [rip+lay_box_count]
    cmp     eax, BOX_MAX
    jge     1f
    mov     ecx, eax
    inc     dword ptr [rip+lay_box_count]
    imul    rcx, SE_PAINT_BOX
    lea     rbx, [rip+lay_boxes]
    add     rbx, rcx
    push    rdi
    push    rax
    mov     rdi, rbx
    xor     eax, eax
    mov     ecx, SE_PAINT_BOX
    rep     stosb
    pop     rax
    pop     rdi
    ret
1:  mov     eax, NODE_NONE
    xor     ebx, ebx
    ret

lay_blob_append:
    push    rbx
    mov     ebx, [rip+lay_text_len]
    mov     eax, ebx
    add     eax, edx
    inc     eax
    cmp     eax, TEXT_BLOB_MAX
    jg      1f
    lea     rdi, [rip+lay_text_blob]
    add     rdi, rbx
    mov     ecx, edx
    rep     movsb
    mov     byte ptr [rdi], 0
    lea     eax, [ebx + edx + 1]
    mov     [rip+lay_text_len], eax
    mov     eax, ebx
    pop     rbx
    ret
1:  mov     eax, NODE_NONE
    pop     rbx
    ret

# esi=id → rdi=&node
lay_node:
    mov     eax, esi
    imul    rax, NODE_SIZE
    mov     rdi, [rip+lay_dom_base]
    add     rdi, rax
    ret

lay_datalen:
    call    lay_node
    add     rdi, OFF_DATA
    xor     eax, eax
1:  cmp     eax, DATA_CAP
    jge     2f
    cmp     byte ptr [rdi+rax], 0
    je      2f
    inc     eax
    jmp     1b
2:  ret

# esi=id → eax display
lay_disp:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     .Ld
    cmp     esi, [rip+lay_style_n]
    jge     .Ld
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      .Ld
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_DISPLAY
    jz      .Ld
    mov     eax, [rax+SE_OFF_DISPLAY]
    ret
.Ld:call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     1f
    mov     eax, SE_DISP_INLINE
    ret
1:  movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_HEAD
    je      2f
    cmp     eax, TAG_TITLE
    je      2f
    cmp     eax, TAG_SCRIPT
    je      2f
    cmp     eax, TAG_STYLE
    je      2f
    cmp     eax, TAG_SPAN
    je      3f
    cmp     eax, TAG_A
    je      3f
    cmp     eax, TAG_TABLE
    je      4f
    cmp     eax, TAG_TR
    je      5f
    cmp     eax, TAG_TD
    je      6f
    cmp     eax, TAG_TH
    je      6f
    cmp     eax, TAG_IMG
    je      7f
    mov     eax, SE_DISP_BLOCK
    ret
2:  mov     eax, SE_DISP_NONE
    ret
3:  mov     eax, SE_DISP_INLINE
    ret
4:  mov     eax, SE_DISP_TABLE
    ret
5:  mov     eax, SE_DISP_TABLE_ROW
    ret
6:  mov     eax, SE_DISP_TABLE_CELL
    ret
7:  mov     eax, SE_DISP_INLINE_BLOCK
    ret

lay_margin:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_MARGIN
    jz      1f
    mov     eax, [rax+SE_OFF_MARGIN]
    ret
1:  xor     eax, eax
    ret

lay_padding:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_PADDING
    jz      1f
    mov     eax, [rax+SE_OFF_PADDING]
    ret
1:  xor     eax, eax
    ret

# esi=id → border-width px if SE_FLAG_BORDER_W; else -1 (UA default)
lay_border_w:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_BORDER_W
    jz      1f
    mov     eax, [rax+SE_OFF_BORDER_W]
    ret
1:  mov     eax, -1
    ret

# esi=id → border-color rgb if SE_FLAG_BORDER_C; else UA #606060
lay_border_color:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_BORDER_C
    jz      1f
    mov     eax, [rax+SE_OFF_BORDER_C]
    ret
1:  mov     eax, 0x00606060
    ret

# esi=id → border-style; unset → SOLID (UA); flagged none → NONE
lay_border_style:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_BORDER_S
    jz      1f
    mov     eax, [rax+SE_OFF_BORDER_S]
    ret
1:  mov     eax, SE_BORDER_SOLID
    ret

# esi=id → visibility; nearest flagged ancestor/self; else VISIBLE
lay_visibility:
    push    r12
    mov     r12d, esi
.Lvis:
    cmp     r12d, 0
    jl      .Lvis_def
    cmp     dword ptr [rip+lay_style_n], 0
    jle     .Lvis_par
    cmp     r12d, [rip+lay_style_n]
    jge     .Lvis_par
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      .Lvis_par
    mov     edx, r12d
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_VIS
    jz      .Lvis_par
    mov     eax, [rax+SE_OFF_VIS]
    pop     r12
    ret
.Lvis_par:
    mov     esi, r12d
    call    lay_node
    mov     eax, [rdi+OFF_PARENT]
    mov     r12d, eax
    cmp     eax, NODE_NONE
    jne     .Lvis
.Lvis_def:
    mov     eax, SE_VIS_VISIBLE
    pop     r12
    ret

# esi=id → opacity 0|1; unset → 1 (UA opaque)
lay_opacity:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_OPACITY
    jz      1f
    mov     eax, [rax+SE_OFF_OPACITY]
    ret
1:  mov     eax, 1
    ret

# esi=id → width px if SE_FLAG_WIDTH; else -1 (UA = avail)
lay_width:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_WIDTH
    jz      1f
    mov     eax, [rax+SE_OFF_WIDTH]
    ret
1:  mov     eax, -1
    ret

# esi=id → height px if SE_FLAG_HEIGHT; else -1 (UA = content)
lay_height:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_HEIGHT
    jz      1f
    mov     eax, [rax+SE_OFF_HEIGHT]
    ret
1:  mov     eax, -1
    ret

# esi=id → max-height px if SE_FLAG_MAX_HEIGHT; else -1
lay_max_height:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_MAX_HEIGHT
    jz      1f
    mov     eax, [rax+SE_OFF_MAX_HEIGHT]
    ret
1:  mov     eax, -1
    ret

# esi=id → min-height px if SE_FLAG_MIN_HEIGHT; else -1
lay_min_height:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_MIN_HEIGHT
    jz      1f
    mov     eax, [rax+SE_OFF_MIN_HEIGHT]
    ret
1:  mov     eax, -1
    ret

# esi=id → max-width px if SE_FLAG_MAX_WIDTH; else -1
lay_max_width:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_MAX_WIDTH
    jz      1f
    mov     eax, [rax+SE_OFF_MAX_WIDTH]
    ret
1:  mov     eax, -1
    ret

# esi=id → min-width px if SE_FLAG_MIN_WIDTH; else -1
lay_min_width:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_MIN_WIDTH
    jz      1f
    mov     eax, [rax+SE_OFF_MIN_WIDTH]
    ret
1:  mov     eax, -1
    ret

lay_font:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_FONT
    jz      1f
    mov     eax, [rax+SE_OFF_FONT]
    test    eax, eax
    jnz     2f
1:  mov     eax, 16
2:  ret

# → 0x00RRGGBB fill (CSS background-color or UA gray)
lay_color:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     1f
    cmp     esi, [rip+lay_style_n]
    jge     1f
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      1f
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_BG
    jz      1f
    mov     eax, [rax+SE_OFF_BG]
    ret
1:  mov     eax, 0x00E8E8E8
    ret

# esi=id → CSS color on self or ancestors (named/#hex); else black
lay_text_color:
    push    rbx
    push    r12
    mov     r12d, esi
.Ltc:
    cmp     r12d, 0
    jl      .Ltc_blk
    cmp     dword ptr [rip+lay_style_n], 0
    jle     .Ltc_par
    cmp     r12d, [rip+lay_style_n]
    jge     .Ltc_par
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      .Ltc_par
    mov     edx, r12d
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_COLOR
    jz      .Ltc_par
    mov     eax, [rax+SE_OFF_COLOR]
    pop     r12
    pop     rbx
    ret
.Ltc_par:
    mov     esi, r12d
    call    lay_node
    mov     eax, [rdi+OFF_PARENT]
    mov     r12d, eax
    cmp     eax, NODE_NONE
    jne     .Ltc
.Ltc_blk:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret

# esi=id → CSS background-color or table-cell UA tints
lay_cell_color:
    cmp     dword ptr [rip+lay_style_n], 0
    jle     .Lcc
    cmp     esi, [rip+lay_style_n]
    jge     .Lcc
    mov     rax, [rip+lay_styles]
    test    rax, rax
    jz      .Lcc
    mov     edx, esi
    imul    rdx, SE_STYLE_SIZE
    add     rax, rdx
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_BG
    jz      .Lcc
    mov     eax, [rax+SE_OFF_BG]
    ret
.Lcc:
    call    lay_node
    movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_TH
    je      .Lcc_th
    cmp     eax, TAG_TD
    je      .Lcc_td
    mov     eax, 0x00E8E8E8
    ret
.Lcc_th:
    mov     eax, 0x00D0D0F0
    ret
.Lcc_td:
    mov     eax, 0x00F0F0F0
    ret

# patch border flag + width + color on last box
# edi=border_w px >0  esi=border_rgb 0x00RRGGBB
lay_patch_border:
    mov     eax, [rip+lay_box_count]
    test    eax, eax
    jz      1f
    dec     eax
    imul    rax, SE_PAINT_BOX
    lea     rcx, [rip+lay_boxes]
    add     rax, rcx
    or      byte ptr [rax+19], SE_FLAG_BORDER
    mov     [rax+28], edi
    mov     [rax+32], esi
1:  ret

lay_flush:
    mov     eax, [rip+lay_line_h]
    test    eax, eax
    jz      1f
    add     [rip+lay_line_y], eax
    mov     dword ptr [rip+lay_line_x], 0
    mov     dword ptr [rip+lay_line_h], 0
1:  ret

# edi=x esi=y edx=w ecx=h r8d=rgb  (x += lay_ox)
lay_emit_fill:
    push    rbx
    call    lay_alloc
    cmp     eax, NODE_NONE
    je      1f
    add     edi, [rip+lay_ox]
    mov     [rbx], edi
    mov     [rbx+4], esi
    mov     [rbx+8], edx
    mov     [rbx+12], ecx
    mov     eax, r8d
    cmp     eax, SE_BG_TRANSPARENT
    jne     2f
    mov     dword ptr [rbx+16], 0
    mov     byte ptr [rbx+19], SE_FLAG_NOFILL
    jmp     1f
2:  mov     byte ptr [rbx+18], al
    shr     eax, 8
    mov     byte ptr [rbx+17], al
    shr     eax, 8
    mov     byte ptr [rbx+16], al
    mov     byte ptr [rbx+19], 0
1:  pop     rbx
    ret

# edi=x esi=y edx=toff ecx=tlen r8d=rgb r9d=line_h
lay_emit_text:
    push    rbx
    call    lay_alloc
    cmp     eax, NODE_NONE
    je      1f
    add     edi, [rip+lay_ox]
    mov     [rbx], edi
    mov     [rbx+4], esi
    mov     eax, ecx
    imul    eax, CHAR_W
    test    eax, eax
    jnz     2f
    mov     eax, CHAR_W
2:  mov     [rbx+8], eax
    mov     eax, r9d
    test    eax, eax
    jnz     3f
    mov     eax, LINE_H
3:  mov     [rbx+12], eax
    mov     eax, r8d
    mov     byte ptr [rbx+18], al
    shr     eax, 8
    mov     byte ptr [rbx+17], al
    shr     eax, 8
    mov     byte ptr [rbx+16], al
    mov     byte ptr [rbx+19], SE_FLAG_TEXT
    mov     [rbx+20], edx
    mov     [rbx+24], ecx
1:  pop     rbx
    ret

# esi=id → eax estimated inline-block width (px)
lay_ib_width:
    push    rbx
    push    r12
    push    r13
    mov     r12d, esi
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     1f
    call    lay_datalen
    imul    eax, CHAR_W
    cmp     eax, IB_MIN_W
    jge     9f
    mov     eax, IB_MIN_W
    jmp     9f
1:  movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_IMG
    jne     2f
    mov     eax, IB_IMG_W
    jmp     9f
2:  mov     ebx, [rdi+OFF_FIRST]
    xor     r13d, r13d
3:  cmp     ebx, NODE_NONE
    je      4f
    mov     esi, ebx
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     5f
    mov     esi, ebx
    call    lay_datalen
    imul    eax, CHAR_W
    add     r13d, eax
5:  mov     esi, ebx
    call    lay_node
    mov     ebx, [rdi+OFF_NEXT]
    jmp     3b
4:  mov     eax, r13d
    cmp     eax, IB_MIN_W
    jge     9f
    mov     eax, IB_MIN_W
9:  pop     r13
    pop     r12
    pop     rbx
    ret

# place text node esi (uses lay_cx/cw/line_*)
lay_place_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, esi
    call    lay_datalen
    mov     r13d, eax
    test    r13d, r13d
    jz      .Lpt_done
    mov     esi, r12d
    call    lay_visibility
    cmp     eax, SE_VIS_HIDDEN
    je      .Lpt_hid
    mov     esi, r12d
    call    lay_opacity
    test    eax, eax
    jz      .Lpt_hid
    call    lay_node
    lea     rsi, [rdi+OFF_DATA]
    mov     edx, r13d
    call    lay_blob_append
    cmp     eax, NODE_NONE
    je      .Lpt_done
    mov     r14d, eax
    mov     esi, r12d
    call    lay_font
    # line_h ≈ font + font/4
    mov     r9d, eax
    mov     ecx, eax
    shr     ecx, 2
    add     r9d, ecx
    mov     r15d, r13d
    imul    r15d, CHAR_W
    mov     eax, [rip+lay_line_x]
    add     eax, r15d
    cmp     eax, [rip+lay_cw]
    jle     .Lpt_fit
    call    lay_flush
.Lpt_fit:
    mov     esi, r12d
    call    lay_text_color
    cmp     eax, SE_BG_TRANSPARENT
    je      .Lpt_trans
    mov     r8d, eax
    mov     edi, [rip+lay_cx]
    add     edi, [rip+lay_line_x]
    mov     esi, [rip+lay_line_y]
    mov     edx, r14d
    mov     ecx, r13d
    # r9d already line_h
    call    lay_emit_text
    add     [rip+lay_line_x], r15d
    jmp     .Lpt_adv
.Lpt_trans:
    # transparent ink: keep advance, no glyph paint
    add     [rip+lay_line_x], r15d
.Lpt_adv:
    mov     esi, r12d
    call    lay_font
    mov     ecx, eax
    shr     ecx, 2
    add     eax, ecx
    cmp     eax, [rip+lay_line_h]
    jle     .Lpt_done
    mov     [rip+lay_line_h], eax
    jmp     .Lpt_done
.Lpt_hid:
    # Hidden text still consumes inline advance (CSS visibility).
    mov     esi, r12d
    call    lay_font
    mov     r9d, eax
    mov     ecx, eax
    shr     ecx, 2
    add     r9d, ecx
    mov     r15d, r13d
    imul    r15d, CHAR_W
    mov     eax, [rip+lay_line_x]
    add     eax, r15d
    cmp     eax, [rip+lay_cw]
    jle     .Lpt_hid_fit
    call    lay_flush
.Lpt_hid_fit:
    add     [rip+lay_line_x], r15d
    cmp     r9d, [rip+lay_line_h]
    jle     .Lpt_done
    mov     [rip+lay_line_h], r9d
.Lpt_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# spark_layout_run(rdi=nodes, esi=n, edx=root) → eax boxes
spark_layout_run:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     [rip+lay_dom_base], rdi
    mov     [rip+lay_dom_count], esi
    mov     r12d, edx
    call    spark_layout_reset
    cmp     dword ptr [rip+lay_vp_w], 0
    jg      1f
    mov     edi, [rip+lay_def_w]
    mov     esi, [rip+lay_def_h]
    call    spark_layout_set_viewport
1:  cmp     r12d, 0
    jl      2f
    cmp     r12d, [rip+lay_dom_count]
    jge     2f
    mov     esi, r12d
    mov     edi, [rip+lay_vp_w]
    xor     edx, edx
    call    lay_flow
2:  mov     eax, [rip+lay_box_count]
    pop     r12
    pop     rbx
    pop     rbp
    ret

# Frame locals: [rbp-4]=fill_idx [rbp-8]=used_y [rbp-12]=child
# esi=node edi=avail_w edx=y → eax=y_after
lay_flow:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12d, esi
    mov     r13d, edi
    mov     r14d, edx
    mov     dword ptr [rbp-4], NODE_NONE

    cmp     r12d, 0
    jl      .Lret_y
    cmp     r12d, [rip+lay_dom_count]
    jge     .Lret_y

    mov     esi, r12d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      .Lret_y
    cmp     eax, SE_DISP_INLINE
    je      .Linline
    cmp     eax, SE_DISP_INLINE_BLOCK
    je      .Liblock
    cmp     eax, SE_DISP_TABLE_ROW
    je      .Lrow

    # ---- block / table / table-cell ----
    # Frame: [rbp-4] fill_idx [rbp-8] used_h [rbp-20] pad_px
    #         [rbp-24] saved avail_w for min-width cap
    mov     esi, r12d
    call    lay_margin
    add     r14d, eax

    mov     esi, r12d
    call    lay_padding
    mov     [rbp-20], eax

    mov     [rbp-24], r13d
    # CSS width px clamps avail for this block/cell box + kids
    mov     esi, r12d
    call    lay_width
    cmp     eax, 0
    jl      .Lw_skip
    cmp     eax, r13d
    jle     .Lw_ok
    mov     eax, r13d
.Lw_ok:
    mov     r13d, eax
.Lw_skip:
    # CSS max-width px clamps after width
    mov     esi, r12d
    call    lay_max_width
    cmp     eax, 0
    jl      .Lmnw
    cmp     eax, r13d
    jge     .Lmnw
    mov     r13d, eax
.Lmnw:
    # CSS min-width px expands floor (capped by saved avail)
    mov     esi, r12d
    call    lay_min_width
    cmp     eax, 0
    jl      .Lmw_done
    cmp     eax, r13d
    jle     .Lmw_done
    cmp     eax, [rbp-24]
    jle     .Lmnw_ok
    mov     eax, [rbp-24]
.Lmnw_ok:
    mov     r13d, eax
.Lmw_done:

    mov     esi, r12d
    call    lay_node
    movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_HTML
    je      .Lnobox
    # visibility:hidden / opacity:0 → keep space; skip fill/border paint
    mov     esi, r12d
    call    lay_visibility
    cmp     eax, SE_VIS_HIDDEN
    je      .Lnobox
    mov     esi, r12d
    call    lay_opacity
    test    eax, eax
    jz      .Lnobox
    mov     esi, r12d
    call    lay_node
    movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_TD
    je      .Lcell_box
    cmp     eax, TAG_TH
    je      .Lcell_box
    mov     esi, r12d
    call    lay_color
    jmp     .Lemit_box
.Lcell_box:
    mov     esi, r12d
    call    lay_cell_color
.Lemit_box:
    mov     r8d, eax
    xor     edi, edi
    mov     esi, r14d
    mov     edx, r13d
    mov     ecx, LINE_H
    call    lay_emit_fill
    mov     esi, r12d
    call    lay_node
    movzx   eax, byte ptr [rdi+OFF_TAG]
    cmp     eax, TAG_TD
    je      .Lcell_border
    cmp     eax, TAG_TH
    je      .Lcell_border
    jmp     .Lcell_done
.Lcell_border:
    # border-style:none skips stroke; unset → UA solid
    mov     esi, r12d
    call    lay_border_style
    cmp     eax, SE_BORDER_NONE
    je      .Lcell_done
    # border-width:0 clears; unset → UA 1px; >0 → that many px stroke
    mov     esi, r12d
    call    lay_border_w
    cmp     eax, 0
    je      .Lcell_done
    mov     edi, 1
    cmp     eax, 0
    jl      .Lpb
    mov     edi, eax
.Lpb:
    push    rdi
    mov     esi, r12d
    call    lay_border_color
    mov     esi, eax
    pop     rdi
    call    lay_patch_border
.Lcell_done:
    mov     eax, [rip+lay_box_count]
    dec     eax
    mov     [rbp-4], eax
.Lnobox:
    # Content origin = box_y + padding (absolute). Glyphs sit inside pad.
    mov     dword ptr [rip+lay_cx], 0
    mov     [rip+lay_cw], r13d
    mov     dword ptr [rip+lay_line_x], 0
    mov     eax, r14d
    add     eax, [rbp-20]
    mov     [rip+lay_line_y], eax
    mov     dword ptr [rip+lay_line_h], 0
    mov     dword ptr [rbp-8], 0

    mov     esi, r12d
    call    lay_node
    mov     r15d, [rdi+OFF_FIRST]
.Lch:
    cmp     r15d, NODE_NONE
    je      .Lch_done
    mov     esi, r15d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      .Lch_next
    cmp     eax, SE_DISP_INLINE
    je      .Lch_in
    cmp     eax, SE_DISP_INLINE_BLOCK
    je      .Lch_ib

    # block / table / table-row / table-cell child
    call    lay_flush
    mov     eax, [rip+lay_line_y]
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lch_by
    mov     [rbp-8], eax
.Lch_by:
    mov     esi, r15d
    mov     edi, r13d
    mov     edx, r14d
    add     edx, [rbp-8]
    call    lay_flow
    sub     eax, r14d
    mov     [rbp-8], eax
    mov     [rip+lay_cw], r13d
    mov     dword ptr [rip+lay_cx], 0
    mov     dword ptr [rip+lay_line_x], 0
    mov     eax, r14d
    add     eax, [rbp-8]
    mov     [rip+lay_line_y], eax
    mov     dword ptr [rip+lay_line_h], 0
    jmp     .Lch_next

.Lch_in:
    mov     esi, r15d
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     .Lch_inel
    mov     esi, r15d
    call    lay_place_text
    mov     eax, [rip+lay_line_y]
    add     eax, [rip+lay_line_h]
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lch_next
    mov     [rbp-8], eax
    jmp     .Lch_next

.Lch_inel:
    mov     esi, r15d
    mov     edi, r13d
    mov     edx, r14d
    add     edx, [rbp-8]
    call    lay_flow
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lch_rest
    mov     [rbp-8], eax
.Lch_rest:
    mov     [rip+lay_cw], r13d
    mov     dword ptr [rip+lay_cx], 0
    mov     dword ptr [rip+lay_line_x], 0
    mov     eax, r14d
    add     eax, [rbp-8]
    mov     [rip+lay_line_y], eax
    mov     dword ptr [rip+lay_line_h], 0
    jmp     .Lch_next

# inline-block child on the current line
.Lch_ib:
    mov     esi, r15d
    call    lay_ib_width
    mov     ebx, eax
    mov     eax, [rip+lay_line_x]
    add     eax, ebx
    cmp     eax, [rip+lay_cw]
    jle     .Lch_ib_fit
    call    lay_flush
.Lch_ib_fit:
    mov     esi, r15d
    call    lay_color
    mov     r8d, eax
    mov     edi, [rip+lay_cx]
    add     edi, [rip+lay_line_x]
    mov     esi, [rip+lay_line_y]
    mov     edx, ebx
    mov     ecx, LINE_H
    call    lay_emit_fill
    # nest children inside IB: bump ox, reset line
    mov     eax, [rip+lay_ox]
    mov     [rbp-16], eax
    mov     eax, [rip+lay_cx]
    add     eax, [rip+lay_line_x]
    add     [rip+lay_ox], eax
    mov     eax, [rip+lay_cw]
    mov     [rbp-20], eax
    mov     eax, [rip+lay_line_x]
    mov     [rbp-24], eax
    mov     dword ptr [rip+lay_cx], 0
    mov     dword ptr [rip+lay_line_x], 0
    mov     [rip+lay_cw], ebx
    mov     esi, r15d
    call    lay_ib_children
    mov     eax, [rbp-16]
    mov     [rip+lay_ox], eax
    mov     eax, [rbp-20]
    mov     [rip+lay_cw], eax
    mov     eax, [rbp-24]
    mov     [rip+lay_line_x], eax
    add     [rip+lay_line_x], ebx
    mov     eax, LINE_H
    cmp     eax, [rip+lay_line_h]
    jle     .Lch_ib_uh
    mov     [rip+lay_line_h], eax
.Lch_ib_uh:
    mov     eax, [rip+lay_line_y]
    add     eax, [rip+lay_line_h]
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lch_next
    mov     [rbp-8], eax
    jmp     .Lch_next

.Lch_next:
    mov     esi, r15d
    call    lay_node
    mov     r15d, [rdi+OFF_NEXT]
    jmp     .Lch

.Lch_done:
    call    lay_flush
    mov     eax, [rip+lay_line_y]
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lh
    mov     [rbp-8], eax
.Lh:mov     eax, [rbp-8]
    # Empty content: keep at least LINE_H inside the padding shell.
    cmp     eax, [rbp-20]
    jg      .Lpad_bot
    mov     eax, [rbp-20]
    add     eax, LINE_H
    mov     [rbp-8], eax
.Lpad_bot:
    mov     eax, [rbp-8]
    add     eax, [rbp-20]
    mov     [rbp-8], eax
    # CSS height px expands block/cell box (content taller wins)
    mov     esi, r12d
    call    lay_height
    cmp     eax, 0
    jl      .Lmnh
    cmp     eax, [rbp-8]
    jle     .Lmnh
    mov     [rbp-8], eax
.Lmnh:
    # CSS min-height px expands floor (like height)
    mov     esi, r12d
    call    lay_min_height
    cmp     eax, 0
    jl      .Lmh
    cmp     eax, [rbp-8]
    jle     .Lmh
    mov     [rbp-8], eax
.Lmh:
    # CSS max-height px clamps after height/min expand
    mov     esi, r12d
    call    lay_max_height
    cmp     eax, 0
    jl      .Lpatch
    cmp     eax, [rbp-8]
    jge     .Lpatch
    mov     [rbp-8], eax
.Lpatch:
    mov     eax, [rbp-4]
    cmp     eax, NODE_NONE
    je      .Lend
    imul    rax, SE_PAINT_BOX
    lea     rcx, [rip+lay_boxes]
    add     rax, rcx
    mov     edx, [rbp-8]
    mov     [rax+12], edx
.Lend:
    mov     eax, r14d
    add     eax, [rbp-8]
    mov     r15d, eax
    mov     esi, r12d
    call    lay_margin
    add     eax, r15d
    jmp     .Lret

# ---- table-row: equal-width cells side by side ----
# Frame: [rbp-4] unused fill [rbp-8] max_h [rbp-12] cell_w [rbp-16] saved_ox
.Lrow:
    mov     esi, r12d
    call    lay_margin
    add     r14d, eax
    mov     dword ptr [rbp-8], LINE_H
    # count visible children
    mov     esi, r12d
    call    lay_node
    mov     r15d, [rdi+OFF_FIRST]
    xor     ebx, ebx
.Lrow_cnt:
    cmp     r15d, NODE_NONE
    je      .Lrow_cnt_d
    mov     esi, r15d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      .Lrow_cnt_n
    inc     ebx
.Lrow_cnt_n:
    mov     esi, r15d
    call    lay_node
    mov     r15d, [rdi+OFF_NEXT]
    jmp     .Lrow_cnt
.Lrow_cnt_d:
    test    ebx, ebx
    jz      .Lrow_empty
    mov     eax, r13d
    xor     edx, edx
    div     ebx
    test    eax, eax
    jnz     .Lrow_cw
    mov     eax, 1
.Lrow_cw:
    mov     [rbp-12], eax
    # optional row chrome fill
    mov     esi, r12d
    call    lay_color
    mov     r8d, eax
    xor     edi, edi
    mov     esi, r14d
    mov     edx, r13d
    mov     ecx, LINE_H
    call    lay_emit_fill
    mov     eax, [rip+lay_ox]
    mov     [rbp-16], eax
    mov     esi, r12d
    call    lay_node
    mov     r15d, [rdi+OFF_FIRST]
    xor     ebx, ebx
.Lrow_cells:
    cmp     r15d, NODE_NONE
    je      .Lrow_done
    mov     esi, r15d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      .Lrow_nx
    mov     eax, [rbp-16]
    add     eax, ebx
    mov     [rip+lay_ox], eax
    mov     esi, r15d
    call    lay_width
    cmp     eax, 0
    jl      .Lrow_eq
    cmp     eax, [rbp-12]
    jle     .Lrow_cw_use
    mov     eax, [rbp-12]
.Lrow_cw_use:
    mov     edi, eax
    jmp     .Lrow_mw
.Lrow_eq:
    mov     edi, [rbp-12]
.Lrow_mw:
    push    rdi
    mov     esi, r15d
    call    lay_max_width
    pop     rdi
    cmp     eax, 0
    jl      .Lrow_flow
    cmp     eax, edi
    jge     .Lrow_flow
    mov     edi, eax
.Lrow_flow:
    mov     esi, r15d
    mov     edx, r14d
    call    lay_flow
    sub     eax, r14d
    cmp     eax, [rbp-8]
    jle     .Lrow_adv
    mov     [rbp-8], eax
.Lrow_adv:
    add     ebx, [rbp-12]
.Lrow_nx:
    mov     esi, r15d
    call    lay_node
    mov     r15d, [rdi+OFF_NEXT]
    jmp     .Lrow_cells
.Lrow_done:
    mov     eax, [rbp-16]
    mov     [rip+lay_ox], eax
    # patch row fill height if we emitted one (last-but-cells)
    mov     eax, r14d
    add     eax, [rbp-8]
    mov     r15d, eax
    mov     esi, r12d
    call    lay_margin
    add     eax, r15d
    jmp     .Lret
.Lrow_empty:
    mov     eax, r14d
    add     eax, LINE_H
    jmp     .Lret

# ---- inline-block entry (atomic on a fresh line context) ----
.Liblock:
    mov     dword ptr [rip+lay_cx], 0
    mov     [rip+lay_cw], r13d
    mov     [rip+lay_line_y], r14d
    mov     dword ptr [rip+lay_line_x], 0
    mov     dword ptr [rip+lay_line_h], 0
    mov     esi, r12d
    call    lay_ib_width
    mov     ebx, eax
    cmp     ebx, r13d
    jle     .Lib_w
    mov     ebx, r13d
.Lib_w:
    mov     esi, r12d
    call    lay_color
    mov     r8d, eax
    xor     edi, edi
    mov     esi, r14d
    mov     edx, ebx
    mov     ecx, LINE_H
    call    lay_emit_fill
    mov     esi, r12d
    call    lay_ib_children
    mov     eax, r14d
    add     eax, LINE_H
    jmp     .Lret

# esi=ib node — place text kids inside current ox/cw
lay_ib_children:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r15
    mov     r12d, esi
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     1f
    call    lay_place_text
    jmp     9f
1:  mov     r15d, [rdi+OFF_FIRST]
2:  cmp     r15d, NODE_NONE
    je      9f
    mov     esi, r15d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      3f
    mov     esi, r15d
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     3f
    mov     esi, r15d
    call    lay_place_text
3:  mov     esi, r15d
    call    lay_node
    mov     r15d, [rdi+OFF_NEXT]
    jmp     2b
9:  pop     r15
    pop     r12
    pop     rbx
    pop     rbp
    ret

# ---- inline entry (element or text) ----
.Linline:
    mov     dword ptr [rip+lay_cx], 0
    mov     [rip+lay_cw], r13d
    mov     [rip+lay_line_y], r14d
    mov     dword ptr [rip+lay_line_x], 0
    mov     dword ptr [rip+lay_line_h], 0
    mov     esi, r12d
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     .Lin_el
    mov     esi, r12d
    call    lay_place_text
    call    lay_flush
    mov     eax, [rip+lay_line_y]
    jmp     .Lret
.Lin_el:
    mov     esi, r12d
    call    lay_node
    mov     r15d, [rdi+OFF_FIRST]
.Lin_loop:
    cmp     r15d, NODE_NONE
    je      .Lin_done
    mov     esi, r15d
    call    lay_disp
    cmp     eax, SE_DISP_NONE
    je      .Lin_nx
    mov     esi, r15d
    call    lay_node
    cmp     byte ptr [rdi+OFF_KIND], KIND_TEXT
    jne     .Lin_sub
    mov     esi, r15d
    call    lay_place_text
    jmp     .Lin_nx
.Lin_sub:
    mov     esi, r15d
    mov     edi, r13d
    mov     edx, [rip+lay_line_y]
    call    lay_flow
    mov     [rip+lay_line_y], eax
    mov     dword ptr [rip+lay_line_x], 0
    mov     dword ptr [rip+lay_line_h], 0
    mov     [rip+lay_cw], r13d
.Lin_nx:
    mov     esi, r15d
    call    lay_node
    mov     r15d, [rdi+OFF_NEXT]
    jmp     .Lin_loop
.Lin_done:
    call    lay_flush
    mov     eax, [rip+lay_line_y]
    jmp     .Lret

.Lret_y:
    mov     eax, r14d
.Lret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rsp, rbp
    pop     rbp
    ret

# --- fixture: 12 parse-shaped nodes, root 0 ---
spark_layout_fixture_simple:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rcx, 16 * NODE_SIZE
    xor     eax, eax
    rep     stosb
    mov     rdi, r12

    # 0 html
    mov     byte ptr [rdi+OFF_KIND], KIND_ELEM
    mov     byte ptr [rdi+OFF_TAG], TAG_HTML
    mov     dword ptr [rdi+OFF_FIRST], 1
    mov     dword ptr [rdi+OFF_NEXT], NODE_NONE
    mov     dword ptr [rdi+4], NODE_NONE

    # 1 head
    lea     rbx, [rdi+NODE_SIZE]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_HEAD
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], 2
    mov     dword ptr [rbx+4], 0

    # 2 body
    lea     rbx, [rdi+NODE_SIZE*2]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], 3
    mov     dword ptr [rbx+OFF_FIRST], 3
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 0

    # 3 h1
    lea     rbx, [rdi+NODE_SIZE*3]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], 6
    mov     dword ptr [rbx+OFF_FIRST], 4
    mov     dword ptr [rbx+OFF_NEXT], 5
    mov     dword ptr [rbx+4], 2

    # 4 text Hello
    lea     rbx, [rdi+NODE_SIZE*4]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 3
    lea     rsi, [rip+fx_hello]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    # 5 p
    mov     rdi, r12
    lea     rbx, [rdi+NODE_SIZE*5]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], 5
    mov     dword ptr [rbx+OFF_FIRST], 6
    mov     dword ptr [rbx+OFF_NEXT], 7
    mov     dword ptr [rbx+4], 2

    # 6 text para
    lea     rbx, [rdi+NODE_SIZE*6]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 5
    lea     rsi, [rip+fx_para]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    # 7 div
    mov     rdi, r12
    lea     rbx, [rdi+NODE_SIZE*7]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], 10
    mov     dword ptr [rbx+OFF_FIRST], 8
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 2

    # 8 span
    lea     rbx, [rdi+NODE_SIZE*8]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_SPAN
    mov     dword ptr [rbx+OFF_FIRST], 9
    mov     dword ptr [rbx+OFF_NEXT], 10
    mov     dword ptr [rbx+4], 7

    # 9 text aa
    lea     rbx, [rdi+NODE_SIZE*9]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 8
    lea     rsi, [rip+fx_aa]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    # 10 span
    mov     rdi, r12
    lea     rbx, [rdi+NODE_SIZE*10]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_SPAN
    mov     dword ptr [rbx+OFF_FIRST], 11
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 7

    # 11 text bb
    lea     rbx, [rdi+NODE_SIZE*11]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 10
    lea     rsi, [rip+fx_bb]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    mov     eax, 12
    xor     edx, edx
    pop     r12
    pop     rbx
    pop     rbp
    ret

# Mini DOM: html > body > table > tr > th(A) + td(B)
# → eax=n edx=root(0)
spark_layout_fixture_table:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    mov     rcx, 16 * NODE_SIZE
    xor     eax, eax
    rep     stosb
    mov     rdi, r12

    # 0 html
    mov     byte ptr [rdi+OFF_KIND], KIND_ELEM
    mov     byte ptr [rdi+OFF_TAG], TAG_HTML
    mov     dword ptr [rdi+OFF_FIRST], 1
    mov     dword ptr [rdi+OFF_NEXT], NODE_NONE
    mov     dword ptr [rdi+4], NODE_NONE

    # 1 body
    lea     rbx, [rdi+NODE_SIZE]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], 3
    mov     dword ptr [rbx+OFF_FIRST], 2
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 0

    # 2 table
    lea     rbx, [rdi+NODE_SIZE*2]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_TABLE
    mov     dword ptr [rbx+OFF_FIRST], 3
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 1

    # 3 tr
    lea     rbx, [rdi+NODE_SIZE*3]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_TR
    mov     dword ptr [rbx+OFF_FIRST], 4
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 2

    # 4 th
    lea     rbx, [rdi+NODE_SIZE*4]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_TH
    mov     dword ptr [rbx+OFF_FIRST], 5
    mov     dword ptr [rbx+OFF_NEXT], 6
    mov     dword ptr [rbx+4], 3

    # 5 text A
    lea     rbx, [rdi+NODE_SIZE*5]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 4
    lea     rsi, [rip+fx_th]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    # 6 td
    mov     rdi, r12
    lea     rbx, [rdi+NODE_SIZE*6]
    mov     byte ptr [rbx+OFF_KIND], KIND_ELEM
    mov     byte ptr [rbx+OFF_TAG], TAG_TD
    mov     dword ptr [rbx+OFF_FIRST], 7
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 3

    # 7 text B
    lea     rbx, [rdi+NODE_SIZE*7]
    mov     byte ptr [rbx+OFF_KIND], KIND_TEXT
    mov     dword ptr [rbx+OFF_FIRST], NODE_NONE
    mov     dword ptr [rbx+OFF_NEXT], NODE_NONE
    mov     dword ptr [rbx+4], 6
    lea     rsi, [rip+fx_td]
    lea     rdi, [rbx+OFF_DATA]
    call    lay_cpy

    mov     eax, 8
    xor     edx, edx
    pop     r12
    pop     rbx
    pop     rbp
    ret

lay_cpy:
    xor     ecx, ecx
1:  mov     al, [rsi+rcx]
    mov     [rdi+rcx], al
    test    al, al
    jz      2f
    inc     ecx
    cmp     ecx, DATA_CAP - 1
    jl      1b
    mov     byte ptr [rdi+rcx], 0
2:  ret

spark_layout_selftest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+fix_dom]
    call    spark_layout_fixture_simple
    mov     r12d, eax
    mov     r13d, edx
    mov     edi, 640
    mov     esi, 480
    call    spark_layout_set_viewport
    xor     edi, edi
    xor     esi, esi
    call    spark_layout_set_styles
    lea     rdi, [rip+fix_dom]
    mov     esi, r12d
    mov     edx, r13d
    call    spark_layout_run
    mov     ebx, eax

    lea     rsi, [rip+msg_ok]
    mov     rdx, msg_ok_len
    call    lay_write
    mov     eax, ebx
    call    lay_print_u32
    lea     rsi, [rip+msg_ex]
    mov     rdx, msg_ex_len
    call    lay_write
    mov     eax, [rip+lay_expect]
    call    lay_print_u32
    lea     rsi, [rip+msg_abi]
    mov     rdx, msg_abi_len
    call    lay_write

    cmp     ebx, [rip+lay_expect]
    jne     .Lbad
    cmp     ebx, 1
    jl      .Lbad
    call    spark_layout_box_stride
    cmp     eax, 36
    jne     .Lbad
    lea     rsi, [rip+msg_ok2]
    mov     rdx, msg_ok2_len
    call    lay_write
    xor     eax, eax
    jmp     .Ldone
.Lbad:
    lea     rsi, [rip+msg_bad]
    mov     rdx, msg_bad_len
    call    lay_write
    mov     eax, 1
.Ldone:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# Scan lay_boxes for two equal 320px table cells; emit layout.table JSON.
# Returns 0 if emitted, 1 if no table proof (not an error for DOM layout).
spark_layout_emit_table_proof:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    r11
    mov     r12d, [rip+lay_box_count]

    mov     r14d, NODE_NONE
    mov     r15d, NODE_NONE
    xor     ebx, ebx
.Let_scan:
    cmp     ebx, r12d
    jge     .Let_chk
    mov     edi, ebx
    call    spark_layout_box_at
    test    rax, rax
    jz      .Let_nx
    movzx   ecx, byte ptr [rax+19]
    test    ecx, SE_FLAG_TEXT
    jnz     .Let_nx
    cmp     dword ptr [rax+8], 320
    jne     .Let_nx
    cmp     r14d, NODE_NONE
    jne     1f
    mov     r14d, ebx
    jmp     .Let_nx
1:  cmp     r15d, NODE_NONE
    jne     .Let_nx
    mov     r15d, ebx
.Let_nx:
    inc     ebx
    jmp     .Let_scan
.Let_chk:
    cmp     r14d, NODE_NONE
    je      .Let_skip
    cmp     r15d, NODE_NONE
    je      .Let_skip
    mov     edi, r14d
    call    spark_layout_box_at
    mov     r13d, [rax]
    mov     r11d, [rax+4]
    mov     ecx, [rax+12]
    mov     edi, r15d
    call    spark_layout_box_at
    mov     r8d, [rax]
    mov     r9d, [rax+4]
    cmp     r9d, r11d
    jne     .Let_skip
    cmp     r8d, r13d
    jle     .Let_skip
    # Spill before any syscall (Linux syscall clobbers rcx/r11).
    mov     [rip+tbl_cell0_x], r13d
    mov     [rip+tbl_cell1_x], r8d
    mov     [rip+tbl_cell_y], r11d
    mov     [rip+tbl_cell_h], ecx
    test    ecx, ecx
    jnz     .Let_h_ok
    mov     ecx, 48
    mov     [rip+tbl_cell_h], ecx
.Let_h_ok:

    xor     r10d, r10d
    xor     ebx, ebx
.Let_bord:
    mov     r12d, [rip+lay_box_count]
    cmp     ebx, r12d
    jge     .Let_txt0
    mov     edi, ebx
    call    spark_layout_box_at
    test    rax, rax
    jz      .Let_bord_nx
    movzx   ecx, byte ptr [rax+19]
    test    ecx, SE_FLAG_BORDER
    jz      .Let_bord_nx
    inc     r10d
.Let_bord_nx:
    inc     ebx
    jmp     .Let_bord
.Let_txt0:
    # Band = [cell_y, max(y+h) over 320px cells). Memory compares —
    # PIE/ASLR left r11/r13 unstable (~50/50 cell_text 0↔4).
    mov     r11d, [rip+tbl_cell_y]
    mov     r13d, [rip+tbl_cell_h]
    add     r13d, r11d
    mov     [rip+tbl_band_end], r13d
    xor     ebx, ebx
.Let_band:
    mov     r12d, [rip+lay_box_count]
    cmp     ebx, r12d
    jge     .Let_txt_init
    mov     edi, ebx
    call    spark_layout_box_at
    test    rax, rax
    jz      .Let_band_nx
    movzx   ecx, byte ptr [rax+19]
    test    ecx, SE_FLAG_TEXT
    jnz     .Let_band_nx
    cmp     dword ptr [rax+8], 320
    jne     .Let_band_nx
    mov     edx, [rax+4]
    add     edx, [rax+12]
    cmp     edx, [rip+tbl_band_end]
    jle     .Let_band_nx
    mov     [rip+tbl_band_end], edx
.Let_band_nx:
    inc     ebx
    jmp     .Let_band
.Let_txt_init:
    xor     r14d, r14d
    xor     ebx, ebx
.Let_txt:
    mov     r12d, [rip+lay_box_count]
    cmp     ebx, r12d
    jge     .Let_out
    mov     edi, ebx
    call    spark_layout_box_at
    test    rax, rax
    jz      .Let_txt_nx
    movzx   ecx, byte ptr [rax+19]
    test    ecx, SE_FLAG_TEXT
    jz      .Let_txt_nx
    mov     edx, [rax+4]
    cmp     edx, [rip+tbl_cell_y]
    jl      .Let_txt_nx
    cmp     edx, [rip+tbl_band_end]
    jge     .Let_txt_nx
    inc     r14d
.Let_txt_nx:
    inc     ebx
    jmp     .Let_txt
.Let_out:
    mov     [rip+tbl_borders], r10d
    mov     [rip+tbl_texts], r14d
    lea     rsi, [rip+msg_tbl]
    mov     rdx, msg_tbl_len
    call    lay_write
    mov     eax, r12d
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl2]
    mov     rdx, msg_tbl2_len
    call    lay_write
    mov     eax, [rip+tbl_cell0_x]
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl3]
    mov     rdx, msg_tbl3_len
    call    lay_write
    mov     eax, [rip+tbl_cell1_x]
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl4]
    mov     rdx, msg_tbl4_len
    call    lay_write
    mov     eax, [rip+tbl_cell_y]
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl5]
    mov     rdx, msg_tbl5_len
    call    lay_write
    mov     eax, [rip+tbl_borders]
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl5b]
    mov     rdx, msg_tbl5b_len
    call    lay_write
    mov     eax, [rip+tbl_texts]
    call    lay_print_u32
    lea     rsi, [rip+msg_tbl6]
    mov     rdx, msg_tbl6_len
    call    lay_write
    xor     eax, eax
    jmp     .Let_done
.Let_skip:
    mov     eax, 1
.Let_done:
    pop     r11
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

# Prove table-row places two equal cells side-by-side (same y, x1>x0).
spark_layout_selftest_table:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+fix_dom]
    call    spark_layout_fixture_table
    mov     r12d, eax
    mov     r13d, edx
    mov     edi, 640
    mov     esi, 480
    call    spark_layout_set_viewport
    xor     edi, edi
    xor     esi, esi
    call    spark_layout_set_styles
    lea     rdi, [rip+fix_dom]
    mov     esi, r12d
    mov     edx, r13d
    call    spark_layout_run
    call    spark_layout_emit_table_proof
    test    eax, eax
    jnz     .Lst_bad
    xor     eax, eax
    jmp     .Lst_done
.Lst_bad:
    lea     rsi, [rip+msg_bad]
    mov     rdx, msg_bad_len
    call    lay_write
    mov     eax, 1
.Lst_done:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
