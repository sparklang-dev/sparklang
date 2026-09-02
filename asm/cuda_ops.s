# Spark CUDA — pure x86_64 asm syscalls to NVIDIA device nodes +
# NV_ESC_CARD_INFO / CHECK_VERSION ioctl (numbers from
# /usr/src/nvidia-*/common/inc/nv-ioctl-numbers.h as data).
# Prefer /dev/nvidia0. Never open /dev/nvidia2 (voice-only
# GPU, Device Minor 2 on this host) for compute tests.
#
# Exports: cuda_ops_dispatch, memory_ops_dispatch
.intel_syntax noprefix
.global cuda_ops_dispatch
.global memory_ops_dispatch

.extern linebuf
.extern write_stdout
.extern contains
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit
.extern sys_write
.extern pcie_ops_dispatch

.equ SYS_IOCTL, 16
.equ SYS_MMAP, 9
.equ SYS_MUNMAP, 11
.equ SYS_MLOCK, 149
.equ O_RDWR, 2
.equ O_RDONLY, 0
.equ PROT_READ, 1
.equ PROT_WRITE, 2
.equ MAP_PRIVATE, 2
.equ MAP_ANONYMOUS, 0x20

# _IOWR('F', 210, 72) CHECK_VERSION — discovered 0xc04846d2
.equ IOC_CHECK_VERSION, 0xc04846d2
# _IOWR('F', 200, 2304) CARD_INFO array[32] — 0xc90046c8
.equ IOC_CARD_INFO, 0xc90046c8
.equ CARD_STRIDE, 72
.equ CARD_MAX, 32
.equ OFF_VALID, 0
.equ OFF_BUS, 8
.equ OFF_FB_SIZE, 48
.equ OFF_MINOR, 56
# this host: minor 2 = reserved voice-only — never prefer
.equ VOICE_MINOR, 2

.section .bss
.align 16
dev_buf:        .space 256
ver_buf:        .space 72          # nv_ioctl_rm_api_version_t
cards_buf:      .space 2304        # 32 * 72
info_buf:       .space 2048
path_buf:       .space 256
num_buf:        .space 32
pin_sz:         .space 8
pin_ptr:        .space 8

.section .data
msg_cuda:   .ascii "[cuda] "
msg_cuda_len = . - msg_cuda
msg_mem:    .ascii "[memory] "
msg_mem_len = . - msg_mem
msg_nl:     .ascii "\n"
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow

path_ctl:   .ascii "/dev/nvidiactl\0"
path_n0:    .ascii "/dev/nvidia0\0"
path_uvm:   .ascii "/dev/nvidia-uvm\0"
# Do NOT open path_n2 in prefer/compute paths
path_n2:    .ascii "/dev/nvidia2\0"

path_ver:   .ascii "/proc/driver/nvidia/version\0"
path_params:.ascii "/proc/driver/nvidia/params\0"
# this host BDF information (UUID/model) — read-only procfs
path_i0:    .ascii "/proc/driver/nvidia/gpus/0000:01:00.0/information\0"
path_i1:    .ascii "/proc/driver/nvidia/gpus/0000:c3:00.0/information\0"
path_i2:    .ascii "/proc/driver/nvidia/gpus/0000:21:00.0/information\0"
path_w0:    .ascii "/sys/bus/pci/devices/0000:01:00.0/current_link_width\0"
path_w2:    .ascii "/sys/bus/pci/devices/0000:21:00.0/current_link_width\0"
path_w1:    .ascii "/sys/bus/pci/devices/0000:c3:00.0/current_link_width\0"

needle_probe:   .ascii "probe\0"
needle_memstat: .ascii "memstat\0"
needle_prefer:  .ascii "prefer\0"
needle_pcie:    .ascii "pcie\0"
needle_pin:     .ascii "pin\0"
# Spark `gpu N` = Device Minor N (/dev/nvidiaN), NOT nvidia-smi
# index. Live this host: minor 0=prefer, 1=secondary, 2=voice-only.
# Refuse only minor 2 / nvidia2 / gpu 2. Allow gpu 1 (secondary).
needle_gpu2:    .ascii "gpu 2\0"
needle_nvidia2: .ascii "nvidia2\0"
needle_minor2:  .ascii "minor 2\0"

err_open_ctl:
    .ascii "error: cannot open /dev/nvidiactl\n"
err_open_ctl_len = . - err_open_ctl
err_ioctl:
    .ascii "error: nvidia ioctl failed\n"
err_ioctl_len = . - err_ioctl
err_prefer_voice:
    .ascii "error: prefer refused — reserved voice GPU"
    .ascii " is voice-only (Device Minor 2"
    .ascii " /dev/nvidia2)\n"
err_prefer_voice_len = . - err_prefer_voice
err_mmap:
    .ascii "error: memory pin mmap failed\n"
err_mmap_len = . - err_mmap
err_mlock:
    .ascii "error: memory pin mlock failed errno="
err_mlock_len = . - err_mlock

json_probe_pre:
    .ascii "{\"op\":\"probe\",\"iface\":\"asm-dev+ioctl\","
    .ascii "\"opened\":{\"nvidiactl\":true,\"nvidia0\":"
json_probe_pre_len = . - json_probe_pre
json_probe_mid:
    .ascii ",\"nvidia_uvm\":"
json_probe_mid_len = . - json_probe_mid
json_probe_ver:
    .ascii "},\"rm_api_version\":\""
json_probe_ver_len = . - json_probe_ver
json_probe_cards:
    .ascii "\",\"prefer_minor\":0,\"never_minor\":2,"
    .ascii "\"cards\":["
json_probe_cards_len = . - json_probe_cards
json_card_pre:
    .ascii "{\"minor\":"
json_card_pre_len = . - json_card_pre
json_card_fb:
    .ascii ",\"fb_bytes\":"
json_card_fb_len = . - json_card_fb
json_card_role:
    .ascii ",\"role\":\""
json_card_role_len = . - json_card_role
role_prefer:    .ascii "spark-prefer"
role_prefer_len = . - role_prefer
role_voice:     .ascii "voice-only-never-spark"
role_voice_len = . - role_voice
role_ok:        .ascii "ok-secondary"
role_ok_len = . - role_ok
json_card_end:  .ascii "\"}"
json_card_end_len = . - json_card_end
json_comma:     .ascii ","
json_probe_suf: .ascii "]}"
json_probe_suf_len = . - json_probe_suf

json_mem_pre:
    .ascii "{\"op\":\"memstat\",\"iface\":\"asm-dev+ioctl\","
    .ascii "\"cards\":["
json_mem_pre_len = . - json_mem_pre
json_mem_suf:
    .ascii "],\"note\":\"fb_bytes from NV_ESC_CARD_INFO;"
    .ascii " prefer minor 0; never minor 2\"}"
json_mem_suf_len = . - json_mem_suf

json_prefer_ok:
    .ascii "{\"op\":\"prefer\",\"ok\":true,\"prefer_minor\":0,"
    .ascii "\"dev\":\"/dev/nvidia0\",\"never_minor\":2,"
    .ascii "\"note\":\"prefer GPU ok; voice GPU refused\"}"
json_prefer_ok_len = . - json_prefer_ok

true_s:     .ascii "true"
true_len = 4
false_s:    .ascii "false"
false_len = 5

pin_ok_pre:
    .ascii "{\"op\":\"pin\",\"ok\":true,\"mlock\":true,"
    .ascii "\"size_bytes\":"
pin_ok_pre_len = . - pin_ok_pre
pin_ok_mid:
    .ascii ",\"addr_hex\":\"0x"
pin_ok_mid_len = . - pin_ok_mid
pin_ok_suf:
    .ascii "\"}"
pin_ok_suf_len = . - pin_ok_suf

.section .text

# ------------------------------------------------------------
cuda_ops_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    # pcie before [cuda] banner — pcie_ops prints [pcie]
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_pcie]
    call    contains
    test    rax, rax
    jnz     do_pcie

    lea     rsi, [rip+msg_cuda]
    mov     rdx, msg_cuda_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_memstat]
    call    contains
    test    rax, rax
    jnz     do_memstat

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_prefer]
    call    contains
    test    rax, rax
    jnz     do_prefer

    # default / probe
    jmp     do_probe

# ---------- pcie (asm/pcie_ops.s — live sysfs) ----------
do_pcie:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    jmp     pcie_ops_dispatch

# ---------- probe ----------
do_probe:
    # open nvidiactl
    lea     rdi, [rip+path_ctl]
    mov     rsi, O_RDWR
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      fail_ctl
    mov     r12, rax                # ctl fd

    # CHECK_VERSION ioctl
    lea     rdi, [rip+ver_buf]
    xor     eax, eax
    mov     rcx, 72/8
    rep     stosq
    mov     dword ptr [rip+ver_buf], '2'   # QUERY
    mov     eax, SYS_IOCTL
    mov     edi, r12d
    mov     esi, IOC_CHECK_VERSION
    lea     rdx, [rip+ver_buf]
    syscall
    test    rax, rax
    js      fail_ioctl_ctl

    # CARD_INFO ioctl
    lea     rdi, [rip+cards_buf]
    mov     rcx, 2304
    xor     eax, eax
    rep     stosb
    mov     eax, SYS_IOCTL
    mov     edi, r12d
    mov     esi, IOC_CARD_INFO
    lea     rdx, [rip+cards_buf]
    syscall
    test    rax, rax
    js      fail_ioctl_ctl

    mov     rdi, r12
    call    sys_close

    # open /dev/nvidia0 (prefer) — reachability
    lea     rdi, [rip+path_n0]
    mov     rsi, O_RDWR
    xor     rdx, rdx
    call    sys_open
    mov     r13, rax                # >=0 ok
    cmp     rax, 0
    jl      n0_skip
    mov     rdi, rax
    call    sys_close
n0_skip:

    # open uvm
    lea     rdi, [rip+path_uvm]
    mov     rsi, O_RDWR
    xor     rdx, rdx
    call    sys_open
    mov     r14, rax
    cmp     rax, 0
    jl      uvm_skip
    mov     rdi, rax
    call    sys_close
uvm_skip:

    # tiny anonymous mmap as mmap path proof (host, not GPU BAR)
    mov     eax, SYS_MMAP
    xor     edi, edi
    mov     esi, 4096
    mov     edx, PROT_READ|PROT_WRITE
    mov     r10d, MAP_PRIVATE|MAP_ANONYMOUS
    mov     r8d, -1
    xor     r9d, r9d
    syscall
    cmp     rax, -4095
    jae     mmap_skip_p
    mov     r15, rax
    mov     eax, SYS_MUNMAP
    mov     rdi, r15
    mov     esi, 4096
    syscall
mmap_skip_p:

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout

    lea     rsi, [rip+json_probe_pre]
    mov     rdx, json_probe_pre_len
    call    write_stdout
    # nvidia0 bool
    cmp     r13, 0
    jl      n0_false
    lea     rsi, [rip+true_s]
    mov     rdx, true_len
    jmp     n0_out
n0_false:
    lea     rsi, [rip+false_s]
    mov     rdx, false_len
n0_out:
    call    write_stdout
    lea     rsi, [rip+json_probe_mid]
    mov     rdx, json_probe_mid_len
    call    write_stdout
    cmp     r14, 0
    jl      uvm_false
    lea     rsi, [rip+true_s]
    mov     rdx, true_len
    jmp     uvm_out
uvm_false:
    lea     rsi, [rip+false_s]
    mov     rdx, false_len
uvm_out:
    call    write_stdout
    lea     rsi, [rip+json_probe_ver]
    mov     rdx, json_probe_ver_len
    call    write_stdout
    # versionString at ver_buf+8
    lea     rsi, [rip+ver_buf+8]
    call    strlen_c
    mov     rdx, rax
    lea     rsi, [rip+ver_buf+8]
    call    write_stdout
    lea     rsi, [rip+json_probe_cards]
    mov     rdx, json_probe_cards_len
    call    write_stdout
    call    emit_cards_json
    lea     rsi, [rip+json_probe_suf]
    mov     rdx, json_probe_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     cuda_done

# ---------- memstat ----------
do_memstat:
    lea     rdi, [rip+path_ctl]
    mov     rsi, O_RDWR
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      fail_ctl
    mov     r12, rax
    lea     rdi, [rip+cards_buf]
    mov     rcx, 2304
    xor     eax, eax
    rep     stosb
    mov     eax, SYS_IOCTL
    mov     edi, r12d
    mov     esi, IOC_CARD_INFO
    lea     rdx, [rip+cards_buf]
    syscall
    test    rax, rax
    js      fail_ioctl_ctl
    mov     rdi, r12
    call    sys_close

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+json_mem_pre]
    mov     rdx, json_mem_pre_len
    call    write_stdout
    call    emit_cards_json
    lea     rsi, [rip+json_mem_suf]
    mov     rdx, json_mem_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     cuda_done

# ---------- prefer ----------
do_prefer:
    # this host Device Minor map (verified 2026-08-31):
    #   0 = prefer /dev/nvidia0
    #   1 = secondary /dev/nvidia1 (allowed)
    #   2 = voice-only /dev/nvidia2 (refuse)
    # nvidia-smi index may differ; Spark `gpu N`
    # means Device Minor — do NOT refuse "gpu 1" (secondary).
    # Prefer path ONLY opens /dev/nvidia0 — never path_n2.
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_gpu2]
    call    contains
    test    rax, rax
    jnz     prefer_voice_fail
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_nvidia2]
    call    contains
    test    rax, rax
    jnz     prefer_voice_fail
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_minor2]
    call    contains
    test    rax, rax
    jnz     prefer_voice_fail

    # open nvidia0 as preferred device proof (never nvidia2)
    lea     rdi, [rip+path_n0]
    mov     rsi, O_RDWR
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      fail_ctl
    mov     rdi, rax
    call    sys_close

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+json_prefer_ok]
    mov     rdx, json_prefer_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     cuda_done

prefer_voice_fail:
    lea     rsi, [rip+err_prefer_voice]
    mov     rdx, err_prefer_voice_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# emit_cards_json: walk cards_buf, emit valid entries
emit_cards_json:
    push    rbx
    push    r12
    push    r13
    xor     r12, r12                # index
    xor     r13, r13                # emitted count
ec_loop:
    cmp     r12, CARD_MAX
    jge     ec_done
    mov     rax, r12
    imul    rax, CARD_STRIDE
    lea     rbx, [rip+cards_buf]
    add     rbx, rax
    cmp     dword ptr [rbx+OFF_VALID], 0
    je      ec_next
    cmp     r13, 0
    je      ec_nocomma
    lea     rsi, [rip+json_comma]
    mov     rdx, 1
    call    write_stdout
ec_nocomma:
    lea     rsi, [rip+json_card_pre]
    mov     rdx, json_card_pre_len
    call    write_stdout
    mov     edi, [rbx+OFF_MINOR]
    call    write_u32_dec
    lea     rsi, [rip+json_card_fb]
    mov     rdx, json_card_fb_len
    call    write_stdout
    mov     rdi, [rbx+OFF_FB_SIZE]
    call    write_u64_dec
    lea     rsi, [rip+json_card_role]
    mov     rdx, json_card_role_len
    call    write_stdout
    mov     eax, [rbx+OFF_MINOR]
    cmp     eax, 0
    je      ec_role_pref
    cmp     eax, VOICE_MINOR
    je      ec_role_voice
    lea     rsi, [rip+role_ok]
    mov     rdx, role_ok_len
    jmp     ec_role_out
ec_role_pref:
    lea     rsi, [rip+role_prefer]
    mov     rdx, role_prefer_len
    jmp     ec_role_out
ec_role_voice:
    lea     rsi, [rip+role_voice]
    mov     rdx, role_voice_len
ec_role_out:
    call    write_stdout
    lea     rsi, [rip+json_card_end]
    mov     rdx, json_card_end_len
    call    write_stdout
    inc     r13
ec_next:
    inc     r12
    jmp     ec_loop
ec_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

fail_ctl:
    lea     rsi, [rip+err_open_ctl]
    mov     rdx, err_open_ctl_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

fail_ioctl_ctl:
    mov     rdi, r12
    call    sys_close
    lea     rsi, [rip+err_ioctl]
    mov     rdx, err_ioctl_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

cuda_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# memory pin — mmap anonymous + mlock; fail loud with errno
# ------------------------------------------------------------
memory_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_mem]
    mov     rdx, msg_mem_len
    call    write_stdout

    # default size 1MiB; parse trailing number + K/M if present
    mov     qword ptr [rip+pin_sz], 1048576
    lea     rsi, [rip+linebuf]
    call    parse_size_from_line
    # rax = size if found
    test    rax, rax
    jz      pin_sz_ok
    mov     [rip+pin_sz], rax
pin_sz_ok:
    mov     r12, [rip+pin_sz]

    mov     eax, SYS_MMAP
    xor     edi, edi
    mov     rsi, r12
    mov     edx, PROT_READ|PROT_WRITE
    mov     r10d, MAP_PRIVATE|MAP_ANONYMOUS
    mov     r8d, -1
    xor     r9d, r9d
    syscall
    cmp     rax, -4095
    jae     pin_mmap_fail
    mov     r13, rax
    mov     [rip+pin_ptr], rax

    mov     eax, SYS_MLOCK
    mov     rdi, r13
    mov     rsi, r12
    syscall
    test    rax, rax
    js      pin_mlock_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+pin_ok_pre]
    mov     rdx, pin_ok_pre_len
    call    write_stdout
    mov     rdi, r12
    call    write_u64_dec
    lea     rsi, [rip+pin_ok_mid]
    mov     rdx, pin_ok_mid_len
    call    write_stdout
    mov     rdi, r13
    call    write_hex64
    lea     rsi, [rip+pin_ok_suf]
    mov     rdx, pin_ok_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    # leave pinned for process lifetime (demo); no munmap
    pop     r13
    pop     r12
    pop     rbx
    ret

pin_mmap_fail:
    lea     rsi, [rip+err_mmap]
    mov     rdx, err_mmap_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

pin_mlock_fail:
    # rax = -errno
    neg     rax
    mov     r12, rax
    lea     rsi, [rip+err_mlock]
    mov     rdx, err_mlock_len
    call    write_stdout
    mov     rdi, r12
    call    write_u32_dec
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# parse_size_from_line: find first digit run; optional K/M/G suffix
# → rax size or 0
parse_size_from_line:
    push    rbx
    lea     rbx, [rip+linebuf]
ps_find:
    mov     al, [rbx]
    test    al, al
    jz      ps_none
    cmp     al, '0'
    jb      ps_i
    cmp     al, '9'
    ja      ps_i
    xor     rax, rax
ps_num:
    movzx   ecx, byte ptr [rbx]
    cmp     cl, '0'
    jb      ps_suf
    cmp     cl, '9'
    ja      ps_suf
    imul    rax, 10
    sub     cl, '0'
    add     rax, rcx
    inc     rbx
    jmp     ps_num
ps_suf:
    mov     cl, [rbx]
    cmp     cl, 'M'
    je      ps_m
    cmp     cl, 'm'
    je      ps_m
    cmp     cl, 'K'
    je      ps_k
    cmp     cl, 'k'
    je      ps_k
    cmp     cl, 'G'
    je      ps_g
    cmp     cl, 'g'
    je      ps_g
    jmp     ps_done
ps_k:
    shl     rax, 10
    jmp     ps_done
ps_m:
    shl     rax, 20
    jmp     ps_done
ps_g:
    shl     rax, 30
    jmp     ps_done
ps_i:
    inc     rbx
    jmp     ps_find
ps_none:
    xor     rax, rax
ps_done:
    pop     rbx
    ret

strlen_c:
    xor     rax, rax
sc:
    cmp     byte ptr [rsi+rax], 0
    je      sc_d
    inc     rax
    jmp     sc
sc_d:
    ret

# write_u32_dec: edi = value
write_u32_dec:
    push    rbx
    push    rcx
    push    rdx
    mov     eax, edi
    lea     rbx, [rip+num_buf+31]
    mov     byte ptr [rbx], 0
    mov     ecx, 10
    test    eax, eax
    jnz     u32_loop
    dec     rbx
    mov     byte ptr [rbx], '0'
    jmp     u32_out
u32_loop:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    eax, eax
    jnz     u32_loop
u32_out:
    mov     rsi, rbx
    lea     rdx, [rip+num_buf+31]
    sub     rdx, rbx
    call    write_stdout
    pop     rdx
    pop     rcx
    pop     rbx
    ret

# write_u64_dec: rdi = value
write_u64_dec:
    push    rbx
    push    rcx
    push    rdx
    mov     rax, rdi
    lea     rbx, [rip+num_buf+31]
    mov     byte ptr [rbx], 0
    mov     ecx, 10
    test    rax, rax
    jnz     u64_loop
    dec     rbx
    mov     byte ptr [rbx], '0'
    jmp     u64_out
u64_loop:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    rax, rax
    jnz     u64_loop
u64_out:
    mov     rsi, rbx
    lea     rdx, [rip+num_buf+31]
    sub     rdx, rbx
    call    write_stdout
    pop     rdx
    pop     rcx
    pop     rbx
    ret

# write_hex64: rdi = value
write_hex64:
    push    rbx
    push    rcx
    lea     rbx, [rip+num_buf]
    mov     rcx, 16
    mov     rax, rdi
wh_loop:
    dec     rcx
    mov     rdx, rax
    and     edx, 0xf
    cmp     dl, 10
    jb      wh_d
    add     dl, 'a'-10
    jmp     wh_s
wh_d:
    add     dl, '0'
wh_s:
    mov     [rbx+rcx], dl
    shr     rax, 4
    test    rcx, rcx
    jnz     wh_loop
    mov     rsi, rbx
    mov     rdx, 16
    call    write_stdout
    pop     rcx
    pop     rbx
    ret
