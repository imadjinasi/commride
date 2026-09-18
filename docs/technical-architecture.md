# CommRide Technical Architecture v0.1

Status: Proposed  
Date: 18 September 2026

## 1. Goals

The first architecture should:

- support Android first without blocking iOS;
- keep fixed infrastructure cost close to zero at small scale;
- scale down when no Ride is active;
- support background location;
- support realtime Ride rooms;
- avoid excessive Google Maps API usage;
- avoid premature microservices;
- preserve an escape path from any individual map provider.

## 2. Proposed stack

### Mobile
**Flutter**

Reasoning:
- Android + iOS from one primary codebase;
- strong mobile UI ecosystem;
- native bridges available for background location and platform-specific behavior.

### Authentication and push
**Firebase Authentication** for initial non-SMS identity flows.  
**Firebase Cloud Messaging (FCM)** for Android push notifications.

iOS later uses APNs through an appropriate integration.

SMS OTP is intentionally not required for MVP due to cost and operational complexity.

For the custom Cloudflare Worker API, the mobile client sends its Firebase ID
token as a Bearer token over HTTPS. The Worker verifies the token signature
against Firebase's published public signing certificates and validates the
Firebase project audience/issuer plus token timing and subject claims.

The initial verification path uses an edge-compatible JWT library rather than
requiring the Firebase Admin SDK or a service-account private key solely for
ID-token verification. The Firebase project ID is configuration; no production
Firebase project is assumed to exist from repository code alone.

Standard ID-token verification does not by itself prove token revocation. A
revocation/account-disable strategy must be addressed before production policy
requires immediate session invalidation.

### Backend edge/API
**Cloudflare Workers**

Responsibilities:
- authenticated API;
- Club/Ride business logic;
- route provider orchestration;
- social API;
- notification orchestration;
- Ride state transitions.

### Persistent data
**Cloudflare D1** for early-stage relational persistence.

Suitable initial domains:
- Riders;
- Clubs;
- memberships;
- Rides;
- route metadata;
- checkpoints;
- posts;
- achievements.

D1 is chosen for low fixed cost and early-stage simplicity, not because it is the final database for all future scale.

### Realtime Ride room
**Cloudflare Durable Objects**

Model:
- one logical realtime coordination room per Active Ride;
- authenticated WebSocket clients join through the Worker API;
- Worker verifies Firebase identity, Rider profile, Ride state, and RideMembership before forwarding the upgrade to the room;
- room identity is derived from Ride ID; client input never selects another Rider identity;
- latest Ride presence/state kept near the room;
- outgoing updates broadcast to authorized participants;
- Cloudflare WebSocket Hibernation API is used so idle connected rooms can hibernate;
- per-connection Rider metadata is stored as WebSocket attachment so it survives hibernation.

The initial protocol is versioned as `v=1`. An unsupported protocol version is
rejected before the WebSocket upgrade.

### Object storage
**Cloudflare R2**

Future use:
- avatars;
- Club images;
- Ride photos;
- incident attachments.

Do not upload large media in the first implementation unless required.

### Maps and route provider
Initial provider: **Google Maps Platform**

Expected capabilities:
- Maps SDK;
- Places autocomplete/search;
- Routes;
- route alternatives;
- Add Stop/waypoints;
- Nearby Search;
- Search Along Route.

The first web-service adapter runs server-side in the Worker. The mobile app
does not receive the Google Maps Platform web-service key and does not depend
on raw Google response models.

Provider limitations must remain explicit. As of the implementation baseline,
Google Routes supports `TWO_WHEELER` where region support is available, but
Places Search Along Route does not support `TWO_WHEELER`. CommRide therefore
must not silently present DRIVE routing summaries as motorcycle-specific
results.

Embedded Navigation SDK is not required for MVP.

The app may deep-link to:
- Google Maps;
- Waze;
- Apple Maps on iOS;

for turn-by-turn guidance.

## 3. Provider abstraction

Business logic should not directly depend on Google-specific APIs throughout the codebase.

Conceptual interfaces:

### MapPlaceProvider
- autocomplete()
- searchPlace()
- searchNearby()
- searchAlongRoute()

### RouteProvider
- computeRoutes()
- computeRouteWithStops()
- routeAlternatives()
- routeMetadata()

Provider-specific models should be converted into CommRide domain DTOs.

This does not need an elaborate plugin framework. A clear adapter boundary is enough.

## 4. High-level runtime

```
Flutter App
  |
  | HTTPS
  v
Cloudflare Worker API
  |-- D1
  |-- R2
  |-- Google Maps/Routes/Places
  |-- Firebase notification integration
  |
  | WebSocket / Ride channel
  v
Durable Object: Active Ride Room
  |-- latest Rider presence
  |-- Ride operational state
  |-- broadcast events
  `-- checkpoint / quick-action realtime events
```

## 5. Realtime location strategy

A location update should not automatically become a permanent database write.

### Active Ride protocol v1

Client -> room:
- `presence.update`
- `quick_action.raise`

Room -> client:
- `ride.snapshot`
- `presence.updated`
- `quick_action.raised`
- `ride.ended`
- `error`

Each client event carries:
- `v: 1`;
- a client-generated `eventId`;
- `sentAt`;
- typed payload.

The server derives Rider ID and Ride role from the authenticated WebSocket
attachment. Rider identity is never accepted from the event payload.

### Presence freshness

The room stores only the latest operational RiderPresence per Rider for room
recovery; it does not append every GPS message.

Initial freshness policy:
- **Live**: latest accepted observation age <= 30 seconds while a socket is connected;
- **Stale**: observation age > 30 seconds;
- **Offline**: no active socket for that Rider; last-known position may remain with its timestamp.

The 30-second freshness threshold is an initial coordination policy and may be
changed after field testing. UI must always show the observation timestamp and
must not animate stale/offline coordinates as live.

Presence updates with an `observedAt` older than the currently accepted
observation for that Rider are ignored so reconnect queues cannot regress
latest-known state.

The room may periodically confirm the Ride is still Active from authoritative
D1 state, but must not perform a D1 write for each location update.

### Room end

When Ride state becomes Completed, the lifecycle command signals the room.
The room broadcasts `ride.ended`, rejects further operational messages, and
closes connected sockets. New connections are independently rejected by the
Worker because D1 Ride state is no longer Active.

Proposed path:

```
Rider GPS
  -> Flutter background location
  -> authenticated WebSocket
  -> Active Ride Durable Object
  -> update latest RiderPresence
  -> broadcast compact presence update
  -> sample selected points to history when needed
```

### Why
A group with many Riders can generate large numbers of coordinates. Realtime operational state and permanent history have different requirements.

### Adaptive cadence
Exact values require field testing.

Potential policy:
- moving: moderately frequent updates;
- stopped: slower updates;
- foreground map: potentially more responsive;
- weak connection: queue/retry selectively;
- critical event/SOS: immediate position event.

Battery life is a product requirement, not just an implementation detail.

## 6. Historical location

Permanent route history should use sampling and event-triggered points rather than storing every GPS message.

Candidate triggers:
- elapsed interval;
- meaningful distance moved;
- checkpoint arrival;
- deviation;
- incident;
- Ride start/end.

Retention policy must be defined before production launch.

## 7. Spatial calculations

MVP should not depend on PostGIS.

Simple computations can run in application code:
- Haversine distance;
- point-to-checkpoint distance;
- approximate route deviation;
- convoy spread;
- gap heuristics.

Complex discovery such as “fuel stations along this route” remains the map provider's job.

If future analytics require serious spatial querying, the persistence layer can evolve toward PostgreSQL/PostGIS.

## 8. Route planning flow

Conceptual flow:

1. Leader searches destination.
2. Places provider resolves selected locations.
3. Routes provider returns alternatives.
4. Leader selects route.
5. Leader uses Add Stop / Search Along Route.
6. Route is recomputed.
7. Stops may become Checkpoints.
8. CommRide stores a provider-independent route plan plus enough provider metadata for refresh.
9. Ride Briefing snapshots the accepted plan.
10. During Ride, the active route may be revised with explicit revision history.

## 9. Search Along Route cost discipline

Search Along Route and similar Places queries should be user-driven and cacheable.

Rules:
- do not continuously query Places as the map moves;
- a Leader search should be shareable to the Ride rather than repeated by every Rider;
- cache appropriate results for the planning session where provider terms permit;
- impose server-side request controls;
- configure external API quotas/budgets;
- use narrow provider response field masks rather than wildcard response masks;
- cap MVP route requests at 10 intermediate stops even when the provider allows more;
- request route alternatives before intermediate stops are added, then recompute the selected route as stops change.

The 10-stop cap is both a product-complexity guard and a billing guard: current
Google Routes billing places requests with 11-25 intermediate waypoints in a
higher billing tier.

Cost-control behavior is part of architecture.

## 10. Offline/poor signal

Initial goals:
- cache Ride briefing;
- cache current route and checkpoint list;
- show last known Rider position with timestamp;
- distinguish stale from live;
- reconnect WebSocket safely;
- make quick actions idempotent where possible.

Future:
- more complete offline route package;
- provider-supported offline map strategy if product demand justifies it.

## 11. Security

Baseline requirements:
- authenticated API;
- authorization on every Club/Ride resource;
- active Ride room validates RideMembership;
- live location access is not implied by social follow;
- server controls role-sensitive actions;
- secrets remain server-side;
- map keys restricted by platform/API where possible;
- rate limits on expensive external API actions;
- SOS/incident writes audited.

## 12. Privacy

Required behaviors:
- explicit background location permission;
- visible active tracking state;
- tracking scoped to a Ride session;
- Ride end stops live tracking by default;
- stale timestamp always retained with stale location;
- location retention policy documented;
- public social content never exposes private location implicitly.

## 13. State consistency

Authoritative persistent state belongs in the database.

Durable Object holds operational realtime state for an Active Ride and should persist only what is necessary for recovery.

Important state transitions such as:
- Start Ride;
- End Ride;
- route revision;
- checkpoint release;
- SOS;

must have idempotent server-side commands.

## 14. Observability

Before public release:
- structured API errors;
- request IDs;
- external provider error logging;
- realtime connection metrics;
- Ride room health metrics;
- crash reporting for mobile;
- budget/quota alerting.

Avoid logging raw location more broadly than operationally necessary.

## 15. Deployment environments

At minimum:
- development;
- production.

A staging environment can be added once external integrations and mobile release workflows justify it.

Do not share production secrets with development.

## 16. Cost model principle

The early stack is intentionally selected so small usage can remain within no-cost tiers.

Expected early fixed infrastructure target:

> **approximately zero recurring backend cost at low usage**

Actual billing depends on then-current provider pricing and usage, so provider quotas and billing alerts are required before launch.

## 17. Evolution path

Possible future changes without changing the product model:

- D1 -> PostgreSQL/PostGIS;
- more advanced job/queue infrastructure;
- dedicated analytics pipeline;
- alternative route/place provider;
- embedded navigation;
- richer media pipeline;
- multi-region strategy.

These should be triggered by measured needs, not preemptive complexity.

## 18. Deliberate non-choices

Not recommended for MVP:
- Kubernetes;
- microservices;
- always-on VPS solely for API;
- storing every GPS point permanently;
- Firestore as a high-frequency location event log;
- embedded navigation engine;
- AI planner before deterministic planning flows work.
