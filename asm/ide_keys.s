# Spark IDE — keymap / command loop (asm syscalls).
# Owns: quit, save, run, open, show from a command script file.
# Dry-run: command-trace JSON only (no save write / no run fork);
#   open still reads + paints editor.ppm; show dry-validates via
#   engine_window_show (live forks ./spark-engine-show).
# Live: real open/read/paint, write, fork_exec ./spark, quit ends loop.
# Buffer: shared core `ide_buf` / `ide_buf_len` + paint → editor.ppm.
# No mouse GUI. Paint owns cursor; this lane owns command script.
#
# Language:
#   ide keys "path/to/cmds.txt"
#   ide key quit|save|run|open|show ["path"]
#
# Script lines (one cmd per line; # comments ok):
#   q|quit  s|save  r|run  o|open <path>  w|show
#   open "<path>"
#
# Exports: ide_keys_dispatch (rax=1 handled), ide_keys_cur_path,
#          ide_keys_loop

.intel_syntax noprefix
.global ide_keys_dispatch
.global ide_keys_loop
.global ide_keys_cur_path

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern sys_open
.extern sys_read
.extern sys_write
.extern sys_close
.extern sys_exit
.extern msg_nl
.extern flag_live
.extern fork_exec_wait
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern ide_buf
.extern ide_buf_len
.extern ide_paint_bind
.extern ide_paint_editor
.extern ide_paint_write_ppm
.extern ide_status_set
.extern ide_dirty
.extern engine_window_show

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT,  64
.equ O_TRUNC,  512
.equ MODE_0644, 420
.equ MODE_0755, 493
.equ IK_SCRIPT_MAX, 4096
.equ IDE_BUF_CAP,   65536
.equ IK_PATH_MAX,   512
.equ IK_LINE_MAX,   512
.equ IK_JSON_MAX,   768

.section .bss
.align 16
ide_keys_cur_path:  .space IK_PATH_MAX
ik_have_path:       .space 8
ik_script:          .space IK_SCRIPT_MAX
ik_script_len:      .space 8
ik_line:            .space IK_LINE_MAX
ik_json:            .space IK_JSON_MAX
ik_argv:            .space 48
ik_mode_flag:       .space 16

.section .data
msg_ik:
    .ascii "[ide.keys] "
msg_ik_len = . - msg_ik
msg_arrow:
    .ascii "  → "
msg_arrow_len = . - msg_arrow

needle_keys:    .ascii "keys\0"
needle_key:     .ascii "key\0"
needle_quit:    .ascii "quit\0"
needle_save:    .ascii "save\0"
needle_run:     .ascii "run\0"
needle_open:    .ascii "open\0"
needle_show:    .ascii "show\0"

kw_q:           .ascii "q\0"
kw_s:           .ascii "s\0"
kw_r:           .ascii "r\0"
kw_o:           .ascii "o\0"
kw_w:           .ascii "w\0"

path_out:       .ascii "out\0"
path_ide:       .ascii "out/ide\0"
path_trace:     .ascii "out/ide/keys_trace.jsonl\0"
path_editor_ppm:.ascii "out/ide/editor.ppm\0"
default_cmds:   .ascii "examples/fixtures/ide/cmds.txt\0"
show_line_def:
    .ascii "ide show \"out/ide/editor.ppm\"\0"

spark_bin:      .ascii "./spark\0"
spark_arg0:     .ascii "spark\0"
flag_dry:       .ascii "--dry-run\0"
flag_live_s:    .ascii "--live\0"

err_unknown:
    .ascii "error: ide keys: want `ide keys [\"script\"]`"
    .ascii " or `ide key quit|save|run|open|show [\"path\"]`\n"
err_unknown_len = . - err_unknown
err_script:
    .ascii "error: ide keys: cannot open command script\n"
err_script_len = . - err_script
err_open:
    .ascii "error: ide keys: open path failed\n"
err_open_len = . - err_open
err_nopath:
    .ascii "error: ide keys: no path (open first)\n"
err_nopath_len = . - err_nopath
err_run:
    .ascii "error: ide keys: run fork failed\n"
err_run_len = . - err_run
err_show_ppm:
    .ascii "error: ide keys: show needs editor.ppm"
    .ascii " (open first)\n"
err_show_ppm_len = . - err_show_ppm

# JSON fragments (assembled into ik_json)
j_pre:
    .ascii "{\"op\":\"ide.keys\",\"mode\":\""
j_pre_len = . - j_pre
j_dry:
    .ascii "dry-run"
j_dry_len = . - j_dry
j_live:
    .ascii "live"
j_live_len = . - j_live
j_mid:
    .ascii "\",\"cmd\":\""
j_mid_len = . - j_mid
j_path:
    .ascii "\",\"path\":\""
j_path_len = . - j_path
j_ok:
    .ascii "\",\"ok\":"
j_ok_len = . - j_ok
j_true:
    .ascii "true"
j_true_len = . - j_true
j_false:
    .ascii "false"
j_false_len = . - j_false
j_note_dry:
    .ascii ",\"note\":\"trace only; no save write / no run fork\""
j_note_dry_len = . - j_note_dry
j_end:
    .ascii "}\n"
j_end_len = . - j_end

cmd_quit:   .ascii "quit\0"
cmd_save:   .ascii "save\0"
cmd_run:    .ascii "run\0"
cmd_open:   .ascii "open\0"
cmd_show:   .ascii "show\0"
cmd_unk:    .ascii "unknown\0"

.section .text

# ide_keys_dispatch — handle ide keys|key from linebuf.
# rax=1 if this lane handled the line; rax=0 if not (peer may own).
ide_keys_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_keys]
    call    contains
    test    rax, rax
    jnz     ikd_keys

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_key]
    call    contains
    test    rax, rax
    jnz     ikd_one
    # not ours
    xor     rax, rax
    jmp     ikd_ret

ikd_keys:
    lea     rsi, [rip+msg_ik]
    mov     rdx, msg_ik_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ikd_def_script
    # copy quote → path on stack via ik_line then loop
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+ik_line]
    xor     r13, r13
ikd_copy_q:
    cmp     r13, r12
    jge     ikd_copy_q_done
    cmp     r13, IK_PATH_MAX-1
    jge     ikd_copy_q_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     ikd_copy_q
ikd_copy_q_done:
    mov     byte ptr [rdi+r13], 0
    lea     rdi, [rip+ik_line]
    call    ide_keys_loop
    jmp     ikd_done_ok

ikd_def_script:
    lea     rdi, [rip+default_cmds]
    call    ide_keys_loop
    jmp     ikd_done_ok

ikd_one:
    lea     rsi, [rip+msg_ik]
    mov     rdx, msg_ik_len
    call    write_stdout
    call    ik_parse_one_from_linebuf
    call    ik_emit_bind
    mov     rax, 1
    jmp     ikd_ret

ikd_done_ok:
    call    ik_emit_bind
    mov     rax, 1
ikd_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

ik_emit_bind:
    lea     rsi, [rip+ik_json]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+ik_json]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    ret

# ide_keys_loop(rdi=script cstr) — read file list, run cmds.
# Dry: JSON traces. Live: real syscalls for open/save/run.
ide_keys_loop:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rsi, rdi
    call    ik_load_script
    test    rax, rax
    jns     ikl_ok_load
    lea     rsi, [rip+err_script]
    mov     rdx, err_script_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ikl_ok_load:
    call    ik_ensure_dirs
    # walk script bytes
    lea     r12, [rip+ik_script]        # cursor
    mov     r13, [rip+ik_script_len]
    lea     r14, [r12+r13]              # end

ikl_next:
    cmp     r12, r14
    jge     ikl_done
    # skip CR/LF/space
ikl_skip:
    cmp     r12, r14
    jge     ikl_done
    movzx   eax, byte ptr [r12]
    cmp     al, ' '
    je      ikl_skip_inc
    cmp     al, 9
    je      ikl_skip_inc
    cmp     al, 10
    je      ikl_skip_inc
    cmp     al, 13
    je      ikl_skip_inc
    jmp     ikl_have
ikl_skip_inc:
    inc     r12
    jmp     ikl_skip

ikl_have:
    cmp     al, '#'
    jne     ikl_copy_line
    # skip to EOL
ikl_skip_com:
    cmp     r12, r14
    jge     ikl_done
    movzx   eax, byte ptr [r12]
    inc     r12
    cmp     al, 10
    jne     ikl_skip_com
    jmp     ikl_next

ikl_copy_line:
    lea     rdi, [rip+ik_line]
    xor     rbx, rbx
ikl_cl:
    cmp     r12, r14
    jge     ikl_cl_done
    movzx   eax, byte ptr [r12]
    cmp     al, 10
    je      ikl_cl_nl
    cmp     al, 13
    je      ikl_cl_nl
    cmp     rbx, IK_LINE_MAX-1
    jge     ikl_cl_nl
    mov     [rdi+rbx], al
    inc     rbx
    inc     r12
    jmp     ikl_cl
ikl_cl_nl:
    inc     r12
ikl_cl_done:
    mov     byte ptr [rdi+rbx], 0
    test    rbx, rbx
    jz      ikl_next

    lea     rdi, [rip+ik_line]
    call    ik_dispatch_line
    # quit returns rax=2 → stop loop (do not exit process)
    cmp     rax, 2
    je      ikl_done
    jmp     ikl_next

ikl_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ik_load_script(rsi=path) → rax=0 ok, -1 fail
ik_load_script:
    push    rbx
    mov     rdi, rsi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      ikls_fail
    mov     rbx, rax
    mov     rdi, rbx
    lea     rsi, [rip+ik_script]
    mov     rdx, IK_SCRIPT_MAX-1
    call    sys_read
    cmp     rax, 0
    jl      ikls_fail_close
    mov     [rip+ik_script_len], rax
    lea     rdi, [rip+ik_script]
    mov     byte ptr [rdi+rax], 0
    mov     rdi, rbx
    call    sys_close
    xor     rax, rax
    pop     rbx
    ret
ikls_fail_close:
    mov     rdi, rbx
    call    sys_close
ikls_fail:
    mov     rax, -1
    pop     rbx
    ret

# ik_parse_one_from_linebuf — single `ide key …`
ik_parse_one_from_linebuf:
    push    rbx
    lea     rbx, [rip+linebuf]
    # prefer quoted path for open
    lea     rdi, [rip+linebuf]
    call    extract_quote
    # fall through to needle match on full line
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_quit]
    call    contains
    test    rax, rax
    jnz     ikp_quit
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_show]
    call    contains
    test    rax, rax
    jnz     ikp_show
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_save]
    call    contains
    test    rax, rax
    jnz     ikp_save
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     ikp_run
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_open]
    call    contains
    test    rax, rax
    jnz     ikp_open
    lea     rsi, [rip+err_unknown]
    mov     rdx, err_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ikp_quit:
    lea     rdi, [rip+cmd_quit]
    call    ik_cmd_quit
    pop     rbx
    ret
ikp_show:
    call    ik_cmd_show
    pop     rbx
    ret
ikp_save:
    lea     rdi, [rip+cmd_save]
    call    ik_cmd_save
    pop     rbx
    ret
ikp_run:
    lea     rdi, [rip+cmd_run]
    call    ik_cmd_run
    pop     rbx
    ret
ikp_open:
    call    ik_open_from_linebuf_quote
    pop     rbx
    ret

# ik_dispatch_line(rdi=ik_line) → rax=0 ok, 2=quit
ik_dispatch_line:
    push    rbx
    push    r12
    mov     rbx, rdi

    # trim leading space already done
    movzx   eax, byte ptr [rbx]
    cmp     al, 'q'
    je      ikdl_qcheck
    cmp     al, 'Q'
    je      ikdl_qcheck
    jmp     ikdl_not_q
ikdl_qcheck:
    movzx   eax, byte ptr [rbx+1]
    test    al, al
    jz      ikdl_quit
    cmp     al, ' '
    je      ikdl_quit
    cmp     al, 9
    je      ikdl_quit
ikdl_not_q:
    mov     rdi, rbx
    lea     rsi, [rip+needle_quit]
    call    contains
    test    rax, rax
    jnz     ikdl_quit

    movzx   eax, byte ptr [rbx]
    cmp     al, 's'
    je      ikdl_scheck
    cmp     al, 'S'
    je      ikdl_scheck
    jmp     ikdl_not_s
ikdl_scheck:
    movzx   eax, byte ptr [rbx+1]
    test    al, al
    jz      ikdl_save
    cmp     al, ' '
    je      ikdl_save
ikdl_not_s:
    mov     rdi, rbx
    lea     rsi, [rip+needle_save]
    call    contains
    test    rax, rax
    jnz     ikdl_save

    movzx   eax, byte ptr [rbx]
    cmp     al, 'r'
    je      ikdl_rcheck
    cmp     al, 'R'
    je      ikdl_rcheck
    jmp     ikdl_not_r
ikdl_rcheck:
    movzx   eax, byte ptr [rbx+1]
    test    al, al
    jz      ikdl_run
    cmp     al, ' '
    je      ikdl_run
ikdl_not_r:
    mov     rdi, rbx
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     ikdl_run

    # w | show — window via spark-engine-show (not `s`; that is save)
    movzx   eax, byte ptr [rbx]
    cmp     al, 'w'
    je      ikdl_wcheck
    cmp     al, 'W'
    je      ikdl_wcheck
    jmp     ikdl_not_w
ikdl_wcheck:
    movzx   eax, byte ptr [rbx+1]
    test    al, al
    jz      ikdl_show
    cmp     al, ' '
    je      ikdl_show
    cmp     al, 9
    je      ikdl_show
ikdl_not_w:
    mov     rdi, rbx
    lea     rsi, [rip+needle_show]
    call    contains
    test    rax, rax
    jnz     ikdl_show

    movzx   eax, byte ptr [rbx]
    cmp     al, 'o'
    je      ikdl_ocheck
    cmp     al, 'O'
    je      ikdl_ocheck
    jmp     ikdl_not_o
ikdl_ocheck:
    movzx   eax, byte ptr [rbx+1]
    cmp     al, ' '
    je      ikdl_open
    cmp     al, 9
    je      ikdl_open
    test    al, al
    jz      ikdl_open_need
ikdl_not_o:
    mov     rdi, rbx
    lea     rsi, [rip+needle_open]
    call    contains
    test    rax, rax
    jnz     ikdl_open
    # unknown line — skip with trace
    lea     rsi, [rip+cmd_unk]
    mov     rdx, 0
    call    ik_trace
    xor     rax, rax
    jmp     ikdl_ret

ikdl_quit:
    call    ik_cmd_quit
    mov     rax, 2
    jmp     ikdl_ret
ikdl_save:
    call    ik_cmd_save
    xor     rax, rax
    jmp     ikdl_ret
ikdl_run:
    call    ik_cmd_run
    xor     rax, rax
    jmp     ikdl_ret
ikdl_show:
    call    ik_cmd_show
    xor     rax, rax
    jmp     ikdl_ret
ikdl_open_need:
    lea     rsi, [rip+err_nopath]
    mov     rdx, err_nopath_len
    call    write_stdout
    xor     rax, rax
    jmp     ikdl_ret
ikdl_open:
    mov     rdi, rbx
    call    ik_open_from_cmd_line
    xor     rax, rax
ikdl_ret:
    pop     r12
    pop     rbx
    ret

# ---- commands ----

ik_cmd_quit:
    lea     rsi, [rip+cmd_quit]
    mov     rdx, 1
    call    ik_trace
    ret

# ik_cmd_show — reuse engine_window_show (dry validate / live X11)
# Quote must be .ppm/.rgb; else default editor.ppm (ignore keys script path).
ik_cmd_show:
    push    rbx
    push    r12
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      iksh_def
    mov     rsi, rax
    mov     r12, rcx
    cmp     r12, 4
    jl      iksh_def
    lea     rbx, [rsi+r12]
    sub     rbx, 4
    cmp     byte ptr [rbx], '.'
    jne     iksh_def
    cmp     byte ptr [rbx+1], 'p'
    je      iksh_ppm
    cmp     byte ptr [rbx+1], 'r'
    jne     iksh_def
    cmp     byte ptr [rbx+2], 'g'
    jne     iksh_def
    cmp     byte ptr [rbx+3], 'b'
    jne     iksh_def
    jmp     iksh_go
iksh_ppm:
    cmp     byte ptr [rbx+2], 'p'
    jne     iksh_def
    cmp     byte ptr [rbx+3], 'm'
    jne     iksh_def
    jmp     iksh_go
iksh_def:
    lea     rsi, [rip+show_line_def]
    lea     rdi, [rip+linebuf]
    xor     rbx, rbx
iksh_copy:
    mov     al, [rsi+rbx]
    mov     [rdi+rbx], al
    test    al, al
    jz      iksh_go
    inc     rbx
    cmp     rbx, 510
    jl      iksh_copy
    mov     byte ptr [rdi+rbx], 0
iksh_go:
    call    engine_window_show
    lea     rsi, [rip+cmd_show]
    mov     rdx, 1
    call    ik_trace
    pop     r12
    pop     rbx
    ret

ik_cmd_save:
    cmp     qword ptr [rip+flag_live], 1
    je      iksv_live
    lea     rsi, [rip+cmd_save]
    mov     rdx, 1
    call    ik_trace
    ret
iksv_live:
    cmp     qword ptr [rip+ik_have_path], 1
    je      iksv_do
    lea     rsi, [rip+err_nopath]
    mov     rdx, err_nopath_len
    call    write_stdout
    lea     rsi, [rip+cmd_save]
    xor     rdx, rdx
    call    ik_trace
    ret
iksv_do:
    lea     rdi, [rip+ide_keys_cur_path]
    lea     rsi, [rip+ide_buf]
    mov     rdx, [rip+ide_buf_len]
    call    write_bytes_path
    lea     rdi, [rip+ide_buf]
    mov     rsi, [rip+ide_buf_len]
    call    ide_paint_bind
    lea     rsi, [rip+cmd_save]
    mov     rdx, 1
    call    ik_trace
    ret

ik_cmd_run:
    cmp     qword ptr [rip+flag_live], 1
    je      ikrn_live
    lea     rsi, [rip+cmd_run]
    mov     rdx, 1
    call    ik_trace
    ret
ikrn_live:
    cmp     qword ptr [rip+ik_have_path], 1
    je      ikrn_do
    lea     rsi, [rip+err_nopath]
    mov     rdx, err_nopath_len
    call    write_stdout
    lea     rsi, [rip+cmd_run]
    xor     rdx, rdx
    call    ik_trace
    ret
ikrn_do:
    # argv: spark --dry-run path NULL (never nest live ask)
    lea     rax, [rip+spark_arg0]
    mov     [rip+ik_argv], rax
    lea     rax, [rip+flag_dry]
    mov     [rip+ik_argv+8], rax
    lea     rax, [rip+ide_keys_cur_path]
    mov     [rip+ik_argv+16], rax
    mov     qword ptr [rip+ik_argv+24], 0
    lea     rdi, [rip+spark_bin]
    lea     rsi, [rip+ik_argv]
    call    fork_exec_wait
    test    rax, rax
    jz      ikrn_ok
    lea     rsi, [rip+err_run]
    mov     rdx, err_run_len
    call    write_stdout
    lea     rsi, [rip+cmd_run]
    xor     rdx, rdx
    call    ik_trace
    ret
ikrn_ok:
    lea     rsi, [rip+cmd_run]
    mov     rdx, 1
    call    ik_trace
    ret

# open from `ide key open "path"`
ik_open_from_linebuf_quote:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      iko_fail
    mov     rsi, rax
    mov     rdx, rcx
    call    ik_set_path_and_load
    ret
iko_fail:
    lea     rsi, [rip+err_open]
    mov     rdx, err_open_len
    call    write_stdout
    lea     rsi, [rip+cmd_open]
    xor     rdx, rdx
    call    ik_trace
    ret

# open from script line: `o path` / `open path` / `open "path"`
ik_open_from_cmd_line:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    extract_quote
    test    rax, rax
    jz      ikof_scan
    mov     rsi, rax
    mov     rdx, rcx
    call    ik_set_path_and_load
    jmp     ikof_ret
ikof_scan:
    # skip first token
    mov     rsi, rbx
ikof_skip_tok:
    movzx   eax, byte ptr [rsi]
    test    al, al
    jz      ikof_need
    cmp     al, ' '
    je      ikof_ws
    cmp     al, 9
    je      ikof_ws
    inc     rsi
    jmp     ikof_skip_tok
ikof_ws:
    # skip spaces
ikof_ws2:
    movzx   eax, byte ptr [rsi]
    cmp     al, ' '
    je      ikof_ws_inc
    cmp     al, 9
    je      ikof_ws_inc
    jmp     ikof_path
ikof_ws_inc:
    inc     rsi
    jmp     ikof_ws2
ikof_path:
    test    al, al
    jz      ikof_need
    # cstr length
    mov     r12, rsi
    xor     rcx, rcx
ikof_len:
    movzx   eax, byte ptr [r12+rcx]
    test    al, al
    jz      ikof_got
    inc     rcx
    cmp     rcx, IK_PATH_MAX-1
    jl      ikof_len
ikof_got:
    mov     rsi, r12
    mov     rdx, rcx
    call    ik_set_path_and_load
    jmp     ikof_ret
ikof_need:
    lea     rsi, [rip+err_nopath]
    mov     rdx, err_nopath_len
    call    write_stdout
    lea     rsi, [rip+cmd_open]
    xor     rdx, rdx
    call    ik_trace
ikof_ret:
    pop     r12
    pop     rbx
    ret

# ik_set_path_and_load(rsi=ptr, rdx=len) — always real open+read
ik_set_path_and_load:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    lea     rdi, [rip+ide_keys_cur_path]
    xor     rbx, rbx
iksp_copy:
    cmp     rbx, r13
    jge     iksp_term
    cmp     rbx, IK_PATH_MAX-1
    jge     iksp_term
    mov     al, [r12+rbx]
    mov     [rdi+rbx], al
    inc     rbx
    jmp     iksp_copy
iksp_term:
    mov     byte ptr [rdi+rbx], 0

    lea     rdi, [rip+ide_keys_cur_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      iksp_fail
    mov     rbx, rax
    mov     rdi, rbx
    lea     rsi, [rip+ide_buf]
    mov     rdx, IDE_BUF_CAP-1
    call    sys_read
    cmp     rax, 0
    jl      iksp_fail_cl
    mov     [rip+ide_buf_len], rax
    lea     rdi, [rip+ide_buf]
    mov     byte ptr [rdi+rax], 0
    mov     rdi, rbx
    call    sys_close
    mov     qword ptr [rip+ik_have_path], 1
    mov     qword ptr [rip+ide_dirty], 0
    lea     rsi, [rip+ide_keys_cur_path]
    call    strlen
    mov     rsi, rax
    lea     rdi, [rip+ide_keys_cur_path]
    call    ide_status_set
    lea     rdi, [rip+ide_buf]
    mov     rsi, [rip+ide_buf_len]
    call    ide_paint_bind
    # Polish: same as core — paint → out/ide/editor.ppm for ide show
    call    ik_ensure_dirs
    call    ide_paint_editor
    test    eax, eax
    jnz     iksp_trace
    lea     rdi, [rip+path_editor_ppm]
    call    ide_paint_write_ppm
iksp_trace:
    lea     rsi, [rip+cmd_open]
    mov     rdx, 1
    call    ik_trace
    pop     r13
    pop     r12
    pop     rbx
    ret
iksp_fail_cl:
    mov     rdi, rbx
    call    sys_close
iksp_fail:
    mov     qword ptr [rip+ik_have_path], 0
    lea     rsi, [rip+err_open]
    mov     rdx, err_open_len
    call    write_stdout
    lea     rsi, [rip+cmd_open]
    xor     rdx, rdx
    call    ik_trace
    pop     r13
    pop     r12
    pop     rbx
    ret

# ik_trace(rsi=cmd cstr, rdx=ok 0/1) — print JSON + append jsonl
ik_trace:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi            # cmd
    mov     r13, rdx            # ok

    lea     rdi, [rip+ik_json]
    # pre
    lea     rsi, [rip+j_pre]
    mov     rcx, j_pre_len
    call    ik_append
    cmp     qword ptr [rip+flag_live], 1
    je      ikt_live
    lea     rsi, [rip+j_dry]
    mov     rcx, j_dry_len
    call    ik_append
    jmp     ikt_mid
ikt_live:
    lea     rsi, [rip+j_live]
    mov     rcx, j_live_len
    call    ik_append
ikt_mid:
    lea     rsi, [rip+j_mid]
    mov     rcx, j_mid_len
    call    ik_append
    # cmd strlen
    mov     rsi, r12
    call    strlen
    mov     rcx, rax
    mov     rsi, r12
    call    ik_append
    lea     rsi, [rip+j_path]
    mov     rcx, j_path_len
    call    ik_append
    cmp     qword ptr [rip+ik_have_path], 1
    jne     ikt_nopath
    lea     rsi, [rip+ide_keys_cur_path]
    call    strlen
    mov     rcx, rax
    lea     rsi, [rip+ide_keys_cur_path]
    call    ik_append
    jmp     ikt_ok
ikt_nopath:
    # empty path
ikt_ok:
    lea     rsi, [rip+j_ok]
    mov     rcx, j_ok_len
    call    ik_append
    test    r13, r13
    jz      ikt_false
    lea     rsi, [rip+j_true]
    mov     rcx, j_true_len
    call    ik_append
    jmp     ikt_note
ikt_false:
    lea     rsi, [rip+j_false]
    mov     rcx, j_false_len
    call    ik_append
ikt_note:
    cmp     qword ptr [rip+flag_live], 1
    je      ikt_end
    lea     rsi, [rip+j_note_dry]
    mov     rcx, j_note_dry_len
    call    ik_append
ikt_end:
    lea     rsi, [rip+j_end]
    mov     rcx, j_end_len
    call    ik_append
    mov     byte ptr [rdi], 0

    # stdout: arrow + json
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ik_json]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+ik_json]
    call    write_stdout

    # append jsonl (best-effort)
    call    ik_append_trace_file

    pop     r13
    pop     r12
    pop     rbx
    ret

# ik_append: rdi=dest cursor, rsi=src, rcx=len → rdi advanced
ik_append:
    push    rax
    push    rbx
    xor     rbx, rbx
ika_loop:
    cmp     rbx, rcx
    jge     ika_done
    # bounds: ik_json + IK_JSON_MAX
    lea     rax, [rip+ik_json]
    add     rax, IK_JSON_MAX-1
    cmp     rdi, rax
    jge     ika_done
    mov     al, [rsi+rbx]
    mov     [rdi], al
    inc     rdi
    inc     rbx
    jmp     ika_loop
ika_done:
    pop     rbx
    pop     rax
    ret

ik_ensure_dirs:
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_ide]
    mov     rsi, MODE_0755
    call    sys_mkdir
    ret

# append ik_json to out/ide/keys_trace.jsonl (O_CREAT|O_WRONLY|append)
ik_append_trace_file:
    push    rbx
    push    r12
    # open with O_WRONLY|O_CREAT|O_APPEND (1024)
    lea     rdi, [rip+path_trace]
    mov     rsi, O_WRONLY
    or      rsi, O_CREAT
    or      rsi, 1024              # O_APPEND
    mov     rdx, MODE_0644
    call    sys_open
    cmp     rax, 0
    jl      ikat_done
    mov     rbx, rax
    lea     rsi, [rip+ik_json]
    call    strlen
    mov     r12, rax
    mov     rdi, rbx
    lea     rsi, [rip+ik_json]
    mov     rdx, r12
    call    sys_write
    mov     rdi, rbx
    call    sys_close
ikat_done:
    pop     r12
    pop     rbx
    ret
