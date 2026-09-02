# Spark engine B — display window (browser show / engine show).
# Dry-run: validate PPM / raw RGB path, write show.json, never open X11.
# Live: fork ./spark-engine-show --ppm PATH --hold 2000 (X11 PutImage).
# Pipeline PPM path: out/engine/pipeline.ppm (engine render / paint boxes).
# Pure-asm display path preferred; X11 handshake is companion-only.
.intel_syntax noprefix
.global engine_window_show

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

.equ MODE_0755, 493
.equ O_RDONLY, 0

.section .bss
.align 16
path_buf:       .space 512
show_argv:      .space 64
hdr_buf:        .space 64
assemble_buf:   .space 1024

.section .data
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow

path_out:       .ascii "out\0"
path_browser:   .ascii "out/browser\0"
path_show_json: .ascii "out/browser/show.json\0"
default_ppm:    .ascii "examples/fixtures/browser/engine_show.ppm\0"

show_bin:       .ascii "./spark-engine-show\0"
show_arg0:      .ascii "spark-engine-show\0"
show_ppm_flag:  .ascii "--ppm\0"
show_hold_flag: .ascii "--hold\0"
# Live fork: keep window mapped ~2s (companion default 0 is CI flash).
show_hold_ms:   .ascii "2000\0"

j_show_dry_pre:
    .ascii "{\"op\":\"show\",\"ok\":true,\"mode\":\"dry-run\","
    .ascii "\"display\":false,\"path\":\""
j_show_dry_pre_len = . - j_show_dry_pre
j_show_dry_mid:
    .ascii "\",\"format\":\""
j_show_dry_mid_len = . - j_show_dry_mid
j_show_dry_suf:
    .ascii "\"}"
j_show_dry_suf_len = . - j_show_dry_suf

j_show_live_pre:
    .ascii "{\"op\":\"show\",\"ok\":true,\"mode\":\"live\","
    .ascii "\"display\":true,\"path\":\""
j_show_live_pre_len = . - j_show_live_pre
j_show_live_suf:
    .ascii "\"}"
j_show_live_suf_len = . - j_show_live_suf

fmt_ppm:    .ascii "ppm\0"
fmt_rgb:    .ascii "rgb\0"
fmt_unk:    .ascii "unknown\0"

err_show_missing:
    .ascii "error: browser show: cannot open image"
    .ascii " (PPM/RGB path)\n"
err_show_missing_len = . - err_show_missing
err_show_bad:
    .ascii "error: browser show: not P6 PPM or .rgb"
    .ascii " (want P6 header or --rgb)\n"
err_show_bad_len = . - err_show_bad
err_show_live:
    .ascii "error: browser show live helper failed"
    .ascii " (./spark-engine-show --ppm PATH)\n"
err_show_live_len = . - err_show_live

.section .text

# engine_window_show — called from browser_ops after "show" match.
# Uses linebuf quote for path; default fixture if none.
# Success: ret. Failure: stderr-style stdout + sys_exit(1).
engine_window_show:
    push    rbx
    push    r12
    push    r13

    call    ew_ensure_dirs

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ew_def_path
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+path_buf]
    xor     r13, r13
ew_copy_path:
    cmp     r13, r12
    jge     ew_path_term
    cmp     r13, 510
    jge     ew_path_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     ew_copy_path
ew_path_term:
    mov     byte ptr [rdi+r13], 0
    jmp     ew_have_path
ew_def_path:
    lea     rsi, [rip+default_ppm]
    lea     rdi, [rip+path_buf]
    call    ew_copy_cstr

ew_have_path:
    call    ew_validate_image
    cmp     rax, 0
    jle     ew_bad_image        # 0=missing, -1=bad fmt
    mov     r12, rax            # 1=ppm 2=rgb

    cmp     qword ptr [rip+flag_live], 1
    je      ew_live

    # ---- dry: JSON + show.json, never display ----
    call    ew_build_dry_json
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+assemble_buf]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rdx, rax
    lea     rdi, [rip+path_show_json]
    lea     rsi, [rip+assemble_buf]
    call    write_bytes_path

    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+assemble_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     r13
    pop     r12
    pop     rbx
    ret

ew_live:
    lea     rax, [rip+show_arg0]
    mov     [rip+show_argv], rax
    lea     rax, [rip+show_ppm_flag]
    mov     [rip+show_argv+8], rax
    lea     rax, [rip+path_buf]
    mov     [rip+show_argv+16], rax
    lea     rax, [rip+show_hold_flag]
    mov     [rip+show_argv+24], rax
    lea     rax, [rip+show_hold_ms]
    mov     [rip+show_argv+32], rax
    mov     qword ptr [rip+show_argv+40], 0
    lea     rdi, [rip+show_bin]
    lea     rsi, [rip+show_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     ew_live_fail

    call    ew_build_live_json
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+assemble_buf]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rdx, rax
    lea     rdi, [rip+path_show_json]
    lea     rsi, [rip+assemble_buf]
    call    write_bytes_path
    lea     rsi, [rip+assemble_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+assemble_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     r13
    pop     r12
    pop     rbx
    ret

ew_live_fail:
    lea     rsi, [rip+err_show_live]
    mov     rdx, err_show_live_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ew_bad_image:
    # rax=0 missing; rax=-1 bad format
    cmp     rax, -1
    je      ew_bad_fmt
    lea     rsi, [rip+err_show_missing]
    mov     rdx, err_show_missing_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
ew_bad_fmt:
    lea     rsi, [rip+err_show_bad]
    mov     rdx, err_show_bad_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---- helpers ----
ew_ensure_dirs:
    lea     rdi, [rip+path_out]
    mov     esi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_browser]
    mov     esi, MODE_0755
    call    sys_mkdir
    ret

# rsi=src rdi=dst copy cstr incl NUL
ew_copy_cstr:
ew_cc:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     ew_cc
    ret

# Validate path_buf. rax=1 ppm, 2 rgb, 0 missing, -1 bad format
ew_validate_image:
    lea     rdi, [rip+path_buf]
    mov     esi, O_RDONLY
    xor     edx, edx
    call    sys_open
    cmp     rax, 0
    jl      ew_v_miss
    mov     r13, rax
    mov     rdi, r13
    lea     rsi, [rip+hdr_buf]
    mov     rdx, 16
    call    sys_read
    mov     rbx, rax
    mov     rdi, r13
    call    sys_close
    cmp     rbx, 3
    jl      ew_v_bad
    cmp     byte ptr [rip+hdr_buf], 'P'
    jne     ew_try_rgb
    cmp     byte ptr [rip+hdr_buf+1], '6'
    jne     ew_try_rgb
    mov     al, [rip+hdr_buf+2]
    cmp     al, 10
    je      ew_v_ppm
    cmp     al, 13
    je      ew_v_ppm
    cmp     al, ' '
    je      ew_v_ppm
    cmp     al, 9
    je      ew_v_ppm
    jmp     ew_try_rgb
ew_v_ppm:
    mov     eax, 1
    ret
ew_try_rgb:
    lea     rdi, [rip+path_buf]
    call    strlen
    cmp     rax, 4
    jl      ew_v_bad
    lea     rsi, [rip+path_buf]
    add     rsi, rax
    sub     rsi, 4
    cmp     byte ptr [rsi], '.'
    jne     ew_v_bad
    cmp     byte ptr [rsi+1], 'r'
    jne     ew_v_bad
    cmp     byte ptr [rsi+2], 'g'
    jne     ew_v_bad
    cmp     byte ptr [rsi+3], 'b'
    jne     ew_v_bad
    mov     eax, 2
    ret
ew_v_miss:
    xor     eax, eax
    ret
ew_v_bad:
    mov     rax, -1
    ret

# Build dry JSON into assemble_buf (NUL-terminated). r12=1|2 format
ew_build_dry_json:
    lea     rdi, [rip+assemble_buf]
    lea     rsi, [rip+j_show_dry_pre]
    mov     rcx, j_show_dry_pre_len
    call    ew_memcpy_n
    lea     rsi, [rip+path_buf]
    call    ew_append_cstr
    lea     rsi, [rip+j_show_dry_mid]
    mov     rcx, j_show_dry_mid_len
    call    ew_memcpy_n
    cmp     r12, 2
    je      ew_fmt_rgb
    lea     rsi, [rip+fmt_ppm]
    jmp     ew_fmt_done
ew_fmt_rgb:
    lea     rsi, [rip+fmt_rgb]
ew_fmt_done:
    call    ew_append_cstr
    lea     rsi, [rip+j_show_dry_suf]
    mov     rcx, j_show_dry_suf_len
    call    ew_memcpy_n
    mov     byte ptr [rdi], 0
    ret

ew_build_live_json:
    lea     rdi, [rip+assemble_buf]
    lea     rsi, [rip+j_show_live_pre]
    mov     rcx, j_show_live_pre_len
    call    ew_memcpy_n
    lea     rsi, [rip+path_buf]
    call    ew_append_cstr
    lea     rsi, [rip+j_show_live_suf]
    mov     rcx, j_show_live_suf_len
    call    ew_memcpy_n
    mov     byte ptr [rdi], 0
    ret

ew_memcpy_n:
    test    rcx, rcx
    jz      ew_mcn_d
ew_mcn:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     ew_mcn
ew_mcn_d:
    ret

ew_append_cstr:
ew_ac:
    mov     al, [rsi]
    test    al, al
    jz      ew_ac_d
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     ew_ac
ew_ac_d:
    ret
