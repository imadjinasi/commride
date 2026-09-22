# Android Device UAT — 22 September 2026

Status: Round 1 in progress  
Source baseline: `a1d04a949b9de12a46f79be8d24758984a175c0d`

## Operator evidence

A release APK was built locally after repository tests passed:

- `flutter test`: 162 tests passed;
- `flutter build apk --release --dart-define-from-file=pilot-defines.local.json`: PASS;
- output: `build/app/outputs/flutter-apk/app-release.apk`.

The operator tested checklist items 1–6 from the first Android device acceptance pass.
Anything in those items not listed as a gap below is accepted for this round only.
Checklist items 7 onward remain untested and must not be treated as Device PASS.

## Gaps found

1. Android orientation changed even though the device auto-rotate setting was disabled.
   CommRide must follow the user's device orientation preference rather than forcing
   sensor-driven rotation.
2. The approved CommRide logo must remain visible in the main application header,
   not only on authentication/startup surfaces.
3. Email/password authentication needs an explicit forgot/reset-password flow.
4. Club invitation asks for a Rider ID, but the Rider cannot discover that ID in
   the Profile UI. Profile must expose the Rider ID and make it easy to copy.
5. The operator has revised the approved branding assets locally. The canonical
   repository assets must be replaced with those revised files before this round
   is accepted.

## Deferred acceptance

Active Ride/navigation, Quick Actions, Comms/SOS, background behavior, Ride end,
multi-device Live/Stale/Offline behavior and field-convoy acceptance remain outside
this round until the gaps above are closed and a new APK is installed.

Repository fixes and CI do not by themselves close Device PASS. Re-test the exact
post-fix APK on Android and append the result here or in a later dated evidence
record.
