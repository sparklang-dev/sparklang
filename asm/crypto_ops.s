# Spark crypto — keygen/load + encrypt seal/open via ./spark-enc-gateway
# Real AES-256-GCM envelopes (companion). No fake base64.
#
# Exports: crypto_ops_dispatch, encrypt_ops_dispatch,
#          enc_key_path, enc_gateway_on, enc_key_loaded
.intel_syntax noprefix
.global crypto_ops_dispatch
.global encrypt_ops_dispatch
.global enc_key_path
.global enc_gateway_on
.global enc_key_loaded

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern fork_exec_wait
.extern write_bytes_path
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern sys_mkdir
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern vars_get
.extern skip_ws
.extern skip_ws_from_rbx

.equ O_RDONLY, 0

.section .bss
.align 16
enc_key_path:   .space 512
enc_gateway_on: .space 8
enc_key_loaded: .space 8
enc_argv:       .space 128
enc_outbuf:     .space 4096
enc_blob_path:  .space 512
enc_pt_path:    .space 512
enc_name:       .space 64

.section .data
msg_crypto: .ascii "[crypto] "
msg_crypto_len = . - msg_crypto
msg_encrypt: .ascii "[encrypt] "
msg_encrypt_len = . - msg_encrypt
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_nl:     .ascii "\n"

msg_need_key:
    .ascii "error: encrypt requires crypto keygen or"
    .ascii " crypto load key first\n"
msg_need_key_len = . - msg_need_key
msg_need_blob:
    .ascii "error: encrypt open needs a bound blob path"
    .ascii " (from encrypt seal → blob)\n"
msg_need_blob_len = . - msg_need_blob
msg_fail:
    .ascii "error: spark-enc-gateway failed\n"
msg_fail_len = . - msg_fail
msg_enable_ok:
    .ascii "{\"op\":\"gateway_enable\",\"key_loaded\":true}\n"
msg_enable_ok_len = . - msg_enable_ok
msg_bad_backend:
    .ascii "error: crypto backend expects openssl|af_alg\n"
msg_bad_backend_len = . - msg_bad_backend

needle_keygen:  .ascii "keygen\0"
needle_load:    .ascii "load\0"
needle_probe:   .ascii "probe\0"
needle_backend: .ascii "backend\0"
needle_af_alg:  .ascii "af_alg\0"
needle_openssl: .ascii "openssl\0"
needle_seal:    .ascii "seal\0"
needle_open:    .ascii "open\0"
needle_gateway: .ascii "gateway\0"
needle_enable:  .ascii "enable\0"
needle_text:    .ascii "text\0"

enc_bin:        .ascii "./spark-enc-gateway\0"
flg_keygen:     .ascii "keygen\0"
flg_probe:      .ascii "probe\0"
flg_backend:    .ascii "backend\0"
flg_set:        .ascii "--set\0"
flg_openssl:    .ascii "openssl\0"
flg_af_alg:     .ascii "af_alg\0"
flg_seal:       .ascii "seal\0"
flg_open:       .ascii "open\0"
flg_key:        .ascii "--key\0"
flg_out:        .ascii "--out\0"
flg_in:         .ascii "--in\0"
flg_text:       .ascii "--text\0"
flg_envelope:   .ascii "--envelope\0"
flg_aad:        .ascii "--aad\0"
aad_ask:        .ascii "spark-ask\0"

default_key:    .ascii "out/encrypt/spark.key\0"
default_blob:   .ascii "out/encrypt/seal.envelope.json\0"
default_pt:     .ascii "out/encrypt/open.pt\0"
outdir_enc:     .ascii "out\0"
outdir_enc2:    .ascii "out/encrypt\0"
pt_tmp:         .ascii "/tmp/spark-enc-seal-pt.txt\0"

.section .text

# ------------------------------------------------------------
crypto_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_crypto]
    mov     rdx, msg_crypto_len
    call    write_stdout

    lea     rdi, [rip+outdir_enc]
    mov     rsi, 493                 # 0755 out/
    call    sys_mkdir
    lea     rdi, [rip+outdir_enc2]
    mov     rsi, 448                 # 0700 out/encrypt/
    call    sys_mkdir

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_keygen]
    call    contains
    test    rax, rax
    jnz     do_keygen

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_load]
    call    contains
    test    rax, rax
    jnz     do_load

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_probe]
    call    contains
    test    rax, rax
    jnz     do_probe

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_backend]
    call    contains
    test    rax, rax
    jnz     do_backend

    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# --- crypto keygen -> key ---
do_keygen:
    lea     rsi, [rip+default_key]
    lea     rdi, [rip+enc_key_path]
    call    copy_path

    lea     rax, [rip+enc_bin]
    mov     [rip+enc_argv], rax
    lea     rax, [rip+flg_keygen]
    mov     [rip+enc_argv+8], rax
    lea     rax, [rip+flg_out]
    mov     [rip+enc_argv+16], rax
    lea     rax, [rip+enc_key_path]
    mov     [rip+enc_argv+24], rax
    mov     qword ptr [rip+enc_argv+32], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+enc_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     enc_fail

    mov     qword ptr [rip+enc_key_loaded], 1

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+enc_key_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+enc_key_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+enc_key_path]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+enc_key_path]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     crypto_done

# --- crypto load key "PATH" -> key ---
do_load:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      enc_fail
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+enc_key_path]
    xor     r13, r13
load_copy:
    cmp     r13, r12
    jge     load_done
    cmp     r13, 510
    jge     load_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     load_copy
load_done:
    mov     byte ptr [rdi+r13], 0
    # verify readable
    lea     rdi, [rip+enc_key_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      enc_fail
    mov     rdi, rax
    call    sys_close

    mov     qword ptr [rip+enc_key_loaded], 1

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+enc_key_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+enc_key_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+enc_key_path]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+enc_key_path]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     crypto_done

# --- crypto probe -> info (honest AF_ALG blacklist) ---
do_probe:
    lea     rax, [rip+enc_bin]
    mov     [rip+enc_argv], rax
    lea     rax, [rip+flg_probe]
    mov     [rip+enc_argv+8], rax
    mov     qword ptr [rip+enc_argv+16], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+enc_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     enc_fail

    # companion already printed JSON to stdout; bind path marker
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rdi, [rip+enc_outbuf]
    # stash short marker for bind
    mov     dword ptr [rdi], 0x626f7270   # 'prob'
    mov     dword ptr [rdi+4], 0x00006b65 # 'ek\0\0'
    lea     rax, [rip+enc_outbuf]
    mov     rcx, 5
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     crypto_done

# --- crypto backend openssl|af_alg (fail-loud if AF_ALG unusable) ---
do_backend:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_af_alg]
    call    contains
    test    rax, rax
    jnz     backend_afalg

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_openssl]
    call    contains
    test    rax, rax
    jnz     backend_openssl

    lea     rsi, [rip+msg_bad_backend]
    mov     rdx, msg_bad_backend_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

backend_openssl:
    lea     r12, [rip+flg_openssl]
    jmp     backend_run
backend_afalg:
    lea     r12, [rip+flg_af_alg]
backend_run:
    lea     rax, [rip+enc_bin]
    mov     [rip+enc_argv], rax
    lea     rax, [rip+flg_backend]
    mov     [rip+enc_argv+8], rax
    lea     rax, [rip+flg_set]
    mov     [rip+enc_argv+16], rax
    mov     [rip+enc_argv+24], r12
    mov     qword ptr [rip+enc_argv+32], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+enc_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     enc_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    mov     rsi, r12
    call    strlen
    mov     rdx, rax
    mov     rsi, r12
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    mov     rax, r12
    call    strlen
    mov     rcx, rax
    mov     rax, r12
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     crypto_done

crypto_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
encrypt_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_encrypt]
    mov     rdx, msg_encrypt_len
    call    write_stdout

    lea     rdi, [rip+outdir_enc]
    mov     rsi, 493                 # 0755 out/
    call    sys_mkdir
    lea     rdi, [rip+outdir_enc2]
    mov     rsi, 448                 # 0700 out/encrypt/
    call    sys_mkdir

    # Match verb AFTER "encrypt " only — never scan quoted payload
    # (e.g. seal text "... until gateway" must not hit gateway).
    lea     rbx, [rip+linebuf]
    call    skip_ws_from_rbx
    mov     rbx, rax
    # skip "encrypt"
    add     rbx, 7
    call    skip_ws_from_rbx
    mov     rbx, rax

    mov     rsi, rbx
    lea     rdi, [rip+needle_gateway]
    mov     rdx, 7
    call    enc_kw_match
    test    rax, rax
    jnz     do_enc_gateway_enable

    mov     rsi, rbx
    lea     rdi, [rip+needle_seal]
    mov     rdx, 4
    call    enc_kw_match
    test    rax, rax
    jnz     do_seal

    mov     rsi, rbx
    lea     rdi, [rip+needle_open]
    mov     rdx, 4
    call    enc_kw_match
    test    rax, rax
    jnz     do_open_env

    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# encrypt gateway enable [key]
do_enc_gateway_enable:
    cmp     qword ptr [rip+enc_key_loaded], 0
    jne     ege_ok
    cmp     byte ptr [rip+enc_key_path], 0
    jne     ege_ok
    lea     rsi, [rip+msg_need_key]
    mov     rdx, msg_need_key_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
ege_ok:
    mov     qword ptr [rip+enc_key_loaded], 1
    mov     qword ptr [rip+enc_gateway_on], 1
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+msg_enable_ok]
    mov     rdx, msg_enable_ok_len
    call    write_stdout
    lea     rax, [rip+msg_enable_ok]
    mov     rcx, msg_enable_ok_len
    dec     rcx                    # drop trailing nl for bind
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     encrypt_done

# encrypt seal text "..." -> blob
do_seal:
    cmp     qword ptr [rip+enc_key_loaded], 0
    jne     seal_have_key
    cmp     byte ptr [rip+enc_key_path], 0
    je      need_key_err
seal_have_key:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      enc_fail
    # write plaintext temp
    mov     rsi, rax
    mov     rdx, rcx
    lea     rdi, [rip+pt_tmp]
    call    write_bytes_path

    lea     rsi, [rip+default_blob]
    lea     rdi, [rip+enc_blob_path]
    call    copy_path

    lea     rax, [rip+enc_bin]
    mov     [rip+enc_argv], rax
    lea     rax, [rip+flg_seal]
    mov     [rip+enc_argv+8], rax
    lea     rax, [rip+flg_key]
    mov     [rip+enc_argv+16], rax
    lea     rax, [rip+enc_key_path]
    mov     [rip+enc_argv+24], rax
    lea     rax, [rip+flg_in]
    mov     [rip+enc_argv+32], rax
    lea     rax, [rip+pt_tmp]
    mov     [rip+enc_argv+40], rax
    lea     rax, [rip+flg_out]
    mov     [rip+enc_argv+48], rax
    lea     rax, [rip+enc_blob_path]
    mov     [rip+enc_argv+56], rax
    lea     rax, [rip+flg_aad]
    mov     [rip+enc_argv+64], rax
    lea     rax, [rip+aad_ask]
    mov     [rip+enc_argv+72], rax
    mov     qword ptr [rip+enc_argv+80], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+enc_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     enc_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+enc_blob_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+enc_blob_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+enc_blob_path]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+enc_blob_path]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     encrypt_done

# encrypt open blob -> text  (blob = var name or path quote)
do_open_env:
    cmp     qword ptr [rip+enc_key_loaded], 0
    je      need_key_err

    # prefer quoted path; else token after "open"
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jnz     open_from_quote

    # parse name after "open "
    lea     rbx, [rip+linebuf]
open_find:
    cmp     byte ptr [rbx], 0
    je      need_blob_err
    cmp     dword ptr [rbx], 0x6e65706f  # 'o''p''e''n' little-endian
    je      open_after_kw
    inc     rbx
    jmp     open_find
open_after_kw:
    add     rbx, 4
    call    skip_ws_from_rbx
    mov     rbx, rax
    lea     rdi, [rip+enc_name]
    xor     rcx, rcx
open_name:
    mov     al, [rbx+rcx]
    cmp     al, 0
    je      open_name_done
    cmp     al, ' '
    je      open_name_done
    cmp     al, '-'
    je      open_name_done
    cmp     rcx, 62
    jge     open_name_done
    mov     [rdi+rcx], al
    inc     rcx
    jmp     open_name
open_name_done:
    mov     byte ptr [rdi+rcx], 0
    test    rcx, rcx
    jz      need_blob_err
    lea     rdi, [rip+enc_name]
    call    vars_get
    test    rax, rax
    jz      need_blob_err
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+enc_blob_path]
    xor     r13, r13
open_vcopy:
    cmp     r13, r12
    jge     open_vdone
    cmp     r13, 510
    jge     open_vdone
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     open_vcopy
open_vdone:
    mov     byte ptr [rdi+r13], 0
    jmp     open_run

open_from_quote:
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+enc_blob_path]
    xor     r13, r13
open_qcopy:
    cmp     r13, r12
    jge     open_qdone
    cmp     r13, 510
    jge     open_qdone
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     open_qcopy
open_qdone:
    mov     byte ptr [rdi+r13], 0

open_run:
    lea     rsi, [rip+default_pt]
    lea     rdi, [rip+enc_pt_path]
    call    copy_path

    lea     rax, [rip+enc_bin]
    mov     [rip+enc_argv], rax
    lea     rax, [rip+flg_open]
    mov     [rip+enc_argv+8], rax
    lea     rax, [rip+flg_key]
    mov     [rip+enc_argv+16], rax
    lea     rax, [rip+enc_key_path]
    mov     [rip+enc_argv+24], rax
    lea     rax, [rip+flg_envelope]
    mov     [rip+enc_argv+32], rax
    lea     rax, [rip+enc_blob_path]
    mov     [rip+enc_argv+40], rax
    lea     rax, [rip+flg_out]
    mov     [rip+enc_argv+48], rax
    lea     rax, [rip+enc_pt_path]
    mov     [rip+enc_argv+56], rax
    mov     qword ptr [rip+enc_argv+64], 0

    lea     rdi, [rip+enc_bin]
    lea     rsi, [rip+enc_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     enc_fail

    # read plaintext into enc_outbuf for bind
    lea     rdi, [rip+enc_pt_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      enc_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+enc_outbuf]
    mov     rdx, 4095
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jl      enc_fail
    lea     rax, [rip+enc_outbuf]
    mov     byte ptr [rax+r13], 0

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+enc_outbuf]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rax, [rip+enc_outbuf]
    mov     rcx, r13
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     encrypt_done

need_key_err:
    lea     rsi, [rip+msg_need_key]
    mov     rdx, msg_need_key_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

need_blob_err:
    lea     rsi, [rip+msg_need_blob]
    mov     rdx, msg_need_blob_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

enc_fail:
    lea     rsi, [rip+msg_fail]
    mov     rdx, msg_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

encrypt_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# copy_path: rsi=src cstr → rdi=dst
copy_path:
    push    rcx
    xor     rcx, rcx
cp_loop:
    mov     al, [rsi+rcx]
    mov     [rdi+rcx], al
    test    al, al
    jz      cp_done
    inc     rcx
    cmp     rcx, 510
    jl      cp_loop
    mov     byte ptr [rdi+rcx], 0
cp_done:
    pop     rcx
    ret

# enc_kw_match: rsi=text rdi=kw rdx=len → rax=1 if prefix + boundary
enc_kw_match:
    push    rbx
    push    rcx
    mov     rbx, rdx
    xor     rcx, rcx
ekm_cmp:
    cmp     rcx, rbx
    jge     ekm_bound
    mov     al, [rsi+rcx]
    mov     ah, [rdi+rcx]
    cmp     al, ah
    jne     ekm_no
    inc     rcx
    jmp     ekm_cmp
ekm_bound:
    mov     al, [rsi+rbx]
    test    al, al
    jz      ekm_yes
    cmp     al, ' '
    je      ekm_yes
    cmp     al, '\t'
    je      ekm_yes
    cmp     al, '\n'
    je      ekm_yes
    jmp     ekm_no
ekm_yes:
    mov     rax, 1
    pop     rcx
    pop     rbx
    ret
ekm_no:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret
