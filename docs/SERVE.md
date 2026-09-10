# Serve forward + HTTP/API

How Spark **serves** tiny CPU forward from SPARK_BC / safetensors.
Spark / SparkLang only.

## Tiny CPU serve (file SERVE)

```bash
make spark-serve
./spark-serve docs/examples/spark-builder.sparkbc /tmp/serve-dry-001

PYTHONPATH=python python3 tools/spark-bc-dump/dump.py \
 docs/examples/spark-builder.sparkbc \
 --serve /tmp/serve-dry-001 \
 --serve-weights /path/to/weights.safetensors # optional
```

Writes `SERVE` with `forward=true` and honest `trained` from weights
meta. Forward path when MLP tensors exist:

`embed_mean_pool->mlp0->rms_norm->lm_head`

Code: `python/sparklang/model_lab/serve.py`. Gate:
`make test-sparkbc` (`test_serve_forward`).

Architecture: [Architecture](ARCHITECTURE.md) ·
[Attention / forward](ATTENTION_FORWARD.md).

## HTTP / stdio API (serve API path — on tip)

```bash
make spark-serve-api
./spark-serve-api --weights /tmp/serve-dry-001/weights.safetensors \
 --http --host 127.0.0.1 --port 8765

curl -s http://127.0.0.1:8765/health
curl -s http://127.0.0.1:8765/version
curl -s -X POST http://127.0.0.1:8765/v1/predict \
 -H 'content-type: application/json' \
 -d '{"token_ids":[65,66,67]}'
curl -s -X POST http://127.0.0.1:8765/v1/embeddings \
 -H 'content-type: application/json' \
 -d '{"token_ids":[65,66]}'

# stdio JSON lines:
./spark-serve-api --weights … --stdio

make test-serve-api
```

| Endpoint | Role |
|----------|------|
| `GET /health` | Liveness (`production: false`) |
| `GET /version` | Product / version / lane `G` |
| `POST /v1/predict` | Next-token via tiny CPU forward |
| `POST /v1/embeddings` | Embeddings from Spark weights |

Implementation: `python/sparklang/model_lab/serve_api.py` wraps
`run_tiny_forward` / `run_tiny_embed` — same path as file SERVE
(now **attn0** when tensors exist; layer-0 attention). Builder §6c:
[SPARK_BC Builder](SPARK_BUILDER.md).

Optional live **gateway** ask/embed (the AI gateway etc.) is a different
surface — [AI_MODELS.md](AI_MODELS.md) / [ASK_LIVE.md](ASK_LIVE.md).

## Never

- Claim production LLM serving.
- Claim multi-layer / RoPE / KV-cache decode (layer-0 last-query
 only).
- Claim a competitive AI win from SERVE / predict JSON.
- Bind serve training to the 6000.

## Related

- [SPARK_BC Builder](SPARK_BUILDER.md) § 6b / 6c
- [Factory hub](FACTORY.md) · [Eval](EVAL.md)
- [SPARKBC_MAKE.md](SPARKBC_MAKE.md)
