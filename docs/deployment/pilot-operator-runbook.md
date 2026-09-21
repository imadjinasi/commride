# CommRide Pilot Operator Runbook

This runbook applies to the MapLibre + Geoapify implementation in PR #68 on top of
readiness PR #67. Repository implementation is not a deployed provider-backed app.
Follow the approved exact source revision; do not deploy an unreviewed draft.

## Evidence rule

Keep four independent gates:

1. Repository PASS: source, dependencies, tests, migrations and CI build checks.
2. Provider/runtime PASS: actual Firebase, Geoapify, Cloudflare/D1 and Worker behavior.
3. Device PASS: installed signed build, permissions, map/GPS/push and battery evidence.
4. Field convoy PASS: observed group behavior in a safely conducted real Ride.

No gate substitutes for another. Do not close #33, #52, #55, #58 or #59 on CI alone.

## 0. Known setup and what must not be repeated

Operator evidence on 21 September 2026 already records:

- Firebase project `CommRide Pilot`, ID `commride-pilot`;
- Android Firebase app `CommRide` registered for `io.github.imadjinasi.commride`;
- Email/Password authentication enabled;
- Android google-services.json downloaded locally;
- Geoapify project `CommRide Pilot` created;
- Cloudflare OAuth login verified for the operator account;
- D1 database `commride-pilot` created in APAC with database ID
  `b03592b1-10b1-40c9-a252-faa4ab568810`;
- repository runtime config uses the required `DB` binding name and does not
  default local development to the remote pilot database;
- local API typecheck/tests and Wrangler dry-run passed on the earlier readiness source;
- local migration validation did not run because Python was unavailable;
- real npm lockfile generated locally and committed; API CI now uses npm ci.

Do not recreate these resources without a mismatch. The Android application ID is
a long-lived technical identity, not a website URL. iOS Bundle ID/registration
remains unfinalized; do not create it by assumption.

Google Maps is deferred. Do not block the pilot on Google billing or another card.
There is no Cloudflare/D1 deployment, real provider acceptance, installed Firebase
integration, FCM delivery, device or convoy PASS in the setup evidence above.

## 1. Source gate and baseline record

Record exact Git SHA, operator, date/time and intended `pilot` environment. Check
both API and Mobile CI on the selected revision. PR #68 must not be merged without
explicit authorization. An unprotected main branch is not a reason to skip review.

In PowerShell, check local changes before switching or pulling:

```powershell
git status
git branch --show-current
git fetch origin
```

Preserve local files and use fast-forward-only updates. Do not use reset/clean or
blindly stage all files. Read the
[provider migration contract](maplibre-geoapify-pilot.md) and
[pilot checklist](../pilot-release-checklist.md).

From `services/api`:

```powershell
npm ci --no-audit --no-fund
npm run typecheck
npm test
npx wrangler deploy --dry-run --outdir "$env:TEMP\commride-worker"
```

Stop on a failed command. Run `python scripts/validate_migrations.py` once Python
is installed, or retain CI migration evidence clearly labeled as CI rather than a
local result. A dependency-script warning alone is not a failed test; inspect the
actual exit/result before changing npm policy.

## 2. Provision the actual Cloudflare resources

Cloudflare login and D1 provisioning were completed by the operator on
21 September 2026. The repository now records the real pilot D1 resource:

- binding: `DB`;
- database: `commride-pilot`;
- database ID: `b03592b1-10b1-40c9-a252-faa4ab568810`;
- region: APAC.

The source already declares `ACTIVE_RIDE_ROOM` and the SQLite-backed
`ActiveRideRoom` export; do not replace it with an unrelated
lifecycle/migration model.

Wrangler's interactive create flow offered to configure a lowercase
`commride_pilot` binding and remote-local access. That local generated
configuration is **not** the application contract. CommRide requires the `DB`
binding, and shared pilot D1 must not become the default local-development
database.

Review and apply the existing D1 migrations in order:

```powershell
npx wrangler d1 migrations list commride-pilot --remote
npx wrangler d1 migrations apply commride-pilot --remote
```

Record exact SHA, database ID and migration output. A dry-run alone does not prove
login, provisioning, remote migrations or deployment.

## 3. Runtime variables and secret boundaries

Non-secret configuration:

- `FIREBASE_PROJECT_ID=commride-pilot`;
- `LOCATION_SAMPLE_RETENTION_DAYS=30` unless an approved value in 1..365 is required.

Set the Firebase project ID in the actual Worker variables, not just in a document.
It must match the issuer/audience of mobile Firebase ID tokens.

Use a dedicated Geoapify backend key in Cloudflare's secret store:

```powershell
npx wrangler secret put GEOAPIFY_API_KEY
```

The backend now consumes that exact name; it does not fall back to a Google key.
Use the Wrangler prompt locally, never paste a value into chat or GitHub.

After the Cloudflare secret store is ready, configure FCM HTTP v1 credentials:

```powershell
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
```

Keep service-account JSON/private keys outside the checkout and never commit them.
No service-account private key is needed solely for Firebase ID-token verification.
FCM failures must not undo authoritative Ride/SOS/Briefing/Checkpoint persistence.

Use a separate client map key for Geoapify styles/tiles. A mobile key can be
recovered from an APK; do not reuse the backend key. Confirm the actual Geoapify
restriction options and account quotas instead of assuming Google-style Android
certificate or API restrictions. Check per-second limits as well as daily usage;
request caps are not a global provider quota guarantee.

## 4. Deploy and verify the Worker

After reviewing variables, bindings, migrations and secrets:

```powershell
npx wrangler deploy
```

Record exact Git SHA, real Worker URL, Worker deployment/version identifier, D1
ID, Firebase project ID, provider configuration state and deployment time.

Verify the real URL without inventing it:

- GET /health succeeds;
- GET /version returns the expected service version;
- real Firebase-authenticated GET /v1/me works, or returns the expected new-Rider
  onboarding 404 before PUT /v1/me;
- joined Active Ride upgrades to its authenticated WebSocket;
- daily retention and 15-minute reminder triggers are configured and their actual
  execution is verified separately.

The current /version response is not a Git SHA attestation. Record the selected
SHA and Worker version together; do not infer exact source from service version
0.1.0. A working /health alone is not runtime PASS.

## 5. Verify Geoapify behavior before distributing a build

Using authenticated CommRide API requests with the actual provider configuration:

- autocomplete and resolve a real place;
- compute a motorcycle route with no car substitution;
- add/reorder Stops and recompute/save a RoutePlan revision;
- inspect recommended/shortest alternatives when materially distinct;
- exercise Fuel/Food/Rest/Hotel/custom Search Along Route;
- verify invalid-key/quota failures do not expose provider credentials;
- observe account usage and ensure pilot concurrent load stays within real limits.

Search Along Route is approximate sampled-area search: up to six distance-spaced
5 km circles, not an exhaustive corridor or proof of road access. Long routes can
have gaps. Detour distance/time remains unavailable until actual recomputation
through the selected Stop. Do not present this as Google-identical behavior.

## 6. Complete local Android Firebase and map integration

Only after backend/provider setup, prepare the actual mobile build. The accepted
Android application ID remains `io.github.imadjinasi.commride`.

From `apps/mobile`, with Flutter/Android SDK/Java 21 and Python installed:

```powershell
flutter create --platforms=android,ios --project-name commride_mobile --org io.github.imadjinasi .
python tool/configure_platforms.py
python tool/verify_platforms.py
```

Run the clean-source verifier before placing provider files. The configurator
sets the Android application ID, release Internet permission and location/FCM
declarations; it does not perform Firebase registration or finalize iOS identity.

Complete the official local FlutterFire/native Android configuration against
`commride-pilot`. Select Android only until iOS identity is accepted. Keep the
local google-services.json and generated Firebase options out of Git. Verify an
installed build really signs in; producing configuration files is not auth PASS.

Copy the example defines file in PowerShell:

```powershell
Copy-Item pilot-defines.example.json pilot-defines.local.json
notepad pilot-defines.local.json
```

In that ignored local file set the actual Worker URL, request maps and supply an
HTTPS Geoapify style URL with only the dedicated client map key. Do not put the
server key, service-account credentials or signing password in Dart defines.
The example URL is intentionally unusable and maps are disabled until configured.

```powershell
git check-ignore pilot-defines.local.json
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=pilot-defines.local.json
```

For Play distribution after actual signing/store setup:

```powershell
flutter build appbundle --release --dart-define-from-file=pilot-defines.local.json
```

A CI release AAB is only a build gate, not a Play-signed release or installed-device
provider acceptance. Never commit the keystore or signing passwords.

## 7. Two-Rider functional smoke before any road test

Use two separate accounts/devices. Complete Account, Rider profile, Vehicle, Club,
invite/join, Ride, Route Planner and save, Briefing, both Riders Ready, Start Ride,
Live Group, Quick Action, Checkpoint check-in/release, private chat, Leader
announcement, raise SOS, verify End Ride rejection, cancel/resolve SOS, End Ride
and Ride Recap. Any core blocker stops progression to field testing.

## 8. Physical-device acceptance

On Android record fresh install, permission denied/later enabled for notifications
and location, tracking started only from Active Ride, screen lock for at least
20 minutes, background/foreground, temporary internet loss/reconnect, Wi-Fi/mobile
transition, OEM battery optimization, foreground location-service notification,
FCM receipt, map rendering/freshness/fallback, End Ride/sign-out teardown and
measured battery start/end over a representative Ride.

Document force-stop/terminated behavior exactly as observed; never infer it from
native declarations or unit tests. Opening a map must not independently request
location or start a second tracking session.

Before iOS support is claimed, finalize/register the Bundle ID, configure Firebase
and APNs, enable Push Notifications capability with actual signing entitlements,
and repeat equivalent scenarios on a signed physical iPhone. No APNs entitlement
or provider identity is fabricated by repository bootstrap.

## 9. Convoy field acceptance

Use at least three vehicles: Leader, Member and Sweeper. Verify all Live, deliberate
Stale/Offline, last-known timestamps, reconnect only becoming Live after a fresh
accepted observation, Saya Berhenti, Saya Tertinggal, Butuh Bantuan, separation
attention, Checkpoints, chat, announcement, SOS with/without GPS, End Ride blocked
by SOS, SOS closure, successful End Ride and planned-vs-sampled Recap.

Screen interactions must be performed while safely stopped. CommRide is not an
emergency dispatch service or crash/fall detector.

## 10. Evidence record

For each test record exact app/API SHA; Worker URL/version; D1 ID; Firebase project;
app version/build/signing channel; device models/OS; permission states; Rider count;
Ride duration; network scenarios; battery start/end; GPS/background/freshness
outcome; map/provider and notification outcomes; SOS/Checkpoint/End Ride/Recap
results; errors; observed Cloudflare/Geoapify usage; approximate cost; linked
defects; operator and date/time. Do not include credentials or unneeded raw GPS.

Accept the pilot only when repository, provider/runtime, device and field evidence
are each explicitly recorded. Deployment/provider/device work remains pending
until the operator actually performs and verifies these steps.
