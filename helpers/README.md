# SparkLang helpers (K-lane)

Ergonomic CLIs wrapping real SPARK_BC compile / run / train / inspect
paths. CPU only. Never 6000. Does **not** claim beat Claude.

| Helper | Invoke | What |
|--------|--------|------|
| `spark-run` | `./helpers/spark-run file.spark` | compile → `--run-bc` → dump |
| `spark-train-proof` | `./helpers/spark-train-proof` | thin wrap of `make spark-sgd-proof` |
| `spark-check-env` | `./helpers/spark-check-env` | bootstrap / python / fixtures check |
| `spark-bc-pp` | `./helpers/spark-bc-pp file.sparkbc` | pretty-print SPARK_BC dump |
| `spark-bc-diff` | `./helpers/spark-bc-diff a.sparkbc b.sparkbc` | structural + hash diff |
| `spark-shadow` | `./helpers/spark-shadow …` | shadow copy / build dir / verify |
| `spark-ask` | `./spark-ask file.sparkbc --text "…"` | dump/text ask (TinyCoder or facts) |
| `spark-speak-ask` | `./spark-speak-ask file.sparkbc --dry` | voice ask loop (STT→TTS) |

Voice ask docs: [../docs/VOICE_ASK.md](../docs/VOICE_ASK.md).

Shadows: see [../shadows/README.md](../shadows/README.md).
Tool kit: `tools/spark_kit/` (`make helpers` / `make tools-test`).

Pack: `make sdk-pack` stages into `dist/spark-sdk/` (and overlays
I-lane `out/sdk-pack/` when present).
