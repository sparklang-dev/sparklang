# Spark VM — x86_64 Linux (GAS / AT&T)
# Primary runtime: assembly → machine code. Dry-run needs no libc.
# Syscalls only: open/read/write/close/exit.
#
# Build: as --64 -o spark.o asm/spark.s && ld -o spark spark.o

.intel_syntax noprefix
.global _start
# Exported for asm/model_ops.s (model analyze/compare/improve/build)
.global linebuf
.global write_stdout
.global extract_quote
.global contains
.global strlen
.global write_bytes_path
.global sys_mkdir
.global msg_nl
.global msg_reply
.global msg_reply_len
.global outdir_name
.global sys_open
.global sys_read
.global sys_write
.global sys_close
.global sys_lseek
.global sys_fstat
.global sys_exit
.global skip_ws
.global skip_ws_from_rbx
.global vars
.global last_val
.global last_val_len
.global bind_name
.global tmpbuf
.global linebuf
.global flag_allow_net_capture
.global flag_allow_net
.global flag_live
.global flag_pstn_live
.global tools_active
.global tool_reg_name
.global tool_reg_len
.global tools_scope
.global fork_exec_wait
.global pick_ask_reply_ptr
.extern model_ops_dispatch
.extern binary_ops_dispatch
.extern network_ops_dispatch
.extern os_ops_dispatch
.extern browser_ops_dispatch
.extern mitm_ops_dispatch
.extern engine_js_ops_dispatch
.extern cuda_ops_dispatch
.extern memory_ops_dispatch
.extern ask_live_dispatch
.extern ask_encrypt_dispatch
.extern ask_probe_dispatch
.extern ask_remember_model
.extern embed_live_dispatch
.extern retrieve_live_dispatch
.extern pcie_ops_dispatch
.extern voice_ops_dispatch
.extern voice_speak_model_dispatch
.extern voice_listen_live_dispatch
.extern voice_speak_live_dispatch
.extern crypto_ops_dispatch
.extern encrypt_ops_dispatch
.extern gateway_ops_dispatch
.extern engine_html_ops_dispatch
.extern engine_fetch_dispatch
.extern engine_css_dispatch
.extern engine_ops_dispatch
.extern ide_ops_dispatch
.extern ide_keys_dispatch
.extern enc_gateway_on
.extern do_let
.extern do_with
.extern looks_like_field
.extern set_last_from_rcx
.extern bind_arrow_from_line
.extern vars_get
.extern vars_put
.extern honest_question_exit

.equ SYS_READ,  0
.equ SYS_WRITE, 1
.equ SYS_OPEN,  2
.equ SYS_CLOSE, 3
.equ SYS_FSTAT, 5
.equ SYS_LSEEK, 8
.equ SYS_MMAP,  9
.equ SYS_MUNMAP, 11
.equ SYS_EXIT,  60
.equ SYS_MKDIR, 83
.equ SYS_MLOCK, 149
.equ SYS_MUNLOCK, 150
.equ SYS_FORK,  57
.equ SYS_EXECVE, 59
.equ SYS_WAIT4, 61
.equ O_RDONLY,  0
.equ O_WRONLY,  1
.equ O_CREAT,   64
.equ O_TRUNC,   512
.equ MAX_FILE,  65536
.equ MAX_LINE,  2048
.equ MAP_PRIVATE, 0x02
.equ MAP_ANONYMOUS, 0x20
.equ PROT_READ, 1
.equ PROT_WRITE, 2

.section .bss
.align 16
filebuf:    .space MAX_FILE
linebuf:    .space MAX_LINE
pathbuf:    .space 512
outbuf:     .space 4096
tmpbuf:     .space 1024
vars:       .space 8192          # name\0value\0…\0
speak_path: .space 256
last_val:   .space 1024          # last stub result for -> bind
last_val_len: .space 8
bind_name:  .space 64
flag_allow_net_capture: .space 8
flag_allow_net: .space 8
flag_live:  .space 8
flag_pstn_live: .space 8
tools_active: .space 8
tool_reg_name: .space 64
tool_reg_len: .space 8
tools_scope: .space 128
saved_envp: .space 8
cuda_argv:  .space 48
review_argv: .space 64
review_url_buf: .space 1024
pin_size:   .space 8
pin_addr:   .space 8
errno_buf:  .space 32

.section .data
msg_usage:
    .ascii "Spark VM (asm→machine code) — 0.6.0\n"
    .ascii "Usage: spark --dry-run [--allow-net]"
    .ascii " [--allow-net-capture] <file.spark>\n"
    .ascii "       spark --live <file.spark>"
    .ascii "  # ask → AI_GATEWAY_URL\n"
    .ascii "       spark --live --pstn-live <file>"
    .ascii "  # PSTN off unless SPARK_PSTN=1\n"
    .ascii "       spark --version\n"
    .ascii "Note: review url = spark-review-url companion;"
    .ascii " file:// offline; http(s) needs --allow-net;"
    .ascii " never eval\n"
    .ascii "      cuda probe|memstat|prefer|pcie →"
    .ascii " /dev/nvidia* + sysfs PCIe link (asm)\n"
    .ascii "      memory pin → mmap+mlock syscall"
    .ascii " (fail loud)\n"
    .ascii "      binary disasm/understand → ALL sections +"
    .ascii " C lift under out/decompile/<name>/lifted/\n"
    .ascii "      network capture: fixture unless"
    .ascii " --allow-net-capture (AF_PACKET/"
    .ascii " CAP_NET_RAW via spark-net-capture)\n"
    .ascii "      os design|specify|generate|build|explain\n"
    .ascii "      browser run|flags (QUIC on default)\n"
    .ascii "      mitm ca-init|ca-install|ca-status |"
    .ascii " quic listen|status|smoke |"
    .ascii " disable_quic\n"
msg_usage_len = . - msg_usage

msg_version:
    .ascii "spark 0.6.0 (x86_64 asm + companions)\n"
msg_version_len = . - msg_version

msg_banner:
    .ascii "[spark] dry-run via assembly VM (machine code)\n"
msg_banner_len = . - msg_banner
msg_banner_live:
    .ascii "[spark] live ask via AI_GATEWAY_URL (spark-ask-http)\n"
msg_banner_live_len = . - msg_banner_live

msg_nl:     .ascii "\n"
msg_ask:    .ascii "[ask] "
msg_ask_len = . - msg_ask
msg_reply:  .ascii "  → "
msg_reply_len = . - msg_reply
msg_cls:    .ascii "[classify] "
msg_cls_len = . - msg_cls
msg_embed:  .ascii "[embed] "
msg_embed_len = . - msg_embed
msg_shell:  .ascii "[shell] "
msg_shell_len = . - msg_shell
msg_accounting:
    .ascii "[accounting] latency_ms=0 prompt_tokens=0 "
    .ascii "completion_tokens=0 total_tokens=0 "
    .ascii "note=dry-run\n"
msg_accounting_len = . - msg_accounting
msg_embed_cli:
    .ascii "{\"spark_embed\":true,\"api\":\"stub\","
    .ascii "\"note\":\"FFI host embed handshake — "
    .ascii "import spark is [next]\"}\n"
msg_embed_cli_len = . - msg_embed_cli
dry_shell_echo:
    .ascii "{\"ok\":true,\"mode\":\"dry-run\","
    .ascii "\"argv\":\"echo\",\"stdout\":\"hello\","
    .ascii "\"note\":\"fixture — no exec\"}"
dry_shell_echo_len = . - dry_shell_echo
dry_shell_true:
    .ascii "{\"ok\":true,\"mode\":\"dry-run\","
    .ascii "\"argv\":\"true\",\"stdout\":\"\","
    .ascii "\"note\":\"fixture — no exec\"}"
dry_shell_true_len = . - dry_shell_true
dry_shell_false:
    .ascii "{\"ok\":false,\"mode\":\"dry-run\","
    .ascii "\"argv\":\"false\",\"stdout\":\"\","
    .ascii "\"note\":\"fixture — no exec\"}"
dry_shell_false_len = . - dry_shell_false
msg_shell_refuse:
    .ascii "error: dry-run refuses shell/run "
    .ascii "(allowlist: echo|true|false)\n"
msg_shell_refuse_len = . - msg_shell_refuse
msg_retrieve: .ascii "[retrieve] "
msg_retrieve_len = . - msg_retrieve
msg_listen: .ascii "[listen] "
msg_listen_len = . - msg_listen
msg_speak:  .ascii "[speak] wrote "
msg_speak_len = . - msg_speak
msg_pipe:   .ascii "[pipeline] step\n"
msg_pipe_len = . - msg_pipe
msg_model:  .ascii "[model] "
msg_model_len = . - msg_model
msg_print:  .ascii "[print] "
msg_print_len = . - msg_print
msg_extract:.ascii "[extract] "
msg_extract_len = . - msg_extract
msg_tool:   .ascii "[tool] registered "
msg_tool_len = . - msg_tool
msg_tool_call:
    .ascii "[tool:"
msg_tool_call_len = . - msg_tool_call
msg_tool_stub:
    .ascii "] stub:local"
msg_tool_stub_len = . - msg_tool_stub
msg_voice:  .ascii "[voice] "
msg_voice_len = . - msg_voice
msg_review: .ascii "[review] "
msg_review_len = . - msg_review
msg_builder:.ascii "[builder] "
msg_builder_len = . - msg_builder
msg_impl:   .ascii "[implement] wrote "
msg_impl_len = . - msg_impl
msg_cuda:   .ascii "[cuda] "
msg_cuda_len = . - msg_cuda
msg_memory: .ascii "[memory] "
msg_memory_len = . - msg_memory
msg_binary: .ascii "[binary] "
msg_binary_len = . - msg_binary
msg_noreval:.ascii "  (static only — never eval web JS)\n"
msg_noreval_len = . - msg_noreval
msg_done:   .ascii "[spark] ok\n"
msg_done_len = . - msg_done
msg_err_open:
    .ascii "error: cannot open file\n"
msg_err_open_len = . - msg_err_open
msg_err_args:
    .ascii "error: need --dry-run|--live <file.spark>\n"
msg_err_args_len = . - msg_err_args
msg_err_unknown:
    .ascii "error: unknown or unimplemented statement: "
msg_err_unknown_len = . - msg_err_unknown
msg_err_review_path:
    .ascii "error: review path cannot open file\n"
msg_err_review_path_len = . - msg_err_review_path
msg_err_review_url:
    .ascii "error: review url requires a quoted URL\n"
msg_err_review_url_len = . - msg_err_review_url
msg_err_review_comp:
    .ascii "error: spark-review-url failed"
    .ascii " (see stderr; http(s) needs --allow-net)\n"
msg_err_review_comp_len = . - msg_err_review_comp
msg_err_trunc:
    .ascii "error: source exceeds MAX_FILE (64KiB)"
    .ascii " — truncated read refused\n"
msg_err_trunc_len = . - msg_err_trunc
msg_let:    .ascii "[let] "
msg_let_len = . - msg_let
msg_with:   .ascii "[with] scope (dry-run — nested lines still run)\n"
msg_with_len = . - msg_with
msg_err_let:
    .ascii "error: let requires: let name = \"value\"\n"
msg_err_let_len = . - msg_err_let
msg_prefer_voice:
    .ascii "error: cuda prefer gpu 2 forbidden —"
    .ascii " reserved GPU index is voice-only\n"
msg_prefer_voice_len = . - msg_prefer_voice
msg_mlock_fail:
    .ascii "error: memory pin mlock failed errno="
msg_mlock_fail_len = . - msg_mlock_fail
msg_mmap_fail:
    .ascii "error: memory pin mmap failed\n"
msg_mmap_fail_len = . - msg_mmap_fail

dry_gravity:
    .ascii "Gravity pulls masses together."
dry_gravity_len = . - dry_gravity
dry_summary:
    .ascii "Summary: dry-run summary of the document."
dry_summary_len = . - dry_summary
dry_es:
    .ascii "Resumen en español (dry-run)."
dry_es_len = . - dry_es
dry_generic:
    .ascii "[dry-run] model response"
dry_generic_len = . - dry_generic
dry_intent:
    .ascii "{\"label\":\"support\",\"confidence\":0.91}"
dry_intent_len = . - dry_intent
dry_json:
    .ascii "{\"name\":\"Ada Lovelace\",\"age\":36}"
dry_json_len = . - dry_json
dry_weather:
    .ascii "Dry-run: partly cloudy, 72°F in Springfield."
dry_weather_len = . - dry_weather
dry_person:
    .ascii "{\"name\":\"Ada Lovelace\",\"age\":36}"
dry_person_len = . - dry_person
dry_support:
    .ascii "{\"label\":\"support\",\"confidence\":0.91,\"reasons\":[\"dry-run\"]}"
dry_support_len = . - dry_support
dry_embed:
    .ascii "{\"object\":\"list\",\"model\":\"embed-rag\","
    .ascii "\"data\":[{\"object\":\"embedding\",\"index\":0,"
    .ascii "\"embedding\":[0.01,-0.02,0.03,0.0]}],"
    .ascii "\"usage\":{\"prompt_tokens\":8,\"total_tokens\":8},"
    .ascii "\"note\":\"dry-run fixture — not a live TEI vector\"}"
dry_embed_len = . - dry_embed
dry_retrieve:
    .ascii "{\"chunks\":[{\"chunk_id\":\"docs/LANGUAGE.md#embed\","
    .ascii "\"content\":\"<<<RAG_CHUNK>>> embed text to vec "
    .ascii "<<<END_RAG_CHUNK>>>\",\"score\":0.91,"
    .ascii "\"source\":\"spark-docs\",\"title\":\"LANGUAGE.md\"}],"
    .ascii "\"by_source\":{\"spark-docs\":1},"
    .ascii "\"gateway_available\":true,\"audience\":\"operator\","
    .ascii "\"project\":\"docs\",\"backends_used\":[\"fixture\"],"
    .ascii "\"cache_hit\":false,"
    .ascii "\"crag\":{\"grade\":\"correct\",\"retried\":false},"
    .ascii "\"note\":\"dry-run fixture — gateway CRAG for operator\"}"
dry_retrieve_len = . - dry_retrieve
dry_retrieve_empty:
    .ascii "{\"chunks\":[],\"by_source\":{},"
    .ascii "\"gateway_available\":true,\"audience\":\"operator\","
    .ascii "\"project\":\"docs\",\"backends_used\":[\"fixture\"],"
    .ascii "\"cache_hit\":false,"
    .ascii "\"crag\":{\"grade\":\"incorrect\",\"retried\":false},"
    .ascii "\"note\":\"dry-run empty — no matching fixture cue\"}"
dry_retrieve_empty_len = . - dry_retrieve_empty
dry_sales:
    .ascii "{\"label\":\"sales\",\"confidence\":0.88,\"reasons\":[\"dry-run\"]}"
dry_sales_len = . - dry_sales
dry_spam:
    .ascii "{\"label\":\"spam\",\"confidence\":0.95,\"reasons\":[\"dry-run\"]}"
dry_spam_len = . - dry_spam
dry_transcript:
    .ascii "My account is locked and I need support."
dry_transcript_len = . - dry_transcript
dry_reply:
    .ascii "Happy to help — what do you need?"
dry_reply_len = . - dry_reply

# review reports (JSON) — path/text heuristics; url via companion
dry_rev_higher:
    .ascii "{\"issues\":[\"possible eval\",\"ai-authored patterns\"],\"complexity\":\"mid\",\"suggested_level\":\"higher\",\"rationale\":\"web/JS surface — suggest high-level companion; never execute\"}"
dry_rev_higher_len = . - dry_rev_higher
dry_rev_lower:
    .ascii "{\"issues\":[\"hot path candidate\"],\"complexity\":\"low\",\"suggested_level\":\"lower\",\"rationale\":\"asm/.s — keep machine-code level\"}"
dry_rev_lower_len = . - dry_rev_lower
dry_rev_mid:
    .ascii "{\"issues\":[\"glue boilerplate\"],\"complexity\":\"mid\",\"suggested_level\":\"mid\",\"rationale\":\"Spark/C-like fit — stay on asm VM surface\"}"
dry_rev_mid_len = . - dry_rev_mid
review_bin:
    .ascii "./spark-review-url\0"
review_flag_url:
    .ascii "--url\0"
review_flag_out:
    .ascii "--out\0"
review_flag_net:
    .ascii "--allow-net\0"
review_out_path:
    .ascii "/tmp/spark-review-url.json\0"

dry_bld_lower:
    .ascii "{\"prefer\":\"lower\",\"plan\":\"emit Spark+asm ops\",\"artifact\":\"out/program.spark\"}"
dry_bld_lower_len = . - dry_bld_lower
dry_bld_higher:
    .ascii "{\"prefer\":\"higher\",\"plan\":\"emit Python-ish suggestion layer\",\"artifact\":\"out/program.py.txt\"}"
dry_bld_higher_len = . - dry_bld_higher
dry_bld_auto:
    .ascii "{\"prefer\":\"auto\",\"plan\":\"use review.suggested_level\",\"artifact\":\"out/program.spark\"}"
dry_bld_auto_len = . - dry_bld_auto

# CUDA / memory dry-run stubs (no NVML/CUDA in default ELF)
dry_cuda_probe:
    .ascii "{\"mode\":\"dry-run\",\"driver\":\"see spark-cuda-probe\",\"cuda_driver_api\":\"13.0\",\"toolkit\":\"12.8\",\"gpus\":3,\"prefer_index\":0,\"never_index\":[1],\"policy\":\"spark-cuda.toml\",\"live\":\"make spark-cuda && ./spark-cuda-probe\"}"
dry_cuda_probe_len = . - dry_cuda_probe
dry_cuda_memstat:
    .ascii "{\"mode\":\"dry-run\",\"note\":\"live memstat via ./spark-cuda-probe --memstat\",\"pool\":\"recommended\",\"pinned_host\":\"mlock/MAP_LOCKED when live\",\"uvm\":\"nvidia_uvm loaded — prefer explicit cudaMalloc for Spark demos\"}"
dry_cuda_memstat_len = . - dry_cuda_memstat
dry_cuda_prefer:
    .ascii "{\"mode\":\"dry-run\",\"prefer_gpu\":0,\"uuid_preferred\":\"GPU-00000000-0000-0000-0000-000000000000\",\"never\":\"GPU-ffffffff (reserved voice-only)\"}"
dry_cuda_prefer_len = . - dry_cuda_prefer
dry_mem_pin:
    .ascii "{\"mode\":\"dry-run\",\"op\":\"pin\",\"note\":\"stub only — live pin needs libc/mlock companion; default ELF stays syscalls-only\",\"size\":\"parsed\"}"
dry_mem_pin_len = . - dry_mem_pin

# codegen artifact written by implement (Spark source the VM can re-run)
impl_spark_body:
    .ascii "# generated by Spark builder/implement (dry-run)\n"
    .ascii "model fast\n"
    .ascii "classify Intent { support, sales, spam } from \"need help\" -> intent\n"
    .ascii "voice {\n"
    .ascii "  listen -> user\n"
    .ascii "  classify Intent { support, sales } from user -> intent\n"
    .ascii "  ask \"Reply helpfully to: {user}\" -> reply\n"
    .ascii "  speak reply\n"
    .ascii "}\n"
impl_spark_body_len = . - impl_spark_body

impl_py_body:
    .ascii "# suggestion layer only — not the Spark VM\n"
    .ascii "# def classify(text): ...\n"
    .ascii "# def voice_turn(): listen(); classify(); ask(); speak()\n"
impl_py_body_len = . - impl_py_body

default_wav:
    .ascii "spark-out.wav\0"
default_out_spark:
    .ascii "out/program.spark\0"
default_out_py:
    .ascii "out/program.py.txt\0"
outdir_name:
    .ascii "out\0"
kw_dry:     .ascii "--dry-run\0"
kw_live:    .ascii "--live\0"
kw_ver:     .ascii "--version\0"
kw_help:    .ascii "--help\0"
kw_allow_net_cap:.ascii "--allow-net-capture\0"
kw_allow_net_fetch:.ascii "--allow-net\0"
kw_pstn_live:.ascii "--pstn-live\0"
needle_with_model: .ascii "with model\0"
needle_analyze_kw: .ascii "analyze\0"
needle_compare_kw: .ascii "compare\0"
needle_improve_kw: .ascii "improve\0"
needle_build_kw:   .ascii "build\0"

# keyword tables (null-terminated, compared after skip spaces)
kw_ask:     .ascii "ask"
kw_gen:     .ascii "generate"
kw_cls:     .ascii "classify"
kw_embed:   .ascii "embed"
kw_shell:   .ascii "shell"
kw_run:     .ascii "run"
kw_embed_cli: .ascii "--embed\0"
kw_retrieve:.ascii "retrieve"
kw_listen:  .ascii "listen"
kw_speak:   .ascii "speak"
kw_say:     .ascii "say"
kw_pipe:    .ascii "pipeline"
kw_model:   .ascii "model"
kw_use:     .ascii "use"
kw_print:   .ascii "print"
kw_extract: .ascii "extract"
kw_tool:    .ascii "tool"
kw_voice:   .ascii "voice"
kw_let:     .ascii "let"
kw_with:    .ascii "with"
kw_review:  .ascii "review"
kw_builder: .ascii "builder"
kw_implement: .ascii "implement"
kw_cuda:    .ascii "cuda"
kw_pcie:    .ascii "pcie"
kw_memory:  .ascii "memory"
kw_binary:  .ascii "binary"
kw_network: .ascii "network"
kw_os:      .ascii "os"
kw_mitm:    .ascii "mitm"
kw_browser: .ascii "browser"
kw_engine:  .ascii "engine"
kw_ide:     .ascii "ide"
kw_js:      .ascii "js"
kw_crypto:  .ascii "crypto"
kw_encrypt: .ascii "encrypt"
kw_gateway: .ascii "gateway"
needle_arrow:   .ascii "->\0"
needle_gravity: .ascii "gravity\0"
needle_probe:   .ascii "probe\0"
needle_memstat: .ascii "memstat\0"
needle_prefer:  .ascii "prefer\0"
needle_pin:     .ascii "pin\0"
needle_sum:     .ascii "summar\0"
needle_span:    .ascii "spanish\0"
needle_reply:   .ascii "reply\0"
needle_intent:  .ascii "intent\0"
needle_json:    .ascii "json\0"
needle_weather: .ascii "weather\0"
needle_trans:   .ascii "translate\0"
needle_explain: .ascii "explain\0"
needle_one_sent:.ascii "one sentence\0"
needle_buy:     .ascii "buy\0"
needle_price:   .ascii "price\0"
needle_spam:    .ascii "spam\0"
needle_help:    .ascii "help\0"
needle_broken:  .ascii "broken\0"
needle_support: .ascii "support\0"
needle_embed:   .ascii "embed\0"
needle_retrieve:.ascii "retrieve\0"
needle_dryrun:  .ascii "dry-run\0"
needle_language:.ascii "language\0"
needle_rag:     .ascii "rag\0"
needle_url:     .ascii "url\0"
needle_path:    .ascii "path\0"
needle_engine_fetch: .ascii "fetch\0"
needle_engine_css:   .ascii "css\0"
needle_lower:   .ascii "lower\0"
needle_higher:  .ascii "higher\0"
needle_auto:    .ascii "auto\0"
needle_js:      .ascii ".js\0"
needle_py:      .ascii ".py\0"
needle_asm:     .ascii ".s\0"
needle_spark:   .ascii ".spark\0"
needle_eval:    .ascii "eval\0"
wav_stub:
    .ascii "RIFF"
    .long 36
    .ascii "WAVEfmt "
    .long 16
    .word 1
    .word 1
    .long 8000
    .long 8000
    .word 1
    .word 8
    .ascii "data"
    .long 4
    .ascii "SPK\n"
wav_stub_len = . - wav_stub

.section .text

# ------------------------------------------------------------
# _start: argv → flags + --dry-run path | --version | usage
# ------------------------------------------------------------
_start:
    mov     rbp, rsp
    mov     qword ptr [rip+flag_allow_net_capture], 0
    mov     qword ptr [rip+flag_allow_net], 0
    mov     qword ptr [rip+flag_live], 0
    mov     qword ptr [rip+flag_pstn_live], 0
    # envp follows argv NULL on the initial stack (needed by execve)
    mov     rax, [rbp]              # argc
    lea     rdi, [rbp+8]
    lea     rdi, [rdi+rax*8+8]      # &envp[0]
    mov     [rip+saved_envp], rdi
    mov     rax, [rbp]          # argc
    cmp     rax, 2
    jl      usage_exit

    # scan argv[1..] for --version / --help / --allow-net /
    # --allow-net-capture / --pstn-live / --dry-run|--live <path>
    mov     r12, 1              # i
    xor     r13, r13            # path set flag
arg_scan:
    cmp     r12, [rbp]
    jge     arg_done
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]          # argv[i]
    lea     rdi, [rip+kw_ver]
    call    streq
    test    rax, rax
    jnz     do_version
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_embed_cli]
    call    streq
    test    rax, rax
    jnz     do_embed_cli
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_help]
    call    streq
    test    rax, rax
    jnz     usage_ok
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_allow_net_fetch]
    call    streq
    test    rax, rax
    jz      arg_net_cap
    mov     qword ptr [rip+flag_allow_net], 1
    inc     r12
    jmp     arg_scan
arg_net_cap:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_allow_net_cap]
    call    streq
    test    rax, rax
    jz      arg_pstn_flag
    mov     qword ptr [rip+flag_allow_net_capture], 1
    inc     r12
    jmp     arg_scan
arg_pstn_flag:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_pstn_live]
    call    streq
    test    rax, rax
    jz      arg_mode
    mov     qword ptr [rip+flag_pstn_live], 1
    inc     r12
    jmp     arg_scan
arg_mode:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_dry]
    call    streq
    test    rax, rax
    jnz     arg_mode_ok
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_live]
    call    streq
    test    rax, rax
    jz      err_args
    mov     qword ptr [rip+flag_live], 1
arg_mode_ok:
    inc     r12
    cmp     r12, [rbp]
    jge     err_args
    # skip more flags then take path
arg_after_dry:
    cmp     r12, [rbp]
    jge     err_args
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_allow_net_fetch]
    call    streq
    test    rax, rax
    jz      arg_after_cap
    mov     qword ptr [rip+flag_allow_net], 1
    inc     r12
    jmp     arg_after_dry
arg_after_cap:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_allow_net_cap]
    call    streq
    test    rax, rax
    jz      arg_after_pstn
    mov     qword ptr [rip+flag_allow_net_capture], 1
    inc     r12
    jmp     arg_after_dry
arg_after_pstn:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+kw_pstn_live]
    call    streq
    test    rax, rax
    jz      arg_path
    mov     qword ptr [rip+flag_pstn_live], 1
    inc     r12
    jmp     arg_after_dry
arg_path:
    mov     rax, r12
    shl     rax, 3
    add     rax, rbp
    add     rax, 8
    mov     rsi, [rax]
    lea     rdi, [rip+pathbuf]
    call    strcpy
    mov     r13, 1
    jmp     arg_run
arg_done:
    test    r13, r13
    jz      err_args
arg_run:
    call    run_file
    lea     rsi, [rip+msg_done]
    mov     rdx, msg_done_len
    call    write_stdout
    xor     edi, edi
    call    sys_exit

do_embed_cli:
    lea     rsi, [rip+msg_embed_cli]
    mov     rdx, msg_embed_cli_len
    call    write_stdout
    xor     edi, edi
    call    sys_exit

do_version:
    lea     rsi, [rip+msg_version]
    mov     rdx, msg_version_len
    call    write_stdout
    xor     edi, edi
    call    sys_exit

usage_ok:
    lea     rsi, [rip+msg_usage]
    mov     rdx, msg_usage_len
    call    write_stdout
    xor     edi, edi
    call    sys_exit

usage_exit:
    lea     rsi, [rip+msg_usage]
    mov     rdx, msg_usage_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

err_args:
    lea     rsi, [rip+msg_err_args]
    mov     rdx, msg_err_args_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ------------------------------------------------------------
# run_file: open pathbuf, read, interpret lines
# ------------------------------------------------------------
run_file:
    push    rbx
    push    r12
    push    r13

    cmp     qword ptr [rip+flag_live], 0
    je      rf_banner_dry
    lea     rsi, [rip+msg_banner_live]
    mov     rdx, msg_banner_live_len
    call    write_stdout
    jmp     rf_open
rf_banner_dry:
    lea     rsi, [rip+msg_banner]
    mov     rdx, msg_banner_len
    call    write_stdout
rf_open:
    # open
    lea     rdi, [rip+pathbuf]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      open_fail
    mov     r12, rax            # fd

    # read (refuse silent truncate at MAX_FILE)
    mov     rdi, r12
    lea     rsi, [rip+filebuf]
    mov     rdx, MAX_FILE
    call    sys_read
    cmp     rax, 0
    jl      open_fail
    cmp     rax, MAX_FILE
    jge     trunc_fail
    mov     r13, rax            # length
    lea     rdi, [rip+filebuf]
    add     rdi, r13
    mov     byte ptr [rdi], 0

    mov     rdi, r12
    call    sys_close

    # clear bindings store
    mov     byte ptr [rip+vars], 0
    mov     qword ptr [rip+last_val_len], 0

# walk lines — use r14/r15 so interpret_line's rbx save cannot alias cursor
    lea     r14, [rip+filebuf]
    lea     r15, [rip+filebuf]
    add     r15, r13            # end

line_loop:
    cmp     r14, r15
    jge     run_done
    lea     rdi, [rip+linebuf]
    mov     rcx, 0
copy_line:
    cmp     r14, r15
    jge     line_ready
    mov     al, [r14]
    inc     r14
    cmp     al, 10
    je      line_ready
    cmp     rcx, MAX_LINE-1
    jge     copy_line
    mov     [rdi+rcx], al
    inc     rcx
    jmp     copy_line
line_ready:
    mov     byte ptr [rdi+rcx], 0
    call    interpret_line
    jmp     line_loop

run_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

trunc_fail:
    mov     rdi, r12
    call    sys_close
    lea     rsi, [rip+msg_err_trunc]
    mov     rdx, msg_err_trunc_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

open_fail:
    lea     rsi, [rip+msg_err_open]
    mov     rdx, msg_err_open_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

# ------------------------------------------------------------
# interpret_line: dispatch on first keyword in linebuf
# ------------------------------------------------------------
interpret_line:
    push    rbx
    lea     rbx, [rip+linebuf]
    call    skip_ws
    mov     rbx, rax
    # empty / comment
    cmp     byte ptr [rbx], 0
    je      il_done
    cmp     byte ptr [rbx], '#'
    je      il_done
    cmp     byte ptr [rbx], '}'
    jne     il_not_end_block
    # end with-tools scope
    mov     qword ptr [rip+tools_active], 0
    jmp     il_done
il_not_end_block:
    cmp     byte ptr [rbx], '{'
    je      il_done
    cmp     byte ptr [rbx], '|'
    jne     il_qcheck
    # pipe prefix
    inc     rbx
    call    skip_ws_from_rbx
    mov     rbx, rax

il_qcheck:
    cmp     byte ptr [rbx], '?'
    jne     il_kw
    jmp     do_ask

il_kw:
    # match keywords
    mov     rsi, rbx
    lea     rdi, [rip+kw_use]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jnz     do_model

    mov     rsi, rbx
    lea     rdi, [rip+kw_ask]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jnz     do_ask

    mov     rsi, rbx
    lea     rdi, [rip+kw_gen]
    mov     rdx, 8
    call    keyword_match
    test    rax, rax
    jnz     do_ask

    mov     rsi, rbx
    lea     rdi, [rip+kw_cls]
    mov     rdx, 8
    call    keyword_match
    test    rax, rax
    jnz     do_classify

    mov     rsi, rbx
    lea     rdi, [rip+kw_embed]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_embed

    mov     rsi, rbx
    lea     rdi, [rip+kw_retrieve]
    mov     rdx, 8
    call    keyword_match
    test    rax, rax
    jnz     do_retrieve

    mov     rsi, rbx
    lea     rdi, [rip+kw_shell]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_shell

    mov     rsi, rbx
    lea     rdi, [rip+kw_run]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jnz     do_shell

    mov     rsi, rbx
    lea     rdi, [rip+kw_listen]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_listen

    mov     rsi, rbx
    lea     rdi, [rip+kw_speak]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_speak

    mov     rsi, rbx
    lea     rdi, [rip+kw_say]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jnz     do_speak

    mov     rsi, rbx
    lea     rdi, [rip+kw_pipe]
    mov     rdx, 8
    call    keyword_match
    test    rax, rax
    jnz     do_pipeline

    mov     rsi, rbx
    lea     rdi, [rip+kw_voice]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_voice

    mov     rsi, rbx
    lea     rdi, [rip+kw_model]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_model

    mov     rsi, rbx
    lea     rdi, [rip+kw_print]
    mov     rdx, 5
    call    keyword_match
    test    rax, rax
    jnz     do_print

    mov     rsi, rbx
    lea     rdi, [rip+kw_extract]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_extract

    mov     rsi, rbx
    lea     rdi, [rip+kw_tool]
    mov     rdx, 4
    call    keyword_match
    test    rax, rax
    jnz     do_tool

    mov     rsi, rbx
    lea     rdi, [rip+kw_review]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_review

    mov     rsi, rbx
    lea     rdi, [rip+kw_builder]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_builder

    mov     rsi, rbx
    lea     rdi, [rip+kw_implement]
    mov     rdx, 9
    call    keyword_match
    test    rax, rax
    jnz     do_implement

    mov     rsi, rbx
    lea     rdi, [rip+kw_cuda]
    mov     rdx, 4
    call    keyword_match
    test    rax, rax
    jnz     do_cuda

    mov     rsi, rbx
    lea     rdi, [rip+kw_pcie]
    mov     rdx, 4
    call    keyword_match
    test    rax, rax
    jnz     do_pcie

    mov     rsi, rbx
    lea     rdi, [rip+kw_memory]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_memory

    mov     rsi, rbx
    lea     rdi, [rip+kw_binary]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_binary

    mov     rsi, rbx
    lea     rdi, [rip+kw_network]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_network

    mov     rsi, rbx
    lea     rdi, [rip+kw_os]
    mov     rdx, 2
    call    keyword_match
    test    rax, rax
    jnz     do_os

    mov     rsi, rbx
    lea     rdi, [rip+kw_browser]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_browser

    mov     rsi, rbx
    lea     rdi, [rip+kw_engine]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_engine

    mov     rsi, rbx
    lea     rdi, [rip+kw_ide]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jnz     do_ide

    mov     rsi, rbx
    lea     rdi, [rip+kw_mitm]
    mov     rdx, 4
    call    keyword_match
    test    rax, rax
    jnz     do_mitm

    mov     rsi, rbx
    lea     rdi, [rip+kw_js]
    mov     rdx, 2
    call    keyword_match
    test    rax, rax
    jnz     do_js

    mov     rsi, rbx
    lea     rdi, [rip+kw_crypto]
    mov     rdx, 6
    call    keyword_match
    test    rax, rax
    jnz     do_crypto

    mov     rsi, rbx
    lea     rdi, [rip+kw_encrypt]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_encrypt

    mov     rsi, rbx
    lea     rdi, [rip+kw_gateway]
    mov     rdx, 7
    call    keyword_match
    test    rax, rax
    jnz     do_gateway

    mov     rsi, rbx
    lea     rdi, [rip+kw_let]
    mov     rdx, 3
    call    keyword_match
    test    rax, rax
    jz      il_try_with
    call    do_let
    jmp     il_done
il_try_with:
    mov     rsi, rbx
    lea     rdi, [rip+kw_with]
    mov     rdx, 4
    call    keyword_match
    test    rax, rax
    jz      il_after_with
    call    do_with
    jmp     il_done
il_after_with:

    # schema / string body lines are not statements
    cmp     byte ptr [rbx], '"'
    je      il_done
    call    looks_like_field
    test    rax, rax
    jnz     il_done

    # unknown / unimplemented → fail loud
    lea     rsi, [rip+msg_err_unknown]
    mov     rdx, msg_err_unknown_len
    call    write_stdout
    mov     rsi, rbx
    call    strlen
    mov     rdx, rax
    mov     rsi, rbx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    mov     edi, 1
    call    sys_exit

il_done:
    pop     rbx
    ret

# --- statement handlers ---

do_ask:
    # ask probe (no quote) → gateway probe credential check
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jnz     ask_not_probe
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_probe]
    call    contains
    test    rax, rax
    jz      ask_not_probe
    call    ask_probe_dispatch
    jmp     il_done
ask_not_probe:
    cmp     qword ptr [rip+enc_gateway_on], 0
    je      ask_plain
    call    ask_encrypt_dispatch
    jmp     il_done
ask_plain:
    cmp     qword ptr [rip+flag_live], 0
    je      ask_dry
    call    ask_live_dispatch
    jmp     il_done
ask_dry:
    lea     rsi, [rip+msg_ask]
    mov     rdx, msg_ask_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ask_noreply
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
ask_noreply:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    # with tools active → dry invoke registered tool stub
    cmp     qword ptr [rip+tools_active], 0
    je      ask_no_tools
    cmp     qword ptr [rip+tool_reg_len], 0
    je      ask_no_tools
    # build "[tool:NAME] stub:local" into tmpbuf
    lea     rdi, [rip+tmpbuf]
    lea     rsi, [rip+msg_tool_call]
    mov     rcx, msg_tool_call_len
    xor     r8, r8
ask_tc_copy:
    cmp     r8, rcx
    jge     ask_tc_name
    mov     al, [rsi+r8]
    mov     [rdi+r8], al
    inc     r8
    jmp     ask_tc_copy
ask_tc_name:
    lea     rsi, [rip+tool_reg_name]
    mov     rcx, qword ptr [rip+tool_reg_len]
    xor     r9, r9
ask_tn_copy:
    cmp     r9, rcx
    jge     ask_tc_stub
    mov     al, [rsi+r9]
    mov     [rdi+r8], al
    inc     r8
    inc     r9
    jmp     ask_tn_copy
ask_tc_stub:
    lea     rsi, [rip+msg_tool_stub]
    mov     rcx, msg_tool_stub_len
    xor     r9, r9
ask_ts_copy:
    cmp     r9, rcx
    jge     ask_tc_done
    mov     al, [rsi+r9]
    mov     [rdi+r8], al
    inc     r8
    inc     r9
    jmp     ask_ts_copy
ask_tc_done:
    mov     byte ptr [rdi+r8], 0
    lea     rax, [rip+tmpbuf]
    mov     rcx, r8
    jmp     ask_emit
ask_no_tools:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ask_whole
    push    r12
    push    r13
    mov     rdi, rax
    mov     r12, rax
    add     r12, rcx
    movzx   r13, byte ptr [r12]
    mov     byte ptr [r12], 0
    call    pick_ask_reply_ptr
    mov     byte ptr [r12], r13b
    pop     r13
    pop     r12
    jmp     ask_emit
ask_whole:
    lea     rdi, [rip+linebuf]
    call    pick_ask_reply_ptr
ask_emit:
    push    rax
    push    rcx
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_accounting]
    mov     rdx, msg_accounting_len
    call    write_stdout
    jmp     il_done


do_shell:
    lea     rsi, [rip+msg_shell]
    mov     rdx, msg_shell_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      shell_refuse
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      shell_refuse
    mov     rsi, rax
    mov     rdx, rcx
    cmp     rdx, 4
    jb      shell_refuse
    cmp     byte ptr [rsi], 'e'
    jne     shell_chk_t
    cmp     byte ptr [rsi+1], 'c'
    jne     shell_chk_t
    cmp     byte ptr [rsi+2], 'h'
    jne     shell_chk_t
    cmp     byte ptr [rsi+3], 'o'
    jne     shell_chk_t
    cmp     rdx, 4
    je      shell_ok_echo
    cmp     byte ptr [rsi+4], ' '
    jne     shell_chk_t
    jmp     shell_ok_echo
shell_chk_t:
    cmp     rdx, 4
    jne     shell_chk_f
    cmp     byte ptr [rsi], 't'
    jne     shell_chk_f
    cmp     byte ptr [rsi+1], 'r'
    jne     shell_chk_f
    cmp     byte ptr [rsi+2], 'u'
    jne     shell_chk_f
    cmp     byte ptr [rsi+3], 'e'
    jne     shell_chk_f
    jmp     shell_ok_true
shell_chk_f:
    cmp     rdx, 5
    jne     shell_refuse
    cmp     byte ptr [rsi], 'f'
    jne     shell_refuse
    cmp     byte ptr [rsi+1], 'a'
    jne     shell_refuse
    cmp     byte ptr [rsi+2], 'l'
    jne     shell_refuse
    cmp     byte ptr [rsi+3], 's'
    jne     shell_refuse
    cmp     byte ptr [rsi+4], 'e'
    jne     shell_refuse
    jmp     shell_ok_false
shell_ok_echo:
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_shell_echo]
    mov     rdx, dry_shell_echo_len
    call    write_stdout
    lea     rax, [rip+dry_shell_echo]
    mov     rcx, dry_shell_echo_len
    call    set_last_from_rcx
    jmp     shell_bind
shell_ok_true:
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_shell_true]
    mov     rdx, dry_shell_true_len
    call    write_stdout
    lea     rax, [rip+dry_shell_true]
    mov     rcx, dry_shell_true_len
    call    set_last_from_rcx
    jmp     shell_bind
shell_ok_false:
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_shell_false]
    mov     rdx, dry_shell_false_len
    call    write_stdout
    lea     rax, [rip+dry_shell_false]
    mov     rcx, dry_shell_false_len
    call    set_last_from_rcx
shell_bind:
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done
shell_refuse:
    lea     rsi, [rip+msg_shell_refuse]
    mov     rdx, msg_shell_refuse_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

do_classify:
    lea     rsi, [rip+msg_cls]
    mov     rdx, msg_cls_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      cls_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    push    r12
    push    r13
    mov     rdi, rax
    mov     r12, rax
    add     r12, rcx
    movzx   r13, byte ptr [r12]
    mov     byte ptr [r12], 0
    call    pick_classify_ptr
    mov     byte ptr [r12], r13b
    pop     r13
    pop     r12
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done
cls_noq:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_support]
    mov     rdx, dry_support_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_embed:
    cmp     qword ptr [rip+flag_live], 0
    je      embed_dry
    call    embed_live_dispatch
    jmp     il_done
embed_dry:
    lea     rsi, [rip+msg_embed]
    mov     rdx, msg_embed_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      emb_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
emb_noq:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_embed]
    mov     rdx, dry_embed_len
    mov     rax, rsi
    mov     rcx, rdx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_retrieve:
    cmp     qword ptr [rip+flag_live], 0
    je      retrieve_dry
    call    retrieve_live_dispatch
    jmp     il_done
retrieve_dry:
    lea     rsi, [rip+msg_retrieve]
    mov     rdx, msg_retrieve_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ret_noq
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    # cue-match like dry_rag.c
    push    rax
    push    rcx
    mov     rdi, rax
    lea     rsi, [rip+needle_embed]
    call    contains
    test    rax, rax
    jnz     ret_hit
    pop     rcx
    pop     rax
    push    rax
    push    rcx
    mov     rdi, rax
    lea     rsi, [rip+needle_retrieve]
    call    contains
    test    rax, rax
    jnz     ret_hit
    pop     rcx
    pop     rax
    push    rax
    push    rcx
    mov     rdi, rax
    lea     rsi, [rip+needle_dryrun]
    call    contains
    test    rax, rax
    jnz     ret_hit
    pop     rcx
    pop     rax
    push    rax
    push    rcx
    mov     rdi, rax
    lea     rsi, [rip+needle_language]
    call    contains
    test    rax, rax
    jnz     ret_hit
    pop     rcx
    pop     rax
    push    rax
    push    rcx
    mov     rdi, rax
    lea     rsi, [rip+needle_rag]
    call    contains
    test    rax, rax
    jnz     ret_hit
    pop     rcx
    pop     rax
    jmp     ret_empty
ret_hit:
    pop     rcx
    pop     rax
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_retrieve]
    mov     rdx, dry_retrieve_len
    mov     rax, rsi
    mov     rcx, rdx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done
ret_empty:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_retrieve_empty]
    mov     rdx, dry_retrieve_empty_len
    mov     rax, rsi
    mov     rcx, rdx
    push    rax
    push    rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done
ret_noq:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rsi, [rip+dry_retrieve_empty]
    mov     rdx, dry_retrieve_empty_len
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_listen:
    cmp     qword ptr [rip+flag_live], 0
    je      listen_dry
    call    voice_listen_live_dispatch
    jmp     il_done
listen_dry:
    lea     rsi, [rip+msg_listen]
    mov     rdx, msg_listen_len
    call    write_stdout
    lea     rsi, [rip+dry_transcript]
    mov     rdx, dry_transcript_len
    call    write_stdout
    lea     rax, [rip+dry_transcript]
    mov     rcx, dry_transcript_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_speak:
    cmp     qword ptr [rip+flag_live], 0
    je      speak_dry
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_with_model]
    call    contains
    test    rax, rax
    jz      speak_live_go
    call    voice_speak_model_dispatch
speak_live_go:
    call    voice_speak_live_dispatch
    jmp     il_done
speak_dry:
    lea     rsi, [rip+msg_speak]
    mov     rdx, msg_speak_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_with_model]
    call    contains
    test    rax, rax
    jz      speak_wav
    call    voice_speak_model_dispatch
speak_wav:
    # default out; honor speak … -> "path.wav" (was always spark-out.wav)
    lea     rsi, [rip+default_wav]
    lea     rdi, [rip+speak_path]
    call    strcpy
    xor     r12, r12
    lea     rdi, [rip+linebuf]
spk_ar_scan:
    cmp     byte ptr [rdi], 0
    je      spk_ar_done
    cmp     byte ptr [rdi], '-'
    jne     spk_ar_inc
    cmp     byte ptr [rdi+1], '>'
    jne     spk_ar_inc
    mov     r12, rdi
    jmp     spk_ar_done
spk_ar_inc:
    inc     rdi
    jmp     spk_ar_scan
spk_ar_done:
    test    r12, r12
    jz      spk_write
    lea     rdi, [r12+2]
    call    extract_quote
    test    rax, rax
    jz      spk_write
    mov     rsi, rax
    mov     r13, rcx
    lea     rdi, [rip+speak_path]
    xor     r12, r12
spk_cp:
    cmp     r12, r13
    jge     spk_cp_d
    cmp     r12, 255
    jge     spk_cp_d
    mov     al, [rsi+r12]
    mov     [rdi+r12], al
    inc     r12
    jmp     spk_cp
spk_cp_d:
    mov     byte ptr [rdi+r12], 0
spk_write:
    lea     rdi, [rip+speak_path]
    call    write_stub_wav
    lea     rsi, [rip+speak_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+speak_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_pipeline:
    lea     rsi, [rip+msg_pipe]
    mov     rdx, msg_pipe_len
    call    write_stdout
    jmp     il_done

do_voice:
    lea     rsi, [rip+msg_voice]
    mov     rdx, msg_voice_len
    call    write_stdout
    # review|code|copy|model|pstn → voice_ops; else session block
    call    voice_ops_dispatch
    jmp     il_done

do_model:
    lea     rsi, [rip+msg_model]
    mov     rdx, msg_model_len
    call    write_stdout
    # analyze|compare|improve|build live in asm/model_ops.s
    call    model_ops_dispatch
    # remember plain alias for --live ask
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_analyze_kw]
    call    contains
    test    rax, rax
    jnz     model_done
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_compare_kw]
    call    contains
    test    rax, rax
    jnz     model_done
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_improve_kw]
    call    contains
    test    rax, rax
    jnz     model_done
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_build_kw]
    call    contains
    test    rax, rax
    jnz     model_done
    call    ask_remember_model
model_done:
    jmp     il_done

do_print:
    lea     rsi, [rip+msg_print]
    mov     rdx, msg_print_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      print_ident
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    jmp     print_nl
print_ident:
    lea     rbx, [rip+linebuf]
    call    skip_ws
    add     rax, 5
    mov     rbx, rax
    call    skip_ws_from_rbx
    mov     rbx, rax
    # null-term first token into tmpbuf for vars_get
    lea     rdi, [rip+tmpbuf]
    xor     rcx, rcx
pi_tok:
    mov     al, [rbx+rcx]
    cmp     al, 0
    je      pi_tok_done
    cmp     al, ' '
    je      pi_tok_done
    cmp     al, '\t'
    je      pi_tok_done
    cmp     rcx, 62
    jge     pi_tok_done
    mov     [rdi+rcx], al
    inc     rcx
    jmp     pi_tok
pi_tok_done:
    mov     byte ptr [rdi+rcx], 0
    lea     rdi, [rip+tmpbuf]
    call    vars_get
    test    rax, rax
    jz      pi_raw
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    jmp     print_nl
pi_raw:
    lea     rsi, [rip+tmpbuf]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+tmpbuf]
    call    write_stdout
print_nl:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_extract:
    lea     rsi, [rip+msg_extract]
    mov     rdx, msg_extract_len
    call    write_stdout
    lea     rsi, [rip+dry_person]
    mov     rdx, dry_person_len
    call    write_stdout
    lea     rax, [rip+dry_person]
    mov     rcx, dry_person_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

do_tool:
    lea     rsi, [rip+msg_tool]
    mov     rdx, msg_tool_len
    call    write_stdout
    lea     rbx, [rip+linebuf]
    call    skip_ws
    add     rax, 4
    mov     rbx, rax
    call    skip_ws_from_rbx
    mov     rsi, rax
    # print + register name until '(' or space
    mov     rcx, 0
tool_name:
    mov     al, [rsi+rcx]
    cmp     al, 0
    je      tool_name_done
    cmp     al, '('
    je      tool_name_done
    cmp     al, ' '
    je      tool_name_done
    inc     rcx
    jmp     tool_name
tool_name_done:
    cmp     rcx, 63
    jle     tool_name_ok
    mov     rcx, 63
tool_name_ok:
    mov     qword ptr [rip+tool_reg_len], rcx
    push    rsi
    push    rcx
    lea     rdi, [rip+tool_reg_name]
    xor     r8, r8
tool_copy:
    cmp     r8, rcx
    jge     tool_copy_done
    mov     al, [rsi+r8]
    mov     [rdi+r8], al
    inc     r8
    jmp     tool_copy
tool_copy_done:
    mov     byte ptr [rdi+rcx], 0
    pop     rcx
    pop     rsi
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

# --- review / builder / implement ---

do_review:
    push    r12
    push    r13
    lea     rsi, [rip+msg_review]
    mov     rdx, msg_review_len
    call    write_stdout
    # review url → companion (file:// offline; http needs --allow-net)
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_url]
    call    contains
    test    rax, rax
    jz      rev_try_path
    jmp     do_review_url

rev_try_path:
    # review path "…" must open the file
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_path]
    call    contains
    test    rax, rax
    jz      rev_emit_path
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      rev_path_fail
    # copy path — use tmpbuf
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+tmpbuf]
    xor     r13, r13
rev_copy:
    cmp     r13, r12
    jge     rev_path_ok
    cmp     r13, 1022
    jge     rev_path_ok
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     rev_copy
rev_path_ok:
    mov     byte ptr [rdi+r13], 0
    lea     rdi, [rip+tmpbuf]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rev_path_fail
    mov     rdi, rax
    call    sys_close
    jmp     rev_emit_path
rev_path_fail:
    lea     rsi, [rip+msg_err_review_path]
    mov     rdx, msg_err_review_path_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

rev_emit_path:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      rev_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
rev_noq:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_noreval]
    mov     rdx, msg_noreval_len
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    pick_review_report
    push    rax
    push    rcx
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     r13
    pop     r12
    jmp     il_done

# review url — fork ./spark-review-url (never eval)
do_review_url:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      rev_url_noq
    # copy URL into review_url_buf
    mov     rsi, rax
    mov     r12, rcx
    lea     rdi, [rip+review_url_buf]
    xor     r13, r13
rev_url_copy:
    cmp     r13, r12
    jge     rev_url_copied
    cmp     r13, 1022
    jge     rev_url_copied
    mov     al, [rsi+r13]
    mov     [rdi+r13], al
    inc     r13
    jmp     rev_url_copy
rev_url_copied:
    mov     byte ptr [rdi+r13], 0
    lea     rsi, [rip+review_url_buf]
    mov     rdx, r13
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_noreval]
    mov     rdx, msg_noreval_len
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    # argv: bin --url URL --out PATH [--allow-net]
    lea     rax, [rip+review_bin]
    mov     [rip+review_argv], rax
    lea     rax, [rip+review_flag_url]
    mov     [rip+review_argv+8], rax
    lea     rax, [rip+review_url_buf]
    mov     [rip+review_argv+16], rax
    lea     rax, [rip+review_flag_out]
    mov     [rip+review_argv+24], rax
    lea     rax, [rip+review_out_path]
    mov     [rip+review_argv+32], rax
    cmp     qword ptr [rip+flag_allow_net], 1
    jne     rev_url_argv_done
    lea     rax, [rip+review_flag_net]
    mov     [rip+review_argv+40], rax
    mov     qword ptr [rip+review_argv+48], 0
    jmp     rev_url_fork
rev_url_argv_done:
    mov     qword ptr [rip+review_argv+40], 0
rev_url_fork:
    lea     rdi, [rip+review_bin]
    lea     rsi, [rip+review_argv]
    call    fork_exec_wait
    test    rax, rax
    jz      rev_url_ok
    # non-zero: companion error (remote needs --allow-net, etc.)
    mov     edi, eax
    test    edi, edi
    jnz     rev_url_exit
    mov     edi, 1
rev_url_exit:
    call    sys_exit
rev_url_ok:
    # read JSON report from --out
    lea     rdi, [rip+review_out_path]
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    call    sys_open
    cmp     rax, 0
    jl      rev_url_comp_fail
    mov     r12, rax
    mov     rdi, r12
    lea     rsi, [rip+outbuf]
    mov     rdx, 4095
    call    sys_read
    mov     r13, rax
    mov     rdi, r12
    call    sys_close
    cmp     r13, 0
    jle     rev_url_comp_fail
    # trim trailing newline for bind; still print with nl after
    lea     rsi, [rip+outbuf]
    mov     rdx, r13
    call    write_stdout
    # ensure last_val has the JSON (strip final \n if present)
    lea     rax, [rip+outbuf]
    mov     rcx, r13
    cmp     rcx, 0
    jle     rev_url_bind
    cmp     byte ptr [rax+rcx-1], 10
    jne     rev_url_bind
    dec     rcx
rev_url_bind:
    call    set_last_from_rcx
    call    bind_arrow_from_line
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    pop     r13
    pop     r12
    jmp     il_done
rev_url_noq:
    lea     rsi, [rip+msg_err_review_url]
    mov     rdx, msg_err_review_url_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit
rev_url_comp_fail:
    lea     rsi, [rip+msg_err_review_comp]
    mov     rdx, msg_err_review_comp_len
    call    write_stdout
    mov     edi, 1
    call    sys_exit

do_builder:
    lea     rsi, [rip+msg_builder]
    mov     rdx, msg_builder_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      bld_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
bld_noq:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_reply]
    mov     rdx, msg_reply_len
    call    write_stdout
    lea     rdi, [rip+linebuf]
    call    pick_builder_plan
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

# --- binary (ELF open/parse in asm; dynsym/objdump via probe) ---

do_binary:
    call    binary_ops_dispatch
    jmp     il_done

do_network:
    call    network_ops_dispatch
    jmp     il_done

do_os:
    call    os_ops_dispatch
    jmp     il_done

do_browser:
    call    browser_ops_dispatch
    jmp     il_done

do_engine:
    # Engine B ops router (fetch/parse/css/layout/paint/render/show)
    call    engine_ops_dispatch
    jmp     il_done

do_ide:
    # keys/key first (keymap lane); else core new|open|save|run|buffer
    call    ide_keys_dispatch
    test    rax, rax
    jnz     il_done
    call    ide_ops_dispatch
    jmp     il_done

do_mitm:
    call    mitm_ops_dispatch
    jmp     il_done

do_js:
    call    engine_js_ops_dispatch
    jmp     il_done

# --- cuda / memory / pcie (asm device + sysfs) ---

do_cuda:
    call    cuda_ops_dispatch
    jmp     il_done

do_pcie:
    call    pcie_ops_dispatch
    jmp     il_done

do_crypto:
    call    crypto_ops_dispatch
    jmp     il_done

do_encrypt:
    call    encrypt_ops_dispatch
    jmp     il_done

do_gateway:
    call    gateway_ops_dispatch
    jmp     il_done

do_memory:
    call    memory_ops_dispatch
    jmp     il_done

# fork_exec_wait: rdi=path rsi=argv → rax=0 ok, else child exit status
# (or 1 if signaled / wait failed). Passes parent environ to child.
fork_exec_wait:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     eax, SYS_FORK
    syscall
    test    rax, rax
    js      few_fail
    jz      few_child
    mov     r13, rax                # child pid
    lea     rsi, [rip+tmpbuf]       # status
    mov     rdi, r13
    xor     rdx, rdx
    xor     r10, r10
    mov     eax, SYS_WAIT4
    syscall
    mov     eax, [rip+tmpbuf]
    # WIFEXITED && WEXITSTATUS==0 → (status & 0xff00)==0 and (status&0x7f)==0
    test    eax, 0x7f
    jnz     few_fail
    shr     eax, 8
    and     eax, 0xff
    test    eax, eax
    jnz     few_fail_status
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret
few_fail_status:
    mov     ebx, eax                # preserve exit status
    pop     r13
    pop     r12
    mov     eax, ebx
    pop     rbx
    ret
few_child:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [rip+saved_envp]
    mov     eax, SYS_EXECVE
    syscall
    mov     edi, 127
    call    sys_exit
few_fail:
    pop     r13
    pop     r12
    pop     rbx
    mov     rax, 1
    ret

do_implement:
    # mkdir out (ignore EEXIST)
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+linebuf]
    # .py in path/line → suggestion layer; else Spark artifact
    lea     rsi, [rip+needle_py]
    call    contains
    test    rax, rax
    jnz     impl_py
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_higher]
    call    contains
    test    rax, rax
    jz      impl_spark
impl_py:
    lea     rdi, [rip+default_out_py]
    lea     rsi, [rip+impl_py_body]
    mov     rdx, impl_py_body_len
    call    write_bytes_path
    lea     rsi, [rip+msg_impl]
    mov     rdx, msg_impl_len
    call    write_stdout
    lea     rsi, [rip+default_out_py]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+default_out_py]
    call    write_stdout
    jmp     impl_nl
impl_spark:
    lea     rdi, [rip+default_out_spark]
    lea     rsi, [rip+impl_spark_body]
    mov     rdx, impl_spark_body_len
    call    write_bytes_path
    lea     rsi, [rip+msg_impl]
    mov     rdx, msg_impl_len
    call    write_stdout
    lea     rsi, [rip+default_out_spark]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+default_out_spark]
    call    write_stdout
impl_nl:
    lea     rsi, [rip+msg_nl]
    mov     rdx, 1
    call    write_stdout
    jmp     il_done

# pick_review_report: rdi=line → rax/rcx path/text JSON
# (url never reaches here — companion path)
pick_review_report:
    push    rbx
    mov     rbx, rdi
pr_path:
    mov     rdi, rbx
    lea     rsi, [rip+needle_js]
    call    contains
    test    rax, rax
    jnz     pr_higher
    mov     rdi, rbx
    lea     rsi, [rip+needle_py]
    call    contains
    test    rax, rax
    jnz     pr_higher
    mov     rdi, rbx
    lea     rsi, [rip+needle_eval]
    call    contains
    test    rax, rax
    jnz     pr_higher
    mov     rdi, rbx
    lea     rsi, [rip+needle_spark]
    call    contains
    test    rax, rax
    jnz     pr_mid
    mov     rdi, rbx
    lea     rsi, [rip+needle_asm]
    call    contains
    test    rax, rax
    jz      pr_mid
    lea     rax, [rip+dry_rev_lower]
    mov     rcx, dry_rev_lower_len
    pop     rbx
    ret
pr_higher:
    lea     rax, [rip+dry_rev_higher]
    mov     rcx, dry_rev_higher_len
    pop     rbx
    ret
pr_mid:
    lea     rax, [rip+dry_rev_mid]
    mov     rcx, dry_rev_mid_len
    pop     rbx
    ret

pick_builder_plan:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rip+needle_lower]
    call    contains
    test    rax, rax
    jz      pb_hi
    lea     rax, [rip+dry_bld_lower]
    mov     rcx, dry_bld_lower_len
    pop     rbx
    ret
pb_hi:
    mov     rdi, rbx
    lea     rsi, [rip+needle_higher]
    call    contains
    test    rax, rax
    jz      pb_auto
    lea     rax, [rip+dry_bld_higher]
    mov     rcx, dry_bld_higher_len
    pop     rbx
    ret
pb_auto:
    lea     rax, [rip+dry_bld_auto]
    mov     rcx, dry_bld_auto_len
    pop     rbx
    ret

# write_bytes_path: rdi=path cstr, rsi=buf, rdx=len
write_bytes_path:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     rdi, rbx
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 420
    call    sys_open
    cmp     rax, 0
    jl      wbp_done
    mov     rdi, rax
    push    rdi
    mov     rsi, r12
    mov     rdx, r13
    call    sys_write
    pop     rdi
    call    sys_close
wbp_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# pick_ask_reply_ptr: rdi=text → rax=ptr rcx=len
# ------------------------------------------------------------
pick_ask_reply_ptr:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rip+needle_gravity]
    call    contains
    test    rax, rax
    jz      pa_sum
    lea     rax, [rip+dry_gravity]
    mov     rcx, dry_gravity_len
    pop     rbx
    ret
pa_sum:
    mov     rdi, rbx
    lea     rsi, [rip+needle_trans]
    call    contains
    test    rax, rax
    jnz     pa_es_hit
    lea     rsi, [rip+needle_span]
    call    contains
    test    rax, rax
    jnz     pa_es_hit
    lea     rsi, [rip+needle_sum]
    call    contains
    test    rax, rax
    jz      pa_help
    lea     rax, [rip+dry_summary]
    mov     rcx, dry_summary_len
    pop     rbx
    ret
pa_es_hit:
    lea     rax, [rip+dry_es]
    mov     rcx, dry_es_len
    pop     rbx
    ret
pa_help:
    mov     rdi, rbx
    lea     rsi, [rip+needle_reply]
    call    contains
    test    rax, rax
    jz      pa_help2
    lea     rax, [rip+dry_reply]
    mov     rcx, dry_reply_len
    pop     rbx
    ret
pa_help2:
    mov     rdi, rbx
    lea     rsi, [rip+needle_intent]
    call    contains
    test    rax, rax
    jnz     pa_intent
    lea     rsi, [rip+needle_json]
    call    contains
    test    rax, rax
    jnz     pa_json
    lea     rsi, [rip+needle_weather]
    call    contains
    test    rax, rax
    jnz     pa_weather
    mov     rdi, rbx
    lea     rsi, [rip+needle_explain]
    call    contains
    test    rax, rax
    jz      pa_one
    lea     rax, [rip+dry_gravity]
    mov     rcx, dry_gravity_len
    pop     rbx
    ret
pa_intent:
    lea     rax, [rip+dry_intent]
    mov     rcx, dry_intent_len
    pop     rbx
    ret
pa_json:
    lea     rax, [rip+dry_json]
    mov     rcx, dry_json_len
    pop     rbx
    ret
pa_weather:
    lea     rax, [rip+dry_weather]
    mov     rcx, dry_weather_len
    pop     rbx
    ret
pa_one:
    mov     rdi, rbx
    lea     rsi, [rip+needle_one_sent]
    call    contains
    test    rax, rax
    jz      pa_gen
    lea     rax, [rip+dry_gravity]
    mov     rcx, dry_gravity_len
    pop     rbx
    ret
pa_gen:
    lea     rax, [rip+dry_generic]
    mov     rcx, dry_generic_len
    pop     rbx
    ret

pick_classify_ptr:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rip+needle_spam]
    call    contains
    test    rax, rax
    jz      pc_sales
    # only treat as spam if "spam" is the message topic — require
    # unsubscribe/viagra-like, or whole word; for MVP: if needle is
    # only "spam" and text is short label collision, prefer other
    # cues first — check sales/support BEFORE spam word in enums.
    jmp     pc_sales
pc_sales:
    mov     rdi, rbx
    lea     rsi, [rip+needle_buy]
    call    contains
    test    rax, rax
    jnz     pc_sales_hit
    mov     rdi, rbx
    lea     rsi, [rip+needle_price]
    call    contains
    test    rax, rax
    jz      pc_sup_check
pc_sales_hit:
    lea     rax, [rip+dry_sales]
    mov     rcx, dry_sales_len
    pop     rbx
    ret
pc_sup_check:
    mov     rdi, rbx
    lea     rsi, [rip+needle_broken]
    call    contains
    test    rax, rax
    jnz     pc_sup
    mov     rdi, rbx
    lea     rsi, [rip+needle_help]
    call    contains
    test    rax, rax
    jnz     pc_sup
    mov     rdi, rbx
    lea     rsi, [rip+needle_support]
    call    contains
    test    rax, rax
    jnz     pc_sup
    mov     rdi, rbx
    lea     rsi, [rip+needle_spam]
    call    contains
    test    rax, rax
    jz      pc_sup
    lea     rax, [rip+dry_spam]
    mov     rcx, dry_spam_len
    pop     rbx
    ret
pc_sup:
    lea     rax, [rip+dry_support]
    mov     rcx, dry_support_len
    pop     rbx
    ret

# ------------------------------------------------------------
# write_stub_wav: rdi = path cstring — write tiny stub file
# ------------------------------------------------------------
write_stub_wav:
    push    rbx
    mov     rbx, rdi
    # open creat trunc
    mov     rdi, rbx
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 420
    call    sys_open
    cmp     rax, 0
    jl      wsv_done
    mov     r8, rax
    # write RIFF-ish stub + marker
    mov     rdi, r8
    lea     rsi, [rip+wav_stub]
    mov     rdx, wav_stub_len
    call    sys_write
    mov     rdi, r8
    call    sys_close
wsv_done:
    pop     rbx
    ret

# ------------------------------------------------------------
# string helpers
# ------------------------------------------------------------
# streq: rdi=a rsi=b → rax=1 if equal
streq:
    push    rbx
streq_loop:
    mov     al, [rdi]
    mov     bl, [rsi]
    cmp     al, bl
    jne     streq_no
    test    al, al
    jz      streq_yes
    inc     rdi
    inc     rsi
    jmp     streq_loop
streq_yes:
    mov     rax, 1
    pop     rbx
    ret
streq_no:
    xor     rax, rax
    pop     rbx
    ret

strcpy:
    push    rax
sc_loop:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     sc_loop
    pop     rax
    ret

strlen:
    push    rdi
    mov     rdi, rsi
    xor     rax, rax
slen_loop:
    cmp     byte ptr [rdi], 0
    je      slen_done
    inc     rax
    inc     rdi
    jmp     slen_loop
slen_done:
    pop     rdi
    ret

# skip_ws: rbx=ptr → rax=ptr after spaces
skip_ws:
    mov     rax, rbx
sw_loop:
    mov     cl, [rax]
    cmp     cl, ' '
    je      sw_adv
    cmp     cl, 9
    je      sw_adv
    ret
sw_adv:
    inc     rax
    jmp     sw_loop

skip_ws_from_rbx:
    mov     rax, rbx
    jmp     sw_loop

# keyword_match: rsi=text rdi=kw rdx=len → rax=1 if prefix + boundary
keyword_match:
    push    rbx
    push    rcx
    mov     rcx, rdx
    mov     rbx, rsi
km_loop:
    test    rcx, rcx
    jz      km_bound
    mov     al, [rbx]
    mov     dl, [rdi]
    # tolower-ish: only exact for MVP
    cmp     al, dl
    jne     km_no
    inc     rbx
    inc     rdi
    dec     rcx
    jmp     km_loop
km_bound:
    mov     al, [rbx]
    cmp     al, ' '
    je      km_yes
    cmp     al, '"'
    je      km_yes
    cmp     al, '{'
    je      km_yes
    cmp     al, 0
    je      km_yes
    cmp     al, 9
    je      km_yes
    cmp     al, '('
    je      km_yes
    jmp     km_no
km_yes:
    mov     rax, 1
    pop     rcx
    pop     rbx
    ret
km_no:
    xor     rax, rax
    pop     rcx
    pop     rbx
    ret

# extract_quote: rdi=line → rax=ptr inside quotes, rcx=len (0 if none)
extract_quote:
    xor     rax, rax
    xor     rcx, rcx
eq_find:
    mov     al, [rdi]
    test    al, al
    jz      eq_none
    cmp     al, '"'
    je      eq_start
    inc     rdi
    jmp     eq_find
eq_start:
    inc     rdi
    mov     rax, rdi
    xor     rcx, rcx
eq_copy:
    mov     dl, [rdi]
    test    dl, dl
    jz      eq_done
    cmp     dl, '"'
    je      eq_done
    inc     rcx
    inc     rdi
    jmp     eq_copy
eq_done:
    ret
eq_none:
    xor     rax, rax
    xor     rcx, rcx
    ret

# contains: rdi=haystack rsi=needle → rax=1/0 (case-insensitive a-z)
contains:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
c_outer:
    mov     rsi, r13
    mov     rdi, r12
    cmp     byte ptr [rdi], 0
    je      c_no
c_inner:
    mov     al, [rsi]
    test    al, al
    jz      c_yes
    mov     bl, [rdi]
    test    bl, bl
    jz      c_adv
    # lower both
    cmp     al, 'A'
    jb      c_al
    cmp     al, 'Z'
    ja      c_al
    add     al, 32
c_al:
    cmp     bl, 'A'
    jb      c_bl
    cmp     bl, 'Z'
    ja      c_bl
    add     bl, 32
c_bl:
    cmp     al, bl
    jne     c_adv
    inc     rsi
    inc     rdi
    jmp     c_inner
c_adv:
    inc     r12
    jmp     c_outer
c_yes:
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
c_no:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    ret

# ------------------------------------------------------------
# syscalls
# ------------------------------------------------------------
write_stdout:
    mov     rdi, 1
    # rsi, rdx already set
    mov     rax, SYS_WRITE
    syscall
    ret

sys_open:
    mov     rax, SYS_OPEN
    syscall
    ret

sys_read:
    mov     rax, SYS_READ
    syscall
    ret

sys_write:
    mov     rax, SYS_WRITE
    syscall
    ret

sys_close:
    mov     rax, SYS_CLOSE
    syscall
    ret

sys_lseek:
    mov     rax, SYS_LSEEK
    syscall
    ret

sys_fstat:
    mov     rax, SYS_FSTAT
    syscall
    ret

sys_mkdir:
    mov     rax, SYS_MKDIR
    syscall
    ret

sys_exit:
    mov     rax, SYS_EXIT
    syscall
