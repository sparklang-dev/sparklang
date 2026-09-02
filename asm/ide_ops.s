# Spark IDE core — language ops (asm syscalls only).
# Ops: ide new | open | save | run | buffer | ask | show
# Buffer in BSS; open/save via path; run fork/exec ./spark.
# ide ask → ask_run_prompt (dry fixture / live companion).
# ide show → engine_window_show (dry validate PPM; live spark-engine-show).
# Dry-run: child always gets --dry-run (safe). Display = terminal dump.
# Paint wire: .global ide_buf / ide_buf_len / ide_dirty + paint after mutate.
# Dirty '*': status strip after buffer edit (ide new); cleared on open/save.
# No PyQt / Electron / VS Code product surface.
.intel_syntax noprefix
.global ide_ops_dispatch
.global ide_buf
.global ide_buf_len
.global ide_dirty

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
.extern flag_live
.extern fork_exec_wait
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern ide_paint_bind
.extern ide_paint_editor
.extern ide_paint_write_ppm
.extern ask_run_prompt
.extern ide_ai_set
.extern ide_status_set
.extern last_val
.extern last_val_len
.extern engine_window_show

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT,  64
.equ O_TRUNC,  512
.equ MODE_0755, 493
.equ IDE_BUF_CAP, 65536
.equ IDE_PATH_CAP, 512
.equ IDE_ASK_CAP, 4096
.equ IDE_STATUS_SCR, 64

.section .bss
.align 16
ide_buf:        .space IDE_BUF_CAP
ide_buf_len:    .space 8
ide_path:       .space IDE_PATH_CAP
ide_path_set:   .space 8
ide_dirty:      .space 8
ide_status_scr: .space IDE_STATUS_SCR
run_argv:       .space 48
quote_tmp:      .space IDE_PATH_CAP
ide_ask_prompt: .space IDE_ASK_CAP

.section .data
msg_ide:        .ascii "[ide] "
msg_ide_len = . - msg_ide
msg_arrow:      .ascii "  → "
msg_arrow_len = . - msg_arrow

needle_new:     .ascii "new\0"
needle_open:    .ascii "open\0"
needle_save:    .ascii "save\0"
needle_run:     .ascii "run\0"
needle_buffer:  .ascii "buffer\0"
needle_ask:     .ascii "ask\0"
needle_show:    .ascii "show\0"
sep_nl:         .ascii "\n---\n"
sep_nl_len = . - sep_nl

path_out:       .ascii "out\0"
path_out_ide:   .ascii "out/ide\0"
path_temp:      .ascii "out/ide/buffer.spark\0"
path_editor_ppm:.ascii "out/ide/editor.ppm\0"
# Default show line → engine_window_show quote (editor PPM after paint)
show_line_def:
    .ascii "ide show \"out/ide/editor.ppm\"\0"

spark_bin:      .ascii "./spark\0"
spark_arg0:     .ascii "spark\0"
flag_dry:       .ascii "--dry-run\0"
flag_live_s:    .ascii "--live\0"

j_new:
    .ascii "{\"op\":\"ide.new\",\"ok\":true,"
    .ascii "\"buffer\":true,\"dirty\":true}\n"
j_new_len = . - j_new

j_open:
    .ascii "{\"op\":\"ide.open\",\"ok\":true,"
    .ascii "\"dirty\":false}\n"
j_open_len = . - j_open

j_save:
    .ascii "{\"op\":\"ide.save\",\"ok\":true,"
    .ascii "\"dirty\":false}\n"
j_save_len = . - j_save

path_status_txt:
    .ascii "out/ide/status.txt\0"
path_status_dirty:
    .ascii "out/ide/status_dirty.txt\0"
cstr_untitled:
    .ascii "untitled\0"

j_run_dry:
    .ascii "{\"op\":\"ide.run\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\"}\n"
j_run_dry_len = . - j_run_dry

j_run_live:
    .ascii "{\"op\":\"ide.run\",\"ok\":true,"
    .ascii "\"mode\":\"live\"}\n"
j_run_live_len = . - j_run_live

j_buf:
    .ascii "{\"op\":\"ide.buffer\",\"ok\":true}\n"
j_buf_len = . - j_buf

j_ask:
    .ascii "{\"op\":\"ide.ask\",\"ok\":true,"
    .ascii "\"via\":\"ask_run_prompt\"}\n"
j_ask_len = . - j_ask

j_show:
    .ascii "{\"op\":\"ide.show\",\"ok\":true,"
    .ascii "\"via\":\"spark-engine-show\"}\n"
j_show_len = . - j_show

err_unknown:
    .ascii "error: unknown ide op"
    .ascii " (want: new|open|save|run|buffer|ask|show)\n"
err_unknown_len = . - err_unknown
err_open_q:
    .ascii "error: ide open needs \"path\"\n"
err_open_q_len = . - err_open_q
err_open_fail:
    .ascii "error: ide open: cannot read path\n"
err_open_fail_len = . - err_open_fail
err_save_path:
    .ascii "error: ide save: no path"
    .ascii " (ide save \"path\" or open first)\n"
err_save_path_len = . - err_save_path
err_run_empty:
    .ascii "error: ide run: empty buffer"
    .ascii " (ide open or write first)\n"
err_run_empty_len = . - err_run_empty
err_run_fail:
    .ascii "error: ide run: ./spark child failed\n"
err_run_fail_len = . - err_run_fail
err_ask_empty:
    .ascii "error: ide ask: empty buffer"
    .ascii " (ide open first)\n"
err_ask_empty_len = . - err_ask_empty

.section .text

# ------------------------------------------------------------
ide_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_ide]
    mov     rdx, msg_ide_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ask]
    call    contains
    test    rax, rax
    jnz     ide_ask

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_open]
    call    contains
    test    rax, rax
    jnz     ide_open

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_save]
    call    contains
    test    rax, rax
    jnz     ide_save

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     ide_run

    # buffer before show — "-> shown" binds contain substring "show"
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_buffer]
    call    contains
    test    rax, rax
    jnz     ide_buffer

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_show]
    call    contains
    test    rax, rax
    jnz     ide_show

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_new]
    call    contains
    test    rax, rax
    jnz     ide_new

    lea     rsi, [rip+err_unknown]
    mov     rdx, err_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- ide ask ["instruction"] — buffer → real ask path ---
ide_ask:
    lea     rsi, [rip+needle_ask]
    mov     rdx, 3
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    cmp     qword ptr [rip+ide_buf_len], 0
    je      ide_ask_empty

    lea     r12, [rip+ide_ask_prompt]
    xor     r13, r13
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ide_ask_buf_only

    mov     rsi, rax
    mov     rbx, rcx
    cmp     rbx, IDE_ASK_CAP - 64
    jl      ia_q_ok
    mov     rbx, IDE_ASK_CAP - 64
ia_q_ok:
    xor     rcx, rcx
ia_q_copy:
    cmp     rcx, rbx
    jge     ia_q_sep
    mov     al, [rsi+rcx]
    mov     [r12+rcx], al
    inc     rcx
    jmp     ia_q_copy
ia_q_sep:
    mov     r13, rcx
    lea     rsi, [rip+sep_nl]
    xor     rcx, rcx
ia_sep_copy:
    cmp     rcx, sep_nl_len
    jge     ia_append_buf
    mov     al, [rsi+rcx]
    mov     [r12+r13], al
    inc     r13
    inc     rcx
    jmp     ia_sep_copy

ide_ask_buf_only:
    xor     r13, r13
ia_append_buf:
    lea     rsi, [rip+ide_buf]
    mov     rbx, [rip+ide_buf_len]
    mov     rax, IDE_ASK_CAP - 1
    sub     rax, r13
    cmp     rbx, rax
    jle     ia_blen_ok
    mov     rbx, rax
ia_blen_ok:
    xor     rcx, rcx
ia_b_copy:
    cmp     rcx, rbx
    jge     ia_b_done
    mov     al, [rsi+rcx]
    mov     [r12+r13], al
    inc     r13
    inc     rcx
    jmp     ia_b_copy
ia_b_done:
    mov     byte ptr [r12+r13], 0

    lea     rdi, [rip+ide_ask_prompt]
    mov     rsi, r13
    call    ask_run_prompt

    lea     rdi, [rip+last_val]
    mov     rsi, [rip+last_val_len]
    call    ide_ai_set
    call    ide_rebind_paint

    # Keep ask reply in last_val for `-> name`
    lea     rsi, [rip+j_ask]
    mov     rdx, j_ask_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

ide_ask_empty:
    lea     rsi, [rip+err_ask_empty]
    mov     rdx, err_ask_empty_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- ide show ["path.ppm"] — real engine_window / spark-engine-show ---
# After open/paint: default out/ide/editor.ppm. Dry validates; live X11.
ide_show:
    lea     rsi, [rip+needle_show]
    mov     rdx, 4
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    # Refresh paint when buffer has content (open/ask already painted)
    cmp     qword ptr [rip+ide_buf_len], 0
    je      ide_show_path
    call    ide_rebind_paint

ide_show_path:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jnz     ide_show_go
    lea     rsi, [rip+show_line_def]
    lea     rdi, [rip+linebuf]
    call    ide_strcpy

ide_show_go:
    call    engine_window_show

    lea     rsi, [rip+j_show]
    mov     rdx, j_show_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- ide new ---
ide_new:
    lea     rsi, [rip+needle_new]
    mov     rdx, 3
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    mov     qword ptr [rip+ide_buf_len], 0
    mov     byte ptr [rip+ide_buf], 0
    mov     qword ptr [rip+ide_path_set], 0
    mov     byte ptr [rip+ide_path], 0
    # buffer cleared = dirty edit (status strip shows *)
    mov     qword ptr [rip+ide_dirty], 1

    # optional path quote → set path, keep empty buffer
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ide_new_rebind
    call    ide_store_path
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ide_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+ide_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
ide_new_rebind:
    call    ide_rebind_paint
ide_new_json:
    lea     rax, [rip+j_new]
    mov     rcx, j_new_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_new]
    mov     rdx, j_new_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- ide open "path" ---
ide_open:
    lea     rsi, [rip+needle_open]
    mov     rdx, 4
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ide_open_noq
    call    ide_store_path

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ide_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+ide_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+ide_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      ide_open_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+ide_buf]
    mov     rdx, IDE_BUF_CAP - 1
    call    sys_read
    cmp     rax, 0
    jl      ide_open_fail_close
    mov     r13, rax
    mov     qword ptr [rip+ide_buf_len], r13
    lea     rdi, [rip+ide_buf]
    add     rdi, r13
    mov     byte ptr [rdi], 0
    mov     rdi, r12
    call    sys_close
    mov     qword ptr [rip+ide_dirty], 0
    call    ide_rebind_paint

    lea     rax, [rip+j_open]
    mov     rcx, j_open_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_open]
    mov     rdx, j_open_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

ide_open_noq:
    lea     rsi, [rip+err_open_q]
    mov     rdx, err_open_q_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ide_open_fail_close:
    mov     rdi, r12
    call    sys_close
ide_open_fail:
    lea     rsi, [rip+err_open_fail]
    mov     rdx, err_open_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- ide save ["path"] ---
ide_save:
    lea     rsi, [rip+needle_save]
    mov     rdx, 4
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ide_save_use_cur
    call    ide_store_path
ide_save_use_cur:
    cmp     qword ptr [rip+ide_path_set], 1
    jne     ide_save_nopath

    call    ide_ensure_outdir

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ide_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+ide_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+ide_path]
    lea     rsi, [rip+ide_buf]
    mov     rdx, [rip+ide_buf_len]
    call    write_bytes_path
    mov     qword ptr [rip+ide_dirty], 0
    call    ide_rebind_paint

    lea     rax, [rip+j_save]
    mov     rcx, j_save_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_save]
    mov     rdx, j_save_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

ide_save_nopath:
    lea     rsi, [rip+err_save_path]
    mov     rdx, err_save_path_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- ide buffer (terminal dump) ---
ide_buffer:
    lea     rsi, [rip+needle_buffer]
    mov     rdx, 6
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ide_buf]
    mov     rdx, [rip+ide_buf_len]
    call    write_stdout
    # ensure trailing nl if buffer nonempty and last != nl
    cmp     qword ptr [rip+ide_buf_len], 0
    je      ide_buf_json
    mov     rax, [rip+ide_buf_len]
    lea     rdi, [rip+ide_buf]
    add     rdi, rax
    dec     rdi
    cmp     byte ptr [rdi], 10
    je      ide_buf_json
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
ide_buf_json:
    lea     rax, [rip+j_buf]
    mov     rcx, j_buf_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_buf]
    mov     rdx, j_buf_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- ide run — fork/exec ./spark on path or temp ---
ide_run:
    lea     rsi, [rip+needle_run]
    mov     rdx, 3
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    cmp     qword ptr [rip+ide_buf_len], 0
    je      ide_run_empty

    call    ide_ensure_outdir

    # path set → flush buffer to path; else → temp
    cmp     qword ptr [rip+ide_path_set], 1
    je      ide_run_flush_path
    # copy temp path into ide_path for this run
    lea     rsi, [rip+path_temp]
    lea     rdi, [rip+ide_path]
    call    ide_strcpy
    mov     qword ptr [rip+ide_path_set], 1
ide_run_flush_path:
    lea     rdi, [rip+ide_path]
    lea     rsi, [rip+ide_buf]
    mov     rdx, [rip+ide_buf_len]
    call    write_bytes_path

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ide_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+ide_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    # argv: spark (--dry-run|--live) path
    lea     rax, [rip+spark_arg0]
    mov     [rip+run_argv], rax
    cmp     qword ptr [rip+flag_live], 1
    je      ide_run_live_argv
    lea     rax, [rip+flag_dry]
    mov     [rip+run_argv+8], rax
    jmp     ide_run_argv_path
ide_run_live_argv:
    lea     rax, [rip+flag_live_s]
    mov     [rip+run_argv+8], rax
ide_run_argv_path:
    lea     rax, [rip+ide_path]
    mov     [rip+run_argv+16], rax
    mov     qword ptr [rip+run_argv+24], 0

    lea     rdi, [rip+spark_bin]
    lea     rsi, [rip+run_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     ide_run_child_fail

    cmp     qword ptr [rip+flag_live], 1
    je      ide_run_json_live
    lea     rax, [rip+j_run_dry]
    mov     rcx, j_run_dry_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_run_dry]
    mov     rdx, j_run_dry_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret
ide_run_json_live:
    lea     rax, [rip+j_run_live]
    mov     rcx, j_run_live_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+j_run_live]
    mov     rdx, j_run_live_len
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

ide_run_empty:
    lea     rsi, [rip+err_run_empty]
    mov     rdx, err_run_empty_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ide_run_child_fail:
    lea     rsi, [rip+err_run_fail]
    mov     rdx, err_run_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- helpers ---
# ide_store_path: rax=src rcx=len → ide_path + path_set=1
ide_store_path:
    push    rbx
    push    r12
    mov     rsi, rax
    mov     r12, rcx
    cmp     r12, IDE_PATH_CAP - 1
    jl      isp_ok
    mov     r12, IDE_PATH_CAP - 1
isp_ok:
    lea     rdi, [rip+ide_path]
    xor     rbx, rbx
isp_copy:
    cmp     rbx, r12
    jge     isp_done
    mov     al, [rsi+rbx]
    mov     [rdi+rbx], al
    inc     rbx
    jmp     isp_copy
isp_done:
    mov     byte ptr [rdi+rbx], 0
    mov     qword ptr [rip+ide_path_set], 1
    pop     r12
    pop     rbx
    ret

# ide_strcpy: rsi=src cstr → rdi=dst (max IDE_PATH_CAP-1)
ide_strcpy:
    push    rbx
    xor     rbx, rbx
isc_loop:
    mov     al, [rsi+rbx]
    mov     [rdi+rbx], al
    test    al, al
    jz      isc_done
    inc     rbx
    cmp     rbx, IDE_PATH_CAP - 1
    jl      isc_loop
    mov     byte ptr [rdi+rbx], 0
isc_done:
    pop     rbx
    ret

ide_ensure_outdir:
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_out_ide]
    mov     rsi, MODE_0755
    call    sys_mkdir
    ret

# ide_rebind_paint: status path[+*] + bind + paint → editor.ppm
# Dirty after buffer edit (ide new): append '*' to status strip.
ide_rebind_paint:
    push    rbx
    push    r12
    lea     rdi, [rip+ide_status_scr]
    xor     rbx, rbx
    cmp     qword ptr [rip+ide_path_set], 1
    jne     irp_copy_untitled
    lea     rsi, [rip+ide_path]
    jmp     irp_copy_src
irp_copy_untitled:
    lea     rsi, [rip+cstr_untitled]
irp_copy_src:
    mov     al, [rsi+rbx]
    test    al, al
    jz      irp_copied
    cmp     rbx, IDE_STATUS_SCR - 2
    jge     irp_copied
    mov     [rdi+rbx], al
    inc     rbx
    jmp     irp_copy_src
irp_copied:
    cmp     qword ptr [rip+ide_dirty], 1
    jne     irp_term
    cmp     rbx, IDE_STATUS_SCR - 1
    jge     irp_term
    mov     byte ptr [rdi+rbx], '*'
    inc     rbx
irp_term:
    mov     byte ptr [rdi+rbx], 0
    mov     r12, rbx
    lea     rdi, [rip+ide_status_scr]
    mov     rsi, r12
    call    ide_status_set
    lea     rdi, [rip+ide_buf]
    mov     rsi, [rip+ide_buf_len]
    call    ide_paint_bind
    call    ide_ensure_outdir
    # status.txt = current strip; status_dirty.txt snapshot if dirty
    lea     rdi, [rip+path_status_txt]
    lea     rsi, [rip+ide_status_scr]
    mov     rdx, r12
    call    write_bytes_path
    cmp     qword ptr [rip+ide_dirty], 1
    jne     irp_paint
    lea     rdi, [rip+path_status_dirty]
    lea     rsi, [rip+ide_status_scr]
    mov     rdx, r12
    call    write_bytes_path
irp_paint:
    call    ide_paint_editor
    test    eax, eax
    jnz     irp_done
    lea     rdi, [rip+path_editor_ppm]
    call    ide_paint_write_ppm
irp_done:
    pop     r12
    pop     rbx
    ret
