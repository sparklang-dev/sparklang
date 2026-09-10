# Research: LLMs that can decompile (and how that relates to Spark)

Engineer-grade survey for **Spark / SparkLang**. Verified with public
papers and tools (2024–2026). **SoT for SPARK_BC remains deterministic** (`--compile`, `dump.py`,
`--run-bc`). Optional LLM assist is for naming / comments / drafts —
never the authority for bytecode bytes.

Companion how-to: [Decompile](../DECOMPILE.md)
([/docs/decompile.html](/docs/decompile.html)).
Mermaid overview: [Diagrams](../DIAGRAMS.md)
([/docs/diagrams.html](/docs/diagrams.html)).

Does **not** claim any LLM
perfectly decompiles SPARK_BC. Native RE benchmarks are a different
problem space from SPARK_BC SoT.

## Further reading

Selected public papers, repos, and articles:

1. DecompAI discussion (agent-style RE):
 https://www.reddit.com/r/ReverseEngineering/comments/1kt2gcb/decompai_an_llmpowered_reverse_engineering_agent/
2. LLM4Decompile discussion:
 https://www.reddit.com/r/ReverseEngineering/comments/1bfkvbq/llm4decompile_decompiling_binary_code_with_large/
3. LLM4Decompile project (End/Ref, SK²Decompile, decompile-bench;
 HF models; re-exec metrics; Ghidra refine path):
 https://github.com/albertan017/LLM4Decompile
4. End-to-end LLM decompilation survey (ReF, Idioms, SALT, SK²,
 WaDec, SmartHalo, ICL4Decomp; metrics RRR / R2I / …):
 https://www.emergentmind.com/topics/end-to-end-llm-decompilation
5. Quarkslab — defeating (or not) AI-assisted RE; agents route
 around static hardening; hallucination / cheating; obfuscation
 as cost multiplier:
 https://blog.quarkslab.com/defeating-ai-assisted-reverse-engineering-or-at-least-trying-to.html
6. Quarkslab reverse-engineering category (continuing RE source —
 follow alongside the AI-assisted RE article above):
 https://blog.quarkslab.com/category/reverse-engineering.html
7. Plain English overview — demystifying decompilation with LLMs
 (accessible survey / pipeline survey; not SPARK_BC SoT):
 https://ai.plainenglish.io/demystifying-decompilation-with-large-language-models-0e63bf067045
8. OpenBin — commercial/online AI decompiler & RE platform
 (browser + cloud projects; **not** open research weights like
 LLM4Decompile; **not** SPARK_BC SoT; third-party upload /
 trust/IP implications):
 https://openbin.ai/

**Also useful for theme discovery** (not primary references): search
snippets on “AI LLM-based decompilers” — always verify against the
sources above and against Spark’s local dump / compile SoT.
Prefer the canonical paper / product URLs listed here over overview
text.

## Overview (LLM decompilers — native binaries)

LLM decompilers translate binaries / assembly → high-level C/C++
(or readable pseudocode). Two common shapes:

| Approach | Idea | Caveat |
|----------|------|--------|
| **Refine-based** | Classical decompiler (Ghidra / IDA / Hex-Rays) → LLM cleans / renames / repairs | Still inherits classical misses; fluent C ≠ verified semantics |
| **End-to-end** | Asm / bytes → LLM source in one generative path (optionally with tool calls) | Less tool dependence; still partial re-exec on hard opts |

Papers and products often advertise **readability** and
**recompilability**. **Recompile ≠ semantic fidelity:** a candidate
can build and pass shipped I/O tests while diverging on other inputs
(or silently dropping crash/vuln behavior). That risk binds any
future Spark LLM assist lane — dump / `--compile` / `--run-bc` stay
SoT; never treat “it recompiled” as SPARK_BC truth.

## Diagrams (function layout)

### Deterministic Spark vs LLM assist

![Deterministic vs LLM](/docs/images/diagram-deterministic-vs-llm.svg?v=0.6.60)

*Caption: Spark SoT (left) vs optional LLM assist (right). Assist may
suggest names or draft source; it must not pack or silently rewrite
`.sparkbc`.*

### How LLMs typically assist compile / decompile

![LLM assist flows](/docs/images/diagram-llm-compile-decompile.svg?v=0.6.60)

*Caption: Industry pattern — decompile: bytes/asm → LLM guess →
human verify. Compile assist: intent → LLM draft → **Spark**
deterministic `--compile` → dump/`--run-bc` check. Orange = guessed;
green = SoT or human gate.*

### Spark tool paths (context)

![Compile path](/docs/images/diagram-compile-path.svg?v=0.6.60)

![Decompile path](/docs/images/diagram-decompile-path.svg?v=0.6.60)

*Caption: Same diagrams as the [decompile how-to](../DECOMPILE.md) —
where helpers / GUI sit relative to SPARK_BC.*

## Two different LLM “decompile” shapes

Do not conflate these — they imply different Spark policy.

| Shape | What it does | Spark takeaway |
|-------|--------------|----------------|
| **Seq2seq / specialized decompile models** | One-shot or refine: asm/bytes → guessed C (or IR→names). Train/eval on re-exec, edit similarity, R2I, etc. | Interesting research for *native* C; **not** SPARK_BC SoT; no transfer assumed |
| **Agent-style RE (tool loop)** | LLM plans → runs Ghidra / objdump / gdb / emulate → iterates. May route *around* static analysis | Closer to “assistant with shell”; still can hallucinate or cheat; must never overwrite `.sparkbc` |

### DecompAI — agent-style RE (not a seq2seq model)

**DecompAI** (community write-ups +
[louisgthier/decompai](https://github.com/louisgthier/decompai)) is an
**LLM agent** (LangGraph / Gradio, ReAct-style) that **orchestrates
tools** (objdump, gdb, Ghidra hooks, shell) over x86 Linux ELFs in a
chat loop. That is **distinct** from LLM4Decompile-class models that
map linearized assembly → C in one generative pass.

Reddit thread:
https://www.reddit.com/r/ReverseEngineering/comments/1kt2gcb/decompai_an_llmpowered_reverse_engineering_agent/

Honest limits: exploratory RE accelerator for supported binaries —
**not** a verified SPARK_BC→`.spark` recovery pipeline, and not
proof that agent output is ground truth.

## Survey (cited)

### Specialized decompile LLMs (seq2seq / staged)

| Project | What it is | Notes / limits |
|---------|------------|----------------|
| **LLM4Decompile** | Open LLM series (≈1.3B–33B) for binary→C; **End** (asm→C) + **Ref** (refine Ghidra pseudocode); HF-hosted weights; siblings **SK²Decompile**, **decompile-bench** | EMNLP 2024. Paper reports stronger re-exec than GPT-4o/Ghidra on HumanEval-Decompile / ExeBench — still far from perfect; obfuscation resists both LLM and Ghidra. Repo: [albertan017/LLM4Decompile](https://github.com/albertan017/LLM4Decompile). Reddit: [r/ReverseEngineering](https://www.reddit.com/r/ReverseEngineering/comments/1bfkvbq/llm4decompile_decompiling_binary_code_with_large/). Papers: [arXiv:2403.05286](https://arxiv.org/abs/2403.05286) · [ACL PDF](https://aclanthology.org/2024.emnlp-main.203.pdf) |
| **Nova** | Generative LLM for assembly (hierarchical attention + contrastive learning) | ICLR 2025. Improves binary code recovery / similarity vs prior; not a SPARK_BC tool. [OpenReview](https://openreview.net/forum?id=4ytRL3HJrq) · [GitHub lt-asset/nova](https://github.com/lt-asset/nova) |
| **SK²Decompile** | Two-phase “skeleton → skin” (structure then identifiers) on LLM4Decompile-class bases | arXiv 2025-09. Separates structure recovery from naming; RL objectives for compilability vs naming. Survey cites ~69% avg re-exec on HumanEval (O0–O3) in *their* metrics — still not perfect, not SPARK_BC. [arXiv:2509.22114](https://arxiv.org/abs/2509.22114) |
| **Decompile-Bench** (LLM4Decompile sibling dataset) | ~2M binary–source function pairs + eval set | NeurIPS 2025 poster track. Fine-tuning improves re-exec ≈20% on their metrics — still partial. [arXiv:2505.12668](https://arxiv.org/abs/2505.12668) |
| **DecompileBench** (ACL eval framework) | Comprehensive real-world decompiler eval (OSS-Fuzz-derived functions; recompilation + runtime + LLM-as-Judge readability) | ACL Findings 2025. LLM methods can look more readable while lagging traditional tools on functional correctness — same “pretty ≠ correct” lesson. [ACL Anthology](https://aclanthology.org/2025.findings-acl.1194/) · [arXiv:2505.11340](https://arxiv.org/abs/2505.11340) |
| **AutoDecompiler** | RL multi-turn refine with compile/exec feedback | arXiv 2026. Treats decompile as iterative repair, not one-shot. [arXiv:2606.16162](https://arxiv.org/abs/2606.16162) |
| **DecLLM** | Iterative LLM repair of classical decompiler output: static recompile diagnostics + dynamic runtime / ASAN feedback | ISSTA 2025. Raises recompilability for programmatic use of decompiled C — still not perfect; commercial LLM API path has cost/privacy trade-offs. [ACM](https://doi.org/10.1145/3728958) · [PDF](https://daoyuan14.github.io/papers/ISSTA25_DecLLM.pdf) |
| **HELIOS** | Graph-to-text: hierarchical CFG / call-graph abstraction into LLM prompts (+ optional compiler-in-the-loop) | NDSS Symposium 2026 (LAST-X). Structure-aware prompting without fine-tuning; compilability gains ≠ SPARK_BC SoT. [NDSS](https://www.ndss-symposium.org/ndss-paper/auto-draft-684/) · [arXiv:2601.14598](https://arxiv.org/abs/2601.14598) |
| **ReF / Interactive End-to-End** | End-to-end asm→C with relabeling + interactive binary data access; MDPI article frames refine vs end-to-end | Improves HumanEval-Decompile-class re-exec in paper metrics; still native-C research. [arXiv:2502.12221](https://arxiv.org/abs/2502.12221) · [MDPI Electronics](https://www.mdpi.com/2079-9292/14/22/4442) |
| **When LLM Decompilers Recompile More and Preserve Less** | Behavioral oracle (Decompile-Diverge): recompile/pass-shipped-tests can still diverge on other inputs; vulns can vanish | arXiv 2026-09. **Important for Spark** for any future LLM assist — recompile metrics can reward the wrong path. [arXiv:2609.05370](https://arxiv.org/abs/2609.05370) |
| **ReF / Idioms / SALT / ICL4Decomp / …** | Structure-augmented or staged: relabel jumps (ReF), joint code+types (Idioms), SALT logic trees, in-context exemplars (ICL4Decomp) | See EmergentMind survey below. Functional correctness still often fails a large share of hard suites |

### Survey landscape (EmergentMind)

Owner cite:
https://www.emergentmind.com/topics/end-to-end-llm-decompilation

Useful vocabulary (native C / Wasm / Solidity — **not** SPARK_BC):

| Family | Idea (one line) |
|--------|-----------------|
| **ReF Decompile** | Relabel addresses + tool-backed literal recovery from `.rodata` |
| **Idioms** | Joint generation of source **and** user-defined types |
| **SALT4Decompile** | Source-level abstract logic tree before LLM decode |
| **SK²Decompile** | Structure IR first, identifier naming second |
| **WaDec / StackSight** | Wasm→C-ish with loop/stack cues |
| **SmartHalo** | EVM/Solidity recovery with dependency graphs |
| **ICL4Decomp** | Retrieval / rule-based in-context prompts for opt levels |

**Metrics you will see** (paper-specific; do not invent Spark scores):

- **Re-executability / RRR** — recompile + pass original tests
- **R2I** — relative readability (AST-ish)
- Edit similarity, CER (coverage equivalence), Elo-style LLM judges

Survey note: even strong native numbers leave large failure rates;
LLM output can be more *readable* while less *functionally correct*
than classical decompilers on some benches. **None of this is a
SPARK_BC fidelity claim.** See also the Plain English overview
section below.

### Traditional decompiler + general LLM assistants

| Tool / pattern | Role | Cite |
|----------------|------|------|
| **Ghidra / IDA / Binary Ninja** | Deterministic (or heuristic) decompile → pseudocode | Industry SoT for native RE; LLM papers refine *their* output |
| **GhidraMCP / ReVa / Better-Ghidra-MCP / GhidraGPT** | MCP or plugin bridges so Claude/GPT/Codex rename, comment, explain | e.g. [LaurieWired/GhidraMCP](https://github.com/LaurieWired/GhidraMCP), [cyberkaida/reverse-engineering-assistant](https://github.com/cyberkaida/reverse-engineering-assistant), [Better-Ghidra-MCP](https://github.com/TheFlashBold/Better-Ghidra-MCP), [GhidraGPT](https://github.com/weirdmachine64/GhidraGPT) |
| **DecompAI (agent)** | Tool-loop RE over binaries (see above) | [GitHub](https://github.com/louisgthier/decompai) · [Reddit](https://www.reddit.com/r/ReverseEngineering/comments/1kt2gcb/decompai_an_llmpowered_reverse_engineering_agent/) |
| **Claude / GPT / Codex as RE assistants** | Read dump/pseudocode; suggest names, summaries, patches | Useful for readability; **not** proven SPARK_BC→`.spark` fidelity |

### Commercial / online AI decompiler products

Distinct from **open research** models (LLM4Decompile, Nova, SK², …):

| Product | What it is | Spark status |
|---------|------------|---------------|
| **OpenBin** ([openbin.ai](https://openbin.ai/)) | Free / open-source **online** AI reverse-engineering platform (The Open Binary Project): browser UI, cloud projects, Ghidra-backed native decompile + agent Q&A, BYOK LLM keys; sibling OpenAPK for Android. Source: [openbin-ai/platform](https://github.com/openbin-ai/platform). CLI pin: [openbin-v0.10.0](https://github.com/openbin-ai/platform/releases/tag/openbin-v0.10.0). | **Not** SPARK_BC SoT. Uploading binaries (or decompile artifacts) to a third party has **trust / IP / malware-handling** implications. Spark keeps **local** deterministic `dump.py` / `--compile` / `--run-bc`. Do not treat OpenBin output as verified Spark recovery. See also [Methods vs OpenBin](../METHODS_OPENBIN.md). Prefer a **gated lab** container if you run their CLI at all; binary stays local. |

### Quarkslab: why LLM output is not verified SoT

Cited (article + continuing category index):

- https://blog.quarkslab.com/defeating-ai-assisted-reverse-engineering-or-at-least-trying-to.html
- https://blog.quarkslab.com/category/reverse-engineering.html
 (Quarkslab RE category — keep as an ongoing source next to the
 specific AI-assisted RE post)

Takeaways that bind Spark policy (paraphrase, not marketing):

1. **Agents route around static hardening** — when CFG/MBA noise is
 expensive, they lift/emulate/patch instead of “solving”
 deobfuscation. A fluent narrative ≠ they understood the protect.
2. **Hallucination and cheating** — agents take the cheapest path to
 something answer-shaped (leaked keys, prior session flags, wrong
 ISA stories). Confidence stays high either way.
3. **Artifacts lie** — a script that prints the right string may
 hardcode it or skip the claimed emulator; report quality ≠ proof.
4. **Obfuscation remains a cost multiplier** — not obsolete; it pushes
 agents onto dynamic / hallucinated paths. Throughput changes; SoT
 does not.

**Other RE themes on that category index** (link the category; do
**not** treat titles as Spark product claims — status for tooling
expectations only):

- **Firmware / hardware RE** — black-box secure chips, smartwatch
 firmware teardown, blinkenlights-style extract paths; slow
 evidence work, not one-shot LLM “decompile.”
- **VM attack comparison (QBDI vs TritonDSE)** — dynamic
 instrumentation / DSE trade-offs against a protected VM; reminds
 that bytecode-ish VMs need *instrumentation evidence*, not fluent
 narrative alone.
- **Obfuscation** — same cost-multiplier theme as the AI-assisted RE
 post; hardening raises agent cost, it does not mint verified SoT.

**Spark implication:** treat any LLM / agent decompile or rename as
**assist only**. Verified bytes and behavior stay
`--compile` / `dump.py` / `--run-bc` (+ human). Never promote model
text to SPARK_BC SoT because it “looked right.”

### Plain English: demystifying LLM decompilation

Overview cite:
https://ai.plainenglish.io/demystifying-decompilation-with-large-language-models-0e63bf067045

Use as a readable overview of how LLM decompile *pipelines* are
framed in industry writing (stages, assist roles, failure modes).
It does **not** change Spark policy: dump/`--compile`/`--run-bc`
remain SoT; LLM text is assist; no perfect SPARK_BC recovery claim;
### Bytecode / other RE note

Native x86/ARM C recovery dominates the literature. JVM/Python/WASM
and custom ISAs (including **SPARK_BC**) are **under-covered**. Do
not assume LLM4Decompile-style models or DecompAI tool loops transfer
to Spark orchestration opcodes without new data and evals.

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
3. Do **not** claim Spark “beats” LLM4Decompile / Nova / DecompAI /
 Claude / OpenBin on native binary benchmarks — different problem,
 different metrics.
4. If evaluating assist: measure dump→suggested-name accuracy and
 recompile round-trip — and remember **recompile more ≠ preserve
 more** ([arXiv:2609.05370](https://arxiv.org/abs/2609.05370)).
5. Treat agent loops (DecompAI / OpenBin-class) with the same
 Quarkslab caution: tool traces can still cheat or invent; require
 dump/`--run-bc` gates. Prefer **local** artifacts over third-party
 upload for proprietary SPARK_BC.
6. Prefer CPU / RTX **5090** for any SPARK_BC factory GPU train
 (see [Factory hub](../FACTORY.md)); leave reserved GPUs alone.

## Operator brief (short)

- Specialized models (LLM4Decompile End/Ref, Nova, SK², AutoDecompiler,
 DecLLM, HELIOS, ReF) help **native** binary→C with **partial**
 re-exec; none are SPARK_BC SoT.
- **DecompileBench** (ACL) and **Recompile More / Preserve Less**
 both warn: readable / recompilable output can still be semantically
 wrong — call this out for any future Spark LLM assist.
- **OpenBin** = online commercial/community AI RE product — distinct
 from open research weights; not Spark SoT; third-party trust/IP.
- **DecompAI** = agent + tools, not the same as seq2seq decompile
 models.
- Quarkslab: agents evade, hallucinate, and write confident wrong
 artifacts — another reason LLM ≠ verified decompile SoT. Keep
 following the RE category index (firmware, QBDI/TritonDSE VM
 attacks, obfuscation) without scraping it into this page.
- Plain English demystify piece is a readable overview only — not a
 SPARK_BC fidelity claim. Google AI Overview clusters are
 **secondary**.
- General LLMs + Ghidra plugins excel at **annotation**, not
 guaranteed recovery.
- Spark path: compile/dump/run deterministic; LLM optional for docs-
 level assist only.
- Honest bar: no perfect SPARK_BC decompile claim; no competitive AI win claim /
 no beat these models/products. GPU train: see factory policy.

## Related

- [Decompile](../DECOMPILE.md) · [COMPILE.md](../COMPILE.md)
- [Factory hub](../FACTORY.md) · [SPARK_BC.md](../SPARK_BC.md)
- [Diagrams](../DIAGRAMS.md) (Mermaid; screenshots live on
 DECOMPILE)
