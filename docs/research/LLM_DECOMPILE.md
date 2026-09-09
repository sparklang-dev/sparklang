# Research: LLMs that can decompile (and how that relates to Spark)

Engineer-grade survey for **Spark / SparkLang**. Verified with public
papers and tools (2024–2026). Honest about limits.

**SoT for SPARK_BC remains deterministic** (`--compile`, `dump.py`,
`--run-bc`). Optional LLM assist is a **later lane** for naming /
comments / drafts — never the authority for bytecode bytes.

Companion how-to: [DECOMPILE.md](../DECOMPILE.md)
([/docs/decompile.html](/docs/decompile.html)).
Mermaid overview: [DIAGRAMS.md](../DIAGRAMS.md)
([/docs/diagrams.html](/docs/diagrams.html)).

Does **not** beat Claude. **Never** 6000. **Never** claim any LLM
perfectly decompiles SPARK_BC.

## Diagrams (function layout)

### Deterministic Spark vs LLM assist

![Deterministic vs LLM](/docs/images/diagram-deterministic-vs-llm.svg)

*Caption: Spark SoT (left) vs optional LLM assist (right). Assist may
suggest names or draft source; it must not pack or silently rewrite
`.sparkbc`.*

### How LLMs typically assist compile / decompile

![LLM assist flows](/docs/images/diagram-llm-compile-decompile.svg)

*Caption: Industry pattern — decompile: bytes/asm → LLM guess →
human verify. Compile assist: intent → LLM draft → **Spark**
deterministic `--compile` → dump/`--run-bc` check. Orange = guessed;
green = SoT or human gate.*

### Spark tool paths (context)

![Compile path](/docs/images/diagram-compile-path.svg)

![Decompile path](/docs/images/diagram-decompile-path.svg)

*Caption: Same diagrams as the [decompile how-to](../DECOMPILE.md) —
where helpers / GUI sit relative to SPARK_BC.*

## Survey (cited)

### Specialized decompile LLMs

| Project | What it is | Notes / limits |
|---------|------------|----------------|
| **LLM4Decompile** | Open LLM series (≈1.3B–33B) trained for binary→C; End + Ref (refine Ghidra) | EMNLP 2024. Stronger re-exec than GPT-4o/Ghidra on HumanEval-Decompile / ExeBench in paper — still far from perfect; obfuscation resists both LLM and Ghidra. [arXiv:2403.05286](https://arxiv.org/abs/2403.05286) · [ACL PDF](https://aclanthology.org/2024.emnlp-main.203.pdf) · [GitHub](https://github.com/albertan017/LLM4Decompile) |
| **Nova** | Generative LLM for assembly (hierarchical attention + contrastive learning) | ICLR 2025. Improves binary code recovery / similarity vs prior; not a SPARK_BC tool. [OpenReview](https://openreview.net/forum?id=4ytRL3HJrq) · [GitHub lt-asset/nova](https://github.com/lt-asset/nova) |
| **SK2Decompile** | Two-phase “skeleton → skin” (structure then identifiers) on LLM4Decompile-class bases | arXiv 2025-09. Separates structure recovery from naming; RL objectives for compilability vs naming. [arXiv:2509.22114](https://arxiv.org/abs/2509.22114) |
| **Decompile-Bench** | ~2M binary–source function pairs + eval set | NeurIPS 2025 poster track. Fine-tuning improves re-exec ≈20% on their metrics — still partial. [arXiv:2505.12668](https://arxiv.org/abs/2505.12668) |
| **AutoDecompiler** | RL multi-turn refine with compile/exec feedback | arXiv 2026. Treats decompile as iterative repair, not one-shot. [arXiv PDF](https://arxiv.org/pdf/2606.16162) |
| **D-LIFT / Idioms / Ref-Decomp / DecLLM** | Pseudo-code refine, context, iterative repair | Cited in AutoDecompiler / SK2 surveys; functional correctness often fails ~half of HumanEval-Decompile-class tasks in reported baselines |

### Traditional decompiler + general LLM assistants

| Tool / pattern | Role | Cite |
|----------------|------|------|
| **Ghidra / IDA / Binary Ninja** | Deterministic (or heuristic) decompile → pseudocode | Industry SoT for native RE; LLM papers refine *their* output |
| **GhidraMCP / ReVa / Better-Ghidra-MCP / GhidraGPT** | MCP or plugin bridges so Claude/GPT/Codex rename, comment, explain | e.g. [LaurieWired/GhidraMCP](https://github.com/LaurieWired/GhidraMCP), [cyberkaida/reverse-engineering-assistant](https://github.com/cyberkaida/reverse-engineering-assistant), [Better-Ghidra-MCP](https://github.com/TheFlashBold/Better-Ghidra-MCP), [GhidraGPT](https://github.com/weirdmachine64/GhidraGPT) |
| **Claude / GPT / Codex as RE assistants** | Read dump/pseudocode; suggest names, summaries, patches | Useful for readability; **not** proven SPARK_BC→`.spark` fidelity |

### Bytecode / other RE note

Native x86/ARM C recovery dominates the literature. JVM/Python/WASM
and custom ISAs (including **SPARK_BC**) are **under-covered**. Do
not assume LLM4Decompile-style models transfer to Spark orchestration
opcodes without new data and evals.

## How this maps to Spark SPARK_BC

| Layer | Spark today | LLM role (optional later) |
|-------|-------------|---------------------------|
| Pack / unpack bytes | `--compile` / `dump.py` | **None** as SoT |
| Mnemonic listing | Deterministic opcode tables | Could annotate comments |
| Behavior | `--run-bc`, STEP, serve | Could explain JSON lines |
| Source recovery | **Not implemented** | Guessed `.spark` would need human + recompile gate |
| Naming | String pool as compiled | LLM rename suggestions only |

**Deterministic disasm vs LLM naming:** Spark dump is the ground
truth of what is in the file. An LLM may invent prettier names that
are wrong. Always recompile and re-dump to verify.

## Recommendations for Spark

1. Keep **deterministic decompiler/inspect** (`dump.py`, `--run-bc`)
   as SoT.
2. Optional later: LLM assist lane that consumes **dump text** only
   (comments / rename proposals) — never silent rewrite of `.sparkbc`.
3. Do **not** claim Spark “beats” LLM4Decompile / Nova / Claude on
   native binary benchmarks — different problem, different metrics.
4. If evaluating assist: measure dump→suggested-name accuracy and
   recompile round-trip — not marketing re-exec slogans.
5. **Never** route SPARK_BC factory train to GPU 6000.

## Operator brief (short)

- Specialized models (LLM4Decompile, Nova, SK2, AutoDecompiler) help
  **native** binary→C with partial re-exec; none are SPARK_BC SoT.
- General LLMs + Ghidra plugins excel at **annotation**, not guaranteed
  recovery.
- Spark path: compile/dump/run deterministic; LLM optional for docs-
  level assist only.
- Honest bar: no perfect SPARK_BC decompile claim; no beat Claude; no
  6000.

## Related

- [DECOMPILE.md](../DECOMPILE.md) · [COMPILE.md](../COMPILE.md)
- [FACTORY.md](../FACTORY.md) · [SPARK_BC.md](../SPARK_BC.md)
