# Spark — build assembly → machine code (x86_64 Linux)
AS      ?= as
LD      ?= ld
ASFLAGS ?= --64
LDFLAGS ?=
OBJDUMP ?= objdump
CC      ?= cc
CUDA_INC ?= /usr/local/cuda-12.8/include
NVML_LIB ?= /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1

.PHONY: all clean test test-hdl test-e2e-browser test-examples machine-proof \
	examples-run corpus corpus-agg spark-cuda spark-net spark-binary \
	spark-lift spark-section-dump companions browser-scaffold \
	test-model-lab spark-model-lab spark-serve spark-serve-api \
	test-serve-api test-bpe-seed \
	browser-mitm-analyze ide test-engine-paint test-engine-css \
	test-engine-layout test-ide-paint spark-bootstrap sparkc \
	test-bootstrap test-sparkbc test-sparkbc-e2e sparkbc-e2e \
	spark-bc spark-bc-pack-hello sparkasm \
	test-sparkasm test-sparkasm-control docs-docx function-catalog \
	playbooks-catalog spark-eval spark-eval-claude test-spark-eval \
	spark-sgd-proof spark-sgd-proof-scale docs-html docs-check \
	sdk-pack dist test-sdk-pack spark-bc-gui \
	helpers tools-test test-senses \
	spark-coder-train spark-coder-train-large test-spark-coder \
	weight-gallery \
	weight-gallery-xl \
	test-weights-play \
	test-spark-ask \
	test-spark-analyze \
	voice-easy test-voice-easy voice-easy-large

all: spark companions

# Open Spark IDE (Cursor + Bifrost workspace). Not an ELF subcommand.
ide:
	./tools/open-spark-ide.sh

# Graphical Spark IDE (browse/compile/ask/weights; needs a display).
spark-bc-gui: spark-bootstrap
	PYTHONPATH=tools:python ./tools/spark_bc_gui/launch.sh

# Downloadable runtime + SDK + IDE + GUI pack (out/sdk-pack/).
# K-lane overlay: also stage dist/spark-sdk/ helpers/shadows/kit.
sdk-pack: spark-bootstrap helpers
	bash ./tools/package_sdk_ide.sh
	bash ./tools/package_helpers_k.sh

dist: sdk-pack

# Headless pack manifest + GUI core smoke (no display required).
test-sdk-pack: spark-bootstrap
	PYTHONPATH=tools:python python3 \
		tools/spark_bc_gui/test_gui_pack.py -v

# Professional .docx from on-disk markdown (pandoc + reference.docx).
# No invented content — TOC/headers/ops-index from existing MD only.
docs-docx:
	python3 tools/docs_docx.py --rebuild-reference

.PHONY: docs-html docs-check sync-nav test-senses helpers tools-test
docs-html:
	python3 tools/md_to_doc_html.py --all-stale
	python3 tools/sync_site_nav.py
	mkdir -p website/docs/images
	cp -a docs/images/. website/docs/images/

docs-check: docs-html
	python3 tools/md_to_doc_html.py --check
	python3 tools/sync_site_nav.py --check
	PYTHONPATH=python python3 -m unittest \
		tools.test_docs_nav -v

sync-nav:
	python3 tools/sync_site_nav.py

test-senses:
	PYTHONPATH=python python3 -m unittest \
		sparklang.senses.test_senses -v

# K-lane: helpers, shadows, spark_kit (enhances I-lane minimal helpers).
helpers:
	chmod +x helpers/spark-* spark-ask spark-speak-ask \
	  tools/package_helpers_k.sh
	@echo "helpers:"
	@ls -1 helpers/spark-*
	@echo "ask: ./spark-ask  ./spark-speak-ask  (VOICE_ASK.md)"
	@echo "shadows: see shadows/README.md (build/shadow/)"
	@echo "kit: tools/spark_kit/  module: tools/spark_shadow/"

tools-test: helpers
	PYTHONPATH=python:tools python3 -m unittest \
		spark_kit.test_kit spark_analyze.test_analyze -v

test-spark-analyze: helpers
	PYTHONPATH=python:tools python3 -m unittest \
		spark_analyze.test_analyze -v

.PHONY: test-spark-ask
test-spark-ask: helpers
	PYTHONPATH=python:tools python3 -m unittest \
		tools.spark_ask.test_voice_ask -v



function-catalog:
	python3 tools/gen_function_catalog.py

.PHONY: playbooks-catalog
playbooks-catalog:
	python3 tools/gen_playbooks_catalog.py

SPARK_OBJS = asm/spark.o asm/model_ops.o asm/train_ops.o asm/binary_ops.o \
	asm/network_ops.o asm/os_ops.o asm/bind_ops.o asm/cuda_ops.o \
	asm/ask_ops.o asm/rag_ops.o asm/http_ops.o asm/extract_ops.o \
	asm/expect_ops.o asm/abstain_ops.o asm/shell_ops.o \
	asm/browser_ops.o \
	asm/voice_ops.o asm/pcie_ops.o \
	asm/crypto_ops.o asm/gateway_ops.o asm/engine_js.o asm/engine_html.o \
	asm/engine_window.o asm/engine_paint.o asm/engine_paint_ops.o \
	asm/engine_css.o asm/engine_fetch.o asm/engine_layout.o \
	asm/engine_pipeline.o \
	asm/ide_ops.o asm/ide_keys.o asm/ide_paint.o



spark: $(SPARK_OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

asm/spark.o: asm/spark.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/binary_ops.o: asm/binary_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

# Engine B HTML fetch (file:// + http asm + https OpenSSL BIO companion)
asm/engine_fetch.o: asm/engine_fetch.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/network_ops.o: asm/network_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/os_ops.o: asm/os_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/bind_ops.o: asm/bind_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/cuda_ops.o: asm/cuda_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/pcie_ops.o: asm/pcie_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/crypto_ops.o: asm/crypto_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/gateway_ops.o: asm/gateway_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/ask_ops.o: asm/ask_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/rag_ops.o: asm/rag_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/http_ops.o: asm/http_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/extract_ops.o: asm/extract_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/expect_ops.o: asm/expect_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/abstain_ops.o: asm/abstain_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/shell_ops.o: asm/shell_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/browser_ops.o: asm/browser_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_html.o: asm/engine_html.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_css.o: asm/engine_css.s asm/engine_style.inc
	$(AS) $(ASFLAGS) -o $@ $<


asm/engine_window.o: asm/engine_window.s
	$(AS) $(ASFLAGS) -o $@ $<


asm/engine_paint.o: asm/engine_paint.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_paint_main.o: asm/engine_paint_main.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_paint_ops.o: asm/engine_paint_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_layout.o: asm/engine_layout.s asm/engine_style.inc
	$(AS) $(ASFLAGS) -I. -o $@ $<

asm/engine_layout_test.o: asm/engine_layout_test.s
	$(AS) $(ASFLAGS) -o $@ $<

spark-engine-layout-test: asm/engine_layout.o asm/engine_layout_test.o
	$(LD) $(LDFLAGS) -o $@ $^

.PHONY: test-engine-layout test-engine-pipeline-table test-engine-fetch-parse-layout
test-engine-layout: spark-engine-layout-test
	chmod +x engine/tests/test_layout_boxes.sh
	./engine/tests/test_layout_boxes.sh

test-engine-pipeline-table: spark spark-engine-layout-test
	chmod +x engine/tests/test_pipeline_table.sh
	./engine/tests/test_pipeline_table.sh

test-engine-fetch-parse-layout: spark
	chmod +x engine/tests/test_fetch_parse_layout.sh
	./engine/tests/test_fetch_parse_layout.sh


asm/engine_pipeline.o: asm/engine_pipeline.s
	$(AS) $(ASFLAGS) -o $@ $<

# IDE core — buffer open/save/run (asm); no Electron/Qt product
asm/ide_ops.o: asm/ide_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

# IDE keymap / command loop (quit|save|run|open from script)
asm/ide_keys.o: asm/ide_keys.s
	$(AS) $(ASFLAGS) -o $@ $<

# Software paint fixture ELF (rects + glyphs → PPM). No Qt.
spark-engine-paint: asm/engine_paint.o asm/engine_paint_main.o
	$(LD) $(LDFLAGS) -o $@ $^

test-engine-paint: spark-engine-paint
	./engine/tests/test_paint.sh

asm/ide_paint.o: asm/ide_paint.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/ide_paint_main.o: asm/ide_paint_main.s
	$(AS) $(ASFLAGS) -o $@ $<

# IDE editor presentation ELF (gutter + glyphs + cursor → PPM).
spark-ide-paint: asm/ide_paint.o asm/ide_paint_main.o asm/engine_paint.o
	$(LD) $(LDFLAGS) -o $@ $^

test-ide-paint: spark-ide-paint
	./engine/tests/test_ide_paint.sh

.PHONY: test-engine-css
test-engine-css: spark
	chmod +x engine/tests/test_css.sh
	./engine/tests/test_css.sh

asm/voice_ops.o: asm/voice_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/model_ops.o: asm/model_ops.s
	$(AS) $(ASFLAGS) -o $@ $<

asm/engine_js.o: asm/engine_js.s
	$(AS) $(ASFLAGS) -o $@ $<

companions: spark-cuda-probe spark-net-capture \
	spark-binary-probe spark-section-dump spark-lift spark-ask-http \
	spark-ask-probe spark-rag-http spark-http spark-extract spark-expect \
	spark-train-http spark-abstain spark-ground spark-model-lab spark-serve \
	spark-serve-api spark-shell \
	spark-browser-host spark-mitm-quic \
	spark-mitm-quic-divert spark-mitm-ca spark-mitm-h2 spark-browser-cdp spark-pstn-dial \
	spark-enc-gateway spark-stt-tts spark-review-url spark-engine-show \
	spark-engine-paint spark-ide-paint spark-engine-fetch-tls

spark-cuda: spark-cuda-probe
spark-cuda-probe: tools/cuda/spark_cuda_probe.c
	$(CC) -O2 -Wall -Wextra -o $@ $< -I$(CUDA_INC) $(NVML_LIB)

spark-net: spark-net-capture
spark-net-capture: tools/network/spark_net_capture.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

spark-binary: spark-binary-probe spark-section-dump spark-lift

spark-binary-probe: tools/binary/spark_binary_probe.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

spark-section-dump: tools/binary/spark_section_dump.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

spark-lift: tools/binary/spark_lift.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

# Live OpenAI-compatible ask (AI_GATEWAY_URL).
# Offline dry gate: make test-ask-gateway (no network).
spark-ask-http: tools/ask/spark_ask_http.c bootstrap/ground_or_idk.c \
	bootstrap/ground_or_idk.h
	$(CC) -O2 -Wall -Wextra -I. -o $@ tools/ask/spark_ask_http.c \
		bootstrap/ground_or_idk.c

# Gated argv exec for language shell/run (allowlist; never system()).
spark-shell: tools/shell/spark_shell.c
	$(CC) -O2 -Wall -Wextra -o $@ tools/shell/spark_shell.c

# Embed (Bifrost /v1/embeddings) + retrieve (rag-gateway /v1/retrieve).
spark-rag-http: tools/rag/spark_rag_http.c bootstrap/dry_rag.c \
	bootstrap/dry_rag.h
	$(CC) -O2 -Wall -Wextra -o $@ tools/rag/spark_rag_http.c \
		bootstrap/dry_rag.c

# Generic http get/post (dry fixtures; live curl + auth/retries).
spark-http: tools/http/spark_http.c bootstrap/dry_http.c \
	bootstrap/dry_http.h
	$(CC) -O2 -Wall -Wextra -o $@ tools/http/spark_http.c \
		bootstrap/dry_http.c

# Typed extract (dry fixture files + schema validation).
spark-extract: tools/extract/spark_extract.c bootstrap/dry_extract.c \
	bootstrap/dry_extract.h
	$(CC) -O2 -Wall -Wextra -o $@ tools/extract/spark_extract.c \
		bootstrap/dry_extract.c

# Expect equal/contains (literal or fixture want; pass/fail exit).
spark-expect: tools/expect/spark_expect.c bootstrap/dry_expect.c \
	bootstrap/dry_expect.h
	$(CC) -O2 -Wall -Wextra -o $@ tools/expect/spark_expect.c \
		bootstrap/dry_expect.c

# Model train submit/status (HTTP or allowlisted local-yield).
spark-train-http: tools/train/spark_train_http.c bootstrap/dry_train.c \
	bootstrap/dry_train.h
	$(CC) -O2 -Wall -Wextra -o $@ tools/train/spark_train_http.c \
		bootstrap/dry_train.c

# Abstain / IDK heads (Python companion; dry fixtures + CPU train).
spark-abstain: tools/spark-abstain/spark_abstain.sh \
	tools/spark-abstain/cli.py
	install -m 755 tools/spark-abstain/spark_abstain.sh $@

# Grounded generation / anti-guess (verify-before-speak).
spark-ground: tools/spark-ground/spark_ground.sh \
	tools/spark-ground/cli.py
	install -m 755 tools/spark-ground/spark_ground.sh $@

# Model lab: reverse local HF config; compile/modify via ./spark.
spark-model-lab: tools/spark-model-lab/spark_model_lab.sh \
	tools/spark-model-lab/cli.py
	install -m 755 tools/spark-model-lab/spark_model_lab.sh $@

spark-serve: tools/spark-bc-dump/spark_serve.sh \
	tools/spark-bc-dump/dump.py
	install -m 755 tools/spark-bc-dump/spark_serve.sh $@

# Tiny CPU HTTP/stdio predict + embeddings (G-lane; not production).
spark-serve-api: tools/spark-serve-api/spark_serve_api.sh \
	python/sparklang/model_lab/serve_api.py
	install -m 755 tools/spark-serve-api/spark_serve_api.sh $@

.PHONY: test-serve-api
test-serve-api:
	PYTHONPATH=python python3 tools/spark-serve-api/test_serve_api.py

# Gateway probe credential dry/live check (public AI gateway).
spark-ask-probe: tools/ask/spark_ask_probe.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

# Encrypt-to-model gateway (AES-256-GCM). Offline self-test in make test.
spark-enc-gateway: tools/crypto/spark_enc_gateway.c
	$(CC) -O2 -Wall -Wextra -o $@ $< -lcrypto

# Optional Qt GUI helper — only forked by `browser gui --live`.
spark-browser-host: tools/browser/spark_browser_host.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

# Engine B display — PPM/RGB → X11 PutImage (forked by browser show --live).
spark-engine-show: tools/browser/spark_engine_show.c
	$(CC) -O2 -Wall -Wextra -o $@ $< -lX11

# PSTN companion — OFF by default; requires --pstn-live + SPARK_PSTN=1
spark-pstn-dial: tools/voice/spark_pstn_dial.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

# Live STT/TTS — dry-run never forks; net vendors OFF without SPARK_*_NET
spark-stt-tts: tools/voice/spark_stt_tts.c
	$(CC) -O2 -Wall -Wextra -o $@ $< -lm

# review url — file:// offline; http(s) needs --allow-net (A+B)
spark-review-url: tools/review/spark_review_url.c
	$(CC) -O2 -Wall -Wextra -o $@ $<

# engine fetch https — OpenSSL BIO companion (forked with --allow-net)
spark-engine-fetch-tls: tools/engine/spark_engine_fetch_tls.c
	$(CC) -O2 -Wall -Wextra -o $@ $< -lssl -lcrypto

.PHONY: voice-test
voice-test: spark spark-pstn-dial spark-stt-tts
	./spark --dry-run examples/voice_reviewer.spark
	./spark --dry-run examples/voice_coder.spark
	./spark --dry-run examples/voice_copy.spark
	./spark --dry-run examples/voice_model.spark
	./spark --dry-run examples/voice_pstn.spark
	./spark-pstn-dial --to +15555550100 >/dev/null 2>&1; \
	  test $$? -ne 0
	./spark-stt-tts status | grep -q local_synth
	./spark-stt-tts speak --text "hi" --out /tmp/spark-voice-test.wav
	test -f /tmp/spark-voice-test.wav
	./spark-stt-tts listen --in examples/fixtures/audio/sample_review.wav \
	  --out /tmp/spark-voice-test.txt
	grep -q washer /tmp/spark-voice-test.txt
	./spark --live examples/voice_live.spark >/dev/null
	test -f out/voice_live.wav
	@echo "voice-test OK (PSTN gated; STT/TTS local+live)"

# QUIC/H3 MITM smoke — forked by `mitm quic smoke` (Python aioquic helper).
spark-mitm-quic: tools/browser/spark_mitm_quic.sh
	install -m 755 tools/browser/spark_mitm_quic.sh $@

# QUIC UDP divert — forked by `mitm quic divert` (gated apply).
spark-mitm-quic-divert: tools/browser/spark_mitm_quic_divert.sh
	install -m 755 tools/browser/spark_mitm_quic_divert.sh $@

# CA init/install/status — forked by `mitm ca-*` (Python ensure_ca helper).
spark-mitm-ca: tools/browser/spark_mitm_ca.sh
	install -m 755 tools/browser/spark_mitm_ca.sh $@

# HTTPS CONNECT MITM (h2/h1) — forked by `mitm enable|smoke` (Spark-owned).
spark-mitm-h2: tools/browser/spark_mitm_h2.sh
	install -m 755 tools/browser/spark_mitm_h2.sh $@

# CDP client — forked by `browser cdp` (Python helper in spark-browser).
spark-browser-cdp: tools/browser/spark_browser_cdp.sh
	install -m 755 tools/browser/spark_browser_cdp.sh $@

# Show that the shipped binary is assembled machine code
machine-proof: spark
	@echo "=== file(1) ==="
	file ./spark
	@echo "=== ELF header (hex) ==="
	xxd ./spark | head -4
	@echo "=== _start disassembly (first instructions) ==="
	$(OBJDUMP) -d ./spark | sed -n '/<_start>:/,/^$$/p' | head -20

test: spark companions spark-bootstrap test-sparkbc test-ai-playbooks \
	test-extract test-expect test-host-embed test-abstain test-ground \
	test-model-lab \
	test-serve-api \
	test-bpe-seed \
	test-shell \
	test-ask-gateway
	./tests/run_dry.sh
	./tests/hdl_check.sh
	./bootstrap/tests/run_bootstrap.sh

# Deterministic byte-level BPE seed (pinned fixture; no downloads).
.PHONY: test-bpe-seed
test-bpe-seed:
	PYTHONPATH=python python3 tools/spark-bpe-seed/test_bpe.py

# HDL: real iverilog compile of hdl/*.v, or honest SKIP with reason
.PHONY: test-hdl
test-hdl:
	./tests/hdl_check.sh

# Dry browser E2E — no display, no --live GUI. Live entry is
# spark-browser: make run → ./spark --live browser/run.spark
test-e2e-browser: spark companions
	./tests/e2e_browser_dry.sh

# Every examples/*.spark under --dry-run. Fail-loud IDE demos expect rc!=0.
test-examples: spark companions
	@fail=0; \
	fail_loud='ide_open_miss|ide_open_nopath|ide_run_nobuf|ide_save_nopath|ide_show_miss|ide_show_notppm|ide_ask_nobuf|ide_key_bad|ide_keys_miss|http_get_live|extract_bad|expect_fail|expect_miss_fixture|shell_refuse'; \
	for f in examples/*.spark; do \
	  to=""; \
	  base="$$(basename "$$f")"; \
	  case "$$f" in examples/binary_cuda_drivers.spark) to="timeout 120";; esac; \
	  if echo "$$base" | grep -qE "$$fail_loud"; then \
	    if $$to ./spark --dry-run "$$f" >/dev/null 2>&1; then \
	      echo "FAIL (fail-loud) $$f"; fail=1; \
	    else \
	      echo "PASS (fail-loud) $$f"; \
	    fi; \
	  elif $$to ./spark --dry-run "$$f" >/dev/null 2>&1; then \
	    echo "PASS $$f"; \
	  else \
	    echo "FAIL $$f"; fail=1; \
	  fi; \
	done; \
	if [ "$$fail" -ne 0 ]; then exit 1; fi; \
	echo "test-examples OK"

examples-run: test-examples

.PHONY: browser-scaffold
browser-scaffold:
	# Refresh out/os/browser_mitm from templates/os/browser
	# (same tree os generate emits). Does not overwrite spark-browser
	# Python MITM/CA packages.
	python3 tools/browser/scaffold_spark_browser.py

.PHONY: browser-mitm-analyze
browser-mitm-analyze:
	@test -n "$(HAR)" || (echo "usage: make browser-mitm-analyze HAR=…"; exit 2)
	cd ../spark-browser && PYTHONPATH=. \
	  python3 -m spark_browser mitm analyze "$(HAR)" \
	  --spark "$(CURDIR)/spark"

.PHONY: model-probe
model-probe:
	bash tools/model_probe/probe.sh

# Frozen copy/recall + next-token probes. Dry default; optional WEIGHTS=
# or SPARK_EVAL_WEIGHTS. Optional CLAUDE=off|auto|on (default off).
# Exit 0 = harness ran (not a beat-Claude claim). Never invents keys.
CLAUDE ?= off
.PHONY: spark-eval
spark-eval:
	@if [ -n "$(WEIGHTS)" ]; then \
	  PYTHONPATH=python python3 tools/spark-eval/run.py \
	    --claude "$(CLAUDE)" --weights "$(WEIGHTS)"; \
	elif [ -n "$${SPARK_EVAL_WEIGHTS}" ]; then \
	  PYTHONPATH=python python3 tools/spark-eval/run.py \
	    --claude "$(CLAUDE)" --weights "$${SPARK_EVAL_WEIGHTS}"; \
	else \
	  PYTHONPATH=python python3 tools/spark-eval/run.py \
	    --claude "$(CLAUDE)"; \
	fi

# Head-to-head measurement: Spark scores + Claude baseline if creds
# exist; otherwise status skipped_no_credentials. Never claims win.
.PHONY: spark-eval-claude
spark-eval-claude:
	@$(MAKE) spark-eval CLAUDE=auto WEIGHTS="$(WEIGHTS)"

.PHONY: test-spark-eval
test-spark-eval:
	PYTHONPATH=python python3 tools/spark-eval/test_eval.py

# Owned Spark coding model (M-lane): TinyCoder written+trained here.
# Prefers RTX 5090 when available; CPU fallback. Never 6000.
# Not a HF/Claude wrapper. Not beat Claude.
# Tiny = CI/default. Large = opt-in (dim 64 / n_layer 4).
.PHONY: spark-coder-train spark-coder-train-large test-spark-coder
spark-coder-train: spark-bootstrap
	@mkdir -p models/spark-coder
	@rm -f models/spark-coder/weights.safetensors \
	  models/spark-coder/checkpoint.json \
	  models/spark-coder/factory_step_checkpoint.json
	./spark-code train \
	  --scale $${SPARK_CODER_SCALE:-tiny} \
	  --sparkbc docs/examples/spark-train-step.sparkbc \
	  --dataset examples/fixtures/coder/dataset.jsonl \
	  --out models/spark-coder \
	  --outer 10 --inner 10 --lr 0.2 \
	  --device auto
	./spark-code prove \
	  --weights models/spark-coder/weights.safetensors \
	  --fixtures examples/fixtures/coder/prove.json \
	  --min-acc 0.5
	@test -f models/spark-coder/weights.safetensors
	@test -f models/spark-coder/checkpoint.json
	@test -f models/spark-coder/arch.json

# Opt-in large coder: dim 64 / n_layer 4. Prefer 5090. Never 6000.
# Not GHA default. Still does not beat Claude.
spark-coder-train-large: spark-bootstrap
	@mkdir -p models/spark-coder-large
	@rm -f models/spark-coder-large/weights.safetensors \
	  models/spark-coder-large/checkpoint.json \
	  models/spark-coder-large/factory_step_checkpoint.json
	./spark-code train \
	  --scale large \
	  --sparkbc docs/examples/spark-train-step.sparkbc \
	  --dataset examples/fixtures/coder/dataset.jsonl \
	  --out models/spark-coder-large \
	  --outer $${SPARK_CODER_OUTER:-6} \
	  --inner $${SPARK_CODER_INNER:-8} \
	  --lr $${SPARK_CODER_LR:-0.12} \
	  --device $${SPARK_CODER_DEVICE:-auto}
	@test -f models/spark-coder-large/weights.safetensors
	@test -f models/spark-coder-large/arch.json
	@python3 -c "import json; a=json.load(open('models/spark-coder-large/arch.json')); \
	  assert a['scale']=='large' and a['dim']>=64 and a['n_layer']>=4; \
	  assert a['beats_claude'] is False; assert a['never']=='rtx-pro-6000'; \
	  print('large ok dim', a['dim'], 'n_layer', a['n_layer'], 'never', a['never'])"

test-spark-coder: spark-bootstrap
	PYTHONPATH=python python3 -m unittest \
	  sparklang.spark_coder.test_spark_coder -v

# Weight gallery: catalog tiny→xl kinds; emit scale+large samples;
# write website catalog JSON. Play/diff/stats on CPU. Never 6000.
.PHONY: weight-gallery weight-gallery-xl test-weights-play
weight-gallery: spark-bootstrap
	@mkdir -p out/gallery/scale out/gallery/large \
	  website/docs/examples
	PYTHONPATH=python python3 tools/spark-weights/cli.py generate scale \
	  --out out/gallery/scale/weights.safetensors --cpu
	PYTHONPATH=python python3 tools/spark-weights/cli.py generate large \
	  --out out/gallery/large/weights.safetensors --cpu
	PYTHONPATH=python python3 tools/spark-weights/cli.py \
	  write-catalog-json \
	  --out website/docs/examples/weight-gallery-catalog.json
	@cp -f website/docs/examples/weight-gallery-catalog.json \
	  docs/examples/weight-gallery-catalog.json 2>/dev/null || true
	PYTHONPATH=python python3 tools/spark-weights/cli.py catalog | head -c 4000
	@echo ""
	@echo "weight-gallery: scale+large under out/gallery/; catalog JSON written"

# Opt-in XL (dim=256). Prefer 5090; refuse 6000; CPU fallback OK.
weight-gallery-xl: spark-bootstrap
	@mkdir -p out/gallery/xl
	PYTHONPATH=python python3 tools/spark-weights/cli.py generate xl \
	  --out out/gallery/xl/weights.safetensors --5090
	PYTHONPATH=python python3 tools/spark-weights/cli.py play \
	  out/gallery/xl/weights.safetensors --prompt "xl"

test-weights-play:
	PYTHONPATH=python python3 -m unittest \
	  sparklang.model_lab.test_weight_gallery -v
	PYTHONPATH=python python3 tools/spark-weights/cli.py inspect \
	  docs/examples/spark-self.init.safetensors >/tmp/wg-inspect.json
	PYTHONPATH=python python3 tools/spark-weights/cli.py play \
	  docs/examples/spark-self.init.safetensors --prompt "ok" \
	  >/tmp/wg-play.json
	@python3 -c "import json; p=json.load(open('/tmp/wg-play.json')); \
	  assert p['beats_claude'] is False; assert 'argmax' in p['forward']; \
	  print('play_ok', p['forward']['path'], 'beats_claude=False')"

# Voice easy — owned STT/TTS heads (tiny CI + large opt-in).
# Prefer RTX 5090; NEVER RTX PRO 6000. Not ElevenLabs overnight.
.PHONY: voice-easy test-voice-easy voice-easy-large
voice-easy:
	chmod +x spark-voice tools/spark-voice/cli.py
	./spark-voice easy --dry --device auto --scale tiny

test-voice-easy:
	chmod +x spark-voice tools/spark-voice/cli.py
	PYTHONPATH=python python3 -m unittest \
	  sparklang.voice_easy.test_voice_easy -v
	./spark-voice easy --dry --device cpu --scale tiny

voice-easy-large:
	chmod +x spark-voice tools/spark-voice/cli.py
	./spark-voice easy --scale large --device auto

# Multi-outer CPU SGD + layer-0 attn proof + measurement-only eval.
# Never claims beat Claude. CPU only. Tiny fixture = GHA/CI default.
# Asserts frozen probe scores >0 after attn train (not a Claude win).
.PHONY: spark-sgd-proof
spark-sgd-proof: spark-bootstrap
	@mkdir -p out/train/sgd-proof
	@rm -f out/train/sgd-proof/{weights.safetensors,checkpoint.json}
	PYTHONPATH=python python3 tools/spark-bc-dump/apply_step.py \
	  --sparkbc docs/examples/spark-train-step.sparkbc \
	  --weights out/train/sgd-proof/weights.safetensors \
	  --checkpoint out/train/sgd-proof/checkpoint.json \
	  --dataset examples/fixtures/train/dataset.jsonl \
	  --outer 4 --inner 8 --lr 0.08 --step 1 \
	  --command 'make spark-sgd-proof'
	@python3 -c "import json; c=json.load(open('out/train/sgd-proof/checkpoint.json')); \
	  print('loss_curve', [(p['outer'], round(p['loss'],6)) for p in c['loss_curve']]); \
	  print('loss', c['loss_before'], '->', c['loss_after']); \
	  print('train_attn', c.get('train_attn'), 'beats_claude', c['beats_claude'], 'device', c['device']); \
	  assert c['loss_after'] < c['loss_before']; \
	  assert c.get('train_attn') is True; \
	  assert c['beats_claude'] is False"
	@$(MAKE) spark-eval WEIGHTS=out/train/sgd-proof/weights.safetensors
	@PYTHONPATH=python python3 -c "from pathlib import Path; \
	  import importlib.util as u; \
	  s=u.spec_from_file_location('ev','tools/spark-eval/run.py'); \
	  m=u.module_from_spec(s); s.loader.exec_module(m); \
	  r=m.run_suite(m.SUITE_DEFAULT, Path('out/train/sgd-proof/weights.safetensors')); \
	  sc={p['name']:p['score'] for p in r['probes']}; \
	  print('proof_scores', sc); \
	  assert sc.get('copy_recall',0)>0 and sc.get('next_token',0)>0, sc; \
	  print('eval_nonzero_ok beats_claude=False')"

# Opt-in local scale proof: larger JSONL + dim/n_layer knobs.
# Still CPU-fast; not overnight; not GHA default. Not beat Claude.
# Knobs: SPARK_SGD_DIM SPARK_SGD_N_LAYER SPARK_SGD_OUTER SPARK_SGD_INNER
.PHONY: spark-sgd-proof-scale
spark-sgd-proof-scale: spark-bootstrap
	@mkdir -p out/train/sgd-proof-scale
	@rm -f out/train/sgd-proof-scale/{weights.safetensors,checkpoint.json}
	PYTHONPATH=python python3 tools/spark-bc-dump/apply_step.py \
	  --sparkbc docs/examples/spark-train-step.sparkbc \
	  --weights out/train/sgd-proof-scale/weights.safetensors \
	  --checkpoint out/train/sgd-proof-scale/checkpoint.json \
	  --dataset examples/fixtures/train/dataset_scale.jsonl \
	  --dim $${SPARK_SGD_DIM:-64} \
	  --n-layer $${SPARK_SGD_N_LAYER:-4} \
	  --outer $${SPARK_SGD_OUTER:-2} \
	  --inner $${SPARK_SGD_INNER:-4} \
	  --step 1 \
	  --command 'make spark-sgd-proof-scale'
	@python3 -c "import json; c=json.load(open('out/train/sgd-proof-scale/checkpoint.json')); \
	  print('scale dataset_n', c['dataset_n'], 'dim', c.get('arch_dim'), \
	        'n_layer', c.get('arch_n_layer')); \
	  print('loss_curve', [(p['outer'], round(p['loss'],6)) for p in c['loss_curve']]); \
	  print('loss', c['loss_before'], '->', c['loss_after']); \
	  print('beats_claude', c['beats_claude'], 'device', c['device']); \
	  assert c['dataset_n'] >= 72; \
	  assert int(c.get('arch_dim') or 0) >= 64; \
	  assert int(c.get('arch_n_layer') or 0) >= 4; \
	  assert c['loss_after'] < c['loss_before']; \
	  assert c['beats_claude'] is False; \
	  assert c['device'] == 'cpu'; \
	  assert c['never'] == 'rtx-pro-6000'"
	@$(MAKE) spark-eval WEIGHTS=out/train/sgd-proof-scale/weights.safetensors

corpus:
	mkdir -p data
	python3 tools/corpus_million/run_corpus.py --checkpoint-every 2000

corpus-agg:
	python3 tools/corpus_million/aggregate.py \
	  --report reports/spark-corpus-1m-20260831.md

clean:
	rm -f spark $(SPARK_OBJS) spark-out.wav out.wav
	rm -f spark-cuda-probe spark-net-capture
	rm -f spark-binary-probe spark-section-dump spark-lift
	rm -f spark-ask-http spark-ask-probe spark-rag-http spark-http \
		spark-extract spark-expect spark-train-http spark-abstain \
		spark-ground spark-shell spark-model-lab spark-serve spark-serve-api \
		spark-browser-host spark-pstn-dial spark-mitm-quic
	rm -f spark-mitm-quic-divert spark-mitm-ca spark-mitm-h2 spark-browser-cdp spark-enc-gateway
	rm -f spark-stt-tts spark-review-url spark-engine-show spark-engine-paint
	rm -f spark-ide-paint spark-engine-fetch-tls
	rm -f spark-bootstrap sparkc spark-bc-pack-hello spark-bc-emit
	rm -f selfhost/spark-lex
	rm -f asm/engine_paint_main.o asm/engine_paint_ops.o
	rm -f asm/ide_paint.o asm/ide_paint_main.o
	rm -f out/program.spark out/program.py.txt out/better-model.md
	rm -rf out/os out/browser out/voice_models out/voice_codegen.spark
	rm -rf out/encrypt out/engine
	rm -f examples/c/host_embed

# --- B: C bootstrap VM (isolated; not linked into ./spark ELF) ---
SPARKC_SRCS = bootstrap/main.c bootstrap/vm.c bootstrap/engine_parse.c \
	bootstrap/engine_css.c bootstrap/engine_layout.c \
	bootstrap/engine_paint.c bootstrap/engine_show.c \
	bootstrap/engine_render.c bootstrap/dry_ask.c bootstrap/dry_auto_model.c \
	bootstrap/dry_classify.c bootstrap/dry_rag.c bootstrap/dry_http.c \
	bootstrap/dry_extract.c bootstrap/dry_expect.c \
	bootstrap/dry_train.c \
	bootstrap/dry_engine.c \
	bootstrap/dry_ide.c bootstrap/dry_ops.c \
	bootstrap/bc_read.c bootstrap/bc_vm.c bootstrap/bc_write.c \
	bootstrap/spark_parse.c selfhost/lex.c
spark-bootstrap sparkc: $(SPARKC_SRCS) bootstrap/vm.h \
	bootstrap/dry_ask.h bootstrap/dry_auto_model.h bootstrap/dry_classify.h \
	bootstrap/dry_rag.h bootstrap/dry_http.h bootstrap/dry_extract.h \
	bootstrap/dry_expect.h \
	bootstrap/dry_train.h \
	bootstrap/dry_engine.h \
	bootstrap/dry_ide.h \
	bootstrap/dry_ops.h \
	bootstrap/bc_opcodes.h \
	bootstrap/bc_read.h bootstrap/bc_vm.h bootstrap/bc_write.h \
	bootstrap/spark_parse.h selfhost/lex.h \
	bootstrap/engine_parse.h bootstrap/engine_css.h \
	bootstrap/engine_layout.h bootstrap/engine_paint.h \
	bootstrap/engine_show.h bootstrap/engine_render.h \
	asm/engine_layout.o asm/engine_paint.o asm/ide_paint.o
	$(CC) -O2 -Wall -Wextra -I. -o spark-bootstrap $(SPARKC_SRCS) \
		asm/engine_layout.o asm/engine_paint.o asm/ide_paint.o
	ln -sfn spark-bootstrap sparkc

test-bootstrap: spark-bootstrap
	chmod +x bootstrap/tests/run_bootstrap.sh
	./bootstrap/tests/run_bootstrap.sh

.PHONY: test-ai-playbooks
test-ai-playbooks: spark-bootstrap playbooks-catalog
	chmod +x bootstrap/tests/run_ai_playbooks.sh
	./bootstrap/tests/run_ai_playbooks.sh
	chmod +x bootstrap/tests/run_playbooks_catalog.sh
	./bootstrap/tests/run_playbooks_catalog.sh

# Offline Bifrost ask companion gate (+ optional SPARK_ASK_GATEWAY_LIVE=1).
.PHONY: test-ask-gateway
test-ask-gateway: spark-ask-http
	chmod +x tools/ask/run_ask_gateway_gate.sh
	./tools/ask/run_ask_gateway_gate.sh

.PHONY: test-rag-gateway
test-rag-gateway: spark-rag-http spark
	chmod +x tools/rag/run_rag_gateway_gate.sh
	./tools/rag/run_rag_gateway_gate.sh

.PHONY: test-http
test-http: spark-http spark
	chmod +x tools/http/run_http_gate.sh
	./tools/http/run_http_gate.sh

.PHONY: test-extract
# spark-expect: published lib-expect-after-extract forks ./spark-expect
test-extract: spark-extract spark-expect spark
	chmod +x tools/extract/run_extract_gate.sh
	./tools/extract/run_extract_gate.sh
	chmod +x tools/extract/run_lib_gate.sh
	./tools/extract/run_lib_gate.sh

.PHONY: test-expect
test-expect: spark-expect spark
	chmod +x tools/expect/run_expect_gate.sh
	./tools/expect/run_expect_gate.sh

.PHONY: test-host-embed
test-host-embed: spark examples/c/host_embed
	chmod +x tools/host_embed/run_host_embed_gate.sh
	./tools/host_embed/run_host_embed_gate.sh

examples/c/host_embed: examples/c/host_embed.c host/c/sparklang.c \
	host/c/sparklang.h
	$(CC) -O2 -Wall -Wextra -o $@ examples/c/host_embed.c \
		host/c/sparklang.c

.PHONY: test-shell
test-shell: spark spark-shell
	chmod +x tools/shell/run_shell_gate.sh
	./tools/shell/run_shell_gate.sh

.PHONY: test-abstain
test-abstain: spark spark-abstain spark-expect spark-http
	chmod +x tools/spark-abstain/run_abstain_gate.sh
	./tools/spark-abstain/run_abstain_gate.sh

.PHONY: test-ground
test-ground: spark-ground
	chmod +x tools/spark-ground/run_ground_gate.sh
	./tools/spark-ground/run_ground_gate.sh

.PHONY: test-spark-lsp
test-spark-lsp:
	PYTHONPATH=tools python3 -m unittest spark_lsp.test_lsp -v

.PHONY: test-model-lab
test-model-lab: spark spark-model-lab spark-abstain spark-expect spark-http
	chmod +x tools/spark-model-lab/run_lab_gate.sh
	./tools/spark-model-lab/run_lab_gate.sh
	PYTHONPATH=python python3 tools/spark-bc-dump/test_dump.py

# Optional: SPARK_ABSTAIN_HF=1 SPARK_ABSTAIN_MODEL=/path ./make …
.PHONY: smoke-abstain-hf
smoke-abstain-hf: spark spark-abstain
	chmod +x tools/spark-abstain/hf_export_train_smoke.sh
	./tools/spark-abstain/hf_export_train_smoke.sh

.PHONY: test-train-http
test-train-http: spark-train-http spark
	./spark-train-http --dry --submit | grep -q job-dry-001
	./spark-train-http --dry --submit --method spark_pref_pack | \
		grep -q spark_pref_pack
	./spark-train-http --dry --submit --method spark_playbook_fit | \
		grep -q spark_playbook_fit
	./spark-train-http --dry --submit --method spark_faq_index | \
		grep -q spark_faq_index
	./spark-train-http --dry --submit --method spark_reply_pack | \
		grep -q spark_reply_pack
	./spark-train-http --dry --status job-reply-001 | grep -q job-reply-001
	./spark-train-http --dry --status job-dry-001 | grep -q '"state":"succeeded"'
	./spark-train-http --dry --status job-pref-001 | grep -q job-pref-001
	./spark-train-http --dry --status job-missing-999 ; test $$? -ne 0
	./spark-train-http --dry --submit --method not_a_method ; \
		test $$? -ne 0
	printf '%s\n' \
	  'model train dataset "examples/fixtures/train/dataset.jsonl" base "spark_pref_pack" out "out/train/job-pref-001" backend "http" method "spark_pref_pack" -> job' \
	  > /tmp/spark-train-line-test.txt
	./spark-train-http --dry --submit --spark-line \
		/tmp/spark-train-line-test.txt | grep -q spark_pref_pack
	test -f out/train/job-pref-001/ARTIFACT
	./spark --dry-run examples/model_train.spark | grep -q '"op":"train"'
	test -f out/train/job-dry-001/ARTIFACT
	./spark --dry-run examples/model_train_reply.spark | grep -q '"op":"train"'
	./spark-train-http --dry --submit --method spark_reply_pack \
	  --out out/train/job-reply-001 | grep -q spark_reply_pack
	test -f out/train/job-reply-001/ARTIFACT
	python3 tools/spark-train-ref/test_reply_pack.py
	@echo "test-train-http OK (dry only)"

# Packer for goldens (encoding, not a .spark compiler).
spark-bc-pack-hello: bootstrap/bc_pack_hello.c bootstrap/bc_write.c \
	bootstrap/bc_read.h bootstrap/bc_write.h bootstrap/bc_opcodes.h
	$(CC) -O2 -Wall -Wextra -o spark-bc-pack-hello \
		bootstrap/bc_pack_hello.c bootstrap/bc_write.c

.PHONY: test-sparkbc test-sparkbc-e2e sparkbc-e2e \
	spark-bc-emit test-bc-emit spark-bc \
	test-decompile-compete decompile-roundtrip decompile-bench
test-sparkbc: spark-bootstrap spark
	chmod +x bootstrap/tests/run_sparkbc.sh
	./bootstrap/tests/run_sparkbc.sh
	PYTHONPATH=python python3 tools/spark-bc-dump/test_dump.py

# Focused TRAIN→STEP→TRAIN_STATUS e2e: compile → dump → --run-bc →
# ARTIFACT (+ GAS ./spark --run-bc). STEP = tiny CPU SGD.
test-sparkbc-e2e: spark-bootstrap spark
	chmod +x tools/spark-bc-dump/run_e2e_gate.sh
	./tools/spark-bc-dump/run_e2e_gate.sh

sparkbc-e2e: test-sparkbc-e2e

# Richer dump symbols/xrefs + analysis project (no GPU).
test-decompile-compete:
	PYTHONPATH=python python3 \
		tools/spark-bc-dump/test_decompile_compete.py

# Loud SoT win: compile → dump → recompile hash on fixtures.
decompile-roundtrip: spark-bootstrap
	PYTHONPATH=python python3 tools/spark-bc-dump/roundtrip.py \
		--json-out out/decompile-bench/roundtrip.json

# Measured scoreboard JSON (+ sample analysis project).
decompile-bench: spark-bootstrap test-decompile-compete
	PYTHONPATH=python python3 tools/spark-bc-dump/decompile_bench.py \
		--json-out website/data/decompile-scoreboard.json \
		--project-dir out/decompile-bench/sample-project
	cp -f website/data/decompile-scoreboard.json \
		docs/examples/decompile-scoreboard.json
	mkdir -p website/docs/examples
	cp -f docs/examples/decompile-scoreboard.json \
		website/docs/examples/decompile-scoreboard.json

spark-bc-emit: bootstrap/bc_emit_sasm.c bootstrap/bc_read.c \
	bootstrap/dry_ask.c bootstrap/dry_auto_model.c \
	bootstrap/dry_classify.c bootstrap/dry_ops.c \
	bootstrap/bc_read.h bootstrap/bc_opcodes.h bootstrap/dry_ask.h \
	bootstrap/dry_auto_model.h bootstrap/dry_classify.h bootstrap/dry_ops.h
	$(CC) -O2 -Wall -Wextra -I. -o spark-bc-emit \
		bootstrap/bc_emit_sasm.c bootstrap/bc_read.c \
		bootstrap/dry_ask.c bootstrap/dry_auto_model.c \
		bootstrap/dry_classify.c bootstrap/dry_ops.c

test-bc-emit: spark-bc-emit spark-bc-pack-hello sparkasm
	chmod +x bootstrap/tests/run_bc_emit.sh
	./bootstrap/tests/run_bc_emit.sh

# Phase 6 product wrapper (compile → bc_vm when supported); not GAS ./spark.
spark-bc: spark-bootstrap
	chmod +x scripts/spark-bc

# --- C: Spark-native assembler (isolated; not GAS SoT) ---
.PHONY: sparkasm test-sparkasm test-sparkasm-control
sparkasm:
	$(MAKE) -C sparkasm

test-sparkasm:
	$(MAKE) -C sparkasm test

# Tensor-assembly source shape check (control.sparkasm). Not a tensor VM.
test-sparkasm-control:
	PYTHONPATH=python python3 -m sparklang.model_lab.sparkasm_check \
		examples/models/control.sparkasm
	PYTHONPATH=python python3 -m unittest \
		sparklang.model_lab.test_sparkasm_check -v

# --- A: self-host seed (lexer aid; not B VM, not C assembler) ---
.PHONY: selfhost-lex test-selfhost-lex
selfhost-lex: selfhost/lex.c selfhost/lex.h
	$(CC) -O2 -Wall -Wextra -DSPARK_LEX_STANDALONE_MAIN \
	  -I. -o selfhost/spark-lex selfhost/lex.c

# Golden diff: spark-lex and spark-bootstrap --lex (17 fixtures).
test-selfhost-lex: selfhost-lex spark-bootstrap
	chmod +x bootstrap/tests/run_selfhost_lex.sh
	./bootstrap/tests/run_selfhost_lex.sh

