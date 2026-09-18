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
- explicit setup screen when Firebase or API configuration is absent.

Not implemented yet:

- vehicle profile UI;
- Google Maps;
- background location;
- realtime Ride state;
- final high-fidelity design.

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
flutter create --platforms=android,ios --project-name commride_mobile .
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

This lifecycle does not yet include Route planning, checkpoints, live location,
chat, or the social feed.
