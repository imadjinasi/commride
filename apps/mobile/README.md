# CommRide Mobile

Flutter application shell for CommRide.

## Current scope

This scaffold implements only the documented top-level information architecture:

- Home
- Ride
- Explore
- Clubs
- Profile

It intentionally does **not** implement authentication, maps, background location, realtime Ride state, or final visual design yet.

## Prerequisites

- Flutter stable with Dart compatible with `pubspec.yaml`
- Android SDK for Android builds
- Xcode for iOS builds on macOS

## First local bootstrap

Platform directories are intentionally generated with the local Flutter SDK rather than hand-maintained before the first verified Flutter bootstrap.

From `apps/mobile`:

```bash
flutter create --platforms=android,ios --project-name commride_mobile .
flutter pub get
flutter analyze
flutter test
```

Review generated platform identifiers before any store release.

## Run

Development:

```bash
flutter run --dart-define=COMMRIDE_ENV=development
```

With an API endpoint:

```bash
flutter run \
  --dart-define=COMMRIDE_ENV=development \
  --dart-define=COMMRIDE_API_BASE_URL=https://example.invalid
```

Do not pass secrets through `--dart-define`. Mobile clients cannot safely hold server secrets.

## Configuration

Currently supported non-secret defines:

- `COMMRIDE_ENV=development|production`
- `COMMRIDE_API_BASE_URL=<url>`

Provider keys and platform-specific configuration will be added only when the relevant integration issue is implemented.

## UX source of truth

See:

- `../../docs/ux/information-architecture.md`
- `../../docs/ux/interaction-principles.md`
- `../../docs/ux/core-user-flows.md`
