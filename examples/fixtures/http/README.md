# HTTP dry-run fixtures

Real files only. `http get` / `http post` in `--dry-run` **fopen** these
paths (via `fixture "…"` or a `file://` / `examples/fixtures/http/…` URL).

Missing fixture → fail loud. No invented 200s. Live (`./spark --live`)
ignores fixtures and dials the URL through `./spark-http`.
