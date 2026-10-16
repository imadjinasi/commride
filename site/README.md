# Public site

Static pages Google Play needs as public URLs:

- `privasi.html` — privacy policy (Play Console → App content → Privacy policy)
- `hapus-akun.html` — account deletion request (Play Console → Data safety →
  Delete account URL)
- `index.html` — small landing page linking both

The content follows what the app actually collects; keep it in sync with
`docs/account-deletion.md` and `docs/pilot-release-checklist.md` §5 when
behavior changes.

## Before publishing

Replace every highlighted placeholder (`<mark>[...]</mark>`, including the
`mailto:` link in `hapus-akun.html`):

- `[nama pengelola]` — person or organisation responsible for CommRide
- `[email kontak]` — inbox that handles privacy and deletion requests
- `[tanggal berlaku]` — effective date
- `[usia minimal, misalnya 17]` — minimum user age

Then remove the `<mark>` tags. The publish workflow refuses to deploy while
placeholders remain.

## Publishing

`.github/workflows/site-pages.yml` deploys `site/` to GitHub Pages on pushes to
`main`. Enable it once in **Settings → Pages → Source: GitHub Actions**. The
pages are then served at `https://imadjinasi.github.io/commride/`.
