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

5. **Deploy Cloudflare Pages (`website/`) via Wrangler CLI** (OAuth
   session — not `CLOUDFLARE_*` env). From the repo root, after the
   release commit is on `main` (or you have checked out that SHA):

   ```bash
   # Regenerate stale doc HTML if markdown changed
   python3 tools/md_to_doc_html.py --all-stale
   # Mirror CHANGELOG.md → website/CHANGELOG.html; sync
   # docs/examples/ → website/docs/examples/ when Builder artifacts
   # changed.

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

   After deploy, spot-check and record the Pages deployment id next
   to the git SHA (example: production deployment `80b7d3ee` for
   `51e4dbd…`):

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
