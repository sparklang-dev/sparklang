# Spark OS design (AI / agent blueprints)

## Honest scope

Spark **`os`** ops produce **OS blueprints and educational /
bootable-style artifacts** (BIOS boot sector stub, unikernel-style
agent runtime sketch, syscall docs). They do **not**:

- Replace Linux on the developer host
- Reboot the host
- `dd` images onto real disks
- Claim a production-ready OS

Running stubs on bare metal is **owner-driven** on disposable media
only. Agents stop at `out/os/<name>/`.

## Language

| Statement | Result |
|-----------|--------|
| `os design name "…" kind ai_agent\|ai_runtime\|browser …` | JSON blueprint |
| `os specify blueprint { … }` | JSON / SPEC shape |
| `os generate … into "out/os/…"` | File tree from templates |
| `os build tree` | Dry-run: would assemble via tree Makefile |
| `os explain blueprint` | Exact why text for AI-agent shape |

Example:

```bash
./spark --dry-run examples/os_agentos.spark
```

## Emitted tree (`out/os/agentos/`)

Copied from `templates/os/ai_agent/`:

- `README.md` — scope bounds + build notes
- `SPEC.md` — target, AI knobs, security
- `MEMORY_MAP.md` — flat map + isolates
- `WHY.md` — exact why for agents
- `agent_syscall.md` — ask/classify/voice + tool bus
- `boot.s` / `kernel_stub.s` — educational asm
- `Makefile` — assemble stubs → `image.bin`
- `optional/net_binary_hooks.md` — optional net/binary refs

## AI / agent requirements (covered in templates)

- Cooperative task / isolate model (no ambient ring0)
- Model I/O syscalls (ask / classify / voice-shaped)
- Tool bus + capability tokens
- Fair RR scheduler notes for multi-agent
- Optional network + binary-analyze hooks (reference Spark
 `network` / `binary` ops; codegen stays in `asm/os_ops.s`)

## Implementation

| Piece | Path |
|-------|------|
| VM dispatch | `asm/spark.s` keyword `os` → `os_ops_dispatch` |
| Ops + generate | `asm/os_ops.s` (separate from binary/network) |
| Templates | `templates/os/ai_agent/` |
| Example | `examples/os_agentos.spark` |

## What “build” means

In dry-run, Spark prints that the generated Makefile would assemble
boot + kernel stubs. Assembling under `out/os/agentos/` is optional
and owner-local. **Never** write the image to a live system disk from
an agent session.

## Browser kind (`os generate` → browser scaffold)

Kind **`browser`** is a separate emit path from AgentOS. Line text
containing `browser` or `mitm` selects it (design / generate /
explain).

| Piece | Path |
|-------|------|
| Templates | `templates/os/browser/` |
| Emit tree | `out/os/browser_mitm/` |
| Example | `examples/browser_mitm.spark` |
| Product | `~/workspaces/spark-browser` (Qt WebEngine + MITM) |
| Scaffold refresh | `make browser-scaffold` |

### Emitted tree (`out/os/browser_mitm/`)

Copied from `templates/os/browser/` — **layout hooks**, not a second
MITM implementation and **not** AgentOS `boot.s` / `kernel_stub.s`:

- `README.md` / `SPEC.md` / `WHY.md` / `LAYOUT.md` — scope + path map
- `Makefile` / `.gitignore` — owner hooks mirroring product
- `docs/ARCHITECTURE.md` — proxy / inspector / HAR diagram
- `spark_browser/**/HOOKS.md` — package / mitm / inspector / cdp hooks
- `scripts/` `bin/` `tests/` HOOKS — product script/CLI/smoke map
- `data/ca/README.md` — CA dir contract (**no** private keys emitted)
- `optional/spark_network_hooks.md` — Spark `network analyze` bridge

### Browser scope
- MITM is **127.0.0.1 / this browser only**
- Never auto-install CA; never reboot the developer host
- Live Python MITM/CA stay in `spark-browser/` — templates document
 layout only
- Do not claim Chrome replacement or Speedometer wins without benches

```bash
./spark --dry-run examples/browser_mitm.spark # scaffold + flags
./spark --dry-run examples/browser_main.spark # dry language SoT
make browser-scaffold
cd ../spark-browser && make run # sole live entry
# dry E2E (no display): make test-e2e-browser
```
