# Spark engine B ? language ops + e2e wiring (real symbols only).
#
# engine_ops_dispatch:
#   fetch+parse ? fetch then parse "out/engine/body.bin"
#   fetch|parse|css|layout|paint|show ? matching lane dispatch
#   layout ? set_styles + run(nodes); fail closed if no DOM
#   layout fixture ? spark_layout_selftest
#   paint boxes ? SePaintBox[] ? out/engine/pipeline.ppm (fail if 0 boxes)
#   paint fixture ? engine_paint_fixture
#   render / show ? layout+paint_boxes+engine_window_show (pipeline.ppm)
#   live show ? fork ./spark-engine-show --ppm out/engine/pipeline.ppm
#
# Gaps: js phase-1 only; https fetch refused (no TLS-in-asm)
.intel_syntax noprefix
.global engine_ops_dispatch
.global engine_pipeline_render

.extern linebuf
.extern write_stdout
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern sys_exit
.extern msg_nl
.extern set_last_from_rcx
.extern bind_arrow_from_line

.extern engine_html_ops_dispatch
.extern engine_fetch_dispatch
.extern engine_css_dispatch
.extern engine_paint_dispatch
.extern engine_paint_fixture
.extern engine_window_show
.extern nodes
.extern nnodes
.extern root_id
.extern se_style_pool
.extern se_style_count
.extern spark_layout_set_viewport
.extern spark_layout_set_styles
.extern spark_layout_run
.extern spark_layout_box_count
.extern spark_layout_selftest
.extern spark_layout_emit_table_proof
.extern spark_layout_boxes_base
.extern spark_layout_text_blob
.extern engine_paint_init
.extern engine_paint_clear
.extern engine_paint_boxes
.extern engine_paint_write_ppm

.equ MODE_0755, 493

.section .bss
.align 16
json_buf:       .space 512

.section .data
msg_pipe:   .ascii "[engine] "
msg_pipe_len = . - msg_pipe
msg_arrow:  .ascii "  -> "
msg_arrow_len = . - msg_arrow

needle_render:  .ascii "render\0"
needle_layout:  .ascii "layout\0"
needle_paint:   .ascii "paint\0"
needle_show:    .ascii "show\0"
needle_parse:   .ascii "parse\0"
needle_fetch:   .ascii "fetch\0"
needle_css:     .ascii "css\0"
needle_fixture: .ascii "fixture\0"
needle_boxes:   .ascii "boxes\0"

path_out:       .ascii "out\0"
path_browser:   .ascii "out/browser\0"
path_engdir:    .ascii "out/browser/engine\0"
path_engroot:   .ascii "out/engine\0"
json_path:      .ascii "out/browser/engine/render.json\0"
json_pipe_path: .ascii "out/browser/engine/pipeline.json\0"

show_line:
    .ascii "browser show \"out/engine/pipeline.ppm\"\0"
parse_body_line:
    .ascii "engine parse \"out/engine/body.bin\"\0"
layout_ppm:
    .asciz "out/engine/pipeline.ppm"

err_unknown:
    .ascii "error: unknown engine op"
    .ascii " (want: fetch|parse|css|layout|paint|render|show)\n"
err_unknown_len = . - err_unknown
err_layout_dom:
    .ascii "error: engine layout needs DOM"
    .ascii " (engine parse first; or: engine layout fixture)\n"
err_layout_dom_len = . - err_layout_dom
err_layout_boxes:
    .ascii "error: engine layout produced 0 boxes\n"
err_layout_boxes_len = . - err_layout_boxes
err_paint_boxes:
    .ascii "error: engine paint boxes needs layout"
    .ascii " (engine layout first; 0 boxes)\n"
err_paint_boxes_len = . - err_paint_boxes
err_paint:
    .ascii "error: engine render: layout/paint failed\n"
err_paint_len = . - err_paint
err_render_dom:
    .ascii "error: engine render needs DOM"
    .ascii " (engine parse first; no fixture fallback)\n"
err_render_dom_len = . - err_render_dom

j_render:
    .ascii "{\"op\":\"engine.render\",\"ok\":true,"
    .ascii "\"stages\":[\"layout\",\"paint_boxes\",\"show\"],"
    .ascii "\"ppm\":\"out/engine/pipeline.ppm\","
    .ascii "\"abi\":\"SePaintBox\"}\0"

j_paint_boxes:
    .ascii "{\"op\":\"engine.paint\",\"ok\":true,"
    .ascii "\"mode\":\"boxes\",\"abi\":\"SePaintBox\","
    .ascii "\"ppm\":\"out/engine/pipeline.ppm\","
    .ascii "\"box_count\":"
j_paint_boxes_len = . - j_paint_boxes
j_paint_boxes_sfx:
    .ascii "}\n"
j_paint_boxes_sfx_len = . - j_paint_boxes_sfx

j_fp:
    .ascii "{\"op\":\"engine.fetch_parse\",\"ok\":true,"
    .ascii "\"body\":\"out/engine/body.bin\","
    .ascii "\"next\":\"engine.parse\"}\0"

j_layout_pfx:
    .ascii "{\"op\":\"engine.layout\",\"ok\":true,"
    .ascii "\"abi\":\"SePaintBox\",\"box_stride\":36,"
    .ascii "\"box_count\":"
j_layout_pfx_len = . - j_layout_pfx
j_layout_sfx:
    .ascii "}\n"
j_layout_sfx_len = . - j_layout_sfx

.section .text

engine_ops_dispatch:
    push    rbx

    lea     rsi, [rip+msg_pipe]
    mov     rdx, msg_pipe_len
    call    write_stdout

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fetch]
    call    contains
    test    rax, rax
    jz      .no_fp
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_parse]
    call    contains
    test    rax, rax
    jnz     .do_fetch_parse
.no_fp:

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_render]
    call    contains
    test    rax, rax
    jnz     .do_render

    # paint/show before layout ? quoted paths may contain "layout"
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_paint]
    call    contains
    test    rax, rax
    jnz     .do_paint

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_show]
    call    contains
    test    rax, rax
    jnz     .do_show

    # parse/fetch before css ? filename css_*.html must not steal parse
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fetch]
    call    contains
    test    rax, rax
    jnz     .do_fetch

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_parse]
    call    contains
    test    rax, rax
    jnz     .do_parse

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_css]
    call    contains
    test    rax, rax
    jnz     .do_css

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_layout]
    call    contains
    test    rax, rax
    jnz     .do_layout

    lea     rsi, [rip+err_unknown]
    mov     rdx, err_unknown_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

.do_fetch_parse:
    call    engine_fetch_dispatch
    lea     rsi, [rip+parse_body_line]
    lea     rdi, [rip+linebuf]
    call    ep_copy_cstr
    call    engine_html_ops_dispatch
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_fp]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+j_fp]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

.do_render:
    call    engine_pipeline_render
    pop     rbx
    ret

.do_layout:
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fixture]
    call    contains
    test    rax, rax
    jz      .lay_dom
    call    spark_layout_selftest
    test    eax, eax
    jz      .lay_fix_ok
    mov     edi, 1
    call    sys_exit
.lay_fix_ok:
    pop     rbx
    ret
.lay_dom:
    mov     rax, [rip+nnodes]
    test    rax, rax
    jnz     .lay_run
    lea     rsi, [rip+err_layout_dom]
    mov     rdx, err_layout_dom_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
.lay_run:
    # match paint FB max (EP_MAX 640x480)
    mov     edi, 640
    mov     esi, 480
    call    spark_layout_set_viewport
    lea     rdi, [rip+se_style_pool]
    mov     esi, [rip+se_style_count]
    call    spark_layout_set_styles
    lea     rdi, [rip+nodes]
    mov     esi, [rip+nnodes]
    mov     edx, [rip+root_id]
    call    spark_layout_run
    mov     ebx, eax
    test    ebx, ebx
    jnz     .lay_have
    lea     rsi, [rip+err_layout_boxes]
    mov     rdx, err_layout_boxes_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
.lay_have:
    lea     rsi, [rip+j_layout_pfx]
    mov     rdx, j_layout_pfx_len
    call    write_stdout
    mov     eax, ebx
    call    ep_print_u32
    lea     rsi, [rip+j_layout_sfx]
    mov     rdx, j_layout_sfx_len
    call    write_stdout
    call    spark_layout_emit_table_proof
    test    eax, eax
    jnz     .lay_done
    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
.lay_done:
    pop     rbx
    ret

.do_paint:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_boxes]
    call    contains
    test    rax, rax
    jnz     .paint_boxes
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_layout]
    call    contains
    test    rax, rax
    jnz     .paint_boxes
    call    engine_paint_dispatch
    pop     rbx
    ret
.paint_boxes:
    call    ep_paint_layout_boxes
    pop     rbx
    ret

.do_show:
    call    engine_window_show
    pop     rbx
    ret

.do_css:
    call    engine_css_dispatch
    pop     rbx
    ret

.do_fetch:
    call    engine_fetch_dispatch
    pop     rbx
    ret

.do_parse:
    call    engine_html_ops_dispatch
    pop     rbx
    ret

# layout SePaintBox[] ? paint PPM ? show. Fail closed if no DOM.
engine_pipeline_render:
    push    rbx
    push    r12

    call    ep_ensure_dirs

    mov     rax, [rip+nnodes]
    test    rax, rax
    jnz     .pr_dom
    lea     rsi, [rip+err_render_dom]
    mov     rdx, err_render_dom_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

.pr_dom:
    mov     edi, 640
    mov     esi, 480
    call    spark_layout_set_viewport
    lea     rdi, [rip+se_style_pool]
    mov     esi, [rip+se_style_count]
    call    spark_layout_set_styles
    lea     rdi, [rip+nodes]
    mov     esi, [rip+nnodes]
    mov     edx, [rip+root_id]
    call    spark_layout_run
    mov     r12d, eax
    test    r12d, r12d
    jnz     .pr_boxes
    lea     rsi, [rip+err_layout_boxes]
    mov     rdx, err_layout_boxes_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

.pr_boxes:
    mov     edi, 640
    mov     esi, 480
    call    engine_paint_init
    test    eax, eax
    jnz     .pr_fail
    mov     dil, 255
    mov     sil, 255
    mov     dl, 255
    call    engine_paint_clear
    call    spark_layout_text_blob
    mov     rdx, rax
    call    spark_layout_boxes_base
    mov     rdi, rax
    mov     esi, r12d
    call    engine_paint_boxes
    lea     rdi, [rip+layout_ppm]
    call    engine_paint_write_ppm
    test    eax, eax
    jnz     .pr_fail

    lea     rsi, [rip+j_render]
    lea     rdi, [rip+json_buf]
    call    ep_copy_cstr

    lea     rsi, [rip+json_buf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+json_buf]
    lea     rdi, [rip+json_path]
    call    write_bytes_path

    lea     rsi, [rip+show_line]
    lea     rdi, [rip+linebuf]
    call    ep_copy_cstr
    call    engine_window_show

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

    pop     r12
    pop     rbx
    ret

.pr_fail:
    lea     rsi, [rip+err_paint]
    mov     rdx, err_paint_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# Paint current layout boxes ? out/engine/layout.ppm
# eax unused; fail closed if box_count==0
ep_paint_layout_boxes:
    push    rbx
    push    r12
    call    ep_ensure_dirs
    call    spark_layout_box_count
    mov     r12d, eax
    test    r12d, r12d
    jnz     .pb_ok
    lea     rsi, [rip+err_paint_boxes]
    mov     rdx, err_paint_boxes_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
.pb_ok:
    mov     edi, 640
    mov     esi, 480
    call    engine_paint_init
    test    eax, eax
    jnz     .pb_fail
    mov     dil, 255
    mov     sil, 255
    mov     dl, 255
    call    engine_paint_clear
    call    spark_layout_text_blob
    mov     rdx, rax
    call    spark_layout_boxes_base
    mov     rdi, rax
    mov     esi, r12d
    call    engine_paint_boxes
    lea     rdi, [rip+layout_ppm]
    call    engine_paint_write_ppm
    test    eax, eax
    jnz     .pb_fail

    lea     rsi, [rip+msg_arrow]
    mov     rdx, msg_arrow_len
    call    write_stdout
    lea     rsi, [rip+j_paint_boxes]
    mov     rdx, j_paint_boxes_len
    call    write_stdout
    mov     eax, r12d
    call    ep_print_u32
    lea     rsi, [rip+j_paint_boxes_sfx]
    mov     rdx, j_paint_boxes_sfx_len
    call    write_stdout
    pop     r12
    pop     rbx
    ret
.pb_fail:
    lea     rsi, [rip+err_paint]
    mov     rdx, err_paint_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

ep_ensure_dirs:
    lea     rdi, [rip+path_out]
    mov     esi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_browser]
    mov     esi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_engdir]
    mov     esi, MODE_0755
    call    sys_mkdir
    lea     rdi, [rip+path_engroot]
    mov     esi, MODE_0755
    call    sys_mkdir
    ret

ep_copy_cstr:
.ecc:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .ecc
    ret

.section .bss
.align 8
ep_num_buf: .space 32

.section .text
ep_print_u32:
    push    rbx
    push    rcx
    push    rdx
    lea     rbx, [rip+ep_num_buf+15]
    mov     ecx, 10
    test    eax, eax
    jnz     1f
    dec     rbx
    mov     byte ptr [rbx], '0'
    jmp     2f
1:  xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rbx
    mov     [rbx], dl
    test    eax, eax
    jnz     1b
2:  lea     rdx, [rip+ep_num_buf+15]
    sub     rdx, rbx
    mov     rsi, rbx
    call    write_stdout
    pop     rdx
    pop     rcx
    pop     rbx
    ret
