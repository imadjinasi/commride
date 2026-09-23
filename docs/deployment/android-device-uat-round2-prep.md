# Android Device UAT — Round 2 Preparation

Status: repository follow-up in progress  
Baseline: `68715e4636907c6f065a3d559e7ef0dfa71739d2`

The first Android device pass covered checklist items 1–6. The operator accepted
all behavior in that range except the gaps already closed by PR #80.

Before producing another APK, audit the remaining checklist items so one rebuild
can cover the next meaningful device pass.

## Repository gaps found

1. **Start Ride flow**
   - the current Leader action transitions Published -> Active immediately;
   - it does not show the documented pre-start readiness review;
   - after a successful start it remains on Ride Detail instead of foregrounding
     the Active Ride command center.

2. **Active Ride operational access**
   - Quick Actions exist in Live Group, but are not directly reachable from the
     primary navigation surface;
   - text Comms exist from Ride Detail, but are not directly reachable from the
     primary Active Ride navigation surface.

3. **Rider ID discoverability**
   - Profile and Club invite now explain Rider ID, but the Ride invite dialog
     still lacks the same guidance.

4. **End Ride protection**
   - End Ride is currently a one-tap destructive operational transition.
     Add an explicit confirmation while preserving the server-side active-SOS
     guard and local tracking teardown.

## Already implemented; still needs device evidence

- Briefing revision/readiness UI;
- explicit location start and permission request;
- Android foreground location notification configuration;
- Active Ride MapLibre navigation and RiderPresence overlay;
- rejoin-first off-route recovery;
- Live/Stale/Offline semantics;
- Quick Action realtime transport;
- Comms and Leader announcement;
- SOS raise/cancel/resolve;
- End Ride server event and local location-session teardown.

Repository implementation is not Device PASS. Background/lock-screen continuity,
notification delivery, multi-device presence and field convoy behavior remain
operator/device acceptance work after the next APK is installed.


## Round 2 device findings — 23 September 2026

- Password reset returned the Rider to an account state without the expected
  history. Treat this as a blocking identity-continuity defect; password reset
  must preserve the Firebase identity mapping and Rider history.
- The persistent CommRide header logo is visually too small. The primary logo
  needs a horizontal layout slot rather than a square 44 px box. The repository
  already contains the PR #80 branding assets; any newer operator-local artwork
  still requires an explicit asset handoff before it can be committed.
- RoutePlan and Briefing both fail to load on the current pilot runtime.
  Repository review shows both read paths now depend on
  `route_plans.maneuvers_json`, introduced by migration
  `0009_route_plan_maneuvers.sql`. Remote D1 migration state must be verified
  and 0009 applied before classifying this as a mobile defect.
- Add persistent in-app notification surfaces for **Account** and **Club**.
  OS push remains an optional delivery channel; notification history must not
  disappear merely because push permission is denied.
