# Native network and native web in Spark

Spark ships **first-class language statements** for packet capture, HTTP fetch,
and browser automation — not only AI `ask`. This doc states what works **today**
(cite fixtures) and what is **[roadmap]** only.

**Full syntax:** [LANGUAGE.md](LANGUAGE.md) (Network + Browser / MITM) ·
**HTTP patterns:** `lib/http.spark` · **Examples:** `examples/network_*.spark`,
`examples/browser_*.spark`, `examples/engine_*.spark`

## Summary

| Surface | Today | Dry-run default | Live / network flags |
|---------|--------|-----------------|----------------------|
| **Packet capture** | `network capture probe\|capture`, `open`, `analyze`, `explain` | Fixture pcap; probe always `claimed:false` | `--allow-net-capture` + `CAP_NET_RAW` for live sniff |
| **HTTP fetch** | `engine fetch "…"` (`file://`, `http://`, `https://`) | `file://` always | `http(s)://` needs `--allow-net`; HTTPS via `./spark-engine-fetch-tls` |
| **Browser driver** | `browser run\|goto\|flags\|cdp`, `browser show\|engine render` | Session JSON + mocks; dry E2E | `browser gui` + `--live`; CDP dials only under `--live` |
| **MITM / HAR** | `mitm ca-*`, `enable`, `har export`, QUIC lane | Synthetic HAR markers | `--live` forks `./spark-mitm-h2` / `./spark-mitm-quic` |
| **Engine B render** | `engine parse\|css attach\|layout\|paint boxes\|show` | PPM + JSON under `out/engine/`, `out/browser/` | `--live` → `./spark-engine-show` (X11) |
| **First-class `http get` / `http post`** | **done** (timeout, auth, retries, dry fixtures) | Fixture files; no network | `./spark --live` → `./spark-http` (curl). `bearer`/`header` + `retries`/`backoff` |

Dry-run and `make test` stay **offline** unless you opt into `--allow-net` or
`--allow-net-capture`. No vendor API keys required for develop/test.

See [LANGUAGE.md — Network](LANGUAGE.md#network) and
[LANGUAGE.md — Browser / MITM](LANGUAGE.md#browser--mitm-language-sot) for
canonical ops and scope bounds (not full CSS, not Chromium product chrome).

---

## Native network (today)

```
network capture probe -> info
network open "examples/fixtures/sample.pcap" -> pcap
network analyze pcap -> traffic_report
network explain traffic_report -> text
```

| Example | Path |
|---------|------|
| Open + analyze + explain | `examples/network_analyze.spark` |
| Capture probe | `examples/network_capture_probe.spark` |
| Sample pcap | `examples/fixtures/sample.pcap` |

```bash
./spark --dry-run examples/network_analyze.spark
./spark --dry-run examples/network_capture_probe.spark
./spark --dry-run --allow-net-capture examples/network_capture.spark
```

Remote HTTP: `engine fetch` or `review url` with `--allow-net`. Neg:
`examples/neg/engine_fetch_blocked.spark`.

## Native web (today)

```
browser run "examples/browser_main.spark" -> session
browser goto "https://example.com/" -> page
mitm har export "out/browser/session.har"
engine fetch parse "file://examples/fixtures/engine/sample.html"
```

| Example | Path |
|---------|------|
| Dry browser + HAR | `examples/browser_main.spark` |
| Engine pipeline | `examples/engine_fetch_parse_layout.spark` |
| Dry E2E | `make test-e2e-browser` |

Browser SoT: `asm/browser_ops.s` — not voice-phase-only; not `python3 -m spark_browser run`.

## Keys and dry-run vs --live

| Mode | Network | `ask` / model | Keys |
|------|---------|---------------|------|
| `--dry-run` | Fixture pcap, browser session markers | Heuristic stubs | **None** |
| `--live` | `--allow-net` / `--allow-net-capture` opt-in | `./spark-ask-http` → optional OpenAI-compatible gateway | Gateway Bearer optional (`SPARK_GATEWAY_KEY` / wire-compat `OPENAI_API_KEY`) |

See [AI_MODELS.md](AI_MODELS.md) · [ASK_LIVE.md](ASK_LIVE.md).
