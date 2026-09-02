# AgentOS blueprint (Spark-generated stub)

**Honesty bound:** This tree is an **OS blueprint + educational /
bootable-style stubs**, not a production operating system and **not**
a replacement for Linux on this host. Spark never reboots the host and
never installs an OS on live disks.

## What you get

| Artifact | Role |
|----------|------|
| `SPEC.md` | Target arch, memory model, AI runtime knobs |
| `MEMORY_MAP.md` | Flat x86_64 sketch (boot / kernel / agents) |
| `boot.s` | Classic BIOS boot-sector educational stub |
| `kernel_stub.s` | Unikernel-style agent runtime sketch |
| `agent_syscall.md` | Model I/O + tool-bus syscalls |
| `WHY.md` | Exact why this shape for AI agents |
| `Makefile` | Assemble stubs → `image.bin` (owner-driven) |
| `optional/net_binary_hooks.md` | Optional net + binary-analyze subsystems |

## Build (owner-driven, never auto on this host)

```bash
cd out/os/agentos   # or your generate path
make                # assembles boot+kernel stubs
# Do NOT dd image.bin onto a real disk from agents.
# Bare-metal boot is an owner decision on disposable media only.
```

## Security defaults

- Agents run in **user-mode isolates** (or cooperative tasks) — **no
  raw ring0** by default.
- Tool bus uses **capability tokens**; ring0 stays in the tiny kernel.
- Optional network / binary-analyze hooks are **opt-in** and live in
  separate objects (see Spark `asm/os_ops.s` vs `binary_ops` /
  `network_ops` — no shared asm label fights).

## Generate again

```bash
./spark --dry-run examples/os_agentos.spark
```
