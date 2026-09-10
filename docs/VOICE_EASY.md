# Voice easy — train STT / TTS in 3 steps

Piece-of-cake path for **owned** Spark voice-related heads we write
and train in this repo. Companion to [VOICE.md](VOICE.md) and
[Model aspects](MODEL_ASPECTS.md) (ears/speaking).

Owned Spark STT/TTS heads trained in this repo — not a vendor TTS SaaS.
Prefer CPU or a consumer GPU for optional train.

## 3 steps

```bash
# 1) Env check (no secrets)
./spark-voice env --dry

# 2) Tiny happy path (CI / laptop) — fixtures → train → prove
./spark-voice easy --dry --device auto

# 3) Status
./spark-voice status
```

Outputs:

- `models/spark-voice-easy/weights.safetensors` (+ `arch.json`,
 `checkpoint.json`)
- `out/voice_easy/fixtures/` — owned tone WAVs + phrases
- `out/voice_easy/roundtrip/` — TTS dry WAVs + `roundtrip.json`

## Scales

| Scale | How | Dims / steps | Device |
|-------|-----|--------------|--------|
| **tiny** (default) | `--scale tiny` or omit | dim 16, ~12 steps | CPU fine; CI |
| **large** (opt-in) | `--scale large` or `VOICE_SCALE=large` | dim 256, ~80 steps | Consumer GPU suggested; ~2 GiB VRAM hint |

```bash
# Large — opt-in; prefers a consumer GPU; fail closed without one
./spark-voice easy --scale large --device auto

# Large on CPU only when you explicitly ask (still owned weights)
./spark-voice easy --scale large --device cpu
```

Large ≠ production vendor quality. It is a **bigger owned head** for
local experiments — covers fixture-scale STT classify + PCM
tone TTS.

### Fail closed (device guard)

If `--scale large` and the visible GPU is reserved for other
workloads, Spark **refuses** (exit 2) unless you pass
`--device cpu`. Training never routes to reserved devices.

## Flags

| Flag / env | Meaning |
|------------|---------|
| `--dry` | CI-friendly (clamped steps) |
| `--device auto\|cpu\|…` | device pick; auto prefers a consumer GPU (or CPU) |
| `--scale tiny\|large` | model size |
| `VOICE_SCALE=large` | same as `--scale large` when flag omitted |

## Reuse ears / speaking

Language `listen` / `speak` and `./spark-stt-tts` stay the live
sidecar path ([VOICE.md](VOICE.md)). Voice-easy trains a **separate
owned head** under `models/spark-voice-easy/` so the training path
is obvious:

```text
ears (fixtures / spark-stt-tts)
 → voice-easy STT head (classify phrases)
brain (optional spark-coder / dump ask)
 → voice-easy TTS head (PCM params)
speaking (roundtrip WAV / spark-stt-tts speak)
```

## External STT / TTS sidecars (later)

Plug vendors **outside** these owned weights — same gates as voice:

| Gate | Meaning |
|------|---------|
| `SPARK_STT_CMD` / `SPARK_TTS_CMD` | Local shell (`%i` / `%o`) |
| `SPARK_STT_NET=1` + URL | HTTP STT |
| `SPARK_TTS_NET=1` + URL | HTTP TTS |

URL without gate → fail closed. Never commit Bearer keys.

## IDE

Spark IDE extension command **“Spark: Voice easy train”** runs
`./spark-voice easy --dry` (CLI-first; stub task hook).

## CLI / CI

```bash
./spark-voice easy --dry # dry tiny happy path
./spark-voice easy --scale large --device auto # opt-in local large
```

## Scope
| Claim | Status |
|-------|--------|
| Owned STT/TTS heads we train | **yes** (tiny + large) |
| CI dry green | **yes** (`make test-voice-easy`) |
| Vendor mega-TTS overnight | Out of scope |
| Marketing win banners | Out of scope |
