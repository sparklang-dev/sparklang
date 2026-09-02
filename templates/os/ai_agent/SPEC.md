# AgentOS spec (Spark `os specify` stub)

```yaml
kind: ai_agent
target: x86_64
memory_model: flat
ai:
  agent_runtime: true
  model_slots: 4
  tool_bus: true
  isolate_model: cooperative_tasks
  scheduler: fair_rr
drivers:
  - serial
  - framebuffer_stub
  - virtio_net_stub   # optional; off until owner enables
security:
  agent_ring0: false
  capability_tokens: true
optional_subsystems:
  - network_hooks     # Spark network ops reference
  - binary_analyze    # Spark binary ops reference
honesty: stub_blueprint_not_production
```

Edit this file when refining a design; regenerate docs with
`os generate` if you want a fresh tree copy from templates.
