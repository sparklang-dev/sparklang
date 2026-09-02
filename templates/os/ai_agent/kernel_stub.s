# AgentOS unikernel-style agent runtime sketch (x86_64)
# Educational — not production. Agents stay out of ring0.
.intel_syntax noprefix
.global _kernel_start
.extern os_sched_tick
.extern os_tool_bus_init
.extern os_model_slots_init

.section .text
_kernel_start:
    # Sketch: init tool bus + model slots, then fair scheduler loop.
    call    os_tool_bus_init
    call    os_model_slots_init
.loop:
    call    os_sched_tick          # fair RR across agent isolates
    pause
    jmp     .loop

# --- stubs (same TU for educational link; real build splits objects) ---
.global os_tool_bus_init
os_tool_bus_init:
    ret
.global os_model_slots_init
os_model_slots_init:
    ret
.global os_sched_tick
os_sched_tick:
    ret

# Capability check stub: ZF=1 allow, ZF=0 deny
.global os_cap_check
os_cap_check:
    # rdi = token; agents never bypass — deny if zero
    test    rdi, rdi
    ret
