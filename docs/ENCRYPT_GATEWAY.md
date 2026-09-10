# Spark Encrypt Gateway (encrypt-to-model)

## Architecture

```
┌─────────────┐ AES-256-GCM envelope ┌──────────────────────┐
│ Spark agent │ ───────────────────────► │ spark-enc-gateway │
│ (asm VM) │ {alg,nonce,ct,tag,aad} │ holds keys │
└─────────────┘ │ decrypts in-process │
 │ ───────────────► │
 │ the AI gateway / model API │
 │ ◄─────────────── │
 │ optional re-seal │
 └──────────────────────┘
```

From the **agent’s perspective**, outbound data to the AI stack is
**encrypted**. Plaintext exists only **inside** `spark-enc-gateway`
after decrypt, then that process calls the AI gateway (`spark-ask-http`).

This is **not** redact/tokenize. Models receive decrypted plaintext
from the trusted gateway process — not ciphertext, and not a
tokenization substitute.

## Language

```
crypto keygen -> key
crypto load key "path/to/key.hex" -> key
encrypt gateway enable key
gateway encrypt on
ask "..." -> reply # seals → ask-proxy → model
encrypt seal text "..." -> blob
encrypt open blob -> text
gateway encrypt off
```

Off by default. `gateway encrypt on` requires a loaded key.

## Crypto

- **AES-256-GCM** envelopes: `alg`, `nonce_hex`, `ciphertext_hex`,
 `tag_hex`, `aad_hex` (hex encoding of real ciphertext — not a stub).
- **Default backend: OpenSSL** `EVP_aes_256_gcm` (always the working
 path on a typical Linux host today).
- **Optional backend: AF_ALG** `aead` / `gcm(aes)` via
 `crypto backend af_alg`. **Fail-loud** if `algif_aead` is missing or
 blacklisted — never silently falls back to OpenSSL when AF_ALG was
 requested.
- Host: `algif_aead` is **blacklisted** for CVE-2026-31431
 (`/etc/modprobe.d/disable-algif_aead.conf`, `install algif_aead
 /bin/false`). `crypto probe` / `./spark-enc-gateway probe` report
 `af_alg_status:"blacklisted"` honestly. Agents must **not** edit
 modprobe / sysctl / security policy.
- Selection: `crypto backend openssl|af_alg`, CLI `--backend`, env
 `SPARK_ENC_BACKEND`, or file `out/encrypt/backend` (CLI > env >
 file > openssl).
- Keys: 32-byte `getrandom` written as 64 hex chars. Mode **0600**
 (owner-only). `out/encrypt/` is **0700**. **Never commit keys.**
 `.gitignore` covers `out/encrypt/`, `*.key`, and MITM CA material.

## Language

```
crypto probe -> info
crypto backend openssl
crypto backend af_alg # fail-loud if AF_ALG unusable
crypto keygen -> key
encrypt gateway enable key
gateway encrypt on
encrypt seal text "..." -> blob
encrypt open blob -> text
gateway encrypt off
```

## Run

```bash
make # spark + spark-enc-gateway
./spark-enc-gateway probe # AF_ALG vs OpenSSL status
./spark-enc-gateway self-test # NIST SP 800-38D via OpenSSL
./spark --dry-run examples/encrypt_gateway.spark
./spark --dry-run examples/crypto_probe.spark
```

# Live (the AI gateway): gateway decrypts then spark-ask-http
```bash
export AI_GATEWAY_URL=http://127.0.0.1:4000
export OPENAI_API_KEY=… # never commit
./spark --live examples/encrypt_gateway.spark
```

## Threat model (short)

| Trust | Holds plaintext? |
|-------|------------------|
| Spark agent process (with gateway on) | Only before seal / after open |
| Wire agent → enc-gateway | Ciphertext envelope |
| `spark-enc-gateway` | Yes (decrypt + model call) |
| the AI gateway / model provider | Yes (after gateway decrypt) |
| Logs under `out/encrypt/` | Key files if you leave them — gitignore |

Compromise of the gateway process = compromise of keys and plaintext.
Compromise of the agent with gateway on still sees plaintext at seal/open
edges; the point is encrypting the hop **to** the model path.

## Never

- Commit `out/encrypt/*.key` or raw key material
- Fake “encryption” via base64(plaintext)
- Treat redact/tokenize as this feature
