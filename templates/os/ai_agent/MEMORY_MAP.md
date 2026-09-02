# Memory map (flat x86_64 sketch)

Educational layout for the AgentOS stub. Not a claim of a shipped MMU
policy.

| Region | Addr (sketch) | Size | Who |
|--------|---------------|------|-----|
| Boot sector | `0x7C00` | 512 B | BIOS load |
| Kernel stub | `0x10000` | ~64 KiB | ring0 runtime |
| Tool-bus table | `0x20000` | 4 KiB | capability tokens |
| Model slots | `0x30000` | 4 × 16 KiB | ask/classify/voice I/O rings |
| Agent isolates | `0x40000+` | N × 64 KiB | cooperative tasks |
| Framebuffer stub | `0xA0000` | VGA-era stub | optional |
| Virtio-net stub | `0xB00000` | page | optional subsystem |

## Isolation

- Default: **cooperative tasks** in separate stacks with capability
  checks on every tool/syscall.
- Optional later: paging / rings for harder isolates — still no agent
  ring0 by default.
