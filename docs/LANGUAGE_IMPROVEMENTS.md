# Spark language improvements (2026-09-01)

Shippable DX wins — syntax, bootstrap VM, dry-run fixtures, stdlib includes.

## Summary (measurable)

| Metric | Before | After |
|--------|--------|-------|
| Model line | longer `model …` | shorter `use …` sugar (same explicit id) |
| Ask line chars | `ask "…"` (4+quote) | `? "…"` — **3 chars saved** |
| Default model source | empty until set | `spark.toml` + explicit statement |
| Stdlib reuse | copy-paste patterns | `include "lib/*.spark"` (bootstrap) |
| Prompt `{var}` binding | docs only | **bootstrap interpolates** |
| Dry fixture keywords | 5 needles | **12+ needles** (intent, json, weather, …) |
| Speak alias | `speak` only | `say` alias (GAS + bootstrap) |

## 1. `use` — sugar for `model`

**Why:** Shorter programs; same explicit model id (HF / path / configured
name). Not a the AI gateway alias picker.

```
# before
model "fixtures/tiny-lm"

# after
use "fixtures/tiny-lm"
```

Works in `./spark` (GAS) and `./spark-bootstrap` (C VM).
`use auto` keeps the prior configured line — it does **not** invent
`fast`/`code` from task text.

## 2. `?` — alias for `ask`

**Why:** Questions visually match intent; fewer keystrokes in scripts.

```
# before
ask "Explain gravity in one sentence" -> text

# after
? "Explain gravity in one sentence" -> text
```

Works in GAS and bootstrap. Live path unchanged (`--live` + companion).

## 3. `say` — alias for `speak`

```
say "Hello" -> "out.wav"
```

## 4. `include "path"` — bootstrap only

**Why:** Share stdlib snippets without a full module system yet.

```
include "lib/ai.spark"
? "Hello" -> reply
```

- Cycle detection + depth limit (8).
- `./spark` (GAS) does not implement include — use bootstrap for self-host lane B.

Stdlib:

- `lib/ai.spark` — default model + patterns
- `lib/pipeline.spark` — pipeline documentation / templates

## 5. `spark.toml` model default — bootstrap

Reads `model = "alias"` from cwd `spark.toml` on VM init.
Statement `model` / `use` in `.spark` overrides.

## 6. `{var}` interpolation — bootstrap `ask` / `?`

**Why:** Pipeline examples in docs finally work in bootstrap dry-run.

```
let topic "gravity"
? "Explain {topic} in one sentence" -> text
```

Unknown `{name}` → fail loud (no silent empty).

## 7. Richer dry-run fixtures

Added keyword → reply mapping (GAS + bootstrap):

| Prompt contains | Dry reply |
|---------------|-----------|
| gravity / explain / one sentence | Gravity one-liner |
| summar | Summary stub |
| spanish / translate | Spanish stub |
| intent / classify | JSON label stub |
| json / extract | Person JSON stub |
| weather | Springfield weather stub |
| reply / helpfully | Helpful reply stub |

## 8. Clearer errors — bootstrap

Unknown statements print a **hint** line listing common ops.

## Examples

| File | Proves |
|------|--------|
| `examples/hello_sugar.spark` | `use` + `?` |
| `examples/dx_showcase.spark` | sugar + `{var}` + pipeline |
| `bootstrap/fixtures/dx_include.spark` | `include` (bootstrap tests) |

## Not in this pass

- GAS `include` (self-host lane C first)
- Full module `import` with namespaces
- `{var}` in GAS ask (bootstrap only for now)
