# SparkLang shadows (K-lane)

Safety tooling so experiments do not clobber primary artifacts.

| Mode | Invoke | What |
|------|--------|------|
| copy | `./helpers/spark-shadow copy PATH` | timestamped shadow beside file |
| build-dir | `./helpers/spark-shadow build-dir` | print/create `build/shadow/` |
| verify | `./helpers/spark-shadow verify ORIG SHADOW` | compare SHA-256 |
| verify-recompile | `./helpers/spark-shadow verify-recompile SRC.spark BC` | recompile + hash |

Default shadow build root: `build/shadow/` (override
`SPARK_SHADOW_ROOT`). Primary `out/train/` stays untouched when you
point `--weights` / checkpoints at the shadow dir.

Never 6000. Does not claim beat Claude.
