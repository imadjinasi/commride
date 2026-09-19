# CommRide Mobile

Flutter application for CommRide.

## Current scope

Implemented foundation:

- primary navigation: Home, Ride, Explore, Clubs, Profile;
- CommRide theme tokens;
- Firebase Authentication adapter;
- email/password sign in and account creation;
- authenticated CommRide API client;
- Rider profile onboarding through `GET/PUT /v1/me`;
- Rider Vehicle profile management;
- Club/Ride lifecycle;
- Route Planner flow with place search, route alternatives, Add Stop, Search Along Route, reorder/remove, Checkpoint metadata, and RoutePlan revision save;
- Ride Briefing publish/read/readiness flow tied to immutable RoutePlan revisions;
- Active Ride location-session core with explicit contextual permission and realtime lifecycle contracts;
- authenticated Active Ride WebSocket protocol-v1 client;
- Live Group presence/attention state for Live, Stale, and Offline Riders;
- shared Active Ride realtime runtime;
- native Android/iOS location-provider adapter through reproducible platform bootstrap;
- guarded Google Maps Live Group rendering;
- Completed Ride Recap;
- explicit Ride notification opt-in and Firebase Messaging token lifecycle;
- explicit setup screen when Firebase or API configuration is absent.

Still outside the repository-only acceptance boundary:

- real Firebase/Maps production credentials;
- real-device background/lock-screen/battery validation;
- Play/App Store signing and distribution;
- final field-tested high-fidelity polish.

## Prerequisites

- Flutter stable with Dart compatible with `pubspec.yaml`
- Android SDK for Android builds
- Xcode for iOS builds on macOS
- a Firebase project configured for the target platform when testing real auth

## First local bootstrap

Platform directories are intentionally generated with the local Flutter SDK
rather than hand-maintained before the first verified Flutter bootstrap.

From `apps/mobile`:

```bash
flutter create --platforms=android,ios --project-name commride_mobile \
  --org io.github.imadjinasi .
python tool/configure_platforms.py
flutter pub get
flutter analyze
flutter test
```

Review generated platform identifiers before any store release.

## Firebase configuration

The repository intentionally does not invent or commit a production Firebase
project configuration.

For a real device build, configure Firebase using the official FlutterFire
workflow or verified platform configuration for the Firebase project you
actually own.

The application calls `Firebase.initializeApp()`. If Firebase is not
configured, CommRide shows a setup-required screen instead of bypassing
authentication.

Email/password authentication must be enabled in the selected Firebase project
for the currently implemented sign-in flow.

No SMS OTP is required by the MVP auth flow.

## Run

Development:

```bash
flutter run \
  --dart-define=COMMRIDE_ENV=development \
  --dart-define=COMMRIDE_API_BASE_URL=https://your-api.example
```

Do not pass server secrets through `--dart-define`. Mobile clients cannot
safely hold server secrets.

## Configuration

Supported non-secret defines:

- `COMMRIDE_ENV=development|production`
- `COMMRIDE_API_BASE_URL=<url>`
- `COMMRIDE_MAPS_ENABLED=true|false`

The API base URL is required for authenticated Rider profile bootstrap.

## Authentication flow

1. Firebase determines signed-in/signed-out state.
2. Signed-out users see Sign In / Create Account.
3. Signed-in users call `GET /v1/me` using their Firebase ID token.
4. API `404 rider_profile_not_found` enters Rider profile onboarding.
5. `PUT /v1/me` creates/updates the authenticated Rider profile.
6. A completed profile enters the main CommRide shell.

The client never sends its own auth subject to the API.

## Location permission

Authentication and Rider onboarding do **not** request foreground or background
location permission.

Location permission belongs to the later Ride/location feature and must be
requested contextually when the user uses functionality that requires it.

## UX source of truth

See:

- `../../docs/ux/information-architecture.md`
- `../../docs/ux/interaction-principles.md`
- `../../docs/ux/core-user-flows.md`


## Club and Ride lifecycle

The authenticated application shell now has a server-backed lifecycle client
and UI for the initial Club/Ride flow:

- list membership-scoped Clubs;
- create a Club;
- accept a Club invitation;
- Club owner/admin can invite another Rider by Rider ID;
- list Rides for an active Club membership;
- create a Ride;
- accept a Ride invitation;
- Leader can invite Member/Sweeper/Navigator;
- Leader can publish, start, and end a Ride.

The mobile lifecycle uses explicit command endpoints rather than locally
mutating authoritative Ride state. After restart, Club and Ride lists are
loaded from the API.

Current backend dependencies are the stacked API work in PRs #12 and #16.

Rider-ID invitation is an internal baseline, not the intended final discovery
experience. Invite links, user-friendly Rider lookup, and public discovery are
future product work.

This lifecycle does not yet include live location, checkpoint arrival/release,
chat, or the social feed.

## Route Planner

A joined Ride participant can open the saved RoutePlan. A Leader can edit and
save RoutePlan revisions while the Ride is Draft or Published.

Implemented planning flow:

- search origin and destination;
- compute and choose route alternatives before Stops are added;
- Add Stop with place search;
- on-demand Search Along Route categories;
- preview added distance/time when provider routing summary is available;
- reorder or remove Stops;
- recompute before committing a changed Stop order;
- convert a Stop into a typed Checkpoint;
- set planned Checkpoint duration;
- save the current route as a new RoutePlan revision;
- open external navigation to the next Stop, or the destination when no Stop
  remains in the plan.

If recomputation fails, the UI preserves the previous valid route and Stop
list. It does not replace them with a partial failed state.

Backend runtime behavior depends on the server-side route/place adapter in PR
#22 and RoutePlan persistence in PR #23. The Google Maps Platform web-service
key remains on the server; it is never passed through mobile
`--dart-define`.

Current provider limitation: Search Along Route does not use DRIVE results as a
motorcycle substitute. If the provider rejects `two_wheeler`, the UI explains
the limitation and directs the Leader to ordinary Add Stop search.

The native Google Maps canvas is intentionally not added in repository-only
work yet. Platform Android/iOS directories and platform-restricted map SDK
configuration are generated and verified locally before committing them.
The planner remains functional as a list/summary flow against the CommRide API.

Route planning does **not** request foreground or background location
permission. Live Ride tracking remains a separate contextual permission flow.


## Ride Briefing and readiness

Joined Ride participants can open **Ride Briefing** from Ride detail.

Leader behavior while Draft/Published:

- preview the current saved RoutePlan when no Briefing exists;
- add/edit operational notes;
- publish an immutable Briefing revision;
- publish a new revision when RoutePlan or notes change;
- see current Ready/expected Rider counts.

Rider behavior while Draft/Published:

- read the current Briefing;
- see departure, Leader/Sweeper, route summary, Stops/Checkpoints, and notes;
- confirm **Ready · Sudah dibaca** for the exact Briefing revision.

If RoutePlan changes after Briefing publication, the UI keeps the previous
Briefing visible but marks it stale. Ready is disabled until the Leader
publishes a new Briefing revision.

A newer Briefing revision does not inherit readiness from an older revision.

Readiness is advisory in the MVP. The mobile UI does not treat incomplete
readiness as a hard block for Start Ride.

This mobile flow depends on the backend Briefing API in PR #26. It does not
request location permission and does not assume push notification delivery.


## Active Ride location-session core

The repository now defines a testable Flutter boundary for Active Ride location
sharing without inventing native project configuration.

Core components:

- `RideLocationProvider` — permission + device-location adapter contract;
- `ActiveRideRealtimeClient` — authenticated realtime transport contract;
- `RideLocationSessionController` — lifecycle state machine;
- `ActiveRideTrackingScreen` — contextual permission explanation and visible
  tracking state.

The controller separates Ride lifecycle from OS permission and transport state.

It guarantees at the Flutter/domain boundary that:

- a non-Active Ride cannot start tracking;
- opening the Active Ride screen does not request location permission;
- permission is requested only after the Rider explicitly confirms tracking;
- denied permission stays recoverable and does not fabricate an active session;
- provider samples retain their original observation timestamp;
- failed presence delivery retains only the newest pending observation rather
  than building a long offline GPS trace;
- realtime reconnection can flush that newest pending observation;
- server `ride.ended` stops local location and realtime publishing;
- sign-out teardown stops the local session.

### Native platform bootstrap

Generated Android/iOS projects remain reproducible rather than hand-edited.
After `flutter create`, run:

```bash
python tool/configure_platforms.py
```

The configurator applies the accepted MVP declarations:

- Android coarse/fine location plus location foreground-service permissions;
- Android persistent location foreground-service support without
  `ACCESS_BACKGROUND_LOCATION` by default;
- Android 13+ notification declaration;
- iOS When In Use explanation plus `UIBackgroundModes=location`;
- iOS background-location explanation required by the selected plugin;
- iOS `remote-notification` background mode and the FlutterFire UIScene
  notification-center delegate hook;
- Maps SDK key hooks whose values come only from local environment variables.

Optional local key inputs:

```bash
export COMMRIDE_MAPS_ANDROID_API_KEY=...
export COMMRIDE_MAPS_IOS_API_KEY=...
```

The script writes those values only into generated native files. Do not commit
real keys. Client Maps keys must be restricted to the final Android application
ID / iOS bundle ID and Maps SDK API.

The repository CI generates both native projects and builds an Android debug
APK with Maps disabled, so Dart/native dependency integration is checked without
requiring secrets.

The current default bootstrap organization is `io.github.imadjinasi` for
development builds. Confirm the final store application/bundle identifiers
before release registration; do not treat that default as a claimed production
identifier.

The runtime now includes `GeolocatorRideLocationProvider`. It starts only
after the Rider explicitly enables tracking from an Active Ride. Android uses a
visible foreground-service notification; iOS uses a foreground-started
continuous location session. Real lock-screen/app-switch/battery behavior still
requires device verification before #33 can be accepted.


## Active Ride realtime mobile client

The mobile code now includes an Android/iOS-oriented Dart IO WebSocket adapter
for the backend Active Ride protocol v1.

Behavior:

- converts the configured CommRide API base URL from `https/http` to
  `wss/ws`;
- connects to `/v1/rides/:rideId/live?v=1`;
- obtains a fresh Firebase ID token for each initial/reconnect attempt;
- sends the token only as an Authorization Bearer header;
- never sends authoritative Rider ID in `presence.update` payloads;
- preserves each device sample's original `observedAt` timestamp;
- emits structured connection-state events to the location-session controller;
- parses server `ride.ended` and stops reconnect intent;
- exposes structured protocol errors without fabricating disconnects;
- reconnects after unexpected socket loss with bounded backoff of 1s, 2s, 5s,
  then 10s.

The adapter uses `dart:io`, matching the current Android/iOS-first product
scope. No browser/Web transport is implied by this implementation.

This still does not make device GPS operational by itself. A verified native
`RideLocationProvider` implementation and generated Android/iOS platform
configuration remain required before live Ride tracking works on a real device.


## Live Group

The mobile Active Ride layer now consumes group coordination events from the
backend protocol without requiring a native map canvas.

Handled server events:

- `ride.snapshot`
- `presence.updated`
- `quick_action.raised`
- `ride.ended`
- structured `error`

The group controller keeps only one latest operational presence per Rider.
An observation older than the current Rider observation is ignored. An equal
observation may still update freshness, for example Live -> Offline after the
socket closes.

Freshness behavior:

- server Live is shown as Live only while its observation remains inside the
  documented 30-second freshness window;
- local time may age Live -> Stale;
- server Stale and Offline are never promoted back to Live without a new
  presence event;
- last-known observation age stays visible for Stale/Offline positions;
- Ride end downgrades all retained last-known Rider presence to Offline while
  preserving the last observation timestamp;
- the list does not animate, extrapolate, or score Rider movement.

The initial non-map **Live Group** screen shows:

- realtime connection/end state;
- Live / Stale / Offline counts;
- recent structured attention actions;
- Rider role, movement state, freshness, and observation age.

Recent quick actions are deduplicated by event ID and kept in a bounded list.
The initial labels are:

- `stopping` -> **Saya Berhenti**
- `left_behind` -> **Saya Tertinggal**
- `need_help` -> **Butuh Bantuan**

This view intentionally does not show a stream of exact coordinates as normal
product copy. Coordinates remain part of operational presence for future map
rendering.


## Rider Quick Actions

Active Ride now has a typed low-friction send path for:

- **Saya Berhenti**
- **Saya Tertinggal**
- **Butuh Bantuan**

The basic action is one tap from Live Group. A Rider may optionally add a short
reason (up to 240 characters) before sending.

The mobile client sends only:

- protocol version;
- client event ID;
- send timestamp;
- quick-action kind;
- optional reason.

It deliberately does **not** send authoritative Rider ID or a second location
claim for the action. The backend derives Rider identity from the authenticated
socket and may attach the latest server-accepted RiderPresence context.

Incoming quick actions may therefore include optional presence context. Live
Group shows only its freshness and observation age, not raw coordinates as the
primary action UI.

If realtime is disconnected, sending fails explicitly in the UI. CommRide does
not silently build an unbounded offline quick-action queue.

**Butuh Bantuan** is a Rider-to-group coordination action, not SOS and not a
claim that emergency services were contacted. It can be raised even when no
GPS presence is available on the server.


## Checkpoint coordination

The mobile Ride detail now exposes **Checkpoints** for participating Riders
when a Ride is Active or Completed.

The screen consumes the persisted Checkpoint API rather than inferring arrival
from RiderPresence.

Active Ride behavior:

- ordered current / upcoming / released Checkpoints;
- explicit expected / arrived / missing counts;
- Rider **Saya sudah tiba** manual check-in;
- manual check-in is clearly labeled as **not GPS verification**;
- late manual check-in remains available for a released Checkpoint while the
  Ride is still Active;
- Leader-only **Lepas Checkpoint** for the current Checkpoint;
- when Riders are still missing, release requires explicit confirmation that
  shows the missing count;
- API response becomes the new authoritative local view after every mutation.

Completed Ride behavior is read-only. It keeps release and check-in history
visible but removes mutation actions.

This slice does not request location permission, use geofencing, or call a map
provider.


## Private Ride Comms

Active and Completed Ride detail now exposes a private **Comms** surface for
eligible Ride participants.

The mobile contract follows the backend's D1-authoritative communication model:

- message history loads from the authenticated HTTP API;
- participant chat sends through the persisted HTTP command;
- Leader announcement sends through the separate Leader-only HTTP command;
- every send carries a bounded client-generated `clientMessageId`;
- a failed send remains visibly failed and retry reuses the **same**
  `clientMessageId` so backend idempotency remains effective;
- HTTP success is inserted into local history without waiting for realtime;
- Completed Ride remains readable but removes all compose/announcement actions.

The screen keeps the latest Leader announcement visually separate from ordinary
chat. Quick Actions, Checkpoints, convoy separation, Ride End, and future SOS
remain typed operational state rather than being flattened into chat.

Incoming protocol event `ride.message_created` is parsed into
`ActiveRideMessageCreated`, and `RideCommsController` can consume a shared
Active Ride realtime client to insert a persisted message without duplicating
the HTTP-created record.

The current app entrypoint deliberately does **not** open a second
screen-specific Active Ride WebSocket for Comms. Active Ride room connection
ownership still needs to be centralized because the room replaces an older
socket for the same Rider. Until that shared session is wired, the Comms screen
uses HTTP history/refresh as the authoritative recovery path instead of
competing with future location/Live Group socket ownership.

Message bodies render as plain text. No HTML/rich-text execution, attachment
upload, edit/delete, voice note, or public/social exposure is introduced by
this slice.


## Persistent Ride SOS

Active and Completed Ride detail exposes a dedicated **SOS** surface. SOS is
kept separate from ordinary Comms and from the lightweight **Butuh Bantuan**
Quick Action.

Mobile behavior:
- authenticated HTTP history is authoritative;
- Active Ride participants deliberately confirm before raising SOS;
- optional reason is bounded to the backend contract;
- every raise uses a client-generated `clientCommandId`;
- failed raise remains visibly failed and retry reuses that exact ID;
- the app never fabricates Active SOS before server acknowledgement;
- SOS remains valid when no GPS/presence snapshot exists;
- trusted presence is labeled Live/Stale/Offline and shown as last-known
  context, not implied current position;
- the Rider who raised an Active SOS can cancel it;
- the Ride Leader can resolve an Active SOS;
- Completed Ride is history-only.

The realtime parser understands `ride.sos_raised`,
`ride.sos_cancelled`, and `ride.sos_resolved`. The controller can consume a
shared Active Ride realtime client and replaces incidents by persisted ID.

As with Comms, the current SOS screen does not open a second screen-specific
Active Ride socket. Until shared session ownership is centralized, HTTP
load/refresh is the recovery path.

The confirmation UI explicitly states that CommRide does **not** automatically
contact ambulance, police, or public emergency services.


## Live Rider map runtime

The Live Group surface now supports Map / List when
`COMMRIDE_MAPS_ENABLED=true`.

Map behavior is intentionally conservative:

- one marker per server-accepted RiderPresence;
- Live / Stale / Offline remain explicit;
- Stale/Offline coordinates are labeled as last-known;
- server-derived convoy separation may affect attention styling;
- incoming presence updates do not continuously recenter the camera;
- **Fit Group** is an explicit Rider action;
- no speed leaderboard or racing metric is introduced.

If Maps is disabled, the existing Live Group list remains the operational
fallback.


## Ride notifications

CommRide uses Firebase Cloud Messaging only as a delivery surface. Authoritative
Ride state remains in the API/realtime room.

The signed-in app shell owns one notification controller:

- app startup checks existing OS permission but **never prompts automatically**;
- if permission already exists, the current FCM token is synchronized silently;
- Profile exposes **Aktifkan notifikasi Ride** as the explicit permission action;
- Firebase token rotation re-registers the new token;
- foreground messages appear as an in-app snackbar;
- explicit sign-out attempts best-effort token unregistration before Firebase
  sign-out;
- notification cleanup failure never blocks sign-out.

The server currently targets high-value operational notifications: SOS,
Need Help, Left Behind, confirmed convoy separation, Leader announcement,
Briefing publication, and Checkpoint release.

For a real Firebase build, configure the Android/iOS Firebase application using
the actual project. Do not commit server service-account credentials.

For iOS device delivery, also configure the final Xcode target with the
**Push Notifications** capability and the real APNs/Firebase relationship.
The reproducible bootstrap adds the runtime Info.plist/AppDelegate declarations,
but it intentionally does not invent an `aps-environment` entitlement or
signing identity.

The API-side FCM sender needs these environment secrets:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL`
- `FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY`

Those values belong in the deployment secret store, not mobile
`--dart-define` and not Git.
