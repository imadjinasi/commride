# MVP First-Club Pilot Candidate

This document records the repository-only integration candidate for the first
CommRide real-Club pilot.

Candidate integration commit:

`d9e725ca675411230a2fda3232ab51081a627060`

The commit has two parents:

- mobile pilot-hardening line;
- backend notification-completion line.

It does **not** mean either parent PR, or this integration candidate, has been
merged to `main`.

## Included product flow

The integrated repository now contains the end-to-end MVP path:

**Account / Rider profile → Vehicle → Club → Ride → Route Planner →
Briefing / Ready → Start Ride → Live Group → Quick Actions → Checkpoints →
Private Comms → SOS → End Ride → Ride Recap**

Repository-side supporting behavior also includes:

- authenticated Active Ride WebSocket room;
- native Android/iOS platform bootstrap;
- explicit contextual location permission;
- background-capable location-session declarations;
- Live/Stale/Offline Rider presence semantics;
- Google Maps Live Group adapter guarded by runtime config;
- shared Active Ride realtime ownership;
- server-derived convoy-separation attention;
- low-frequency Completed Ride journey sampling;
- persistent SOS with optional trusted last-known presence;
- FCM device-token lifecycle;
- high-priority Ride notification fan-out;
- Published Ride reminders;
- Ride Recap available notification;
- sampled-location retention;
- realtime event cadence guards;
- Android debug APK and release AAB CI build gates.

## Repository acceptance boundary

The candidate may be called **repository-complete for first-club pilot**
only when both API CI and Mobile CI pass on this exact integration head.

That statement means:

- source compiles/analyzes;
- automated unit/widget tests pass;
- D1 migrations validate;
- generated native declarations validate;
- Android debug APK builds;
- Android release AAB builds;
- CI contains no tracked provider/signing secret files.

It does **not** mean the application has passed real-device or production
provider validation.

## Operator / device gates still required

Before inviting real Riders, complete the checklist in
`docs/pilot-release-checklist.md`, including:

- real Cloudflare D1 / Durable Object resources and deployment;
- real Firebase Android/iOS app registration;
- API FCM service-account secrets;
- real APNs configuration and signed iOS entitlement;
- restricted Android/iOS Maps keys;
- restricted server-side Maps key;
- final application/bundle identifiers;
- Android/iOS physical-device background tracking;
- notification receipt on real devices;
- lock-screen and network-recovery tests;
- OEM battery-optimization checks;
- actual battery-drain measurement;
- real convoy field test;
- provider usage/cost observation.

CI must never be used as evidence that those gates passed.

## Current deliberate product limits

The first pilot does not claim:

- automatic emergency-service dispatch;
- crash/fall detection;
- voice-note/media messaging;
- turn-by-turn embedded navigation;
- public social feed/follow/badge implementation;
- terminated-app GPS behavior beyond what a real device test proves;
- exact full-trip GPS history.

CommRide remains a group coordination product; it is not represented as an
emergency-response service.

## Traceability

Recent completion stack includes:

- #54 native Live Ride / Live Group map runtime;
- #56 backend MVP finish + Ride Recap;
- #57 mobile Completed Ride Recap;
- #60 backend FCM notification lifecycle;
- #61 mobile explicit notification opt-in;
- #62 backend pilot hardening;
- #63 mobile build/native hardening;
- #64 Ride reminder + Recap notification completion.

Those PRs remain independent review units. This integration branch exists so
the combined result can be validated before any decision to merge.
