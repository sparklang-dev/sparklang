# Spark model analyze / compare / improve / train / step / status / plan
# plus reverse / inspect / compile / modify (lab pipeline).
# Linked with asm/spark.s. Dry-run = fixtures; live forks spark-train-http.
# make test never starts GPU jobs or dials the network.
#
# SPARK_BC match (interpreter, not emit):
#   model train / model build  → TRAIN        0x26
#   model step                 → STEP         0x28
#   model status                → TRAIN_STATUS 0x27
# Same dry JSON shape as bootstrap/dry_train.c. Dry ≠ SGD ≠ trained.
# GAS --run-bc / --compile thin-wrap spark-bootstrap (bc_vm / C
# lowering remain SoT). Dry ≠ SGD ≠ trained.
#
# Exports: model_ops_dispatch
# Imports from spark.s: linebuf, write_stdout, extract_quote, contains,
#   strlen, write_bytes_path, sys_mkdir, msg_nl, msg_reply, outdir_name,
#   flag_live, fork_exec_wait, set_last_from_rcx, bind_arrow_from_line,
#   sys_exit

.intel_syntax noprefix
.global model_ops_dispatch
.extern voice_loop_model_hook

# Match bootstrap/bc_opcodes.h (verbs in GAS; emit BLOCKED).
.set SPBC_OP_TRAIN, 0x26
.set SPBC_OP_TRAIN_STATUS, 0x27
.set SPBC_OP_STEP, 0x28

.section .rodata
# Opcode bytes in the GAS ELF (interpreter ids, not a SPARK_BC stream).
spbc_train_ops:
    .byte SPBC_OP_TRAIN
    .byte SPBC_OP_STEP
    .byte SPBC_OP_TRAIN_STATUS

.extern linebuf
.extern write_stdout
.extern extract_quote
.extern contains
.extern strlen
.extern write_bytes_path
.extern sys_mkdir
.extern sys_exit
.extern outdir_name
.extern flag_live
.extern fork_exec_wait
.extern train_live_submit
.extern train_live_status
.extern set_last_from_rcx
.extern bind_arrow_from_line

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
needle_step:    .ascii "step\0"
needle_status:  .ascii "status\0"
needle_plan:    .ascii "plan\0"
needle_reverse: .ascii "reverse\0"
needle_inspect: .ascii "inspect\0"
needle_compile: .ascii "compile\0"
needle_modify:  .ascii "modify\0"
needle_quality: .ascii "quality\0"
needle_speed:   .ascii "speed\0"
needle_cost:    .ascii "cost\0"
needle_local:   .ascii "local\0"
needle_all:     .ascii "all\0"
needle_fast_id: .ascii "fast\0"
needle_code_id: .ascii "code\0"
needle_meth_kw: .ascii "method \"\0"
needle_meth_dist: .ascii "spark_distill_cpu\0"
needle_meth_pref: .ascii "spark_pref_pack\0"
needle_meth_play: .ascii "spark_playbook_fit\0"
needle_meth_faq:  .ascii "spark_faq_index\0"
needle_meth_reply:.ascii "spark_reply_pack\0"
needle_job_dry:   .ascii "job-dry-001\0"
needle_job_pref:  .ascii "job-pref-001\0"
needle_job_play:  .ascii "job-play-001\0"
needle_job_faq:   .ascii "job-faq-001\0"
needle_job_reply: .ascii "job-reply-001\0"

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

# Dry TRAIN 0x26 / TRAIN_STATUS 0x27 — match bootstrap/dry_train.c
# (method + job_id). Not SGD. Not a trained model.
dry_train_accept:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    .ascii "\"backend\":\"http\",\"method\":\"spark_distill_cpu\","
    .ascii "\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    .ascii "\"base\":\"fixture-base\",\"out\":\"out/train/job-dry-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — method planned; no train on this host\"}"
dry_train_accept_len = . - dry_train_accept

dry_train_accept_pref:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-pref-001\","
    .ascii "\"backend\":\"http\",\"method\":\"spark_pref_pack\","
    .ascii "\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    .ascii "\"base\":\"spark_pref_pack\",\"out\":\"out/train/job-pref-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-pref-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-pref-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-pref-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — method planned; no train on this host\"}"
dry_train_accept_pref_len = . - dry_train_accept_pref

dry_train_accept_play:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-play-001\","
    .ascii "\"backend\":\"http\",\"method\":\"spark_playbook_fit\","
    .ascii "\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    .ascii "\"base\":\"spark_playbook_fit\",\"out\":\"out/train/job-play-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-play-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-play-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-play-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — method planned; no train on this host\"}"
dry_train_accept_play_len = . - dry_train_accept_play

dry_train_accept_faq:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-faq-001\","
    .ascii "\"backend\":\"http\",\"method\":\"spark_faq_index\","
    .ascii "\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/dataset.jsonl\","
    .ascii "\"base\":\"spark_faq_index\",\"out\":\"out/train/job-faq-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-faq-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-faq-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-faq-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — method planned; no train on this host\"}"
dry_train_accept_faq_len = . - dry_train_accept_faq

dry_train_accept_reply:
    .ascii "{\"op\":\"train\",\"mode\":\"dry-run\",\"job_id\":\"job-reply-001\","
    .ascii "\"backend\":\"http\",\"method\":\"spark_reply_pack\","
    .ascii "\"status\":\"accepted\","
    .ascii "\"dataset\":\"examples/fixtures/train/reply_pack.jsonl\","
    .ascii "\"base\":\"spark_reply_pack\",\"out\":\"out/train/job-reply-001\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-reply-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-reply-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-reply-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run — method planned; no train on this host\"}"
dry_train_accept_reply_len = . - dry_train_accept_reply

dry_train_status:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-dry-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-dry-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_len = . - dry_train_status

dry_train_status_pref:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-pref-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-pref-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-pref-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-pref-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_pref_len = . - dry_train_status_pref

dry_train_status_play:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-play-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-play-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-play-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-play-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_play_len = . - dry_train_status_play

dry_train_status_faq:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-faq-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-faq-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-faq-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-faq-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_faq_len = . - dry_train_status_faq

dry_train_status_reply:
    .ascii "{\"op\":\"status\",\"mode\":\"dry-run\",\"job_id\":\"job-reply-001\","
    .ascii "\"state\":\"succeeded\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"adapter\":\"out/train/job-reply-001/adapter.bin\","
    .ascii "\"checkpoint\":\"out/train/job-reply-001/checkpoint.json\","
    .ascii "\"marker\":\"out/train/job-reply-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run fixture — weights not trained on this host\"}"
dry_train_status_reply_len = . - dry_train_status_reply

# Dry STEP 0x28 — match bootstrap/dry_train.c spark_pick_train_step.
# step_n=1. Not SGD. Not a trained model.
dry_train_step:
    .ascii "{\"op\":\"step\",\"mode\":\"dry-run\",\"job_id\":\"job-dry-001\","
    .ascii "\"step\":1,\"state\":\"stepped\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"marker\":\"out/train/job-dry-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run STEP — not SGD; not trained\"}"
dry_train_step_len = . - dry_train_step

dry_train_step_pref:
    .ascii "{\"op\":\"step\",\"mode\":\"dry-run\",\"job_id\":\"job-pref-001\","
    .ascii "\"step\":1,\"state\":\"stepped\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"marker\":\"out/train/job-pref-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run STEP — not SGD; not trained\"}"
dry_train_step_pref_len = . - dry_train_step_pref

dry_train_step_play:
    .ascii "{\"op\":\"step\",\"mode\":\"dry-run\",\"job_id\":\"job-play-001\","
    .ascii "\"step\":1,\"state\":\"stepped\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"marker\":\"out/train/job-play-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run STEP — not SGD; not trained\"}"
dry_train_step_play_len = . - dry_train_step_play

dry_train_step_faq:
    .ascii "{\"op\":\"step\",\"mode\":\"dry-run\",\"job_id\":\"job-faq-001\","
    .ascii "\"step\":1,\"state\":\"stepped\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"marker\":\"out/train/job-faq-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run STEP — not SGD; not trained\"}"
dry_train_step_faq_len = . - dry_train_step_faq

dry_train_step_reply:
    .ascii "{\"op\":\"step\",\"mode\":\"dry-run\",\"job_id\":\"job-reply-001\","
    .ascii "\"step\":1,\"state\":\"stepped\",\"backend\":\"http\","
    .ascii "\"artifacts\":{"
    .ascii "\"marker\":\"out/train/job-reply-001/ARTIFACT\"},"
    .ascii "\"note\":\"dry-run STEP — not SGD; not trained\"}"
dry_train_step_reply_len = . - dry_train_step_reply

train_dir_parent:
    .ascii "out/train\0"
train_dir_dry:
    .ascii "out/train/job-dry-001\0"
train_dir_pref:
    .ascii "out/train/job-pref-001\0"
train_dir_play:
    .ascii "out/train/job-play-001\0"
train_dir_faq:
    .ascii "out/train/job-faq-001\0"
train_dir_reply:
    .ascii "out/train/job-reply-001\0"
train_artifact_path:
    .ascii "out/train/job-dry-001/ARTIFACT\0"
train_art_pref:
    .ascii "out/train/job-pref-001/ARTIFACT\0"
train_art_play:
    .ascii "out/train/job-play-001/ARTIFACT\0"
train_art_faq:
    .ascii "out/train/job-faq-001/ARTIFACT\0"
train_art_reply:
    .ascii "out/train/job-reply-001/ARTIFACT\0"
train_artifact_body:
    .ascii "spark-train-dry\n"
    .ascii "note=dry-run fixture — not SGD, not trained\n"
train_artifact_body_len = . - train_artifact_body

# ARTIFACT after STEP — match spark_bump_train_step (step_n, not SGD).
step_artifact_dry:
    .ascii "spark-train-dry job-dry-001\n"
    .ascii "mode=dry-run-fixture\n"
    .ascii "not_sgd=true\n"
    .ascii "trained=false\n"
    .ascii "step_n=1\n"
    .ascii "op=step\n"
    .ascii "note=dry STEP -- not SGD; not a trained model\n"
step_artifact_dry_len = . - step_artifact_dry

step_artifact_pref:
    .ascii "spark-train-dry job-pref-001\n"
    .ascii "mode=dry-run-fixture\n"
    .ascii "not_sgd=true\n"
    .ascii "trained=false\n"
    .ascii "step_n=1\n"
    .ascii "op=step\n"
    .ascii "note=dry STEP -- not SGD; not a trained model\n"
step_artifact_pref_len = . - step_artifact_pref

step_artifact_play:
    .ascii "spark-train-dry job-play-001\n"
    .ascii "mode=dry-run-fixture\n"
    .ascii "not_sgd=true\n"
    .ascii "trained=false\n"
    .ascii "step_n=1\n"
    .ascii "op=step\n"
    .ascii "note=dry STEP -- not SGD; not a trained model\n"
step_artifact_play_len = . - step_artifact_play

step_artifact_faq:
    .ascii "spark-train-dry job-faq-001\n"
    .ascii "mode=dry-run-fixture\n"
    .ascii "not_sgd=true\n"
    .ascii "trained=false\n"
    .ascii "step_n=1\n"
    .ascii "op=step\n"
    .ascii "note=dry STEP -- not SGD; not a trained model\n"
step_artifact_faq_len = . - step_artifact_faq

step_artifact_reply:
    .ascii "spark-train-dry job-reply-001\n"
    .ascii "mode=dry-run-fixture\n"
    .ascii "not_sgd=true\n"
    .ascii "trained=false\n"
    .ascii "step_n=1\n"
    .ascii "op=step\n"
    .ascii "note=dry STEP -- not SGD; not a trained model\n"
step_artifact_reply_len = . - step_artifact_reply

msg_train_why:
    .ascii "  (dry-run TRAIN 0x26 — fixture JSON; not SGD / not trained)\n"
msg_train_why_len = . - msg_train_why
msg_step_why:
    .ascii "  (dry-run STEP 0x28 — ARTIFACT step_n; not SGD / not trained)\n"
msg_step_why_len = . - msg_step_why
msg_status_why:
    .ascii "  (dry-run TRAIN_STATUS 0x27 — fixture; weights not trained)\n"
msg_status_why_len = . - msg_status_why
msg_train_miss:
    .ascii "error: train fixture miss (unknown method — not SGD)\n"
msg_train_miss_len = . - msg_train_miss
msg_step_miss:
    .ascii "error: train step fixture miss (unknown job id)\n"
msg_step_miss_len = . - msg_step_miss
msg_step_live:
    .ascii "error: model step live not implemented (dry-run only)\n"
msg_step_live_len = . - msg_step_live
msg_status_miss:
    .ascii "error: train status fixture miss (unknown job id)\n"
msg_status_miss_len = . - msg_status_miss

msg_lab_why:
    .ascii "  (dry-run lab — inspect/compile/modify fixtures; no GPU)\n"
msg_lab_why_len = . - msg_lab_why

# Reverse-engineer published architecture (local config / index only)
dry_reverse:
    .ascii "{\"op\":\"reverse\",\"mode\":\"dry-run\",\"target\":\"fixtures/tiny-lm\","
    .ascii "\"architecture\":\"Qwen3ForCausalLM\",\"hidden_size\":64,"
    .ascii "\"num_hidden_layers\":2,\"num_attention_heads\":4,"
    .ascii "\"vocab_size\":256,\"model_type\":\"qwen3\","
    .ascii "\"tensors\":[\"model.embed_tokens.weight\",\"lm_head.weight\"],"
    .ascii "\"source\":\"examples/fixtures/models/tiny-lm/config.json\","
    .ascii "\"keep_special_training\":true,"
    .ascii "\"note\":\"inspect local published config/index only — "
    .ascii "not closed weights, not a new foundation LLM\"}"
dry_reverse_len = . - dry_reverse

dry_compile:
    .ascii "{\"op\":\"compile\",\"mode\":\"dry-run\","
    .ascii "\"src\":\"examples/model_lab.spark\","
    .ascii "\"out\":\"out/lab/model_lab.sparkbc\",\"format\":\"sparkbc\","
    .ascii "\"note\":\"dry plan — real bytes via spark-bootstrap --compile\"}"
dry_compile_len = . - dry_compile

dry_modify:
    .ascii "{\"op\":\"modify\",\"mode\":\"dry-run\",\"keep_existing\":true,"
    .ascii "\"existing\":[\"out/train/existing-lora\"],"
    .ascii "\"add\":\"out/train/job-dry-001/adapter.bin\","
    .ascii "\"head\":\"out/heads/abstain.pt\","
    .ascii "\"keep_special_training\":true,"
    .ascii "\"note\":\"attach only — never delete special training\"}"
dry_modify_len = . - dry_modify

lab_dir:
    .ascii "out/lab\0"
compile_out_path:
    .ascii "out/lab/model_lab.sparkbc\0"
compile_artifact_body:
    .ascii "spark-compile-dry SPARK_BC plan\n"
    .ascii "src=examples/model_lab.spark\n"
    .ascii "format=sparkbc\n"
compile_artifact_body_len = . - compile_artifact_body
modify_artifact_path:
    .ascii "out/lab/MODIFY\0"
modify_artifact_body:
    .ascii "spark-modify-dry keep_existing=true\n"
    .ascii "existing=out/train/existing-lora\n"
    .ascii "add=out/train/job-dry-001/adapter.bin\n"
    .ascii "head=out/heads/abstain.pt\n"
modify_artifact_body_len = . - modify_artifact_body

.section .text

# ------------------------------------------------------------
# model_ops_dispatch — called from do_model after "[model] " printed
# ------------------------------------------------------------
model_ops_dispatch:
    push    rbx
    # voice-loop: model pairs | model serve helper
    call    voice_loop_model_hook
    test    rax, rax
    jz      mod_after_vl
    pop     rbx
    ret
mod_after_vl:
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
    lea     rsi, [rip+needle_step]
    call    contains
    test    rax, rax
    jnz     model_step

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_plan]
    call    contains
    test    rax, rax
    jnz     model_plan

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_reverse]
    call    contains
    test    rax, rax
    jnz     model_reverse

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_inspect]
    call    contains
    test    rax, rax
    jnz     model_reverse

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_compile]
    call    contains
    test    rax, rax
    jnz     model_compile

    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_modify]
    call    contains
    test    rax, rax
    jnz     model_modify

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
    # Bind -> name so expect / print can read the JSON.
    lea     rax, [rip+dry_compare]
    mov     rcx, dry_compare_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
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

# pick_train_accept: rax=json rcx=len. Unknown method → rax=0.
pick_train_accept:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_kw]
    call    contains
    test    rax, rax
    jz      pta_dist
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_reply]
    call    contains
    test    rax, rax
    jnz     pta_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_pref]
    call    contains
    test    rax, rax
    jnz     pta_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_play]
    call    contains
    test    rax, rax
    jnz     pta_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_faq]
    call    contains
    test    rax, rax
    jnz     pta_faq
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_dist]
    call    contains
    test    rax, rax
    jnz     pta_dist
    xor     rax, rax
    xor     rcx, rcx
    ret
pta_reply:
    lea     rax, [rip+dry_train_accept_reply]
    mov     rcx, dry_train_accept_reply_len
    ret
pta_pref:
    lea     rax, [rip+dry_train_accept_pref]
    mov     rcx, dry_train_accept_pref_len
    ret
pta_play:
    lea     rax, [rip+dry_train_accept_play]
    mov     rcx, dry_train_accept_play_len
    ret
pta_faq:
    lea     rax, [rip+dry_train_accept_faq]
    mov     rcx, dry_train_accept_faq_len
    ret
pta_dist:
    lea     rax, [rip+dry_train_accept]
    mov     rcx, dry_train_accept_len
    ret

# pick_train_jobdir / art: rax=NUL path (same method needles)
pick_train_jobdir:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_reply]
    call    contains
    test    rax, rax
    jnz     ptj_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_pref]
    call    contains
    test    rax, rax
    jnz     ptj_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_play]
    call    contains
    test    rax, rax
    jnz     ptj_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_faq]
    call    contains
    test    rax, rax
    jnz     ptj_faq
    lea     rax, [rip+train_dir_dry]
    ret
ptj_reply:
    lea     rax, [rip+train_dir_reply]
    ret
ptj_pref:
    lea     rax, [rip+train_dir_pref]
    ret
ptj_play:
    lea     rax, [rip+train_dir_play]
    ret
ptj_faq:
    lea     rax, [rip+train_dir_faq]
    ret

pick_train_art:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_reply]
    call    contains
    test    rax, rax
    jnz     pta2_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_pref]
    call    contains
    test    rax, rax
    jnz     pta2_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_play]
    call    contains
    test    rax, rax
    jnz     pta2_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_meth_faq]
    call    contains
    test    rax, rax
    jnz     pta2_faq
    lea     rax, [rip+train_artifact_path]
    ret
pta2_reply:
    lea     rax, [rip+train_art_reply]
    ret
pta2_pref:
    lea     rax, [rip+train_art_pref]
    ret
pta2_play:
    lea     rax, [rip+train_art_play]
    ret
pta2_faq:
    lea     rax, [rip+train_art_faq]
    ret

# pick_train_status: rax=json rcx=len. Quoted unknown job → rax=0.
pick_train_status:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      pts_dry
    test    rcx, rcx
    jz      pts_dry
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_reply]
    call    contains
    test    rax, rax
    jnz     pts_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_pref]
    call    contains
    test    rax, rax
    jnz     pts_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_play]
    call    contains
    test    rax, rax
    jnz     pts_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_faq]
    call    contains
    test    rax, rax
    jnz     pts_faq
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_dry]
    call    contains
    test    rax, rax
    jnz     pts_dry
    xor     rax, rax
    xor     rcx, rcx
    ret
pts_reply:
    lea     rax, [rip+dry_train_status_reply]
    mov     rcx, dry_train_status_reply_len
    ret
pts_pref:
    lea     rax, [rip+dry_train_status_pref]
    mov     rcx, dry_train_status_pref_len
    ret
pts_play:
    lea     rax, [rip+dry_train_status_play]
    mov     rcx, dry_train_status_play_len
    ret
pts_faq:
    lea     rax, [rip+dry_train_status_faq]
    mov     rcx, dry_train_status_faq_len
    ret
pts_dry:
    lea     rax, [rip+dry_train_status]
    mov     rcx, dry_train_status_len
    ret

# pick_train_step: rax=json rcx=len. Quoted unknown job → rax=0.
pick_train_step:
    lea     rdi, [rip+linebuf]
    call    extract_quote
    test    rax, rax
    jz      pst_dry
    test    rcx, rcx
    jz      pst_dry
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_reply]
    call    contains
    test    rax, rax
    jnz     pst_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_pref]
    call    contains
    test    rax, rax
    jnz     pst_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_play]
    call    contains
    test    rax, rax
    jnz     pst_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_faq]
    call    contains
    test    rax, rax
    jnz     pst_faq
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_dry]
    call    contains
    test    rax, rax
    jnz     pst_dry
    xor     rax, rax
    xor     rcx, rcx
    ret
pst_reply:
    lea     rax, [rip+dry_train_step_reply]
    mov     rcx, dry_train_step_reply_len
    ret
pst_pref:
    lea     rax, [rip+dry_train_step_pref]
    mov     rcx, dry_train_step_pref_len
    ret
pst_play:
    lea     rax, [rip+dry_train_step_play]
    mov     rcx, dry_train_step_play_len
    ret
pst_faq:
    lea     rax, [rip+dry_train_step_faq]
    mov     rcx, dry_train_step_faq_len
    ret
pst_dry:
    lea     rax, [rip+dry_train_step]
    mov     rcx, dry_train_step_len
    ret

# pick_step_body: rax=body rcx=len (ARTIFACT bump text).
pick_step_body:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_reply]
    call    contains
    test    rax, rax
    jnz     psb_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_pref]
    call    contains
    test    rax, rax
    jnz     psb_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_play]
    call    contains
    test    rax, rax
    jnz     psb_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_faq]
    call    contains
    test    rax, rax
    jnz     psb_faq
    lea     rax, [rip+step_artifact_dry]
    mov     rcx, step_artifact_dry_len
    ret
psb_reply:
    lea     rax, [rip+step_artifact_reply]
    mov     rcx, step_artifact_reply_len
    ret
psb_pref:
    lea     rax, [rip+step_artifact_pref]
    mov     rcx, step_artifact_pref_len
    ret
psb_play:
    lea     rax, [rip+step_artifact_play]
    mov     rcx, step_artifact_play_len
    ret
psb_faq:
    lea     rax, [rip+step_artifact_faq]
    mov     rcx, step_artifact_faq_len
    ret

# pick_step_art / pick_step_jobdir: job id from line (not method).
pick_step_jobdir:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_reply]
    call    contains
    test    rax, rax
    jnz     psj_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_pref]
    call    contains
    test    rax, rax
    jnz     psj_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_play]
    call    contains
    test    rax, rax
    jnz     psj_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_faq]
    call    contains
    test    rax, rax
    jnz     psj_faq
    lea     rax, [rip+train_dir_dry]
    ret
psj_reply:
    lea     rax, [rip+train_dir_reply]
    ret
psj_pref:
    lea     rax, [rip+train_dir_pref]
    ret
psj_play:
    lea     rax, [rip+train_dir_play]
    ret
psj_faq:
    lea     rax, [rip+train_dir_faq]
    ret

pick_step_art:
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_reply]
    call    contains
    test    rax, rax
    jnz     psa_reply
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_pref]
    call    contains
    test    rax, rax
    jnz     psa_pref
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_play]
    call    contains
    test    rax, rax
    jnz     psa_play
    lea     rdi, [rip+linebuf]
    lea     rsi, [rip+needle_job_faq]
    call    contains
    test    rax, rax
    jnz     psa_faq
    lea     rax, [rip+train_artifact_path]
    ret
psa_reply:
    lea     rax, [rip+train_art_reply]
    ret
psa_pref:
    lea     rax, [rip+train_art_pref]
    ret
psa_play:
    lea     rax, [rip+train_art_play]
    ret
psa_faq:
    lea     rax, [rip+train_art_faq]
    ret

# --- model train / build (TRAIN 0x26; dry = fixtures, not SGD) ---
model_train:
    cmp     qword ptr [rip+flag_live], 0
    je      mt_dry
    call    train_live_submit
    pop     rbx
    ret
mt_dry:
    call    pick_train_accept
    test    rax, rax
    jnz     mt_ok
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_train_miss]
    mov     rdx, msg_train_miss_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
mt_ok:
    push    rax
    push    rcx
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_dir_parent]
    mov     rsi, 493
    call    sys_mkdir
    call    pick_train_jobdir
    mov     rdi, rax
    mov     rsi, 493
    call    sys_mkdir
    call    pick_train_art
    mov     rdi, rax
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
    pop     rcx
    pop     rax
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_built]
    mov     rdx, msg_model_built_len
    call    write_stdout
    call    pick_train_art
    mov     rsi, rax
    call    strlen
    mov     rdx, rax
    call    pick_train_art
    mov     rsi, rax
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

# --- model step (STEP 0x28; dry ARTIFACT step_n, not SGD) ---
model_step:
    cmp     qword ptr [rip+flag_live], 0
    je      mst_dry
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_step_live]
    mov     rdx, msg_step_live_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
mst_dry:
    call    pick_train_step
    test    rax, rax
    jnz     mst_ok
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_step_miss]
    mov     rdx, msg_step_miss_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
mst_ok:
    push    rax
    push    rcx
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+train_dir_parent]
    mov     rsi, 493
    call    sys_mkdir
    call    pick_step_jobdir
    mov     rdi, rax
    mov     rsi, 493
    call    sys_mkdir
    call    pick_step_art
    push    rax
    call    pick_step_body
    mov     rsi, rax
    mov     rdx, rcx
    pop     rdi
    call    write_bytes_path
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_step_why]
    mov     rdx, msg_step_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    pop     rcx
    pop     rax
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

# --- model status (TRAIN_STATUS 0x27) ---
model_status:
    cmp     qword ptr [rip+flag_live], 0
    je      ms_dry
    call    train_live_status
    pop     rbx
    ret
ms_dry:
    call    pick_train_status
    test    rax, rax
    jnz     ms_ok
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_status_miss]
    mov     rdx, msg_status_miss_len
    call    write_stdout
    mov     rdi, 1
    call    sys_exit
ms_ok:
    push    rax
    push    rcx
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_status_why]
    mov     rdx, msg_status_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    pop     rcx
    pop     rax
    mov     rsi, rax
    mov     rdx, rcx
    push    rax
    push    rcx
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    pop     rcx
    pop     rax
    call    set_last_from_rcx
    call    bind_arrow_from_line
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

# --- model reverse / inspect (published architecture only) ---
model_reverse:
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_lab_why]
    mov     rdx, msg_lab_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_reverse]
    mov     rdx, dry_reverse_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+dry_reverse]
    mov     rcx, dry_reverse_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

# --- model compile (.spark → SPARK_BC plan; dry = fixture) ---
model_compile:
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+lab_dir]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+compile_out_path]
    lea     rsi, [rip+compile_artifact_body]
    mov     rdx, compile_artifact_body_len
    call    write_bytes_path
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_lab_why]
    mov     rdx, msg_lab_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_compile]
    mov     rdx, dry_compile_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_built]
    mov     rdx, msg_model_built_len
    call    write_stdout
    lea     rsi, [rip+compile_out_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+compile_out_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+dry_compile]
    mov     rcx, dry_compile_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
    pop     rbx
    ret

# --- model modify (attach; keep existing special training) ---
model_modify:
    lea     rdi, [rip+outdir_name]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+lab_dir]
    mov     rsi, 493
    call    sys_mkdir
    lea     rdi, [rip+modify_artifact_path]
    lea     rsi, [rip+modify_artifact_body]
    mov     rdx, modify_artifact_body_len
    call    write_bytes_path
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_lab_why]
    mov     rdx, msg_lab_why_len
    call    write_stdout
    lea     rsi, [rip+msg_reply_local]
    mov     rdx, msg_reply_local_len
    call    write_stdout
    lea     rsi, [rip+dry_modify]
    mov     rdx, dry_modify_len
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rsi, [rip+msg_model_built]
    mov     rdx, msg_model_built_len
    call    write_stdout
    lea     rsi, [rip+modify_artifact_path]
    call    strlen
    mov     rdx, rax
    lea     rsi, [rip+modify_artifact_path]
    call    write_stdout
    lea     rsi, [rip+msg_nl_local]
    mov     rdx, 1
    call    write_stdout
    lea     rax, [rip+dry_modify]
    mov     rcx, dry_modify_len
    call    set_last_from_rcx
    call    bind_arrow_from_line
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
