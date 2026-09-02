# Optional — Spark network hooks (browser_mitm)

Browser HAR/pcap exports bridge to Spark `network` ops (separate
object from `asm/os_ops.s`):

```bash
# Dry-run fixture path (examples/browser_mitm.spark)
network open "examples/fixtures/sample.pcap" -> pcap
network analyze pcap -> traffic_report

# Live product HAR
cd ../spark-browser
make analyze HAR=sessions/latest/session.har
# or from spark/:
make browser-mitm-analyze HAR=../spark-browser/sessions/latest/session.har
```

Optional subsystem — opt-in. Does not pull AgentOS boot stubs.
