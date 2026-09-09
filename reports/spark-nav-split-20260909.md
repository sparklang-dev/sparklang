# Spark site nav split — 2026-09-09

## Problem
Primary nav dumped ~12–25 links under a single **More** drawer (inconsistent
across marketing vs docs pages).

## Structure (unified)

| Slot | Contents |
|------|----------|
| Top-level | Loop · Learn · Docs · **Factory** · Download · Try |
| **Forge** ▾ | Model aspects, Diagrams, Builder, Build models, Model training, Train loop, Spark coder, AI models, Voice / STT / TTS |
| **Bench** ▾ | Compile, Decompile, Programming guide, IDE, IDE web shell, Network + web, Serve, Tools & helpers, About |

Deep docs (opcodes, attention, tokenizer, eval, make, CI, adoption,
architecture, LLM research, self-host, …) stay reachable via **Docs** /
**Factory** hubs — not duplicated in the header junk drawer.

## Touched
- All `website/**/*.html` with primary nav
- `tools/md_to_doc_html.py` generator template
- `website/js/site.js` — Docs aria-current skips Factory + Forge/Bench hits

## Base
Rebased on `origin/main` @ `b47ca61` (UI polish #37 already merged).
