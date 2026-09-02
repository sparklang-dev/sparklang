# Spark bindings + field skip + owner questions — asm helpers for spark.s
.intel_syntax noprefix
.global do_let
.global do_with
.global looks_like_field
.global set_last_from_rcx
.global bind_arrow_from_line
.global vars_get
.global vars_put
.global honest_question_exit

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern skip_ws
.extern skip_ws_from_rbx
.extern sys_exit
.extern msg_nl

# BSS symbols live in spark.s
.extern vars
.extern last_val
.extern last_val_len
.extern bind_name
.extern tmpbuf
.extern tools_active
.extern tool_reg_name
.extern tool_reg_len
.extern tools_scope

.section .data
msg_let:
    .ascii "[let] "
msg_let_len = . - msg_let
msg_with_prefix:
    .ascii "[with] "
msg_with_prefix_len = . - msg_with_prefix
msg_with_json_a:
    .ascii "{\"op\":\"with_tools\",\"tools\":\""
msg_with_json_a_len = . - msg_with_json_a
msg_with_json_b:
    .ascii "\",\"active\":true}\n"
msg_with_json_b_len = . - msg_with_json_b
msg_err_let:
    .ascii "error: let requires: let name [=] \"value\"\n"
msg_err_let_len = . - msg_err_let
msg_err_with:
    .ascii "error: with tools [name] requires a prior"
    .ascii " tool registration and a [list]\n"
msg_err_with_len = . - msg_err_with
needle_arrow:
    .ascii "->\0"
needle_tools:
    .ascii "tools\0"
msg_eq:
    .ascii " = "
msg_eq_len = . - msg_eq

.section .text

# looks_like_field: rbx=line start → rax=1 if ident:
looks_like_field:
    push    rbx
    mov     rsi, rbx
    movzx   eax, byte ptr [rsi]
    cmp     al, 'a'
    jl      llf_up
    cmp     al, 'z'
    jle     llf_scan
llf_up:
    cmp     al, 'A'
    jl      llf_no
    cmp     al, 'Z'
    jg      llf_no
llf_scan:
    inc     rsi
    movzx   eax, byte ptr [rsi]
    cmp     al, 0
    je      llf_no
    cmp     al, ':'
    je      llf_yes
    cmp     al, 'a'
    jl      llf_dig
    cmp     al, 'z'
    jle     llf_scan
llf_dig:
    cmp     al, 'A'
    jl      llf_us
    cmp     al, 'Z'
    jle     llf_scan
llf_us:
    cmp     al, '_'
    je      llf_scan
    cmp     al, '0'
    jl      llf_no
    cmp     al, '9'
    jle     llf_scan
    jmp     llf_no
llf_yes:
    mov     rax, 1
    pop     rbx
    ret
llf_no:
    xor     rax, rax
    pop     rbx
    ret

# set_last_from_rcx: rax=ptr rcx=len → copy into last_val
set_last_from_rcx:
    push    rsi
    push    rdi
    push    rcx
    mov     rsi, rax
    lea     rdi, [rip+last_val]
    cmp     rcx, 1023
    jle     sl_ok
    mov     rcx, 1023
sl_ok:
    mov     [rip+last_val_len], rcx
    rep     movsb
    mov     byte ptr [rdi], 0
    pop     rcx
    pop     rdi
    pop     rsi
    ret

# bind_arrow_from_line: if linebuf has -> name, vars_put(name, last_val)
bind_arrow_from_line:
    push    rbx
    push    r12
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_arrow]
    call    contains
    test    rax, rax
    jz      ba_done
    # find "->"
    lea     rbx, [rip+linebuf]
ba_find:
    cmp     byte ptr [rbx], 0
    je      ba_done
    cmp     word ptr [rbx], 0x3e2d       # '-' '=' little? '-'=0x2d '>'=0x3e
    je      ba_after
    inc     rbx
    jmp     ba_find
ba_after:
    add     rbx, 2
    call    skip_ws_from_rbx
    mov     rbx, rax
    # copy name into bind_name
    lea     rdi, [rip+bind_name]
    xor     rcx, rcx
ba_name:
    mov     al, [rbx+rcx]
    cmp     al, 0
    je      ba_name_done
    cmp     al, ' '
    je      ba_name_done
    cmp     al, '\t'
    je      ba_name_done
    cmp     al, '#'
    je      ba_name_done
    cmp     rcx, 62
    jge     ba_name_done
    mov     [rdi+rcx], al
    inc     rcx
    jmp     ba_name
ba_name_done:
    mov     byte ptr [rdi+rcx], 0
    cmp     rcx, 0
    je      ba_done
    lea     rdi, [rip+bind_name]
    lea     rsi, [rip+last_val]
    mov     rdx, [rip+last_val_len]
    call    vars_put
ba_done:
    pop     r12
    pop     rbx
    ret

# vars_put: rdi=name cstr, rsi=value, rdx=len
# store format: name\0value\0 … ending with \0 name
vars_put:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi            # name
    mov     r13, rsi            # value
    mov     r14, rdx            # len
    # for MVP: reset store and write single binding (last wins globally ok for demos)
    # actually append: walk to end
    lea     rbx, [rip+vars]
vp_find_end:
    cmp     byte ptr [rbx], 0
    je      vp_at_end
    # skip name
vp_skn:
    cmp     byte ptr [rbx], 0
    je      vp_after_name
    inc     rbx
    jmp     vp_skn
vp_after_name:
    inc     rbx
vp_skv:
    cmp     byte ptr [rbx], 0
    je      vp_after_val
    inc     rbx
    jmp     vp_skv
vp_after_val:
    inc     rbx
    jmp     vp_find_end
vp_at_end:
    # write name
    mov     rsi, r12
    mov     rdi, rbx
vp_cn:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     vp_cn
    # write value (rdx bytes + NUL)
    mov     rsi, r13
    mov     rcx, r14
    cmp     rcx, 500
    jle     vp_cv
    mov     rcx, 500
vp_cv:
    rep     movsb
    mov     byte ptr [rdi], 0
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# vars_get: rdi=name → rax=value ptr, rcx=len (0 if miss)
vars_get:
    push    rbx
    push    r12
    mov     r12, rdi
    lea     rbx, [rip+vars]
vg_loop:
    cmp     byte ptr [rbx], 0
    je      vg_miss
    # compare name
    mov     rsi, r12
    mov     rdi, rbx
vg_cmp:
    mov     al, [rdi]
    mov     cl, [rsi]
    cmp     al, cl
    jne     vg_next
    test    al, al
    jz      vg_hit
    inc     rdi
    inc     rsi
    jmp     vg_cmp
vg_hit:
    inc     rdi                 # value start
    mov     rax, rdi
    xor     rcx, rcx
vg_len:
    cmp     byte ptr [rdi+rcx], 0
    je      vg_done
    inc     rcx
    jmp     vg_len
vg_done:
    pop     r12
    pop     rbx
    ret
vg_next:
    # skip name
vg_sn:
    cmp     byte ptr [rbx], 0
    je      vg_an
    inc     rbx
    jmp     vg_sn
vg_an:
    inc     rbx
vg_sv:
    cmp     byte ptr [rbx], 0
    je      vg_av
    inc     rbx
    jmp     vg_sv
vg_av:
    inc     rbx
    jmp     vg_loop
vg_miss:
    xor     rax, rax
    xor     rcx, rcx
    pop     r12
    pop     rbx
    ret

do_let:
    push    rbx
    push    r12
    push    r13
    lea     rsi, [rip+msg_let]
    mov     rdx, msg_let_len
    call    write_stdout
    lea     rbx, [rip+linebuf]
    call    skip_ws
    add     rax, 3              # past "let"
    mov     rbx, rax
    call    skip_ws_from_rbx
    mov     rbx, rax
    # name
    lea     rdi, [rip+bind_name]
    xor     rcx, rcx
dl_name:
    mov     al, [rbx+rcx]
    cmp     al, 0
    je      dl_fail
    cmp     al, ' '
    je      dl_name_done
    cmp     al, '='
    je      dl_name_done
    cmp     rcx, 62
    jge     dl_name_done
    mov     [rdi+rcx], al
    inc     rcx
    jmp     dl_name
dl_name_done:
    mov     byte ptr [rdi+rcx], 0
    cmp     rcx, 0
    je      dl_fail
    add     rbx, rcx
    call    skip_ws_from_rbx
    mov     rbx, rax
    cmp     byte ptr [rbx], '='
    jne     dl_no_eq
    inc     rbx
    call    skip_ws_from_rbx
    mov     rbx, rax
dl_no_eq:
    # value must be a quote on the line
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      dl_fail
    mov     r12, rax                # value ptr
    mov     r13, rcx                # value len (rcx is caller-saved)
    # print name = value
    lea     rsi, [rip+bind_name]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+bind_name]
    call    write_stdout
    lea     rsi, [rip+msg_eq]
    mov     rdx, msg_eq_len
    call    write_stdout
    mov     rsi, r12
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rdi, [rip+bind_name]
    mov     rsi, r12
    mov     rdx, r13
    call    vars_put
    mov     rax, r12
    mov     rcx, r13
    call    set_last_from_rcx
    pop     r13
    pop     r12
    pop     rbx
    ret
dl_fail:
    lea     rsi, [rip+msg_err_let]
    mov     rdx, msg_err_let_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# do_with: with tools [name,…] { … } → activate registered tools
do_with:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_tools]
    call    contains
    test    rax, rax
    jz      dw_fail
    cmp     qword ptr [rip+tool_reg_len], 0
    je      dw_fail
    # find '[' … ']'
    lea     rbx, [rip+linebuf]
    xor     r12, r12
dw_find_lb:
    mov     al, [rbx+r12]
    cmp     al, 0
    je      dw_fail
    cmp     al, '['
    je      dw_have_lb
    inc     r12
    jmp     dw_find_lb
dw_have_lb:
    inc     r12
    lea     rsi, [rbx+r12]
    xor     rcx, rcx
dw_copy_scope:
    mov     al, [rsi+rcx]
    cmp     al, 0
    je      dw_fail
    cmp     al, ']'
    je      dw_scope_done
    cmp     rcx, 126
    jge     dw_scope_done
    lea     rdi, [rip+tools_scope]
    mov     [rdi+rcx], al
    inc     rcx
    jmp     dw_copy_scope
dw_scope_done:
    lea     rdi, [rip+tools_scope]
    mov     byte ptr [rdi+rcx], 0
    mov     r13, rcx
    # registered name must appear in scope list
    lea     rdi, [rip+tools_scope]
    lea     rsi, [rip+tool_reg_name]
    call    contains
    test    rax, rax
    jz      dw_fail
    mov     qword ptr [rip+tools_active], 1
    lea     rsi, [rip+msg_with_prefix]
    mov     rdx, msg_with_prefix_len
    call    write_stdout
    lea     rsi, [rip+msg_with_json_a]
    mov     rdx, msg_with_json_a_len
    call    write_stdout
    lea     rsi, [rip+tools_scope]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_with_json_b]
    mov     rdx, msg_with_json_b_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret
dw_fail:
    lea     rsi, [rip+msg_err_with]
    mov     rdx, msg_err_with_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# honest_question_exit: rsi=msg rdx=len → print + exit 2
honest_question_exit:
    call    write_stdout
    mov     edi, 2
    call    sys_exit
