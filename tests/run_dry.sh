#!/usr/bin/env bash
# Dry-run tests — asm VM; assert real behaviors + fail-loud / questions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make -s spark

fail=0
check() {
  local name="$1" file="$2" needle="$3"
  out="$(./spark --dry-run "$file" 2>&1)" || {
    echo "FAIL $name: exit non-zero"
    fail=1
    return
  }
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing '$needle'"
    echo "$out" | head -20
    fail=1
  fi
}

# Expect non-zero + needle (questions / fail-loud)
check_fail() {
  local name="$1" file="$2" needle="$3"
  set +e
  out="$(./spark --dry-run "$file" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL $name: expected non-zero exit"
    fail=1
    return
  fi
  if echo "$out" | grep -qE "$needle"; then
    echo "PASS $name"
  else
    echo "FAIL $name: missing '$needle' (rc=$rc)"
    echo "$out" | head -20
    fail=1
  fi
}

check hello examples/hello.spark "Gravity"
check hello_sugar examples/hello_sugar.spark "Gravity"
check dx_showcase examples/dx_showcase.spark "Resumen"
check classify examples/classify_intent.spark '"label":"support"'

# IDE core — open/save/run dry (asm buffer; fork ./spark --dry-run)
check ide_open examples/ide_hello.spark '"op":"ide.open"'
check ide_buffer examples/ide_hello.spark '"op":"ide.buffer"'
check ide_save examples/ide_hello.spark '"op":"ide.save"'
check ide_run examples/ide_hello.spark '"op":"ide.run"'
check ide_run_mode examples/ide_hello.spark '"mode":"dry-run"'
check ide_run_child examples/ide_hello.spark "Gravity"
# ide save dry proof — file written + size + sha256 match source
if test -f out/ide/ide_hello_saved.spark \
  && grep -q 'Explain gravity' out/ide/ide_hello_saved.spark \
  && test "$(wc -c < out/ide/ide_hello_saved.spark)" \
    -eq "$(wc -c < examples/hello.spark)" \
  && test "$(sha256sum out/ide/ide_hello_saved.spark | awk '{print $1}')" \
    = "$(sha256sum examples/hello.spark | awk '{print $1}')"; then
  echo "PASS ide_save_file"
else
  echo "FAIL ide_save_file"
  fail=1
fi
# IDE open→save→reopen e2e — round-trip buffer + checksum proof
check ide_save_reopen_save examples/ide_save_reopen.spark \
  '"op":"ide.save"'
check ide_save_reopen_open examples/ide_save_reopen.spark \
  '"op":"ide.open"'
check ide_save_reopen_buffer examples/ide_save_reopen.spark \
  '"op":"ide.buffer"'
check ide_save_reopen_body examples/ide_save_reopen.spark \
  "Explain gravity"
if test -f out/ide/ide_saved_rt.spark \
  && test "$(wc -c < out/ide/ide_saved_rt.spark)" \
    -eq "$(wc -c < examples/hello.spark)" \
  && test "$(sha256sum out/ide/ide_saved_rt.spark | awk '{print $1}')" \
    = "$(sha256sum examples/hello.spark | awk '{print $1}')"; then
  echo "PASS ide_save_reopen_checksum"
else
  echo "FAIL ide_save_reopen_checksum"
  fail=1
fi
# E2E: open → paint PPM (P6) → run
test -f out/ide/editor.ppm \
  && head -c 2 out/ide/editor.ppm | grep -q P6 \
  && test "$(wc -c < out/ide/editor.ppm)" -gt 1000 \
  && echo "PASS ide_open_paint_ppm" || {
  echo "FAIL ide_open_paint_ppm"
  fail=1
}
# Status strip (top 16px) after open — real path glyphs in editor.ppm
if python3 - out/ide/editor.ppm <<'PY'
import sys
p = open(sys.argv[1], "rb").read()
assert p.startswith(b"P6\n"), p[:16]
_, dims, _, body = p.split(b"\n", 3)
w, h = map(int, dims.split())
assert w == 320 and h == 160
status_h = 16
bright = 0
for y in range(status_h):
    for x in range(w):
        i = (y * w + x) * 3
        if body[i] > 60 or body[i + 1] > 100 or body[i + 2] > 100:
            bright += 1
assert bright > 20, f"status strip too dim ({bright})"
PY
then
  echo "PASS ide_status_strip_ppm"
else
  echo "FAIL ide_status_strip_ppm"
  fail=1
fi
# IDE show — after paint, real engine_window_show (dry, no X11)
check ide_show_op examples/ide_show.spark '"op":"ide.show"'
check ide_show_via examples/ide_show.spark 'spark-engine-show'
check ide_show_engine examples/ide_show.spark '"op":"show"'
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_show_json" || {
  echo "FAIL ide_show_json"
  fail=1
}
# IDE run+show e2e — open → fork run → engine show (browser wire)
check ide_run_show_op examples/ide_run_show.spark '"op":"ide.run"'
check ide_run_show_show examples/ide_run_show.spark '"op":"ide.show"'
check ide_run_show_engine examples/ide_run_show.spark '"op":"show"'
check ide_run_show_child examples/ide_run_show.spark "Gravity"
check ide_run_show_via examples/ide_run_show.spark 'spark-engine-show'
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_run_show_json" || {
  echo "FAIL ide_run_show_json"
  fail=1
}
# IDE ask+show e2e — open → ask (AI strip) → engine show
check ide_ask_show_ask examples/ide_ask_show.spark '"op":"ide.ask"'
check ide_ask_show_show examples/ide_ask_show.spark '"op":"ide.show"'
check ide_ask_show_engine examples/ide_ask_show.spark '"op":"show"'
check ide_ask_show_fixture examples/ide_ask_show.spark "Gravity"
check ide_ask_show_via examples/ide_ask_show.spark 'spark-engine-show'
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_ask_show_json" || {
  echo "FAIL ide_ask_show_json"
  fail=1
}
# IDE keymap / command loop (dry JSON traces; open uses real read)
check ide_keys_loop examples/ide_keys.spark '"op":"ide.keys"'
check ide_keys_open examples/ide_keys.spark '"cmd":"open"'
check ide_keys_show examples/ide_keys.spark '"cmd":"show"'
check ide_keys_save examples/ide_keys.spark '"cmd":"save"'
check ide_keys_run examples/ide_keys.spark '"cmd":"run"'
check ide_keys_quit examples/ide_keys.spark '"cmd":"quit"'
check ide_keys_drynote examples/ide_keys.spark 'trace only'
test -f out/ide/keys_trace.jsonl \
  && grep -q '"op":"ide.keys"' out/ide/keys_trace.jsonl \
  && echo "PASS ide_keys_trace_file" || {
  echo "FAIL ide_keys_trace_file"
  fail=1
}
# Proven keymap save (`s`) — script token + ide key save (no invent)
check ide_keys_s_script examples/ide_keys_save.spark \
  '"cmd":"save".*"path":"examples/hello.spark"'
check ide_keys_s_open examples/ide_keys_save.spark '"cmd":"open"'
check ide_keys_s_quit examples/ide_keys_save.spark '"cmd":"quit"'
check ide_keys_s_drynote examples/ide_keys_save.spark \
  'no save write / no run fork'
# Script fixture must name token s (not invented key names)
grep -qE '^s$' examples/fixtures/ide/cmds_save.txt \
  && echo "PASS ide_keys_s_token" || {
  echo "FAIL ide_keys_s_token"
  fail=1
}
# Proven keymap run (`r`) — script token + ide key run (no invent)
check ide_keys_r_script examples/ide_keys_run.spark \
  '"cmd":"run".*"path":"examples/hello.spark"'
check ide_keys_r_open examples/ide_keys_run.spark '"cmd":"open"'
check ide_keys_r_quit examples/ide_keys_run.spark '"cmd":"quit"'
check ide_keys_r_drynote examples/ide_keys_run.spark \
  'no save write / no run fork'
# Script fixture must name token r (not invented key names)
grep -qE '^r$' examples/fixtures/ide/cmds_run.txt \
  && echo "PASS ide_keys_r_token" || {
  echo "FAIL ide_keys_r_token"
  fail=1
}
# Proven keymap quit (`q`) — script token + ide key quit (no invent)
check ide_keys_q_script examples/ide_keys_quit.spark \
  '"cmd":"quit".*"path":"examples/hello.spark"'
check ide_keys_q_open examples/ide_keys_quit.spark '"cmd":"open"'
check ide_keys_q_drynote examples/ide_keys_quit.spark \
  'no save write / no run fork'
# Script fixture must name token q (not invented key names)
grep -qE '^q$' examples/fixtures/ide/cmds_quit.txt \
  && echo "PASS ide_keys_q_token" || {
  echo "FAIL ide_keys_q_token"
  fail=1
}
# Proven keymap show (`w`) — script token + ide key show (no invent)
check ide_keys_w_script examples/ide_keys_show.spark \
  '"cmd":"show".*"path":"examples/hello.spark"'
check ide_keys_w_open examples/ide_keys_show.spark '"cmd":"open"'
check ide_keys_w_quit examples/ide_keys_show.spark '"cmd":"quit"'
check ide_keys_w_engine examples/ide_keys_show.spark '"op":"show"'
check ide_keys_w_drynote examples/ide_keys_show.spark \
  'no save write / no run fork'
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_keys_w_show_json" || {
  echo "FAIL ide_keys_w_show_json"
  fail=1
}
# Script fixture must name token w (not invented key names)
grep -qE '^w$' examples/fixtures/ide/cmds_show.txt \
  && echo "PASS ide_keys_w_token" || {
  echo "FAIL ide_keys_w_token"
  fail=1
}
# Proven keymap open (`o`) — script token + ide key open (no invent)
check ide_keys_o_script examples/ide_keys_open.spark \
  '"cmd":"open".*"path":"examples/hello.spark"'
check ide_keys_o_quit examples/ide_keys_open.spark '"cmd":"quit"'
check ide_keys_o_drynote examples/ide_keys_open.spark \
  'no save write / no run fork'
test -f out/ide/editor.ppm \
  && test "$(wc -c < out/ide/editor.ppm)" -gt 1000 \
  && echo "PASS ide_keys_o_paint_ppm" || {
  echo "FAIL ide_keys_o_paint_ppm"
  fail=1
}
# Script fixture must name token o (not invented key names)
grep -qE '^o ' examples/fixtures/ide/cmds_open.txt \
  && echo "PASS ide_keys_o_token" || {
  echo "FAIL ide_keys_o_token"
  fail=1
}
# Proven keymap long-form open/quit (aliases of o/q — not new tokens)
check ide_keys_long_open examples/ide_keys_long.spark \
  '"cmd":"open".*"path":"examples/hello.spark"'
check ide_keys_long_quit examples/ide_keys_long.spark \
  '"cmd":"quit".*"path":"examples/hello.spark"'
check ide_keys_long_drynote examples/ide_keys_long.spark \
  'no save write / no run fork'
test -f out/ide/editor.ppm \
  && test "$(wc -c < out/ide/editor.ppm)" -gt 1000 \
  && echo "PASS ide_keys_long_paint_ppm" || {
  echo "FAIL ide_keys_long_paint_ppm"
  fail=1
}
grep -qE '^open ' examples/fixtures/ide/cmds_long.txt \
  && grep -qE '^quit$' examples/fixtures/ide/cmds_long.txt \
  && echo "PASS ide_keys_long_tokens" || {
  echo "FAIL ide_keys_long_tokens"
  fail=1
}
# Proven keymap long-form save/run/show (aliases of s/r/w)
check ide_keys_long_srs_save examples/ide_keys_long_srs.spark \
  '"cmd":"save".*"path":"examples/hello.spark"'
check ide_keys_long_srs_run examples/ide_keys_long_srs.spark \
  '"cmd":"run".*"path":"examples/hello.spark"'
check ide_keys_long_srs_show examples/ide_keys_long_srs.spark \
  '"cmd":"show".*"path":"examples/hello.spark"'
check ide_keys_long_srs_open examples/ide_keys_long_srs.spark \
  '"cmd":"open"'
check ide_keys_long_srs_quit examples/ide_keys_long_srs.spark \
  '"cmd":"quit"'
check ide_keys_long_srs_drynote examples/ide_keys_long_srs.spark \
  'no save write / no run fork'
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_keys_long_srs_json" || {
  echo "FAIL ide_keys_long_srs_json"
  fail=1
}
grep -qE '^save$' examples/fixtures/ide/cmds_long_srs.txt \
  && grep -qE '^run$' examples/fixtures/ide/cmds_long_srs.txt \
  && grep -qE '^show$' examples/fixtures/ide/cmds_long_srs.txt \
  && echo "PASS ide_keys_long_srs_tokens" || {
  echo "FAIL ide_keys_long_srs_tokens"
  fail=1
}
# Proven keymap unknown token — fail-loud ok:false (not invented)
check ide_keys_unk_cmd examples/ide_keys_unknown.spark \
  '"cmd":"unknown".*"ok":false'
check ide_keys_unk_quit examples/ide_keys_unknown.spark \
  '"cmd":"quit".*"ok":true'
grep -qE '^x$' examples/fixtures/ide/cmds_unknown.txt \
  && echo "PASS ide_keys_unk_token" || {
  echo "FAIL ide_keys_unk_token"
  fail=1
}
# Proven ide save nopath fail-loud (no path / no open first)
check_fail ide_save_nopath examples/ide_save_nopath.spark \
  'ide save: no path'
# Proven ide run empty-buffer fail-loud (no open / empty buffer)
check_fail ide_run_nobuf examples/ide_run_nobuf.spark \
  'ide run: empty buffer'
# Proven ide ask empty-buffer fail-loud (no open first)
check_fail ide_ask_nobuf examples/ide_ask_nobuf.spark \
  'ide ask: empty buffer'
# Proven ide open needs-path fail-loud (no quote path)
check_fail ide_open_nopath examples/ide_open_nopath.spark \
  'ide open needs'
# Proven open/save bind forms (-> opened / -> saved) + print
check ide_bind_forms_open examples/ide_bind_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_bind_forms_save examples/ide_bind_forms.spark \
  '"op":"ide.save".*"dirty":false'
check ide_bind_forms_print_open examples/ide_bind_forms.spark \
  '\[print\] \{"op":"ide.open"'
check ide_bind_forms_print_save examples/ide_bind_forms.spark \
  '\[print\] \{"op":"ide.save"'
if test -f out/ide/ide_bind_forms_rt.spark \
  && test "$(sha256sum out/ide/ide_bind_forms_rt.spark | awk '{print $1}')" \
    = "$(sha256sum examples/hello.spark | awk '{print $1}')"; then
  echo "PASS ide_bind_forms_checksum"
else
  echo "FAIL ide_bind_forms_checksum"
  fail=1
fi
# Proven status path strip after open (status.txt == path, no *)
check ide_status_path_open examples/ide_status_path.spark \
  '"op":"ide.open".*"dirty":false'
./spark --dry-run examples/ide_status_path.spark >/dev/null 2>&1 || {
  echo "FAIL ide_status_path_rc"
  fail=1
}
if test -f out/ide/status.txt \
  && test "$(cat out/ide/status.txt)" = "examples/hello.spark" \
  && ! grep -qE '\*$' out/ide/status.txt; then
  echo "PASS ide_status_path_file"
else
  echo "FAIL ide_status_path_file"
  fail=1
fi
# Proven ide ask bind (-> reply) + print Gravity fixture
check ide_ask_bind_open examples/ide_ask_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_ask_bind_ask examples/ide_ask_bind.spark \
  '"op":"ide.ask".*"via":"ask_run_prompt"'
check ide_ask_bind_print examples/ide_ask_bind.spark \
  '\[print\] Gravity'
# Proven ide open missing path fail-loud
check_fail ide_open_miss examples/ide_open_miss.spark \
  'ide open: cannot read path'
# Proven ide show missing PPM fail-loud
check_fail ide_show_miss examples/ide_show_miss.spark \
  'cannot open image'
# Proven ide show non-PPM path fail-loud
check_fail ide_show_notppm examples/ide_show_notppm.spark \
  'not P6 PPM or .rgb'
# Proven ide keys missing script fail-loud
check_fail ide_keys_miss examples/ide_keys_miss.spark \
  'cannot open command script'
# Proven ide run bind (-> ran) + print op JSON
check ide_run_bind_open examples/ide_run_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_run_bind_run examples/ide_run_bind.spark \
  '"op":"ide.run".*"mode":"dry-run"'
check ide_run_bind_print examples/ide_run_bind.spark \
  '\[print\] \{"op":"ide.run"'
# Proven ide new bind (-> created) + print op JSON
check ide_new_bind_new examples/ide_new_bind.spark \
  '"op":"ide.new".*"dirty":true'
check ide_new_bind_print examples/ide_new_bind.spark \
  '\[print\] \{"op":"ide.new"'
# Proven quoted ide ask bind (-> reply) + print Gravity
check ide_ask_quote_bind_open examples/ide_ask_quote_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_ask_quote_bind_ask examples/ide_ask_quote_bind.spark \
  '"op":"ide.ask".*"via":"ask_run_prompt"'
check ide_ask_quote_bind_print examples/ide_ask_quote_bind.spark \
  '\[print\] Gravity'
# Proven ide key bad-token fail-loud (singular; not keys-script unknown)
check_fail ide_key_bad examples/ide_key_bad.spark \
  'want .ide keys'
# Proven ide buffer bind (-> dump) + print op JSON
check ide_buffer_bind_open examples/ide_buffer_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_buffer_bind_op examples/ide_buffer_bind.spark \
  '"op":"ide.buffer".*"ok":true'
check ide_buffer_bind_print examples/ide_buffer_bind.spark \
  '\[print\] \{"op":"ide.buffer"'
# Proven bare ide keys (default cmds.txt)
check ide_keys_bare_open examples/ide_keys_bare.spark \
  '"cmd":"open".*"ok":true'
check ide_keys_bare_quit examples/ide_keys_bare.spark \
  '"cmd":"quit".*"ok":true'
check ide_keys_bare_drynote examples/ide_keys_bare.spark \
  'trace only'
# Proven ide key open without path (soft fail: ok:false, rc=0)
check ide_key_open_nopath_err examples/ide_key_open_nopath.spark \
  'open path failed'
check ide_key_open_nopath_okf examples/ide_key_open_nopath.spark \
  '"cmd":"open".*"ok":false'
./spark --dry-run examples/ide_key_open_nopath.spark >/dev/null 2>&1 || {
  echo "FAIL ide_key_open_nopath_rc"
  fail=1
}
# Proven ide open bind (-> opened) + print op JSON
check ide_open_bind_op examples/ide_open_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_open_bind_print examples/ide_open_bind.spark \
  '\[print\] \{"op":"ide.open"'
# Proven ide save bind (-> saved) + print op JSON
check ide_save_bind_open examples/ide_save_bind.spark \
  '"op":"ide.open".*"dirty":false'
check ide_save_bind_save examples/ide_save_bind.spark \
  '"op":"ide.save".*"dirty":false'
check ide_save_bind_print examples/ide_save_bind.spark \
  '\[print\] \{"op":"ide.save"'
# Proven status.txt trailing * after ide new (path)
check ide_status_new_star_op examples/ide_status_new_star.spark \
  '"op":"ide.new".*"dirty":true'
./spark --dry-run examples/ide_status_new_star.spark >/dev/null 2>&1 || {
  echo "FAIL ide_status_new_star_rc"
  fail=1
}
if test -f out/ide/status.txt \
  && test "$(cat out/ide/status.txt)" = "out/ide/status_new_star.spark*" \
  && grep -qE '\*$' out/ide/status.txt; then
  echo "PASS ide_status_new_star_file"
else
  echo "FAIL ide_status_new_star_file"
  fail=1
fi
# Proven bare ide key quit (no prior open) + keys_trace
check ide_key_quit_alone_cmd examples/ide_key_quit_alone.spark \
  '"cmd":"quit".*"ok":true'
check ide_key_quit_alone_drynote examples/ide_key_quit_alone.spark \
  'trace only'
rm -f out/ide/keys_trace.jsonl
./spark --dry-run examples/ide_key_quit_alone.spark >/dev/null 2>&1 || {
  echo "FAIL ide_key_quit_alone_rc"
  fail=1
}
test -f out/ide/keys_trace.jsonl \
  && grep -q '"cmd":"quit"' out/ide/keys_trace.jsonl \
  && echo "PASS ide_key_quit_alone_trace" || {
  echo "FAIL ide_key_quit_alone_trace"
  fail=1
}
# Proven status.txt clears * after new+save
check ide_status_clear_new examples/ide_status_clear.spark \
  '"op":"ide.new".*"dirty":true'
check ide_status_clear_save examples/ide_status_clear.spark \
  '"op":"ide.save".*"dirty":false'
./spark --dry-run examples/ide_status_clear.spark >/dev/null 2>&1 || {
  echo "FAIL ide_status_clear_rc"
  fail=1
}
if test -f out/ide/status.txt \
  && test "$(cat out/ide/status.txt)" = "out/ide/status_clear.spark" \
  && ! grep -qE '\*$' out/ide/status.txt; then
  echo "PASS ide_status_clear_file"
else
  echo "FAIL ide_status_clear_file"
  fail=1
fi
# Proven bare ide key show (no prior open) + keys_trace
check ide_key_show_alone_cmd examples/ide_key_show_alone.spark \
  '"cmd":"show".*"ok":true'
check ide_key_show_alone_engine examples/ide_key_show_alone.spark \
  '"op":"show".*"path":"out/ide/editor.ppm"'
rm -f out/ide/keys_trace.jsonl
./spark --dry-run examples/ide_key_show_alone.spark >/dev/null 2>&1 || {
  echo "FAIL ide_key_show_alone_rc"
  fail=1
}
test -f out/ide/keys_trace.jsonl \
  && grep -q '"cmd":"show"' out/ide/keys_trace.jsonl \
  && echo "PASS ide_key_show_alone_trace" || {
  echo "FAIL ide_key_show_alone_trace"
  fail=1
}
# Dirty '*' in status strip after buffer edit (ide new) — not keymap n
check ide_dirty_open examples/ide_dirty_status.spark \
  '"op":"ide.open".*"dirty":false'
check ide_dirty_new examples/ide_dirty_status.spark \
  '"op":"ide.new".*"dirty":true'
check ide_dirty_save examples/ide_dirty_status.spark \
  '"op":"ide.save".*"dirty":false'
test -f out/ide/status_dirty.txt \
  && grep -qE '\*$' out/ide/status_dirty.txt \
  && echo "PASS ide_dirty_status_star" || {
  echo "FAIL ide_dirty_status_star"
  fail=1
}
test -f out/ide/status.txt \
  && ! grep -qE '\*$' out/ide/status.txt \
  && echo "PASS ide_dirty_cleared_star" || {
  echo "FAIL ide_dirty_cleared_star"
  fail=1
}
test -f out/ide/editor.ppm \
  && test "$(wc -c < out/ide/editor.ppm)" -gt 1000 \
  && echo "PASS ide_dirty_paint_ppm" || {
  echo "FAIL ide_dirty_paint_ppm"
  fail=1
}
# Proven ide new chain — new → buffer → save (0-byte) → open → buffer
# (not keymap n; documents core ide new only)
check ide_new_chain_new examples/ide_new_chain.spark \
  '"op":"ide.new".*"dirty":true'
check ide_new_chain_save examples/ide_new_chain.spark \
  '"op":"ide.save".*"dirty":false'
check ide_new_chain_open examples/ide_new_chain.spark \
  '"op":"ide.open".*"dirty":false'
check ide_new_chain_buffer examples/ide_new_chain.spark \
  '"op":"ide.buffer"'
test -f out/ide/ide_new_blank.spark \
  && test "$(wc -c < out/ide/ide_new_blank.spark)" -eq 0 \
  && echo "PASS ide_new_chain_empty_file" || {
  echo "FAIL ide_new_chain_empty_file"
  fail=1
}
test -f out/ide/status.txt \
  && ! grep -qE '\*$' out/ide/status.txt \
  && echo "PASS ide_new_chain_status_clean" || {
  echo "FAIL ide_new_chain_status_clean"
  fail=1
}
test -f out/ide/editor.ppm \
  && test "$(wc -c < out/ide/editor.ppm)" -gt 1000 \
  && echo "PASS ide_new_chain_paint_ppm" || {
  echo "FAIL ide_new_chain_paint_ppm"
  fail=1
}
# Proven ide buffer forms — bare + -> shown (after quit 54b005e).
# Dirty * e2e not repeated (covered by ide_dirty_status / ide_new_chain).
check ide_buffer_forms_open examples/ide_buffer_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_buffer_forms_bind examples/ide_buffer_forms.spark \
  '"op":"ide.buffer"'
check ide_buffer_forms_body examples/ide_buffer_forms.spark \
  "Explain gravity"
check ide_buffer_forms_new examples/ide_buffer_forms.spark \
  '"op":"ide.new".*"dirty":true'
buf_out="$(./spark --dry-run examples/ide_buffer_forms.spark 2>&1)" || {
  echo "FAIL ide_buffer_forms_rc"
  fail=1
  buf_out=""
}
buf_n="$(echo "$buf_out" | grep -cE '"op":"ide\.buffer"' || true)"
if test "$buf_n" -eq 2; then
  echo "PASS ide_buffer_forms_twice"
else
  echo "FAIL ide_buffer_forms_twice: count=$buf_n want=2"
  fail=1
fi
if echo "$buf_out" | grep -qE '"op":"ide\.show"'; then
  echo "FAIL ide_buffer_forms_not_show: -> shown hit show"
  fail=1
else
  echo "PASS ide_buffer_forms_not_show"
fi
# Proven ide save forms — quoted path + bare (after buffer forms 96b484c).
# Bare after open of hello would overwrite fixture — quote first, then bare.
check ide_save_forms_open examples/ide_save_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_save_forms_quoted examples/ide_save_forms.spark \
  'out/ide/ide_save_forms_rt.spark'
check ide_save_forms_ok examples/ide_save_forms.spark \
  '"op":"ide.save".*"dirty":false'
save_forms_out="$(./spark --dry-run examples/ide_save_forms.spark 2>&1)" || {
  echo "FAIL ide_save_forms_rc"
  fail=1
  save_forms_out=""
}
save_forms_n="$(echo "$save_forms_out" | grep -cE '"op":"ide\.save"' || true)"
if test "$save_forms_n" -eq 2; then
  echo "PASS ide_save_forms_twice"
else
  echo "FAIL ide_save_forms_twice: count=$save_forms_n want=2"
  fail=1
fi
if test -f out/ide/ide_save_forms_rt.spark \
  && test "$(wc -c < out/ide/ide_save_forms_rt.spark)" \
    -eq "$(wc -c < examples/hello.spark)" \
  && test "$(sha256sum out/ide/ide_save_forms_rt.spark | awk '{print $1}')" \
    = "$(sha256sum examples/hello.spark | awk '{print $1}')"; then
  echo "PASS ide_save_forms_checksum"
else
  echo "FAIL ide_save_forms_checksum"
  fail=1
fi
# Proven ide show forms — bare + quoted .ppm (after keys-open)
check ide_show_forms_open examples/ide_show_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_show_forms_op examples/ide_show_forms.spark '"op":"ide.show"'
check ide_show_forms_via examples/ide_show_forms.spark 'spark-engine-show'
check ide_show_forms_engine examples/ide_show_forms.spark '"op":"show"'
show_forms_out="$(./spark --dry-run examples/ide_show_forms.spark 2>&1)" || {
  echo "FAIL ide_show_forms_rc"
  fail=1
  show_forms_out=""
}
show_forms_n="$(echo "$show_forms_out" | grep -cE '"op":"ide\.show"' || true)"
if test "$show_forms_n" -eq 2; then
  echo "PASS ide_show_forms_twice"
else
  echo "FAIL ide_show_forms_twice: count=$show_forms_n want=2"
  fail=1
fi
test -f out/browser/show.json \
  && grep -q 'out/ide/editor.ppm' out/browser/show.json \
  && echo "PASS ide_show_forms_json" || {
  echo "FAIL ide_show_forms_json"
  fail=1
}
# Proven ide ask forms — bare + quoted instruction (after show forms)
check ide_ask_forms_open examples/ide_ask_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_ask_forms_op examples/ide_ask_forms.spark '"op":"ide.ask"'
check ide_ask_forms_via examples/ide_ask_forms.spark 'ask_run_prompt'
check ide_ask_forms_fixture examples/ide_ask_forms.spark "Gravity"
check ide_ask_forms_quote examples/ide_ask_forms.spark \
  'Explain gravity briefly'
ask_forms_out="$(./spark --dry-run examples/ide_ask_forms.spark 2>&1)" || {
  echo "FAIL ide_ask_forms_rc"
  fail=1
  ask_forms_out=""
}
ask_forms_n="$(echo "$ask_forms_out" | grep -cE '"op":"ide\.ask"' || true)"
if test "$ask_forms_n" -eq 2; then
  echo "PASS ide_ask_forms_twice"
else
  echo "FAIL ide_ask_forms_twice: count=$ask_forms_n want=2"
  fail=1
fi
# Proven ide new forms — bare + quoted path (after keys-long)
check ide_new_forms_bare examples/ide_new_forms.spark \
  '"op":"ide.new".*"dirty":true'
check ide_new_forms_path examples/ide_new_forms.spark \
  'out/ide/ide_new_forms_blank.spark'
check ide_new_forms_buffer examples/ide_new_forms.spark \
  '"op":"ide.buffer"'
new_forms_out="$(./spark --dry-run examples/ide_new_forms.spark 2>&1)" || {
  echo "FAIL ide_new_forms_rc"
  fail=1
  new_forms_out=""
}
new_forms_n="$(echo "$new_forms_out" | grep -cE '"op":"ide\.new"' || true)"
if test "$new_forms_n" -eq 2; then
  echo "PASS ide_new_forms_twice"
else
  echo "FAIL ide_new_forms_twice: count=$new_forms_n want=2"
  fail=1
fi
# Proven ide run forms — bare + -> ran (after long-srs)
check ide_run_forms_open examples/ide_run_forms.spark \
  '"op":"ide.open".*"dirty":false'
check ide_run_forms_ok examples/ide_run_forms.spark \
  '"op":"ide.run".*"mode":"dry-run"'
check ide_run_forms_child examples/ide_run_forms.spark "Gravity"
run_forms_out="$(./spark --dry-run examples/ide_run_forms.spark 2>&1)" || {
  echo "FAIL ide_run_forms_rc"
  fail=1
  run_forms_out=""
}
run_forms_n="$(echo "$run_forms_out" | grep -cE '"op":"ide\.run"' || true)"
if test "$run_forms_n" -eq 2; then
  echo "PASS ide_run_forms_twice"
else
  echo "FAIL ide_run_forms_twice: count=$run_forms_n want=2"
  fail=1
fi
# IDE AI strip — buffer → real ask_run_prompt (dry fixture)
check ide_ask_op examples/ide_ask.spark '"op":"ide.ask"'
check ide_ask_via examples/ide_ask.spark 'ask_run_prompt'
check ide_ask_fixture examples/ide_ask.spark "Gravity"


check classify_sales examples/classify_intent.spark '"label":"sales"'
check voice examples/voice_turn.spark "\[listen\]"
check voice_speak examples/voice_turn.spark "\[speak\]"
check voice_session examples/voice_turn.spark "\[voice\] session"

check voice_review examples/voice_reviewer.spark '"op":"voice.review"'
check voice_review_parse examples/voice_reviewer.spark 'byte_parsed.:true'
check voice_review_sr examples/voice_reviewer.spark '"sample_rate":16000'
check voice_coder examples/voice_coder.spark "out/voice_codegen.spark"
check voice_copy examples/voice_copy.spark "out/voice_models/demo_voice"
check voice_copy_load examples/voice_copy.spark "loaded demo_voice"
check voice_model_write examples/voice_model.spark "out/voice_models/brand_voice"
check voice_model_speak examples/voice_model.spark "with model"
check voice_pstn_dry examples/voice_pstn.spark 'claimed.:false'
check voice_pstn_status examples/voice_pstn.spark 'enabled_default.:false'

test -f out/voice_codegen.spark && grep -q "listen" out/voice_codegen.spark \
  && echo "PASS voice-codegen-artifact" || {
  echo "FAIL voice-codegen-artifact"
  fail=1
}
test -f out/voice_models/demo_voice/manifest.json \
  && test -f out/voice_models/demo_voice/features.bin \
  && grep -q "spark_voice_model" out/voice_models/demo_voice/manifest.json \
  && echo "PASS voice-model-artifact" || {
  echo "FAIL voice-model-artifact"
  fail=1
}
# PSTN companion: default refuse (no SPARK_PSTN / no --spark-cli)
if [[ -x ./spark-pstn-dial ]]; then
  set +e
  ./spark-pstn-dial --to +15555550100 >/dev/null 2>&1
  prc=$?
  set -e
  if [[ "$prc" -eq 0 ]]; then
    echo "FAIL pstn-default-off: companion dialed without gates"
    fail=1
  else
    echo "PASS pstn-default-off"
  fi
else
  echo "FAIL pstn-default-off: spark-pstn-dial missing"
  fail=1
fi
check pipeline examples/pipeline_translate.spark "Summarize|Resumen"
check extract examples/extract_person.spark "Ada Lovelace"
check tool examples/tool_agent.spark "\[tool\]"
check with_tools examples/tool_agent.spark \
  'with_tools.*"active":true|"active":true'
check tool_ask examples/tool_agent.spark '\[tool:weather\] stub:local'
check_fail with_no_tool examples/neg/with_no_tool.spark \
  "with tools"
check review examples/review_builder.spark "\[review\]"
check review_static examples/review_builder.spark "never eval"
check review_url examples/review_builder.spark '"op":"review.url"'
check review_url_bytes examples/review_builder.spark '"bytes":'
check review_url_eval_flag examples/review_builder.spark '"eval":false'
check review_url_issues examples/review_builder.spark 'possible eval'
check builder examples/review_builder.spark "\[builder\]"
check implement examples/review_builder.spark "out/program.spark"
check builder_higher examples/review_builder_higher.spark 'prefer":"higher'

# review url remote without --allow-net → clear --allow-net error, no dial
mkdir -p examples/neg
printf 'review url "https://example.com/app.js"\n' \
  > examples/neg/review_url_blocked.spark
check_fail review_url_blocked examples/neg/review_url_blocked.spark \
  "Pass --allow-net|needs --allow-net|blocked by default"
# companion must not print QUESTION (policy decided A+B)
set +e
_ru_out="$(./spark --dry-run examples/neg/review_url_blocked.spark 2>&1)"
_ru_rc=$?
set -e
if [[ "$_ru_rc" -eq 0 ]] || echo "$_ru_out" | grep -q 'QUESTION:'; then
  echo "FAIL review_url_no_question: got QUESTION or exit 0"
  fail=1
else
  echo "PASS review_url_no_question"
fi

# companion direct: file:// always; http without flag refuses; --allow-net
# fetches loopback (proves real curl path without public net)
make -s spark-review-url
./spark-review-url --url "file://examples/fixtures/sample.js" \
  >/tmp/spark-review-url-file.json 2>/tmp/spark-review-url-file.err \
  && grep -q '"op":"review.url"' /tmp/spark-review-url-file.json \
  && grep -q '"fetched":false' /tmp/spark-review-url-file.json \
  && echo "PASS review_url_companion_file" \
  || { echo "FAIL review_url_companion_file"; fail=1; }

set +e
./spark-review-url --url "https://example.com/app.js" \
  >/tmp/spark-review-url-block.out 2>/tmp/spark-review-url-block.err
_ru_c_rc=$?
set -e
if [[ "$_ru_c_rc" -ne 0 ]] \
  && grep -q -- '--allow-net' /tmp/spark-review-url-block.err \
  && ! grep -q 'QUESTION:' /tmp/spark-review-url-block.out \
  && ! grep -q 'QUESTION:' /tmp/spark-review-url-block.err; then
  echo "PASS review_url_companion_block"
else
  echo "FAIL review_url_companion_block"
  fail=1
fi

_ru_port_file=/tmp/spark-review-url-http.port
rm -f "$_ru_port_file"
python3 -c "
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os, sys
os.chdir('examples/fixtures')
httpd = ThreadingHTTPServer(('127.0.0.1', 0), SimpleHTTPRequestHandler)
open('$_ru_port_file', 'w').write(str(httpd.server_address[1]))
httpd.serve_forever()
" >/tmp/spark-review-url-http.log 2>&1 &
_ru_http_pid=$!
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$_ru_port_file" ]] && break
  sleep 0.1
done
_ru_port="$(cat "$_ru_port_file" 2>/dev/null || true)"
set +e
./spark-review-url --allow-net \
  --url "http://127.0.0.1:${_ru_port}/sample.js" \
  --out /tmp/spark-review-url-net.json \
  >/tmp/spark-review-url-net.out 2>/tmp/spark-review-url-net.err
_ru_net_rc=$?
set -e
kill "$_ru_http_pid" 2>/dev/null || true
wait "$_ru_http_pid" 2>/dev/null || true
if [[ -n "$_ru_port" && "$_ru_net_rc" -eq 0 ]] \
  && grep -q '"op":"review.url"' /tmp/spark-review-url-net.json \
  && grep -q '"fetched":true' /tmp/spark-review-url-net.json \
  && grep -q '"source":"http"' /tmp/spark-review-url-net.json; then
  echo "PASS review_url_companion_allow_net"
else
  echo "FAIL review_url_companion_allow_net (rc=$_ru_net_rc port=$_ru_port)"
  head -20 /tmp/spark-review-url-net.err || true
  fail=1
fi

# cuda/memory — real asm device + mlock
check cuda_probe examples/cuda_mem.spark '"op":"probe"'
check cuda_iface examples/cuda_mem.spark 'asm-dev\+ioctl'
check cuda_rm_ver examples/cuda_mem.spark '580\.'
check cuda_prefer_0 examples/cuda_mem.spark 'spark-prefer'
check cuda_never_voice examples/cuda_mem.spark 'never_minor.:2'
check cuda_memstat examples/cuda_mem.spark '"op":"memstat"'
check memory_pin examples/cuda_mem.spark '"op":"pin".*"mlock":true'

# cuda pcie — live sysfs (topology varies by host; assert shape only)
check cuda_pcie examples/cuda_pcie.spark '"op":"pcie"'
check cuda_pcie_iface examples/cuda_pcie.spark 'asm-sysfs'
check cuda_pcie_prefer examples/cuda_pcie.spark 'spark-prefer'
check cuda_pcie_never examples/cuda_pcie.spark 'voice-only-never-spark'
check cuda_pcie_bus0 examples/cuda_pcie.spark '0000:'
check cuda_pcie_down examples/cuda_pcie.spark '"downgraded":'
check cuda_pcie_w2 examples/cuda_pcie.spark '"width_current":'
check cuda_pcie_explain examples/cuda_pcie.spark 'pcie_explain'
check cuda_pcie_no_reboot examples/cuda_pcie.spark 'Measured PCIe|No reboot|downgrade'
test -f examples/fixtures/pcie/0000:01:00.0/current_link_width \
  && test -f examples/fixtures/pcie/0000:21:00.0/max_link_width \
  && echo "PASS pcie-sysfs-fixture" || {
  echo "FAIL pcie-sysfs-fixture"
  fail=1
}

check model_analyze examples/model_improve.spark "\[model\]"
check model_analyze_op examples/model_improve.spark '"op":"analyze"'
check model_analyze_why examples/model_improve.spark "tool-call JSON validity 94%"
check model_analyze_all examples/model_improve.spark "reachable configured"
check model_compare examples/model_improve.spark '"op":"compare"'
check model_compare_why examples/model_improve.spark "94% vs 71%"
check model_improve examples/model_improve.spark '"op":"improve"'
check model_improve_prefer examples/model_improve.spark '"prefer":"quality"'
check model_improve_delta examples/model_improve.spark "metrics_delta"
check model_plan examples/model_improve.spark "out/better-model.md"
check model_fixture_banner examples/model_improve.spark "not live leaderboard"
check model_train examples/model_train.spark '"op":"train"'
check model_train_job examples/model_train.spark "job-dry-001"
check model_status examples/model_train.spark '"op":"status"'
check model_status_ok examples/model_train.spark '"state":"succeeded"'

check binary_open examples/binary_any.spark "\[binary\]"
check binary_elf_ok examples/binary_any.spark '"class":"ELF64"'
check binary_understand examples/binary_any.spark '"op":"understand"'
check binary_all_sections examples/binary_any.spark 'all_sections.:true'
check binary_decompile_dir examples/binary_any.spark 'out/decompile/'
check binary_exports examples/binary_any.spark 'cuInit'
check binary_kernelmod examples/binary_any.spark '"op":"kernelmod"'
check binary_firmware examples/binary_any.spark '"op":"firmware"'

test -f out/decompile/tiny_cuda_stub.so/ALL_SECTIONS.contents \
  && test -f out/decompile/tiny_cuda_stub.so/ALL_SECTIONS.disasm \
  && test -f out/decompile/tiny_cuda_stub.so/.text.raw \
  && test -f out/decompile/tiny_cuda_stub.so/.dynsym.raw \
  && test -d out/decompile/tiny_cuda_stub.so/lifted \
  && test -f out/decompile/tiny_cuda_stub.so/lifted/lifted_common.h \
  && echo "PASS binary-all-section-artifacts" || {
  echo "FAIL binary-all-section-artifacts"
  fail=1
}

check binary_lifted examples/binary_any.spark 'lifted.:true'

check network_open examples/network_analyze.spark '"op":"open"'
check network_analyze examples/network_analyze.spark 'byte_parsed.:true'
check network_dns examples/network_analyze.spark "example.com"
check network_explain examples/network_analyze.spark '"op":"explain"'

# Negative: unknown op fail-loud
mkdir -p examples/neg
printf 'foobar\n' > examples/neg/unknown.spark
check_fail unknown_op examples/neg/unknown.spark "error: unknown"
printf 'review path "/no/such/file.js"\n' > examples/neg/missing_review.spark
check_fail review_missing examples/neg/missing_review.spark "error: review path"
printf 'network analyze pcap\n' > examples/neg/analyze_no_open.spark
check_fail analyze_no_open examples/neg/analyze_no_open.spark "requires successful"

# Real NVIDIA libs — open/elf + full understand (resume if decompile
# artifacts exist). Absent → skip. Timeout protects fresh 96MiB dump.
if [[ -e /lib/x86_64-linux-gnu/libcuda.so.1 ]]; then
  set +e
  out="$(timeout 120 ./spark --dry-run examples/binary_cuda_drivers.spark 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 124 ]]; then
    echo "FAIL binary_cuda_real (timeout — understand hung)"
    fail=1
  elif [[ "$rc" -eq 139 ]] || echo "$out" | grep -qE 'Segmentation fault'; then
    echo "FAIL binary_cuda_real (SIGSEGV)"
    fail=1
  elif echo "$out" | grep -qE '"op":"understand"' \
    && echo "$out" | grep -qE '"class":"ELF64"'; then
    echo "PASS binary_cuda_real"
  else
    echo "FAIL binary_cuda_real (rc=$rc)"
    echo "$out" | tail -30
    fail=1
  fi
else
  echo "SKIP binary_cuda_real (libcuda.so.1 absent)"
fi

# Synthetic large e_shoff — must not SIGSEGV on understand
check binary_large_shoff examples/binary_large_shoff.spark '"op":"understand"'
check binary_large_shoff_exports examples/binary_large_shoff.spark 'cuInit'

# network capture dry path (fixture, claimed:false)
printf 'network capture interface "lo" duration 1s -> pcap\nnetwork analyze pcap\n' \
  > examples/neg/capture_dry.spark
check capture_dry examples/neg/capture_dry.spark 'claimed.:false'
check capture_dry_analyze examples/neg/capture_dry.spark 'byte_parsed.:true'

# net-capture gate: --probe never claims; CAP miss on live → exit 4
make -s spark-net-capture
./spark-net-capture --probe >/tmp/spark-net-probe.json 2>/tmp/spark-net-probe.err
_nprc=$?
if [[ "$_nprc" -eq 0 ]] \
  && grep -q '"op":"capture_probe"' /tmp/spark-net-probe.json \
  && grep -q '"claimed":false' /tmp/spark-net-probe.json \
  && grep -qE '"ready":(true|false)' /tmp/spark-net-probe.json; then
  echo "PASS net-capture-probe-companion"
else
  echo "FAIL net-capture-probe-companion rc=$_nprc"
  cat /tmp/spark-net-probe.json /tmp/spark-net-probe.err | head -20
  fail=1
fi
check capture_probe examples/network_capture_probe.spark \
  'capture_probe|"claimed":false'
# When CAP absent, --allow-net-capture must fail loud exit 4
if grep -q '"ready":false' /tmp/spark-net-probe.json; then
  set +e
  _cap_out="$(./spark --dry-run --allow-net-capture \
    examples/network_capture.spark 2>&1)"
  _cap_rc=$?
  set -e
  if [[ "$_cap_rc" -eq 4 ]] \
    && echo "$_cap_out" | grep -qE 'CAP_NET_RAW|claimed.:false'; then
    echo "PASS net-capture-allow-cap-miss-exit4"
  else
    echo "FAIL net-capture-allow-cap-miss-exit4 rc=$_cap_rc"
    echo "$_cap_out" | head -20
    fail=1
  fi
else
  echo "SKIP net-capture-allow-cap-miss-exit4 (CAP_NET_RAW ready)"
fi

test -f examples/fixtures/sample.pcap \
  && test -f examples/fixtures/binary/tiny_cuda_stub.so \
  && echo "PASS binary-network-fixtures" || {
  echo "FAIL binary-network-fixtures"
  fail=1
}

test -f out/program.spark && grep -q "classify Intent" out/program.spark \
  && echo "PASS implement-artifact" || {
  echo "FAIL implement-artifact"
  fail=1
}

test -f out/better-model.md && grep -q "model train" out/better-model.md \
  && echo "PASS model-plan-artifact" || {
  echo "FAIL model-plan-artifact"
  fail=1
}

test -f out/train/job-dry-001/ARTIFACT \
  && grep -q job-dry-001 out/train/job-dry-001/ARTIFACT \
  && echo "PASS model-train-artifact" || {
  echo "FAIL model-train-artifact"
  fail=1
}

test -f examples/fixtures/models/alias-code-analyze.json \
  && test -f examples/eval_suite.json \
  && echo "PASS model-fixtures" || {
  echo "FAIL model-fixtures"
  fail=1
}

rm -rf out/os/agentos
check os_design examples/os_agentos.spark '"op":"design"'
check os_specify examples/os_agentos.spark '"op":"specify"'
check os_generate examples/os_agentos.spark "out/os/agentos"
check os_build examples/os_agentos.spark "build dry-run"
check os_explain examples/os_agentos.spark "cooperative isolates"
check os_honesty examples/os_agentos.spark "blueprint"

test -f out/os/agentos/README.md \
  && test -f out/os/agentos/boot.s \
  && echo "PASS os-generate-tree" || {
  echo "FAIL os-generate-tree"
  fail=1
}

rm -rf out/os/browser_mitm
check browser_mitm examples/browser_mitm.spark '"kind":"browser"'
check browser_mitm_gen examples/browser_mitm.spark "out/os/browser_mitm"
check browser_mitm_net examples/browser_mitm.spark 'byte_parsed|network'
check browser_flags examples/browser_mitm.spark 'disable_quic.:false'
check browser_dq examples/browser_mitm.spark '"op":"disable_quic"'
test -f out/os/browser_mitm/README.md \
  && test -f out/os/browser_mitm/LAYOUT.md \
  && test -f out/os/browser_mitm/spark_browser/mitm/HOOKS.md \
  && test ! -f out/os/browser_mitm/boot.s \
  && echo "PASS browser-generate-tree" || {
  echo "FAIL browser-generate-tree"
  fail=1
}

# Spark-first QUIC + disable-quic (asm + aioquic helper smoke)
check browser_quic_flags examples/browser_quic.spark '"op":"flags"'
check browser_quic_status examples/browser_quic.spark 'mitm.quic.status'
check browser_quic_smoke examples/browser_quic.spark 'mitm.quic.smoke'
check browser_cdp_status examples/browser_cdp.spark 'cdp\.status'
check browser_cdp_nav examples/browser_cdp.spark 'cdp\.navigate'

# Spark-owned HTTPS MITM smoke (./spark-mitm-h2 — not Qt)
check browser_h2_smoke examples/browser_h2.spark 'mitm.smoke'
check browser_h2_owner examples/browser_h2.spark 'spark-mitm-h2'

# mitm ca-init / ca-status / ca-install (language SoT; helper crypto)
rm -rf out/browser/ca out/browser/ca.json
check browser_ca_init examples/browser_ca.spark '"op":"ca_init"'
check browser_ca_status examples/browser_ca.spark '"op":"ca_status"'
check browser_ca_install_plan examples/browser_ca.spark \
  'ca_install.*"planned":true|"planned":true'
test -f out/browser/ca/ca.pem \
  && test -f out/browser/ca/ca.key \
  && test -f out/browser/ca/ca.meta.json \
  && test -f out/browser/ca.json \
  && grep -q 'BEGIN CERTIFICATE' out/browser/ca/ca.pem \
  && echo "PASS browser-ca-artifacts" || {
  echo "FAIL browser-ca-artifacts"
  fail=1
}

# browser / mitm language ops (asm SoT — session + HAR artifacts)
rm -rf out/browser
check browser_lang_run examples/browser_main.spark '\[browser\]'
check browser_lang_goto examples/browser_main.spark '"op":"goto"'
check browser_lang_mitm examples/browser_main.spark '"op":"enable"'
check browser_lang_har examples/browser_main.spark 'har_export|byte_written'
test -f out/browser/session.json \
  && test -f out/browser/mitm.json \
  && test -f out/browser/session.har \
  && grep -q 'example.com' out/browser/session.har \
  && grep -q 'cdn.example.com' out/browser/session.har \
  && grep -q 'api.example.com' out/browser/session.har \
  && grep -q 'demo-multiflow' out/browser/session.har \
  && grep -q '"log"' out/browser/session.har \
  && echo "PASS browser-lang-artifacts" || {
  echo "FAIL browser-lang-artifacts"
  fail=1
}
# Multi-flow dry HAR must analyze via spark-browser hook
if [[ -f ../spark-browser/spark_browser/__main__.py ]]; then
  PYTHONPATH=../spark-browser python3 -m spark_browser mitm analyze \
    out/browser/session.har --spark "$ROOT/spark" --require-spark \
    --no-fixture-fallback >/tmp/spark-har-analyze.out 2>&1 \
    && grep -qE '"ok": true|"byte_parsed": true' \
      out/browser/spark_mitm_report.json \
    && python3 -c "
import json
r=json.load(open('out/browser/spark_mitm_report.json'))
assert r.get('entries',0) >= 4, r
assert r.get('pcap_frames',0) >= 2, r
assert r.get('spark',{}).get('ok') is True, r
print('PASS browser-har-analyze-multiflow')
" || {
    echo "FAIL browser-har-analyze-multiflow"
    head -40 /tmp/spark-har-analyze.out || true
    fail=1
  }
else
  echo "WARN skip browser-har-analyze-multiflow (no spark-browser)"
fi

# Negatives: goto without session; har without enable
printf 'browser goto "https://x.test/"\n' > examples/neg/browser_no_session.spark
check_fail browser_no_session examples/neg/browser_no_session.spark \
  "session required"
printf 'mitm har export "out/browser/x.har"\n' > examples/neg/mitm_no_enable.spark
check_fail mitm_no_enable examples/neg/mitm_no_enable.spark \
  "mitm enable"

# browser gui without --live must fail loud
printf 'browser gui\n' > examples/neg/browser_gui_dry.spark
check_fail browser_gui_dry examples/neg/browser_gui_dry.spark \
  "requires --live"

# Engine B — HTML tokenize/parse → DOM (asm)
./tests/engine_html_parse.sh || fail=1

# Engine B browser show (dry — no X11)
check browser_show examples/browser_show.spark '"op":"show"'
check browser_show_dry examples/browser_show.spark 'display.:false'
test -f out/browser/show.json \
  && grep -q '"op":"show"' out/browser/show.json \
  && echo "PASS browser-show-artifact" || {
  echo "FAIL browser-show-artifact"
  fail=1
}
check_fail browser_show_missing examples/neg/browser_show_missing.spark \
  "cannot open image"
./spark-engine-show --dry --ppm examples/fixtures/browser/engine_show.ppm \
  | grep -q '"dry":true' \
  && echo "PASS engine-show-companion-dry" || {
  echo "FAIL engine-show-companion-dry"
  fail=1
}
# Live X11 is not in dry suite (needs DISPLAY). Documented:
#   ./spark --live examples/engine_pipeline.spark
#   ./spark-engine-show --ppm out/engine/pipeline.ppm --hold 2000

# Engine B pipeline wiring (fetch→parse; fetch|parse|css|layout|paint|show)
check engine_fetch_parse examples/engine_fetch_parse.spark \
  '"op":"engine.fetch_parse"'
test -f out/engine/body.bin && test -f out/browser/engine/dom.json \
  && echo "PASS engine-fetch-parse-artifacts" || {
  echo "FAIL engine-fetch-parse-artifacts"
  fail=1
}
chmod +x engine/tests/test_fetch_parse_layout.sh
./engine/tests/test_fetch_parse_layout.sh || fail=1
check engine_pipeline examples/engine_pipeline.spark \
  '"op":"show"'
chmod +x engine/tests/test_pipeline_table.sh
./engine/tests/test_pipeline_table.sh || fail=1
test -f out/engine/body.bin && test -f out/browser/engine/dom.json \
  && test -f out/browser/engine/css.json \
  && test -f out/engine/pipeline.ppm && test -f out/browser/show.json \
  && echo "PASS engine-pipeline-artifacts" || {
  echo "FAIL engine-pipeline-artifacts"
  fail=1
}
check browser_engine_render examples/browser_engine_render.spark \
  '"op":"engine.render"'
test -f out/engine/pipeline.ppm && test -f out/browser/show.json \
  && grep -q paint_boxes out/browser/engine/render.json \
  && echo "PASS engine-render-artifacts" || {
  echo "FAIL engine-render-artifacts"
  fail=1
}
check_fail engine_layout_no_dom examples/neg/engine_layout_no_dom.spark \
  "engine layout needs DOM"


# Encrypt-to-model gateway (AES-256-GCM; offline)
./spark-enc-gateway self-test | grep -q '"pass":true' \
  && echo "PASS enc-gateway-nist" || {
  echo "FAIL enc-gateway-nist"
  fail=1
}
./spark-enc-gateway probe | grep -qE '"af_alg_status":"(blacklisted|ok|unavailable)"' \
  && echo "PASS enc-gateway-probe-status" || {
  echo "FAIL enc-gateway-probe-status"
  fail=1
}
./spark-enc-gateway probe | grep -q '"openssl_evp":true' \
  && echo "PASS enc-gateway-probe-openssl" || {
  echo "FAIL enc-gateway-probe-openssl"
  fail=1
}
# Host: algif_aead blacklisted — require honest blacklist signal
if [[ -f /etc/modprobe.d/disable-algif_aead.conf ]]; then
  ./spark-enc-gateway probe | grep -q '"af_alg_status":"blacklisted"' \
    && echo "PASS enc-gateway-probe-blacklist" || {
    echo "FAIL enc-gateway-probe-blacklist"
    fail=1
  }
  set +e
  ./spark-enc-gateway backend --set af_alg >/dev/null 2>&1
  brc=$?
  set -e
  if [[ "$brc" -eq 0 ]]; then
    echo "FAIL enc-backend-afalg-fail-loud: expected non-zero"
    fail=1
  else
    echo "PASS enc-backend-afalg-fail-loud"
  fi
fi
./spark-enc-gateway backend --set openssl | grep -q '"backend":"openssl"' \
  && echo "PASS enc-backend-openssl-set" || {
  echo "FAIL enc-backend-openssl-set"
  fail=1
}
rm -rf out/encrypt
check enc_keygen examples/encrypt_gateway.spark '\[crypto\]'
check enc_seal examples/encrypt_gateway.spark '\[encrypt\]'
check enc_open examples/encrypt_gateway.spark 'SSN 123-45-6789'
check enc_gateway_on examples/encrypt_gateway.spark \
  'gateway_encrypt.*"enabled":true|"enabled":true'
check enc_ask_proxy examples/encrypt_gateway.spark 'encrypt-gateway'
check enc_ask_decrypt examples/encrypt_gateway.spark 'decrypted envelope|gateway-ok'
check enc_probe examples/crypto_probe.spark 'af_alg_status'
check enc_backend_openssl examples/crypto_backend_openssl.spark \
  '"backend":"openssl"|openssl'
check_fail enc_backend_afalg_neg examples/neg/crypto_backend_afalg.spark \
  'AF_ALG|af_alg|blacklisted|spark-enc-gateway failed'

# Gateway probe dry credential check (offline — no curl)
./spark-ask-probe --dry | grep -qE '"op":"ask_probe"' \
  && echo "PASS ask-probe-dry-json" || {
  echo "FAIL ask-probe-dry-json"
  fail=1
}
set +e
SPARK_ASK_PROBE_FORCE_UNAVAILABLE=1 ./spark-ask-probe --dry \
  >/tmp/spark-ask-probe-miss.json 2>/tmp/spark-ask-probe-miss.err
rc=$?
set -e
if [[ "$rc" -eq 4 ]] && grep -q 'credential unavailable' /tmp/spark-ask-probe-miss.err \
  && grep -q 'credential unavailable' /tmp/spark-ask-probe-miss.json; then
  echo "PASS ask-probe-dry-miss-exit4"
else
  echo "FAIL ask-probe-dry-miss-exit4 rc=$rc"
  fail=1
fi
check ask_probe examples/ask_probe.spark 'ask_probe|credential|ready'
check gateway_probe examples/gateway_probe.spark 'ask_probe|credential|ready'
test -f out/encrypt/spark.key \
  && test -f out/encrypt/seal.envelope.json \
  && grep -q 'AES-256-GCM' out/encrypt/seal.envelope.json \
  && grep -q 'ciphertext_hex' out/encrypt/seal.envelope.json \
  && ! grep -q 'SSN 123-45-6789' out/encrypt/seal.envelope.json \
  && echo "PASS enc-envelope-artifact" || {
  echo "FAIL enc-envelope-artifact"
  fail=1
}
# Keys / encrypt dir must not be world-readable
mode="$(stat -c '%a' out/encrypt/spark.key 2>/dev/null || echo missing)"
if [[ "$mode" == "600" ]]; then
  echo "PASS enc-key-mode-0600"
else
  echo "FAIL enc-key-mode-0600: mode=$mode (want 600)"
  fail=1
fi
dmode="$(stat -c '%a' out/encrypt 2>/dev/null || echo missing)"
if [[ "$dmode" == "700" ]]; then
  echo "PASS enc-dir-mode-0700"
else
  echo "FAIL enc-dir-mode-0700: mode=$dmode (want 700)"
  fail=1
fi
printf 'gateway encrypt on\n' > examples/neg/gateway_no_key.spark
check_fail gateway_no_key examples/neg/gateway_no_key.spark "requires a loaded key"

# CUDA prefer: Device Minor 2 / nvidia2 / gpu 2 = voice-only refuse.
# gpu 1 = secondary (Device Minor 1) — must NOT refuse (smi index ≠ minor).
mkdir -p examples/neg
printf 'cuda prefer gpu 2\n' > examples/neg/cuda_prefer_voice.spark
check_fail cuda_prefer_voice examples/neg/cuda_prefer_voice.spark \
  "voice-only|refused|voice GPU|nvidia2|Minor 2"
printf 'cuda prefer /dev/nvidia2\n' > examples/neg/cuda_prefer_n2.spark
check_fail cuda_prefer_n2 examples/neg/cuda_prefer_n2.spark \
  "voice-only|refused|voice GPU|nvidia2|Minor 2"
printf 'cuda prefer minor 2\n' > examples/neg/cuda_prefer_minor2.spark
check_fail cuda_prefer_minor2 examples/neg/cuda_prefer_minor2.spark \
  "voice-only|refused|voice GPU|nvidia2|Minor 2"
# Positive: gpu 1 (secondary) must succeed prefer path (opens nvidia0)
printf 'cuda prefer gpu 1\n' > /tmp/spark-cuda-prefer-gpu1.spark
set +e
_out="$(./spark --dry-run /tmp/spark-cuda-prefer-gpu1.spark 2>&1)"
_rc=$?
set -e
rm -f /tmp/spark-cuda-prefer-gpu1.spark
if [[ "$_rc" -eq 0 ]] && echo "$_out" | grep -qE 'prefer_minor.:0|ok.:true'; then
  echo "PASS cuda_prefer_gpu1_secondary_allowed"
else
  echo "FAIL cuda_prefer_gpu1_secondary_allowed: rc=$_rc out=$_out"
  fail=1
fi

# PSTN divert refuse (exit 4) when store DID under failover ledger
if [[ -x ./spark-pstn-dial ]]; then
  _divtmp="$(mktemp -d)"
  mkdir -p "$_divtmp/.local/share/spark"
  printf '%s\n' \
    '{"mode":"failover","applied_dids":{"+15555550199":true}}' \
    > "$_divtmp/.local/share/spark/outage-forward-state.json"
  set +e
  HOME="$_divtmp" SPARK_PSTN=1 SPARK_PSTN_ALLOW=+15555550199 \
    ./spark-pstn-dial --spark-cli --to +15555550199 >/dev/null 2>&1
  _drc=$?
  set -e
  rm -rf "$_divtmp"
  if [[ "$_drc" -eq 4 ]]; then
    echo "PASS pstn-divert-refuse-exit4"
  else
    echo "FAIL pstn-divert-refuse-exit4: rc=$_drc (want 4)"
    fail=1
  fi
else
  echo "FAIL pstn-divert-refuse-exit4: companion missing"
  fail=1
fi

# Live STT/TTS companion — offline local only in make test (no vendor net)
if [[ -x ./spark-stt-tts ]]; then
  ./spark-stt-tts status | grep -q '"local_synth":true' \
    && echo "PASS speech-status" || {
    echo "FAIL speech-status"
    fail=1
  }
  rm -f /tmp/spark-test-speak.wav /tmp/spark-test-listen.txt
  ./spark-stt-tts speak --text "spark" --out /tmp/spark-test-speak.wav \
    && test -f /tmp/spark-test-speak.wav \
    && python3 -c "import sys;d=open('/tmp/spark-test-speak.wav','rb').read(12);sys.exit(0 if d[:4]==b'RIFF' and d[8:12]==b'WAVE' else 1)" \
    && echo "PASS speech-speak-local-wav" || {
    echo "FAIL speech-speak-local-wav"
    fail=1
  }
  ./spark-stt-tts listen \
    --in examples/fixtures/audio/sample_review.wav \
    --out /tmp/spark-test-listen.txt \
    && grep -qi account /tmp/spark-test-listen.txt \
    && echo "PASS speech-listen-sidecar" || {
    echo "FAIL speech-listen-sidecar"
    fail=1
  }
  # Network vendors stay gated OFF without SPARK_*_NET
  set +e
  SPARK_TTS_URL=http://127.0.0.1:9/tts \
    ./spark-stt-tts speak --text "x" --out /tmp/spark-net-refuse.wav \
    >/dev/null 2>&1
  _trc=$?
  set -e
  if [[ "$_trc" -eq 2 ]]; then
    echo "PASS speech-tts-net-gated"
  else
    echo "FAIL speech-tts-net-gated: rc=$_trc (want 2)"
    fail=1
  fi
  set +e
  SPARK_STT_URL=http://127.0.0.1:9/stt \
    ./spark-stt-tts listen --in examples/fixtures/audio/sample_review.wav \
    >/dev/null 2>&1
  _src=$?
  set -e
  # URL set without NET → gated (2); sidecar would win if URL not preferred
  # Companion prefers HTTP only when net allowed; else sidecar — so with URL
  # set but net off, it should hit gated path before sidecar when URL isset.
  if [[ "$_src" -eq 2 ]]; then
    echo "PASS speech-stt-net-gated"
  else
    echo "FAIL speech-stt-net-gated: rc=$_src (want 2)"
    fail=1
  fi
  # Dry-run never forks companion (still stub transcript)
  check voice_dry_offline examples/voice_turn.spark '\[listen\]'
  # Dry speak must honor -> "path" (was always spark-out.wav)
  rm -f out/speak-path-test.wav
  mkdir -p out
  printf '%s\n' 'speak "path check" -> "out/speak-path-test.wav"' \
    > /tmp/spark-speak-path.spark
  ./spark --dry-run /tmp/spark-speak-path.spark >/dev/null \
    && test -f out/speak-path-test.wav \
    && echo "PASS speech-speak-path" || {
    echo "FAIL speech-speak-path"
    fail=1
  }
  # Live local STT/TTS (sidecar + synth) — no vendor net
  rm -f out/voice_live.wav
  ./spark --live examples/voice_live.spark >/tmp/spark-live-speech.out 2>&1 \
    && grep -q account /tmp/spark-live-speech.out \
    && test -f out/voice_live.wav \
    && python3 -c "import sys;d=open('out/voice_live.wav','rb').read(12);sys.exit(0 if d[:4]==b'RIFF' and d[8:12]==b'WAVE' else 1)" \
    && echo "PASS speech-live-local" || {
    echo "FAIL speech-live-local"
    fail=1
  }
  ./spark-stt-tts status | grep -q '"stt_whisper"' \
    && echo "PASS speech-whisper-status" || {
    echo "FAIL speech-whisper-status"
    fail=1
  }
else
  echo "FAIL speech companion missing (spark-stt-tts)"
  fail=1
fi

# Secret paths listed in .gitignore
grep -q 'out/encrypt/' .gitignore \
  && grep -qE 'out/browser/ca/|\*\*/data/ca/ca\.key' .gitignore \
  && grep -q '\*\.key' .gitignore \
  && echo "PASS gitignore-secrets" || {
  echo "FAIL gitignore-secrets"
  fail=1
}

# Engine B fetch — file:// dry; http blocked without --allow-net;
# http://127.0.0.1 with --allow-net via asm sockets (not urllib).
check engine_fetch_file examples/engine_fetch.spark '"op":"engine.fetch"'
check engine_fetch_source examples/engine_fetch.spark '"source":"file"'
check engine_fetch_transport examples/engine_fetch.spark '"transport":"open"'
check engine_fetch_body_art examples/engine_fetch.spark 'out/engine/body.bin'
test -f out/engine/body.bin \
  && grep -q 'Hello from Spark engine B fetch' out/engine/body.bin \
  && echo "PASS engine_fetch_body_bytes" || {
  echo "FAIL engine_fetch_body_bytes"
  fail=1
}
check_fail engine_fetch_blocked examples/neg/engine_fetch_blocked.spark \
  "Pass --allow-net|blocked by default"
check_fail engine_fetch_https examples/neg/engine_fetch_https.spark \
  "https blocked by default|Pass --allow-net|spark-engine-fetch-tls"

_ef_port_file=/tmp/spark-engine-fetch-http.port
rm -f "$_ef_port_file"
python3 -c "
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
os.chdir('examples/fixtures/engine')
httpd = ThreadingHTTPServer(('127.0.0.1', 0), SimpleHTTPRequestHandler)
open('$_ef_port_file', 'w').write(str(httpd.server_address[1]))
httpd.serve_forever()
" >/tmp/spark-engine-fetch-http.log 2>&1 &
_ef_http_pid=$!
for _i in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f "$_ef_port_file" ]] && break
  sleep 0.1
done
_ef_port="$(cat "$_ef_port_file" 2>/dev/null || true)"
printf 'engine fetch "http://127.0.0.1:%s/sample.html"\n' "$_ef_port" \
  >/tmp/spark-engine-fetch-http.spark
set +e
./spark --dry-run --allow-net /tmp/spark-engine-fetch-http.spark \
  >/tmp/spark-engine-fetch-net.out 2>/tmp/spark-engine-fetch-net.err
_ef_net_rc=$?
set -e
kill "$_ef_http_pid" 2>/dev/null || true
wait "$_ef_http_pid" 2>/dev/null || true
if [[ -n "$_ef_port" && "$_ef_net_rc" -eq 0 ]] \
  && grep -q '"op":"engine.fetch"' /tmp/spark-engine-fetch-net.out \
  && grep -q '"source":"http"' /tmp/spark-engine-fetch-net.out \
  && grep -q '"fetched":true' /tmp/spark-engine-fetch-net.out \
  && grep -q 'asm-socket' /tmp/spark-engine-fetch-net.out \
  && test -f out/engine/body.bin \
  && grep -q 'Hello from Spark engine B fetch' out/engine/body.bin; then
  echo "PASS engine_fetch_asm_socket_loopback"
else
  echo "FAIL engine_fetch_asm_socket_loopback (rc=$_ef_net_rc port=$_ef_port)"
  head -30 /tmp/spark-engine-fetch-net.out || true
  head -30 /tmp/spark-engine-fetch-net.err || true
  fail=1
fi

# HTTPS — companion refuse without --allow-net; loopback OpenSSL BIO
# with self-signed cert (--insecure auto for 127.0.0.1).
if [[ ! -x ./spark-engine-fetch-tls ]]; then
  echo "FAIL engine_fetch_tls_companion_missing"
  fail=1
else
  set +e
  ./spark-engine-fetch-tls --url "https://example.com/" \
    --out /tmp/spark-ef-tls-refuse.bin >/tmp/spark-ef-tls-refuse.out 2>&1
  _ef_tls_refuse=$?
  set -e
  if [[ "$_ef_tls_refuse" -ne 0 ]] \
    && grep -qi 'allow-net\|blocked' /tmp/spark-ef-tls-refuse.out; then
    echo "PASS engine_fetch_tls_companion_refuse"
  else
    echo "FAIL engine_fetch_tls_companion_refuse rc=$_ef_tls_refuse"
    head -20 /tmp/spark-ef-tls-refuse.out || true
    fail=1
  fi

  _ef_tls_dir=/tmp/spark-engine-fetch-tls-$$
  mkdir -p "$_ef_tls_dir"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$_ef_tls_dir/key.pem" -out "$_ef_tls_dir/cert.pem" \
    -days 1 -nodes -subj "/CN=127.0.0.1" \
    >/tmp/spark-ef-tls-cert.log 2>&1
  cp examples/fixtures/engine/sample.html "$_ef_tls_dir/sample.html"
  _ef_tls_port_file="$_ef_tls_dir/port"
  python3 -c "
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
" >"$_ef_tls_port_file"
  _ef_tls_port="$(cat "$_ef_tls_port_file")"
  (
    cd "$_ef_tls_dir"
    openssl s_server -accept "$_ef_tls_port" -cert cert.pem -key key.pem \
      -WWW -quiet
  ) >/tmp/spark-ef-tls-server.log 2>&1 &
  _ef_tls_srv=$!
  sleep 0.3
  set +e
  ./spark-engine-fetch-tls \
    --url "https://127.0.0.1:${_ef_tls_port}/sample.html" \
    --out "$_ef_tls_dir/body.bin" --allow-net --insecure \
    >/tmp/spark-ef-tls-direct.out 2>/tmp/spark-ef-tls-direct.err
  _ef_tls_direct_rc=$?
  set -e
  if [[ "$_ef_tls_direct_rc" -eq 0 ]] \
    && test -f "$_ef_tls_dir/body.bin" \
    && grep -q 'Hello from Spark engine B fetch' "$_ef_tls_dir/body.bin"; then
    echo "PASS engine_fetch_tls_companion_loopback"
  else
    echo "FAIL engine_fetch_tls_companion_loopback rc=$_ef_tls_direct_rc"
    head -30 /tmp/spark-ef-tls-direct.out || true
    head -30 /tmp/spark-ef-tls-direct.err || true
    head -30 /tmp/spark-ef-tls-server.log || true
    fail=1
  fi

  printf 'engine fetch "https://127.0.0.1:%s/sample.html"\n' \
    "$_ef_tls_port" >/tmp/spark-engine-fetch-https.spark
  set +e
  ./spark --dry-run --allow-net /tmp/spark-engine-fetch-https.spark \
    >/tmp/spark-engine-fetch-https.out 2>/tmp/spark-engine-fetch-https.err
  _ef_https_rc=$?
  set -e
  kill "$_ef_tls_srv" 2>/dev/null || true
  wait "$_ef_tls_srv" 2>/dev/null || true
  rm -rf "$_ef_tls_dir"
  if [[ "$_ef_https_rc" -eq 0 ]] \
    && grep -q '"op":"engine.fetch"' /tmp/spark-engine-fetch-https.out \
    && grep -q '"source":"https"' /tmp/spark-engine-fetch-https.out \
    && grep -q 'openssl-bio' /tmp/spark-engine-fetch-https.out \
    && test -f out/engine/body.bin \
    && grep -q 'Hello from Spark engine B fetch' out/engine/body.bin; then
    echo "PASS engine_fetch_https_openssl_bio"
  else
    echo "FAIL engine_fetch_https_openssl_bio (rc=$_ef_https_rc)"
    head -30 /tmp/spark-engine-fetch-https.out || true
    head -30 /tmp/spark-engine-fetch-https.err || true
    fail=1
  fi
fi

./spark --version | grep -qE "asm|dry-run" && echo "PASS version" || {
  echo "FAIL version"
  fail=1
}

file ./spark | grep -q "ELF 64-bit" && echo "PASS elf-machine-code" || {
  echo "FAIL elf-machine-code"
  fail=1
}

# Engine B JS phase-1 (numbers, strings, +, console.log)
if [[ -x ./engine/tests/js_phase1.sh ]]; then
  ./engine/tests/js_phase1.sh || fail=1
else
  echo "FAIL engine js_phase1.sh missing"
  fail=1
fi

# Engine B — <script> text → engine_js_eval after parse
if [[ -x ./engine/tests/js_script_dom.sh ]]; then
  ./engine/tests/js_script_dom.sh || fail=1
else
  echo "FAIL engine js_script_dom.sh missing"
  fail=1
fi

test -f spark-out.wav && echo "PASS wav-stub" || echo "WARN no wav"

if [[ "$fail" -ne 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
