# Public site

Static pages Google Play needs as public URLs:

- `privasi.html` — privacy policy (Play Console → App content → Privacy policy)
- `hapus-akun.html` — account deletion request (Play Console → Data safety →
  Delete account URL)
- `index.html` — small landing page linking both

The content follows what the app actually collects; keep it in sync with
`docs/account-deletion.md` and `docs/pilot-release-checklist.md` §5 when
behavior changes.

## Operator details

Filled on 16 October 2026: operator Samijaya, contact
commride.app@gmail.com, effective date 16 Oktober 2026, minimum age 17.
When any of these change, update every page and the effective date. The
publish workflow refuses to deploy if a `<mark>[...]` placeholder reappears.

## Publishing

`.github/workflows/site-pages.yml` deploys `site/` to GitHub Pages on pushes to
`main`. Enable it once in **Settings → Pages → Source: GitHub Actions**. The
pages are then served at `https://imadjinasi.github.io/commride/`.
