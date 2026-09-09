# SparkLang shadows (I-lane / pack)

Isolated copy → build → verify helpers for compile/decompile workflows.

| Script | What |
|--------|------|
| `shadow_copy.sh` | Mirror sources into `out/shadow/<name>/` |
| `shadow_build.sh` | `make spark-bootstrap` + `--compile` in the shadow |
| `shadow_verify.sh` | sha256 vs golden + SPARK_BC decode check |

CPU only. Never 6000. Does not claim beat Claude.
