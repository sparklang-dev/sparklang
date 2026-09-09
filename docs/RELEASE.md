# SparkLang release process

## Version source

- Runtime / installer kit version: `website/downloads/manifest.json`
  → `"version"`
- User-facing notes: `CHANGELOG.md` (mirrored at `/CHANGELOG.html`)
- CLI: `./spark --version`

## Cutting a release

1. Bump `manifest.json` version when shipping installers (keep CHANGELOG in sync).
2. Add a `## X.Y.Z — YYYY-MM-DD` section to `CHANGELOG.md`.
3. Commit + merge to `main`.
4. Tag and publish a **GitHub Release** from that commit:

```bash
git tag -a vX.Y.Z -m "SparkLang X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "SparkLang X.Y.Z" --notes-file - <<'EOF'
See CHANGELOG.md for X.Y.Z.
Installers: https://sparklang.dev/downloads.html
EOF
```

5. **Deploy Cloudflare Pages (`website/`) so Changelog + Downloads
   match the tag.**

   Before any deploy, on the release SHA:

   ```bash
   python3 tools/md_to_doc_html.py --all-stale
   # Mirror CHANGELOG.md → website/CHANGELOG.html; sync
   # docs/examples/ → website/docs/examples/ when Builder artifacts
   # changed.
   ```

   ### 5a. Preferred — Wrangler CLI (OAuth)

   When Wrangler is available on the box (OAuth session — not
   `CLOUDFLARE_*` env):

   ```bash
   npx wrangler pages deploy website \
     --project-name=sparklang-dev \
     --branch=production \
     --commit-hash="$(git rev-parse HEAD)"
   ```

   **Auth gotcha:** Wrangler OAuth on SoapBox lives under
   `~/.config/.wrangler/` (leading **dot** on `.wrangler`), with
   `pages:write`. That is **not** `~/.config/wrangler/` (no leading
   dot). If deploy fails with auth / missing credentials, check the
   dotted path first — do not invent or print tokens.

   ### 5b. Fallback — Cloudflare dashboard (no CLI)

   When Wrangler is **absent** or auth fails: do **not** invent a CLI
   path. Exact human steps:

   1. Note the **git SHA** you are shipping (`git rev-parse HEAD`).
   2. Open the Cloudflare dashboard → **Workers & Pages** → project
      that serves **sparklang.dev** (Pages).
   3. **Upload / deploy** the contents of the local `website/`
      directory from that SHA (Direct Upload, or the project's
      connected production branch if CI is already wired — prefer the
      same mechanism used for the last good Pages deploy).
   4. Record the Pages deployment id / time next to the git SHA.

   After either path, spot-check:

   - `https://sparklang.dev/`
   - `https://sparklang.dev/CHANGELOG.html`
   - `https://sparklang.dev/docs/spark-builder.html`
   - `https://sparklang.dev/downloads.html`

   Tip ≠ pin: if the live site lags git, say so — do not claim
   sparklang.dev equals an unpushed local tree.

6. Sync the public mirror so `sparklang-dev/sparklang` matches the
   tagged tree.

## Maintainer

Public source: GitHub org **sparklang-dev** /
https://github.com/sparklang-dev/sparklang
— no private store or personal ops data on the public site.

**CLI names:** `spark` / `./spark-bootstrap` remain the UX entrypoints.
Product name in docs/site is **SparkLang**.

## Notes

- Do not invent token/cost numbers in release notes.
- Dry-run remains the default story; live gateway is optional.
- Builder factory honesty: init ≠ trained; GAS `--compile`/`--run-bc` wrap bootstrap
  — see [SPARK_BUILDER.md](SPARK_BUILDER.md).
- Local serve API (G-lane): `./spark-serve-api --weights … --http`
  exposes `/health`, `/version`, `/v1/predict`, `/v1/embeddings` on
  CPU only (wraps tiny forward; not production). Gate:
  `make test-serve-api`. See Builder §6c.
