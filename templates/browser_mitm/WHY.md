# WHY — browser_mitm

Agents and humans debugging portal / web apps need:

1. First-class request timeline (not DevTools buried under menus)
2. TLS visibility without installing Wireshark + separate mitmproxy
3. CDP for automation (Playwright/agent) on the same session
4. Spark `network analyze` on exported HAR/pcap

This is a **debug appliance**, not a consumer Chrome replacement.
Metrics before multipliers — never claim 10000× without benchmarks.
