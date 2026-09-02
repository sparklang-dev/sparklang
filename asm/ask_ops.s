# Spark live ask — fork/exec spark-ask-http (OpenAI-compatible Bifrost)
# Dry-run path stays in asm/spark.s; this unit only runs when --live.
#
# Exports: ask_live_dispatch, ask_remember_model, ask_probe_dispatch,
#          ask_run_prompt (buffer/selection → dry fixture | live companion)
# Imports: linebuf, write_stdout, extract_quote, fork_exec_wait,
#          write_bytes_path, sys_open, sys_read, sys_close, sys_exit,
#          set_last_from_rcx, bind_arrow_from_line, strlen, flag_live,
#          pick_ask_reply_ptr (dry fixture path — same as ask_dry)

.intel_syntax noprefix
.global ask_live_dispatch
.global ask_remember_model
.global ask_encrypt_dispatch
.global ask_probe_dispatch
.global ask_run_prompt
.global current_model

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern fork_exec_wait
.extern write_bytes_path
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern sys_mkdir
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern strlen
.extern flag_live
.extern enc_gateway_on
.extern enc_key_path
.extern enc_key_loaded
.extern pick_ask_reply_ptr
# Use local msg_arrow for lengths — extern absolute msg_reply_len
# assembles as memory load from address 6 (SIGSEGV). Do not .extern equ.

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 64
.equ O_TRUNC, 512

.section .bss
.align 16
current_model:  .space 64
ask_prompt:     .space 4096
ask_reply:      .space 65536
ask_argv:       .space 128

.section .data

ask_bin:
    .ascii "./spark-ask-http\0"
probe_bin:
    .ascii "./spark-ask-probe\0"
flg_live_probe: .ascii "--live\0"
enc_bin:
    .ascii "./spark-enc-gateway\0"
msg_ask_probe:
    .ascii "[ask] probe "
msg_ask_probe_len = . - msg_ask_probe
msg_probe_fail:
    .ascii "error: spark-ask-probe failed"
    .ascii " (401=credential unavailable;"
    .ascii " no routing conclusion)\n"
msg_probe_fail_len = . - msg_probe_fail
ask_flag_model:
    .ascii "--model\0"
ask_flag_pf:
    .ascii "--prompt-file\0"
ask_flag_out:
    .ascii "--out\0"
ask_prompt_path:
    .ascii "/tmp/spark-ask-prompt.txt\0"
ask_out_path:
    .ascii "/tmp/spark-ask-out.txt\0"
ask_env_path:
    .ascii "/tmp/spark-ask-envelope.json\0"
ask_seal_reply:
    .ascii "/tmp/spark-ask-reply.envelope.json\0"
default_model:
    .ascii "fast\0"
flg_seal:       .ascii "seal\0"
flg_ask_proxy:  .ascii "ask-proxy\0"
flg_key:        .ascii "--key\0"
flg_in:         .ascii "--in\0"
flg_envelope:   .ascii "--envelope\0"
flg_seal_reply: .ascii "--seal-reply\0"
flg_dry:        .ascii "--dry\0"
flg_aad:        .ascii "--aad\0"
aad_ask:        .ascii "spark-ask\0"
outdir_out:     .ascii "out\0"
outdir_enc:     .ascii "out/encrypt\0"

msg_ask_live:
    .ascii "[ask] live "
msg_ask_live_len = . - msg_ask_live
msg_ask_enc:
    .ascii "[ask] encrypt-gateway "
msg_ask_enc_len = . - msg_ask_enc
msg_ask_run:
    .ascii "[ask] "
msg_ask_run_len = . - msg_ask_run
msg_arrow:
    .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_nl:
    .ascii "\n"
msg_fail:
    .ascii "error: spark-ask-http failed (check AI_GATEWAY_URL /"
    .ascii " OPENAI_API_KEY; 401=credential unavailable)\n"
msg_fail_len = . - msg_fail
msg_enc_fail:
    .ascii "error: encrypt-gateway ask-proxy failed\n"
msg_enc_fail_len = . - msg_enc_fail
msg_need_live:
    .ascii "error: internal ask_live without --live\n"
msg_need_live_len = . - msg_need_live
msg_need_key:
    .ascii "error: gateway encrypt on but no key loaded\n"
msg_need_key_len = . - msg_need_key

.section .text

# ------------------------------------------------------------
# ask_probe_dispatch: gateway probe credential dry/live check
# --dry (default / --dry-run): no network. --live: public tunnel.
# Exit 4 = credential unavailable (propagate).
# ------------------------------------------------------------
ask_probe_dispatch:
    push    rbx
    push    r12

    lea     rsi, [rip+msg_ask_probe]
    mov     rdx, msg_ask_probe_len
    call    write_stdout

    lea     rax, [rip+probe_bin]
    mov     [rip+ask_argv], rax
    cmp     qword ptr [rip+flag_live], 0
    jne     apd_live
    lea     rax, [rip+flg_dry]
    mov     [rip+ask_argv+8], rax
    jmp     apd_argv_done
apd_live:
    lea     rax, [rip+flg_live_probe]
    mov     [rip+ask_argv+8], rax
apd_argv_done:
    mov     qword ptr [rip+ask_argv+16], 0

    lea     rdi, [rip+probe_bin]
    lea     rsi, [rip+ask_argv]
    call    fork_exec_wait
    mov     r12, rax
    test    rax, rax
    jz      apd_ok

    lea     rsi, [rip+msg_probe_fail]
    mov     rdx, msg_probe_fail_len
    call    write_stdout
    mov     rdi, r12
    call    sys_exit

apd_ok:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    # short bind marker
    lea     rdi, [rip+ask_reply]
    mov     dword ptr [rdi], 0x626f7270   # 'prob'
    mov     dword ptr [rdi+4], 0x00006b65 # 'ek'
    lea     rax, [rip+ask_reply]
    mov     rcx, 5
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# ask_remember_model: caller guarantees plain `model <alias>`
# Copies first token after "model" into current_model.
# ------------------------------------------------------------
ask_remember_model:
    push    rbx
    lea     rbx, [rip+linebuf]
    mov     rsi, rbx
arm_skip_kw:
    mov     al, [rsi]
    test    al, al
    jz      arm_default
    cmp     al, ' '
    je      arm_ws
    cmp     al, '\t'
    je      arm_ws
    inc     rsi
    jmp     arm_skip_kw
arm_ws:
    mov     al, [rsi]
    cmp     al, ' '
    je      arm_ws_inc
    cmp     al, '\t'
    je      arm_ws_inc
    jmp     arm_tok
arm_ws_inc:
    inc     rsi
    jmp     arm_ws
arm_tok:
    cmp     byte ptr [rsi], 0
    je      arm_default
    lea     rdi, [rip+current_model]
    xor     rcx, rcx
arm_copy:
    mov     al, [rsi+rcx]
    cmp     al, 0
    je      arm_term
    cmp     al, ' '
    je      arm_term
    cmp     al, '\t'
    je      arm_term
    cmp     al, '\n'
    je      arm_term
    cmp     rcx, 62
    jge     arm_term
    mov     [rdi+rcx], al
    inc     rcx
    jmp     arm_copy
arm_term:
    mov     byte ptr [rdi+rcx], 0
    test    rcx, rcx
    jz      arm_default
    pop     rbx
    ret
arm_default:
    lea     rsi, [rip+default_model]
    lea     rdi, [rip+current_model]
    mov     rcx, 5
    rep movsb
    pop     rbx
    ret

# ------------------------------------------------------------
# ask_live_dispatch: live OpenAI-compatible ask via companion
# ------------------------------------------------------------
ask_live_dispatch:
    push    rbx
    push    r12
    push    r13

    cmp     qword ptr [rip+flag_live], 0
    jne     ald_go
    lea     rsi, [rip+msg_need_live]
    mov     rdx, msg_need_live_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ald_go:
    # ensure default model
    cmp     byte ptr [rip+current_model], 0
    jne     ald_have_model
    lea     rsi, [rip+default_model]
    lea     rdi, [rip+current_model]
    mov     rcx, 5
    rep movsb
ald_have_model:

    lea     rsi, [rip+msg_ask_live]
    mov     rdx, msg_ask_live_len
    call    write_stdout
    lea     rsi, [rip+current_model]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+current_model]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ald_empty
    # write prompt file
    mov     rsi, rax
    mov     rdx, rcx
    lea     rdi, [rip+ask_prompt_path]
    call    write_bytes_path
    # also print prompt echo
    lea     rdi, [rip+linebuf]
    call    extract_quote
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     ald_argv
ald_empty:
    lea     rdi, [rip+ask_prompt_path]
    lea     rsi, [rip+msg_nl]
    mov     rdx, 0
    call    write_bytes_path

ald_argv:
    lea     rax, [rip+ask_bin]
    mov     [rip+ask_argv], rax
    lea     rax, [rip+ask_flag_model]
    mov     [rip+ask_argv+8], rax
    lea     rax, [rip+current_model]
    mov     [rip+ask_argv+16], rax
    lea     rax, [rip+ask_flag_pf]
    mov     [rip+ask_argv+24], rax
    lea     rax, [rip+ask_prompt_path]
    mov     [rip+ask_argv+32], rax
    lea     rax, [rip+ask_flag_out]
    mov     [rip+ask_argv+40], rax
    lea     rax, [rip+ask_out_path]
    mov     [rip+ask_argv+48], rax
    mov     qword ptr [rip+ask_argv+56], 0

    lea     rdi, [rip+ask_bin]
    lea     rsi, [rip+ask_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     ald_fail_status

    # read out file
    lea     rdi, [rip+ask_out_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      ald_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+ask_reply]
    mov     rdx, 65535
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jle     ald_fail

    # trim trailing newlines from companion stdout
    lea     rbx, [rip+ask_reply]
ald_trim:
    cmp     r13, 0
    je      ald_trim_done
    lea     rsi, [rbx+r13]
    mov     al, [rsi-1]
    cmp     al, 10
    je      ald_trim_one
    cmp     al, 13
    jne     ald_trim_done
ald_trim_one:
    dec     r13
    jmp     ald_trim
ald_trim_done:

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ask_reply]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+ask_reply]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     r13
    pop     r12
    pop     rbx
    ret

ald_fail_status:
    mov     r12, rax                # child exit status
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, r12
    call    sys_exit

ald_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ------------------------------------------------------------
# ask_encrypt_dispatch: seal prompt → ask-proxy (decrypt at
# gateway → Bifrost when --live; --dry when offline)
# ------------------------------------------------------------
ask_encrypt_dispatch:
    push    rbx
    push    r12
    push    r13

    cmp     qword ptr [rip+enc_key_loaded], 0
    je      aed_need_key
    cmp     byte ptr [rip+enc_key_path], 0
    je      aed_need_key

    cmp     byte ptr [rip+current_model], 0
    jne     aed_have_model
    lea     rsi, [rip+default_model]
    lea     rdi, [rip+current_model]
    mov     rcx, 5
    rep movsb
aed_have_model:

    lea     rdi, [rip+outdir_out]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+outdir_enc]
    mov     rsi, 493
    call    sys_mkdir

    lea     rsi, [rip+msg_ask_enc]
    mov     rdx, msg_ask_enc_len
    call    write_stdout
    lea     rsi, [rip+current_model]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+current_model]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      aed_empty
    mov     rsi, rax
    mov     rdx, rcx
    lea     rdi, [rip+ask_prompt_path]
    call    write_bytes_path
    jmp     aed_seal
aed_empty:
    lea     rdi, [rip+ask_prompt_path]
    lea     rsi, [rip+msg_nl]
    mov     rdx, 0
    call    write_bytes_path

aed_seal:
    # Agent → gateway: seal plaintext into envelope
    lea     rax, [rip+enc_bin]
    mov     [rip+ask_argv], rax
    lea     rax, [rip+flg_seal]
    mov     [rip+ask_argv+8], rax
    lea     rax, [rip+flg_key]
    mov     [rip+ask_argv+16], rax
    lea     rax, [rip+enc_key_path]
    mov     [rip+ask_argv+24], rax
    lea     rax, [rip+flg_in]
    mov     [rip+ask_argv+32], rax
    lea     rax, [rip+ask_prompt_path]
    mov     [rip+ask_argv+40], rax
    lea     rax, [rip+ask_flag_out]
    mov     [rip+ask_argv+48], rax
    lea     rax, [rip+ask_env_path]
    mov     [rip+ask_argv+56], rax
    lea     rax, [rip+flg_aad]
    mov     [rip+ask_argv+64], rax
    lea     rax, [rip+aad_ask]
    mov     [rip+ask_argv+72], rax
    mov     qword ptr [rip+ask_argv+80], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+ask_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     aed_fail

    # Gateway: open envelope → model (or --dry)
    lea     rax, [rip+enc_bin]
    mov     [rip+ask_argv], rax
    lea     rax, [rip+flg_ask_proxy]
    mov     [rip+ask_argv+8], rax
    lea     rax, [rip+flg_key]
    mov     [rip+ask_argv+16], rax
    lea     rax, [rip+enc_key_path]
    mov     [rip+ask_argv+24], rax
    lea     rax, [rip+flg_envelope]
    mov     [rip+ask_argv+32], rax
    lea     rax, [rip+ask_env_path]
    mov     [rip+ask_argv+40], rax
    lea     rax, [rip+ask_flag_model]
    mov     [rip+ask_argv+48], rax
    lea     rax, [rip+current_model]
    mov     [rip+ask_argv+56], rax
    lea     rax, [rip+ask_flag_out]
    mov     [rip+ask_argv+64], rax
    lea     rax, [rip+ask_out_path]
    mov     [rip+ask_argv+72], rax
    lea     rax, [rip+flg_seal_reply]
    mov     [rip+ask_argv+80], rax
    lea     rax, [rip+ask_seal_reply]
    mov     [rip+ask_argv+88], rax

    cmp     qword ptr [rip+flag_live], 0
    jne     aed_live_proxy
    lea     rax, [rip+flg_dry]
    mov     [rip+ask_argv+96], rax
    mov     qword ptr [rip+ask_argv+104], 0
    jmp     aed_proxy_exec
aed_live_proxy:
    mov     qword ptr [rip+ask_argv+96], 0
aed_proxy_exec:
    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+ask_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     aed_fail

    lea     rdi, [rip+ask_out_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      aed_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+ask_reply]
    mov     rdx, 65535
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jle     aed_fail

    lea     rbx, [rip+ask_reply]
aed_trim:
    cmp     r13, 0
    je      aed_trim_done
    lea     rsi, [rbx+r13]
    mov     al, [rsi-1]
    cmp     al, 10
    je      aed_trim_one
    cmp     al, 13
    jne     aed_trim_done
aed_trim_one:
    dec     r13
    jmp     aed_trim
aed_trim_done:

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ask_reply]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+ask_reply]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     r13
    pop     r12
    pop     rbx
    ret

aed_need_key:
    lea     rsi, [rip+msg_need_key]
    mov     rdx, msg_need_key_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

aed_fail:
    lea     rsi, [rip+msg_enc_fail]
    mov     rdx, msg_enc_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ------------------------------------------------------------
# ask_run_prompt: rdi=prompt bytes, rsi=len
# Same path as language `ask`: dry → pick_ask_reply_ptr fixtures;
# live → spark-ask-http companion. No invented model replies.
# Caps at 4095. Sets last_val + bind_arrow. Leaves reply in ask_reply.
# ------------------------------------------------------------
ask_run_prompt:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                # src
    mov     r13, rsi                # len
    cmp     r13, 4095
    jle     arp_len_ok
    mov     r13, 4095
arp_len_ok:
    # copy into ask_prompt (NUL-term for picker)
    lea     rdi, [rip+ask_prompt]
    xor     rbx, rbx
arp_copy:
    cmp     rbx, r13
    jge     arp_term
    mov     al, [r12+rbx]
    mov     [rdi+rbx], al
    inc     rbx
    jmp     arp_copy
arp_term:
    mov     byte ptr [rdi+rbx], 0

    # ensure default model for live
    cmp     byte ptr [rip+current_model], 0
    jne     arp_have_model
    lea     rsi, [rip+default_model]
    lea     rdi, [rip+current_model]
    mov     rcx, 5
    rep movsb
arp_have_model:

    lea     rsi, [rip+msg_ask_run]
    mov     rdx, msg_ask_run_len
    call    write_stdout
    lea     rsi, [rip+ask_prompt]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    cmp     qword ptr [rip+flag_live], 0
    jne     arp_live

    # --- dry: real fixture picker (same as ask_dry) ---
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rdi, [rip+ask_prompt]
    call    pick_ask_reply_ptr
    mov     r14, rax
    mov     r13, rcx
    # stash into ask_reply for peers (AI panel)
    lea     rdi, [rip+ask_reply]
    xor     rbx, rbx
arp_stash:
    cmp     rbx, r13
    jge     arp_stash_done
    cmp     rbx, 65535
    jge     arp_stash_done
    mov     al, [r14+rbx]
    mov     [rdi+rbx], al
    inc     rbx
    jmp     arp_stash
arp_stash_done:
    mov     byte ptr [rdi+rbx], 0
    lea     rsi, [rip+ask_reply]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+ask_reply]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

arp_live:
    # write prompt file → companion (same as ask_live_dispatch)
    lea     rdi, [rip+ask_prompt_path]
    lea     rsi, [rip+ask_prompt]
    mov     rdx, r13
    call    write_bytes_path

    lea     rax, [rip+ask_bin]
    mov     [rip+ask_argv], rax
    lea     rax, [rip+ask_flag_model]
    mov     [rip+ask_argv+8], rax
    lea     rax, [rip+current_model]
    mov     [rip+ask_argv+16], rax
    lea     rax, [rip+ask_flag_pf]
    mov     [rip+ask_argv+24], rax
    lea     rax, [rip+ask_prompt_path]
    mov     [rip+ask_argv+32], rax
    lea     rax, [rip+ask_flag_out]
    mov     [rip+ask_argv+40], rax
    lea     rax, [rip+ask_out_path]
    mov     [rip+ask_argv+48], rax
    mov     qword ptr [rip+ask_argv+56], 0

    lea     rdi, [rip+ask_bin]
    lea     rsi, [rip+ask_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     arp_fail_status

    lea     rdi, [rip+ask_out_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      arp_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+ask_reply]
    mov     rdx, 65535
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jle     arp_fail

    lea     rbx, [rip+ask_reply]
arp_trim:
    cmp     r13, 0
    je      arp_trim_done
    lea     rsi, [rbx+r13]
    mov     al, [rsi-1]
    cmp     al, 10
    je      arp_trim_one
    cmp     al, 13
    jne     arp_trim_done
arp_trim_one:
    dec     r13
    jmp     arp_trim
arp_trim_done:
    mov     byte ptr [rbx+r13], 0

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+ask_reply]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+ask_reply]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

arp_fail_status:
    mov     r12, rax
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     rdi, r12
    call    sys_exit

arp_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
