# Spark model analyze / compare / improve / train / status / plan
# Linked with asm/spark.s. Dry-run = fixtures; live forks spark-train-http.
# make test never starts GPU jobs or dials the network.
#
# Exports: model_ops_dispatch
# Imports from spark.s: linebuf, write_stdout, extract_quote, contains,
#   strlen, write_bytes_path, sys_mkdir, msg_nl, msg_reply, outdir_name,
#   flag_live, fork_exec_wait

.intel_syntax noprefix
.global model_ops_dispatch

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern outdir_name
.extern flag_live
.extern fork_exec_wait
.extern train_live_submit
.extern train_live_status

.section .data

msg_nl_local:
    .ascii "\n"
msg_reply_local:
    .ascii "  → "
msg_reply_local_len = . - msg_reply_local

msg_model_why:
    .ascii "  (metrics from fixtures/heuristics — not live leaderboard)\n"
msg_model_why_len = . - msg_model_why

msg_model_built:
    .ascii "wrote "
msg_model_built_len = . - msg_model_built

needle_analyze: .ascii "analyze\0"
needle_compare: .ascii "compare\0"
needle_improve: .ascii "improve\0"
needle_build:   .ascii "build\0"
needle_train:   .ascii "train\0"
needle_status:  .ascii "status\0"
needle_plan:    .ascii "plan\0"
needle_quality: .ascii "quality\0"
needle_speed:   .ascii "speed\0"
needle_cost:    .ascii "cost\0"
needle_local:   .ascii "local\0"
needle_all:     .ascii "all\0"
needle_fast_id: .ascii "fast\0"
needle_code_id: .ascii "code\0"

# Dry-run analyze — fixture-backed heuristics (examples/fixtures/models/)
dry_analyze_code:
    .ascii "{\"op\":\"analyze\",\"target\":\"alias-code\",\"mode\":\"dry-run\","
    .ascii "\"source\":\"examples/fixtures/models/alias-code-analyze.json\","
    .ascii "\"metrics\":{\"latency_ms_p50\":420,\"tokens_per_s\":38.2,"
    .ascii "\"quality_proxy\":0.91,\"tool_call_json_valid_pct\":94},"
    .ascii "\"failure_modes\":[\"occasional multi-tool order drift\"],"
    .ascii "\"reasons\":[\"tool-call JSON validity 94% on fixture suite\","
    .ascii "\"quality_proxy 0.91 vs suite floor 0.80\"],"
    .ascii "\"scope\":\"reachable configured+discovered only — not universal\"}"
dry_analyze_code_len = . - dry_analyze_code

dry_analyze_fast:
    .ascii "{\"op\":\"analyze\",\"target\":\"fast\",\"mode\":\"dry-run\","
    .ascii "\"source\":\"examples/fixtures/models/fast-analyze.json\","
    .ascii "\"metrics\":{\"latency_ms_p50\":95,\"tokens_per_s\":72.0,"
    .ascii "\"quality_proxy\":0.78,\"tool_call_json_valid_pct\":71},"
    .ascii "\"failure_modes\":[\"tool JSON validity drops on nested schemas\"],"
    .ascii "\"reasons\":[\"latency_ms_p50 95 (speed win vs code 420)\","
    .ascii "\"tool_call_json_valid_pct 71% vs code 94%\"],"
    .ascii "\"scope\":\"reachable configured+discovered only — not universal\"}"
dry_analyze_fast_len = . - dry_analyze_fast

dry_analyze_all:
    .ascii "{\"op\":\"analyze\",\"target\":\"all\",\"mode\":\"dry-run\","
    .ascii "\"meaning\":\"all reachable configured aliases + discovered local"
    .ascii " vLLM endpoints (read-only); not all models in existence\","
    .ascii "\"catalog\":\"data/model-catalog.jsonl\","
    .ascii "\"probed\":[\"fast\",\"code\",\"best\",\"alias-code\","
    .ascii "\"local:vllm-coder@:8003\"],"
    .ascii "\"skipped\":[{\"id\":\"public-ai-gateway.example\","
    .ascii "\"reason\":\"credential unavailable or dry-run — no routing"
    .ascii " conclusion invented\"},{\"id\":\"local:vllm-voice@:8010\","
    .ascii "\"reason\":\"reserved voice-only GPU — probe listed read-only,"
    .ascii " never killed\"}],"
    .ascii "\"metrics_summary\":{\"n\":4,\"note\":\"fixture rows only\"},"
    .ascii "\"reasons\":[\"catalog lists real probe/fixture rows only\","
    .ascii "\"extension hooks: spark.toml [models], SPARK_MODEL_* env\"]}"
dry_analyze_all_len = . - dry_analyze_all

dry_analyze_generic:
    .ascii "{\"op\":\"analyze\",\"target\":\"generic\",\"mode\":\"dry-run\","
    .ascii "\"source\":\"examples/fixtures/models/generic-analyze.json\","
    .ascii "\"metrics\":{\"latency_ms_p50\":300,\"tokens_per_s\":40.0,"
    .ascii "\"quality_proxy\":0.85,\"tool_call_json_valid_pct\":80},"
    .ascii "\"failure_modes\":[\"unknown target — used generic fixture\"],"
    .ascii "\"reasons\":[\"no invented live leaderboard numbers\","
    .ascii "\"replace with recorded fixture for this id\"]}"
dry_analyze_generic_len = . - dry_analyze_generic

dry_compare:
    .ascii "{\"op\":\"compare\",\"mode\":\"dry-run\","
    .ascii "\"suite\":\"examples/eval_suite.json\","
    .ascii "\"models\":[\"fast\",\"code\",\"best\"],"
    .ascii "\"metrics\":["
    .ascii "{\"id\":\"fast\",\"latency_ms_p50\":95,\"tokens_per_s\":72.0,"
    .ascii "\"quality_proxy\":0.78,\"tool_call_json_valid_pct\":71},"
    .ascii "{\"id\":\"code\",\"latency_ms_p50\":420,\"tokens_per_s\":38.2,"
    .ascii "\"quality_proxy\":0.91,\"tool_call_json_valid_pct\":94},"
    .ascii "{\"id\":\"best\",\"latency_ms_p50\":610,\"tokens_per_s\":28.0,"
    .ascii "\"quality_proxy\":0.93,\"tool_call_json_valid_pct\":96}"
    .ascii "],"
    .ascii "\"failure_modes\":[\"fast: nested tool JSON\","
    .ascii "\"best: higher latency on short prompts\"],"
    .ascii "\"reasons\":["
    .ascii "\"code wins tool-call JSON validity 94% vs 71% (fast)\","
    .ascii "\"best edges quality_proxy 0.93 vs code 0.91\","
    .ascii "\"fast wins latency_ms_p50 95 vs code 420\"],"
    .ascii "\"winner_by\":{\"quality\":\"best\",\"speed\":\"fast\","
    .ascii "\"tool_json\":\"best\",\"balanced\":\"code\"},"
    .ascii "\"note\":\"numbers from fixtures — not live leaderboard\"}"
dry_compare_len = . - dry_compare

dry_improve_quality:
    .ascii "{\"op\":\"improve\",\"prefer\":\"quality\",\"mode\":\"dry-run\","
    .ascii "\"from\":\"report\",\"blueprint\":{"
    .ascii "\"architecture\":\"route hard tool-call turns to code/best;"
    .ascii " keep fast for short classify\","
    .ascii "\"suggestion\":\"raise min tool_json gate; add JSON-repair once\","
    .ascii "\"config\":{\"primary\":\"code\",\"fallback\":\"best\","
    .ascii "\"repair_once\":true,\"train\":false},"
    .ascii "\"metrics_delta\":{\"quality_proxy\":\"+0.02 expected vs code"
    .ascii " alone\",\"tool_call_json_valid_pct\":\"+2 pts vs code\","
    .ascii "\"latency_ms_p50\":\"+80 vs code (best path)\"},"
    .ascii "\"exact_why\":[\"best quality_proxy 0.93 vs code 0.91 on suite\","
    .ascii "\"tool JSON 96% vs 94% — small but concrete\"],"
    .ascii "\"risks\":[\"cost up on best path\","
    .ascii "\"no train@ — blueprint/config only by default\"]}}"
dry_improve_quality_len = . - dry_improve_quality

dry_improve_speed:
    .ascii "{\"op\":\"improve\",\"prefer\":\"speed\",\"mode\":\"dry-run\","
    .ascii "\"from\":\"report\",\"blueprint\":{"
    .ascii "\"architecture\":\"default fast; escalate to code on tool fail\","
    .ascii "\"suggestion\":\"short max_tokens; disable think for classify\","
    .ascii "\"config\":{\"primary\":\"fast\",\"escalate\":\"code\","
    .ascii "\"train\":false},"
    .ascii "\"metrics_delta\":{\"latency_ms_p50\":\"-325 vs code\","
    .ascii "\"tokens_per_s\":\"+33.8 vs code\","
    .ascii "\"tool_call_json_valid_pct\":\"-23 pts unless escalate\"},"
    .ascii "\"exact_why\":[\"fast latency_ms_p50 95 vs code 420\","
    .ascii "\"must escalate when tool JSON <80%\"],"
    .ascii "\"risks\":[\"quality drop without escalate\","
    .ascii "\"no train@ weights by default\"]}}"
dry_improve_speed_len = . - dry_improve_speed

dry_improve_cost:
    .ascii "{\"op\":\"improve\",\"prefer\":\"cost\",\"mode\":\"dry-run\","
    .ascii "\"from\":\"report\",\"blueprint\":{"
    .ascii "\"architecture\":\"prefer local/fast aliases; cap best\","
    .ascii "\"suggestion\":\"cache classify; batch extract\","
    .ascii "\"config\":{\"primary\":\"fast\",\"local_first\":true,"
    .ascii "\"train\":false},"
    .ascii "\"metrics_delta\":{\"est_cost_per_1k_tok\":\"lower vs best\","
    .ascii "\"quality_proxy\":\"-0.15 vs best if no escalate\"},"
    .ascii "\"exact_why\":[\"fast/local avoids best token $ on suite\","
    .ascii "\"trade: tool JSON 71% vs 96%\"],"
    .ascii "\"risks\":[\"under-quality on hard tools\","
    .ascii "\"no unauthorized train@\"]}}"
dry_improve_cost_len = . - dry_improve_cost

dry_improve_local:
    .ascii "{\"op\":\"improve\",\"prefer\":\"local\",\"mode\":\"dry-run\","
    .ascii "\"from\":\"report\",\"blueprint\":{"
    .ascii "\"architecture\":\"local coder GPU :8003; never voice/:8010\","
    .ascii "\"suggestion\":\"alias local-coder → local coding model\","
    .ascii "\"config\":{\"primary\":\"local:vllm@:8003\","
    .ascii "\"never\":[\":8010\"],\"train\":false},"
    .ascii "\"metrics_delta\":{\"network_rtt\":\"0 vs remote gateway\","
    .ascii "\"quality_proxy\":\"fixture local 0.86\"},"
    .ascii "\"exact_why\":[\"local endpoint discovered listening (fixture)\","
    .ascii "\"voice :8010 listed read-only — not used for Spark improve\"],"
    .ascii "\"risks\":[\"VRAM contention with other local jobs\","
    .ascii "\"weights train ONLY if owner issues train-grant\"]}}"
dry_improve_local_len = . - dry_improve_local

# Optional plan markdown (model plan) — not a train job
blueprint_md:
    .ascii "# Model plan (Spark dry-run)\n\n"
    .ascii "## Exact why\n"
    .ascii "- code wins tool-call JSON validity **94% vs 71%** (fast)\n"
    .ascii "- best quality_proxy **0.93 vs code 0.91** on fixture suite\n"
    .ascii "- Prefer quality → primary `code`, fallback `best`,"
    .ascii " repair_once\n\n"
    .ascii "## Next step\n"
    .ascii "- Use `model train` / `model build` to submit a real job\n"
    .ascii "- This file is a plan only — not weights or adapters\n\n"
    .ascii "## Config sketch\n"
    .ascii "```toml\n"
    .ascii "primary = \"code\"\n"
    .ascii "fallback = \"best\"\n"
    .ascii "repair_once = true\n"
    .ascii "```\n"
blueprint_md_len = . - blueprint_md

default_blueprint_path:
    .ascii "out/better-model.md\0"

# Dry-run train job accept (examples/fixtures/train/accept.json)
dry_train_accept:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    .ascii "\"backend\":\"http\",\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    .ascii "\"base\":\"fixture-base\",\"out\":\"out/train/job-dry-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — no GPU, no network; artifact paths are "
    .ascii "planned stubs\"}"
dry_train_accept_len = . - dry_train_accept

dry_train_status:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_len = . - dry_train_status

train_dir_parent:
    .ascii "out/train\0"
train_dir_job:
    .ascii "out/train/job-dry-001\0"
train_artifact_path:
    .ascii "out/train/job-dry-001/ARTIFACT\0"
train_artifact_body:
    .ascii "spark-train-dry job-dry-001\n"
    .ascii "adapter=out/train/job-dry-001/adapter.bin\n"
    .ascii "checkpoint=out/train/job-dry-001/checkpoint.json\n"
train_artifact_body_len = . - train_artifact_body

msg_train_why:
    .ascii "  (dry-run train — fixtures only; no GPU / no network)\n"
msg_train_why_len = . - msg_train_why

.section .text

# ------------------------------------------------------------
# model_ops_dispatch — called from do_model after "[model] " printed
# ------------------------------------------------------------
model_ops_dispatch:
    push    rbx
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_analyze]
    call    contains
    test    rax, rax
    jnz     model_analyze

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_compare]
    call    contains
    test    rax, rax
    jnz     model_compare

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_improve]
    call    contains
    test    rax, rax
    jnz     model_improve

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_status]
    call    contains
    test    rax, rax
    jnz     model_status

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_plan]
    call    contains
    test    rax, rax
    jnz     model_plan

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_train]
    call    contains
    test    rax, rax
    jnz     model_train

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_build]
    call    contains
    test    rax, rax
    jnz     model_train

    # plain alias: model fast|code|best or use fast — print remainder
    lea     rbx, [rip+linebuf]
    call    skip_ws_local
    mov     rbx, rax
    cmp     byte ptr [rbx], 'u'
    jne     mod_past_model
    cmp     byte ptr [rbx+1], 's'
    jne     mod_past_model
    cmp     byte ptr [rbx+2], 'e'
    jne     mod_past_model
    add     rbx, 3
    jmp     mod_past_kw
mod_past_model:
    add     rbx, 5
mod_past_kw:
    call    skip_ws_from_rbx_local
    mov     rsi, rax
    call    strlen
    mov     rdx, rax
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# --- model analyze ---
model_analyze:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      ma_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
ma_noq:
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_why]
    mov     rdx, msg_model_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    call    pick_analyze_report
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

pick_analyze_report:
    push    rbx
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_all]
    call    contains
    test    rax, rax
    jz      pa_code
    lea     rax, [rip+dry_analyze_all]
    mov     rcx, dry_analyze_all_len
    pop     rbx
    ret
pa_code:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      pa_gen
    # check quote for "fast" or "code" / alias-code
    mov     rbx, rax
    # temporarily null-terminate for contains? contains scans to 0 —
    # quote is mid-line; use linebuf needles instead
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_fast_id]
    call    contains
    test    rax, rax
    jnz     pa_fast
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_code_id]
    call    contains
    test    rax, rax
    jz      pa_gen
    lea     rax, [rip+dry_analyze_code]
    mov     rcx, dry_analyze_code_len
    pop     rbx
    ret
pa_fast:
    lea     rax, [rip+dry_analyze_fast]
    mov     rcx, dry_analyze_fast_len
    pop     rbx
    ret
pa_gen:
    lea     rax, [rip+dry_analyze_generic]
    mov     rcx, dry_analyze_generic_len
    pop     rbx
    ret

# --- model compare ---
model_compare:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      mc_noq
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
mc_noq:
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_why]
    mov     rdx, msg_model_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_compare]
    mov     rdx, dry_compare_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# --- model improve ---
model_improve:
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_why]
    mov     rdx, msg_model_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    call    pick_improve_blueprint
    mov     rsi, rax
    mov     rdx, rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

pick_improve_blueprint:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_speed]
    call    contains
    test    rax, rax
    jz      pi_cost
    lea     rax, [rip+dry_improve_speed]
    mov     rcx, dry_improve_speed_len
    ret
pi_cost:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_cost]
    call    contains
    test    rax, rax
    jz      pi_local
    lea     rax, [rip+dry_improve_cost]
    mov     rcx, dry_improve_cost_len
    ret
pi_local:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_local]
    call    contains
    test    rax, rax
    jz      pi_qual
    lea     rax, [rip+dry_improve_local]
    mov     rcx, dry_improve_local_len
    ret
pi_qual:
    lea     rax, [rip+dry_improve_quality]
    mov     rcx, dry_improve_quality_len
    ret

# --- model train / build (real job; dry = fixtures) ---
model_train:
    cmp     qword ptr [rip+flag_live], 0
    je      mt_dry
    call    train_live_submit
    pop     rbx
    ret
mt_dry:
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_dir_parent]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_dir_job]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_artifact_path]
    lea     rsi, [rip+train_artifact_body]
    mov     rdx, train_artifact_body_len
    call    write_bytes_path
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_train_why]
    mov     rdx, msg_train_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_train_accept]
    mov     rdx, dry_train_accept_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_built]
    mov     rdx, msg_model_built_len
    call    write_stdout
    lea     rsi, [rip+train_artifact_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+train_artifact_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# --- model status ---
model_status:
    cmp     qword ptr [rip+flag_live], 0
    je      ms_dry
    call    train_live_status
    pop     rbx
    ret
ms_dry:
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_train_why]
    mov     rdx, msg_train_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_train_status]
    mov     rdx, dry_train_status_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# --- model plan (markdown only; former blueprint build) ---
model_plan:
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493            # 0755
    call    sys_mkdir
    lea     rdi, [rip+default_blueprint_path]
    lea     rsi, [rip+blueprint_md]
    mov     rdx, blueprint_md_len
    call    write_bytes_path
    lea     rsi, [rip+msg_model_built]
    mov     rdx, msg_model_built_len
    call    write_stdout
    lea     rsi, [rip+default_blueprint_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+default_blueprint_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rbx
    ret

# local skip_ws copies (avoid depending on rbx-calling convention from spark)
skip_ws_local:
    mov     rax, rbx
swl:
    mov     cl, [rax]
    cmp     cl, ' '
    je      swl_adv
    cmp     cl, 9
    je      swl_adv
    ret
swl_adv:
    inc     rax
    jmp     swl

skip_ws_from_rbx_local:
    mov     rax, rbx
    jmp     swl
