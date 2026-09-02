# WHY — browser_mitm (os kind browser)

Spark `os explain` / generate writes this so the browser blueprint
stays reviewable — not marketing.

## Exact why

1. **Debug appliance, not consumer Chrome.** Agents and humans
   debugging portal / web apps need a first-class
   request timeline, not DevTools buried under menus.

2. **TLS visibility without a second stack.** Built-in CONNECT MITM
   + owner CA beats Wireshark + separate mitmproxy for *this*
   browser’s traffic only.

3. **CDP on the same session.** `QTWEBENGINE_REMOTE_DEBUGGING` on
   `127.0.0.1:9222` lets Playwright/agents attach without a second
   browser process.

4. **Spark network bridge.** Exported HAR/pcap feeds Spark
   `network analyze` (`optional/spark_network_hooks.md`).

5. **Qt WebEngine already on this host.** No multi-week Chromium
   compile; CEF and WebKitGTK lose on CDP / packaging here.

6. **Layout hooks, not a second MITM implementation.** Live Python
   MITM/CA stay in `spark-browser/`; this tree documents package
   layout for `os generate` + `make browser-scaffold`.

## What this is not

- Not a Chrome replacement or Speedometer claim
- Not system-wide intercept or silent exfil
- Not AgentOS (`templates/os/ai_agent/`) — different kind
- Not an agent-authorized CA install or host reboot
