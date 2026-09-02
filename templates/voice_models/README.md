# Written voice model templates

Copy `manifest.template.json` → `out/voice_models/<name>/manifest.json`
or use Spark:

```
voice model write NAME spec { ... } -> path
voice copy from "src.wav" to NAME -> path
```

`features.bin` is raw u64 coeffs (peak, rms, sr, silence, clip) written
by `voice copy` / `voice model write`.
