# Spark engine B — HTTP(S) fetch for HTML bytes.
# Language: engine fetch "URL" -> body
#
# Policy (owner A+B style):
#   file:// / bare path → open/read (always; dry default)
#   http:// + --allow-net → AF_INET SOCK_STREAM GET (asm sockets)
#   http(s) without --allow-net → refuse, no dial
#   https:// + --allow-net → fork ./spark-engine-fetch-tls
#     (OpenSSL BIO companion; not TLS-in-asm; not Python)
#
# Hosts (http asm): IPv4 dotted-quad or "localhost"→127.0.0.1 (no DNS).
# Hosts (https companion): getaddrinfo via OpenSSL BIO (DNS OK).
# Exports body buffer for parse/layout lanes.
#
# Never PSTN. Never Python urllib.

.intel_syntax noprefix
.global engine_fetch_dispatch
.global engine_fetch_load
.global engine_fetch_buf
.global engine_fetch_len
.global engine_fetch_ok
.global engine_fetch_body_path

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_open
.extern sys_read
.extern sys_write
.extern sys_close
.extern sys_exit
.extern sys_mkdir
.extern flag_allow_net
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern msg_nl
.extern fork_exec_wait

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 64
.equ O_TRUNC, 512
.equ MODE_0755, 493
.equ MODE_0644, 420
.equ SYS_SOCKET, 41
.equ SYS_CONNECT, 42
.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ FETCH_CAP, 65536
.equ URL_CAP, 1024
.equ HOST_CAP, 64
.equ PATH_CAP, 512

.section .bss
.align 16
engine_fetch_buf:   .space FETCH_CAP
engine_fetch_len:   .space 8
engine_fetch_ok:    .space 8
url_buf:            .space URL_CAP
host_buf:           .space HOST_CAP
path_buf:           .space PATH_CAP
port_num:           .space 8
sockaddr:           .space 16
req_buf:            .space 1536
recv_tmp:           .space FETCH_CAP
json_buf:           .space 2048
dec_buf:            .space 32
body_out_path:      .space 64
tls_argv:           .space 64          # 8 pointers

.section .data
msg_ef:     .ascii "[engine.fetch] "
msg_ef_len = . - msg_ef
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_reply:  .ascii "  → "
msg_reply_len = . - msg_reply

needle_fetch:   .ascii "fetch\0"
pfx_file:       .ascii "file://"
pfx_file_len = 7
pfx_http:       .ascii "http://"
pfx_http_len = 7
pfx_https:      .ascii "https://"
pfx_https_len = 8
name_localhost: .ascii "localhost\0"
ip_loopback:    .ascii "127.0.0.1\0"

path_out:       .ascii "out\0"
path_engine:    .ascii "out/engine\0"
engine_fetch_body_path:
path_body:      .ascii "out/engine/body.bin\0"

msg_need_url:
    .ascii "error: engine fetch requires a quoted URL\n"
msg_need_url_len = . - msg_need_url
msg_need_fetch:
    .ascii "error: engine op must be fetch"
    .ascii " (engine fetch \"URL\")\n"
msg_need_fetch_len = . - msg_need_fetch
msg_block_remote:
    .ascii "error: engine fetch: remote http(s) blocked"
    .ascii " by default (no network dial).\n"
    .ascii "  Pass --allow-net for http:// (asm socket)"
    .ascii " or https:// (OpenSSL BIO companion),"
    .ascii " or use file:// / a local path.\n"
msg_block_remote_len = . - msg_block_remote
msg_https_block:
    .ascii "error: engine fetch: https blocked by default"
    .ascii " (no network dial).\n"
    .ascii "  Pass --allow-net to fork"
    .ascii " ./spark-engine-fetch-tls"
    .ascii " (OpenSSL BIO), or use file://\n"
msg_https_block_len = . - msg_https_block
msg_tls_fail:
    .ascii "error: engine fetch: spark-engine-fetch-tls"
    .ascii " failed (OpenSSL BIO)."
    .ascii " Build with make companions;"
    .ascii " check CA / URL / --allow-net.\n"
msg_tls_fail_len = . - msg_tls_fail
msg_open_fail:
    .ascii "error: engine fetch: cannot open local path\n"
msg_open_fail_len = . - msg_open_fail
msg_parse_fail:
    .ascii "error: engine fetch: bad URL"
    .ascii " (need file://, path, or http://IPv4)\n"
msg_parse_fail_len = . - msg_parse_fail
msg_sock_fail:
    .ascii "error: engine fetch: asm socket"
    .ascii " connect/read failed"
    .ascii " (prefer http://127.0.0.1)\n"
msg_sock_fail_len = . - msg_sock_fail
msg_too_big:
    .ascii "error: engine fetch: body exceeds buffer\n"
msg_too_big_len = . - msg_too_big

# JSON fragments (bytes filled via u64_dec)
json_file_pre:
    .ascii "{\"op\":\"engine.fetch\",\"ok\":true,"
    .ascii "\"source\":\"file\",\"scheme\":\"file\","
    .ascii "\"fetched\":false,\"transport\":\"open\","
    .ascii "\"path\":\"out/engine/body.bin\","
    .ascii "\"bytes\":"
json_file_pre_len = . - json_file_pre
json_http_pre:
    .ascii "{\"op\":\"engine.fetch\",\"ok\":true,"
    .ascii "\"source\":\"http\",\"scheme\":\"http\","
    .ascii "\"fetched\":true,\"transport\":\"asm-socket\","
    .ascii "\"path\":\"out/engine/body.bin\","
    .ascii "\"bytes\":"
json_http_pre_len = . - json_http_pre
json_https_pre:
    .ascii "{\"op\":\"engine.fetch\",\"ok\":true,"
    .ascii "\"source\":\"https\",\"scheme\":\"https\","
    .ascii "\"fetched\":true,\"transport\":\"openssl-bio\","
    .ascii "\"path\":\"out/engine/body.bin\","
    .ascii "\"bytes\":"
json_https_pre_len = . - json_https_pre
json_mid_url:
    .ascii ",\"url\":\""
json_mid_url_len = . - json_mid_url
json_end:
    .ascii "\"}"
json_end_len = . - json_end

http_get:       .ascii "GET "
http_get_len = . - http_get
http_ver:       .ascii " HTTP/1.0\r\nHost: "
http_ver_len = . - http_ver
http_tail:      .ascii "\r\nConnection: close\r\n\r\n"
http_tail_len = . - http_tail
crlfcrlf:       .ascii "\r\n\r\n"
slash_default:  .ascii "/\0"

tls_bin:        .ascii "./spark-engine-fetch-tls\0"
tls_flag_url:   .ascii "--url\0"
tls_flag_out:   .ascii "--out\0"
tls_flag_net:   .ascii "--allow-net\0"
tls_flag_insec: .ascii "--insecure\0"
ip_loop_pfx:    .ascii "https://127.0.0.1"
ip_loop_pfx_len = 16
name_local_pfx: .ascii "https://localhost"
name_local_pfx_len = 17

.section .text

# ------------------------------------------------------------
# engine_fetch_dispatch — language line in linebuf
# ------------------------------------------------------------
engine_fetch_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     rsi, [rip+msg_ef]
    mov     rdx, msg_ef_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fetch]
    call    contains
    test    rax, rax
    jnz     efd_have_fetch
    lea     rsi, [rip+msg_need_fetch]
    mov     rdx, msg_need_fetch_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

efd_have_fetch:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jnz     efd_have_url
    lea     rsi, [rip+msg_need_url]
    mov     rdx, msg_need_url_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

efd_have_url:
    # copy URL into url_buf
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+url_buf]
    xor     r13, r13
efd_copy:
    cmp     r13, r12
    jge     efd_copied
    cmp     r13, URL_CAP-1
    jge     efd_copied
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     efd_copy
efd_copied:
    mov     byte ptr [rdi+r13], 0

    lea     rsi, [rip+url_buf]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rdi, [rip+url_buf]
    call    engine_fetch_load
    test    rax, rax
    jz      efd_ok
    # engine_fetch_load already printed error
    mov     edi, 1
    call    sys_exit

efd_ok:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+json_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+json_buf]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout

    lea     rsi, [rip+json_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+json_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# engine_fetch_load: rdi = URL cstr
# → rax=0 ok / 1 fail; fills engine_fetch_buf/len + json_buf
# ------------------------------------------------------------
engine_fetch_load:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi                    # URL
    mov     qword ptr [rip+engine_fetch_ok], 0
    mov     qword ptr [rip+engine_fetch_len], 0
    # keep URL in url_buf for JSON (API + language)
    lea     rdi, [rip+url_buf]
    mov     rsi, rbx
    call    strcpy_local

    # ensure out/engine
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_engine]
    mov     rsi, MODE_0755
    call    sys_mkdir

    # scheme detect
    mov     rsi, rbx
    lea     rdi, [rip+pfx_https]
    mov     rdx, pfx_https_len
    call    prefix_eq
    test    rax, rax
    jnz     efl_https

    mov     rsi, rbx
    lea     rdi, [rip+pfx_http]
    mov     rdx, pfx_http_len
    call    prefix_eq
    test    rax, rax
    jnz     efl_http

    mov     rsi, rbx
    lea     rdi, [rip+pfx_file]
    mov     rdx, pfx_file_len
    call    prefix_eq
    test    rax, rax
    jnz     efl_file_uri

    # bare path
    mov     rdi, rbx
    jmp     efl_open_path

efl_file_uri:
    lea     rdi, [rbx+pfx_file_len]
    jmp     efl_open_path

efl_https:
    cmp     qword ptr [rip+flag_allow_net], 1
    je      efl_https_go
    lea     rsi, [rip+msg_https_block]
    mov     rdx, msg_https_block_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_https_go:
    # argv: bin --url URL --out body.bin --allow-net [--insecure]
    lea     rax, [rip+tls_bin]
    mov     [rip+tls_argv], rax
    lea     rax, [rip+tls_flag_url]
    mov     [rip+tls_argv+8], rax
    lea     rax, [rip+url_buf]
    mov     [rip+tls_argv+16], rax
    lea     rax, [rip+tls_flag_out]
    mov     [rip+tls_argv+24], rax
    lea     rax, [rip+path_body]
    mov     [rip+tls_argv+32], rax
    lea     rax, [rip+tls_flag_net]
    mov     [rip+tls_argv+40], rax
    # loopback self-signed → --insecure (tests); else verify
    lea     rsi, [rip+url_buf]
    lea     rdi, [rip+ip_loop_pfx]
    mov     rdx, ip_loop_pfx_len
    call    prefix_eq
    test    rax, rax
    jnz     efl_tls_insec
    lea     rsi, [rip+url_buf]
    lea     rdi, [rip+name_local_pfx]
    mov     rdx, name_local_pfx_len
    call    prefix_eq
    test    rax, rax
    jnz     efl_tls_insec
    mov     qword ptr [rip+tls_argv+48], 0
    jmp     efl_tls_fork
efl_tls_insec:
    lea     rax, [rip+tls_flag_insec]
    mov     [rip+tls_argv+48], rax
    mov     qword ptr [rip+tls_argv+56], 0
efl_tls_fork:
    lea     rdi, [rip+tls_bin]
    lea     rsi, [rip+tls_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     efl_fail_tls
    # companion wrote body.bin — load into engine_fetch_buf
    lea     rdi, [rip+path_body]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      efl_fail_tls
    mov     r13, rax
    mov     rdi, r13
    lea     rsi, [rip+engine_fetch_buf]
    mov     rdx, FETCH_CAP-1
    call    sys_read
    cmp     rax, 0
    jl      efl_fail_tls_close
    cmp     rax, FETCH_CAP-1
    jge     efl_too_big_close
    mov     qword ptr [rip+engine_fetch_len], rax
    lea     rdi, [rip+engine_fetch_buf]
    mov     byte ptr [rdi+rax], 0
    mov     rdi, r13
    call    sys_close
    mov     r15, 2                      # source=https
    call    emit_json
    mov     qword ptr [rip+engine_fetch_ok], 1
    xor     rax, rax
    jmp     efl_done

efl_fail_tls_close:
    mov     rdi, r13
    call    sys_close
efl_fail_tls:
    lea     rsi, [rip+msg_tls_fail]
    mov     rdx, msg_tls_fail_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_http:
    cmp     qword ptr [rip+flag_allow_net], 1
    je      efl_http_go
    lea     rsi, [rip+msg_block_remote]
    mov     rdx, msg_block_remote_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_http_go:
    mov     rdi, rbx
    call    http_fetch_asm
    test    rax, rax
    jnz     efl_fail_sock
    # write body + JSON
    call    write_body_out
    test    rax, rax
    jnz     efl_fail_open
    mov     r15, 1                      # source=http
    call    emit_json
    mov     qword ptr [rip+engine_fetch_ok], 1
    xor     rax, rax
    jmp     efl_done

efl_fail_sock:
    lea     rsi, [rip+msg_sock_fail]
    mov     rdx, msg_sock_fail_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_open_path:
    # rdi = filesystem path
    mov     r12, rdi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      efl_fail_open
    mov     r13, rax                    # fd
    mov     rdi, r13
    lea     rsi, [rip+engine_fetch_buf]
    mov     rdx, FETCH_CAP-1
    call    sys_read
    cmp     rax, 0
    jl      efl_fail_open_close
    cmp     rax, FETCH_CAP-1
    jge     efl_too_big_close
    mov     qword ptr [rip+engine_fetch_len], rax
    lea     rdi, [rip+engine_fetch_buf]
    mov     byte ptr [rdi+rax], 0
    mov     rdi, r13
    call    sys_close
    call    write_body_out
    test    rax, rax
    jnz     efl_fail_open
    xor     r15, r15                    # source=file
    call    emit_json
    mov     qword ptr [rip+engine_fetch_ok], 1
    xor     rax, rax
    jmp     efl_done

efl_too_big_close:
    mov     rdi, r13
    call    sys_close
    lea     rsi, [rip+msg_too_big]
    mov     rdx, msg_too_big_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_fail_open_close:
    mov     rdi, r13
    call    sys_close
efl_fail_open:
    lea     rsi, [rip+msg_open_fail]
    mov     rdx, msg_open_fail_len
    call    write_stdout
    mov     rax, 1
    jmp     efl_done

efl_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# write_body_out: engine_fetch_buf/len → out/engine/body.bin
# → rax=0 ok
write_body_out:
    push    rbx
    lea     rdi, [rip+path_body]
    lea     rsi, [rip+engine_fetch_buf]
    mov     rdx, qword ptr [rip+engine_fetch_len]
    call    write_bytes_path
    xor     rax, rax
    pop     rbx
    ret

# emit_json: r15=0 file / 1 http / 2 https; url in url_buf
emit_json:
    push    rbx
    push    r12
    # clear json
    mov     byte ptr [rip+json_buf], 0
    lea     rdi, [rip+json_buf]
    cmp     r15, 2
    je      ej_https
    test    r15, r15
    jnz     ej_http
    lea     rsi, [rip+json_file_pre]
    mov     rcx, json_file_pre_len
    jmp     ej_copy_pre
ej_http:
    lea     rsi, [rip+json_http_pre]
    mov     rcx, json_http_pre_len
    jmp     ej_copy_pre
ej_https:
    lea     rsi, [rip+json_https_pre]
    mov     rcx, json_https_pre_len
ej_copy_pre:
    call    memcpy_rcx
    mov     byte ptr [rdi], 0
    # append decimal bytes
    mov     rax, qword ptr [rip+engine_fetch_len]
    lea     rdi, [rip+dec_buf]
    call    u64_dec
    mov     r12, rax
    lea     rdi, [rip+json_buf]
    call    strlen_rdi
    lea     rdi, [rip+json_buf]
    add     rdi, rax
    lea     rsi, [rip+dec_buf]
    mov     rcx, r12
    call    memcpy_rcx
    mov     byte ptr [rdi], 0
    # ,"url":"
    lea     rdi, [rip+json_buf]
    call    strlen_rdi
    lea     rdi, [rip+json_buf]
    add     rdi, rax
    lea     rsi, [rip+json_mid_url]
    mov     rcx, json_mid_url_len
    call    memcpy_rcx
    mov     byte ptr [rdi], 0
    # url bytes (fixtures — no JSON escape)
    lea     rdi, [rip+json_buf]
    call    strlen_rdi
    lea     rdi, [rip+json_buf]
    add     rdi, rax
    lea     rsi, [rip+url_buf]
    call    strcpy_local
    # overwrite NUL with "}
    dec     rdi
    lea     rsi, [rip+json_end]
    mov     rcx, json_end_len
    call    memcpy_rcx
    mov     byte ptr [rdi], 0
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# http_fetch_asm: rdi = full http:// URL
# → rax=0 ok (body in engine_fetch_buf); 1 fail
# ------------------------------------------------------------
http_fetch_asm:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    # skip "http://"
    add     rbx, pfx_http_len

    # parse host into host_buf until : / or end
    lea     rdi, [rip+host_buf]
    xor     rcx, rcx
hf_host:
    mov     al, [rbx]
    test    al, al
    jz      hf_host_done
    cmp     al, ':'
    je      hf_host_done
    cmp     al, '/'
    je      hf_host_done
    cmp     rcx, HOST_CAP-1
    jge     hf_fail
    mov     [rdi+rcx], al
    inc     rcx
    inc     rbx
    jmp     hf_host
hf_host_done:
    mov     byte ptr [rdi+rcx], 0
    test    rcx, rcx
    jz      hf_fail

    # default port 80
    mov     qword ptr [rip+port_num], 80
    cmp     byte ptr [rbx], ':'
    jne     hf_path
    inc     rbx
    xor     rax, rax
hf_port:
    mov     cl, [rbx]
    cmp     cl, '0'
    jb      hf_port_done
    cmp     cl, '9'
    ja      hf_port_done
    imul    rax, rax, 10
    movzx   edx, cl
    sub     edx, '0'
    add     rax, rdx
    inc     rbx
    jmp     hf_port
hf_port_done:
    test    rax, rax
    jz      hf_fail
    cmp     rax, 65535
    ja      hf_fail
    mov     qword ptr [rip+port_num], rax

hf_path:
    lea     rdi, [rip+path_buf]
    cmp     byte ptr [rbx], '/'
    je      hf_copy_path
    # no path → /
    mov     word ptr [rdi], '/'
    jmp     hf_path_ok
hf_copy_path:
    xor     rcx, rcx
hf_pc:
    mov     al, [rbx]
    test    al, al
    jz      hf_pc_done
    cmp     rcx, PATH_CAP-1
    jge     hf_pc_done
    mov     [rdi+rcx], al
    inc     rcx
    inc     rbx
    jmp     hf_pc
hf_pc_done:
    mov     byte ptr [rdi+rcx], 0
hf_path_ok:

    # localhost → 127.0.0.1
    lea     rsi, [rip+host_buf]
    lea     rdi, [rip+name_localhost]
    call    streq_local
    test    rax, rax
    jz      hf_parse_ip
    lea     rsi, [rip+ip_loopback]
    lea     rdi, [rip+host_buf]
    call    strcpy_local

hf_parse_ip:
    lea     rdi, [rip+host_buf]
    call    parse_ipv4
    test    rax, rax
    js      hf_fail
    mov     r12d, eax                   # network-order addr

    # build sockaddr_in
    lea     rdi, [rip+sockaddr]
    xor     eax, eax
    mov     rcx, 2
    rep     stosq
    lea     rdi, [rip+sockaddr]
    mov     word ptr [rdi], AF_INET
    mov     rax, qword ptr [rip+port_num]
    # htons
    mov     rdx, rax
    and     rax, 0xff
    shl     rax, 8
    shr     rdx, 8
    and     rdx, 0xff
    or      rax, rdx
    mov     word ptr [rdi+2], ax
    # r12 holds network-order value (0x7f000001 for 127.0.0.1);
    # bswap so LE store yields bytes 7f 00 00 01 on the wire.
    mov     eax, r12d
    bswap   eax
    mov     dword ptr [rdi+4], eax

    # socket
    mov     eax, SYS_SOCKET
    mov     edi, AF_INET
    mov     esi, SOCK_STREAM
    xor     edx, edx
    syscall
    cmp     rax, 0
    jl      hf_fail
    mov     r13, rax                    # fd

    # connect
    mov     eax, SYS_CONNECT
    mov     rdi, r13
    lea     rsi, [rip+sockaddr]
    mov     rdx, 16
    syscall
    cmp     rax, 0
    jl      hf_fail_fd

    # build request
    lea     rdi, [rip+req_buf]
    lea     rsi, [rip+http_get]
    mov     rcx, http_get_len
    call    memcpy_rcx
    lea     rsi, [rip+path_buf]
    call    strcpy_local
    # append ver+host
    lea     rdi, [rip+req_buf]
    call    strlen_rdi
    lea     rdi, [rip+req_buf]
    add     rdi, rax
    lea     rsi, [rip+http_ver]
    mov     rcx, http_ver_len
    call    memcpy_rcx
    lea     rsi, [rip+host_buf]
    call    strcpy_local
    # if non-80, append :port
    cmp     qword ptr [rip+port_num], 80
    je      hf_req_tail
    lea     rdi, [rip+req_buf]
    call    strlen_rdi
    lea     rdi, [rip+req_buf]
    add     rdi, rax
    mov     byte ptr [rdi], ':'
    inc     rdi
    mov     rax, qword ptr [rip+port_num]
    push    rdi
    lea     rdi, [rip+dec_buf]
    call    u64_dec
    mov     rcx, rax
    pop     rdi
    lea     rsi, [rip+dec_buf]
    call    memcpy_rcx
    mov     byte ptr [rdi], 0
hf_req_tail:
    lea     rdi, [rip+req_buf]
    call    strlen_rdi
    lea     rdi, [rip+req_buf]
    add     rdi, rax
    lea     rsi, [rip+http_tail]
    mov     rcx, http_tail_len
    call    memcpy_rcx
    mov     byte ptr [rdi], 0

    # write request
    lea     rsi, [rip+req_buf]
    call    strlen
    mov     rdx, rax
    mov     rdi, r13
    lea     rsi, [rip+req_buf]
    call    sys_write
    cmp     rax, 0
    jl      hf_fail_fd

    # read response into recv_tmp
    xor     r14, r14
hf_read:
    cmp     r14, FETCH_CAP-1
    jge     hf_read_done
    mov     rdi, r13
    lea     rsi, [rip+recv_tmp]
    add     rsi, r14
    mov     rdx, FETCH_CAP-1
    sub     rdx, r14
    call    sys_read
    cmp     rax, 0
    jle     hf_read_done
    add     r14, rax
    jmp     hf_read
hf_read_done:
    mov     rdi, r13
    call    sys_close
    lea     rdi, [rip+recv_tmp]
    mov     byte ptr [rdi+r14], 0

    # find \r\n\r\n
    lea     rdi, [rip+recv_tmp]
    mov     rcx, r14
    call    find_header_end
    test    rax, rax
    jz      hf_no_hdr
    # rax = pointer to body start
    mov     rsi, rax
    lea     rdx, [rip+recv_tmp]
    add     rdx, r14
    sub     rdx, rsi                    # body len
    jmp     hf_copy_body
hf_no_hdr:
    lea     rsi, [rip+recv_tmp]
    mov     rdx, r14
hf_copy_body:
    cmp     rdx, FETCH_CAP-1
    jg      hf_fail
    mov     qword ptr [rip+engine_fetch_len], rdx
    lea     rdi, [rip+engine_fetch_buf]
    mov     rcx, rdx
    call    memcpy_rcx
    mov     rax, qword ptr [rip+engine_fetch_len]
    lea     rdi, [rip+engine_fetch_buf]
    mov     byte ptr [rdi+rax], 0
    xor     rax, rax
    jmp     hf_done

hf_fail_fd:
    mov     rdi, r13
    call    sys_close
hf_fail:
    mov     rax, 1
hf_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# find_header_end: rdi=buf rcx=len → rax=body ptr or 0
find_header_end:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rcx
    xor     rcx, rcx
fhe_loop:
    lea     rax, [rcx+3]
    cmp     rax, r12
    jae     fhe_no
    cmp     byte ptr [rbx+rcx], 13
    jne     fhe_next
    cmp     byte ptr [rbx+rcx+1], 10
    jne     fhe_next
    cmp     byte ptr [rbx+rcx+2], 13
    jne     fhe_next
    cmp     byte ptr [rbx+rcx+3], 10
    jne     fhe_next
    lea     rax, [rbx+rcx+4]
    pop     r12
    pop     rbx
    ret
fhe_next:
    inc     rcx
    jmp     fhe_loop
fhe_no:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

# parse_ipv4: rdi=cstr → eax=network-order addr, or rax=-1
parse_ipv4:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     r12, r12                    # result
    xor     r13, r13                    # octet index
pi_oct:
    cmp     r13, 4
    jge     pi_ok
    xor     eax, eax
pi_dig:
    mov     cl, [rbx]
    cmp     cl, '0'
    jb      pi_sep
    cmp     cl, '9'
    ja      pi_sep
    imul    eax, eax, 10
    movzx   edx, cl
    sub     edx, '0'
    add     eax, edx
    cmp     eax, 255
    ja      pi_bad
    inc     rbx
    jmp     pi_dig
pi_sep:
    # shift into network-order (big-endian in register, store LE mem)
    shl     r12, 8
    or      r12, rax
    inc     r13
    cmp     r13, 4
    je      pi_ok
    cmp     byte ptr [rbx], '.'
    jne     pi_bad
    inc     rbx
    jmp     pi_oct
pi_ok:
    cmp     byte ptr [rbx], 0
    jne     pi_bad
    mov     eax, r12d
    # r12 built as big-endian value in register; on LE store dword
    # bytes are already in network order in the low 32 bits if we
    # shifted left each time — e.g. 127.0.0.1 → 0x7f000001. Good.
    pop     r13
    pop     r12
    pop     rbx
    ret
pi_bad:
    mov     rax, -1
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
# prefix_eq: rsi=text rdi=pfx rdx=len → rax=1 if match
prefix_eq:
    push    rbx
    push    rcx
    xor     rcx, rcx
pe_loop:
    cmp     rcx, rdx
    jge     pe_yes
    mov     al, [rsi+rcx]
    mov     bl, [rdi+rcx]
    cmp     al, bl
    jne     pe_no
    inc     rcx
    jmp     pe_loop
pe_yes:
    mov     rax, 1
    pop     rcx
    pop     rbx
    ret
pe_no:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret

# streq_local: rsi=a rdi=b → rax=1 if equal
streq_local:
    push    rbx
sl_loop:
    mov     al, [rsi]
    mov     bl, [rdi]
    cmp     al, bl
    jne     sl_no
    test    al, al
    jz      sl_yes
    inc     rsi
    inc     rdi
    jmp     sl_loop
sl_yes:
    mov     rax, 1
    pop     rbx
    ret
sl_no:
    xor     rax, rax
    pop     rbx
    ret

# strcpy_local: rdi=dst rsi=src (null-term)
strcpy_local:
    push    rax
sc_l:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     sc_l
    pop     rax
    ret

# memcpy_rcx: rdi=dst rsi=src rcx=len; advances rdi by len
memcpy_rcx:
    push    rax
    push    rcx
mc_loop:
    test    rcx, rcx
    jz      mc_done
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     mc_loop
mc_done:
    pop     rcx
    pop     rax
    ret

# strlen_rdi: rdi=cstr → rax=len (does not clobber other)
strlen_rdi:
    push    rdi
    xor     rax, rax
srd_loop:
    cmp     byte ptr [rdi], 0
    je      srd_done
    inc     rax
    inc     rdi
    jmp     srd_loop
srd_done:
    pop     rdi
    ret

# u64_dec: rax=value, rdi=buf → writes digits, rax=len, NUL terminated
u64_dec:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    mov     rsi, rdi                    # start
    test    rax, rax
    jnz     ud_go
    mov     byte ptr [rdi], '0'
    mov     byte ptr [rdi+1], 0
    mov     rax, 1
    jmp     ud_done
ud_go:
    lea     rbx, [rdi+30]
    mov     byte ptr [rbx], 0
    mov     rcx, 10
ud_loop:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    rax, rax
    jnz     ud_loop
    # copy to start
    mov     rdi, rsi
ud_copy:
    mov     al, [rbx]
    mov     [rdi], al
    inc     rbx
    inc     rdi
    test    al, al
    jnz     ud_copy
    # len
    mov     rdi, rsi
    call    strlen_rdi
ud_done:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
