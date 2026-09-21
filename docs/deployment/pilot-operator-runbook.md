# CommRide Pilot Operator Runbook

This runbook turns the repository-ready CommRide MVP into a real provider-backed
pilot build. It is intentionally operator-driven: provider accounts, secrets,
signing credentials, and physical-device evidence must never be invented from
repository state.

## Evidence rule

Three different statements must stay separate:

1. **Repository PASS** — source, tests, migrations, native declarations, and CI
   build gates passed.
2. **Provider/runtime PASS** — real Firebase, Geoapify, Cloudflare, D1, and
   Worker configuration were created and verified.
3. **Device/field PASS** — a signed real build passed physical-device and convoy
   scenarios.

Do not use one class of evidence to claim another class passed.

## 0. Record the pilot baseline

Before changing provider/runtime configuration, record:

- exact Git commit SHA;
- operator name;
- date/time;
- intended environment: `pilot`;
- Android application ID:
  `io.github.imadjinasi.commride` (accepted for the pilot baseline);
- iOS bundle ID once finalized;
- planned API URL;
- Firebase project ID: `commride-pilot`;
- pilot map provider: MapLibre + Geoapify;
- Geoapify project: `CommRide Pilot`;
- provider migration state: not yet implemented until the separate source PR
  lands.

The Android application ID and iOS bundle ID are technical application
identifiers, not website URLs. They are long-lived identifiers used by
Firebase, provider restrictions, Android/iOS signing, and store distribution.

Google Maps is deferred for this pilot; do not block the runbook on Google
billing or a replacement payment card.

## 1. Complete the Firebase pilot integration

Recorded operator evidence already confirms:

- Firebase project display name `CommRide Pilot`;
- Firebase project ID `commride-pilot`;
- Android Firebase app `CommRide`;
- Android application ID `io.github.imadjinasi.commride`;
- Email/Password authentication enabled;
- Android `google-services.json` downloaded locally.

Do not recreate those resources unless a mismatch is discovered. The local
provider file must remain untracked and must never be copied into GitHub,
documentation, screenshots, or chat.

Still required on the mobile development workstation:

```bash
firebase login
dart pub global activate flutterfire_cli
```

First generate the native platform projects from `apps/mobile`:

```bash
flutter create \
  --platforms=android,ios \
  --project-name commride_mobile \
  --org io.github.imadjinasi .
python tool/configure_platforms.py
python tool/verify_platforms.py
```

The verifier above is a clean-source/native-declaration check. Run it **before**
placing local Firebase provider files into the generated native directories.

Then connect the real Android Firebase configuration and run the official
FlutterFire/native workflow:

```bash
flutterfire configure
flutter pub get
flutter analyze
flutter test
```

Expected evidence:

- the installed/dev CommRide build reaches Firebase Email/Password auth;
- Android native configuration resolves for
  `io.github.imadjinasi.commride`;
- no Firebase service-account private key is tracked in Git.

iOS Firebase registration remains pending until the final iOS bundle ID is
accepted.

### iOS push prerequisite

Before iOS FCM acceptance:

- enable **Push Notifications** capability in Xcode;
- enable the required background notification mode;
- create/use an APNs authentication key in the Apple Developer account;
- connect the APNs key to Firebase;
- verify the signed app has the expected APNs entitlement.

## 2. Prepare MapLibre + Geoapify for the pilot

The accepted pilot map direction is:

- MapLibre for mobile map rendering;
- Geoapify for map style/tiles;
- Geoapify server APIs for autocomplete/geocoding, place search/lookup, and
  motorcycle routing;
- CommRide API/provider adapters as the boundary between provider payloads and
  domain DTOs.

The Geoapify project `CommRide Pilot` already exists. Do not paste its API key
into GitHub, documentation, screenshots, or chat.

**Repository reality:** the current integrated source still uses the earlier
Google Maps provider/runtime. Do not call map-provider setup PASS until a
separate source migration PR replaces that implementation and its tests pass.

Prefer two trust boundaries:

1. **Server/provider key** — backend Geoapify calls only; store as a Cloudflare
   secret after the migration PR defines the runtime environment contract.
2. **Mobile map key** — only for the MapLibre map/style/tile surface where a
   client credential is required; keep it out of Git and do not reuse the
   server key.

The backend migration should support:

- autocomplete/geocoding;
- place lookup/search;
- motorcycle routing;
- provider-independent route summaries/alternatives;
- on-demand Search Along Route.

If Search Along Route has no single provider primitive, implement it on the
server from the selected route/polyline by selecting a bounded corridor/sample
set, querying relevant Places areas, deduplicating, ranking, and returning
CommRide DTOs.

Do not fabricate Google-identical route alternatives. Return useful alternatives
only when they materially differ.

Google Maps remains a future provider option; it is not required for the first
pilot.

## 3. Provision Cloudflare pilot resources

From `services/api`:

```bash
npx wrangler login
npx wrangler d1 create commride-pilot --location apac
```

Record the returned real D1 database ID.

Add the real D1 binding to the deployment configuration:

```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "commride-pilot",
    "database_id": "<REAL_DATABASE_ID>"
  }
]
```

Do not invent an ID.

The repository already declares the Active Ride Durable Object binding and the
declarative SQLite-backed `ActiveRideRoom` export.

Check unapplied D1 migrations:

```bash
npx wrangler d1 migrations list commride-pilot --remote
```

Apply them:

```bash
npx wrangler d1 migrations apply commride-pilot --remote
```

Record the migration output and exact Git SHA.

## 4. Configure API variables and secrets

Non-secret operational configuration includes:

- `FIREBASE_PROJECT_ID=commride-pilot`;
- `LOCATION_SAMPLE_RETENTION_DAYS` (repository default: 30).

Secrets include:

- `FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL`;
- `FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY`;
- the Geoapify server/provider key.

The separate provider-migration PR should define one stable backend environment
name for the Geoapify key (recommended: `GEOAPIFY_API_KEY`) before production
configuration is applied.

Use Cloudflare secrets for secret values. After the source contract exists:

```bash
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
npx wrangler secret put GEOAPIFY_API_KEY
```

Do not paste those secret values into GitHub issues, PR comments, screenshots,
documentation, or chat.

Before deployment, verify the Firebase project ID configured by the API matches
the Firebase project issuing the mobile ID tokens.

## 5. Deploy and smoke-test the API

Validate locally/CI first:

```bash
npm install --no-audit --no-fund
npm run typecheck
npm test
python3 scripts/validate_migrations.py
npx wrangler deploy --dry-run
```

A real `services/api/package-lock.json` was generated on the operator machine
but is not yet committed. Do not fabricate a replacement. Once that exact
lockfile is reviewed and committed, switch dependency installation in CI and
this runbook to `npm ci --no-audit --no-fund`.

Then deploy the real pilot Worker:

```bash
npx wrangler deploy
```

Record:

- exact Git SHA;
- Worker URL;
- Worker deployment/version identifier;
- D1 database ID;
- Firebase project ID;
- deployment date/time.

Smoke tests:

1. `GET /health` returns success.
2. `GET /version` returns the expected deployed version/baseline.
3. A real Firebase-authenticated `GET /v1/me` reaches the API.
4. An Active Ride can upgrade to the authenticated WebSocket room.
5. Scheduled retention/reminder configuration is visible and later verified.

Do not call the environment PASS if only `/health` works.

## 6. Build the Android pilot app

From `apps/mobile`, after Firebase is integrated and the separate
MapLibre/Geoapify source migration has landed:

```bash
flutter pub get
flutter analyze
flutter test
```

Build a pilot release against the real API:

```bash
flutter build apk --release \
  --dart-define=COMMRIDE_ENV=production \
  --dart-define=COMMRIDE_API_BASE_URL=https://<REAL_WORKER_URL> \
  --dart-define=COMMRIDE_MAPS_ENABLED=true
```

For Play distribution:

```bash
flutter build appbundle --release \
  --dart-define=COMMRIDE_ENV=production \
  --dart-define=COMMRIDE_API_BASE_URL=https://<REAL_WORKER_URL> \
  --dart-define=COMMRIDE_MAPS_ENABLED=true
```

A CI release AAB is only a build gate. Store distribution still requires real
signing and the appropriate store setup.

Prefer a controlled internal-testing channel for the first Club pilot.

## 7. Two-Rider functional smoke test

Do this before any road test.

Use two separate accounts/devices and complete:

1. Create/sign in account.
2. Complete Rider profile.
3. Create Vehicle.
4. Create Club.
5. Invite/join the second Rider.
6. Create Ride.
7. Invite/join the second Rider.
8. Create/save Route Plan.
9. Publish Briefing.
10. Both Riders acknowledge Ready.
11. Start Ride.
12. Confirm both appear in Live Group.
13. Exercise a Quick Action.
14. Check in/release a Checkpoint.
15. Send private Ride chat and Leader announcement.
16. Raise SOS.
17. Confirm End Ride is rejected while SOS is active.
18. Cancel/resolve SOS.
19. End Ride.
20. Open Ride Recap.

Any core-flow blocker stops progression to the convoy field test.

## 8. Physical-device GPS and notification test

On Android, record at minimum:

- device model and Android version;
- fresh-install permission flow;
- notification denied then later enabled;
- location denied then later enabled;
- tracking starts only from Active Ride;
- lock screen for at least 20 minutes;
- background/foreground app transitions;
- temporary network loss and recovery;
- Wi-Fi/mobile-data transition;
- OEM battery-optimization behavior;
- visible foreground-location notification;
- FCM SOS/Need Help/Leader-announcement delivery;
- MapLibre/Geoapify marker and freshness state;
- End Ride stops sharing;
- sign-out stops local Ride runtime;
- battery percentage at start/end.

Document force-stop behavior exactly as observed. Do not claim terminated-app
tracking beyond evidence.

Repeat the equivalent acceptance set on a signed physical iPhone before iOS is
called supported for the pilot.

## 9. First convoy field test

Use at least three vehicles so Leader / Member / Sweeper and separation behavior
can be exercised.

Record:

- all Riders become Live;
- one Rider intentionally becomes Stale/Offline;
- last-known position remains explicitly stale/offline;
- reconnect becomes Live only after a fresh accepted observation;
- Saya Berhenti;
- Saya Tertinggal;
- Butuh Bantuan;
- convoy separation attention;
- Checkpoint check-in and Leader release;
- private Ride chat;
- Leader announcement;
- SOS with GPS;
- SOS without GPS if safely reproducible;
- End Ride rejection while active SOS exists;
- successful End Ride after SOS closure;
- Ride Recap planned-vs-sampled distinction.

Interactions that require attention to the screen must be done while safely
stopped.

## 10. Pilot evidence record

Create one evidence record per test Ride:

```text
Git SHA:
API deployment/version:
App version/build:
Android/iOS:
Device models:
Rider count:
Ride duration:
Permission state:
Network scenarios:
Battery start/end:
GPS/background result:
Live/Stale/Offline result:
FCM/APNs result:
MapLibre/Geoapify map result:
SOS result:
Checkpoint result:
Provider/runtime errors:
Cloudflare usage:
Geoapify usage:
Approximate cost:
GitHub defects/issues:
Operator:
Date/time:
```

The first-Club pilot can be called accepted only after repository, provider,
device, and field evidence are all explicitly recorded.
