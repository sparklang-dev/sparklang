# Methods we adopted vs rejected (OpenBin prior art)

Spark studied **public** OpenBin surfaces (site copy, CLI `--help` in
a gated lab, [release v0.10.0](https://github.com/openbin-ai/platform/releases/tag/openbin-v0.10.0),
[openbin-ai/platform](https://github.com/openbin-ai/platform) README)
to improve **our** loop — not to clone their product.

Prior art link only: [https://openbin.ai/](https://openbin.ai/).
Spark remains local-first SPARK_BC. Dump / `--compile` / `--run-bc`
are SoT. **Never** 6000. Does **not** beat Claude.

Hub: [FACTORY.md](FACTORY.md) · Loop UX: [/workflow.html](/workflow.html)
· Helpers: [TOOLS_HELPERS.md](TOOLS_HELPERS.md) · Research:
[research/LLM_DECOMPILE.md](research/LLM_DECOMPILE.md).

## Adopted (methods → Spark-native)

| OpenBin method (public) | Spark improvement |
|-------------------------|-------------------|
| One CLI path that lands you in an inspectable **project** | `helpers/spark-analyze` → `out/analyze/<name>/` with dump, ops list, REPORT stub |
| Clear **local-first** story for native binaries | Keep binary / SPARK_BC **local**; analysis folder never uploads |
| Side-by-side inspect vocabulary | Existing `dump.py` + `spark-bc-gui` + loop UX (`/workflow.html`, the loop UX) |
| Optional **Ask** after inspect | `--ask` stub via **owned** `spark-coder` or honesty note — not their SaaS |
| Publish / share findings | Docs + Pages share (examples gallery) — **not** a malware community feed |
| apk vs elf as separate worker paths | Spark stays SPARK_BC-only; no JADX/Ghidra workers in this lane |

## Rejected

| Idea | Why rejected |
|------|----------------|
| Cloud project URL as default SoT | Spark SoT is local dump / SPARK_BC bytes |
| Upload decompiled JSON / APK trees to a third party | Trust / IP / malware-handling; gated lab only for studying their CLI |
| BYOK Anthropic/OpenAI keys in git or Spark CLI defaults | Prefer owned TinyCoder / gateway aliases elsewhere; no keys in git |
| Pixel-clone of OpenBin / OpenAPK UI | Original Spark loop branding (the loop UX) |
| Ghidra/JADX Docker workers as Spark runtime | Different problem (ELF/APK RE vs SPARK_BC orchestration) |
| “AI recovered perfect source” marketing | Forbidden; LLM research stays cited and non-SoT |
| Beat Claude / use RTX PRO 6000 | Standing Spark policy |

## CLI quick path (Spark)

```bash
make helpers
./helpers/spark-analyze docs/examples/spark-train-step.sparkbc
./helpers/spark-analyze examples/spark_train_step.spark --ask
./helpers/spark-analyze file.sparkbc --serve -o out/analyze/demo
# → out/analyze/<name>/{dump.txt,ops.json,REPORT.md,META.json,…}
```

Gate: `make test-spark-analyze` (or `PYTHONPATH=python:tools python3 -m unittest tools.spark_analyze.test_analyze -v`).

## Ethics / lab note

The OpenBin CLI (**v0.10.0**) belongs in a **gated lab** container
(`openbin-lab` DinD) when used at all — not as a parallel SPARK_BC
SoT. Do not dump proprietary worker image layers for redistribution.
Login/BYOK for deeper OpenBin probes is optional operator work; this
doc does not require it.
