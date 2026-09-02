# Spark network — asm syscalls. open+analyze parse pcap bytes.
# Live capture: AF_PACKET via ./spark-net-capture when
# --allow-net-capture is set. Dry-run without flag uses fixture.
.intel_syntax noprefix
.global network_ops_dispatch

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern sys_mkdir
.extern flag_allow_net_capture
.extern fork_exec_wait

.equ O_RDONLY, 0
.equ SYS_FORK, 57
.equ SYS_EXECVE, 59
.equ SYS_WAIT4, 61

.section .bss
.align 16
pcap_path:      .space 512
pcap_have:      .space 8
pcap_buf:       .space 8192
pcap_len:       .space 8
dns_name:       .space 256
iface_buf:      .space 64
cap_argv:       .space 80
dur_buf:        .space 16

.section .data
msg_net:    .ascii "[network] "
msg_net_len = . - msg_net
msg_nl:     .ascii "\n"
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_analyze_need_open:
    .ascii "error: network analyze requires successful"
    .ascii " network open first\n"
msg_analyze_need_open_len = . - msg_analyze_need_open
msg_cap_need_flag:
    .ascii "error: live network capture requires"
    .ascii " --allow-net-capture (and CAP_NET_RAW)."
    .ascii " Dry path uses fixture — see docs.\n"
msg_cap_need_flag_len = . - msg_cap_need_flag
msg_cap_fail:
    .ascii "error: spark-net-capture failed"
    .ascii " (need CAP_NET_RAW / setcap / root?)\n"
msg_cap_fail_len = . - msg_cap_fail
msg_cap_miss:
    .ascii "error: CAP_NET_RAW unavailable"
    .ascii " (exit 4). Probe: ./spark-net-capture --probe"
    .ascii " or: network capture probe\n"
msg_cap_miss_len = . - msg_cap_miss

needle_capture: .ascii "capture\0"
needle_analyze: .ascii "analyze\0"
needle_explain: .ascii "explain\0"
needle_iface:   .ascii "interface\0"
needle_dur:     .ascii "duration\0"
needle_probe:   .ascii "probe\0"

fixture_pcap:
    .ascii "examples/fixtures/sample.pcap\0"
cap_out_path:
    .ascii "out/capture.pcap\0"
outdir_out:
    .ascii "out\0"
cap_bin:
    .ascii "./spark-net-capture\0"
cap_arg0:
    .ascii "spark-net-capture\0"
cap_probe_flag:
    .ascii "--probe\0"
cap_iface_flag:
    .ascii "--iface\0"
cap_dur_flag:
    .ascii "--duration\0"
cap_out_flag:
    .ascii "--out\0"
default_iface:
    .ascii "lo\0"
default_dur:
    .ascii "2\0"

dry_cap_json:
    .ascii "{\"op\":\"capture\",\"claimed\":false,"
    .ascii "\"path\":\"examples/fixtures/sample.pcap\","
    .ascii "\"note\":\"dry-run fixture; pass --allow-net-capture"
    .ascii " for live AF_PACKET (needs CAP_NET_RAW);"
    .ascii " probe: network capture probe /"
    .ascii " ./spark-net-capture --probe\"}"
dry_cap_json_len = . - dry_cap_json

dry_open_ok:
    .ascii "{\"op\":\"open\",\"ok\":true,\"format\":\"pcap\","
    .ascii "\"magic\":\"0xa1b2c3d4\",\"path\":\""
dry_open_ok_len = . - dry_open_ok
sfx_q:      .ascii "\"}"
sfx_q_len = . - sfx_q
dry_open_fail:
    .ascii "{\"op\":\"open\",\"ok\":false,"
    .ascii "\"error\":\"cannot open or not pcap magic\"}"
dry_open_fail_len = . - dry_open_fail

ana_pre:
    .ascii "{\"op\":\"analyze\",\"byte_parsed\":true,"
    .ascii "\"link\":\"Ethernet\",\"protocols\":[\"Ethernet\","
    .ascii "\"IPv4\",\"UDP\",\"DNS\"],\"dns_names\":[\""
ana_pre_len = . - ana_pre
ana_mid:
    .ascii "\"],\"note\":\"DNS QNAME extracted from pcap"
    .ascii " bytes after open\"}"
ana_mid_len = . - ana_mid
ana_nodns:
    .ascii "{\"op\":\"analyze\",\"byte_parsed\":true,"
    .ascii "\"dns_names\":[],\"note\":\"no DNS QNAME found"
    .ascii " in first packet\"}"
ana_nodns_len = . - ana_nodns

exp_pre:
    .ascii "{\"op\":\"explain\",\"byte_parsed\":true,"
    .ascii "\"text\":\"Parsed DNS QNAME from pcap bytes: "
exp_pre_len = . - exp_pre
exp_suf:
    .ascii "\"}"
exp_suf_len = . - exp_suf

.section .text

network_ops_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14

    lea     rsi, [rip+msg_net]
    mov     rdx, msg_net_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_explain]
    call    contains
    test    rax, rax
    jnz     do_explain

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_analyze]
    call    contains
    test    rax, rax
    jnz     do_analyze

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_capture]
    call    contains
    test    rax, rax
    jnz     do_capture

    jmp     do_open

# ---------- capture ----------
do_capture:
    # "network capture probe" — honest CAP check; no sniff claim
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_probe]
    call    contains
    test    rax, rax
    jnz     cap_probe

    cmp     qword ptr [rip+flag_allow_net_capture], 1
    je      cap_live
    # dry: claimed:false + open fixture for analyze
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_cap_json]
    mov     rdx, dry_cap_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    # load fixture into pcap state
    lea     rsi, [rip+fixture_pcap]
    lea     rdi, [rip+pcap_path]
    call    copy_cstr_n
    call    open_pcap_path
    jmp     net_done

# probe: fork ./spark-net-capture --probe (no --allow-net-capture)
cap_probe:
    lea     rax, [rip+cap_arg0]
    mov     [rip+cap_argv], rax
    lea     rax, [rip+cap_probe_flag]
    mov     [rip+cap_argv+8], rax
    mov     qword ptr [rip+cap_argv+16], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rdi, [rip+cap_bin]
    lea     rsi, [rip+cap_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     cap_probe_fail
    # companion already printed JSON on stdout
    jmp     net_done
cap_probe_fail:
    lea     rsi, [rip+msg_cap_fail]
    mov     rdx, msg_cap_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

cap_live:
    lea     rdi, [rip+outdir_out]
    mov     rsi, 493
    call    sys_mkdir
    # iface: quote after interface, else "lo"
    lea     rdi, [rip+iface_buf]
    mov     byte ptr [rdi], 'l'
    mov     byte ptr [rdi+1], 'o'
    mov     byte ptr [rdi+2], 0
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_iface]
    call    contains
    test    rax, rax
    jz      cap_dur_parse
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      cap_dur_parse
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+iface_buf]
    xor     r13, r13
cap_iface_copy:
    cmp     r13, r12
    jge     cap_iface_done
    cmp     r13, 62
    jge     cap_iface_done
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     cap_iface_copy
cap_iface_done:
    mov     byte ptr [rdi+r13], 0

cap_dur_parse:
    # duration: look for digit after "duration", default 2
    lea     rdi, [rip+dur_buf]
    mov     byte ptr [rdi], '2'
    mov     byte ptr [rdi+1], 0
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_dur]
    call    contains
    test    rax, rax
    jz      cap_argv_build
    # scan line for first digit run after "duration"
    lea     rsi, [rip+linebuf]
cap_find_d:
    cmp     byte ptr [rsi], 0
    je      cap_argv_build
    cmp     byte ptr [rsi], 'd'
    jne     cap_fd_inc
    # crude: if "duration" match via contains already true —
    # find first digit in line
    jmp     cap_scan_digit
cap_fd_inc:
    inc     rsi
    jmp     cap_find_d
cap_scan_digit:
    lea     rsi, [rip+linebuf]
cap_sd:
    mov     al, [rsi]
    test    al, al
    jz      cap_argv_build
    cmp     al, '0'
    jb      cap_sd_i
    cmp     al, '9'
    ja      cap_sd_i
    lea     rdi, [rip+dur_buf]
    xor     rcx, rcx
cap_sd_copy:
    mov     al, [rsi]
    cmp     al, '0'
    jb      cap_sd_term
    cmp     al, '9'
    ja      cap_sd_term
    cmp     rcx, 8
    jge     cap_sd_term
    mov     [rdi+rcx], al
    inc     rsi
    inc     rcx
    jmp     cap_sd_copy
cap_sd_term:
    mov     byte ptr [rdi+rcx], 0
    jmp     cap_argv_build
cap_sd_i:
    inc     rsi
    jmp     cap_sd

cap_argv_build:
    lea     rax, [rip+cap_arg0]
    mov     [rip+cap_argv], rax
    lea     rax, [rip+cap_iface_flag]
    mov     [rip+cap_argv+8], rax
    lea     rax, [rip+iface_buf]
    mov     [rip+cap_argv+16], rax
    lea     rax, [rip+cap_dur_flag]
    mov     [rip+cap_argv+24], rax
    lea     rax, [rip+dur_buf]
    mov     [rip+cap_argv+32], rax
    lea     rax, [rip+cap_out_flag]
    mov     [rip+cap_argv+40], rax
    lea     rax, [rip+cap_out_path]
    mov     [rip+cap_argv+48], rax
    mov     qword ptr [rip+cap_argv+56], 0

    lea     rdi, [rip+cap_bin]
    lea     rsi, [rip+cap_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     cap_live_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    # open captured pcap
    lea     rsi, [rip+cap_out_path]
    lea     rdi, [rip+pcap_path]
    call    copy_cstr_n
    call    open_pcap_path
    jmp     net_done

cap_live_fail:
    # rax = child exit status from fork_exec_wait
    cmp     rax, 4
    je      cap_live_cap_miss
    lea     rsi, [rip+msg_cap_fail]
    mov     rdx, msg_cap_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
cap_live_cap_miss:
    # companion already printed claimed:false JSON; add asm note
    lea     rsi, [rip+msg_cap_miss]
    mov     rdx, msg_cap_miss_len
    call    write_stdout
    mov     edi, 4
    call    sys_exit

# open_pcap_path: pcap_path already set; fill pcap_have/buf
open_pcap_path:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+pcap_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      opp_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+pcap_buf]
    mov     rdx, 8191
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 24
    jl      opp_fail
    cmp     byte ptr [rip+pcap_buf], 0xd4
    jne     opp_fail
    cmp     byte ptr [rip+pcap_buf+1], 0xc3
    jne     opp_fail
    cmp     byte ptr [rip+pcap_buf+2], 0xb2
    jne     opp_fail
    cmp     byte ptr [rip+pcap_buf+3], 0xa1
    jne     opp_fail
    mov     qword ptr [rip+pcap_have], 1
    mov     qword ptr [rip+pcap_len], r13
    call    extract_dns_from_buf
    lea     rsi, [rip+dry_open_ok]
    mov     rdx, dry_open_ok_len
    call    write_stdout
    lea     rsi, [rip+pcap_path]
    call    strlen_n
    mov     rdx, rax
    lea     rsi, [rip+pcap_path]
    call    write_stdout
    lea     rsi, [rip+sfx_q]
    mov     rdx, sfx_q_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret
opp_fail:
    mov     qword ptr [rip+pcap_have], 0
    lea     rsi, [rip+dry_open_fail]
    mov     rdx, dry_open_fail_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     r13
    pop     r12
    pop     rbx
    ret

copy_cstr_n:
    # rsi=src rdi=dst
ccn:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     ccn
    ret

do_open:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      open_fail
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+pcap_path]
    xor     r13, r13
copy_p:
    cmp     r13, r12
    jge     path_ok
    cmp     r13, 510
    jge     path_ok
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     copy_p
path_ok:
    mov     byte ptr [rdi+r13], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    call    open_pcap_path
    jmp     net_done

open_fail:
    mov     qword ptr [rip+pcap_have], 0
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_open_fail]
    mov     rdx, dry_open_fail_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     net_done

do_analyze:
    cmp     qword ptr [rip+pcap_have], 1
    jne     analyze_need_open
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    cmp     byte ptr [rip+dns_name], 0
    je      ana_empty
    lea     rsi, [rip+ana_pre]
    mov     rdx, ana_pre_len
    call    write_stdout
    lea     rsi, [rip+dns_name]
    call    strlen_n
    mov     rdx, rax
    lea     rsi, [rip+dns_name]
    call    write_stdout
    lea     rsi, [rip+ana_mid]
    mov     rdx, ana_mid_len
    call    write_stdout
    jmp     ana_nl
ana_empty:
    lea     rsi, [rip+ana_nodns]
    mov     rdx, ana_nodns_len
    call    write_stdout
ana_nl:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     net_done

analyze_need_open:
    lea     rsi, [rip+msg_analyze_need_open]
    mov     rdx, msg_analyze_need_open_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

do_explain:
    cmp     qword ptr [rip+pcap_have], 1
    jne     analyze_need_open
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+exp_pre]
    mov     rdx, exp_pre_len
    call    write_stdout
    cmp     byte ptr [rip+dns_name], 0
    je      exp_end
    lea     rsi, [rip+dns_name]
    call    strlen_n
    mov     rdx, rax
    lea     rsi, [rip+dns_name]
    call    write_stdout
exp_end:
    lea     rsi, [rip+exp_suf]
    mov     rdx, exp_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     net_done

extract_dns_from_buf:
    push    rbx
    push    r12
    mov     byte ptr [rip+dns_name], 0
    lea     rbx, [rip+pcap_buf]
    mov     r12, [rip+pcap_len]
    cmp     r12, 24+16+14+20+8+12
    jl      ed_done
    mov     eax, [rbx+32]
    lea     rdi, [rbx+40]
    cmp     byte ptr [rdi+12], 0x08
    jne     ed_done
    cmp     byte ptr [rdi+13], 0x00
    jne     ed_done
    lea     rsi, [rdi+14]
    movzx   eax, byte ptr [rsi]
    and     eax, 0x0f
    shl     eax, 2
    cmp     byte ptr [rsi+9], 17
    jne     ed_done
    add     rsi, rax
    add     rsi, 8
    add     rsi, 12
    lea     rdi, [rip+dns_name]
    xor     rcx, rcx
ed_lab:
    movzx   edx, byte ptr [rsi]
    test    edx, edx
    jz      ed_term
    cmp     edx, 63
    ja      ed_done
    inc     rsi
ed_ch:
    test    edx, edx
    jz      ed_dot
    mov     al, [rsi]
    mov     [rdi+rcx], al
    inc     rsi
    inc     rcx
    dec     edx
    cmp     rcx, 250
    jge     ed_term
    jmp     ed_ch
ed_dot:
    cmp     byte ptr [rsi], 0
    je      ed_term
    mov     byte ptr [rdi+rcx], '.'
    inc     rcx
    jmp     ed_lab
ed_term:
    mov     byte ptr [rdi+rcx], 0
ed_done:
    pop     r12
    pop     rbx
    ret

net_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

strlen_n:
    xor     rax, rax
sn:
    cmp     byte ptr [rsi+rax], 0
    je      sn_d
    inc     rax
    jmp     sn
sn_d:
    ret
