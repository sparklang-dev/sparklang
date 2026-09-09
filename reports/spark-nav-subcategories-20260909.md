# Spark nav subcategories — 2026-09-09

Ship as **0.6.56** (0.6.53 is sensory mapping 100× on main).

## Goal
Category → subcategory → pages for Hive / Forge / Bench dropdowns,
knowledge hub cards, and knowledge-safety sections. Shared generator
keeps marketing + docs HTML consistent. Mobile-friendly nested menus
(labeled groups inside existing drawers).

## Subcategory map

| Category | Subcategory | Pages |
|----------|-------------|-------|
| **Hive** | *(hub)* | Knowledge hub |
| **Hive** | Foundations | LLMs & transformers · Training · Inference |
| **Hive** | Systems | Multimodal · Agents & tools |
| **Hive** | Safety / Eval | Eval honesty · Safety & limits |
| **Hive** | RE | Decompile + RE · LLM decompile research |
| **Forge** | Senses | Voice / STT / TTS · Voice ask · Voice easy |
| **Forge** | Models | Model aspects · Diagrams · Spark coder · Weight gallery · AI models |
| **Forge** | Train | Builder · Build models · Model training · Train loop |
| **Bench** | Language | Compile · Decompile · Opcodes / ISA · Programming guide |
| **Bench** | Runtime | Serve · IDE · IDE web shell · Network + web |
| **Bench** | Ops | Tools & helpers · About |

## Also
- Knowledge hub index: Foundations / Systems / Safety·Eval / RE card groups
- knowledge-safety: Model limits → Hallucination/…; Guardrails → …; Grounding (anti-guess placeholder)
- model-aspects: Category map (Senses / Models / Train·ops / Behaviors)
- Fixed leftover merge conflict markers on main tip (FACTORY, CI_PAGES, MODEL_ASPECTS)
- SoT: `tools/site_primary_nav.py` + `tools/sync_site_nav.py`; `make docs-html` syncs

## Never
RTX PRO 6000 · pre-Sep-2020 narrative years · beat Claude
