# WHY this OS shape for AI agents

Spark `os explain` / generate writes this so the blueprint stays
reviewable — not marketing.

## Exact why

1. **Agents are not Unix processes by default.** A laundry of
   processes + libc is the wrong unit. AgentOS uses **cooperative
   tasks / isolates** with explicit stacks and a shared tool bus so
   multi-agent fairness is a scheduler concern, not an accident of
   `nice(2)`.

2. **Model I/O is a syscall surface.** `ask` / `classify` / voice-
   shaped rings are first-class (see `agent_syscall.md`). Glue SDKs
   belong above the kernel; the stub kernel owns slots + backpressure.

3. **Capability tokens beat ambient authority.** Tools are gated by
   tokens minted by the kernel. Agents never receive raw ring0 or
   unrestricted DMA.

4. **Scheduler fairness for multi-agent.** Round-robin / weighted
   quanta across isolates; model-slot waits do not starve peer agents.

5. **Optional net + binary-analyze.** Reference Spark’s `network` /
   `binary` ops as *optional* subsystems — separate objects
   (`optional/`), never mixed into boot labels with the binary agent’s
   asm.

6. **Educational boot path.** `boot.s` + `kernel_stub.s` prove the
   blueprint is assemblable. They are **stubs**, not this host's OS.

## What this is not

- Not “we replaced Linux”
- Not production-ready
- Not an agent-authorized host install or reboot
