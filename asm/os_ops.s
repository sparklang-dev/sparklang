# Spark OS design / generate / build / explain — dry-run file emit
# Separate object from binary_ops / network_ops (no shared labels).
# Exports: os_ops_dispatch
# Never dd disks, never reboot host.
# kind browser → templates/os/browser/ → out/os/browser_mitm/
# kind ai_agent (default) → templates/os/ai_agent/ → out/os/agentos/

.intel_syntax noprefix
.global os_ops_dispatch

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
.extern outdir_name

.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT,  64
.equ O_TRUNC,  512
.equ COPY_MAX, 32768

.section .bss
.align 16
copy_buf:   .space COPY_MAX

.section .data

msg_os:
    .ascii "[os] "
msg_os_len = . - msg_os
msg_nl_l:
    .ascii "\n"
msg_arrow:
    .ascii "  → "
msg_arrow_len = . - msg_arrow
msg_honesty:
    .ascii "  (blueprint/stub only — not production OS;"
    .ascii " never reboot/install on this host)\n"
msg_honesty_len = . - msg_honesty
msg_wrote:
    .ascii "wrote tree "
msg_wrote_len = . - msg_wrote
msg_built:
    .ascii "build dry-run: Makefile would assemble boot+kernel"
    .ascii " stubs → image.bin (owner-driven; no dd)\n"
msg_built_len = . - msg_built

needle_design:   .ascii "design\0"
needle_specify:  .ascii "specify\0"
needle_generate: .ascii "generate\0"
needle_build:    .ascii "build\0"
needle_explain:  .ascii "explain\0"
needle_ai_rt:    .ascii "ai_runtime\0"
needle_kitchen:  .ascii "aikitchen\0"
needle_browser:  .ascii "browser\0"
needle_mitm:     .ascii "mitm\0"

dry_design_agent:
    .ascii "{\"op\":\"design\",\"name\":\"agentos\",\"kind\":\"ai_agent\","
    .ascii "\"mode\":\"dry-run\","
    .ascii "\"blueprint\":{\"isolate\":\"cooperative_tasks\","
    .ascii "\"model_slots\":4,\"tool_bus\":true,"
    .ascii "\"scheduler\":\"fair_rr\",\"agent_ring0\":false},"
    .ascii "\"reasons\":[\"agents need isolates+tool bus not libc\","
    .ascii "\"model I/O as syscalls\",\"capability tokens\"]}"
dry_design_agent_len = . - dry_design_agent

dry_design_kitchen:
    .ascii "{\"op\":\"design\",\"name\":\"aikitchen\","
    .ascii "\"kind\":\"ai_runtime\",\"mode\":\"dry-run\","
    .ascii "\"features\":[\"scheduler\",\"model_router\","
    .ascii "\"sandbox\",\"net\"],"
    .ascii "\"blueprint\":{\"isolate\":\"sandbox_slots\","
    .ascii "\"model_router\":true,\"net_optional\":true,"
    .ascii "\"agent_ring0\":false},"
    .ascii "\"reasons\":[\"runtime kitchen for multi-model agents\","
    .ascii "\"net is optional subsystem\"]}"
dry_design_kitchen_len = . - dry_design_kitchen

dry_design_browser:
    .ascii "{\"op\":\"design\",\"name\":\"browser_mitm\","
    .ascii "\"kind\":\"browser\",\"mode\":\"dry-run\","
    .ascii "\"features\":[\"net\",\"mitm\",\"webview\"],"
    .ascii "\"blueprint\":{\"ui_engine\":\"QtWebEngine\","
    .ascii "\"mitm\":\"local_connect_127.0.0.1\","
    .ascii "\"cdp\":9222,\"proxy\":8877,"
    .ascii "\"product\":\"spark-browser\","
    .ascii "\"agent_ring0\":false},"
    .ascii "\"reasons\":[\"debug appliance not Chrome replace\","
    .ascii "\"owner-local MITM+CDP+HAR\","
    .ascii "\"layout hooks not AgentOS stubs\"]}"
dry_design_browser_len = . - dry_design_browser

dry_specify:
    .ascii "{\"op\":\"specify\",\"mode\":\"dry-run\","
    .ascii "\"spec\":{\"target\":\"x86_64\",\"memory_model\":\"flat\","
    .ascii "\"ai\":{\"agent_runtime\":true,\"model_slots\":4,"
    .ascii "\"tool_bus\":true},"
    .ascii "\"drivers\":[\"serial\",\"framebuffer_stub\","
    .ascii "\"virtio_net_stub\"],"
    .ascii "\"security\":{\"agent_ring0\":false,"
    .ascii "\"capability_tokens\":true}},"
    .ascii "\"honesty\":\"stub_blueprint_not_production\"}"
dry_specify_len = . - dry_specify

dry_explain:
    .ascii "{\"op\":\"explain\",\"mode\":\"dry-run\","
    .ascii "\"text\":\"AgentOS uses cooperative isolates, model I/O"
    .ascii " syscalls (ask/classify/voice), a capability tool bus,"
    .ascii " and fair RR scheduling so multi-agent work stays"
    .ascii " fair. Agents never get raw ring0. Optional net and"
    .ascii " binary-analyze hooks reference Spark network/binary"
    .ascii " ops via separate objects. Output is educational"
    .ascii " stubs under out/os/<name>/ — not a Linux replace"
    .ascii " and never auto-installed on this host.\","
    .ascii "\"see\":\"templates/os/ai_agent/WHY.md\"}"
dry_explain_len = . - dry_explain

dry_explain_browser:
    .ascii "{\"op\":\"explain\",\"mode\":\"dry-run\","
    .ascii "\"text\":\"browser_mitm is an owner-local debug browser"
    .ascii " (Qt WebEngine) with CONNECT MITM on 127.0.0.1,"
    .ascii " CDP on :9222, and HAR export for Spark network"
    .ascii " analyze. os generate emits layout hooks from"
    .ascii " templates/os/browser/ into out/os/browser_mitm/"
    .ascii " — not AgentOS boot stubs and not a Chrome"
    .ascii " replacement. CA install is never automatic.\","
    .ascii "\"see\":\"templates/os/browser/WHY.md\"}"
dry_explain_browser_len = . - dry_explain_browser

dry_generate_json:
    .ascii "{\"op\":\"generate\",\"tree\":\"out/os/agentos\","
    .ascii "\"mode\":\"dry-run\",\"emitted\":[\"README.md\","
    .ascii "\"MEMORY_MAP.md\",\"SPEC.md\",\"WHY.md\","
    .ascii "\"agent_syscall.md\",\"boot.s\",\"kernel_stub.s\","
    .ascii "\"Makefile\",\"optional/net_binary_hooks.md\"],"
    .ascii "\"honesty\":\"blueprint stubs only\"}"
dry_generate_json_len = . - dry_generate_json

dry_generate_json_browser:
    .ascii "{\"op\":\"generate\",\"tree\":\"out/os/browser_mitm\","
    .ascii "\"mode\":\"dry-run\",\"kind\":\"browser\","
    .ascii "\"template\":\"templates/os/browser\","
    .ascii "\"emitted\":[\"README.md\",\"SPEC.md\",\"WHY.md\","
    .ascii "\"LAYOUT.md\",\"Makefile\",\".gitignore\","
    .ascii "\"docs/ARCHITECTURE.md\","
    .ascii "\"spark_browser/HOOKS.md\","
    .ascii "\"spark_browser/mitm/HOOKS.md\","
    .ascii "\"spark_browser/inspector/HOOKS.md\","
    .ascii "\"spark_browser/cdp/HOOKS.md\","
    .ascii "\"scripts/HOOKS.md\",\"bin/HOOKS.md\","
    .ascii "\"tests/HOOKS.md\",\"data/ca/README.md\","
    .ascii "\"optional/spark_network_hooks.md\"],"
    .ascii "\"honesty\":\"browser scaffold not agentos\"}"
dry_generate_json_browser_len = . - dry_generate_json_browser

path_out:       .ascii "out\0"
path_out_os:    .ascii "out/os\0"
path_tree:      .ascii "out/os/agentos\0"
path_tree_opt:  .ascii "out/os/agentos/optional\0"

path_btree:     .ascii "out/os/browser_mitm\0"
path_b_docs:    .ascii "out/os/browser_mitm/docs\0"
path_b_pkg:     .ascii "out/os/browser_mitm/spark_browser\0"
path_b_mitm:    .ascii "out/os/browser_mitm/spark_browser/mitm\0"
path_b_insp:    .ascii "out/os/browser_mitm/spark_browser/inspector\0"
path_b_cdp:     .ascii "out/os/browser_mitm/spark_browser/cdp\0"
path_b_scripts: .ascii "out/os/browser_mitm/scripts\0"
path_b_bin:     .ascii "out/os/browser_mitm/bin\0"
path_b_tests:   .ascii "out/os/browser_mitm/tests\0"
path_b_data:    .ascii "out/os/browser_mitm/data\0"
path_b_ca:      .ascii "out/os/browser_mitm/data/ca\0"
path_b_opt:     .ascii "out/os/browser_mitm/optional\0"

# template src → dest pairs (null-terminated paths) — ai_agent
src_readme:     .ascii "templates/os/ai_agent/README.md\0"
dst_readme:     .ascii "out/os/agentos/README.md\0"
src_mem:        .ascii "templates/os/ai_agent/MEMORY_MAP.md\0"
dst_mem:        .ascii "out/os/agentos/MEMORY_MAP.md\0"
src_spec:       .ascii "templates/os/ai_agent/SPEC.md\0"
dst_spec:       .ascii "out/os/agentos/SPEC.md\0"
src_why:        .ascii "templates/os/ai_agent/WHY.md\0"
dst_why:        .ascii "out/os/agentos/WHY.md\0"
src_sys:        .ascii "templates/os/ai_agent/agent_syscall.md\0"
dst_sys:        .ascii "out/os/agentos/agent_syscall.md\0"
src_boot:       .ascii "templates/os/ai_agent/boot.s\0"
dst_boot:       .ascii "out/os/agentos/boot.s\0"
src_kern:       .ascii "templates/os/ai_agent/kernel_stub.s\0"
dst_kern:       .ascii "out/os/agentos/kernel_stub.s\0"
src_mk:         .ascii "templates/os/ai_agent/Makefile\0"
dst_mk:         .ascii "out/os/agentos/Makefile\0"
src_opt:        .ascii "templates/os/ai_agent/optional/net_binary_hooks.md\0"
dst_opt:        .ascii "out/os/agentos/optional/net_binary_hooks.md\0"

# browser template src → dest
bsrc_readme:    .ascii "templates/os/browser/README.md\0"
bdst_readme:    .ascii "out/os/browser_mitm/README.md\0"
bsrc_spec:      .ascii "templates/os/browser/SPEC.md\0"
bdst_spec:      .ascii "out/os/browser_mitm/SPEC.md\0"
bsrc_why:       .ascii "templates/os/browser/WHY.md\0"
bdst_why:       .ascii "out/os/browser_mitm/WHY.md\0"
bsrc_layout:    .ascii "templates/os/browser/LAYOUT.md\0"
bdst_layout:    .ascii "out/os/browser_mitm/LAYOUT.md\0"
bsrc_mk:        .ascii "templates/os/browser/Makefile\0"
bdst_mk:        .ascii "out/os/browser_mitm/Makefile\0"
bsrc_gi:        .ascii "templates/os/browser/.gitignore\0"
bdst_gi:        .ascii "out/os/browser_mitm/.gitignore\0"
bsrc_arch:      .ascii "templates/os/browser/docs/ARCHITECTURE.md\0"
bdst_arch:      .ascii "out/os/browser_mitm/docs/ARCHITECTURE.md\0"
bsrc_pkg:       .ascii "templates/os/browser/spark_browser/HOOKS.md\0"
bdst_pkg:       .ascii "out/os/browser_mitm/spark_browser/HOOKS.md\0"
bsrc_mitm:      .ascii "templates/os/browser/spark_browser/mitm/HOOKS.md\0"
bdst_mitm:      .ascii "out/os/browser_mitm/spark_browser/mitm/HOOKS.md\0"
bsrc_insp:      .ascii "templates/os/browser/spark_browser/inspector/HOOKS.md\0"
bdst_insp:      .ascii "out/os/browser_mitm/spark_browser/inspector/HOOKS.md\0"
bsrc_cdp:       .ascii "templates/os/browser/spark_browser/cdp/HOOKS.md\0"
bdst_cdp:       .ascii "out/os/browser_mitm/spark_browser/cdp/HOOKS.md\0"
bsrc_scripts:   .ascii "templates/os/browser/scripts/HOOKS.md\0"
bdst_scripts:   .ascii "out/os/browser_mitm/scripts/HOOKS.md\0"
bsrc_bin:       .ascii "templates/os/browser/bin/HOOKS.md\0"
bdst_bin:       .ascii "out/os/browser_mitm/bin/HOOKS.md\0"
bsrc_tests:     .ascii "templates/os/browser/tests/HOOKS.md\0"
bdst_tests:     .ascii "out/os/browser_mitm/tests/HOOKS.md\0"
bsrc_ca:        .ascii "templates/os/browser/data/ca/README.md\0"
bdst_ca:        .ascii "out/os/browser_mitm/data/ca/README.md\0"
bsrc_opt:       .ascii "templates/os/browser/optional/spark_network_hooks.md\0"
bdst_opt:       .ascii "out/os/browser_mitm/optional/spark_network_hooks.md\0"

.section .text

# ------------------------------------------------------------
os_ops_dispatch:
    push    rbx
    lea     rsi, [rip+msg_os]
    mov     rdx, msg_os_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_design]
    call    contains
    test    rax, rax
    jnz     os_design

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_specify]
    call    contains
    test    rax, rax
    jnz     os_specify

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_generate]
    call    contains
    test    rax, rax
    jnz     os_generate

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_build]
    call    contains
    test    rax, rax
    jnz     os_build

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_explain]
    call    contains
    test    rax, rax
    jnz     os_explain

    # unknown — print remainder of line
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      os_unk_nl
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
os_unk_nl:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout
    pop     rbx
    ret

# --- design ---
os_design:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      od_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
od_noq:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    call    pick_design
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

pick_design:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_browser]
    call    contains
    test    rax, rax
    jnz     pd_browser
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_mitm]
    call    contains
    test    rax, rax
    jnz     pd_browser
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ai_rt]
    call    contains
    test    rax, rax
    jnz     pd_kit
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_kitchen]
    call    contains
    test    rax, rax
    jnz     pd_kit
    lea     rax, [rip+dry_design_agent]
    mov     rcx, dry_design_agent_len
    ret
pd_kit:
    lea     rax, [rip+dry_design_kitchen]
    mov     rcx, dry_design_kitchen_len
    ret
pd_browser:
    lea     rax, [rip+dry_design_browser]
    mov     rcx, dry_design_browser_len
    ret

# --- specify ---
os_specify:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_specify]
    mov     rdx, dry_specify_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# --- explain ---
os_explain:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    call    pick_explain
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

pick_explain:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_browser]
    call    contains
    test    rax, rax
    jnz     pe_browser
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_mitm]
    call    contains
    test    rax, rax
    jnz     pe_browser
    lea     rax, [rip+dry_explain]
    mov     rcx, dry_explain_len
    ret
pe_browser:
    lea     rax, [rip+dry_explain_browser]
    mov     rcx, dry_explain_browser_len
    ret

# --- build (dry-run — no assemble, no dd) ---
os_build:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout
    lea     rsi, [rip+msg_built]
    mov     rdx, msg_built_len
    call    write_stdout
    pop     rbx
    ret

# --- generate: mkdir + copy templates ---
os_generate:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      og_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
og_noq:
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_honesty]
    mov     rdx, msg_honesty_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_browser]
    call    contains
    test    rax, rax
    jnz     og_browser
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_mitm]
    call    contains
    test    rax, rax
    jnz     og_browser
    jmp     og_agentos

og_agentos:
    lea     rdi, [rip+path_out]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_out_os]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_tree]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_tree_opt]
    mov     rsi, 493
    call    sys_mkdir

    lea     rdi, [rip+src_readme]
    lea     rsi, [rip+dst_readme]
    call    copy_file
    lea     rdi, [rip+src_mem]
    lea     rsi, [rip+dst_mem]
    call    copy_file
    lea     rdi, [rip+src_spec]
    lea     rsi, [rip+dst_spec]
    call    copy_file
    lea     rdi, [rip+src_why]
    lea     rsi, [rip+dst_why]
    call    copy_file
    lea     rdi, [rip+src_sys]
    lea     rsi, [rip+dst_sys]
    call    copy_file
    lea     rdi, [rip+src_boot]
    lea     rsi, [rip+dst_boot]
    call    copy_file
    lea     rdi, [rip+src_kern]
    lea     rsi, [rip+dst_kern]
    call    copy_file
    lea     rdi, [rip+src_mk]
    lea     rsi, [rip+dst_mk]
    call    copy_file
    lea     rdi, [rip+src_opt]
    lea     rsi, [rip+dst_opt]
    call    copy_file

    lea     rsi, [rip+msg_wrote]
    mov     rdx, msg_wrote_len
    call    write_stdout
    lea     rsi, [rip+path_tree]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+path_tree]
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_generate_json]
    mov     rdx, dry_generate_json_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

og_browser:
    lea     rdi, [rip+path_out]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_out_os]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_btree]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_docs]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_pkg]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_mitm]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_insp]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_cdp]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_scripts]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_bin]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_tests]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_data]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_ca]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+path_b_opt]
    mov     rsi, 493
    call    sys_mkdir

    lea     rdi, [rip+bsrc_readme]
    lea     rsi, [rip+bdst_readme]
    call    copy_file
    lea     rdi, [rip+bsrc_spec]
    lea     rsi, [rip+bdst_spec]
    call    copy_file
    lea     rdi, [rip+bsrc_why]
    lea     rsi, [rip+bdst_why]
    call    copy_file
    lea     rdi, [rip+bsrc_layout]
    lea     rsi, [rip+bdst_layout]
    call    copy_file
    lea     rdi, [rip+bsrc_mk]
    lea     rsi, [rip+bdst_mk]
    call    copy_file
    lea     rdi, [rip+bsrc_gi]
    lea     rsi, [rip+bdst_gi]
    call    copy_file
    lea     rdi, [rip+bsrc_arch]
    lea     rsi, [rip+bdst_arch]
    call    copy_file
    lea     rdi, [rip+bsrc_pkg]
    lea     rsi, [rip+bdst_pkg]
    call    copy_file
    lea     rdi, [rip+bsrc_mitm]
    lea     rsi, [rip+bdst_mitm]
    call    copy_file
    lea     rdi, [rip+bsrc_insp]
    lea     rsi, [rip+bdst_insp]
    call    copy_file
    lea     rdi, [rip+bsrc_cdp]
    lea     rsi, [rip+bdst_cdp]
    call    copy_file
    lea     rdi, [rip+bsrc_scripts]
    lea     rsi, [rip+bdst_scripts]
    call    copy_file
    lea     rdi, [rip+bsrc_bin]
    lea     rsi, [rip+bdst_bin]
    call    copy_file
    lea     rdi, [rip+bsrc_tests]
    lea     rsi, [rip+bdst_tests]
    call    copy_file
    lea     rdi, [rip+bsrc_ca]
    lea     rsi, [rip+bdst_ca]
    call    copy_file
    lea     rdi, [rip+bsrc_opt]
    lea     rsi, [rip+bdst_opt]
    call    copy_file

    lea     rsi, [rip+msg_wrote]
    mov     rdx, msg_wrote_len
    call    write_stdout
    lea     rsi, [rip+path_btree]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+path_btree]
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+dry_generate_json_browser]
    mov     rdx, dry_generate_json_browser_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_l]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# copy_file: rdi=src cstr, rsi=dst cstr
# uses copy_buf; returns rax=0 ok, -1 fail
copy_file:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi            # src
    mov     r13, rsi            # dst
    mov     rdi, r12
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      cf_fail
    mov     r14, rax            # fd in
    mov     rdi, r14
    lea     rsi, [rip+copy_buf]
    mov     rdx, COPY_MAX
    call    sys_read
    cmp     rax, 0
    jl      cf_close_fail
    mov     rbx, rax            # nbytes
    mov     rdi, r14
    call    sys_close
    mov     rdi, r13
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 420            # 0644
    call    sys_open
    cmp     rax, 0
    jl      cf_fail
    mov     r14, rax
    mov     rdi, r14
    lea     rsi, [rip+copy_buf]
    mov     rdx, rbx
    call    sys_write
    mov     rdi, r14
    call    sys_close
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
cf_close_fail:
    mov     rdi, r14
    call    sys_close
cf_fail:
    mov     rax, -1
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
