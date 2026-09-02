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

5. Deploy Pages (`website/`) so Changelog + Downloads match the tag.
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
