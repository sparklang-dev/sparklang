# Spark engine B — minimal JS interpreter (phase-1).
# Real eval: numbers, strings, +, unary -, var num assign,
# console.log → buffer. Not full ES. Unknown syntax fails loud.
# Binary - / var string assign not supported.
# After HTML parse: engine_js_run_dom_scripts walks <script> text
# children (DOM data[40]) and calls engine_js_eval — tiny only.
#
# Exports:
#   engine_js_ops_dispatch  — Spark: js eval|run|console|selftest
#   engine_js_eval          — rdi=src rsi=len → rax=0 ok / 1 err
#   engine_js_run_dom_scripts — walk nodes[]; eval <script> text
#   js_result_text / js_result_len / js_console_buf / js_console_len
.intel_syntax noprefix
.global engine_js_ops_dispatch
.global engine_js_eval
.global engine_js_run_dom_scripts
.global js_result_text
.global js_result_len
.global js_console_buf
.global js_console_len

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern sys_exit
.extern nodes
.extern nnodes

.equ TOK_EOF, 0
.equ TOK_NUM, 1
.equ TOK_STR, 2
.equ TOK_IDENT, 3
.equ TOK_PLUS, 4
.equ TOK_LPAREN, 5
.equ TOK_RPAREN, 6
.equ TOK_DOT, 7
.equ TOK_COMMA, 8
.equ TOK_SEMI, 9
.equ TOK_MINUS, 10
.equ TOK_EQ, 11

.equ V_UNDEF, 0
.equ V_NUM, 1
.equ V_STR, 2

# Match engine_html.s DOM ABI (spark_dom_abi.md)
.equ NODE_SIZE, 64
.equ KIND_ELEM, 1
.equ KIND_TEXT, 2
.equ TAG_SCRIPT, 15
.equ DATA_OFF, 24

.equ JS_HEAP_CAP, 8192
.equ JS_CONSOLE_CAP, 4096
.equ JS_IDENT_CAP, 64
.equ JS_RESULT_CAP, 512
.equ JS_VAR_MAX, 16
.equ JS_VAR_NAME_CAP, 64
.equ JS_VAR_SLOT, 72              # name[64] + num qword

.section .bss
.align 16
js_src:             .space 8
js_src_end:         .space 8
js_cur:             .space 8
js_tok:             .space 8
js_tok_num:         .space 8
js_tok_str_off:     .space 8
js_tok_str_len:     .space 8
js_ident:           .space JS_IDENT_CAP
js_ident_len:       .space 8
js_decl_name:       .space JS_IDENT_CAP
js_decl_name_len:   .space 8
js_str_heap:        .space JS_HEAP_CAP
js_str_heap_used:   .space 8
js_console_buf:     .space JS_CONSOLE_CAP
js_console_len:     .space 8
js_result_kind:     .space 8
js_result_num:      .space 8
js_result_str_off:  .space 8
js_result_str_len:  .space 8
js_result_text:     .space JS_RESULT_CAP
js_result_len:      .space 8
js_err:             .space 8
js_val_kind:        .space 8
js_val_num:         .space 8
js_val_str_off:     .space 8
js_val_str_len:     .space 8
js_lhs_kind:        .space 8
js_lhs_num:         .space 8
js_lhs_str_off:     .space 8
js_lhs_str_len:     .space 8
js_nvar:            .space 8
js_vars:            .space JS_VAR_MAX * JS_VAR_SLOT
js_tmp_numbuf:      .space 32

.section .data
msg_js:     .ascii "[js] "
msg_js_len = . - msg_js
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_nl:     .ascii "\n"
msg_phase:
    .ascii "phase1 numbers/strings/+/unary- /var-num/"
    .ascii "console.log (not full ES)\n"
msg_phase_len = . - msg_phase
msg_err_syntax:
    .ascii "error: js phase-1 syntax (want number|"
    .ascii "string|+|unary-|var num|console.log)\n"
msg_err_syntax_len = . - msg_err_syntax
msg_err_quote:
    .ascii "error: js eval/run needs quoted source"
    .ascii " (use '…' inside for JS strings)\n"
msg_err_quote_len = . - msg_err_quote
msg_err_unknown:
    .ascii "error: unknown js op"
    .ascii " (want: eval|run|console|selftest)\n"
msg_err_unknown_len = . - msg_err_unknown
msg_self_ok:
    .ascii "selftest PASS 1+1=2 concat=ab unary=-1"
    .ascii " var=3 log=2\\nab\\n\n"
msg_self_ok_len = . - msg_self_ok
msg_self_fail:
    .ascii "error: js selftest FAILED\n"
msg_self_fail_len = . - msg_self_fail
msg_undef:  .ascii "undefined"
msg_undef_len = . - msg_undef

needle_eval:     .ascii "eval\0"
needle_run:      .ascii "run\0"
needle_console:  .ascii "console\0"
needle_selftest: .ascii "selftest\0"

path_out:        .ascii "out\0"
path_engine:     .ascii "out/engine\0"
path_result:     .ascii "out/engine/js_result.txt\0"
path_console:    .ascii "out/engine/js_console.txt\0"

# selftest sources (NUL-terminated; len computed)
st_add:     .ascii "1+1\0"
st_cat:     .ascii "'a'+'b'\0"
st_neg:     .ascii "-1\0"
st_var:     .ascii "var x = 1; x+2\0"
st_log:     .ascii "console.log(1+1);console.log('a'+'b')\0"

.section .text

# ------------------------------------------------------------
# engine_js_ops_dispatch — linebuf: js eval|run|console|selftest
# ------------------------------------------------------------
engine_js_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_js]
    mov     rdx, msg_js_len
    call    write_stdout

    lea     rdi, [rip+path_out]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_engine]
    mov     rsi, 493
    call    sys_mkdir

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_selftest]
    call    contains
    test    rax, rax
    jnz     js_do_selftest

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_console]
    call    contains
    test    rax, rax
    jz      js_not_console_only
    # "js console" dump — but "console" also appears in eval source
    # Prefer eval/run if those needles present.
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_eval]
    call    contains
    test    rax, rax
    jnz     js_do_eval
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     js_do_run
    jmp     js_do_console_dump
js_not_console_only:

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_eval]
    call    contains
    test    rax, rax
    jnz     js_do_eval

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     js_do_run

    lea     rsi, [rip+msg_err_unknown]
    mov     rdx, msg_err_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

js_do_eval:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      js_need_quote
    test    rcx, rcx
    jz      js_need_quote
    mov     rdi, rax
    mov     rsi, rcx
    call    engine_js_eval
    test    rax, rax
    jnz     js_eval_fail
    call    js_emit_result
    call    js_write_artifacts
    lea     rax, [rip+js_result_text]
    mov     rcx, qword ptr [rip+js_result_len]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     js_ops_done

js_do_run:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      js_need_quote
    test    rcx, rcx
    jz      js_need_quote
    mov     rdi, rax
    mov     rsi, rcx
    call    engine_js_eval
    test    rax, rax
    jnz     js_eval_fail
    # Prefer console buffer when non-empty (log scripts)
    cmp     qword ptr [rip+js_console_len], 0
    je      js_run_use_result
    call    js_emit_console
    call    js_write_artifacts
    lea     rax, [rip+js_console_buf]
    mov     rcx, qword ptr [rip+js_console_len]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     js_ops_done
js_run_use_result:
    call    js_emit_result
    call    js_write_artifacts
    lea     rax, [rip+js_result_text]
    mov     rcx, qword ptr [rip+js_result_len]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     js_ops_done

js_do_console_dump:
    call    js_emit_console
    call    js_write_artifacts
    lea     rax, [rip+js_console_buf]
    mov     rcx, qword ptr [rip+js_console_len]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     js_ops_done

js_do_selftest:
    call    engine_js_selftest
    test    rax, rax
    jnz     js_self_bad
    lea     rsi, [rip+msg_self_ok]
    mov     rdx, msg_self_ok_len
    call    write_stdout
    lea     rax, [rip+msg_self_ok]
    mov     rcx, msg_self_ok_len
    dec     rcx                      # drop trailing \n for bind
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     js_ops_done
js_self_bad:
    lea     rsi, [rip+msg_self_fail]
    mov     rdx, msg_self_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

js_need_quote:
    lea     rsi, [rip+msg_err_quote]
    mov     rdx, msg_err_quote_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

js_eval_fail:
    lea     rsi, [rip+msg_err_syntax]
    mov     rdx, msg_err_syntax_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

js_ops_done:
    lea     rsi, [rip+msg_phase]
    mov     rdx, msg_phase_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# engine_js_run_dom_scripts → rax=0 ok / 1 err
# Walk nodes[0..nnodes): KIND_ELEM+TAG_SCRIPT → text children
# (data[40] copy from parse). Empty/no scripts → 0.
# Fail loud on phase-1 syntax. Artifacts if any script ran.
# ------------------------------------------------------------
engine_js_run_dom_scripts:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    xor     r15, r15                 # scripts evaluated
    xor     r12, r12                 # node index
ejrds_loop:
    cmp     r12, qword ptr [rip+nnodes]
    jge     ejrds_finish
    mov     rax, r12
    imul    rax, NODE_SIZE
    lea     rdx, [rip+nodes]
    add     rax, rdx
    cmp     byte ptr [rax], KIND_ELEM
    jne     ejrds_next
    cmp     byte ptr [rax+1], TAG_SCRIPT
    jne     ejrds_next
    movsxd  r13, dword ptr [rax+8]   # first_child
ejrds_child:
    cmp     r13d, -1
    je      ejrds_next
    mov     rax, r13
    imul    rax, NODE_SIZE
    lea     rdx, [rip+nodes]
    add     rax, rdx
    cmp     byte ptr [rax], KIND_TEXT
    jne     ejrds_sib
    lea     r14, [rax+DATA_OFF]
    mov     rsi, r14                 # spark strlen: rsi=cstr
    call    strlen
    test    rax, rax
    jz      ejrds_sib
    mov     rdi, r14
    mov     rsi, rax
    call    engine_js_eval
    test    rax, rax
    jnz     ejrds_fail
    inc     r15
ejrds_sib:
    mov     rax, r13
    imul    rax, NODE_SIZE
    lea     rdx, [rip+nodes]
    add     rax, rdx
    movsxd  r13, dword ptr [rax+16]  # next_sibling
    jmp     ejrds_child
ejrds_next:
    inc     r12
    jmp     ejrds_loop
ejrds_finish:
    test    r15, r15
    jz      ejrds_ok
    call    js_write_artifacts
ejrds_ok:
    xor     rax, rax
    jmp     ejrds_done
ejrds_fail:
    mov     rax, 1
ejrds_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# engine_js_eval: rdi=src rsi=len → rax=0 ok, 1 error
# ------------------------------------------------------------
engine_js_eval:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     qword ptr [rip+js_err], 0
    mov     qword ptr [rip+js_str_heap_used], 0
    mov     qword ptr [rip+js_console_len], 0
    mov     qword ptr [rip+js_nvar], 0
    mov     qword ptr [rip+js_result_kind], V_UNDEF
    mov     qword ptr [rip+js_result_num], 0
    mov     qword ptr [rip+js_result_str_off], 0
    mov     qword ptr [rip+js_result_str_len], 0
    mov     qword ptr [rip+js_result_len], 0

    mov     qword ptr [rip+js_src], rdi
    mov     qword ptr [rip+js_cur], rdi
    add     rdi, rsi
    mov     qword ptr [rip+js_src_end], rdi

    call    js_lex
    call    js_parse_program
    cmp     qword ptr [rip+js_err], 0
    jne     eje_fail
    cmp     dword ptr [rip+js_tok], TOK_EOF
    jne     eje_fail
    call    js_format_result
    xor     rax, rax
    jmp     eje_done
eje_fail:
    mov     rax, 1
eje_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# engine_js_selftest → rax=0 pass / 1 fail
# ------------------------------------------------------------
engine_js_selftest:
    push    rbx
    # 1+1 → 2
    lea     rdi, [rip+st_add]
    mov     rsi, 3
    call    engine_js_eval
    test    rax, rax
    jnz     ejst_fail
    cmp     qword ptr [rip+js_result_kind], V_NUM
    jne     ejst_fail
    cmp     qword ptr [rip+js_result_num], 2
    jne     ejst_fail
    # 'a'+'b' → ab
    lea     rdi, [rip+st_cat]
    mov     rsi, 7
    call    engine_js_eval
    test    rax, rax
    jnz     ejst_fail
    cmp     qword ptr [rip+js_result_kind], V_STR
    jne     ejst_fail
    cmp     qword ptr [rip+js_result_str_len], 2
    jne     ejst_fail
    lea     rsi, [rip+js_str_heap]
    add     rsi, qword ptr [rip+js_result_str_off]
    cmp     byte ptr [rsi], 'a'
    jne     ejst_fail
    cmp     byte ptr [rsi+1], 'b'
    jne     ejst_fail
    # -1 → -1 (unary minus)
    lea     rdi, [rip+st_neg]
    mov     rsi, 2
    call    engine_js_eval
    test    rax, rax
    jnz     ejst_fail
    cmp     qword ptr [rip+js_result_kind], V_NUM
    jne     ejst_fail
    cmp     qword ptr [rip+js_result_num], -1
    jne     ejst_fail
    # var x = 1; x+2 → 3
    lea     rdi, [rip+st_var]
    mov     rsi, 14
    call    engine_js_eval
    test    rax, rax
    jnz     ejst_fail
    cmp     qword ptr [rip+js_result_kind], V_NUM
    jne     ejst_fail
    cmp     qword ptr [rip+js_result_num], 3
    jne     ejst_fail
    # console.log
    lea     rdi, [rip+st_log]
    mov     rsi, 37
    call    engine_js_eval
    test    rax, rax
    jnz     ejst_fail
    # expect "2\nab\n"
    cmp     qword ptr [rip+js_console_len], 5
    jne     ejst_fail
    lea     rsi, [rip+js_console_buf]
    cmp     byte ptr [rsi], '2'
    jne     ejst_fail
    cmp     byte ptr [rsi+1], 10
    jne     ejst_fail
    cmp     byte ptr [rsi+2], 'a'
    jne     ejst_fail
    cmp     byte ptr [rsi+3], 'b'
    jne     ejst_fail
    cmp     byte ptr [rsi+4], 10
    jne     ejst_fail
    xor     rax, rax
    pop     rbx
    ret
ejst_fail:
    mov     rax, 1
    pop     rbx
    ret

# ------------------------------------------------------------
# Lexer
# ------------------------------------------------------------
js_lex:
    push    rbx
    push    r12
jl_restart:
    mov     rbx, qword ptr [rip+js_cur]
    mov     r12, qword ptr [rip+js_src_end]
jl_ws:
    cmp     rbx, r12
    jge     jl_eof
    movzx   eax, byte ptr [rbx]
    cmp     al, ' '
    je      jl_skip1
    cmp     al, 9
    je      jl_skip1
    cmp     al, 10
    je      jl_skip1
    cmp     al, 13
    je      jl_skip1
    # // line comment
    cmp     al, '/'
    jne     jl_tok
    cmp     rbx, r12
    jge     jl_tok
    cmp     byte ptr [rbx+1], '/'
    jne     jl_tok
    add     rbx, 2
jl_comment:
    cmp     rbx, r12
    jge     jl_eof
    cmp     byte ptr [rbx], 10
    je      jl_ws
    inc     rbx
    jmp     jl_comment
jl_skip1:
    inc     rbx
    jmp     jl_ws
jl_eof:
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_EOF
    pop     r12
    pop     rbx
    ret
jl_tok:
    mov     qword ptr [rip+js_cur], rbx
    movzx   eax, byte ptr [rbx]
    cmp     al, '+'
    jne     jl_not_plus
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_PLUS
    pop     r12
    pop     rbx
    ret
jl_not_plus:
    cmp     al, '-'
    jne     jl_not_minus
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_MINUS
    pop     r12
    pop     rbx
    ret
jl_not_minus:
    cmp     al, '('
    jne     jl_not_lp
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_LPAREN
    pop     r12
    pop     rbx
    ret
jl_not_lp:
    cmp     al, ')'
    jne     jl_not_rp
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_RPAREN
    pop     r12
    pop     rbx
    ret
jl_not_rp:
    cmp     al, '.'
    jne     jl_not_dot
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_DOT
    pop     r12
    pop     rbx
    ret
jl_not_dot:
    cmp     al, ','
    jne     jl_not_comma
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_COMMA
    pop     r12
    pop     rbx
    ret
jl_not_comma:
    cmp     al, ';'
    jne     jl_not_semi
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_SEMI
    pop     r12
    pop     rbx
    ret
jl_not_semi:
    cmp     al, '='
    jne     jl_not_eq
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_EQ
    pop     r12
    pop     rbx
    ret
jl_not_eq:
    # number
    cmp     al, '0'
    jl      jl_not_num
    cmp     al, '9'
    jg      jl_not_num
    xor     r8, r8
jl_num_loop:
    cmp     rbx, r12
    jge     jl_num_done
    movzx   eax, byte ptr [rbx]
    cmp     al, '0'
    jl      jl_num_done
    cmp     al, '9'
    jg      jl_num_done
    imul    r8, r8, 10
    sub     al, '0'
    movzx   eax, al
    add     r8, rax
    inc     rbx
    jmp     jl_num_loop
jl_num_done:
    mov     qword ptr [rip+js_cur], rbx
    mov     qword ptr [rip+js_tok_num], r8
    mov     dword ptr [rip+js_tok], TOK_NUM
    pop     r12
    pop     rbx
    ret
jl_not_num:
    # string '…' or "…"
    cmp     al, 39                   # '
    je      jl_str
    cmp     al, '"'
    jne     jl_not_str
jl_str:
    mov     r9b, al                  # quote char
    inc     rbx
    mov     r10, qword ptr [rip+js_str_heap_used]
    mov     r11, r10                 # start offset
jl_str_loop:
    cmp     rbx, r12
    jge     jl_lex_err
    movzx   eax, byte ptr [rbx]
    cmp     al, r9b
    je      jl_str_end
    cmp     al, 92                   # '\\'
    jne     jl_str_put
    inc     rbx
    cmp     rbx, r12
    jge     jl_lex_err
    movzx   eax, byte ptr [rbx]
jl_str_put:
    cmp     r10, JS_HEAP_CAP-1
    jge     jl_lex_err
    lea     rdi, [rip+js_str_heap]
    mov     [rdi+r10], al
    inc     r10
    inc     rbx
    jmp     jl_str_loop
jl_str_end:
    inc     rbx
    mov     qword ptr [rip+js_cur], rbx
    mov     qword ptr [rip+js_str_heap_used], r10
    mov     qword ptr [rip+js_tok_str_off], r11
    mov     rax, r10
    sub     rax, r11
    mov     qword ptr [rip+js_tok_str_len], rax
    mov     dword ptr [rip+js_tok], TOK_STR
    pop     r12
    pop     rbx
    ret
jl_not_str:
    # identifier
    movzx   eax, byte ptr [rbx]
    call    js_is_ident_start
    test    rax, rax
    jz      jl_lex_err
    xor     r8, r8
jl_ident_loop:
    cmp     rbx, r12
    jge     jl_ident_done
    movzx   eax, byte ptr [rbx]
    mov     r9d, eax                 # save char (call clobbers al)
    call    js_is_ident_cont_al
    test    rax, rax
    jz      jl_ident_done
    cmp     r8, JS_IDENT_CAP-1
    jge     jl_lex_err
    lea     rdi, [rip+js_ident]
    mov     eax, r9d
    mov     [rdi+r8], al
    inc     r8
    inc     rbx
    jmp     jl_ident_loop
jl_ident_done:
    lea     rdi, [rip+js_ident]
    mov     byte ptr [rdi+r8], 0
    mov     qword ptr [rip+js_ident_len], r8
    mov     qword ptr [rip+js_cur], rbx
    mov     dword ptr [rip+js_tok], TOK_IDENT
    pop     r12
    pop     rbx
    ret
jl_lex_err:
    mov     qword ptr [rip+js_err], 1
    mov     dword ptr [rip+js_tok], TOK_EOF
    pop     r12
    pop     rbx
    ret

# al = char → rax 1 if ident start
js_is_ident_start:
    cmp     al, '_'
    je      jis_yes
    cmp     al, 'A'
    jl      jis_no
    cmp     al, 'Z'
    jle     jis_yes
    cmp     al, 'a'
    jl      jis_no
    cmp     al, 'z'
    jle     jis_yes
jis_no:
    xor     rax, rax
    ret
jis_yes:
    mov     rax, 1
    ret

# al = char → rax 1 if ident continue
js_is_ident_cont_al:
    cmp     al, '_'
    je      jic_yes
    cmp     al, '0'
    jl      jic_letter
    cmp     al, '9'
    jle     jic_yes
jic_letter:
    cmp     al, 'A'
    jl      jic_no
    cmp     al, 'Z'
    jle     jic_yes
    cmp     al, 'a'
    jl      jic_no
    cmp     al, 'z'
    jle     jic_yes
jic_no:
    xor     rax, rax
    ret
jic_yes:
    mov     rax, 1
    ret

# ------------------------------------------------------------
# Parser
# ------------------------------------------------------------
js_parse_program:
    push    rbx
jpp_loop:
    cmp     qword ptr [rip+js_err], 0
    jne     jpp_done
    cmp     dword ptr [rip+js_tok], TOK_EOF
    je      jpp_done
    call    js_parse_stmt
    cmp     qword ptr [rip+js_err], 0
    jne     jpp_done
    cmp     dword ptr [rip+js_tok], TOK_SEMI
    jne     jpp_loop
    call    js_lex
    jmp     jpp_loop
jpp_done:
    pop     rbx
    ret

js_parse_stmt:
    push    rbx
    # var name = number-expr  (numbers only; not full ES)
    cmp     dword ptr [rip+js_tok], TOK_IDENT
    jne     jps_expr
    cmp     qword ptr [rip+js_ident_len], 3
    jne     jps_not_var
    lea     rsi, [rip+js_ident]
    cmp     byte ptr [rsi], 'v'
    jne     jps_not_var
    cmp     byte ptr [rsi+1], 'a'
    jne     jps_not_var
    cmp     byte ptr [rsi+2], 'r'
    jne     jps_not_var
    call    js_lex
    cmp     dword ptr [rip+js_tok], TOK_IDENT
    jne     jps_err
    # save decl name (lex overwrites js_ident)
    mov     rcx, qword ptr [rip+js_ident_len]
    mov     qword ptr [rip+js_decl_name_len], rcx
    lea     rsi, [rip+js_ident]
    lea     rdi, [rip+js_decl_name]
    xor     r8, r8
jps_var_copy:
    cmp     r8, rcx
    jge     jps_var_copy_done
    mov     al, [rsi+r8]
    mov     [rdi+r8], al
    inc     r8
    jmp     jps_var_copy
jps_var_copy_done:
    mov     byte ptr [rdi+rcx], 0
    call    js_lex
    cmp     dword ptr [rip+js_tok], TOK_EQ
    jne     jps_err
    call    js_lex
    call    js_parse_expr
    cmp     qword ptr [rip+js_err], 0
    jne     jps_done
    cmp     qword ptr [rip+js_val_kind], V_NUM
    jne     jps_err
    call    js_var_put
    cmp     qword ptr [rip+js_err], 0
    jne     jps_done
    # completion value = assigned number
    mov     qword ptr [rip+js_result_kind], V_NUM
    mov     rax, qword ptr [rip+js_val_num]
    mov     qword ptr [rip+js_result_num], rax
    jmp     jps_done
jps_not_var:
    # console.log(…)
    cmp     dword ptr [rip+js_tok], TOK_IDENT
    jne     jps_expr
    # match "console"
    cmp     qword ptr [rip+js_ident_len], 7
    jne     jps_expr
    lea     rsi, [rip+js_ident]
    cmp     byte ptr [rsi], 'c'
    jne     jps_expr
    cmp     byte ptr [rsi+1], 'o'
    jne     jps_expr
    cmp     byte ptr [rsi+2], 'n'
    jne     jps_expr
    cmp     byte ptr [rsi+3], 's'
    jne     jps_expr
    cmp     byte ptr [rsi+4], 'o'
    jne     jps_expr
    cmp     byte ptr [rsi+5], 'l'
    jne     jps_expr
    cmp     byte ptr [rsi+6], 'e'
    jne     jps_expr
    call    js_lex
    cmp     dword ptr [rip+js_tok], TOK_DOT
    jne     jps_err
    call    js_lex
    cmp     dword ptr [rip+js_tok], TOK_IDENT
    jne     jps_err
    cmp     qword ptr [rip+js_ident_len], 3
    jne     jps_err
    lea     rsi, [rip+js_ident]
    cmp     byte ptr [rsi], 'l'
    jne     jps_err
    cmp     byte ptr [rsi+1], 'o'
    jne     jps_err
    cmp     byte ptr [rsi+2], 'g'
    jne     jps_err
    call    js_lex
    cmp     dword ptr [rip+js_tok], TOK_LPAREN
    jne     jps_err
    call    js_lex
    # args: empty or expr (, expr)*
    cmp     dword ptr [rip+js_tok], TOK_RPAREN
    je      jps_log_close
jps_log_arg:
    call    js_parse_expr
    cmp     qword ptr [rip+js_err], 0
    jne     jps_done
    call    js_console_append_val
    cmp     dword ptr [rip+js_tok], TOK_COMMA
    jne     jps_log_close_check
    call    js_lex
    # space between multi-args
    mov     al, ' '
    call    js_console_putc
    jmp     jps_log_arg
jps_log_close_check:
    cmp     dword ptr [rip+js_tok], TOK_RPAREN
    jne     jps_err
jps_log_close:
    call    js_lex
    mov     al, 10
    call    js_console_putc
    # result stays last expr / undef
    jmp     jps_done
jps_expr:
    call    js_parse_expr
    cmp     qword ptr [rip+js_err], 0
    jne     jps_done
    # store as result
    mov     rax, qword ptr [rip+js_val_kind]
    mov     qword ptr [rip+js_result_kind], rax
    mov     rax, qword ptr [rip+js_val_num]
    mov     qword ptr [rip+js_result_num], rax
    mov     rax, qword ptr [rip+js_val_str_off]
    mov     qword ptr [rip+js_result_str_off], rax
    mov     rax, qword ptr [rip+js_val_str_len]
    mov     qword ptr [rip+js_result_str_len], rax
    jmp     jps_done
jps_err:
    mov     qword ptr [rip+js_err], 1
jps_done:
    pop     rbx
    ret

js_parse_expr:
    push    rbx
    call    js_parse_primary
    cmp     qword ptr [rip+js_err], 0
    jne     jpe_done
jpe_plus:
    cmp     dword ptr [rip+js_tok], TOK_PLUS
    jne     jpe_check_bin_minus
    # save LHS
    mov     rax, qword ptr [rip+js_val_kind]
    mov     qword ptr [rip+js_lhs_kind], rax
    mov     rax, qword ptr [rip+js_val_num]
    mov     qword ptr [rip+js_lhs_num], rax
    mov     rax, qword ptr [rip+js_val_str_off]
    mov     qword ptr [rip+js_lhs_str_off], rax
    mov     rax, qword ptr [rip+js_val_str_len]
    mov     qword ptr [rip+js_lhs_str_len], rax
    call    js_lex
    call    js_parse_primary
    cmp     qword ptr [rip+js_err], 0
    jne     jpe_done
    call    js_binop_plus
    jmp     jpe_plus
jpe_check_bin_minus:
    # Binary - is not phase-1; do not treat as next stmt.
    cmp     dword ptr [rip+js_tok], TOK_MINUS
    jne     jpe_done
    mov     qword ptr [rip+js_err], 1
jpe_done:
    pop     rbx
    ret

js_parse_primary:
    push    rbx
    # unary minus: - primary  (numbers only; not full ES)
    cmp     dword ptr [rip+js_tok], TOK_MINUS
    jne     jppri_num
    call    js_lex
    call    js_parse_primary
    cmp     qword ptr [rip+js_err], 0
    jne     jppri_done
    cmp     qword ptr [rip+js_val_kind], V_NUM
    jne     jppri_err
    neg     qword ptr [rip+js_val_num]
    jmp     jppri_done
jppri_num:
    cmp     dword ptr [rip+js_tok], TOK_NUM
    jne     jppri_str
    mov     qword ptr [rip+js_val_kind], V_NUM
    mov     rax, qword ptr [rip+js_tok_num]
    mov     qword ptr [rip+js_val_num], rax
    call    js_lex
    jmp     jppri_done
jppri_str:
    cmp     dword ptr [rip+js_tok], TOK_STR
    jne     jppri_paren
    mov     qword ptr [rip+js_val_kind], V_STR
    mov     rax, qword ptr [rip+js_tok_str_off]
    mov     qword ptr [rip+js_val_str_off], rax
    mov     rax, qword ptr [rip+js_tok_str_len]
    mov     qword ptr [rip+js_val_str_len], rax
    call    js_lex
    jmp     jppri_done
jppri_paren:
    cmp     dword ptr [rip+js_tok], TOK_LPAREN
    jne     jppri_ident
    call    js_lex
    call    js_parse_expr
    cmp     qword ptr [rip+js_err], 0
    jne     jppri_done
    cmp     dword ptr [rip+js_tok], TOK_RPAREN
    jne     jppri_err
    call    js_lex
    jmp     jppri_done
jppri_ident:
    # bare ident → number var lookup only
    cmp     dword ptr [rip+js_tok], TOK_IDENT
    jne     jppri_err
    call    js_var_get
    test    rax, rax
    jz      jppri_err
    call    js_lex
    jmp     jppri_done
jppri_err:
    mov     qword ptr [rip+js_err], 1
jppri_done:
    pop     rbx
    ret

# ------------------------------------------------------------
# js_var_put: js_decl_name + js_val_num → slot (num only)
# ------------------------------------------------------------
js_var_put:
    push    rbx
    push    r12
    push    r13
    lea     r12, [rip+js_decl_name]
    mov     r13, qword ptr [rip+js_decl_name_len]
    xor     rbx, rbx
jvp_find:
    cmp     rbx, qword ptr [rip+js_nvar]
    jge     jvp_insert
    mov     rax, rbx
    imul    rax, JS_VAR_SLOT
    lea     rdi, [rip+js_vars]
    add     rdi, rax
    # compare names
    xor     rcx, rcx
jvp_cmp:
    cmp     rcx, r13
    jge     jvp_cmp_tail
    mov     al, [rdi+rcx]
    cmp     al, [r12+rcx]
    jne     jvp_next
    inc     rcx
    jmp     jvp_cmp
jvp_cmp_tail:
    cmp     byte ptr [rdi+rcx], 0
    jne     jvp_next
    # update existing
    mov     rax, qword ptr [rip+js_val_num]
    mov     [rdi+JS_VAR_NAME_CAP], rax
    jmp     jvp_ok
jvp_next:
    inc     rbx
    jmp     jvp_find
jvp_insert:
    cmp     qword ptr [rip+js_nvar], JS_VAR_MAX
    jge     jvp_err
    mov     rax, qword ptr [rip+js_nvar]
    imul    rax, JS_VAR_SLOT
    lea     rdi, [rip+js_vars]
    add     rdi, rax
    xor     rcx, rcx
jvp_copy:
    cmp     rcx, r13
    jge     jvp_copy_done
    mov     al, [r12+rcx]
    mov     [rdi+rcx], al
    inc     rcx
    jmp     jvp_copy
jvp_copy_done:
    mov     byte ptr [rdi+rcx], 0
    mov     rax, qword ptr [rip+js_val_num]
    mov     [rdi+JS_VAR_NAME_CAP], rax
    inc     qword ptr [rip+js_nvar]
    jmp     jvp_ok
jvp_err:
    mov     qword ptr [rip+js_err], 1
jvp_ok:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# js_var_get: js_ident → rax=1 + js_val_num / rax=0 miss
# ------------------------------------------------------------
js_var_get:
    push    rbx
    push    r12
    push    r13
    lea     r12, [rip+js_ident]
    mov     r13, qword ptr [rip+js_ident_len]
    xor     rbx, rbx
jvg_loop:
    cmp     rbx, qword ptr [rip+js_nvar]
    jge     jvg_miss
    mov     rax, rbx
    imul    rax, JS_VAR_SLOT
    lea     rdi, [rip+js_vars]
    add     rdi, rax
    xor     rcx, rcx
jvg_cmp:
    cmp     rcx, r13
    jge     jvg_cmp_tail
    mov     al, [rdi+rcx]
    cmp     al, [r12+rcx]
    jne     jvg_next
    inc     rcx
    jmp     jvg_cmp
jvg_cmp_tail:
    cmp     byte ptr [rdi+rcx], 0
    jne     jvg_next
    mov     rax, [rdi+JS_VAR_NAME_CAP]
    mov     qword ptr [rip+js_val_kind], V_NUM
    mov     qword ptr [rip+js_val_num], rax
    mov     rax, 1
    jmp     jvg_done
jvg_next:
    inc     rbx
    jmp     jvg_loop
jvg_miss:
    xor     rax, rax
jvg_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# + : num+num | str+str | coerce mix → string
# LHS in js_lhs_*, RHS in js_val_* → result in js_val_*
# ------------------------------------------------------------
js_binop_plus:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, qword ptr [rip+js_lhs_kind]
    mov     rbx, qword ptr [rip+js_val_kind]
    cmp     rax, V_NUM
    jne     jbp_not_nn
    cmp     rbx, V_NUM
    jne     jbp_not_nn
    mov     rax, qword ptr [rip+js_lhs_num]
    add     rax, qword ptr [rip+js_val_num]
    mov     qword ptr [rip+js_val_kind], V_NUM
    mov     qword ptr [rip+js_val_num], rax
    jmp     jbp_done
jbp_not_nn:
    # ensure both as strings in heap, then concat
    # materialize LHS string → r12=off r13=len
    cmp     qword ptr [rip+js_lhs_kind], V_STR
    je      jbp_lhs_str
    # number → string
    mov     rdi, qword ptr [rip+js_lhs_num]
    call    js_num_to_heap_str   # rax=off rdx=len
    mov     r12, rax
    mov     r13, rdx
    jmp     jbp_rhs
jbp_lhs_str:
    mov     r12, qword ptr [rip+js_lhs_str_off]
    mov     r13, qword ptr [rip+js_lhs_str_len]
jbp_rhs:
    cmp     qword ptr [rip+js_val_kind], V_STR
    je      jbp_rhs_str
    mov     rdi, qword ptr [rip+js_val_num]
    call    js_num_to_heap_str
    mov     r14, rax
    mov     r15, rdx
    jmp     jbp_concat
jbp_rhs_str:
    mov     r14, qword ptr [rip+js_val_str_off]
    mov     r15, qword ptr [rip+js_val_str_len]
jbp_concat:
    # new string at heap_used
    mov     r8, qword ptr [rip+js_str_heap_used]
    mov     r9, r13
    add     r9, r15
    mov     rax, r8
    add     rax, r9
    cmp     rax, JS_HEAP_CAP
    jge     jbp_err
    lea     rdi, [rip+js_str_heap]
    # copy LHS
    xor     rcx, rcx
jbp_c1:
    cmp     rcx, r13
    jge     jbp_c2
    mov     al, [rdi+r12]
    mov     [rdi+r8], al
    inc     r12
    inc     r8
    inc     rcx
    jmp     jbp_c1
jbp_c2:
    xor     rcx, rcx
jbp_c2l:
    cmp     rcx, r15
    jge     jbp_c3
    mov     al, [rdi+r14]
    mov     [rdi+r8], al
    inc     r14
    inc     r8
    inc     rcx
    jmp     jbp_c2l
jbp_c3:
    mov     rax, qword ptr [rip+js_str_heap_used]
    mov     qword ptr [rip+js_val_str_off], rax
    mov     qword ptr [rip+js_val_str_len], r9
    mov     qword ptr [rip+js_str_heap_used], r8
    mov     qword ptr [rip+js_val_kind], V_STR
    jmp     jbp_done
jbp_err:
    mov     qword ptr [rip+js_err], 1
jbp_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# rdi=number → rax=heap off, rdx=len (writes into heap)
js_num_to_heap_str:
    push    rbx
    push    r12
    mov     rax, rdi
    lea     rdi, [rip+js_tmp_numbuf+31]
    mov     byte ptr [rdi], 0
    mov     r12, 0                   # length
    mov     rbx, rax
    test    rbx, rbx
    jns     jnth_pos
    neg     rbx
    mov     r8, 1                    # negative flag
    jmp     jnth_dig
jnth_pos:
    xor     r8, r8
jnth_dig:
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     rbx, rax
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    inc     r12
    test    rbx, rbx
    jnz     jnth_dig
    test    r8, r8
    jz      jnth_copy
    dec     rdi
    mov     byte ptr [rdi], '-'
    inc     r12
jnth_copy:
    # rdi → digits, r12=len; append to heap
    mov     r9, qword ptr [rip+js_str_heap_used]
    mov     rax, r9
    add     rax, r12
    cmp     rax, JS_HEAP_CAP
    jge     jnth_err
    lea     rsi, [rip+js_str_heap]
    xor     rcx, rcx
jnth_cl:
    cmp     rcx, r12
    jge     jnth_ok
    mov     al, [rdi+rcx]
    mov     [rsi+r9], al
    inc     r9
    inc     rcx
    jmp     jnth_cl
jnth_ok:
    mov     rax, qword ptr [rip+js_str_heap_used]
    mov     rdx, r12
    mov     qword ptr [rip+js_str_heap_used], r9
    pop     r12
    pop     rbx
    ret
jnth_err:
    mov     qword ptr [rip+js_err], 1
    xor     rax, rax
    xor     rdx, rdx
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# console helpers — append current js_val_* then optional chars
# ------------------------------------------------------------
js_console_append_val:
    push    rbx
    cmp     qword ptr [rip+js_val_kind], V_NUM
    jne     jcav_str
    mov     rdi, qword ptr [rip+js_val_num]
    call    js_num_to_heap_str       # also on heap; copy to console
    # re-read from heap
    lea     rsi, [rip+js_str_heap]
    add     rsi, rax
    mov     rcx, rdx
    call    js_console_write
    jmp     jcav_done
jcav_str:
    cmp     qword ptr [rip+js_val_kind], V_STR
    jne     jcav_undef
    lea     rsi, [rip+js_str_heap]
    add     rsi, qword ptr [rip+js_val_str_off]
    mov     rcx, qword ptr [rip+js_val_str_len]
    call    js_console_write
    jmp     jcav_done
jcav_undef:
    lea     rsi, [rip+msg_undef]
    mov     rcx, msg_undef_len
    call    js_console_write
jcav_done:
    pop     rbx
    ret

# al = char
js_console_putc:
    push    rbx
    mov     rbx, qword ptr [rip+js_console_len]
    cmp     rbx, JS_CONSOLE_CAP-1
    jge     jcp_done
    lea     rdi, [rip+js_console_buf]
    mov     [rdi+rbx], al
    inc     rbx
    mov     qword ptr [rip+js_console_len], rbx
jcp_done:
    pop     rbx
    ret

# rsi=ptr rcx=len
js_console_write:
    push    rbx
    push    r12
    mov     r12, rsi
    mov     rbx, qword ptr [rip+js_console_len]
jcw_loop:
    test    rcx, rcx
    jz      jcw_done
    cmp     rbx, JS_CONSOLE_CAP-1
    jge     jcw_done
    mov     al, [r12]
    lea     rdi, [rip+js_console_buf]
    mov     [rdi+rbx], al
    inc     rbx
    inc     r12
    dec     rcx
    jmp     jcw_loop
jcw_done:
    mov     qword ptr [rip+js_console_len], rbx
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# Format result → js_result_text / js_result_len
# ------------------------------------------------------------
js_format_result:
    push    rbx
    cmp     qword ptr [rip+js_result_kind], V_NUM
    jne     jfr_str
    mov     rdi, qword ptr [rip+js_result_num]
    call    js_itoa_to_result
    jmp     jfr_done
jfr_str:
    cmp     qword ptr [rip+js_result_kind], V_STR
    jne     jfr_undef
    lea     rsi, [rip+js_str_heap]
    add     rsi, qword ptr [rip+js_result_str_off]
    mov     rcx, qword ptr [rip+js_result_str_len]
    cmp     rcx, JS_RESULT_CAP-1
    jle     jfr_sc
    mov     rcx, JS_RESULT_CAP-1
jfr_sc:
    lea     rdi, [rip+js_result_text]
    xor     r8, r8
jfr_scl:
    cmp     r8, rcx
    jge     jfr_scd
    mov     al, [rsi+r8]
    mov     [rdi+r8], al
    inc     r8
    jmp     jfr_scl
jfr_scd:
    mov     byte ptr [rdi+r8], 0
    mov     qword ptr [rip+js_result_len], r8
    jmp     jfr_done
jfr_undef:
    lea     rsi, [rip+msg_undef]
    mov     rcx, msg_undef_len
    lea     rdi, [rip+js_result_text]
    xor     r8, r8
jfr_ul:
    cmp     r8, rcx
    jge     jfr_ud
    mov     al, [rsi+r8]
    mov     [rdi+r8], al
    inc     r8
    jmp     jfr_ul
jfr_ud:
    mov     byte ptr [rdi+r8], 0
    mov     qword ptr [rip+js_result_len], r8
jfr_done:
    pop     rbx
    ret

# rdi=number → js_result_text
js_itoa_to_result:
    push    rbx
    push    r12
    mov     rax, rdi
    lea     rdi, [rip+js_tmp_numbuf+31]
    mov     byte ptr [rdi], 0
    xor     r12, r12
    mov     rbx, rax
    test    rbx, rbx
    jns     jitr_pos
    neg     rbx
    mov     r8, 1
    jmp     jitr_dig
jitr_pos:
    xor     r8, r8
jitr_dig:
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    mov     rbx, rax
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    inc     r12
    test    rbx, rbx
    jnz     jitr_dig
    test    r8, r8
    jz      jitr_copy
    dec     rdi
    mov     byte ptr [rdi], '-'
    inc     r12
jitr_copy:
    lea     rsi, [rip+js_result_text]
    xor     rcx, rcx
jitr_cl:
    cmp     rcx, r12
    jge     jitr_done
    mov     al, [rdi+rcx]
    mov     [rsi+rcx], al
    inc     rcx
    jmp     jitr_cl
jitr_done:
    mov     byte ptr [rsi+rcx], 0
    mov     qword ptr [rip+js_result_len], r12
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# Emit / artifacts
# ------------------------------------------------------------
js_emit_result:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+js_result_text]
    mov     rdx, qword ptr [rip+js_result_len]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    ret

js_emit_console:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+js_console_buf]
    mov     rdx, qword ptr [rip+js_console_len]
    test    rdx, rdx
    jz      jec_empty
    call    write_stdout
    # ensure trailing nl visible if console lacks one
    jmp     jec_done
jec_empty:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
jec_done:
    # if console didn't end with nl, print one
    cmp     qword ptr [rip+js_console_len], 0
    je      jec_ret
    lea     rsi, [rip+js_console_buf]
    add     rsi, qword ptr [rip+js_console_len]
    dec     rsi
    cmp     byte ptr [rsi], 10
    je      jec_ret
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
jec_ret:
    ret

js_write_artifacts:
    push    rbx
    # NUL-terminate console for file write helpers that use strlen
    mov     rbx, qword ptr [rip+js_console_len]
    lea     rdi, [rip+js_console_buf]
    mov     byte ptr [rdi+rbx], 0
    lea     rdi, [rip+js_result_text]
    mov     rbx, qword ptr [rip+js_result_len]
    mov     byte ptr [rdi+rbx], 0

    lea     rdi, [rip+path_result]
    lea     rsi, [rip+js_result_text]
    mov     rdx, qword ptr [rip+js_result_len]
    call    write_bytes_path

    lea     rdi, [rip+path_console]
    lea     rsi, [rip+js_console_buf]
    mov     rdx, qword ptr [rip+js_console_len]
    call    write_bytes_path
    pop     rbx
    ret
