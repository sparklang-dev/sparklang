# Hook — spark_browser.cdp

Product: `spark-browser/spark_browser/cdp/`

| Item | Role |
|------|------|
| `client.py` | `CdpClient` — navigate / evaluate / screenshot |
| `ws.py` | Stdlib WebSocket for Chromium CDP |
| `cli.py` | Companion CLI (`./spark-browser-cdp`) |
| Env | `QTWEBENGINE_REMOTE_DEBUGGING=127.0.0.1:9222` |

Language: `browser cdp status|navigate|evaluate|screenshot`.
Dry-run mocks never dial. `--live` forks `./spark-browser-cdp`.

```bash
python -m spark_browser.cdp.cli --dry-run status
python -m spark_browser.cdp.cli --dry-run navigate --url https://example.com/
# live (GUI up on :9222):
./spark-browser-cdp navigate --url https://example.com/
```
