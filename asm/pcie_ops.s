# Spark PCIe — pure x86_64 asm syscalls reading live sysfs
# PCI link attrs (current/max speed + width). No inventing;
# no reboot; never treat Device Minor 2 (voice-only GPU)
# as a Spark prefer/target.
#
# Language:
#   cuda pcie -> report
#   cuda pcie explain -> text
#   pcie probe gpu 0 -> report
#
# Sources: /sys/bus/pci/devices/<bdf>/current_link_* + max_link_*
# Exports: pcie_ops_dispatch
.intel_syntax noprefix
.global pcie_ops_dispatch

.extern linebuf
.extern write_stdout
.extern contains
.extern sys_open
.extern sys_read
.extern sys_close
.extern sys_exit

.equ O_RDONLY, 0
.equ VOICE_MINOR, 2
.equ PREFER_MINOR, 0

.section .bss
.align 16
link_buf:       .space 128
num_buf:        .space 32
# Scratch parsed ints (per GPU pass)
cur_gen:        .space 4
max_gen:        .space 4
cur_w:          .space 4
max_w:          .space 4
cur_gts:        .space 4   # integer GT/s from sysfs (e.g. 32)
max_gts:        .space 4
downgraded:     .space 4
filter_minor:   .space 4   # -1 = all; else only that minor
any_down:       .space 4
emit_count:     .space 4

.section .data
msg_pcie:   .ascii "[pcie] "
msg_pcie_len = . - msg_pcie
msg_nl:     .ascii "\n"
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow

needle_explain: .ascii "explain\0"
needle_gpu0:    .ascii "gpu 0\0"
needle_gpu1:    .ascii "gpu 1\0"
needle_gpu2:    .ascii "gpu 2\0"

# --- GPU 0: prefer compute ---
bus0:       .ascii "0000:01:00.0\0"
bus0_len = 12
path0_cs:   .ascii "/sys/bus/pci/devices/0000:01:00.0/current_link_speed\0"
path0_cw:   .ascii "/sys/bus/pci/devices/0000:01:00.0/current_link_width\0"
path0_ms:   .ascii "/sys/bus/pci/devices/0000:01:00.0/max_link_speed\0"
path0_mw:   .ascii "/sys/bus/pci/devices/0000:01:00.0/max_link_width\0"

# --- GPU 1: secondary ---
bus1:       .ascii "0000:c3:00.0\0"
bus1_len = 12
path1_cs:   .ascii "/sys/bus/pci/devices/0000:c3:00.0/current_link_speed\0"
path1_cw:   .ascii "/sys/bus/pci/devices/0000:c3:00.0/current_link_width\0"
path1_ms:   .ascii "/sys/bus/pci/devices/0000:c3:00.0/max_link_speed\0"
path1_mw:   .ascii "/sys/bus/pci/devices/0000:c3:00.0/max_link_width\0"

# --- GPU 2: voice-only (never Spark target) ---
bus2:       .ascii "0000:21:00.0\0"
bus2_len = 12
path2_cs:   .ascii "/sys/bus/pci/devices/0000:21:00.0/current_link_speed\0"
path2_cw:   .ascii "/sys/bus/pci/devices/0000:21:00.0/current_link_width\0"
path2_ms:   .ascii "/sys/bus/pci/devices/0000:21:00.0/max_link_speed\0"
path2_mw:   .ascii "/sys/bus/pci/devices/0000:21:00.0/max_link_width\0"

err_voice:
    .ascii "error: pcie gpu 2 is reserved voice-only"
    .ascii " (minor 2) — never a Spark target\n"
err_voice_len = . - err_voice
err_sysfs:
    .ascii "error: cannot read PCIe sysfs link attrs"
    .ascii " (missing /sys/bus/pci/devices/…)\n"
err_sysfs_len = . - err_sysfs

json_pre:
    .ascii "{\"op\":\"pcie\",\"iface\":\"asm-sysfs\","
    .ascii "\"prefer_minor\":0,\"never_minor\":2,"
    .ascii "\"source\":\"/sys/bus/pci/devices/*/current_link_*\","
    .ascii "\"gpus\":["
json_pre_len = . - json_pre
json_suf:
    .ascii "]}"
json_suf_len = . - json_suf

json_gpu_pre:
    .ascii "{\"minor\":"
json_gpu_pre_len = . - json_gpu_pre
json_bus:
    .ascii ",\"bus_id\":\""
json_bus_len = . - json_bus
json_gens:
    .ascii "\",\"gen_current\":"
json_gens_len = . - json_gens
json_genm:
    .ascii ",\"gen_max\":"
json_genm_len = . - json_genm
json_wc:
    .ascii ",\"width_current\":"
json_wc_len = . - json_wc
json_wm:
    .ascii ",\"width_max\":"
json_wm_len = . - json_wm
json_sc:
    .ascii ",\"speed_current_gts\":"
json_sc_len = . - json_sc
json_sm:
    .ascii ",\"speed_max_gts\":"
json_sm_len = . - json_sm
json_down:
    .ascii ",\"downgraded\":"
json_down_len = . - json_down
json_role:
    .ascii ",\"role\":\""
json_role_len = . - json_role
json_gpu_end:
    .ascii "\"}"
json_gpu_end_len = . - json_gpu_end
json_comma: .ascii ","

role_prefer: .ascii "spark-prefer"
role_prefer_len = . - role_prefer
role_voice:  .ascii "voice-only-never-spark"
role_voice_len = . - role_voice
role_ok:     .ascii "ok-secondary"
role_ok_len = . - role_ok

true_s:     .ascii "true"
true_len = 4
false_s:    .ascii "false"
false_len = 5

# explain (honest causes from measured downgrade only)
exp_pre:
    .ascii "{\"op\":\"pcie_explain\",\"iface\":\"asm-sysfs\","
    .ascii "\"prefer_minor\":0,\"never_minor\":2,"
    .ascii "\"text\":\""
exp_pre_len = . - exp_pre
exp_suf:
    .ascii "\"}"
exp_suf_len = . - exp_suf
exp_down:
    .ascii "Measured PCIe link is below max width and/or "
    .ascii "speed (see gpus[].downgraded). Honest causes: "
    .ascii "riser, bifurcation, incomplete seating, or "
    .ascii "root-port lane share — not proven beyond the "
    .ascii "sysfs numbers. No reboot. Do not claim x16 fixed."
exp_down_len = . - exp_down
exp_ok:
    .ascii "Measured PCIe links at reported max width and "
    .ascii "speed for emitted GPUs (no downgrade flag)."
exp_ok_len = . - exp_ok

.section .text

# ------------------------------------------------------------
pcie_ops_dispatch:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     rsi, [rip+msg_pcie]
    mov     rdx, msg_pcie_len
    call    write_stdout

    # refuse explicit gpu 2 (voice) as Spark target filter
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_gpu2]
    call    contains
    test    rax, rax
    jnz     fail_voice

    # default: all GPUs; optional gpu 0 / gpu 1 filter
    mov     dword ptr [rip+filter_minor], -1
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_gpu0]
    call    contains
    test    rax, rax
    jz      filt_chk1
    mov     dword ptr [rip+filter_minor], 0
    jmp     filt_done
filt_chk1:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_gpu1]
    call    contains
    test    rax, rax
    jz      filt_done
    mov     dword ptr [rip+filter_minor], 1
filt_done:

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_explain]
    call    contains
    test    rax, rax
    jnz     do_explain

    jmp     do_report

# ---------- report ----------
do_report:
    mov     dword ptr [rip+any_down], 0
    mov     dword ptr [rip+emit_count], 0

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+json_pre]
    mov     rdx, json_pre_len
    call    write_stdout

    # emit minor 0, 1, 2 (skip by filter)
    mov     edi, 0
    call    maybe_emit_gpu
    mov     edi, 1
    call    maybe_emit_gpu
    mov     edi, 2
    call    maybe_emit_gpu

    cmp     dword ptr [rip+emit_count], 0
    je      fail_sysfs_after

    lea     rsi, [rip+json_suf]
    mov     rdx, json_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     pcie_done

fail_sysfs_after:
    lea     rsi, [rip+err_sysfs]
    mov     rdx, err_sysfs_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- explain ----------
do_explain:
    # measure first (sets any_down) without printing GPU JSON
    mov     dword ptr [rip+any_down], 0
    mov     dword ptr [rip+emit_count], 0
    # silent measure: load each selected GPU
    mov     edi, 0
    call    measure_gpu_silent
    mov     edi, 1
    call    measure_gpu_silent
    mov     edi, 2
    call    measure_gpu_silent
    cmp     dword ptr [rip+emit_count], 0
    je      fail_sysfs_after

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+exp_pre]
    mov     rdx, exp_pre_len
    call    write_stdout
    cmp     dword ptr [rip+any_down], 0
    je      exp_ok_out
    lea     rsi, [rip+exp_down]
    mov     rdx, exp_down_len
    jmp     exp_out
exp_ok_out:
    lea     rsi, [rip+exp_ok]
    mov     rdx, exp_ok_len
exp_out:
    call    write_stdout
    lea     rsi, [rip+exp_suf]
    mov     rdx, exp_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     pcie_done

# maybe_emit_gpu: edi = minor
maybe_emit_gpu:
    push    rbx
    mov     ebx, edi
    mov     eax, [rip+filter_minor]
    cmp     eax, -1
    je      me_go
    cmp     eax, ebx
    jne     me_skip
me_go:
    mov     edi, ebx
    call    load_gpu_attrs
    test    rax, rax
    js      me_skip
    # comma if not first emit
    cmp     dword ptr [rip+emit_count], 0
    je      me_nocomma
    lea     rsi, [rip+json_comma]
    mov     rdx, 1
    call    write_stdout
me_nocomma:
    call    emit_one_gpu_json
    inc     dword ptr [rip+emit_count]
me_skip:
    pop     rbx
    ret

# measure_gpu_silent: edi = minor; updates any_down/emit_count
measure_gpu_silent:
    push    rbx
    mov     ebx, edi
    mov     eax, [rip+filter_minor]
    cmp     eax, -1
    je      ms_go
    cmp     eax, ebx
    jne     ms_skip
ms_go:
    mov     edi, ebx
    call    load_gpu_attrs
    test    rax, rax
    js      ms_skip
    inc     dword ptr [rip+emit_count]
    cmp     dword ptr [rip+downgraded], 0
    je      ms_skip
    mov     dword ptr [rip+any_down], 1
ms_skip:
    pop     rbx
    ret

# load_gpu_attrs: edi = minor → rax 0 ok / -1 fail
# fills cur_gen, max_gen, cur_w, max_w, downgraded; r12=bus ptr
# r13=bus len; r14d=minor
load_gpu_attrs:
    push    rbx
    mov     r14d, edi
    cmp     edi, 0
    je      lg0
    cmp     edi, 1
    je      lg1
    cmp     edi, 2
    je      lg2
    mov     rax, -1
    pop     rbx
    ret
lg0:
    lea     r12, [rip+bus0]
    mov     r13, bus0_len
    lea     rdi, [rip+path0_cs]
    call    read_speed_pair
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path0_ms]
    call    read_speed_pair_max
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path0_cw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+cur_w], eax
    lea     rdi, [rip+path0_mw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+max_w], eax
    jmp     lg_down
lg1:
    lea     r12, [rip+bus1]
    mov     r13, bus1_len
    lea     rdi, [rip+path1_cs]
    call    read_speed_pair
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path1_ms]
    call    read_speed_pair_max
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path1_cw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+cur_w], eax
    lea     rdi, [rip+path1_mw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+max_w], eax
    jmp     lg_down
lg2:
    lea     r12, [rip+bus2]
    mov     r13, bus2_len
    lea     rdi, [rip+path2_cs]
    call    read_speed_pair
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path2_ms]
    call    read_speed_pair_max
    test    rax, rax
    js      lg_fail
    lea     rdi, [rip+path2_cw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+cur_w], eax
    lea     rdi, [rip+path2_mw]
    call    read_sysfs_u32
    test    rax, rax
    js      lg_fail
    mov     [rip+max_w], eax
lg_down:
    mov     dword ptr [rip+downgraded], 0
    mov     eax, [rip+cur_w]
    cmp     eax, [rip+max_w]
    jge     lg_chk_gen
    mov     dword ptr [rip+downgraded], 1
    mov     dword ptr [rip+any_down], 1
lg_chk_gen:
    mov     eax, [rip+cur_gen]
    cmp     eax, [rip+max_gen]
    jge     lg_ok
    mov     dword ptr [rip+downgraded], 1
    mov     dword ptr [rip+any_down], 1
lg_ok:
    xor     rax, rax
    pop     rbx
    ret
lg_fail:
    mov     rax, -1
    pop     rbx
    ret

# emit_one_gpu_json — uses loaded attrs + r12/r13/r14d
emit_one_gpu_json:
    lea     rsi, [rip+json_gpu_pre]
    mov     rdx, json_gpu_pre_len
    call    write_stdout
    mov     edi, r14d
    call    write_u32_dec
    lea     rsi, [rip+json_bus]
    mov     rdx, json_bus_len
    call    write_stdout
    mov     rsi, r12
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+json_gens]
    mov     rdx, json_gens_len
    call    write_stdout
    mov     edi, [rip+cur_gen]
    call    write_u32_dec
    lea     rsi, [rip+json_genm]
    mov     rdx, json_genm_len
    call    write_stdout
    mov     edi, [rip+max_gen]
    call    write_u32_dec
    lea     rsi, [rip+json_wc]
    mov     rdx, json_wc_len
    call    write_stdout
    mov     edi, [rip+cur_w]
    call    write_u32_dec
    lea     rsi, [rip+json_wm]
    mov     rdx, json_wm_len
    call    write_stdout
    mov     edi, [rip+max_w]
    call    write_u32_dec
    # measured integer GT/s from sysfs (e.g. 32 from "32.0 GT/s")
    lea     rsi, [rip+json_sc]
    mov     rdx, json_sc_len
    call    write_stdout
    mov     edi, [rip+cur_gts]
    call    write_u32_dec
    lea     rsi, [rip+json_sm]
    mov     rdx, json_sm_len
    call    write_stdout
    mov     edi, [rip+max_gts]
    call    write_u32_dec
    lea     rsi, [rip+json_down]
    mov     rdx, json_down_len
    call    write_stdout
    cmp     dword ptr [rip+downgraded], 0
    je      eo_false
    lea     rsi, [rip+true_s]
    mov     rdx, true_len
    jmp     eo_bool
eo_false:
    lea     rsi, [rip+false_s]
    mov     rdx, false_len
eo_bool:
    call    write_stdout
    lea     rsi, [rip+json_role]
    mov     rdx, json_role_len
    call    write_stdout
    cmp     r14d, PREFER_MINOR
    je      eo_pref
    cmp     r14d, VOICE_MINOR
    je      eo_voice
    lea     rsi, [rip+role_ok]
    mov     rdx, role_ok_len
    jmp     eo_role
eo_pref:
    lea     rsi, [rip+role_prefer]
    mov     rdx, role_prefer_len
    jmp     eo_role
eo_voice:
    lea     rsi, [rip+role_voice]
    mov     rdx, role_voice_len
eo_role:
    call    write_stdout
    lea     rsi, [rip+json_gpu_end]
    mov     rdx, json_gpu_end_len
    call    write_stdout
    ret

# read_speed_pair: rdi=current_link_speed path
# → cur_gts + cur_gen; rax 0 ok / -1 fail
read_speed_pair:
    call    read_sysfs_speed_raw
    test    rax, rax
    js      rsp_fail
    mov     [rip+cur_gts], eax
    call    gts_to_gen
    mov     [rip+cur_gen], eax
    xor     rax, rax
    ret
rsp_fail:
    ret

# read_speed_pair_max: rdi=max_link_speed path
read_speed_pair_max:
    call    read_sysfs_speed_raw
    test    rax, rax
    js      rspm_fail
    mov     [rip+max_gts], eax
    call    gts_to_gen
    mov     [rip+max_gen], eax
    xor     rax, rax
    ret
rspm_fail:
    ret

# read_sysfs_speed_raw: rdi=path → eax = integer GT/s, rax ok/-1
read_sysfs_speed_raw:
    push    rbx
    mov     rbx, rdi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rsr_fail
    mov     r15, rax
    lea     rsi, [rip+link_buf]
    mov     rdx, 64
    mov     rdi, r15
    call    sys_read
    mov     rbx, rax
    mov     rdi, r15
    call    sys_close
    cmp     rbx, 1
    jl      rsr_fail
    lea     rsi, [rip+link_buf]
    mov     byte ptr [rsi+rbx], 0
    call    parse_u32
    pop     rbx
    ret
rsr_fail:
    mov     rax, -1
    pop     rbx
    ret

# gts_to_gen: eax = GT/s int → eax = gen
gts_to_gen:
    cmp     eax, 32
    je      g5
    cmp     eax, 16
    je      g4
    cmp     eax, 8
    je      g3
    cmp     eax, 5
    je      g2
    cmp     eax, 2
    je      g1
    xor     eax, eax
    ret
g5:
    mov     eax, 5
    ret
g4:
    mov     eax, 4
    ret
g3:
    mov     eax, 3
    ret
g2:
    mov     eax, 2
    ret
g1:
    mov     eax, 1
    ret

# read_sysfs_u32: rdi = path → eax value, rax>=0 ok / -1 fail
read_sysfs_u32:
    push    rbx
    mov     rbx, rdi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rs_fail
    mov     r15, rax
    lea     rsi, [rip+link_buf]
    mov     rdx, 64
    mov     rdi, r15
    call    sys_read
    mov     rbx, rax
    mov     rdi, r15
    call    sys_close
    cmp     rbx, 1
    jl      rs_fail
    lea     rsi, [rip+link_buf]
    mov     byte ptr [rsi+rbx], 0
    call    parse_u32
    pop     rbx
    ret
rs_fail:
    mov     rax, -1
    pop     rbx
    ret

# parse_u32: rsi = ascii → eax
parse_u32:
    xor     eax, eax
pu_loop:
    movzx   ecx, byte ptr [rsi]
    cmp     cl, '0'
    jb      pu_done
    cmp     cl, '9'
    ja      pu_done
    imul    eax, 10
    sub     cl, '0'
    add     eax, ecx
    inc     rsi
    jmp     pu_loop
pu_done:
    ret

fail_voice:
    lea     rsi, [rip+err_voice]
    mov     rdx, err_voice_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

pcie_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
