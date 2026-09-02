# SPEC — browser_mitm (os kind browser)

```yaml
kind: browser
name: browser_mitm
target: x86_64 Linux (Linux / Ubuntu)
memory_model: host_process   # not AgentOS flat unikernel
ui_engine: Qt WebEngine (PyQt5)
mitm:
  mode: local_connect_proxy
  bind: 127.0.0.1
  default_port: 8877
  leaf_certs: dynamic_from_owner_ca
ca:
  dir: data/ca/
  files: [ca.pem, ca.key]    # product tree; never emit secrets here
cdp:
  host: 127.0.0.1
  port: 9222
  env: QTWEBENGINE_REMOTE_DEBUGGING
inspector:
  timeline: true
  har_export: true
  filters: [url_regex, breakpoint_regex]
ai:
  agent_runtime: false       # browser appliance, not AgentOS
  tool_bus: false
  mitm_inspector: true
drivers:
  - webview_host
  - virtio_net_stub          # optional; Spark network analyze bridge
features: [net, mitm, webview]
product_tree: ../spark-browser
honesty: scaffold_not_chrome_replacement
```

Edit hooks under `spark_browser/**/HOOKS.md` when refining layout;
regenerate with `os generate` into `out/os/browser_mitm`.
