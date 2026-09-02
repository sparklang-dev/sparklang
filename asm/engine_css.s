# Spark engine B — CSS subset attached to HTML DOM (f6d0b5f).
# Real shape: engine_html nodes[] (kind/tag/parent/fc/ns/data).
# Props: color, background-color, font-size, margin, padding,
#   border-width, border-color, border-style, visibility, opacity,
#   transparent/yellow colors,
#   width, height, max-height, min-height, max-width, min-width, display
#   block|inline|inline-block|none|table|table-row|table-cell.
# Cascade: stylesheet tag selectors → inline style= (layout owns UA).
# Pool se_style_pool[node_id] for spark_layout_set_styles.
#
# Spark: engine parse "…html" then engine css attach
.intel_syntax noprefix
.include "asm/engine_style.inc"

.global engine_css_dispatch
.global se_css_reset
.global se_css_parse_decls
.global se_css_add_rule
.global se_css_compute
.global se_css_get
.global se_css_attach
.global se_style_pool
.global se_style_count

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern sys_exit
.extern msg_nl
.extern set_last_from_rcx
.extern bind_arrow_from_line

# HTML DOM (engine_html.s) — real parse artifact
.extern nodes
.extern nnodes
.extern html_buf
.extern html_len

.equ MODE_0755, 493
.equ OUT_CAP, 8192
.equ RULE_STRIDE, SE_RULE_STRIDE
.equ NODE_SIZE, 64
.equ KIND_ELEM, 1
.equ KIND_TEXT, 2
.equ DATA_OFF, 24
.equ OFF_KIND, 0
.equ OFF_TAG, 1
.equ OFF_FIRST, 8
.equ TAG_STYLE, 16
.equ TAG_SCRIPT, 15

.section .bss
.align 16
se_style_pool:  .space SE_STYLE_MAX * SE_STYLE_SIZE
se_style_count: .space 8
se_rules:       .space SE_RULE_MAX * RULE_STRIDE
se_rule_count:  .space 8
out_buf:        .space OUT_CAP
tmp_tag:        .space SE_TAG_MAX
tmp_decls:      .space 512
scan_pos:       .space 8

.section .data
msg_eng:        .ascii "[engine] "
msg_eng_len = . - msg_eng
msg_arrow:      .ascii "  -> "
msg_arrow_len = . - msg_arrow

needle_css:     .ascii "css\0"
needle_attach:  .ascii "attach\0"
needle_apply:   .ascii "apply\0"
needle_demo:    .ascii "demo\0"

path_out:       .ascii "out\0"
path_browser:   .ascii "out/browser\0"
path_engine:    .ascii "out/browser/engine\0"
path_css_json:  .ascii "out/browser/engine/css.json\0"

err_unknown:
    .ascii "error: engine css wants: attach"
    .ascii " (after engine parse)\n"
err_unknown_len = . - err_unknown
err_nodom:
    .ascii "error: engine css attach needs DOM"
    .ascii " (engine parse first)\n"
err_nodom_len = . - err_nodom
err_selftest:
    .ascii "error: engine css selftest failed\n"
err_selftest_len = . - err_selftest

n_color:        .ascii "color\0"
n_bgcolor:      .ascii "background-color\0"
n_fontsize:     .ascii "font-size\0"
n_margin:       .ascii "margin\0"
n_padding:      .ascii "padding\0"
n_border_width: .ascii "border-width\0"
n_border_color: .ascii "border-color\0"
n_border_style: .ascii "border-style\0"
n_solid:        .ascii "solid\0"
n_visibility:   .ascii "visibility\0"
n_visible:      .ascii "visible\0"
n_hidden:       .ascii "hidden\0"
n_opacity:      .ascii "opacity\0"
n_width:        .ascii "width\0"
n_height:       .ascii "height\0"
n_max_height:   .ascii "max-height\0"
n_min_height:   .ascii "min-height\0"
n_max_width:    .ascii "max-width\0"
n_min_width:    .ascii "min-width\0"
n_display:      .ascii "display\0"
n_block:        .ascii "block\0"
n_inline:       .ascii "inline\0"
n_inline_block: .ascii "inline-block\0"
n_none:         .ascii "none\0"
n_table:        .ascii "table\0"
n_table_row:    .ascii "table-row\0"
n_table_cell:   .ascii "table-cell\0"
n_red:          .ascii "red\0"
n_green:        .ascii "green\0"
n_blue:         .ascii "blue\0"
n_black:        .ascii "black\0"
n_white:        .ascii "white\0"
n_gray:         .ascii "gray\0"
n_grey:         .ascii "grey\0"
n_yellow:       .ascii "yellow\0"
n_cyan:         .ascii "cyan\0"
n_magenta:      .ascii "magenta\0"
n_orange:       .ascii "orange\0"
n_lime:         .ascii "lime\0"
n_transparent:  .ascii "transparent\0"
n_style_tag:    .ascii "<style\0"
n_style_end:    .ascii "</style>\0"
n_style_eq:     .ascii "style=\0"

j_pre:
    .ascii "{\"op\":\"engine.css\",\"ok\":true,\"nodes\":"
j_pre_len = . - j_pre
j_mid:
    .ascii ",\"styles\":["
j_mid_len = . - j_mid
j_post:
    .ascii "]}\n"
j_post_len = . - j_post

.section .text

# ============================================================
engine_css_dispatch:
    push    rbx
    # Pipeline already printed [engine] + matched css — attach DOM styles.
    mov     rax, [rip+nnodes]
    test    rax, rax
    jz      css_nodom
    call    se_css_attach
    call    css_emit_json
    call    css_selftest
    test    rax, rax
    jz      css_self_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+path_css_json]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+path_css_json]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+path_css_json]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+path_css_json]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

css_nodom:
    lea     rsi, [rip+err_nodom]
    mov     rdx, err_nodom_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
css_self_fail:
    lea     rsi, [rip+err_selftest]
    mov     rdx, err_selftest_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit

# ============================================================
css_strlen:
    push    rsi
    mov     rsi, rdi
    call    strlen
    pop     rsi
    ret

se_css_reset:
    push    rdi
    push    rcx
    lea     rdi, [rip+se_style_pool]
    mov     rcx, SE_STYLE_MAX * SE_STYLE_SIZE
    xor     eax, eax
    rep stosb
    lea     rdi, [rip+se_rules]
    mov     rcx, SE_RULE_MAX * RULE_STRIDE
    xor     eax, eax
    rep stosb
    mov     qword ptr [rip+se_style_count], 0
    mov     qword ptr [rip+se_rule_count], 0
    pop     rcx
    pop     rdi
    ret

se_css_get:
    cmp     rdi, SE_STYLE_MAX
    jae     1f
    imul    rax, rdi, SE_STYLE_SIZE
    lea     rcx, [rip+se_style_pool]
    add     rax, rcx
    ret
1:  xor     rax, rax
    ret

css_tag_eq:
    push    rbx
1:  mov     al, [rdi]
    mov     bl, [rsi]
    cmp     al, 'A'
    jb      2f
    cmp     al, 'Z'
    ja      2f
    add     al, 32
2:  cmp     bl, 'A'
    jb      3f
    cmp     bl, 'Z'
    ja      3f
    add     bl, 32
3:  cmp     al, bl
    jne     4f
    test    al, al
    jz      5f
    inc     rdi
    inc     rsi
    jmp     1b
4:  xor     rax, rax
    pop     rbx
    ret
5:  mov     rax, 1
    pop     rbx
    ret

css_skip_ws_r12:
1:  mov     al, [r12]
    cmp     al, ' '
    je      2f
    cmp     al, 9
    je      2f
    cmp     al, 10
    je      2f
    cmp     al, 13
    je      2f
    ret
2:  inc     r12
    jmp     1b

css_skip_ws_rdi:
1:  mov     al, [rdi]
    cmp     al, ' '
    je      2f
    cmp     al, 9
    je      2f
    ret
2:  inc     rdi
    jmp     1b

# find needle (rsi) in haystack starting rdi; within bound if
# html: use html_buf+html_len. General: NUL-terminated.
# → rax=ptr or 0
css_find_ci:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
cf_o:
    cmp     byte ptr [r12], 0
    je      cf_m
    mov     rdi, r12
    mov     rsi, r13
cf_i:
    mov     al, [rsi]
    test    al, al
    jz      cf_h
    mov     bl, [rdi]
    test    bl, bl
    jz      cf_m
    cmp     al, 'A'
    jb      1f
    cmp     al, 'Z'
    ja      1f
    add     al, 32
1:  cmp     bl, 'A'
    jb      2f
    cmp     bl, 'Z'
    ja      2f
    add     bl, 32
2:  cmp     al, bl
    jne     cf_n
    inc     rdi
    inc     rsi
    jmp     cf_i
cf_n:
    inc     r12
    jmp     cf_o
cf_h:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbx
    ret
cf_m:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret

# ============================================================
# Value parsers
# ============================================================
css_hex_nibble:
    mov     al, dil
    cmp     al, '0'
    jb      z
    cmp     al, '9'
    ja      a
    sub     al, '0'
    ret
a:  cmp     al, 'a'
    jb      A
    cmp     al, 'f'
    ja      A
    sub     al, 'a' - 10
    ret
A:  cmp     al, 'A'
    jb      z
    cmp     al, 'F'
    ja      z
    sub     al, 'A' - 10
    ret
z:  xor     al, al
    ret

css_parse_hex_rgb:
    push    rbx
    push    r12
    mov     r12, rdi
    call    css_strlen
    cmp     rax, 3
    je      hs
    cmp     rax, 6
    je      hl
    xor     eax, eax
    jmp     hd
hs: mov     dil, [r12]
    call    css_hex_nibble
    mov     bl, al
    shl     bl, 4
    or      bl, al
    mov     dil, [r12+1]
    call    css_hex_nibble
    mov     bh, al
    shl     bh, 4
    or      bh, al
    mov     dil, [r12+2]
    call    css_hex_nibble
    mov     cl, al
    shl     cl, 4
    or      cl, al
    movzx   eax, bl
    shl     eax, 16
    movzx   edx, bh
    shl     edx, 8
    or      eax, edx
    movzx   edx, cl
    or      eax, edx
    jmp     hd
hl: mov     dil, [r12]
    call    css_hex_nibble
    mov     bl, al
    shl     bl, 4
    mov     dil, [r12+1]
    call    css_hex_nibble
    or      bl, al
    mov     dil, [r12+2]
    call    css_hex_nibble
    mov     bh, al
    shl     bh, 4
    mov     dil, [r12+3]
    call    css_hex_nibble
    or      bh, al
    mov     dil, [r12+4]
    call    css_hex_nibble
    mov     cl, al
    shl     cl, 4
    mov     dil, [r12+5]
    call    css_hex_nibble
    or      cl, al
    movzx   eax, bl
    shl     eax, 16
    movzx   edx, bh
    shl     edx, 8
    or      eax, edx
    movzx   edx, cl
    or      eax, edx
hd: pop     r12
    pop     rbx
    ret

css_parse_color:
    push    rbx
    mov     rbx, rdi
    call    css_skip_ws_rdi
    cmp     byte ptr [rdi], '#'
    jne     cn
    inc     rdi
    call    css_parse_hex_rgb
    pop     rbx
    ret
cn: lea     rsi, [rip+n_transparent]
    call    css_tag_eq
    test    rax, rax
    jz      ct0
    mov     eax, SE_BG_TRANSPARENT
    pop     rbx
    ret
ct0:lea     rsi, [rip+n_red]
    call    css_tag_eq
    test    rax, rax
    jz      1f
    mov     eax, 0x00FF0000
    pop     rbx
    ret
1:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_green]
    call    css_tag_eq
    test    rax, rax
    jz      2f
    mov     eax, 0x00008000
    pop     rbx
    ret
2:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_blue]
    call    css_tag_eq
    test    rax, rax
    jz      3f
    mov     eax, 0x000000FF
    pop     rbx
    ret
3:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_black]
    call    css_tag_eq
    test    rax, rax
    jz      4f
    xor     eax, eax
    pop     rbx
    ret
4:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_white]
    call    css_tag_eq
    test    rax, rax
    jz      5f
    mov     eax, 0x00FFFFFF
    pop     rbx
    ret
5:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_yellow]
    call    css_tag_eq
    test    rax, rax
    jz      6f
    mov     eax, 0x00FFFF00
    pop     rbx
    ret
6:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_cyan]
    call    css_tag_eq
    test    rax, rax
    jz      7f
    mov     eax, 0x0000FFFF
    pop     rbx
    ret
7:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_magenta]
    call    css_tag_eq
    test    rax, rax
    jz      8f
    mov     eax, 0x00FF00FF
    pop     rbx
    ret
8:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_orange]
    call    css_tag_eq
    test    rax, rax
    jz      9f
    mov     eax, 0x00FFA500
    pop     rbx
    ret
9:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_lime]
    call    css_tag_eq
    test    rax, rax
    jz      10f
    mov     eax, 0x0000FF00
    pop     rbx
    ret
10: mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_gray]
    call    css_tag_eq
    test    rax, rax
    jnz     cg
    mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_grey]
    call    css_tag_eq
    test    rax, rax
    jnz     cg
    xor     eax, eax
    pop     rbx
    ret
cg: mov     eax, 0x00808080
    pop     rbx
    ret

css_parse_px:
    push    rbx
    call    css_skip_ws_rdi
    xor     ebx, ebx
1:  mov     al, [rdi]
    cmp     al, '0'
    jb      2f
    cmp     al, '9'
    ja      2f
    imul    ebx, ebx, 10
    movzx   eax, al
    sub     eax, '0'
    add     ebx, eax
    inc     rdi
    jmp     1b
2:  mov     eax, ebx
    pop     rbx
    ret

css_parse_display:
    push    rbx
    mov     rbx, rdi
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_none]
    call    css_tag_eq
    test    rax, rax
    jz      1f
    mov     eax, SE_DISP_NONE
    pop     rbx
    ret
1:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_block]
    call    css_tag_eq
    test    rax, rax
    jz      2f
    mov     eax, SE_DISP_BLOCK
    pop     rbx
    ret
2:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_inline_block]
    call    css_tag_eq
    test    rax, rax
    jz      3f
    mov     eax, SE_DISP_INLINE_BLOCK
    pop     rbx
    ret
3:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_inline]
    call    css_tag_eq
    test    rax, rax
    jz      4f
    mov     eax, SE_DISP_INLINE
    pop     rbx
    ret
4:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_table_row]
    call    css_tag_eq
    test    rax, rax
    jz      5f
    mov     eax, SE_DISP_TABLE_ROW
    pop     rbx
    ret
5:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_table_cell]
    call    css_tag_eq
    test    rax, rax
    jz      6f
    mov     eax, SE_DISP_TABLE_CELL
    pop     rbx
    ret
6:  mov     rdi, rbx
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_table]
    call    css_tag_eq
    test    rax, rax
    jz      7f
    mov     eax, SE_DISP_TABLE
    pop     rbx
    ret
7:  mov     eax, SE_DISP_INLINE
    pop     rbx
    ret

# rdi=value — solid → SE_BORDER_SOLID, else none (default).
css_parse_border_style:
    push    rbx
    mov     rbx, rdi
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_solid]
    call    css_tag_eq
    test    rax, rax
    jz      1f
    mov     eax, SE_BORDER_SOLID
    pop     rbx
    ret
1:  mov     eax, SE_BORDER_NONE
    pop     rbx
    ret

# rdi=value — hidden → SE_VIS_HIDDEN; else visible
css_parse_visibility:
    push    rbx
    mov     rbx, rdi
    call    css_skip_ws_rdi
    lea     rsi, [rip+n_hidden]
    call    css_tag_eq
    test    rax, rax
    jz      1f
    mov     eax, SE_VIS_HIDDEN
    pop     rbx
    ret
1:  mov     eax, SE_VIS_VISIBLE
    pop     rbx
    ret

# rdi=value — leading '0' → 0; else 1 (UA opaque subset)
css_parse_opacity:
    push    rbx
    mov     rbx, rdi
    call    css_skip_ws_rdi
    mov     al, [rdi]
    cmp     al, '0'
    jne     1f
    xor     eax, eax
    pop     rbx
    ret
1:  mov     eax, 1
    pop     rbx
    ret

css_rtrim_tmp_decls:
    push    rdi
    lea     rdi, [rip+tmp_decls]
    call    css_strlen
    test    rax, rax
    jz      rd
1:  dec     rax
    mov     cl, [rdi+rax]
    cmp     cl, ' '
    je      2f
    cmp     cl, 9
    je      2f
    mov     byte ptr [rdi+rax+1], 0
    jmp     rd
2:  test    rax, rax
    jnz     1b
    mov     byte ptr [rdi], 0
rd: pop     rdi
    ret

# rdi=decls rsi=style*
se_css_parse_decls:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
pd_l:
    call    css_skip_ws_r12
    cmp     byte ptr [r12], 0
    je      pd_d
    lea     r14, [rip+tmp_tag]
    xor     rcx, rcx
pd_p:
    mov     al, [r12]
    test    al, al
    jz      pd_d
    cmp     al, ':'
    je      pd_c
    cmp     al, ';'
    je      pd_s
    cmp     rcx, SE_TAG_MAX - 1
    jae     pd_a
    cmp     al, 'A'
    jb      pd_w
    cmp     al, 'Z'
    ja      pd_w
    add     al, 32
pd_w:
    mov     [r14+rcx], al
    inc     rcx
pd_a:
    inc     r12
    jmp     pd_p
pd_s:
    inc     r12
    jmp     pd_l
pd_c:
    mov     byte ptr [r14+rcx], 0
    inc     r12
    call    css_skip_ws_r12
    lea     rbx, [rip+tmp_decls]
    xor     rcx, rcx
pd_v:
    mov     al, [r12]
    test    al, al
    jz      pd_e
    cmp     al, ';'
    je      pd_e
    cmp     rcx, 510
    jae     pd_b
    mov     [rbx+rcx], al
    inc     rcx
pd_b:
    inc     r12
    jmp     pd_v
pd_e:
    mov     byte ptr [rbx+rcx], 0
    call    css_rtrim_tmp_decls
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_color]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_co
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_bgcolor]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_bg
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_fontsize]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_fo
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_margin]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_ma
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_padding]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_pa
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_border_width]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_bw
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_border_color]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_bc
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_border_style]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_bs
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_visibility]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_vs
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_opacity]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_op
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_width]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_wi
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_height]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_he
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_max_height]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_mh
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_min_height]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_mnh
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_max_width]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_mw
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_min_width]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_mnw
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+n_display]
    call    css_tag_eq
    test    rax, rax
    jnz     pd_di
    jmp     pd_n
pd_co:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_color
    mov     dword ptr [r13+SE_OFF_COLOR], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_COLOR
    jmp     pd_n
pd_bg:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_color
    mov     dword ptr [r13+SE_OFF_BG], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_BG
    jmp     pd_n
pd_fo:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_FONT], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_FONT
    jmp     pd_n
pd_ma:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_MARGIN], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_MARGIN
    jmp     pd_n
pd_pa:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_PADDING], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_PADDING
    jmp     pd_n
pd_bw:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_BORDER_W], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_BORDER_W
    jmp     pd_n
pd_bc:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_color
    mov     dword ptr [r13+SE_OFF_BORDER_C], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_BORDER_C
    jmp     pd_n
pd_bs:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_border_style
    mov     dword ptr [r13+SE_OFF_BORDER_S], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_BORDER_S
    jmp     pd_n
pd_vs:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_visibility
    mov     dword ptr [r13+SE_OFF_VIS], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_VIS
    jmp     pd_n
pd_op:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_opacity
    mov     dword ptr [r13+SE_OFF_OPACITY], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_OPACITY
    jmp     pd_n
pd_wi:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_WIDTH], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_WIDTH
    jmp     pd_n
pd_he:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_HEIGHT], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_HEIGHT
    jmp     pd_n
pd_mh:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_MAX_HEIGHT], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_MAX_HEIGHT
    jmp     pd_n
pd_mnh:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_MIN_HEIGHT], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_MIN_HEIGHT
    jmp     pd_n
pd_mw:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_MAX_WIDTH], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_MAX_WIDTH
    jmp     pd_n
pd_mnw:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_px
    mov     dword ptr [r13+SE_OFF_MIN_WIDTH], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_MIN_WIDTH
    jmp     pd_n
pd_di:
    lea     rdi, [rip+tmp_decls]
    call    css_parse_display
    mov     dword ptr [r13+SE_OFF_DISPLAY], eax
    or      dword ptr [r13+SE_OFF_FLAGS], SE_FLAG_DISPLAY
pd_n:
    cmp     byte ptr [r12], ';'
    jne     pd_l
    inc     r12
    jmp     pd_l
pd_d:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

se_css_add_rule:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    mov     rax, [rip+se_rule_count]
    cmp     rax, SE_RULE_MAX
    jae     ar_d
    imul    rbx, rax, RULE_STRIDE
    lea     rcx, [rip+se_rules]
    add     rbx, rcx
    mov     rdi, rbx
    mov     rsi, r12
    mov     rcx, SE_TAG_MAX - 1
ar_c:
    mov     al, [rsi]
    test    al, al
    jz      ar_z
    cmp     al, 'A'
    jb      ar_w
    cmp     al, 'Z'
    ja      ar_w
    add     al, 32
ar_w:
    mov     [rdi], al
    inc     rdi
    inc     rsi
    dec     rcx
    jnz     ar_c
ar_z:
    mov     byte ptr [rdi], 0
    lea     rdi, [rbx+SE_TAG_MAX]
    xor     eax, eax
    mov     rcx, SE_STYLE_SIZE
    push    rdi
    rep stosb
    pop     rsi
    mov     rdi, r13
    call    se_css_parse_decls
    inc     qword ptr [rip+se_rule_count]
ar_d:
    pop     r13
    pop     r12
    pop     rbx
    ret

css_merge_style:
    mov     eax, [rdi+SE_OFF_FLAGS]
    test    eax, SE_FLAG_COLOR
    jz      1f
    mov     edx, [rdi+SE_OFF_COLOR]
    mov     [rbx+SE_OFF_COLOR], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_COLOR
1:  test    eax, SE_FLAG_FONT
    jz      2f
    mov     edx, [rdi+SE_OFF_FONT]
    mov     [rbx+SE_OFF_FONT], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_FONT
2:  test    eax, SE_FLAG_MARGIN
    jz      3f
    mov     edx, [rdi+SE_OFF_MARGIN]
    mov     [rbx+SE_OFF_MARGIN], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_MARGIN
3:  test    eax, SE_FLAG_DISPLAY
    jz      4f
    mov     edx, [rdi+SE_OFF_DISPLAY]
    mov     [rbx+SE_OFF_DISPLAY], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_DISPLAY
4:  test    eax, SE_FLAG_PADDING
    jz      5f
    mov     edx, [rdi+SE_OFF_PADDING]
    mov     [rbx+SE_OFF_PADDING], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_PADDING
5:  test    eax, SE_FLAG_BORDER_W
    jz      6f
    mov     edx, [rdi+SE_OFF_BORDER_W]
    mov     [rbx+SE_OFF_BORDER_W], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_BORDER_W
6:  test    eax, SE_FLAG_BG
    jz      7f
    mov     edx, [rdi+SE_OFF_BG]
    mov     [rbx+SE_OFF_BG], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_BG
7:  test    eax, SE_FLAG_WIDTH
    jz      8f
    mov     edx, [rdi+SE_OFF_WIDTH]
    mov     [rbx+SE_OFF_WIDTH], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_WIDTH
8:  test    eax, SE_FLAG_HEIGHT
    jz      9f
    mov     edx, [rdi+SE_OFF_HEIGHT]
    mov     [rbx+SE_OFF_HEIGHT], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_HEIGHT
9:  test    eax, SE_FLAG_MAX_HEIGHT
    jz      10f
    mov     edx, [rdi+SE_OFF_MAX_HEIGHT]
    mov     [rbx+SE_OFF_MAX_HEIGHT], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_MAX_HEIGHT
10: test    eax, SE_FLAG_MIN_HEIGHT
    jz      11f
    mov     edx, [rdi+SE_OFF_MIN_HEIGHT]
    mov     [rbx+SE_OFF_MIN_HEIGHT], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_MIN_HEIGHT
11: test    eax, SE_FLAG_MAX_WIDTH
    jz      12f
    mov     edx, [rdi+SE_OFF_MAX_WIDTH]
    mov     [rbx+SE_OFF_MAX_WIDTH], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_MAX_WIDTH
12: test    eax, SE_FLAG_MIN_WIDTH
    jz      13f
    mov     edx, [rdi+SE_OFF_MIN_WIDTH]
    mov     [rbx+SE_OFF_MIN_WIDTH], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_MIN_WIDTH
13: test    eax, SE_FLAG_BORDER_C
    jz      14f
    mov     edx, [rdi+SE_OFF_BORDER_C]
    mov     [rbx+SE_OFF_BORDER_C], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_BORDER_C
14: test    eax, SE_FLAG_BORDER_S
    jz      15f
    mov     edx, [rdi+SE_OFF_BORDER_S]
    mov     [rbx+SE_OFF_BORDER_S], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_BORDER_S
15: test    eax, SE_FLAG_VIS
    jz      16f
    mov     edx, [rdi+SE_OFF_VIS]
    mov     [rbx+SE_OFF_VIS], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_VIS
16: test    eax, SE_FLAG_OPACITY
    jz      17f
    mov     edx, [rdi+SE_OFF_OPACITY]
    mov     [rbx+SE_OFF_OPACITY], edx
    or      dword ptr [rbx+SE_OFF_FLAGS], SE_FLAG_OPACITY
17: ret

# rdi=node_id rsi=tag_cstr rdx=inline_or_0
# Does NOT set UA — layout UA when flags clear.
se_css_compute:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi
    mov     r13, rsi
    mov     r14, rdx
    cmp     r15, SE_STYLE_MAX
    jae     cc_f
    mov     rdi, r15
    call    se_css_get
    mov     rbx, rax
    mov     rdi, rbx
    xor     eax, eax
    mov     rcx, SE_STYLE_SIZE
    rep stosb
    xor     r12d, r12d
cc_r:
    cmp     r12, [rip+se_rule_count]
    jae     cc_i
    imul    rax, r12, RULE_STRIDE
    lea     rdx, [rip+se_rules]
    add     rax, rdx
    push    rax
    mov     rdi, r13
    mov     rsi, rax
    call    css_tag_eq
    pop     rsi
    test    rax, rax
    jz      cc_n
    lea     rdi, [rsi+SE_TAG_MAX]
    call    css_merge_style
cc_n:
    inc     r12
    jmp     cc_r
cc_i:
    test    r14, r14
    jz      cc_o
    cmp     byte ptr [r14], 0
    je      cc_o
    mov     rdi, r14
    mov     rsi, rbx
    call    se_css_parse_decls
cc_o:
    mov     rax, rbx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
cc_f:
    xor     rax, rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

css_parse_stylesheet:
    push    rbx
    push    r12
    mov     r12, rdi
ss_l:
    call    css_skip_ws_r12
    cmp     byte ptr [r12], 0
    je      ss_d
    lea     rbx, [rip+tmp_tag]
    xor     rcx, rcx
ss_s:
    mov     al, [r12]
    test    al, al
    jz      ss_d
    cmp     al, '{'
    je      ss_b
    cmp     al, ' '
    je      ss_w
    cmp     al, 9
    je      ss_w
    cmp     al, 10
    je      ss_w
    cmp     rcx, SE_TAG_MAX - 1
    jae     ss_a
    cmp     al, 'A'
    jb      ss_t
    cmp     al, 'Z'
    ja      ss_t
    add     al, 32
ss_t:
    mov     [rbx+rcx], al
    inc     rcx
ss_a:
    inc     r12
    jmp     ss_s
ss_w:
    inc     r12
    jmp     ss_s
ss_b:
    mov     byte ptr [rbx+rcx], 0
    inc     r12
    lea     rbx, [rip+tmp_decls]
    xor     rcx, rcx
ss_y:
    mov     al, [r12]
    test    al, al
    jz      ss_d
    cmp     al, '}'
    je      ss_e
    cmp     rcx, 510
    jae     ss_x
    mov     [rbx+rcx], al
    inc     rcx
ss_x:
    inc     r12
    jmp     ss_y
ss_e:
    mov     byte ptr [rbx+rcx], 0
    inc     r12
    lea     rdi, [rip+tmp_tag]
    lea     rsi, [rip+tmp_decls]
    call    se_css_add_rule
    jmp     ss_l
ss_d:
    pop     r12
    pop     rbx
    ret

# ============================================================
# Attach to live HTML DOM + html_buf from engine parse
# ============================================================
se_css_attach:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    call    se_css_reset
    mov     rax, [rip+nnodes]
    cmp     rax, SE_STYLE_MAX
    jbe     1f
    mov     rax, SE_STYLE_MAX
1:  mov     [rip+se_style_count], rax

    # Pass 1: <style> bodies from html_buf (full text, not 40-byte data)
    lea     r12, [rip+html_buf]
at_sheets:
    mov     rdi, r12
    lea     rsi, [rip+n_style_tag]
    call    css_find_ci
    test    rax, rax
    jz      at_nodes
    mov     r12, rax
1:  mov     al, [r12]
    test    al, al
    jz      at_nodes
    cmp     al, '>'
    je      2f
    inc     r12
    jmp     1b
2:  inc     r12
    mov     r13, r12
    mov     rdi, r12
    lea     rsi, [rip+n_style_end]
    call    css_find_ci
    test    rax, rax
    jz      at_nodes
    mov     r14, rax
    mov     byte ptr [r14], 0
    mov     rdi, r13
    call    css_parse_stylesheet
    mov     byte ptr [r14], '<'
    lea     r12, [r14+1]
    jmp     at_sheets

at_nodes:
    mov     qword ptr [rip+scan_pos], 0
    xor     r15, r15
at_loop:
    cmp     r15, [rip+se_style_count]
    jae     at_done
    imul    rax, r15, NODE_SIZE
    lea     rdx, [rip+nodes]
    add     rax, rdx
    mov     rbx, rax
    cmp     byte ptr [rbx+OFF_KIND], KIND_ELEM
    jne     at_next
    # tag name in data[]
    lea     r13, [rbx+DATA_OFF]
    # advance html_buf to this element's open tag
    call    css_next_open_tag
    test    rax, rax
    jz      at_ua
    mov     r12, rax
    mov     rdi, r12
    call    css_tag_gt
    mov     r14, rax
    test    r14, r14
    jz      at_ua
    # extract style= between r12 and r14
    mov     rdi, r12
    mov     rsi, r14
    call    css_extract_style_attr
    mov     rdx, rax
    test    rdx, rdx
    jz      3f
    lea     rdx, [rip+tmp_decls]
3:  mov     rdi, r15
    mov     rsi, r13
    call    se_css_compute
    # advance scan past '>'
    lea     rax, [r14+1]
    lea     rcx, [rip+html_buf]
    sub     rax, rcx
    mov     [rip+scan_pos], rax
    jmp     at_next
at_ua:
    # still compute sheet-only (no inline)
    mov     rdi, r15
    mov     rsi, r13
    xor     rdx, rdx
    call    se_css_compute
at_next:
    inc     r15
    jmp     at_loop
at_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# Find next open tag in html_buf at scan_pos matching nothing —
# just next open element tag. → rax=ptr at '<' or 0
css_next_open_tag:
    push    rbx
    lea     rbx, [rip+html_buf]
    mov     rax, [rip+scan_pos]
    add     rax, rbx
1:  mov     cl, [rax]
    test    cl, cl
    jz      nt_0
    cmp     cl, '<'
    je      2f
    inc     rax
    jmp     1b
2:  cmp     byte ptr [rax+1], '/'
    je      3f
    cmp     byte ptr [rax+1], '!'
    je      3f
    cmp     byte ptr [rax+1], '?'
    je      3f
    pop     rbx
    ret
3:  # skip this tag
    push    rax
    mov     rdi, rax
    call    css_tag_gt
    pop     rdx
    test    rax, rax
    jz      nt_0
    lea     rax, [rax+1]
    jmp     1b
nt_0:
    xor     rax, rax
    pop     rbx
    ret

css_tag_gt:
1:  mov     al, [rdi]
    test    al, al
    jz      2f
    cmp     al, '>'
    je      3f
    inc     rdi
    jmp     1b
2:  xor     rax, rax
    ret
3:  mov     rax, rdi
    ret

# rdi=tag start rsi=gt → rax=1 + tmp_decls if style=, else 0
css_extract_style_attr:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    mov     byte ptr [r13], 0
    mov     rdi, r12
    lea     rsi, [rip+n_style_eq]
    call    css_find_ci
    mov     byte ptr [r13], '>'
    test    rax, rax
    jz      es_0
    cmp     rax, r13
    jae     es_0
    add     rax, 6
    mov     bl, [rax]
    cmp     bl, '"'
    je      es_q
    cmp     bl, 0x27
    je      es_q
    jmp     es_0
es_q:
    inc     rax
    lea     rdi, [rip+tmp_decls]
    xor     rcx, rcx
es_c:
    mov     dl, [rax]
    test    dl, dl
    jz      es_1
    cmp     dl, bl
    je      es_1
    cmp     rcx, 510
    jae     es_a
    mov     [rdi+rcx], dl
    inc     rcx
es_a:
    inc     rax
    jmp     es_c
es_1:
    mov     byte ptr [rdi+rcx], 0
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
es_0:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret

# ============================================================
# JSON + selftest
# ============================================================
css_itoa_u:
    push    rbx
    push    r8
    mov     ebx, 10
    xor     r8, r8
    test    eax, eax
    jnz     it_d
    mov     byte ptr [rdi], '0'
    inc     rdi
    jmp     it_x
it_d:
    test    eax, eax
    jz      it_p
    xor     edx, edx
    div     ebx
    add     dl, '0'
    push    rdx
    inc     r8
    jmp     it_d
it_p:
    test    r8, r8
    jz      it_x
    pop     rdx
    mov     [rdi], dl
    inc     rdi
    dec     r8
    jmp     it_p
it_x:
    pop     r8
    pop     rbx
    ret

css_emit_hex6:
    push    rbx
    mov     ebx, eax
    mov     ecx, 6
1:  mov     eax, ebx
    shr     eax, 20
    and     eax, 0xf
    cmp     al, 10
    jb      2f
    add     al, 'a' - 10
    jmp     3f
2:  add     al, '0'
3:  mov     [rdi], al
    inc     rdi
    shl     ebx, 4
    dec     ecx
    jnz     1b
    pop     rbx
    ret

ej_key_display:
    mov     rax, 0x226c7073696400  # unused
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'd'
    mov     byte ptr [rdi+2], 'i'
    mov     byte ptr [rdi+3], 's'
    mov     byte ptr [rdi+4], 'p'
    mov     byte ptr [rdi+5], 'l'
    mov     byte ptr [rdi+6], 'a'
    mov     byte ptr [rdi+7], 'y'
    mov     byte ptr [rdi+8], '"'
    mov     byte ptr [rdi+9], ':'
    add     rdi, 10
    ret
ej_key_color:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'c'
    mov     byte ptr [rdi+2], 'o'
    mov     byte ptr [rdi+3], 'l'
    mov     byte ptr [rdi+4], 'o'
    mov     byte ptr [rdi+5], 'r'
    mov     byte ptr [rdi+6], '"'
    mov     byte ptr [rdi+7], ':'
    add     rdi, 8
    ret
ej_key_font:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'f'
    mov     byte ptr [rdi+2], 'o'
    mov     byte ptr [rdi+3], 'n'
    mov     byte ptr [rdi+4], 't'
    mov     byte ptr [rdi+5], '_'
    mov     byte ptr [rdi+6], 's'
    mov     byte ptr [rdi+7], 'i'
    mov     byte ptr [rdi+8], 'z'
    mov     byte ptr [rdi+9], 'e'
    mov     byte ptr [rdi+10], '"'
    mov     byte ptr [rdi+11], ':'
    add     rdi, 12
    ret
ej_key_margin:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'm'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'r'
    mov     byte ptr [rdi+4], 'g'
    mov     byte ptr [rdi+5], 'i'
    mov     byte ptr [rdi+6], 'n'
    mov     byte ptr [rdi+7], '"'
    mov     byte ptr [rdi+8], ':'
    add     rdi, 9
    ret
ej_key_padding:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'p'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'd'
    mov     byte ptr [rdi+4], 'd'
    mov     byte ptr [rdi+5], 'i'
    mov     byte ptr [rdi+6], 'n'
    mov     byte ptr [rdi+7], 'g'
    mov     byte ptr [rdi+8], '"'
    mov     byte ptr [rdi+9], ':'
    add     rdi, 10
    ret
ej_key_border_width:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'b'
    mov     byte ptr [rdi+2], 'o'
    mov     byte ptr [rdi+3], 'r'
    mov     byte ptr [rdi+4], 'd'
    mov     byte ptr [rdi+5], 'e'
    mov     byte ptr [rdi+6], 'r'
    mov     byte ptr [rdi+7], '_'
    mov     byte ptr [rdi+8], 'w'
    mov     byte ptr [rdi+9], 'i'
    mov     byte ptr [rdi+10], 'd'
    mov     byte ptr [rdi+11], 't'
    mov     byte ptr [rdi+12], 'h'
    mov     byte ptr [rdi+13], '"'
    mov     byte ptr [rdi+14], ':'
    add     rdi, 15
    ret
ej_key_bgcolor:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'b'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'c'
    mov     byte ptr [rdi+4], 'k'
    mov     byte ptr [rdi+5], 'g'
    mov     byte ptr [rdi+6], 'r'
    mov     byte ptr [rdi+7], 'o'
    mov     byte ptr [rdi+8], 'u'
    mov     byte ptr [rdi+9], 'n'
    mov     byte ptr [rdi+10], 'd'
    mov     byte ptr [rdi+11], '_'
    mov     byte ptr [rdi+12], 'c'
    mov     byte ptr [rdi+13], 'o'
    mov     byte ptr [rdi+14], 'l'
    mov     byte ptr [rdi+15], 'o'
    mov     byte ptr [rdi+16], 'r'
    mov     byte ptr [rdi+17], '"'
    mov     byte ptr [rdi+18], ':'
    add     rdi, 19
    ret
ej_key_width:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'w'
    mov     byte ptr [rdi+2], 'i'
    mov     byte ptr [rdi+3], 'd'
    mov     byte ptr [rdi+4], 't'
    mov     byte ptr [rdi+5], 'h'
    mov     byte ptr [rdi+6], '"'
    mov     byte ptr [rdi+7], ':'
    add     rdi, 8
    ret
ej_key_height:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'h'
    mov     byte ptr [rdi+2], 'e'
    mov     byte ptr [rdi+3], 'i'
    mov     byte ptr [rdi+4], 'g'
    mov     byte ptr [rdi+5], 'h'
    mov     byte ptr [rdi+6], 't'
    mov     byte ptr [rdi+7], '"'
    mov     byte ptr [rdi+8], ':'
    add     rdi, 9
    ret
ej_key_max_height:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'm'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'x'
    mov     byte ptr [rdi+4], '_'
    mov     byte ptr [rdi+5], 'h'
    mov     byte ptr [rdi+6], 'e'
    mov     byte ptr [rdi+7], 'i'
    mov     byte ptr [rdi+8], 'g'
    mov     byte ptr [rdi+9], 'h'
    mov     byte ptr [rdi+10], 't'
    mov     byte ptr [rdi+11], '"'
    mov     byte ptr [rdi+12], ':'
    add     rdi, 13
    ret
ej_key_min_height:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'm'
    mov     byte ptr [rdi+2], 'i'
    mov     byte ptr [rdi+3], 'n'
    mov     byte ptr [rdi+4], '_'
    mov     byte ptr [rdi+5], 'h'
    mov     byte ptr [rdi+6], 'e'
    mov     byte ptr [rdi+7], 'i'
    mov     byte ptr [rdi+8], 'g'
    mov     byte ptr [rdi+9], 'h'
    mov     byte ptr [rdi+10], 't'
    mov     byte ptr [rdi+11], '"'
    mov     byte ptr [rdi+12], ':'
    add     rdi, 13
    ret
ej_key_max_width:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'm'
    mov     byte ptr [rdi+2], 'a'
    mov     byte ptr [rdi+3], 'x'
    mov     byte ptr [rdi+4], '_'
    mov     byte ptr [rdi+5], 'w'
    mov     byte ptr [rdi+6], 'i'
    mov     byte ptr [rdi+7], 'd'
    mov     byte ptr [rdi+8], 't'
    mov     byte ptr [rdi+9], 'h'
    mov     byte ptr [rdi+10], '"'
    mov     byte ptr [rdi+11], ':'
    add     rdi, 12
    ret
ej_key_min_width:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'm'
    mov     byte ptr [rdi+2], 'i'
    mov     byte ptr [rdi+3], 'n'
    mov     byte ptr [rdi+4], '_'
    mov     byte ptr [rdi+5], 'w'
    mov     byte ptr [rdi+6], 'i'
    mov     byte ptr [rdi+7], 'd'
    mov     byte ptr [rdi+8], 't'
    mov     byte ptr [rdi+9], 'h'
    mov     byte ptr [rdi+10], '"'
    mov     byte ptr [rdi+11], ':'
    add     rdi, 12
    ret
ej_key_border_color:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'b'
    mov     byte ptr [rdi+2], 'o'
    mov     byte ptr [rdi+3], 'r'
    mov     byte ptr [rdi+4], 'd'
    mov     byte ptr [rdi+5], 'e'
    mov     byte ptr [rdi+6], 'r'
    mov     byte ptr [rdi+7], '_'
    mov     byte ptr [rdi+8], 'c'
    mov     byte ptr [rdi+9], 'o'
    mov     byte ptr [rdi+10], 'l'
    mov     byte ptr [rdi+11], 'o'
    mov     byte ptr [rdi+12], 'r'
    mov     byte ptr [rdi+13], '"'
    mov     byte ptr [rdi+14], ':'
    add     rdi, 15
    ret
ej_key_border_style:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'b'
    mov     byte ptr [rdi+2], 'o'
    mov     byte ptr [rdi+3], 'r'
    mov     byte ptr [rdi+4], 'd'
    mov     byte ptr [rdi+5], 'e'
    mov     byte ptr [rdi+6], 'r'
    mov     byte ptr [rdi+7], '_'
    mov     byte ptr [rdi+8], 's'
    mov     byte ptr [rdi+9], 't'
    mov     byte ptr [rdi+10], 'y'
    mov     byte ptr [rdi+11], 'l'
    mov     byte ptr [rdi+12], 'e'
    mov     byte ptr [rdi+13], '"'
    mov     byte ptr [rdi+14], ':'
    add     rdi, 15
    ret
ej_key_visibility:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'v'
    mov     byte ptr [rdi+2], 'i'
    mov     byte ptr [rdi+3], 's'
    mov     byte ptr [rdi+4], 'i'
    mov     byte ptr [rdi+5], 'b'
    mov     byte ptr [rdi+6], 'i'
    mov     byte ptr [rdi+7], 'l'
    mov     byte ptr [rdi+8], 'i'
    mov     byte ptr [rdi+9], 't'
    mov     byte ptr [rdi+10], 'y'
    mov     byte ptr [rdi+11], '"'
    mov     byte ptr [rdi+12], ':'
    add     rdi, 13
    ret
ej_key_opacity:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'o'
    mov     byte ptr [rdi+2], 'p'
    mov     byte ptr [rdi+3], 'a'
    mov     byte ptr [rdi+4], 'c'
    mov     byte ptr [rdi+5], 'i'
    mov     byte ptr [rdi+6], 't'
    mov     byte ptr [rdi+7], 'y'
    mov     byte ptr [rdi+8], '"'
    mov     byte ptr [rdi+9], ':'
    add     rdi, 10
    ret
ej_key_flags:
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'f'
    mov     byte ptr [rdi+2], 'l'
    mov     byte ptr [rdi+3], 'a'
    mov     byte ptr [rdi+4], 'g'
    mov     byte ptr [rdi+5], 's'
    mov     byte ptr [rdi+6], '"'
    mov     byte ptr [rdi+7], ':'
    add     rdi, 8
    ret

css_emit_json:
    push    rbx
    push    r13
    push    r14
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_browser]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_engine]
    mov     rsi, MODE_0755
    call    sys_mkdir

    lea     rdi, [rip+out_buf]
    lea     rsi, [rip+j_pre]
    mov     rcx, j_pre_len
    rep movsb
    mov     rax, [rip+se_style_count]
    call    css_itoa_u
    lea     rsi, [rip+j_mid]
    mov     rcx, j_mid_len
    rep movsb

    xor     r13, r13
ej_l:
    cmp     r13, [rip+se_style_count]
    jae     ej_e
    test    r13, r13
    jz      ej_o
    mov     byte ptr [rdi], ','
    inc     rdi
ej_o:
    mov     byte ptr [rdi], '{'
    inc     rdi
    mov     byte ptr [rdi], '"'
    mov     byte ptr [rdi+1], 'i'
    mov     byte ptr [rdi+2], 'd'
    mov     byte ptr [rdi+3], '"'
    mov     byte ptr [rdi+4], ':'
    add     rdi, 5
    mov     rax, r13
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_display
    imul    r14, r13, SE_STYLE_SIZE
    lea     rax, [rip+se_style_pool]
    add     r14, rax
    mov     eax, [r14+SE_OFF_DISPLAY]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_color
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     eax, [r14+SE_OFF_COLOR]
    cmp     eax, SE_BG_TRANSPARENT
    jne     ej_co_hex
    lea     rsi, [rip+n_transparent]
    mov     rcx, 11
    rep movsb
    jmp     ej_co_q
ej_co_hex:
    call    css_emit_hex6
ej_co_q:
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_font
    mov     eax, [r14+SE_OFF_FONT]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_margin
    mov     eax, [r14+SE_OFF_MARGIN]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_padding
    mov     eax, [r14+SE_OFF_PADDING]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_border_width
    mov     eax, [r14+SE_OFF_BORDER_W]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_bgcolor
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     eax, [r14+SE_OFF_BG]
    cmp     eax, SE_BG_TRANSPARENT
    jne     ej_bg_hex
    lea     rsi, [rip+n_transparent]
    mov     rcx, 11
    rep movsb
    jmp     ej_bg_q
ej_bg_hex:
    call    css_emit_hex6
ej_bg_q:
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_width
    mov     eax, [r14+SE_OFF_WIDTH]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_height
    mov     eax, [r14+SE_OFF_HEIGHT]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_max_height
    mov     eax, [r14+SE_OFF_MAX_HEIGHT]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_min_height
    mov     eax, [r14+SE_OFF_MIN_HEIGHT]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_max_width
    mov     eax, [r14+SE_OFF_MAX_WIDTH]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_min_width
    mov     eax, [r14+SE_OFF_MIN_WIDTH]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_border_color
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     eax, [r14+SE_OFF_BORDER_C]
    call    css_emit_hex6
    mov     byte ptr [rdi], '"'
    inc     rdi
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_border_style
    mov     eax, [r14+SE_OFF_BORDER_S]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_visibility
    mov     eax, [r14+SE_OFF_VIS]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_opacity
    mov     eax, [r14+SE_OFF_OPACITY]
    call    css_itoa_u
    mov     byte ptr [rdi], ','
    inc     rdi
    call    ej_key_flags
    mov     eax, [r14+SE_OFF_FLAGS]
    call    css_itoa_u
    mov     byte ptr [rdi], '}'
    inc     rdi
    inc     r13
    jmp     ej_l
ej_e:
    lea     rsi, [rip+j_post]
    mov     rcx, j_post_len
    rep movsb
    lea     rax, [rip+out_buf]
    mov     rdx, rdi
    sub     rdx, rax
    lea     rdi, [rip+path_css_json]
    lea     rsi, [rip+out_buf]
    call    write_bytes_path
    pop     r14
    pop     r13
    pop     rbx
    ret

# Need p with inline color #c80000 + font 20 (flags set)
css_selftest:
    push    rbx
    mov     rax, [rip+se_style_count]
    cmp     rax, 3
    jb      st_f
    xor     ebx, ebx
st_l:
    cmp     rbx, [rip+se_style_count]
    jae     st_f
    mov     rdi, rbx
    call    se_css_get
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_FONT
    jz      st_n
    cmp     dword ptr [rax+SE_OFF_FONT], 20
    jne     st_n
    test    dword ptr [rax+SE_OFF_FLAGS], SE_FLAG_COLOR
    jz      st_n
    cmp     dword ptr [rax+SE_OFF_COLOR], 0x00C80000
    jne     st_n
    mov     rax, 1
    pop     rbx
    ret
st_n:
    inc     rbx
    jmp     st_l
st_f:
    xor     rax, rax
    pop     rbx
    ret
