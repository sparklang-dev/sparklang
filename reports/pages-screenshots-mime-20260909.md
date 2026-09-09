# sparklang.dev screenshots blank — 2026-09-09

## Verdict

Screenshots were **not missing from git**. They were **served with the
wrong `Content-Type`**, so browsers with `X-Content-Type-Options: nosniff`
refused to paint them.

## Root cause

`website/_headers` had:

```
/docs/*
  Content-Type: text/html; charset=utf-8
```

That path also matches `/docs/images/*.png` and `*.svg`. Live proof
before fix:

| URL | Bytes | `Content-Type` |
|-----|------:|----------------|
| `/docs/images/decompile-cli-dump.png` | 120049 (real PNG) | `text/html; charset=utf-8` |
| `/docs/images/diagram-spark-loop.svg` | 3390 (real SVG) | `image/svg+xml, text/html; charset=utf-8` |

HTML on `/docs/decompile` and `/workflow` already embedded `<img src=…>`.

## Fix (0.6.58)

1. Explicit `image/png` / `image/svg+xml` under `/docs/images/`.
2. `/docs/*` → Cache-Control only (no blanket `text/html`).
3. `?v=0.6.58` on image `src` (edge still HIT-cached bare URLs for ≤24h;
   OAuth lacks zone purge).
4. Image Cache-Control shortened to `max-age=3600, must-revalidate`.

## Deploy

- PR: https://github.com/sparklang-dev/sparklang/pull/51
- Pages production: `44f8cfbe` (commit `7b8d8c6`)
- Preview MIME OK: `https://44f8cfbe.sparklang-dev.pages.dev`

## Spot-check

```bash
curl -sI 'https://sparklang.dev/docs/images/decompile-cli-dump.png?v=0.6.58'
# → Content-Type: image/png
```

Hard-refresh https://sparklang.dev/docs/decompile and
https://sparklang.dev/workflow.

## Not in scope

Homepage (`/`) still has **no** product screenshots by design (code/text
only). Separate content pass if Michael wants hero/IDE shots there.

## Never

RTX PRO 6000 · beat Claude · zone API remint for purge
