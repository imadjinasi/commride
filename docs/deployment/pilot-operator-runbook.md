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

MapLibre + Geoapify remains the proven fallback. The accepted next Active Ride
path is MapLibre + CommRide Navigation Engine, with Valhalla as the target
self-hosted motorcycle router and TomTom REST traffic/incident intelligence.
Geoapify stays active until replacement runtime evidence exists. Google source
preparation is optional and must not become a billing prerequisite for the pilot.

Cloudflare/D1, Firebase authentication and Geoapify provider/runtime now have
separate operator evidence recorded after the original setup baseline. FCM
delivery, CommRide embedded-navigation device acceptance, Valhalla/TomTom
provider runtime, and convoy field acceptance still require their own evidence.

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

For the 23 September 2026 Round 2 retest, verify specifically that these are
present remotely before deploying the matching Worker source:

- `0009_route_plan_maneuvers.sql` — required by current RoutePlan and Briefing reads;
- `0010_notification_inbox.sql` — required by Account/Club notification history.

If RoutePlan and Briefing both fail together while other authenticated Ride reads
still work, stop and inspect the remote migration list before changing mobile UI
or provider configuration. Do not hide a missing schema migration with a client
fallback.

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

## 7. Activate the low-cost navigation providers deliberately

Google billing is not required for the pilot path.

### 7.1 Keep the proven fallback while migrating

Until Valhalla has real runtime evidence, keep:
- Geoapify route/place backend available;
- MapLibre client style configured;
- `COMMRIDE_NAVIGATION_ENABLED=false` unless the CommRide navigation surface on
  the exact build has passed its own device gate.

Do not remove `GEOAPIFY_API_KEY` merely because the target provider code exists.

### 7.2 TomTom traffic / incident intelligence

Create a TomTom API key in the operator account without committing or pasting it
into chat. Store only the server-side secret:

```powershell
cd C:\Users\sabilulquran\Documents\Projects\commride\services\api
npx wrangler secret put TOMTOM_API_KEY
```

Enable the non-secret traffic selector only after the secret is present.
Provider calls must be bounded and server-side; one shared Ride result should not
be fetched independently by every Rider. Active Ride refreshes advisory traffic
at a bounded 10-minute cadence, while the Worker shares the exact-RoutePlan
result through a short edge-cache TTL. Verify repeated Rider requests really
reuse cached data, verify failed refreshes do not leave old incidents presented
indefinitely, then verify real Indonesian incident/traffic responses and account
usage before calling this Provider/runtime PASS.

### 7.3 Valhalla routing target

Valhalla is open source but is **not** live merely because an adapter exists.
Provision a reviewed HTTPS Valhalla endpoint separately, keep it outside the
mobile app, and configure its base URL as a non-secret Worker variable only after
the endpoint is reachable and controlled.

Before changing the route default, verify:
- motorcycle costing returns a real route;
- Stops preserve order;
- normalized distance/duration/geometry/maneuvers are complete;
- alternatives are materially different when offered;
- timeouts/errors preserve the previous valid RoutePlan;
- no car route is silently labeled motorcycle.

Until this passes, keep Geoapify as route fallback.

### 7.4 CommRide Navigation Engine device gate

After repository CI passes, use an installed Android build to verify:
- MapLibre renders the accepted RoutePlan;
- the existing Ride location session drives progress (no second hidden GPS stream);
- next maneuver changes with route progress;
- RiderPresence retains Live/Stale/Offline semantics;
- one noisy GPS sample does not trigger off-route;
- sustained deviation enters Recovery;
- Recovery keeps the original RoutePlan and guides toward a sensible future
  rejoin point;
- when provider recovery succeeds, the temporary recovery line follows a
  provider-computed road path rather than a fake straight line;
- repeated GPS samples do not cause continuous upstream route recomputation;
- a recovery-provider failure keeps the original RoutePlan usable and does not
  masquerade as valid road guidance;
- **Cari rute baru** is deliberate and does not change the shared route before
  confirmation;
- Member/Sweeper cannot change the shared route;
- Leader/Navigator replacement creates a new persisted revision before other
  Riders apply it;
- traffic/incidents degrade honestly if TomTom is unavailable.

External Google/Waze navigation links may remain fallback escape hatches. They do
not count as embedded CommRide navigation acceptance.

Voice remains off until a real media transport/SFU is implemented and device
tested.

## 8. Two-Rider functional smoke before any road test

Use two separate accounts/devices. Complete Account, Rider profile, Vehicle, Club,
invite/join, Ride, Route Planner and save, Briefing, both Riders Ready, Start Ride,
Live Group, Quick Action, Checkpoint check-in/release, private chat, Leader
announcement, raise SOS, verify End Ride rejection, cancel/resolve SOS, End Ride
and Ride Recap. Any core blocker stops progression to field testing.

## 9. Physical-device acceptance

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

## 10. Convoy field acceptance

Use at least three vehicles: Leader, Member and Sweeper. Verify all Live, deliberate
Stale/Offline, last-known timestamps, reconnect only becoming Live after a fresh
accepted observation, Saya Berhenti, Saya Tertinggal, Butuh Bantuan, separation
attention, Checkpoints, chat, announcement, SOS with/without GPS, End Ride blocked
by SOS, SOS closure, successful End Ride and planned-vs-sampled Recap.

Screen interactions must be performed while safely stopped. CommRide is not an
emergency dispatch service or crash/fall detector.

## 11. Evidence record

For each test record exact app/API SHA; Worker URL/version; D1 ID; Firebase project;
app version/build/signing channel; device models/OS; permission states; Rider count;
Ride duration; network scenarios; battery start/end; GPS/background/freshness
outcome; map/provider and notification outcomes; SOS/Checkpoint/End Ride/Recap
results; errors; observed Cloudflare/Geoapify usage; approximate cost; linked
defects; operator and date/time. Do not include credentials or unneeded raw GPS.

Accept the pilot only when repository, provider/runtime, device and field evidence
are each explicitly recorded. Deployment/provider/device work remains pending
until the operator actually performs and verifies these steps.
