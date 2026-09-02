# Spark browser / mitm — first-class language ops (asm syscalls).
# Dry-run: multi-flow fixture HAR under out/browser/ (no GUI).
# Live GUI: only on `browser gui` + --live → fork launch helper.
# Spark language is SoT; spark-browser Qt host is optional helper.
.intel_syntax noprefix
.global browser_ops_dispatch
.global mitm_ops_dispatch

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
.extern honest_question_exit
.extern engine_window_show
.extern engine_ops_dispatch
.extern engine_pipeline_render

.equ MODE_0755, 493
.equ O_RDONLY, 0
.equ HAR_COPY_CAP, 16384

.section .bss
.align 16
session_on:     .space 8
mitm_on:        .space 8
url_buf:        .space 512
script_buf:     .space 512
har_path_buf:   .space 512
gui_argv:       .space 64
har_copy_buf:   .space HAR_COPY_CAP

.section .data
msg_br:     .ascii "[browser] "
msg_br_len = . - msg_br
msg_mitm:   .ascii "[mitm] "
msg_mitm_len = . - msg_mitm
msg_arrow:  .ascii "  → "
msg_arrow_len = . - msg_arrow

needle_run:     .ascii "run\0"
needle_goto:    .ascii "goto\0"
needle_open:    .ascii "open\0"
needle_start:   .ascii "start\0"
needle_gui:     .ascii "gui\0"
needle_show:    .ascii "show\0"
needle_render:  .ascii "render\0"
needle_engine:  .ascii "engine\0"
needle_flags:   .ascii "flags\0"
needle_cdp:     .ascii "cdp\0"
needle_navigate:.ascii "navigate\0"
needle_evaluate:.ascii "evaluate\0"
needle_screenshot: .ascii "screenshot\0"
needle_enable:  .ascii "enable\0"
needle_disable_quic: .ascii "disable_quic\0"
needle_enable_quic:  .ascii "enable_quic\0"
needle_disable: .ascii "disable\0"
needle_quic:    .ascii "quic\0"
needle_divert:  .ascii "divert\0"
needle_smoke:   .ascii "smoke\0"
needle_listen:  .ascii "listen\0"
needle_status:  .ascii "status\0"
needle_remove:  .ascii "remove\0"
needle_har:     .ascii "har\0"
needle_export:  .ascii "export\0"
needle_filter:  .ascii "filter\0"
needle_false:   .ascii "false\0"
needle_ca_init: .ascii "ca-init\0"
needle_ca_initu:.ascii "ca_init\0"
needle_ca_inst: .ascii "ca-install\0"
needle_ca_instu:.ascii "ca_install\0"
needle_ca_stat: .ascii "ca-status\0"
needle_ca_statu:.ascii "ca_status\0"
needle_ca:      .ascii "ca\0"

path_out:       .ascii "out\0"
path_browser:   .ascii "out/browser\0"
path_ca_dir:    .ascii "out/browser/ca\0"
path_session:   .ascii "out/browser/session.json\0"
path_mitm:      .ascii "out/browser/mitm.json\0"
path_ca_json:   .ascii "out/browser/ca.json\0"
default_har:    .ascii "out/browser/session.har\0"
default_url:    .ascii "https://example.com/\0"
default_script: .ascii "examples/browser_main.spark\0"
# Dry/demo multi-flow HAR (document + CSS + CDN JS + API + favicon)
fixture_har:    .ascii "examples/fixtures/browser/demo_multiflow.har\0"

gui_bin:        .ascii "./spark-browser-host\0"
gui_arg0:       .ascii "spark-browser-host\0"
gui_url_flag:   .ascii "--url\0"
gui_dq_flag:    .ascii "--disable-quic\0"
gui_eq_flag:    .ascii "--enable-quic\0"
quic_bin:       .ascii "./spark-mitm-quic\0"
quic_arg0:      .ascii "spark-mitm-quic\0"
quic_smoke_flag:.ascii "--smoke\0"
quic_listen_flag:.ascii "--listen\0"
divert_bin:     .ascii "./spark-mitm-quic-divert\0"
divert_arg0:    .ascii "spark-mitm-quic-divert\0"
divert_enable:  .ascii "enable\0"
divert_disable: .ascii "disable\0"
divert_status:  .ascii "status\0"
ca_bin:         .ascii "./spark-mitm-ca\0"
ca_arg0:        .ascii "spark-mitm-ca\0"
ca_init_flag:   .ascii "--init\0"
ca_install_flag:.ascii "--install\0"
ca_status_flag: .ascii "--status\0"
h2_bin:         .ascii "./spark-mitm-h2\0"
h2_arg0:        .ascii "spark-mitm-h2\0"
h2_serve:       .ascii "serve\0"
h2_daemon:      .ascii "--daemon\0"
h2_smoke:       .ascii "--smoke\0"
h2_stop:        .ascii "stop\0"
cdp_bin:        .ascii "./spark-browser-cdp\0"
cdp_arg0:       .ascii "spark-browser-cdp\0"
cdp_status:     .ascii "status\0"
cdp_navigate:   .ascii "navigate\0"
cdp_evaluate:   .ascii "evaluate\0"
cdp_screenshot: .ascii "screenshot\0"
cdp_url_flag:   .ascii "--url\0"
cdp_expr_flag:  .ascii "--expr\0"
cdp_out_flag:   .ascii "--out\0"
default_shot:   .ascii "out/browser/cdp-shot.png\0"

err_br_unknown:
    .ascii "error: unknown browser op"
    .ascii " (want: run|goto|open|start|gui|show|render|engine|flags|cdp)\n"
err_br_unknown_len = . - err_br_unknown
err_cdp_fail:
    .ascii "error: browser cdp helper failed"
    .ascii " (./spark-browser-cdp; need :9222"
    .ascii " live or dry mocks)\n"
err_cdp_fail_len = . - err_cdp_fail
err_mitm_unknown:
    .ascii "error: unknown mitm op"
    .ascii " (want: enable|disable|disable_quic|"
    .ascii " ca-init|ca-install|ca-status|"
    .ascii " quic listen|status|smoke|divert|"
    .ascii " smoke|har|filter)\n"
err_mitm_unknown_len = . - err_mitm_unknown
err_quic_smoke:
    .ascii "error: mitm quic smoke failed"
    .ascii " (./spark-mitm-quic --smoke; aioquic)\n"
err_quic_smoke_len = . - err_quic_smoke
err_quic_divert:
    .ascii "error: mitm quic divert failed"
    .ascii " (./spark-mitm-quic-divert;"
    .ascii " needs SPARK_QUIC_DIVERT=1 to apply)\n"
err_quic_divert_len = . - err_quic_divert
err_quic_listen:
    .ascii "error: mitm quic listen failed"
    .ascii " (./spark-mitm-quic --listen)\n"
err_quic_listen_len = . - err_quic_listen
err_h2_smoke:
    .ascii "error: mitm smoke failed"
    .ascii " (./spark-mitm-h2 --smoke)\n"
err_h2_smoke_len = . - err_h2_smoke
err_h2_enable:
    .ascii "error: live mitm enable failed"
    .ascii " (./spark-mitm-h2 serve --daemon)\n"
err_h2_enable_len = . - err_h2_enable
err_ca_init:
    .ascii "error: mitm ca-init failed"
    .ascii " (./spark-mitm-ca --init;"
    .ascii " needs cryptography)\n"
err_ca_init_len = . - err_ca_init
err_ca_install_live:
    .ascii "error: mitm ca-install requires --live"
    .ascii " (never auto-trust in dry-run)\n"
err_ca_install_live_len = . - err_ca_install_live
err_ca_install:
    .ascii "error: mitm ca-install failed"
    .ascii " (./spark-mitm-ca --install;"
    .ascii " see install-ca.sh)\n"
err_ca_install_len = . - err_ca_install
err_no_session:
    .ascii "error: browser session required"
    .ascii " (browser run|open first)\n"
err_no_session_len = . - err_no_session
err_no_mitm:
    .ascii "error: mitm har export requires"
    .ascii " mitm enable first\n"
err_no_mitm_len = . - err_no_mitm
err_gui_need_live:
    .ascii "error: browser gui requires --live"
    .ascii " (dry-run never launches host GUI)\n"
err_gui_need_live_len = . - err_gui_need_live
err_gui_fail:
    .ascii "error: browser gui launch helper failed"
    .ascii " (see ./spark-browser-host)\n"
err_gui_fail_len = . - err_gui_fail

# --- JSON fragments (real artifacts, not print-only stubs) ---
j_sess_pre:
    .ascii "{\"op\":\"run\",\"ok\":true,\"mode\":\"dry-run\","
    .ascii "\"session\":\"out/browser\","
    .ascii "\"script\":\""
j_sess_pre_len = . - j_sess_pre
j_sess_mid:
    .ascii "\",\"url\":\""
j_sess_mid_len = . - j_sess_mid
j_sess_suf:
    .ascii "\",\"gui\":false,"
    .ascii "\"disable_quic\":false,"
    .ascii "\"chromium_flag\":\"--enable-quic\","
    .ascii "\"note\":\"language session; GUI only via"
    .ascii " browser gui --live; QUIC on by default\"}"
j_sess_suf_len = . - j_sess_suf

j_flags:
    .ascii "{\"op\":\"flags\",\"disable_quic\":false,"
    .ascii "\"default\":false,\"override\":"
    .ascii "\"mitm disable_quic on |"
    .ascii " browser gui --disable-quic\","
    .ascii "\"entrypoint\":\"spark language\"}"
j_flags_len = . - j_flags

j_disable_quic_on:
    .ascii "{\"op\":\"disable_quic\",\"value\":true,"
    .ascii "\"chromium_flag\":\"--disable-quic\","
    .ascii "\"note\":\"optional TCP h2/h1-only MITM\"}"
j_disable_quic_on_len = . - j_disable_quic_on

j_disable_quic_off:
    .ascii "{\"op\":\"disable_quic\",\"value\":false,"
    .ascii "\"note\":\"product default; divert→quic listen\"}"
j_disable_quic_off_len = . - j_disable_quic_off

j_quic_status:
    .ascii "{\"op\":\"mitm.quic.status\",\"forge\":\"aioquic\","
    .ascii "\"alpn\":\"h3\",\"bind\":\"UDP\","
    .ascii "\"browser_default\":\"quic_on\","
    .ascii "\"sni_leaves\":\"dynamic\","
    .ascii "\"connect_udp\":\"501_qt_tcp_only\","
    .ascii "\"helper\":\"./spark-mitm-quic\","
    .ascii "\"divert\":\"./spark-mitm-quic-divert\","
    .ascii "\"note\":\"QUIC on; UDP=divert→listen;"
    .ascii " CONNECT-UDP unsupported on Qt\"}"
j_quic_status_len = . - j_quic_status

j_quic_listen:
    .ascii "{\"op\":\"mitm.quic.listen\",\"claimed\":false,"
    .ascii "\"note\":\"dry-run plan; --live forks"
    .ascii " ./spark-mitm-quic --listen\"}"
j_quic_listen_len = . - j_quic_listen

j_quic_listen_ok:
    .ascii "{\"op\":\"mitm.quic.listen\",\"ok\":true,"
    .ascii "\"via\":\"./spark-mitm-quic --listen\"}"
j_quic_listen_ok_len = . - j_quic_listen_ok

j_quic_smoke_ok:
    .ascii "{\"op\":\"mitm.quic.smoke\",\"ok\":true,"
    .ascii "\"via\":\"./spark-mitm-quic --smoke\"}"
j_quic_smoke_ok_len = . - j_quic_smoke_ok

j_quic_smoke_dry:
    .ascii "{\"op\":\"mitm.quic.smoke\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\",\"forked\":false,"
    .ascii "\"via\":\"./spark-mitm-quic --smoke\","
    .ascii "\"note\":\"--live forks aioquic smoke;"
    .ascii " dry never binds UDP (divert-safe)\"}"
j_quic_smoke_dry_len = . - j_quic_smoke_dry

j_quic_divert_plan:
    .ascii "{\"op\":\"mitm.quic.divert\",\"planned\":true,"
    .ascii "\"live\":false,\"apply\":false,"
    .ascii "\"env\":\"SPARK_QUIC_DIVERT\","
    .ascii "\"scope\":\"uid\",\"note\":\"dry-run plan only;"
    .ascii " --live + SPARK_QUIC_DIVERT=1 to apply;"
    .ascii " revert: quic-udp-divert.sh --remove\"}"
j_quic_divert_plan_len = . - j_quic_divert_plan

j_quic_divert_ok:
    .ascii "{\"op\":\"mitm.quic.divert\",\"ok\":true,"
    .ascii "\"via\":\"./spark-mitm-quic-divert\","
    .ascii "\"note\":\"companion applies only when"
    .ascii " SPARK_QUIC_DIVERT=1\"}"
j_quic_divert_ok_len = . - j_quic_divert_ok

j_goto_pre:
    .ascii "{\"op\":\"goto\",\"ok\":true,\"url\":\""
j_goto_pre_len = . - j_goto_pre
j_goto_suf:
    .ascii "\"}"
j_goto_suf_len = . - j_goto_suf

j_cdp_status_dry:
    .ascii "{\"op\":\"cdp.status\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\",\"host\":\"127.0.0.1\","
    .ascii "\"port\":9222,\"connected\":false,"
    .ascii "\"claimed\":false,"
    .ascii "\"helper\":\"./spark-browser-cdp\","
    .ascii "\"note\":\"dry never dials :9222;"
    .ascii " --live forks companion\"}"
j_cdp_status_dry_len = . - j_cdp_status_dry

j_cdp_nav_dry_pre:
    .ascii "{\"op\":\"cdp.navigate\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\",\"claimed\":false,"
    .ascii "\"url\":\""
j_cdp_nav_dry_pre_len = . - j_cdp_nav_dry_pre
j_cdp_nav_dry_suf:
    .ascii "\",\"helper\":\"./spark-browser-cdp\"}"
j_cdp_nav_dry_suf_len = . - j_cdp_nav_dry_suf

j_cdp_eval_dry:
    .ascii "{\"op\":\"cdp.evaluate\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\",\"claimed\":false,"
    .ascii "\"result\":null,"
    .ascii "\"helper\":\"./spark-browser-cdp\"}"
j_cdp_eval_dry_len = . - j_cdp_eval_dry

j_cdp_shot_dry:
    .ascii "{\"op\":\"cdp.screenshot\",\"ok\":true,"
    .ascii "\"mode\":\"dry-run\",\"claimed\":false,"
    .ascii "\"path\":\"out/browser/cdp-shot.png\","
    .ascii "\"helper\":\"./spark-browser-cdp\","
    .ascii "\"note\":\"dry JSON only; --live writes"
    .ascii " PNG via CDP\"}"
j_cdp_shot_dry_len = . - j_cdp_shot_dry

j_mitm_on:
    .ascii "{\"op\":\"enable\",\"ok\":true,"
    .ascii "\"proxy\":\"127.0.0.1:8877\","
    .ascii "\"cdp\":\"127.0.0.1:9222\","
    .ascii "\"scope\":\"owner-local\","
    .ascii "\"owner\":\"spark-mitm-h2\","
    .ascii "\"mode\":\"dry-run-session\"}"
j_mitm_on_len = . - j_mitm_on

j_mitm_on_live:
    .ascii "{\"op\":\"enable\",\"ok\":true,"
    .ascii "\"proxy\":\"127.0.0.1:8877\","
    .ascii "\"cdp\":\"127.0.0.1:9222\","
    .ascii "\"scope\":\"owner-local\","
    .ascii "\"owner\":\"spark-mitm-h2\","
    .ascii "\"mode\":\"live\","
    .ascii "\"helper\":\"serve --daemon\"}"
j_mitm_on_live_len = . - j_mitm_on_live

j_mitm_off:
    .ascii "{\"op\":\"disable\",\"ok\":true}"
j_mitm_off_len = . - j_mitm_off

j_h2_smoke_ok:
    .ascii "{\"op\":\"mitm.smoke\",\"ok\":true,"
    .ascii "\"owner\":\"spark-mitm-h2\","
    .ascii "\"via\":\"./spark-mitm-h2 --smoke\"}"
j_h2_smoke_ok_len = . - j_h2_smoke_ok

j_filter_pre:
    .ascii "{\"op\":\"filter\",\"ok\":true,\"pattern\":\""
j_filter_pre_len = . - j_filter_pre
j_filter_suf:
    .ascii "\"}"
j_filter_suf_len = . - j_filter_suf

# Fallback single-entry HAR 1.2 if fixture missing (URL splice)
har_pre:
    .ascii "{\"log\":{\"version\":\"1.2\","
    .ascii "\"creator\":{\"name\":\"spark\","
    .ascii "\"version\":\"asm-browser\"},"
    .ascii "\"entries\":[{\"startedDateTime\":"
    .ascii "\"2026-08-31T00:00:00.000Z\",\"time\":1,"
    .ascii "\"request\":{\"method\":\"GET\",\"url\":\""
har_pre_len = . - har_pre
har_mid:
    .ascii "\",\"httpVersion\":\"HTTP/1.1\","
    .ascii "\"cookies\":[],\"headers\":[],"
    .ascii "\"queryString\":[],\"headersSize\":-1,"
    .ascii "\"bodySize\":0},"
    .ascii "\"response\":{\"status\":200,"
    .ascii "\"statusText\":\"OK\","
    .ascii "\"httpVersion\":\"HTTP/1.1\","
    .ascii "\"cookies\":[],\"headers\":[],"
    .ascii "\"content\":{\"size\":0,"
    .ascii "\"mimeType\":\"text/html\",\"text\":\"\"},"
    .ascii "\"redirectURL\":\"\",\"headersSize\":-1,"
    .ascii "\"bodySize\":0},\"cache\":{},"
    .ascii "\"timings\":{\"send\":0,\"wait\":0,"
    .ascii "\"receive\":0}}]}}"
har_mid_len = . - har_mid

j_har_pre:
    .ascii "{\"op\":\"har_export\",\"ok\":true,"
    .ascii "\"format\":\"HAR1.2\","
    .ascii "\"demo\":\"multiflow\",\"path\":\""
j_har_pre_len = . - j_har_pre
j_har_suf:
    .ascii "\",\"byte_written\":true}"
j_har_suf_len = . - j_har_suf

j_ca_init:
    .ascii "{\"op\":\"ca_init\",\"ok\":true,"
    .ascii "\"ca_dir\":\"out/browser/ca\","
    .ascii "\"system_trust\":\"never auto\","
    .ascii "\"install\":\"mitm ca-install\","
    .ascii "\"helper\":\"./spark-mitm-ca --init\","
    .ascii "\"note\":\"RSA CA via helper;"
    .ascii " language SoT is this op\"}"
j_ca_init_len = . - j_ca_init

j_ca_install_plan:
    .ascii "{\"op\":\"ca_install\",\"ok\":true,"
    .ascii "\"planned\":true,\"live\":false,"
    .ascii "\"system_trust\":\"never auto\","
    .ascii "\"note\":\"dry-run plan only;"
    .ascii " re-run with --live to NSS\"}"
j_ca_install_plan_len = . - j_ca_install_plan

j_ca_install_ok:
    .ascii "{\"op\":\"ca_install\",\"ok\":true,"
    .ascii "\"live\":true,"
    .ascii "\"via\":\"./spark-mitm-ca --install\","
    .ascii "\"note\":\"owner NSS/system trust\"}"
j_ca_install_ok_len = . - j_ca_install_ok

j_ca_status_ok:
    .ascii "{\"op\":\"ca_status\",\"ok\":true,"
    .ascii "\"present\":true,"
    .ascii "\"ca_dir\":\"out/browser/ca\","
    .ascii "\"helper\":\"./spark-mitm-ca --status\"}"
j_ca_status_ok_len = . - j_ca_status_ok

j_ca_status_miss:
    .ascii "{\"op\":\"ca_status\",\"ok\":false,"
    .ascii "\"present\":false,"
    .ascii "\"hint\":\"mitm ca-init first\"}"
j_ca_status_miss_len = . - j_ca_status_miss

# scratch for assembled session/HAR body
.section .bss
.align 16
assemble_buf:   .space 4096

.section .text

# ------------------------------------------------------------
browser_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_br]
    mov     rdx, msg_br_len
    call    write_stdout

    # run/open/start/goto/gui/flags before cdp — path may contain "cdp"
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_flags]
    call    contains
    test    rax, rax
    jnz     br_flags

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_goto]
    call    contains
    test    rax, rax
    jnz     br_goto

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_gui]
    call    contains
    test    rax, rax
    jnz     br_gui

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_render]
    call    contains
    test    rax, rax
    jnz     br_render

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_engine]
    call    contains
    test    rax, rax
    jnz     br_engine

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_show]
    call    contains
    test    rax, rax
    jnz     br_show

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_run]
    call    contains
    test    rax, rax
    jnz     br_run

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_open]
    call    contains
    test    rax, rax
    jnz     br_run

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_start]
    call    contains
    test    rax, rax
    jnz     br_run

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_cdp]
    call    contains
    test    rax, rax
    jnz     br_cdp

    lea     rsi, [rip+err_br_unknown]
    mov     rdx, err_br_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- browser flags ----------
br_flags:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_flags]
    mov     rdx, j_flags_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     br_done

# ---------- browser run|open|start ----------
br_run:
    call    ensure_browser_dirs
    # script quote or default
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      br_run_def_script
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+script_buf]
    xor     r13, r13
br_copy_script:
    cmp     r13, r12
    jge     br_script_ok
    cmp     r13, 510
    jge     br_script_ok
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     br_copy_script
br_run_def_script:
    lea     rsi, [rip+default_script]
    lea     rdi, [rip+script_buf]
    call    copy_cstr
    jmp     br_have_url
br_script_ok:
    mov     byte ptr [rdi+r13], 0
    # default URL if empty
br_have_url:
    cmp     byte ptr [rip+url_buf], 0
    jne     br_sess_on
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
br_sess_on:
    mov     qword ptr [rip+session_on], 1
    call    write_session_json
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
    mov     rcx, rax
    lea     rax, [rip+assemble_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done

# ---------- browser goto ----------
br_goto:
    cmp     qword ptr [rip+session_on], 1
    je      br_goto_ok
    lea     rsi, [rip+err_no_session]
    mov     rdx, err_no_session_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
br_goto_ok:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      br_goto_def
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+url_buf]
    xor     r13, r13
br_copy_url:
    cmp     r13, r12
    jge     br_url_term
    cmp     r13, 510
    jge     br_url_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     br_copy_url
br_goto_def:
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
    jmp     br_url_ready
br_url_term:
    mov     byte ptr [rdi+r13], 0
br_url_ready:
    call    write_session_json
    # stdout JSON
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_goto_pre]
    mov     rdx, j_goto_pre_len
    call    write_stdout
    lea     rsi, [rip+url_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+url_buf]
    call    write_stdout
    lea     rsi, [rip+j_goto_suf]
    mov     rdx, j_goto_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    # last_val = url
    lea     rsi, [rip+url_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+url_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done

# ---------- browser gui (--live only) ----------
br_gui:
    cmp     qword ptr [rip+flag_live], 1
    je      br_gui_live
    lea     rsi, [rip+err_gui_need_live]
    mov     rdx, err_gui_need_live_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
br_gui_live:
    cmp     qword ptr [rip+session_on], 1
    je      br_gui_sess
    call    ensure_browser_dirs
    mov     qword ptr [rip+session_on], 1
    cmp     byte ptr [rip+url_buf], 0
    jne     br_gui_sess
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
br_gui_sess:
    # argv: host --url URL [--enable-quic|--disable-quic]
    # Product default: --enable-quic (divert→listen UDP path).
    lea     rax, [rip+gui_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+gui_url_flag]
    mov     [rip+gui_argv+8], rax
    lea     rax, [rip+url_buf]
    mov     [rip+gui_argv+16], rax
    # disable_quic (without false) → --disable-quic; else enable
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_disable_quic]
    call    contains
    test    rax, rax
    jz      br_gui_eq
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_false]
    call    contains
    test    rax, rax
    jnz     br_gui_eq
br_gui_dq:
    lea     rax, [rip+gui_dq_flag]
    mov     [rip+gui_argv+24], rax
    mov     qword ptr [rip+gui_argv+32], 0
    jmp     br_gui_exec
br_gui_eq:
    lea     rax, [rip+gui_eq_flag]
    mov     [rip+gui_argv+24], rax
    mov     qword ptr [rip+gui_argv+32], 0
br_gui_exec:
    lea     rdi, [rip+gui_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     br_gui_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_goto_pre]
    mov     rdx, j_goto_pre_len
    call    write_stdout
    lea     rsi, [rip+url_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+url_buf]
    call    write_stdout
    lea     rsi, [rip+j_goto_suf]
    mov     rdx, j_goto_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     br_done
br_gui_fail:
    lea     rsi, [rip+err_gui_fail]
    mov     rdx, err_gui_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- browser show (engine B window; dry = no X11) ----------
br_show:
    call    engine_window_show
    jmp     br_done

# ---------- browser render / browser engine … (engine B pipeline) ----------
br_render:
    call    engine_pipeline_render
    jmp     br_done

br_engine:
    call    engine_ops_dispatch
    jmp     br_done


# ---------- browser cdp status|navigate|evaluate|screenshot ----------
# Dry-run: JSON mocks (never dial :9222).
# --live: fork ./spark-browser-cdp (real CDP client).
br_cdp:
    call    ensure_browser_dirs
    cmp     qword ptr [rip+session_on], 1
    je      br_cdp_have_sess
    mov     qword ptr [rip+session_on], 1
br_cdp_have_sess:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_navigate]
    call    contains
    test    rax, rax
    jnz     br_cdp_nav

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_evaluate]
    call    contains
    test    rax, rax
    jnz     br_cdp_eval

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_screenshot]
    call    contains
    test    rax, rax
    jnz     br_cdp_shot

    jmp     br_cdp_status

br_cdp_status:
    cmp     qword ptr [rip+flag_live], 1
    je      br_cdp_status_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_cdp_status_dry]
    mov     rdx, j_cdp_status_dry_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_cdp_status_dry]
    mov     rcx, j_cdp_status_dry_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done
br_cdp_status_live:
    lea     rax, [rip+cdp_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+cdp_status]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+cdp_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     br_cdp_fail
    jmp     br_done

br_cdp_nav:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      br_cdp_nav_def
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+url_buf]
    xor     r13, r13
br_cdp_nav_copy:
    cmp     r13, r12
    jge     br_cdp_nav_term
    cmp     r13, 510
    jge     br_cdp_nav_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     br_cdp_nav_copy
br_cdp_nav_def:
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
    jmp     br_cdp_nav_ready
br_cdp_nav_term:
    mov     byte ptr [rdi+r13], 0
br_cdp_nav_ready:
    cmp     qword ptr [rip+flag_live], 1
    je      br_cdp_nav_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_cdp_nav_dry_pre]
    mov     rdx, j_cdp_nav_dry_pre_len
    call    write_stdout
    lea     rsi, [rip+url_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+url_buf]
    call    write_stdout
    lea     rsi, [rip+j_cdp_nav_dry_suf]
    mov     rdx, j_cdp_nav_dry_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+url_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+url_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done
br_cdp_nav_live:
    lea     rax, [rip+cdp_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+cdp_navigate]
    mov     [rip+gui_argv+8], rax
    lea     rax, [rip+cdp_url_flag]
    mov     [rip+gui_argv+16], rax
    lea     rax, [rip+url_buf]
    mov     [rip+gui_argv+24], rax
    mov     qword ptr [rip+gui_argv+32], 0
    lea     rdi, [rip+cdp_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     br_cdp_fail
    jmp     br_done

br_cdp_eval:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      br_cdp_eval_def
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+script_buf]
    xor     r13, r13
br_cdp_eval_copy:
    cmp     r13, r12
    jge     br_cdp_eval_term
    cmp     r13, 510
    jge     br_cdp_eval_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     br_cdp_eval_copy
br_cdp_eval_def:
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+script_buf]
    call    copy_cstr
    jmp     br_cdp_eval_ready
br_cdp_eval_term:
    mov     byte ptr [rdi+r13], 0
br_cdp_eval_ready:
    cmp     qword ptr [rip+flag_live], 1
    je      br_cdp_eval_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_cdp_eval_dry]
    mov     rdx, j_cdp_eval_dry_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_cdp_eval_dry]
    mov     rcx, j_cdp_eval_dry_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done
br_cdp_eval_live:
    lea     rax, [rip+cdp_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+cdp_evaluate]
    mov     [rip+gui_argv+8], rax
    lea     rax, [rip+cdp_expr_flag]
    mov     [rip+gui_argv+16], rax
    lea     rax, [rip+script_buf]
    mov     [rip+gui_argv+24], rax
    mov     qword ptr [rip+gui_argv+32], 0
    lea     rdi, [rip+cdp_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     br_cdp_fail
    jmp     br_done

br_cdp_shot:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      br_cdp_shot_def
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+har_path_buf]
    xor     r13, r13
br_cdp_shot_copy:
    cmp     r13, r12
    jge     br_cdp_shot_term
    cmp     r13, 510
    jge     br_cdp_shot_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     br_cdp_shot_copy
br_cdp_shot_def:
    lea     rsi, [rip+default_shot]
    lea     rdi, [rip+har_path_buf]
    call    copy_cstr
    jmp     br_cdp_shot_ready
br_cdp_shot_term:
    mov     byte ptr [rdi+r13], 0
br_cdp_shot_ready:
    cmp     qword ptr [rip+flag_live], 1
    je      br_cdp_shot_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_cdp_shot_dry]
    mov     rdx, j_cdp_shot_dry_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_cdp_shot_dry]
    mov     rcx, j_cdp_shot_dry_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     br_done
br_cdp_shot_live:
    lea     rax, [rip+cdp_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+cdp_screenshot]
    mov     [rip+gui_argv+8], rax
    lea     rax, [rip+cdp_out_flag]
    mov     [rip+gui_argv+16], rax
    lea     rax, [rip+har_path_buf]
    mov     [rip+gui_argv+24], rax
    mov     qword ptr [rip+gui_argv+32], 0
    lea     rdi, [rip+cdp_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     br_cdp_fail
    jmp     br_done

br_cdp_fail:
    lea     rsi, [rip+err_cdp_fail]
    mov     rdx, err_cdp_fail_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

br_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
mitm_ops_dispatch:
    push    rbx
    push    r12
    push    r13

    lea     rsi, [rip+msg_mitm]
    mov     rdx, msg_mitm_len
    call    write_stdout

    # disable_quic before bare disable (substring)
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_disable_quic]
    call    contains
    test    rax, rax
    jnz     mitm_dq

    # ca-init / ca-install / ca-status before quic (status)
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_init]
    call    contains
    test    rax, rax
    jnz     mitm_ca_init
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_initu]
    call    contains
    test    rax, rax
    jnz     mitm_ca_init

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_inst]
    call    contains
    test    rax, rax
    jnz     mitm_ca_install
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_instu]
    call    contains
    test    rax, rax
    jnz     mitm_ca_install

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_stat]
    call    contains
    test    rax, rax
    jnz     mitm_ca_status
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca_statu]
    call    contains
    test    rax, rax
    jnz     mitm_ca_status
    # "mitm ca status" (space form)
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_ca]
    call    contains
    test    rax, rax
    jz      mitm_after_ca
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_status]
    call    contains
    test    rax, rax
    jnz     mitm_ca_status
mitm_after_ca:

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_quic]
    call    contains
    test    rax, rax
    jnz     mitm_quic

    # bare `mitm smoke` → HTTPS h2/h1 forge (Spark-owned)
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_smoke]
    call    contains
    test    rax, rax
    jnz     mitm_h2_smoke

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_enable]
    call    contains
    test    rax, rax
    jnz     mitm_enable

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_disable]
    call    contains
    test    rax, rax
    jnz     mitm_disable

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_filter]
    call    contains
    test    rax, rax
    jnz     mitm_filter

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_har]
    call    contains
    test    rax, rax
    jnz     mitm_har

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_export]
    call    contains
    test    rax, rax
    jnz     mitm_har

    lea     rsi, [rip+err_mitm_unknown]
    mov     rdx, err_mitm_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- mitm ca-init ----------
mitm_ca_init:
    call    ensure_browser_dirs
    lea     rax, [rip+ca_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+ca_init_flag]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+ca_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_ca_init_fail
    lea     rdi, [rip+path_ca_json]
    lea     rsi, [rip+j_ca_init]
    mov     rdx, j_ca_init_len
    call    write_bytes_path
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_ca_init]
    mov     rdx, j_ca_init_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_ca_init]
    mov     rcx, j_ca_init_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_ca_init_fail:
    lea     rsi, [rip+err_ca_init]
    mov     rdx, err_ca_init_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- mitm ca-install (live only) ----------
mitm_ca_install:
    cmp     qword ptr [rip+flag_live], 1
    je      mitm_ca_inst_live
    # dry-run: plan only — never auto trust
    call    ensure_browser_dirs
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_ca_install_plan]
    mov     rdx, j_ca_install_plan_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_ca_install_plan]
    mov     rcx, j_ca_install_plan_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_ca_inst_live:
    lea     rax, [rip+ca_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+ca_install_flag]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+ca_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_ca_inst_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_ca_install_ok]
    mov     rdx, j_ca_install_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_ca_inst_fail:
    lea     rsi, [rip+err_ca_install]
    mov     rdx, err_ca_install_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- mitm ca-status ----------
mitm_ca_status:
    lea     rax, [rip+ca_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+ca_status_flag]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+ca_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_ca_stat_miss
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_ca_status_ok]
    mov     rdx, j_ca_status_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_ca_stat_miss:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_ca_status_miss]
    mov     rdx, j_ca_status_miss_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done

# ---------- mitm disable_quic on|off ----------
mitm_dq:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_false]
    call    contains
    test    rax, rax
    jnz     mitm_dq_off
    # " off" / enable_quic style
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_enable_quic]
    call    contains
    test    rax, rax
    jnz     mitm_dq_off
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_disable_quic_on]
    mov     rdx, j_disable_quic_on_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_dq_off:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_disable_quic_off]
    mov     rdx, j_disable_quic_off_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done

# ---------- mitm quic listen|status|smoke|divert ----------
mitm_quic:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_divert]
    call    contains
    test    rax, rax
    jnz     mitm_quic_divert

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_smoke]
    call    contains
    test    rax, rax
    jnz     mitm_quic_smoke

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_listen]
    call    contains
    test    rax, rax
    jnz     mitm_quic_listen

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_status]
    mov     rdx, j_quic_status_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done

# divert enable|disable|status — dry-run = plan only (never apply)
mitm_quic_divert:
    cmp     qword ptr [rip+flag_live], 1
    je      mitm_quic_divert_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_divert_plan]
    mov     rdx, j_quic_divert_plan_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_quic_divert_plan]
    mov     rcx, j_quic_divert_plan_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_quic_divert_live:
    lea     rax, [rip+divert_arg0]
    mov     [rip+gui_argv], rax
    # default status; enable/disable/remove from line
    lea     rax, [rip+divert_status]
    mov     [rip+gui_argv+8], rax
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_remove]
    call    contains
    test    rax, rax
    jz      mitm_qd_chk_dis
    lea     rax, [rip+divert_disable]
    mov     [rip+gui_argv+8], rax
    jmp     mitm_qd_fork
mitm_qd_chk_dis:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_disable]
    call    contains
    test    rax, rax
    jz      mitm_qd_chk_en
    lea     rax, [rip+divert_disable]
    mov     [rip+gui_argv+8], rax
    jmp     mitm_qd_fork
mitm_qd_chk_en:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_enable]
    call    contains
    test    rax, rax
    jz      mitm_qd_fork
    lea     rax, [rip+divert_enable]
    mov     [rip+gui_argv+8], rax
mitm_qd_fork:
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+divert_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_quic_divert_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_divert_ok]
    mov     rdx, j_quic_divert_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_quic_divert_fail:
    lea     rsi, [rip+err_quic_divert]
    mov     rdx, err_quic_divert_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

mitm_quic_listen:
    cmp     qword ptr [rip+flag_live], 1
    je      mitm_quic_listen_live
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_listen]
    mov     rdx, j_quic_listen_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_quic_listen_live:
    lea     rax, [rip+quic_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+quic_listen_flag]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+quic_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_quic_listen_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_listen_ok]
    mov     rdx, j_quic_listen_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_quic_listen_fail:
    lea     rsi, [rip+err_quic_listen]
    mov     rdx, err_quic_listen_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

mitm_quic_smoke:
    cmp     qword ptr [rip+flag_live], 1
    je      mitm_quic_smoke_live
    # dry-run: never fork aioquic — live divert UDP can hang smoke
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_smoke_dry]
    mov     rdx, j_quic_smoke_dry_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_quic_smoke_dry]
    mov     rcx, j_quic_smoke_dry_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_quic_smoke_live:
    lea     rax, [rip+quic_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+quic_smoke_flag]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+quic_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_quic_smoke_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_quic_smoke_ok]
    mov     rdx, j_quic_smoke_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_quic_smoke_fail:
    lea     rsi, [rip+err_quic_smoke]
    mov     rdx, err_quic_smoke_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ---------- mitm smoke (HTTPS h2/h1 — Spark-owned helper) ----------
mitm_h2_smoke:
    lea     rax, [rip+h2_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+h2_smoke]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+h2_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_h2_smoke_fail
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_h2_smoke_ok]
    mov     rdx, j_h2_smoke_ok_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_h2_smoke_fail:
    lea     rsi, [rip+err_h2_smoke]
    mov     rdx, err_h2_smoke_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

mitm_enable:
    cmp     qword ptr [rip+session_on], 1
    je      mitm_en_ok
    # auto-start session
    call    ensure_browser_dirs
    mov     qword ptr [rip+session_on], 1
    cmp     byte ptr [rip+url_buf], 0
    jne     mitm_en_ok
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
mitm_en_ok:
    mov     qword ptr [rip+mitm_on], 1
    call    ensure_browser_dirs
    # --live: fork Spark-owned CONNECT MITM daemon
    cmp     qword ptr [rip+flag_live], 1
    je      mitm_en_live
    lea     rdi, [rip+path_mitm]
    lea     rsi, [rip+j_mitm_on]
    mov     rdx, j_mitm_on_len
    call    write_bytes_path
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_mitm_on]
    mov     rdx, j_mitm_on_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_mitm_on]
    mov     rcx, j_mitm_on_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_en_live:
    lea     rax, [rip+h2_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+h2_serve]
    mov     [rip+gui_argv+8], rax
    lea     rax, [rip+h2_daemon]
    mov     [rip+gui_argv+16], rax
    mov     qword ptr [rip+gui_argv+24], 0
    lea     rdi, [rip+h2_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
    test    rax, rax
    jnz     mitm_en_live_fail
    lea     rdi, [rip+path_mitm]
    lea     rsi, [rip+j_mitm_on_live]
    mov     rdx, j_mitm_on_live_len
    call    write_bytes_path
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_mitm_on_live]
    mov     rdx, j_mitm_on_live_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+j_mitm_on_live]
    mov     rcx, j_mitm_on_live_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done
mitm_en_live_fail:
    lea     rsi, [rip+err_h2_enable]
    mov     rdx, err_h2_enable_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

mitm_disable:
    mov     qword ptr [rip+mitm_on], 0
    cmp     qword ptr [rip+flag_live], 1
    jne     mitm_dis_print
    lea     rax, [rip+h2_arg0]
    mov     [rip+gui_argv], rax
    lea     rax, [rip+h2_stop]
    mov     [rip+gui_argv+8], rax
    mov     qword ptr [rip+gui_argv+16], 0
    lea     rdi, [rip+h2_bin]
    lea     rsi, [rip+gui_argv]
    call    fork_exec_wait
mitm_dis_print:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_mitm_off]
    mov     rdx, j_mitm_off_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done

mitm_filter:
    cmp     qword ptr [rip+mitm_on], 1
    je      mitm_filt_ok
    lea     rsi, [rip+err_no_mitm]
    mov     rdx, err_no_mitm_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
mitm_filt_ok:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      mitm_filt_empty
    mov     r12, rax
    mov     r13, rcx
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_filter_pre]
    mov     rdx, j_filter_pre_len
    call    write_stdout
    mov     rsi, r12
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+j_filter_suf]
    mov     rdx, j_filter_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done
mitm_filt_empty:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_filter_pre]
    mov     rdx, j_filter_pre_len
    call    write_stdout
    lea     rsi, [rip+j_filter_suf]
    mov     rdx, j_filter_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     mitm_done

mitm_har:
    cmp     qword ptr [rip+mitm_on], 1
    je      mitm_har_ok
    lea     rsi, [rip+err_no_mitm]
    mov     rdx, err_no_mitm_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
mitm_har_ok:
    call    ensure_browser_dirs
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      mitm_har_def
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+har_path_buf]
    xor     r13, r13
mitm_har_copy:
    cmp     r13, r12
    jge     mitm_har_term
    cmp     r13, 510
    jge     mitm_har_term
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     mitm_har_copy
mitm_har_def:
    lea     rsi, [rip+default_har]
    lea     rdi, [rip+har_path_buf]
    call    copy_cstr
    jmp     mitm_har_ready
mitm_har_term:
    mov     byte ptr [rdi+r13], 0
mitm_har_ready:
    cmp     byte ptr [rip+url_buf], 0
    jne     mitm_har_have_url
    lea     rsi, [rip+default_url]
    lea     rdi, [rip+url_buf]
    call    copy_cstr
mitm_har_have_url:
    call    write_har_file
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_har_pre]
    mov     rdx, j_har_pre_len
    call    write_stdout
    lea     rsi, [rip+har_path_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+har_path_buf]
    call    write_stdout
    lea     rsi, [rip+j_har_suf]
    mov     rdx, j_har_suf_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+har_path_buf]
    call    strlen
    mov     rcx, rax
    lea     rax, [rip+har_path_buf]
    call    set_last_from_rcx
    call    bind_arrow_from_line
    jmp     mitm_done

mitm_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
ensure_browser_dirs:
    lea     rdi, [rip+path_out]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_browser]
    mov     rsi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_ca_dir]
    mov     rsi, MODE_0755
    call    sys_mkdir
    ret

# assemble + write session.json into assemble_buf and disk
write_session_json:
    push    rbx
    push    r12
    lea     rdi, [rip+assemble_buf]
    lea     rsi, [rip+j_sess_pre]
    mov     rcx, j_sess_pre_len
    call    memcpy_n
    # append script
    lea     rsi, [rip+script_buf]
    cmp     byte ptr [rsi], 0
    jne     wsj_script
    lea     rsi, [rip+default_script]
wsj_script:
    call    append_cstr
    lea     rsi, [rip+j_sess_mid]
    mov     rcx, j_sess_mid_len
    call    memcpy_n
    lea     rsi, [rip+url_buf]
    cmp     byte ptr [rsi], 0
    jne     wsj_url
    lea     rsi, [rip+default_url]
wsj_url:
    call    append_cstr
    lea     rsi, [rip+j_sess_suf]
    mov     rcx, j_sess_suf_len
    call    memcpy_n
    mov     byte ptr [rdi], 0
    # length = rdi - assemble_buf
    lea     rax, [rip+assemble_buf]
    mov     rdx, rdi
    sub     rdx, rax
    lea     rdi, [rip+path_session]
    lea     rsi, [rip+assemble_buf]
    call    write_bytes_path
    pop     r12
    pop     rbx
    ret

# Prefer multi-flow fixture HAR; fall back to single-entry splice
write_har_file:
    push    rbx
    push    r12
    push    r13
    lea     rdi, [rip+fixture_har]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      write_har_synthetic
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+har_copy_buf]
    mov     rdx, HAR_COPY_CAP
    call    sys_read
    cmp     rax, 32
    jl      write_har_fix_bad
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    lea     rdi, [rip+har_path_buf]
    lea     rsi, [rip+har_copy_buf]
    mov     rdx, r13
    call    write_bytes_path
    pop     r13
    pop     r12
    pop     rbx
    ret
write_har_fix_bad:
    mov     rdi, r12
    call    sys_close
write_har_synthetic:
    lea     rdi, [rip+assemble_buf]
    lea     rsi, [rip+har_pre]
    mov     rcx, har_pre_len
    call    memcpy_n
    lea     rsi, [rip+url_buf]
    call    append_cstr
    lea     rsi, [rip+har_mid]
    mov     rcx, har_mid_len
    call    memcpy_n
    mov     byte ptr [rdi], 0
    lea     rax, [rip+assemble_buf]
    mov     rdx, rdi
    sub     rdx, rax
    lea     rdi, [rip+har_path_buf]
    lea     rsi, [rip+assemble_buf]
    call    write_bytes_path
    pop     r13
    pop     r12
    pop     rbx
    ret

# rdi=dst advancing, rsi=src, rcx=len — copy and advance rdi
memcpy_n:
    test    rcx, rcx
    jz      mcn_done
mcn_loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     mcn_loop
mcn_done:
    ret

# rdi=dst advancing, rsi=cstr — append without NUL, advance rdi
append_cstr:
ac_loop:
    mov     al, [rsi]
    test    al, al
    jz      ac_done
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     ac_loop
ac_done:
    ret

# rsi=src rdi=dst — copy cstr including NUL
copy_cstr:
cc_loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     cc_loop
    ret
