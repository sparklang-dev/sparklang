# Spark engine B — HTML tokenizer + parser + DOM (asm only).
# Owner lane: parse→DOM. After parse: <script> text →
# engine_js_run_dom_scripts (phase-1 tiny JS only; not full ES).
# Dispatch: `engine parse "path.html"` → out/browser/engine/dom.json
# Exports: engine_html_ops_dispatch
# Never Chromium / Qt / Python / libc.

.intel_syntax noprefix
.global engine_html_ops_dispatch
.global nodes
.global nnodes
.global html_buf
.global html_len
.global root_id
.global body_id

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern msg_nl
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern engine_js_run_dom_scripts

.equ O_RDONLY, 0
.equ MODE_0755, 493
.equ HTML_CAP, 65536
.equ MAX_NODES, 256
.equ NODE_SIZE, 64
.equ DATA_OFF, 24
.equ DATA_LEN, 40
.equ STACK_MAX, 64
.equ OUT_CAP, 49152

# Node fields (little-endian offsets)
# 0 kind u8: 1=element 2=text
# 1 tag  u8
# 2 void u8
# 3 pad
# 4 parent i32
# 8 first_child i32
# 12 last_child i32
# 16 next_sibling i32
# 20 pad i32
# 24 data[40]

.equ KIND_ELEM, 1
.equ KIND_TEXT, 2
.equ TAG_UNK, 0
.equ TAG_HTML, 1
.equ TAG_HEAD, 2
.equ TAG_BODY, 3
.equ TAG_TITLE, 4
.equ TAG_P, 5
.equ TAG_H1, 6
.equ TAG_H2, 7
.equ TAG_H3, 8
.equ TAG_A, 9
.equ TAG_DIV, 10
.equ TAG_SPAN, 11
.equ TAG_IMG, 12
.equ TAG_UL, 13
.equ TAG_LI, 14
.equ TAG_SCRIPT, 15
.equ TAG_STYLE, 16
.equ TAG_BR, 17
.equ TAG_TABLE, 18
.equ TAG_TR, 19
.equ TAG_TD, 20
.equ TAG_TH, 21

.section .bss
.align 16
html_buf:       .space HTML_CAP
html_len:       .space 8
path_buf:       .space 512
nodes:          .space MAX_NODES * NODE_SIZE
nnodes:         .space 8
nelements:      .space 8
ntexts:         .space 8
tag_stack:      .space STACK_MAX * 4
stack_sp:       .space 8
root_id:        .space 8
body_id:        .space 8
parse_pos:      .space 8
out_buf:        .space OUT_CAP
out_ptr:        .space 8
tmp_name:       .space 64
tmp_num:        .space 32
cnt_html:       .space 8
cnt_p:          .space 8
cnt_h1:         .space 8
cnt_h2:         .space 8
cnt_h3:         .space 8
cnt_a:          .space 8
cnt_div:        .space 8
cnt_span:       .space 8
cnt_ul:         .space 8
cnt_li:         .space 8
cnt_img:        .space 8
cnt_table:      .space 8
cnt_tr:         .space 8
cnt_td:         .space 8
cnt_th:         .space 8

.section .data
msg_eng:    .ascii "[engine] "
msg_eng_len = . - msg_eng
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow

needle_parse: .ascii "parse\0"
needle_file:  .ascii "file://\0"

path_out:     .ascii "out\0"
path_br:      .ascii "out/browser\0"
path_eng:     .ascii "out/browser/engine\0"
path_dom:     .ascii "out/browser/engine/dom.json\0"
default_html: .ascii "engine/fixtures/hello.html\0"

err_unknown:
    .ascii "error: unknown engine op (want: parse)\n"
err_unknown_len = . - err_unknown
err_open:
    .ascii "error: engine parse cannot open HTML path\n"
err_open_len = . - err_open
err_oom:
    .ascii "error: engine DOM node pool full\n"
err_oom_len = . - err_oom
err_js_script:
    .ascii "error: engine parse: <script> phase-1 "
    .ascii "eval failed (want number|string|+|"
    .ascii "console.log; not full ES)\n"
err_js_script_len = . - err_js_script

# Fixed JSON spine (counts filled via append helpers)
j_pre:
    .ascii "{\"op\":\"engine.parse\",\"ok\":true,"
    .ascii "\"engine\":\"spark-asm-html\","
    .ascii "\"nnodes\":"
j_pre_len = . - j_pre
j_nel:  .ascii ",\"nelements\":"
j_nel_len = . - j_nel
j_ntx:  .ascii ",\"ntexts\":"
j_ntx_len = . - j_ntx
j_root: .ascii ",\"root\":"
j_root_len = . - j_root
j_body: .ascii ",\"body\":"
j_body_len = . - j_body
j_tags: .ascii ",\"tag_counts\":{\"html\":"
j_tags_len = . - j_tags
j_tp:   .ascii ",\"p\":"
j_tp_len = . - j_tp
j_th1:  .ascii ",\"h1\":"
j_th1_len = . - j_th1
j_th2:  .ascii ",\"h2\":"
j_th2_len = . - j_th2
j_th3:  .ascii ",\"h3\":"
j_th3_len = . - j_th3
j_ta:   .ascii ",\"a\":"
j_ta_len = . - j_ta
j_td:   .ascii ",\"div\":"
j_td_len = . - j_td
j_ts:   .ascii ",\"span\":"
j_ts_len = . - j_ts
j_tu:   .ascii ",\"ul\":"
j_tu_len = . - j_tu
j_tl:   .ascii ",\"li\":"
j_tl_len = . - j_tl
j_ti:   .ascii ",\"img\":"
j_ti_len = . - j_ti
j_ttable: .ascii ",\"table\":"
j_ttable_len = . - j_ttable
j_ttr:  .ascii ",\"tr\":"
j_ttr_len = . - j_ttr
j_ttd:  .ascii ",\"td\":"
j_ttd_len = . - j_ttd
j_tth:  .ascii ",\"th\":"
j_tth_len = . - j_tth
j_nodes:.ascii "},\"nodes\":["
j_nodes_len = . - j_nodes
j_end:  .ascii "]}\n"
j_end_len = . - j_end

# per-node JSON fragments (must be defined before emit uses lens)
em_id:   .ascii "\"id\":"
em_id_len = . - em_id
em_k:    .ascii ",\"k\":"
em_k_len = . - em_k
em_e:    .ascii "\"e\""
em_e_len = . - em_e
em_t:    .ascii "\"t\""
em_t_len = . - em_t
em_tag:  .ascii ",\"tag\":\""
em_tag_len = . - em_tag
em_text: .ascii ",\"text\":\""
em_text_len = . - em_text
em_p:    .ascii "\",\"p\":"
em_p_len = . - em_p
em_fc:   .ascii ",\"fc\":"
em_fc_len = . - em_fc
em_ns:   .ascii ",\"ns\":"
em_ns_len = . - em_ns

# tag name table (cstrs for emit + match)
tn_html:   .ascii "html\0"
tn_head:   .ascii "head\0"
tn_body:   .ascii "body\0"
tn_title:  .ascii "title\0"
tn_p:      .ascii "p\0"
tn_h1:     .ascii "h1\0"
tn_h2:     .ascii "h2\0"
tn_h3:     .ascii "h3\0"
tn_a:      .ascii "a\0"
tn_div:    .ascii "div\0"
tn_span:   .ascii "span\0"
tn_img:    .ascii "img\0"
tn_ul:     .ascii "ul\0"
tn_li:     .ascii "li\0"
tn_script: .ascii "script\0"
tn_style:  .ascii "style\0"
tn_br:     .ascii "br\0"
tn_table:  .ascii "table\0"
tn_tr:     .ascii "tr\0"
tn_td:     .ascii "td\0"
tn_th:     .ascii "th\0"
tn_unk:    .ascii "unknown\0"

.section .text

# ------------------------------------------------------------
engine_html_ops_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     rsi, [rip+msg_eng]
    mov     rdx, msg_eng_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_parse]
    call    contains
    test    rax, rax
    jnz     eng_parse

    lea     rsi, [rip+err_unknown]
    mov     rdx, err_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- engine parse ----------
eng_parse:
    call    eng_ensure_dirs
    # path from quote or default
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      eng_def_path
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+path_buf]
    xor     r13, r13
eng_copy_path:
    cmp     r13, r12
    jge     eng_path_term
    cmp     r13, 510
    jge     eng_path_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     eng_copy_path
eng_path_term:
    mov     byte ptr [rdi+r13], 0
    jmp     eng_strip_file
eng_def_path:
    lea     rsi, [rip+default_html]
    lea     rdi, [rip+path_buf]
    call    eng_copy_cstr
eng_strip_file:
    # strip file:// prefix if present
    lea     rdi, [rip+path_buf]
    lea     rsi, [rip+needle_file]
    call    eng_startswith
    test    rax, rax
    jz      eng_load
    # shift path left by 7
    lea     rsi, [rip+path_buf+7]
    lea     rdi, [rip+path_buf]
    call    eng_copy_cstr
eng_load:
    call    eng_load_html
    test    rax, rax
    jz      eng_open_fail
    call    eng_parse_html
    # Hook: <script> text → phase-1 engine_js_eval (tiny only)
    call    engine_js_run_dom_scripts
    test    rax, rax
    jz      eng_js_ok
    lea     rsi, [rip+err_js_script]
    mov     rdx, err_js_script_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
eng_js_ok:
    call    eng_write_dom_json

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    # print first line of out (stats) from out_buf already written;
    # re-print compact summary from out_buf start via write_stdout
    lea     rsi, [rip+out_buf]
    call    strlen
    mov     rdx, rax
    cmp     rdx, 512
    jbe     eng_print_ok
    mov     rdx, 512
eng_print_ok:
    lea     rsi, [rip+out_buf]
    call    write_stdout
    # ensure newline if truncated
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rsi, [rip+out_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+out_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     eng_done

eng_open_fail:
    lea     rsi, [rip+err_open]
    mov     rdx, err_open_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

eng_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
eng_ensure_dirs:
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_br]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_eng]
    mov     rsi, MODE_0755
    call    sys_mkdir
    ret

# ------------------------------------------------------------
# eng_load_html: path_buf → html_buf; rax=1 ok, 0 fail
eng_load_html:
    push    rbx
    lea     rdi, [rip+path_buf]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      elh_fail
    mov     rbx, rax
    lea     rsi, [rip+html_buf]
    mov     rdx, HTML_CAP - 1
    mov     rdi, rbx
    call    sys_read
    cmp     rax, 0
    jl      elh_fail_close
    mov     [rip+html_len], rax
    lea     rdi, [rip+html_buf]
    mov     byte ptr [rdi+rax], 0
    mov     rdi, rbx
    call    sys_close
    mov     rax, 1
    pop     rbx
    ret
elh_fail_close:
    mov     rdi, rbx
    call    sys_close
elh_fail:
    xor     rax, rax
    pop     rbx
    ret

# ------------------------------------------------------------
# eng_parse_html — tokenize + build DOM in nodes[]
eng_parse_html:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    # reset pools / counts
    mov     qword ptr [rip+nnodes], 0
    mov     qword ptr [rip+nelements], 0
    mov     qword ptr [rip+ntexts], 0
    mov     qword ptr [rip+stack_sp], 0
    mov     qword ptr [rip+root_id], -1
    mov     qword ptr [rip+body_id], -1
    mov     qword ptr [rip+parse_pos], 0
    mov     qword ptr [rip+cnt_html], 0
    mov     qword ptr [rip+cnt_p], 0
    mov     qword ptr [rip+cnt_h1], 0
    mov     qword ptr [rip+cnt_h2], 0
    mov     qword ptr [rip+cnt_h3], 0
    mov     qword ptr [rip+cnt_a], 0
    mov     qword ptr [rip+cnt_div], 0
    mov     qword ptr [rip+cnt_span], 0
    mov     qword ptr [rip+cnt_ul], 0
    mov     qword ptr [rip+cnt_li], 0
    mov     qword ptr [rip+cnt_img], 0
    mov     qword ptr [rip+cnt_table], 0
    mov     qword ptr [rip+cnt_tr], 0
    mov     qword ptr [rip+cnt_td], 0
    mov     qword ptr [rip+cnt_th], 0

parse_loop:
    mov     rax, [rip+parse_pos]
    cmp     rax, [rip+html_len]
    jge     parse_done
    lea     rbx, [rip+html_buf]
    mov     al, [rbx+rax]
    cmp     al, '<'
    je      parse_tag
    # text run
    call    parse_text_run
    jmp     parse_loop

parse_tag:
    # advance past '<'
    inc     qword ptr [rip+parse_pos]
    mov     rax, [rip+parse_pos]
    cmp     rax, [rip+html_len]
    jge     parse_done
    lea     rbx, [rip+html_buf]
    mov     al, [rbx+rax]
    # comment?
    cmp     al, '!'
    jne     pt_not_bang
    call    skip_comment_or_doctype
    jmp     parse_loop
pt_not_bang:
    # closing tag?
    cmp     al, '/'
    jne     pt_open
    inc     qword ptr [rip+parse_pos]
    call    read_tag_name
    mov     r15, rax
    call    skip_to_gt
    mov     eax, r15d
    call    pop_until_tag
    jmp     parse_loop

pt_open:
    call    read_tag_name
    # r15 = tag id from read_tag_name (in rax)
    mov     r15, rax
    call    skip_attrs_to_gt
    # r14 = void flag from skip (rax)
    mov     r14, rax
    # force void for img/br
    cmp     r15d, TAG_IMG
    je      pt_force_void
    cmp     r15d, TAG_BR
    je      pt_force_void
    jmp     pt_mk
pt_force_void:
    mov     r14, 1
pt_mk:
    mov     edi, r15d
    mov     esi, r14d
    call    alloc_element
    # rax = node id
    mov     r13, rax
    cmp     qword ptr [rip+root_id], -1
    jne     pt_attach
    mov     [rip+root_id], r13
pt_attach:
    cmp     r15d, TAG_BODY
    jne     pt_attach2
    mov     [rip+body_id], r13
pt_attach2:
    call    bump_tag_count
    # attach under stack top if any
    cmp     qword ptr [rip+stack_sp], 0
    je      pt_push
    call    stack_top
    mov     edi, eax
    mov     esi, r13d
    call    link_child
pt_push:
    test    r14, r14
    jnz     pt_after_void
    # push open element
    mov     edi, r13d
    call    stack_push
    # script/style: raw text until close
    cmp     r15d, TAG_SCRIPT
    je      pt_raw
    cmp     r15d, TAG_STYLE
    je      pt_raw
    jmp     parse_loop
pt_raw:
    mov     edi, r15d
    call    consume_raw_until_close
    call    stack_pop
    jmp     parse_loop
pt_after_void:
    jmp     parse_loop

parse_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# parse_text_run: from parse_pos until '<' or EOF
parse_text_run:
    push    rbx
    push    r12
    push    r13
    mov     rax, [rip+parse_pos]
    mov     r12, rax          # start
    lea     rbx, [rip+html_buf]
ptr_scan:
    cmp     rax, [rip+html_len]
    jge     ptr_end
    mov     cl, [rbx+rax]
    cmp     cl, '<'
    je      ptr_end
    inc     rax
    jmp     ptr_scan
ptr_end:
    mov     [rip+parse_pos], rax
    mov     r13, rax
    sub     r13, r12          # length
    test    r13, r13
    jz      ptr_done
    # skip if all whitespace
    mov     rdi, r12
    mov     rsi, r13
    call    text_is_ws
    test    rax, rax
    jnz     ptr_done
    # need a parent on stack
    cmp     qword ptr [rip+stack_sp], 0
    je      ptr_done
    mov     rdi, r12
    mov     rsi, r13
    call    alloc_text
    mov     r12, rax          # text node id
    call    stack_top
    mov     edi, eax
    mov     esi, r12d
    call    link_child
ptr_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# text_is_ws: rdi=start off, rsi=len → rax=1 if all ws
text_is_ws:
    push    rbx
    lea     rbx, [rip+html_buf]
    add     rbx, rdi
    mov     rcx, rsi
tiw_loop:
    test    rcx, rcx
    jz      tiw_yes
    mov     al, [rbx]
    cmp     al, ' '
    je      tiw_next
    cmp     al, 9
    je      tiw_next
    cmp     al, 10
    je      tiw_next
    cmp     al, 13
    je      tiw_next
    xor     rax, rax
    pop     rbx
    ret
tiw_next:
    inc     rbx
    dec     rcx
    jmp     tiw_loop
tiw_yes:
    mov     rax, 1
    pop     rbx
    ret

# ------------------------------------------------------------
# read_tag_name: at parse_pos, fill tmp_name, advance; rax=tag id
read_tag_name:
    push    rbx
    push    r12
    lea     rdi, [rip+tmp_name]
    xor     eax, eax
    mov     rcx, 64/8
    rep     stosq
    mov     rax, [rip+parse_pos]
    lea     rbx, [rip+html_buf]
    lea     rdi, [rip+tmp_name]
    xor     r12, r12
rtn_loop:
    cmp     rax, [rip+html_len]
    jge     rtn_done
    mov     cl, [rbx+rax]
    cmp     cl, ' '
    je      rtn_done
    cmp     cl, 9
    je      rtn_done
    cmp     cl, '>'
    je      rtn_done
    cmp     cl, '/'
    je      rtn_done
    cmp     cl, 0
    je      rtn_done
    # tolower A-Z
    cmp     cl, 'A'
    jb      rtn_store
    cmp     cl, 'Z'
    ja      rtn_store
    add     cl, 32
rtn_store:
    cmp     r12, 62
    jge     rtn_adv
    mov     [rdi+r12], cl
    inc     r12
rtn_adv:
    inc     rax
    jmp     rtn_loop
rtn_done:
    mov     [rip+parse_pos], rax
    mov     byte ptr [rdi+r12], 0
    lea     rdi, [rip+tmp_name]
    call    tag_id_from_name
    pop     r12
    pop     rbx
    ret

# tag_id_from_name: rdi=cstr → rax=tag id
tag_id_from_name:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rip+tn_html]
    call    eng_streq
    test    rax, rax
    jz      1f
    mov     eax, TAG_HTML
    pop     rbx
    ret
1:  mov     rdi, rbx
    lea     rsi, [rip+tn_head]
    call    eng_streq
    test    rax, rax
    jz      2f
    mov     eax, TAG_HEAD
    pop     rbx
    ret
2:  mov     rdi, rbx
    lea     rsi, [rip+tn_body]
    call    eng_streq
    test    rax, rax
    jz      3f
    mov     eax, TAG_BODY
    pop     rbx
    ret
3:  mov     rdi, rbx
    lea     rsi, [rip+tn_title]
    call    eng_streq
    test    rax, rax
    jz      4f
    mov     eax, TAG_TITLE
    pop     rbx
    ret
4:  mov     rdi, rbx
    lea     rsi, [rip+tn_p]
    call    eng_streq
    test    rax, rax
    jz      5f
    mov     eax, TAG_P
    pop     rbx
    ret
5:  mov     rdi, rbx
    lea     rsi, [rip+tn_h1]
    call    eng_streq
    test    rax, rax
    jz      6f
    mov     eax, TAG_H1
    pop     rbx
    ret
6:  mov     rdi, rbx
    lea     rsi, [rip+tn_h2]
    call    eng_streq
    test    rax, rax
    jz      7f
    mov     eax, TAG_H2
    pop     rbx
    ret
7:  mov     rdi, rbx
    lea     rsi, [rip+tn_h3]
    call    eng_streq
    test    rax, rax
    jz      8f
    mov     eax, TAG_H3
    pop     rbx
    ret
8:  mov     rdi, rbx
    lea     rsi, [rip+tn_a]
    call    eng_streq
    test    rax, rax
    jz      9f
    mov     eax, TAG_A
    pop     rbx
    ret
9:  mov     rdi, rbx
    lea     rsi, [rip+tn_div]
    call    eng_streq
    test    rax, rax
    jz      10f
    mov     eax, TAG_DIV
    pop     rbx
    ret
10: mov     rdi, rbx
    lea     rsi, [rip+tn_span]
    call    eng_streq
    test    rax, rax
    jz      11f
    mov     eax, TAG_SPAN
    pop     rbx
    ret
11: mov     rdi, rbx
    lea     rsi, [rip+tn_img]
    call    eng_streq
    test    rax, rax
    jz      12f
    mov     eax, TAG_IMG
    pop     rbx
    ret
12: mov     rdi, rbx
    lea     rsi, [rip+tn_ul]
    call    eng_streq
    test    rax, rax
    jz      13f
    mov     eax, TAG_UL
    pop     rbx
    ret
13: mov     rdi, rbx
    lea     rsi, [rip+tn_li]
    call    eng_streq
    test    rax, rax
    jz      14f
    mov     eax, TAG_LI
    pop     rbx
    ret
14: mov     rdi, rbx
    lea     rsi, [rip+tn_script]
    call    eng_streq
    test    rax, rax
    jz      15f
    mov     eax, TAG_SCRIPT
    pop     rbx
    ret
15: mov     rdi, rbx
    lea     rsi, [rip+tn_style]
    call    eng_streq
    test    rax, rax
    jz      16f
    mov     eax, TAG_STYLE
    pop     rbx
    ret
16: mov     rdi, rbx
    lea     rsi, [rip+tn_br]
    call    eng_streq
    test    rax, rax
    jz      17f
    mov     eax, TAG_BR
    pop     rbx
    ret
17: mov     rdi, rbx
    lea     rsi, [rip+tn_table]
    call    eng_streq
    test    rax, rax
    jz      18f
    mov     eax, TAG_TABLE
    pop     rbx
    ret
18: mov     rdi, rbx
    lea     rsi, [rip+tn_tr]
    call    eng_streq
    test    rax, rax
    jz      19f
    mov     eax, TAG_TR
    pop     rbx
    ret
19: mov     rdi, rbx
    lea     rsi, [rip+tn_td]
    call    eng_streq
    test    rax, rax
    jz      20f
    mov     eax, TAG_TD
    pop     rbx
    ret
20: mov     rdi, rbx
    lea     rsi, [rip+tn_th]
    call    eng_streq
    test    rax, rax
    jz      21f
    mov     eax, TAG_TH
    pop     rbx
    ret
21: mov     eax, TAG_UNK
    pop     rbx
    ret

# ------------------------------------------------------------
skip_to_gt:
    mov     rax, [rip+parse_pos]
    lea     rbx, [rip+html_buf]
stg_loop:
    cmp     rax, [rip+html_len]
    jge     stg_done
    cmp     byte ptr [rbx+rax], '>'
    je      stg_found
    inc     rax
    jmp     stg_loop
stg_found:
    inc     rax
stg_done:
    mov     [rip+parse_pos], rax
    ret

# skip_attrs_to_gt: rax=1 if self-closing '/' seen before '>'
skip_attrs_to_gt:
    push    rbx
    push    r12
    xor     r12, r12
    mov     rax, [rip+parse_pos]
    lea     rbx, [rip+html_buf]
sat_loop:
    cmp     rax, [rip+html_len]
    jge     sat_done
    mov     cl, [rbx+rax]
    cmp     cl, '"'
    jne     sat_sq
sat_dq:
    inc     rax
sat_dq2:
    cmp     rax, [rip+html_len]
    jge     sat_done
    cmp     byte ptr [rbx+rax], '"'
    je      sat_dq3
    inc     rax
    jmp     sat_dq2
sat_dq3:
    inc     rax
    jmp     sat_loop
sat_sq:
    cmp     cl, 0x27
    jne     sat_slash
sat_sq_loop:
    inc     rax
    cmp     rax, [rip+html_len]
    jge     sat_done
    cmp     byte ptr [rbx+rax], 0x27
    jne     sat_sq_loop
    inc     rax
    jmp     sat_loop
sat_slash:
    cmp     cl, '/'
    jne     sat_gt
    mov     r12, 1
    inc     rax
    jmp     sat_loop
sat_gt:
    cmp     cl, '>'
    je      sat_end
    inc     rax
    jmp     sat_loop
sat_end:
    inc     rax
sat_done:
    mov     [rip+parse_pos], rax
    mov     rax, r12
    pop     r12
    pop     rbx
    ret

# skip_comment_or_doctype from '!' 
skip_comment_or_doctype:
    push    rbx
    mov     rax, [rip+parse_pos]
    lea     rbx, [rip+html_buf]
    # if <!-- 
    cmp     rax, [rip+html_len]
    jge     scd_done
    # already at '!'
    inc     rax
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '-'
    jne     scd_gt
    inc     rax
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '-'
    jne     scd_gt
    inc     rax
scd_com:
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '-'
    jne     scd_cinc
    inc     rax
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '-'
    jne     scd_com
    inc     rax
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '>'
    jne     scd_com
    inc     rax
    jmp     scd_done
scd_cinc:
    inc     rax
    jmp     scd_com
scd_gt:
    # doctype / other: skip to >
scd_gloop:
    cmp     rax, [rip+html_len]
    jge     scd_done
    cmp     byte ptr [rbx+rax], '>'
    je      scd_gfound
    inc     rax
    jmp     scd_gloop
scd_gfound:
    inc     rax
scd_done:
    mov     [rip+parse_pos], rax
    pop     rbx
    ret

# ------------------------------------------------------------
# consume_raw_until_close: edi=tag id; create optional text; leave pos after </tag>
consume_raw_until_close:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14d, edi         # tag
    mov     rax, [rip+parse_pos]
    mov     r12, rax          # text start
    lea     rbx, [rip+html_buf]
cr_loop:
    cmp     rax, [rip+html_len]
    jge     cr_end
    cmp     byte ptr [rbx+rax], '<'
    jne     cr_inc
    # peek </
    mov     r13, rax
    inc     rax
    cmp     rax, [rip+html_len]
    jge     cr_end
    cmp     byte ptr [rbx+rax], '/'
    jne     cr_notclose
    # save pos at '<'
    mov     [rip+parse_pos], r13
    inc     qword ptr [rip+parse_pos]  # past <
    inc     qword ptr [rip+parse_pos]  # past /
    call    read_tag_name
    cmp     eax, r14d
    je      cr_matched
    # wrong close — treat as text continue from '<'
    mov     rax, r13
    inc     rax
    jmp     cr_loop
cr_matched:
    # text is [r12, r13)
    mov     rsi, r13
    sub     rsi, r12
    test    rsi, rsi
    jz      cr_skip_text
    mov     rdi, r12
    call    alloc_text
    mov     r12, rax
    call    stack_top
    mov     edi, eax
    mov     esi, r12d
    call    link_child
cr_skip_text:
    call    skip_to_gt
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
cr_notclose:
    mov     rax, r13
cr_inc:
    inc     rax
    jmp     cr_loop
cr_end:
    mov     [rip+parse_pos], rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# Node alloc / link / stack
# node_ptr: edi=id → rax = &nodes[id]
node_ptr:
    movsxd  rax, edi
    imul    rax, NODE_SIZE
    lea     rdx, [rip+nodes]
    add     rax, rdx
    ret

# alloc_element: edi=tag, esi=void → rax=id
alloc_element:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    mov     rax, [rip+nnodes]
    cmp     rax, MAX_NODES
    jge     ae_oom
    mov     ebx, eax
    inc     qword ptr [rip+nnodes]
    inc     qword ptr [rip+nelements]
    mov     edi, ebx
    call    node_ptr
    mov     byte ptr [rax], KIND_ELEM
    mov     [rax+1], r12b
    mov     [rax+2], r13b
    mov     dword ptr [rax+4], -1
    mov     dword ptr [rax+8], -1
    mov     dword ptr [rax+12], -1
    mov     dword ptr [rax+16], -1
    # copy tag name into data
    lea     rdi, [rax+DATA_OFF]
    mov     ecx, DATA_LEN
    xor     eax, eax
    push    rdi
    rep     stosb
    pop     rdi
    mov     edi, r12d
    call    tag_name_ptr
    mov     rsi, rax
    mov     edi, ebx
    call    node_ptr
    lea     rdi, [rax+DATA_OFF]
    call    eng_copy_cstr_n
    mov     eax, ebx
    pop     r13
    pop     r12
    pop     rbx
    ret
ae_oom:
    lea     rsi, [rip+err_oom]
    mov     rdx, err_oom_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# alloc_text: rdi=start off in html_buf, rsi=len → rax=id
alloc_text:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    mov     rax, [rip+nnodes]
    cmp     rax, MAX_NODES
    jge     ae_oom
    mov     ebx, eax
    inc     qword ptr [rip+nnodes]
    inc     qword ptr [rip+ntexts]
    mov     edi, ebx
    call    node_ptr
    mov     byte ptr [rax], KIND_TEXT
    mov     byte ptr [rax+1], 0
    mov     byte ptr [rax+2], 0
    mov     dword ptr [rax+4], -1
    mov     dword ptr [rax+8], -1
    mov     dword ptr [rax+12], -1
    mov     dword ptr [rax+16], -1
    lea     rdi, [rax+DATA_OFF]
    mov     ecx, DATA_LEN
    xor     eax, eax
    push    rdi
    rep     stosb
    pop     rdi
    # copy min(len, DATA_LEN-1)
    mov     r14, r13
    cmp     r14, DATA_LEN - 1
    jbe     at_copy
    mov     r14, DATA_LEN - 1
at_copy:
    lea     rsi, [rip+html_buf]
    add     rsi, r12
    mov     rcx, r14
    rep     movsb
    mov     byte ptr [rdi], 0
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# link_child: edi=parent, esi=child
link_child:
    push    rbx
    push    r12
    mov     r12d, edi
    mov     ebx, esi
    mov     edi, ebx
    call    node_ptr
    mov     [rax+4], r12d      # child.parent
    mov     edi, r12d
    call    node_ptr
    cmp     dword ptr [rax+8], -1
    jne     lc_append
    mov     [rax+8], ebx       # first_child
    mov     [rax+12], ebx      # last_child
    jmp     lc_done
lc_append:
    mov     edi, [rax+12]      # old last
    push    rax
    call    node_ptr
    mov     [rax+16], ebx      # next_sibling
    pop     rax
    mov     [rax+12], ebx
lc_done:
    pop     r12
    pop     rbx
    ret

stack_push:
    mov     rax, [rip+stack_sp]
    cmp     rax, STACK_MAX
    jge     sp_done
    lea     rdx, [rip+tag_stack]
    mov     [rdx+rax*4], edi
    inc     qword ptr [rip+stack_sp]
sp_done:
    ret

stack_pop:
    cmp     qword ptr [rip+stack_sp], 0
    je      spo_done
    dec     qword ptr [rip+stack_sp]
spo_done:
    ret

stack_top:
    mov     rax, [rip+stack_sp]
    test    rax, rax
    jz      st_empty
    dec     rax
    lea     rdx, [rip+tag_stack]
    mov     eax, [rdx+rax*4]
    ret
st_empty:
    mov     eax, -1
    ret

# pop_until_tag: matching tag id in eax (from read_tag_name)
pop_until_tag:
    push    rbx
    mov     ebx, eax
put_loop:
    cmp     qword ptr [rip+stack_sp], 0
    je      put_done
    call    stack_top
    mov     edi, eax
    call    node_ptr
    movzx   ecx, byte ptr [rax+1]
    call    stack_pop
    cmp     ecx, ebx
    je      put_done
    jmp     put_loop
put_done:
    pop     rbx
    ret

# bump_tag_count: uses r15 = tag id
bump_tag_count:
    cmp     r15d, TAG_HTML
    jne     1f
    inc     qword ptr [rip+cnt_html]
    ret
1:  cmp     r15d, TAG_P
    jne     2f
    inc     qword ptr [rip+cnt_p]
    ret
2:  cmp     r15d, TAG_H1
    jne     3f
    inc     qword ptr [rip+cnt_h1]
    ret
3:  cmp     r15d, TAG_H2
    jne     4f
    inc     qword ptr [rip+cnt_h2]
    ret
4:  cmp     r15d, TAG_H3
    jne     5f
    inc     qword ptr [rip+cnt_h3]
    ret
5:  cmp     r15d, TAG_A
    jne     6f
    inc     qword ptr [rip+cnt_a]
    ret
6:  cmp     r15d, TAG_DIV
    jne     7f
    inc     qword ptr [rip+cnt_div]
    ret
7:  cmp     r15d, TAG_SPAN
    jne     8f
    inc     qword ptr [rip+cnt_span]
    ret
8:  cmp     r15d, TAG_UL
    jne     9f
    inc     qword ptr [rip+cnt_ul]
    ret
9:  cmp     r15d, TAG_LI
    jne     10f
    inc     qword ptr [rip+cnt_li]
    ret
10: cmp     r15d, TAG_IMG
    jne     11f
    inc     qword ptr [rip+cnt_img]
    ret
11: cmp     r15d, TAG_TABLE
    jne     12f
    inc     qword ptr [rip+cnt_table]
    ret
12: cmp     r15d, TAG_TR
    jne     13f
    inc     qword ptr [rip+cnt_tr]
    ret
13: cmp     r15d, TAG_TD
    jne     14f
    inc     qword ptr [rip+cnt_td]
    ret
14: cmp     r15d, TAG_TH
    jne     15f
    inc     qword ptr [rip+cnt_th]
15: ret

# tag_name_ptr: edi=tag → rax=cstr
tag_name_ptr:
    cmp     edi, TAG_HTML
    jne     1f
    lea     rax, [rip+tn_html]
    ret
1:  cmp     edi, TAG_HEAD
    jne     2f
    lea     rax, [rip+tn_head]
    ret
2:  cmp     edi, TAG_BODY
    jne     3f
    lea     rax, [rip+tn_body]
    ret
3:  cmp     edi, TAG_TITLE
    jne     4f
    lea     rax, [rip+tn_title]
    ret
4:  cmp     edi, TAG_P
    jne     5f
    lea     rax, [rip+tn_p]
    ret
5:  cmp     edi, TAG_H1
    jne     6f
    lea     rax, [rip+tn_h1]
    ret
6:  cmp     edi, TAG_H2
    jne     7f
    lea     rax, [rip+tn_h2]
    ret
7:  cmp     edi, TAG_H3
    jne     8f
    lea     rax, [rip+tn_h3]
    ret
8:  cmp     edi, TAG_A
    jne     9f
    lea     rax, [rip+tn_a]
    ret
9:  cmp     edi, TAG_DIV
    jne     10f
    lea     rax, [rip+tn_div]
    ret
10: cmp     edi, TAG_SPAN
    jne     11f
    lea     rax, [rip+tn_span]
    ret
11: cmp     edi, TAG_IMG
    jne     12f
    lea     rax, [rip+tn_img]
    ret
12: cmp     edi, TAG_UL
    jne     13f
    lea     rax, [rip+tn_ul]
    ret
13: cmp     edi, TAG_LI
    jne     14f
    lea     rax, [rip+tn_li]
    ret
14: cmp     edi, TAG_SCRIPT
    jne     15f
    lea     rax, [rip+tn_script]
    ret
15: cmp     edi, TAG_STYLE
    jne     16f
    lea     rax, [rip+tn_style]
    ret
16: cmp     edi, TAG_BR
    jne     17f
    lea     rax, [rip+tn_br]
    ret
17: cmp     edi, TAG_TABLE
    jne     18f
    lea     rax, [rip+tn_table]
    ret
18: cmp     edi, TAG_TR
    jne     19f
    lea     rax, [rip+tn_tr]
    ret
19: cmp     edi, TAG_TD
    jne     20f
    lea     rax, [rip+tn_td]
    ret
20: cmp     edi, TAG_TH
    jne     21f
    lea     rax, [rip+tn_th]
    ret
21: lea     rax, [rip+tn_unk]
    ret

# ------------------------------------------------------------
# Serialize DOM JSON
eng_write_dom_json:
    push    rbx
    push    r12
    lea     rax, [rip+out_buf]
    mov     [rip+out_ptr], rax

    lea     rsi, [rip+j_pre]
    mov     rdx, j_pre_len
    call    out_append
    mov     rax, [rip+nnodes]
    call    out_u64
    lea     rsi, [rip+j_nel]
    mov     rdx, j_nel_len
    call    out_append
    mov     rax, [rip+nelements]
    call    out_u64
    lea     rsi, [rip+j_ntx]
    mov     rdx, j_ntx_len
    call    out_append
    mov     rax, [rip+ntexts]
    call    out_u64
    lea     rsi, [rip+j_root]
    mov     rdx, j_root_len
    call    out_append
    mov     rax, [rip+root_id]
    call    out_i64
    lea     rsi, [rip+j_body]
    mov     rdx, j_body_len
    call    out_append
    mov     rax, [rip+body_id]
    call    out_i64
    lea     rsi, [rip+j_tags]
    mov     rdx, j_tags_len
    call    out_append
    mov     rax, [rip+cnt_html]
    call    out_u64
    lea     rsi, [rip+j_tp]
    mov     rdx, j_tp_len
    call    out_append
    mov     rax, [rip+cnt_p]
    call    out_u64
    lea     rsi, [rip+j_th1]
    mov     rdx, j_th1_len
    call    out_append
    mov     rax, [rip+cnt_h1]
    call    out_u64
    lea     rsi, [rip+j_th2]
    mov     rdx, j_th2_len
    call    out_append
    mov     rax, [rip+cnt_h2]
    call    out_u64
    lea     rsi, [rip+j_th3]
    mov     rdx, j_th3_len
    call    out_append
    mov     rax, [rip+cnt_h3]
    call    out_u64
    lea     rsi, [rip+j_ta]
    mov     rdx, j_ta_len
    call    out_append
    mov     rax, [rip+cnt_a]
    call    out_u64
    lea     rsi, [rip+j_td]
    mov     rdx, j_td_len
    call    out_append
    mov     rax, [rip+cnt_div]
    call    out_u64
    lea     rsi, [rip+j_ts]
    mov     rdx, j_ts_len
    call    out_append
    mov     rax, [rip+cnt_span]
    call    out_u64
    lea     rsi, [rip+j_tu]
    mov     rdx, j_tu_len
    call    out_append
    mov     rax, [rip+cnt_ul]
    call    out_u64
    lea     rsi, [rip+j_tl]
    mov     rdx, j_tl_len
    call    out_append
    mov     rax, [rip+cnt_li]
    call    out_u64
    lea     rsi, [rip+j_ti]
    mov     rdx, j_ti_len
    call    out_append
    mov     rax, [rip+cnt_img]
    call    out_u64
    lea     rsi, [rip+j_ttable]
    mov     rdx, j_ttable_len
    call    out_append
    mov     rax, [rip+cnt_table]
    call    out_u64
    lea     rsi, [rip+j_ttr]
    mov     rdx, j_ttr_len
    call    out_append
    mov     rax, [rip+cnt_tr]
    call    out_u64
    lea     rsi, [rip+j_ttd]
    mov     rdx, j_ttd_len
    call    out_append
    mov     rax, [rip+cnt_td]
    call    out_u64
    lea     rsi, [rip+j_tth]
    mov     rdx, j_tth_len
    call    out_append
    mov     rax, [rip+cnt_th]
    call    out_u64
    lea     rsi, [rip+j_nodes]
    mov     rdx, j_nodes_len
    call    out_append

    xor     r12, r12
ew_nodes:
    cmp     r12, [rip+nnodes]
    jge     ew_done_nodes
    test    r12, r12
    jz      ew_one
    mov     al, ','
    call    out_byte
ew_one:
    mov     edi, r12d
    call    emit_node_json
    inc     r12
    jmp     ew_nodes
ew_done_nodes:
    lea     rsi, [rip+j_end]
    mov     rdx, j_end_len
    call    out_append
    # NUL terminate
    mov     rdi, [rip+out_ptr]
    mov     byte ptr [rdi], 0
    # length
    lea     rax, [rip+out_buf]
    mov     rdx, [rip+out_ptr]
    sub     rdx, rax
    lea     rdi, [rip+path_dom]
    lea     rsi, [rip+out_buf]
    call    write_bytes_path
    pop     r12
    pop     rbx
    ret

# emit_node_json: edi=id
emit_node_json:
    push    rbx
    push    r12
    mov     r12d, edi
    call    node_ptr
    mov     rbx, rax
    mov     al, '{'
    call    out_byte
    lea     rsi, [rip+em_id]
    mov     rdx, em_id_len
    call    out_append
    mov     eax, r12d
    call    out_u64
    lea     rsi, [rip+em_k]
    mov     rdx, em_k_len
    call    out_append
    cmp     byte ptr [rbx], KIND_TEXT
    je      en_text
    lea     rsi, [rip+em_e]
    mov     rdx, em_e_len
    call    out_append
    lea     rsi, [rip+em_tag]
    mov     rdx, em_tag_len
    call    out_append
    lea     rsi, [rbx+DATA_OFF]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rbx+DATA_OFF]
    call    out_append
    jmp     en_links
en_text:
    lea     rsi, [rip+em_t]
    mov     rdx, em_t_len
    call    out_append
    lea     rsi, [rip+em_text]
    mov     rdx, em_text_len
    call    out_append
    lea     rsi, [rbx+DATA_OFF]
    call    out_escape_append
en_links:
    lea     rsi, [rip+em_p]
    mov     rdx, em_p_len
    call    out_append
    movsxd  rax, dword ptr [rbx+4]
    call    out_i64
    lea     rsi, [rip+em_fc]
    mov     rdx, em_fc_len
    call    out_append
    movsxd  rax, dword ptr [rbx+8]
    call    out_i64
    lea     rsi, [rip+em_ns]
    mov     rdx, em_ns_len
    call    out_append
    movsxd  rax, dword ptr [rbx+16]
    call    out_i64
    mov     al, '}'
    call    out_byte
    pop     r12
    pop     rbx
    ret

# out helpers
out_append:
    # rsi=buf rdx=len
    push    rbx
    push    rcx
    mov     rbx, [rip+out_ptr]
    lea     rax, [rip+out_buf]
    add     rax, OUT_CAP - 8
    mov     rcx, rdx
oa_loop:
    test    rcx, rcx
    jz      oa_done
    cmp     rbx, rax
    jge     oa_done
    mov     dl, [rsi]
    mov     [rbx], dl
    inc     rsi
    inc     rbx
    dec     rcx
    jmp     oa_loop
oa_done:
    mov     [rip+out_ptr], rbx
    pop     rcx
    pop     rbx
    ret

out_byte:
    push    rbx
    mov     rbx, [rip+out_ptr]
    lea     rdx, [rip+out_buf]
    add     rdx, OUT_CAP - 2
    cmp     rbx, rdx
    jge     ob_done
    mov     [rbx], al
    inc     rbx
    mov     [rip+out_ptr], rbx
ob_done:
    pop     rbx
    ret

out_u64:
    # rax = value
    push    rbx
    push    rcx
    push    rdx
    lea     rdi, [rip+tmp_num+31]
    mov     byte ptr [rdi], 0
    mov     rbx, 10
    test    rax, rax
    jnz     ou_loop
    dec     rdi
    mov     byte ptr [rdi], '0'
    jmp     ou_emit
ou_loop:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    rax, rax
    jnz     ou_loop
ou_emit:
    mov     rsi, rdi
    call    strlen
    mov     rdx, rax
    call    out_append
    pop     rdx
    pop     rcx
    pop     rbx
    ret

out_i64:
    # rax signed
    cmp     rax, 0
    jge     out_u64
    push    rax
    mov     al, '-'
    call    out_byte
    pop     rax
    neg     rax
    jmp     out_u64

# out_escape_append: rsi=cstr — escape " \ and close quote already opened
out_escape_append:
    push    rbx
    mov     rbx, rsi
oe_loop:
    mov     al, [rbx]
    test    al, al
    jz      oe_close
    cmp     al, '"'
    je      oe_qq
    cmp     al, '\\'
    je      oe_bs
    cmp     al, 10
    je      oe_nl
    cmp     al, 13
    je      oe_cr
    call    out_byte
    inc     rbx
    jmp     oe_loop
oe_qq:
    mov     al, '\\'
    call    out_byte
    mov     al, '"'
    call    out_byte
    inc     rbx
    jmp     oe_loop
oe_bs:
    mov     al, '\\'
    call    out_byte
    mov     al, '\\'
    call    out_byte
    inc     rbx
    jmp     oe_loop
oe_nl:
    mov     al, '\\'
    call    out_byte
    mov     al, 'n'
    call    out_byte
    inc     rbx
    jmp     oe_loop
oe_cr:
    mov     al, '\\'
    call    out_byte
    mov     al, 'r'
    call    out_byte
    inc     rbx
    jmp     oe_loop
oe_close:
    # closing quote added by em_p which starts with "
    pop     rbx
    ret

# ------------------------------------------------------------
# string helpers
eng_copy_cstr:
    # rsi→rdi
ec_loop:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      ec_done
    inc     rsi
    inc     rdi
    jmp     ec_loop
ec_done:
    ret

eng_copy_cstr_n:
    # rsi→rdi max DATA_LEN-1
    push    rcx
    xor     rcx, rcx
ecn_loop:
    cmp     rcx, DATA_LEN - 1
    jge     ecn_term
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      ecn_done
    inc     rsi
    inc     rdi
    inc     rcx
    jmp     ecn_loop
ecn_term:
    mov     byte ptr [rdi], 0
ecn_done:
    pop     rcx
    ret

eng_streq:
    # rdi, rsi → rax 1/0
es_loop:
    mov     al, [rdi]
    mov     cl, [rsi]
    cmp     al, cl
    jne     es_no
    test    al, al
    jz      es_yes
    inc     rdi
    inc     rsi
    jmp     es_loop
es_yes:
    mov     rax, 1
    ret
es_no:
    xor     rax, rax
    ret

eng_startswith:
    # rdi hay, rsi needle → rax 1/0
    push    rbx
    mov     rbx, rdi
esw_loop:
    mov     al, [rsi]
    test    al, al
    jz      esw_yes
    cmp     al, [rbx]
    jne     esw_no
    inc     rsi
    inc     rbx
    jmp     esw_loop
esw_yes:
    mov     rax, 1
    pop     rbx
    ret
esw_no:
    xor     rax, rax
    pop     rbx
    ret
