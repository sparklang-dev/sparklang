# Hook — spark_browser.inspector

Product: `spark-browser/spark_browser/inspector/`

| File | Role |
|------|------|
| `ui.py` | Right-pane timeline, filters, breakpoints, HAR export |
| `__init__.py` | Package marker |

## Layout expectations

- URL filter regex + breakpoint regex + Resume
- Auto-save HAR under `sessions/latest/` on quit
- No claim of full Chrome DevTools parity
