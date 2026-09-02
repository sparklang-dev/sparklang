#!/usr/bin/env bash
# Dry tests for C bootstrap VM (path B) — no network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

make -s spark-bootstrap

fail=0
check() {
  local name="$1" file="$2" needle="$3"
  out="$(./spark-bootstrap --dry-run "$file" 2>&1)" || {
    echo "FAIL bootstrap_$name: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if echo "$out" | grep -qE -- "$needle"; then
    echo "PASS bootstrap_$name"
  else
    echo "FAIL bootstrap_$name: missing '$needle'"
    echo "$out" | head -20
    fail=1
  fi
}

check_fail() {
  local name="$1" file="$2" needle="$3"
  set +e
  out="$(./spark-bootstrap --dry-run "$file" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL bootstrap_$name: expected non-zero"
    fail=1
    return
  fi
  if echo "$out" | grep -qE -- "$needle"; then
    echo "PASS bootstrap_$name"
  else
    echo "FAIL bootstrap_$name: missing '$needle' (rc=$rc)"
    echo "$out" | head -20
    fail=1
  fi
}

check hello examples/hello.spark "Gravity pulls masses together"
check hello_banner examples/hello.spark "dry-run via"
check hello_print examples/hello.spark "\[print\] Gravity"
check hello_ok examples/hello.spark "\[spark\] ok"

check hello_sugar examples/hello_sugar.spark "Gravity pulls masses together"

tom_out="$(
  cd bootstrap/fixtures && "$ROOT/spark-bootstrap" --dry-run tom_ask.spark 2>&1
)" || {
  echo "FAIL bootstrap_spark_toml: exit non-zero"
  echo "$tom_out" | head -10
  fail=1
}
if echo "$tom_out" | grep -q 'model=code'; then
  echo "PASS bootstrap_spark_toml"
else
  echo "FAIL bootstrap_spark_toml: missing model=code from spark.toml"
  echo "$tom_out" | head -10
  fail=1
fi

check dx_showcase examples/dx_showcase.spark "Resumen en español"

check dx_include bootstrap/fixtures/dx_include.spark \
  "\[include\] lib/ai.spark"
check dx_include_gravity bootstrap/fixtures/dx_include.spark \
  "Gravity pulls masses together"

check let_bind bootstrap/fixtures/let_print.spark "\[let\] greeting"
check let_print bootstrap/fixtures/let_print.spark "\[print\] hello from let"

check classify_support bootstrap/fixtures/classify_intent.spark \
  '"label":"support","confidence":0.91'
check classify_sales bootstrap/fixtures/classify_intent.spark \
  '"label":"sales","confidence":0.88'

check tool_reg bootstrap/fixtures/tool_agent.spark "\[tool\] registered weather"
check tool_with bootstrap/fixtures/tool_agent.spark \
  '"op":"with_tools","tools":"weather"'
check tool_ask bootstrap/fixtures/tool_agent.spark \
  '\[tool:weather\] stub:local'
check tool_print bootstrap/fixtures/tool_agent.spark \
  '\[print\] \[tool:weather\] stub:local'

check extract_person bootstrap/fixtures/extract_listen_pipe.spark \
  '\[extract\] \{"name":"Ada Lovelace","age":36\}'
check listen_stub bootstrap/fixtures/extract_listen_pipe.spark \
  '\[listen\] My account is locked'
check speak_stub bootstrap/fixtures/extract_listen_pipe.spark \
  '\[speak\] wrote out/bootstrap_speak.wav'
check pipe_step bootstrap/fixtures/extract_listen_pipe.spark \
  '\[pipeline\] step'
check pipe_ask bootstrap/fixtures/extract_listen_pipe.spark \
  'Gravity pulls masses together'

check review_higher bootstrap/fixtures/review_path.spark \
  '"suggested_level":"higher"'
check review_noreval bootstrap/fixtures/review_path.spark \
  'never eval web JS'
check review_print bootstrap/fixtures/review_path.spark \
  '\[print\] \{"issues":\["possible eval"'

check_fail gas_only_review_url bootstrap/fixtures/gas_only_review_url.spark \
  "GAS-only"
check_fail with_no_tool bootstrap/fixtures/with_no_tool.spark \
  "prior tool registration"

check voice_session bootstrap/fixtures/voice_session.spark \
  '\[voice\] session'
check voice_listen bootstrap/fixtures/voice_session.spark \
  '\[listen\] My account is locked'
check voice_classify bootstrap/fixtures/voice_session.spark \
  '"label":"support","confidence":0.91'
check voice_speak bootstrap/fixtures/voice_session.spark \
  '\[speak\] wrote out/bootstrap_voice.wav'
check voice_reply bootstrap/fixtures/voice_session.spark \
  'Happy to help'

check_fail gas_only_voice_review bootstrap/fixtures/gas_only_voice_review.spark \
  "GAS-only"

check browser_run bootstrap/fixtures/browser_run_goto.spark \
  '"op":"run","ok":true,"mode":"dry-run"'
check browser_goto bootstrap/fixtures/browser_run_goto.spark \
  '"op":"goto","ok":true,"url":"https://example.com/"'
check browser_print_url bootstrap/fixtures/browser_run_goto.spark \
  '\[print\] https://example.com/'
check browser_quic_note bootstrap/fixtures/browser_run_goto.spark \
  'browser gui --live'

check_fail gas_only_browser_gui bootstrap/fixtures/gas_only_browser_gui.spark \
  "requires --live"
check_fail gas_only_browser_nosession \
  bootstrap/fixtures/gas_only_browser_nosession.spark \
  "session required"
check_fail gas_only_browser_cdp bootstrap/fixtures/gas_only_browser_cdp.spark \
  "GAS-only"
check_fail gas_only_browser_show \
  bootstrap/fixtures/gas_only_browser_show.spark \
  "cannot open image|PPM/RGB"

check browser_show bootstrap/fixtures/browser_show.spark \
  '"op":"show","ok":true,"mode":"dry-run"'
check browser_show_display bootstrap/fixtures/browser_show.spark \
  '"display":false'
check browser_show_path bootstrap/fixtures/browser_show.spark \
  'examples/fixtures/browser/engine_show.ppm'
check browser_show_print bootstrap/fixtures/browser_show.spark \
  '\[print\] {"op":"show"'
check_browser_show_json() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/browser_show.spark \
    2>&1)" || {
    echo "FAIL bootstrap_browser_show_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/browser/show.json ]]; then
    echo "FAIL bootstrap_browser_show_file: missing show.json"
    fail=1
    return
  fi
  if grep -qE '"op":"show"' out/browser/show.json &&
     grep -qE '"mode":"dry-run"' out/browser/show.json &&
     grep -qE '"display":false' out/browser/show.json &&
     grep -qE 'engine_show.ppm' out/browser/show.json &&
     grep -qE '"format":"ppm"' out/browser/show.json; then
    echo "PASS bootstrap_browser_show_file"
  else
    echo "FAIL bootstrap_browser_show_file: show.json fields"
    cat out/browser/show.json
    fail=1
  fi
}
check_browser_show_json

check browser_flags bootstrap/fixtures/browser_flags.spark \
  '"op":"flags","disable_quic":false'
check browser_flags_override bootstrap/fixtures/browser_flags.spark \
  'mitm disable_quic on'
check browser_flags_entrypoint bootstrap/fixtures/browser_flags.spark \
  '"entrypoint":"spark language"'
check browser_flags_print bootstrap/fixtures/browser_flags.spark \
  '\[print\] {"op":"flags"'

check_fail gas_only_browser_render \
  bootstrap/fixtures/gas_only_browser_render.spark \
  "needs DOM|engine parse first"

check browser_render bootstrap/fixtures/browser_render.spark \
  '"op":"engine.render","ok":true'
check browser_render_stages bootstrap/fixtures/browser_render.spark \
  '"stages":\["layout","paint_boxes","show"\]'
check browser_render_prefix bootstrap/fixtures/browser_render.spark \
  '\[browser\]'
check browser_render_print bootstrap/fixtures/browser_render.spark \
  '\[print\] {"op":"engine.render"'
check_browser_render_files() {
  local out
  out="$(./spark-bootstrap --dry-run \
    bootstrap/fixtures/browser_render.spark 2>&1)" || {
    echo "FAIL bootstrap_browser_render_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/browser/engine/render.json ]]; then
    echo "FAIL bootstrap_browser_render_file: missing render.json"
    fail=1
    return
  fi
  if [[ ! -f out/engine/pipeline.ppm ]]; then
    echo "FAIL bootstrap_browser_render_file: missing pipeline.ppm"
    fail=1
    return
  fi
  if grep -qE '"op":"engine.render"' out/browser/engine/render.json &&
     grep -qE '"abi":"SePaintBox"' out/browser/engine/render.json; then
    echo "PASS bootstrap_browser_render_file"
  else
    echo "FAIL bootstrap_browser_render_file: render.json fields"
    cat out/browser/engine/render.json
    fail=1
  fi
}
check_browser_render_files

check mitm_enable bootstrap/fixtures/mitm_enable.spark \
  '"op":"enable","ok":true,"proxy":"127.0.0.1:8877"'
check mitm_enable_mode bootstrap/fixtures/mitm_enable.spark \
  '"mode":"dry-run-session"'
check mitm_enable_print bootstrap/fixtures/mitm_enable.spark \
  '\[print\] {"op":"enable","ok":true'

check_fail gas_only_mitm_live bootstrap/fixtures/gas_only_mitm_live.spark \
  "dry-only"
check_fail gas_only_mitm_smoke bootstrap/fixtures/gas_only_mitm_smoke.spark \
  "GAS-only"

check engine_fetch bootstrap/fixtures/engine_fetch.spark \
  '"op":"engine.fetch","ok":true,"source":"file"'
check engine_fetch_transport bootstrap/fixtures/engine_fetch.spark \
  '"transport":"open"'
check engine_fetch_bytes bootstrap/fixtures/engine_fetch.spark \
  '"bytes":148'
check engine_fetch_print bootstrap/fixtures/engine_fetch.spark \
  '\[print\] {"op":"engine.fetch","ok":true'

check engine_fetch_parse bootstrap/fixtures/engine_fetch_parse.spark \
  '"op":"engine.fetch_parse","ok":true'
check engine_fetch_parse_body bootstrap/fixtures/engine_fetch_parse.spark \
  '"body":"out/engine/body.bin"'
check engine_fetch_parse_next bootstrap/fixtures/engine_fetch_parse.spark \
  '"next":"engine.parse"'
check engine_fetch_parse_nnodes bootstrap/fixtures/engine_fetch_parse.spark \
  '"nnodes":7'
check engine_fetch_parse_arrow bootstrap/fixtures/engine_fetch_parse.spark \
  '-> \{"op":"engine.fetch_parse"'
check engine_fetch_parse_print bootstrap/fixtures/engine_fetch_parse.spark \
  '\[print\] {"op":"engine.fetch","ok":true'

check engine_parse bootstrap/fixtures/engine_parse.spark \
  '"op":"engine.parse","ok":true,"engine":"spark-asm-html"'
check engine_parse_nnodes bootstrap/fixtures/engine_parse.spark \
  '"nnodes":28'
check engine_parse_body bootstrap/fixtures/engine_parse.spark \
  '"body":4'
check engine_parse_table bootstrap/fixtures/engine_parse.spark \
  '"table":1,"tr":1,"td":1,"th":1'
check engine_parse_print bootstrap/fixtures/engine_parse.spark \
  '\[print\] {"op":"engine.parse","ok":true'

check engine_css bootstrap/fixtures/engine_css.spark \
  'out/browser/engine/css.json'
check engine_css_print bootstrap/fixtures/engine_css.spark \
  '\[print\] out/browser/engine/css.json'
# css.json file fields (stdout only has path)
check_css_json() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_css.spark 2>&1)" || {
    echo "FAIL bootstrap_engine_css_file: exit non-zero"
    fail=1
    return
  }
  if [[ ! -f out/browser/engine/css.json ]]; then
    echo "FAIL bootstrap_engine_css_file: missing css.json"
    fail=1
    return
  fi
  if grep -qE '"op":"engine.css"' out/browser/engine/css.json &&
     grep -qE '"ok":true' out/browser/engine/css.json &&
     grep -qE '"font_size":20' out/browser/engine/css.json &&
     grep -qE 'c80000' out/browser/engine/css.json &&
     grep -qE '"border_width":2' out/browser/engine/css.json &&
     grep -qE '"padding":6' out/browser/engine/css.json &&
     grep -qE '"background_color":"00c800"' \
       out/browser/engine/css.json &&
     grep -qE '"width":120' out/browser/engine/css.json &&
     grep -qE '"height":48' out/browser/engine/css.json &&
     grep -qE '"max_height":40' out/browser/engine/css.json &&
     grep -qE '"min_height":56' out/browser/engine/css.json &&
     grep -qE '"max_width":80' out/browser/engine/css.json &&
     grep -qE '"min_width":200' out/browser/engine/css.json &&
     grep -qE '"border_color":"c80000"' out/browser/engine/css.json &&
     grep -qE '"border_style":1' out/browser/engine/css.json &&
     grep -qE '"border_style":0' out/browser/engine/css.json &&
     grep -qE '"visibility":1' out/browser/engine/css.json &&
     grep -qE '"opacity":0' out/browser/engine/css.json &&
     grep -qE '"flags":68568' out/browser/engine/css.json &&
     grep -qE '"flags":35800' out/browser/engine/css.json &&
     grep -qE '"flags":3032' out/browser/engine/css.json &&
     grep -qE '"background_color":"transparent"' \
       out/browser/engine/css.json &&
     grep -qE '"color":"ffff00"' out/browser/engine/css.json &&
     grep -qE '"color":"transparent"' out/browser/engine/css.json &&
     grep -qE '"color":"00ffff"' out/browser/engine/css.json &&
     grep -qE '"color":"ff00ff"' out/browser/engine/css.json; then
    echo "PASS bootstrap_engine_css_file"
  else
    echo "FAIL bootstrap_engine_css_file: css.json missing fields"
    fail=1
  fi
}
check_css_json

check engine_layout bootstrap/fixtures/engine_layout.spark \
  'out/browser/engine/layout.json'
check engine_layout_print bootstrap/fixtures/engine_layout.spark \
  '\[print\] out/browser/engine/layout.json'
check_layout_json() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_layout.spark 2>&1)" || {
    echo "FAIL bootstrap_engine_layout_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/browser/engine/layout.json ]]; then
    echo "FAIL bootstrap_engine_layout_file: missing layout.json"
    fail=1
    return
  fi
  if grep -qE '"op":"engine.layout"' out/browser/engine/layout.json &&
     grep -qE '"ok":true' out/browser/engine/layout.json &&
     grep -qE '"abi":"SePaintBox"' out/browser/engine/layout.json &&
     grep -qE '"box_stride":36' out/browser/engine/layout.json &&
     grep -qE '"box_count":21' out/browser/engine/layout.json; then
    echo "PASS bootstrap_engine_layout_file"
  else
    echo "FAIL bootstrap_engine_layout_file: layout.json missing fields"
    cat out/browser/engine/layout.json
    fail=1
  fi
  if echo "$out" | grep -qE '"op":"layout.table"'; then
    echo "PASS bootstrap_engine_layout_table"
  else
    echo "FAIL bootstrap_engine_layout_table: missing layout.table"
    fail=1
  fi
}
check_layout_json

check engine_paint bootstrap/fixtures/engine_paint.spark \
  'out/engine/pipeline.ppm'
check engine_paint_json bootstrap/fixtures/engine_paint.spark \
  '"op":"engine.paint","ok":true,"mode":"boxes"'
check engine_paint_print bootstrap/fixtures/engine_paint.spark \
  '\[print\] out/engine/pipeline.ppm'
check_paint_ppm() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_paint.spark 2>&1)" || {
    echo "FAIL bootstrap_engine_paint_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/engine/pipeline.ppm ]]; then
    echo "FAIL bootstrap_engine_paint_file: missing pipeline.ppm"
    fail=1
    return
  fi
  if head -c 2 out/engine/pipeline.ppm | grep -q P6 &&
     test "$(wc -c < out/engine/pipeline.ppm)" -gt 1000 &&
     echo "$out" | grep -qE '"box_count":21'; then
    echo "PASS bootstrap_engine_paint_file"
  else
    echo "FAIL bootstrap_engine_paint_file: PPM/json"
    fail=1
  fi
}
check_paint_ppm

check engine_show bootstrap/fixtures/engine_show.spark \
  '"op":"show","ok":true,"mode":"dry-run"'
check engine_show_path bootstrap/fixtures/engine_show.spark \
  'out/engine/pipeline.ppm'
check engine_show_print bootstrap/fixtures/engine_show.spark \
  '\[print\] {"op":"show"'
check_show_json() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_show.spark 2>&1)" || {
    echo "FAIL bootstrap_engine_show_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/browser/show.json ]]; then
    echo "FAIL bootstrap_engine_show_file: missing show.json"
    fail=1
    return
  fi
  if grep -qE '"op":"show"' out/browser/show.json &&
     grep -qE '"ok":true' out/browser/show.json &&
     grep -qE '"mode":"dry-run"' out/browser/show.json &&
     grep -qE '"display":false' out/browser/show.json &&
     grep -qE 'out/engine/pipeline.ppm' out/browser/show.json &&
     grep -qE '"format":"ppm"' out/browser/show.json; then
    echo "PASS bootstrap_engine_show_file"
  else
    echo "FAIL bootstrap_engine_show_file: show.json missing fields"
    cat out/browser/show.json
    fail=1
  fi
}
check_show_json

check engine_render bootstrap/fixtures/engine_render.spark \
  '"op":"engine.render","ok":true'
check engine_render_stages bootstrap/fixtures/engine_render.spark \
  '"stages":\["layout","paint_boxes","show"\]'
check engine_render_print bootstrap/fixtures/engine_render.spark \
  '\[print\] {"op":"engine.render"'
check_render_json() {
  local out
  out="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_render.spark 2>&1)" || {
    echo "FAIL bootstrap_engine_render_file: exit non-zero"
    echo "$out" | head -20
    fail=1
    return
  }
  if [[ ! -f out/browser/engine/render.json ]]; then
    echo "FAIL bootstrap_engine_render_file: missing render.json"
    fail=1
    return
  fi
  if [[ ! -f out/engine/pipeline.ppm ]]; then
    echo "FAIL bootstrap_engine_render_file: missing pipeline.ppm"
    fail=1
    return
  fi
  if [[ ! -f out/browser/show.json ]]; then
    echo "FAIL bootstrap_engine_render_file: missing show.json"
    fail=1
    return
  fi
  if grep -qE '"op":"engine.render"' out/browser/engine/render.json &&
     grep -qE '"ok":true' out/browser/engine/render.json &&
     grep -qE 'paint_boxes' out/browser/engine/render.json &&
     grep -qE '"abi":"SePaintBox"' out/browser/engine/render.json &&
     grep -qE 'out/engine/pipeline.ppm' out/browser/engine/render.json &&
     grep -qE '"display":false' out/browser/show.json; then
    echo "PASS bootstrap_engine_render_file"
  else
    echo "FAIL bootstrap_engine_render_file: render/show fields"
    cat out/browser/engine/render.json
    fail=1
  fi
}
check_render_json

check_fail gas_only_engine_https bootstrap/fixtures/gas_only_engine_https.spark \
  "https blocked by default|Pass --allow-net|spark-engine-fetch-tls"
check_fail gas_only_engine_http bootstrap/fixtures/gas_only_engine_http.spark \
  "Pass --allow-net|blocked by default"
check_fail gas_only_engine_live bootstrap/fixtures/gas_only_engine_live.spark \
  "dry-only"
check_fail gas_only_engine_css bootstrap/fixtures/gas_only_engine_css.spark \
  "needs DOM|engine parse first"
check_fail gas_only_engine_layout \
  bootstrap/fixtures/gas_only_engine_layout.spark \
  "needs DOM|engine parse first|layout fixture"
check_fail gas_only_engine_paint \
  bootstrap/fixtures/gas_only_engine_paint.spark \
  "needs layout|0 boxes"
check_fail gas_only_engine_show \
  bootstrap/fixtures/gas_only_engine_show.spark \
  "cannot open image|PPM/RGB"
check_fail gas_only_engine_render \
  bootstrap/fixtures/gas_only_engine_render.spark \
  "needs DOM|engine parse first|no fixture"
check_fail gas_only_engine_parse_missing \
  bootstrap/fixtures/gas_only_engine_parse_missing.spark \
  "cannot open HTML path"
check_fail gas_only_engine_fetch_parse \
  bootstrap/fixtures/gas_only_engine_fetch_parse.spark \
  "https blocked by default|Pass --allow-net|spark-engine-fetch-tls"

# Optional parity vs GAS for classify + tools (harness, not product)
if [[ -x ./spark ]]; then
  gas_c="$(./spark --dry-run bootstrap/fixtures/classify_intent.spark 2>&1 || true)"
  boot_c="$(./spark-bootstrap --dry-run bootstrap/fixtures/classify_intent.spark 2>&1 || true)"
  if echo "$gas_c" | grep -q '"label":"support","confidence":0.91' &&
     echo "$boot_c" | grep -q '"label":"support","confidence":0.91' &&
     echo "$gas_c" | grep -q '"label":"sales","confidence":0.88' &&
     echo "$boot_c" | grep -q '"label":"sales","confidence":0.88'; then
    echo "PASS bootstrap_classify_parity"
  else
    echo "FAIL bootstrap_classify_parity"
    fail=1
  fi
  gas_t="$(./spark --dry-run bootstrap/fixtures/tool_agent.spark 2>&1 || true)"
  boot_t="$(./spark-bootstrap --dry-run bootstrap/fixtures/tool_agent.spark 2>&1 || true)"
  if echo "$gas_t" | grep -q '\[tool:weather\] stub:local' &&
     echo "$boot_t" | grep -q '\[tool:weather\] stub:local'; then
    echo "PASS bootstrap_tool_parity"
  else
    echo "FAIL bootstrap_tool_parity"
    fail=1
  fi
  gas_r="$(./spark --dry-run bootstrap/fixtures/review_path.spark 2>&1 || true)"
  boot_r="$(./spark-bootstrap --dry-run bootstrap/fixtures/review_path.spark 2>&1 || true)"
  if echo "$gas_r" | grep -q '"suggested_level":"higher"' &&
     echo "$boot_r" | grep -q '"suggested_level":"higher"' &&
     echo "$gas_r" | grep -q 'never eval web JS' &&
     echo "$boot_r" | grep -q 'never eval web JS'; then
    echo "PASS bootstrap_review_parity"
  else
    echo "FAIL bootstrap_review_parity"
    fail=1
  fi
  gas_v="$(./spark --dry-run bootstrap/fixtures/voice_session.spark 2>&1 || true)"
  boot_v="$(./spark-bootstrap --dry-run bootstrap/fixtures/voice_session.spark 2>&1 || true)"
  if echo "$gas_v" | grep -q '\[voice\] session' &&
     echo "$boot_v" | grep -q '\[voice\] session' &&
     echo "$gas_v" | grep -q '\[listen\] My account is locked' &&
     echo "$boot_v" | grep -q '\[listen\] My account is locked' &&
     echo "$gas_v" | grep -q 'Happy to help' &&
     echo "$boot_v" | grep -q 'Happy to help'; then
    echo "PASS bootstrap_voice_parity"
  else
    echo "FAIL bootstrap_voice_parity"
    fail=1
  fi
  gas_b="$(./spark --dry-run bootstrap/fixtures/browser_run_goto.spark 2>&1 || true)"
  boot_b="$(./spark-bootstrap --dry-run bootstrap/fixtures/browser_run_goto.spark 2>&1 || true)"
  if echo "$gas_b" | grep -q '"op":"run","ok":true,"mode":"dry-run"' &&
     echo "$boot_b" | grep -q '"op":"run","ok":true,"mode":"dry-run"' &&
     echo "$gas_b" | grep -q '"op":"goto","ok":true,"url":"https://example.com/"' &&
     echo "$boot_b" | grep -q '"op":"goto","ok":true,"url":"https://example.com/"' &&
     echo "$gas_b" | grep -q '\[print\] https://example.com/' &&
     echo "$boot_b" | grep -q '\[print\] https://example.com/'; then
    echo "PASS bootstrap_browser_parity"
  else
    echo "FAIL bootstrap_browser_parity"
    fail=1
  fi
  # show.json byte-equal for fixture PPM browser show
  ./spark --dry-run bootstrap/fixtures/browser_show.spark \
    >/dev/null 2>&1 || true
  cp -a out/browser/show.json /tmp/boot_parity_gas_br_show.json
  ./spark-bootstrap --dry-run bootstrap/fixtures/browser_show.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_br_show.json out/browser/show.json; then
    echo "PASS bootstrap_browser_show_parity"
  else
    echo "FAIL bootstrap_browser_show_parity (show.json != GAS)"
    echo "GAS:"; cat /tmp/boot_parity_gas_br_show.json; echo
    echo "BOOT:"; cat out/browser/show.json; echo
    fail=1
  fi
  gas_bf="$(./spark --dry-run bootstrap/fixtures/browser_flags.spark \
    2>&1 || true)"
  boot_bf="$(./spark-bootstrap --dry-run \
    bootstrap/fixtures/browser_flags.spark 2>&1 || true)"
  if echo "$gas_bf" | grep -q '"op":"flags","disable_quic":false' &&
     echo "$boot_bf" | grep -q '"op":"flags","disable_quic":false' &&
     echo "$gas_bf" | grep -q '"entrypoint":"spark language"' &&
     echo "$boot_bf" | grep -q '"entrypoint":"spark language"' &&
     echo "$gas_bf" | grep -q 'mitm disable_quic on' &&
     echo "$boot_bf" | grep -q 'mitm disable_quic on'; then
    echo "PASS bootstrap_browser_flags_parity"
  else
    echo "FAIL bootstrap_browser_flags_parity"
    echo "GAS: $gas_bf" | head -c 400; echo
    echo "BOOT: $boot_bf" | head -c 400; echo
    fail=1
  fi
  # browser engine render: render.json + ppm byte-equal vs GAS
  ./spark --dry-run bootstrap/fixtures/browser_render.spark \
    >/dev/null 2>&1 || true
  cp -a out/browser/engine/render.json \
    /tmp/boot_parity_gas_br_render.json
  cp -a out/engine/pipeline.ppm /tmp/boot_parity_gas_br_render.ppm
  ./spark-bootstrap --dry-run bootstrap/fixtures/browser_render.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_br_render.json \
        out/browser/engine/render.json &&
     cmp -s /tmp/boot_parity_gas_br_render.ppm out/engine/pipeline.ppm
  then
    echo "PASS bootstrap_browser_render_parity"
  else
    echo "FAIL bootstrap_browser_render_parity (render/ppm != GAS)"
    echo "GAS:"; cat /tmp/boot_parity_gas_br_render.json; echo
    echo "BOOT:"; cat out/browser/engine/render.json; echo
    fail=1
  fi
  gas_m="$(./spark --dry-run bootstrap/fixtures/mitm_enable.spark 2>&1 || true)"
  boot_m="$(./spark-bootstrap --dry-run bootstrap/fixtures/mitm_enable.spark 2>&1 || true)"
  if echo "$gas_m" | grep -q '"op":"enable","ok":true' &&
     echo "$boot_m" | grep -q '"op":"enable","ok":true' &&
     echo "$gas_m" | grep -q '"mode":"dry-run-session"' &&
     echo "$boot_m" | grep -q '"mode":"dry-run-session"' &&
     echo "$gas_m" | grep -q '"owner":"spark-mitm-h2"' &&
     echo "$boot_m" | grep -q '"owner":"spark-mitm-h2"' &&
     echo "$gas_m" | grep -q '\[print\] {"op":"enable"' &&
     echo "$boot_m" | grep -q '\[print\] {"op":"enable"'; then
    echo "PASS bootstrap_mitm_parity"
  else
    echo "FAIL bootstrap_mitm_parity"
    fail=1
  fi
  gas_e="$(./spark --dry-run bootstrap/fixtures/engine_fetch.spark 2>&1 || true)"
  boot_e="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_fetch.spark 2>&1 || true)"
  if echo "$gas_e" | grep -q '"op":"engine.fetch","ok":true' &&
     echo "$boot_e" | grep -q '"op":"engine.fetch","ok":true' &&
     echo "$gas_e" | grep -q '"source":"file"' &&
     echo "$boot_e" | grep -q '"source":"file"' &&
     echo "$gas_e" | grep -q '"transport":"open"' &&
     echo "$boot_e" | grep -q '"transport":"open"' &&
     echo "$gas_e" | grep -q '"bytes":148' &&
     echo "$boot_e" | grep -q '"bytes":148' &&
     echo "$gas_e" | grep -q '\[print\] {"op":"engine.fetch"' &&
     echo "$boot_e" | grep -q '\[print\] {"op":"engine.fetch"'; then
    echo "PASS bootstrap_engine_fetch_parity"
  else
    echo "FAIL bootstrap_engine_fetch_parity"
    fail=1
  fi
  gas_fp="$(./spark --dry-run bootstrap/fixtures/engine_fetch_parse.spark \
    2>&1 || true)"
  boot_fp="$(./spark-bootstrap --dry-run \
    bootstrap/fixtures/engine_fetch_parse.spark 2>&1 || true)"
  if echo "$gas_fp" | grep -q '"op":"engine.fetch_parse","ok":true' &&
     echo "$boot_fp" | grep -q '"op":"engine.fetch_parse","ok":true' &&
     echo "$gas_fp" | grep -q '"nnodes":7' &&
     echo "$boot_fp" | grep -q '"nnodes":7' &&
     echo "$gas_fp" | grep -q '"bytes":148' &&
     echo "$boot_fp" | grep -q '"bytes":148' &&
     echo "$gas_fp" | grep -q '\[print\] {"op":"engine.fetch","ok":true' &&
     echo "$boot_fp" | grep -q '\[print\] {"op":"engine.fetch","ok":true'; then
    echo "PASS bootstrap_engine_fetch_parse_parity"
  else
    echo "FAIL bootstrap_engine_fetch_parse_parity"
    fail=1
  fi
  gas_p="$(./spark --dry-run bootstrap/fixtures/engine_parse.spark 2>&1 || true)"
  boot_p="$(./spark-bootstrap --dry-run bootstrap/fixtures/engine_parse.spark 2>&1 || true)"
  if echo "$gas_p" | grep -q '"op":"engine.parse","ok":true' &&
     echo "$boot_p" | grep -q '"op":"engine.parse","ok":true' &&
     echo "$gas_p" | grep -q '"engine":"spark-asm-html"' &&
     echo "$boot_p" | grep -q '"engine":"spark-asm-html"' &&
     echo "$gas_p" | grep -q '"nnodes":28' &&
     echo "$boot_p" | grep -q '"nnodes":28' &&
     echo "$gas_p" | grep -q '"body":4' &&
     echo "$boot_p" | grep -q '"body":4' &&
     echo "$gas_p" | grep -q '\[print\] {"op":"engine.parse"' &&
     echo "$boot_p" | grep -q '\[print\] {"op":"engine.parse"'; then
    echo "PASS bootstrap_engine_parse_parity"
  else
    echo "FAIL bootstrap_engine_parse_parity"
    fail=1
  fi
  # css.json byte-equal for style_basic fixture
  ./spark --dry-run examples/engine_css.spark >/dev/null 2>&1 || true
  cp -a out/browser/engine/css.json /tmp/boot_parity_gas_css.json
  ./spark-bootstrap --dry-run bootstrap/fixtures/engine_css.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_css.json out/browser/engine/css.json; then
    echo "PASS bootstrap_engine_css_parity"
  else
    echo "FAIL bootstrap_engine_css_parity (css.json != GAS)"
    fail=1
  fi
  # layout.json matches GAS engine.layout spine (style_basic)
  gas_l="$(./spark --dry-run bootstrap/fixtures/engine_layout.spark 2>&1 || true)"
  ./spark-bootstrap --dry-run bootstrap/fixtures/engine_layout.spark \
    >/dev/null 2>&1 || true
  boot_lj="$(cat out/browser/engine/layout.json 2>/dev/null || true)"
  if echo "$gas_l" | grep -qE '"op":"engine.layout","ok":true' &&
     echo "$gas_l" | grep -qE '"box_count":21' &&
     echo "$boot_lj" | grep -qE '"op":"engine.layout","ok":true' &&
     echo "$boot_lj" | grep -qE '"box_count":21' &&
     echo "$boot_lj" | grep -qE '"abi":"SePaintBox"' &&
     echo "$gas_l" | grep -qE '"op":"layout.table"' &&
     echo "$boot_lj" | grep -qE '"box_stride":36'; then
    echo "PASS bootstrap_engine_layout_parity"
  else
    echo "FAIL bootstrap_engine_layout_parity (layout.json != GAS)"
    echo "GAS: $gas_l" | head -c 400; echo
    echo "BOOT layout.json: $boot_lj"
    fail=1
  fi
  # pipeline.ppm byte-equal for style_basic paint boxes
  ./spark --dry-run bootstrap/fixtures/engine_paint.spark \
    >/dev/null 2>&1 || true
  cp -a out/engine/pipeline.ppm /tmp/boot_parity_gas_paint.ppm
  ./spark-bootstrap --dry-run bootstrap/fixtures/engine_paint.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_paint.ppm out/engine/pipeline.ppm; then
    echo "PASS bootstrap_engine_paint_parity"
  else
    echo "FAIL bootstrap_engine_paint_parity (pipeline.ppm != GAS)"
    ls -la /tmp/boot_parity_gas_paint.ppm out/engine/pipeline.ppm
    fail=1
  fi
  # show.json byte-equal for style_basic paint → show
  ./spark --dry-run bootstrap/fixtures/engine_show.spark \
    >/dev/null 2>&1 || true
  cp -a out/browser/show.json /tmp/boot_parity_gas_show.json
  ./spark-bootstrap --dry-run bootstrap/fixtures/engine_show.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_show.json out/browser/show.json; then
    echo "PASS bootstrap_engine_show_parity"
  else
    echo "FAIL bootstrap_engine_show_parity (show.json != GAS)"
    echo "GAS:"; cat /tmp/boot_parity_gas_show.json; echo
    echo "BOOT:"; cat out/browser/show.json; echo
    fail=1
  fi
  # render.json + pipeline.ppm byte-equal for style_basic render
  ./spark --dry-run bootstrap/fixtures/engine_render.spark \
    >/dev/null 2>&1 || true
  cp -a out/browser/engine/render.json /tmp/boot_parity_gas_render.json
  cp -a out/engine/pipeline.ppm /tmp/boot_parity_gas_render.ppm
  ./spark-bootstrap --dry-run bootstrap/fixtures/engine_render.spark \
    >/dev/null 2>&1 || true
  if cmp -s /tmp/boot_parity_gas_render.json \
        out/browser/engine/render.json &&
     cmp -s /tmp/boot_parity_gas_render.ppm out/engine/pipeline.ppm; then
    echo "PASS bootstrap_engine_render_parity"
  else
    echo "FAIL bootstrap_engine_render_parity (render/ppm != GAS)"
    echo "GAS:"; cat /tmp/boot_parity_gas_render.json; echo
    echo "BOOT:"; cat out/browser/engine/render.json; echo
    ls -la /tmp/boot_parity_gas_render.ppm out/engine/pipeline.ppm
    fail=1
  fi
else
  echo "SKIP bootstrap_classify_parity (no ./spark)"
  echo "SKIP bootstrap_tool_parity (no ./spark)"
  echo "SKIP bootstrap_review_parity (no ./spark)"
  echo "SKIP bootstrap_voice_parity (no ./spark)"
  echo "SKIP bootstrap_browser_parity (no ./spark)"
  echo "SKIP bootstrap_browser_show_parity (no ./spark)"
  echo "SKIP bootstrap_browser_flags_parity (no ./spark)"
  echo "SKIP bootstrap_browser_render_parity (no ./spark)"
  echo "SKIP bootstrap_mitm_parity (no ./spark)"
  echo "SKIP bootstrap_engine_fetch_parity (no ./spark)"
  echo "SKIP bootstrap_engine_fetch_parse_parity (no ./spark)"
  echo "SKIP bootstrap_engine_parse_parity (no ./spark)"
  echo "SKIP bootstrap_engine_css_parity (no ./spark)"
  echo "SKIP bootstrap_engine_layout_parity (no ./spark)"
  echo "SKIP bootstrap_engine_paint_parity (no ./spark)"
  echo "SKIP bootstrap_engine_show_parity (no ./spark)"
  echo "SKIP bootstrap_engine_render_parity (no ./spark)"
fi

if [[ -x ./spark ]]; then
  gas="$(./spark --dry-run examples/hello.spark 2>&1 || true)"
  boot="$(./spark-bootstrap --dry-run examples/hello.spark 2>&1 || true)"
  if echo "$gas" | grep -q "Gravity pulls masses together" &&
     echo "$boot" | grep -q "Gravity pulls masses together"; then
    echo "PASS bootstrap_hello_parity_reply"
  else
    echo "FAIL bootstrap_hello_parity_reply"
    fail=1
  fi
else
  echo "SKIP bootstrap_hello_parity_reply (no ./spark)"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "bootstrap tests FAILED"
  exit 1
fi
echo "bootstrap tests OK"
