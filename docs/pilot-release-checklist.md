# CommRide First-Club Pilot Checklist

Status meaning:

- **Repository gate** — can be proved by source/CI before field testing.
- **Operator gate** — needs real cloud/provider configuration.
- **Device gate** — needs a real Android/iOS device and a Ride.

The first pilot is not accepted until all three classes of gate have evidence.
Repository PASS must never be used as evidence that a device/operator gate
passed.

## 1. Repository gate

Required before handing the build to pilot Riders:

- API typecheck, tests, and migration validation PASS.
- Mobile format, analyze, tests, native bootstrap, Android debug APK, and
  Android release AAB build PASS.
- No Firebase service-account key, map-provider API key, APNs key, signing
  keystore, or password committed.
- Active Ride uses one shared authenticated realtime session per signed-in app.
- GPS starts only after explicit Rider action.
- Stale/Offline positions remain visibly non-Live.
- End Ride stops local tracking and the server room.
- Active SOS blocks End Ride until cancelled/resolved.
- Completed Ride Recap does not invent actual distance when samples are absent.
- FCM failure cannot roll back authoritative Ride state.
- sampled location retention is bounded and tested.
- normal client cadence stays below realtime abuse ceilings.

## 2. Application identity and Firebase operator gate

Recorded operator evidence on 21 September 2026:

- Android application ID is fixed for the pilot baseline as
  `io.github.imadjinasi.commride`;
- Firebase project `commride-pilot` exists;
- Android Firebase app `CommRide` is registered with that application ID;
- Firebase Email/Password authentication is enabled;
- Android `google-services.json` was downloaded locally and must remain
  untracked.

Still required before a real pilot build is accepted:

- decide and record the final iOS bundle ID before iOS provider registration;
- treat Android/iOS identifiers as long-lived release identity, not website
  URLs;
- complete the official FlutterFire/native Android integration using the real
  local provider file;
- register/configure iOS Firebase only after its bundle ID is final;
- configure FCM HTTP v1 service-account credentials only in the API deployment
  secret store;
- rotate any credential that was ever copied into an insecure location;
- verify Firebase token audience matches `FIREBASE_PROJECT_ID`;
- verify a real installed CommRide build can sign in to Firebase.

For iOS push delivery:

- enable the Xcode **Push Notifications** capability for the final target;
- connect the actual APNs key/certificate to Firebase;
- verify the signed build contains the correct `aps-environment` entitlement.

## 3. Map/navigation provider gate

The accepted navigation-first pilot direction is **MapLibre + CommRide
Navigation Engine**. Geoapify is the proven route/place fallback; Valhalla is the
target self-hosted motorcycle router; TomTom REST traffic/incidents are optional
until explicitly configured. Google remains optional and is not a pilot billing
prerequisite.

Repository/provider boundaries must remain explicit:

- MapLibre renders the embedded Active Ride map;
- CommRide Navigation Engine consumes the persisted provider-independent
  RoutePlan locally for progress, maneuver and recovery state;
- Geoapify remains available for autocomplete/place/Search Along Route and
  motorcycle routes while replacement providers are unproven;
- Valhalla may replace only the route adapter after real HTTPS runtime,
  motorcycle costing, Stops, maneuvers and error behavior pass acceptance;
- TomTom traffic may be enabled only with a server-side key and verified
  Indonesian runtime evidence;
- keep provider response models inside adapters and return CommRide DTOs;
- keep provider/server keys only in the Cloudflare secret store;
- keep any mobile map/style credential out of Git and do not reuse a server key;
- Search Along Route and recovery-route computation are bounded/on-demand, not
  triggered by every map or GPS update;
- route alternatives must be materially different;
- a provider failure must preserve the previous valid RoutePlan;
- off-route recovery must not automatically replace the shared RoutePlan.

Do not call Valhalla, TomTom traffic, embedded navigation or field behavior
accepted merely because source support exists.

## 4. Cloudflare operator gate

Provision verified resources and update deployment configuration with real IDs:

- D1 database;
- Active Ride Durable Object binding/migration;
- Worker environment variables;
- FCM secrets;
- Geoapify server/provider key after the provider-migration environment
  contract is implemented;
- daily scheduled trigger.

Apply D1 migrations in order and record the exact deployed commit.

Confirm:

- `GET /health`;
- `GET /version`;
- Firebase-authenticated API request;
- WebSocket upgrade to an Active Ride;
- scheduled retention invocation.

## 5. Privacy and retention

Current MVP policy:

- Live RiderPresence is operational state, not permanent history.
- Completed Ride location history stores at most one accepted sample per Rider
  per minute.
- Default sampled-location retention is 30 days.
- `LOCATION_SAMPLE_RETENTION_DAYS` may be configured from 1 to 365 days.
- SOS may retain a one-time trusted last-known presence snapshot.
- Push tokens belong to authenticated Riders and must not be included in public
  output.
- Following/public Club visibility must never grant access to private Ride
  location.

Before public beta, the privacy notice must state what is collected during an
Active Ride, why it is collected, how long sampled location is retained, and
who can see it.

## 6. Account export and deletion requirements

These are release requirements even though the MVP does not yet expose a
self-service delete/export button.

A Rider data export must be able to account for:

- Rider profile;
- Vehicles;
- Club memberships;
- Ride memberships/roles;
- authored retained Ride messages;
- SOS incidents involving the Rider;
- retained sampled Ride locations still inside the retention window;
- completed Ride/Recap participation.

Push delivery tokens are device credentials/operational identifiers; do not
present them as ordinary profile content.

Before implementing account deletion, define and test:

- how sole Club ownership is transferred or the Club is closed;
- which completed Ride records must remain for other participants;
- whether retained shared Ride records are anonymized instead of deleted;
- deletion of active device push tokens;
- deletion of retained sampled location for the Rider where policy allows;
- Firebase Authentication account deletion;
- a bounded completion timeline and support escalation path.

Do not implement destructive cascades until those shared-record rules are
approved.

## 7. Android device gate

Test at minimum:

- fresh install;
- notification permission denied / later enabled;
- location permission denied / later enabled;
- start tracking only from Active Ride;
- screen off / lock screen for at least 20 minutes;
- app background/foreground cycles;
- temporary network loss and recovery;
- mobile-data ↔ Wi-Fi transition;
- force-stop behavior documented accurately;
- OEM battery-optimization behavior on at least one aggressive Android vendor;
- foreground location service notification remains visible while tracking;
- FCM SOS/Need Help/Leader announcement receipt;
- MapLibre/Geoapify marker and freshness rendering;
- End Ride stops location sharing;
- sign-out stops the local Ride runtime;
- battery drain recorded for a representative Ride duration.

Do not claim support for terminated-app tracking beyond what the tested OS/OEM
combination actually demonstrates.

## 8. iOS device gate

On a signed physical iPhone:

- notification permission lifecycle;
- When In Use location permission lifecycle;
- start tracking in foreground;
- background and lock-screen location continuation;
- blue/background location indicator behavior;
- APNs/FCM receipt;
- app foreground/background transitions;
- temporary network loss/recovery;
- MapLibre/Geoapify rendering with the final iOS configuration;
- End Ride and sign-out teardown;
- representative battery drain.

The repository does not claim this passes until a real signed iOS build is
tested.

## 9. Convoy field test

Use at least three vehicles so separation logic can be exercised.

Record evidence for:

- all Riders become Live after joining;
- Stale/Offline transitions when one device loses connectivity;
- last-known timestamp remains visible;
- Rider reconnect returns to Live only after a new accepted observation;
- Saya Berhenti / Saya Tertinggal / Butuh Bantuan;
- confirmed convoy separation attention;
- Checkpoint manual check-in and Leader release;
- private chat and Leader announcement;
- SOS raise/cancel/resolve, including a no-GPS SOS;
- End Ride rejection while SOS is active;
- successful End Ride after SOS is closed;
- Ride Recap planned-vs-sampled distinction.

## 10. Cost guardrails

Before pilot:

- verify the current Geoapify plan limits/quotas in the provider console;
- keep route/place/Search Along Route calls intentionally bounded and
  on-demand;
- inspect Cloudflare request, D1, and Durable Object usage after each test Ride;
- observe both mobile map tile/style traffic and backend Geoapify API traffic;
- record notification send volume;
- record sampled-location row count per Rider-hour;
- keep the first pilot Club/Ride size deliberately small.

After each pilot Ride, calculate an observed cost-per-Active-Ride estimate from
actual provider usage rather than assuming that any free tier will always cover
usage.

## 11. Pilot evidence record

For each test Ride, record:

- app/API commit SHA;
- Android/iOS app version/build;
- device models + OS versions;
- Ride duration and Rider count;
- permission states;
- network conditions tested;
- battery start/end;
- observed GPS/realtime problems;
- notification outcomes;
- provider/runtime errors;
- approximate provider usage/cost;
- defects linked to GitHub issues.

A repository-only CI result is evidence only for the repository gate.
