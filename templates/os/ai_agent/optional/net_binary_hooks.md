# Optional subsystems — network + binary-analyze hooks

These are **opt-in**. They reference Spark’s existing ops; they do not
fight sibling agents on shared asm labels.

| Hook | Spark surface | AgentOS placement |
|------|---------------|-------------------|
| Packet / capture explain | `network capture\|open\|analyze\|explain` | optional driver; capability-gated |
| ELF / firmware structure | `binary open\|elf\|disasm\|understand` | offline analyze task, not ring0 |

## Implementation note (Spark repo)

- Host VM OS codegen lives in **`asm/os_ops.s`** (separate object).
- Binary / network stay in **`asm/binary_ops.s`** /
  **`asm/network_ops.s`**.
- Generated AgentOS trees keep optional docs here; do not merge
  labels into `boot.s` / `kernel_stub.s` without an owner review.

## Security

Enabling a hook still requires a capability token. Agents cannot open
raw sockets or map kernel memory without an explicit mint.
