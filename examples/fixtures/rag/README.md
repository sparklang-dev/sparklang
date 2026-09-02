# RAG dry fixtures (embed / retrieve)

Offline SoT for Spark `embed` and `retrieve` dry-run. Must match
`bootstrap/dry_rag.c` string literals (same contract as
`dry_ask.c` / ask fixtures).

| File | Statement | Live target |
|------|-----------|-------------|
| `embed-default.json` | `embed "…"` | Bifrost `POST /v1/embeddings` alias `embed-rag` |
| `retrieve-docs.json` | `retrieve "…" from project "docs"` | rag-gateway `POST /v1/retrieve` |

No PII. Generic docs-project only. Live needs keys; `make test` /
`--dry-run` never dial.
