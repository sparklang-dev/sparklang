# Agent syscalls (sketch)

Numbers are educational — not a frozen ABI. Agents call these from
user-mode; the kernel validates capability tokens.

| Nr | Name | Shape | Notes |
|----|------|-------|-------|
| 1 | `sys_ask` | `(slot, prompt_ptr, len, out_ptr, out_len)` | Model I/O ask |
| 2 | `sys_classify` | `(slot, text_ptr, labels_ptr, out_ptr)` | Label + confidence |
| 3 | `sys_voice_in` | `(slot, pcm_ptr, len)` | Voice-shaped listen |
| 4 | `sys_voice_out` | `(slot, pcm_ptr, len)` | Voice-shaped speak |
| 5 | `sys_tool_call` | `(cap_token, tool_id, args_ptr, out_ptr)` | Tool bus |
| 6 | `sys_cap_mint` | `(agent_id, rights_mask) → token` | Kernel only path |
| 7 | `sys_yield` | `()` | Cooperative schedule |
| 8 | `sys_spawn_task` | `(entry, stack, rights)` | New isolate |
| 9 | `sys_net_*` | optional | See `optional/net_binary_hooks.md` |
| 10 | `sys_bin_*` | optional | Binary-analyze hook |

## Security

- Missing / forged capability → `#GP`-style deny (stub: return `-EPERM`).
- `sys_cap_mint` is **not** exposed to agents; only the kernel / trusted
  supervisor path.
- No syscall grants raw port I/O or page-table writes to agents.
