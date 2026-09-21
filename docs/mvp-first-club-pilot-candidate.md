# MVP First-Club Pilot Repository Baseline

This document records the repository-side baseline for the first CommRide
real-Club pilot.

## Integrated main baseline

As verified on 21 September 2026, the integrated repository baseline is:

`a5d5f33c38b6815da4272380119c36180b6245c8`

That baseline includes:

- PR #65, which assembled the first-Club pilot integration candidate and merged
  as `d8cd3f3fcc0ecab94db5e1efc5f12b471f507331`;
- PR #66, which restored the Rider-owned Vehicle API omitted by the initial
  integration and merged as the current baseline
  `a5d5f33c38b6815da4272380119c36180b6245c8`.

API CI passed on the exact current baseline. Mobile CI passed on the exact
mobile source tree inherited from PR #65; PR #66 changed backend/documentation
files only.

This evidence proves repository readiness only. It does not prove that a
Cloudflare/Firebase/map-provider environment has been deployed or that
physical-device and convoy acceptance has passed.

## Included product flow

The integrated repository contains the end-to-end MVP path:

**Account / Rider profile → Vehicle → Club → Ride → Route Planner →
Briefing / Ready → Start Ride → Live Group → Quick Actions → Checkpoints →
Private Comms → SOS → End Ride → Ride Recap**

Repository-side supporting behavior includes:

- authenticated Active Ride WebSocket room;
- native Android/iOS platform bootstrap;
- explicit contextual location permission;
- background-capable location-session declarations;
- Live/Stale/Offline Rider presence semantics;
- guarded Live Group map rendering currently implemented with Google Maps in
  the integrated source; the accepted pilot migration to MapLibre + Geoapify is
  still pending;
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

Repository readiness means:

- source compiles/analyzes;
- automated unit/widget tests pass;
- D1 migrations validate;
- generated native declarations validate;
- Android debug APK builds in CI;
- Android release AAB builds in CI;
- obvious provider/signing secret files are rejected by CI.

It does **not** mean the application has passed real-device, provider,
store-signing, or field validation.

## Operator / device gates still required

Before inviting real Riders, complete
[`pilot-release-checklist.md`](pilot-release-checklist.md) and the
[`pilot operator runbook`](deployment/pilot-operator-runbook.md), including:

- keep the accepted Android application ID
  `io.github.imadjinasi.commride` stable and finalize the iOS bundle ID before
  iOS provider registration;
- real Cloudflare D1 / Durable Object resources and deployment;
- complete FlutterFire/native Android integration against the existing
  `commride-pilot` Firebase project;
- register/configure the iOS Firebase app only after its bundle ID is final;
- API FCM service-account secrets in the deployment secret store;
- real APNs configuration and signed iOS entitlement;
- a separate reviewed source migration from the existing Google Maps runtime to
  MapLibre + Geoapify;
- separate Geoapify trust boundaries for the server provider key and the mobile
  map/style key where required;
- Android/iOS physical-device background tracking;
- notification receipt on real devices;
- lock-screen and network-recovery tests;
- OEM battery-optimization checks;
- actual battery-drain measurement;
- real convoy field test;
- provider usage/cost observation.

Google Maps billing/credential setup is not a first-pilot acceptance gate after
the provider decision change.

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
