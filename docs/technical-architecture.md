# CommRide Technical Architecture v0.1

Status: Pilot architecture direction  
Date: 21 September 2026

## 1. Goals

The first architecture should:

- support Android first without blocking iOS;
- keep fixed infrastructure cost close to zero at small scale;
- scale down when no Ride is active;
- support background location;
- support realtime Ride rooms;
- avoid excessive map/route provider API usage;
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
- WebSocket clients join the Ride room;
- latest Ride presence/state kept near the room;
- outgoing updates broadcast to authorized participants;
- hibernation/scale-to-zero behavior used when inactive.

### Object storage
**Cloudflare R2**

Future use:
- avatars;
- Club images;
- Ride photos;
- incident attachments.

Do not upload large media in the first implementation unless required.

### Maps and route provider
Accepted first-pilot target:

- **MapLibre** for mobile map rendering;
- **Geoapify** map style/tile service for the mobile map;
- **Geoapify APIs** behind the CommRide server adapter for
  autocomplete/geocoding, place lookup/search, and motorcycle routing.

The integrated source still contains the earlier Google Maps implementation.
That is implementation history, not the accepted pilot target. The migration to
MapLibre + Geoapify should be a separate focused PR and must preserve the
provider abstraction.

Expected pilot capabilities:

- map rendering;
- Places-style autocomplete/search;
- motorcycle routing;
- route alternatives when materially different;
- Add Stop/waypoints;
- Nearby Search;
- Search Along Route composed server-side when necessary.

Search Along Route may be implemented by sampling a bounded route/polyline
corridor, querying Places around relevant points, deduplicating, ranking, and
returning provider-independent CommRide DTOs.

Embedded turn-by-turn navigation is not required for MVP.

The app may still deep-link to external navigation apps such as Google Maps,
Waze, or Apple Maps on iOS for turn-by-turn guidance.

## 3. Provider abstraction

Business logic should not directly depend on provider-specific APIs throughout the codebase.

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
  |-- Geoapify place/routing APIs
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

### Mobile location-session boundary

Ride domain state, OS permission state, location-provider runtime, and realtime
connection state are separate concerns.

The Flutter layer owns an explicit Ride location-session controller with states
such as inactive, permission-required, starting, active, degraded, stopping,
stopped-by-Ride-end, denied, and error.

The controller:
- starts only for an Active Ride;
- never requests location during authentication, onboarding, Club browsing, or route planning;
- requests permission only after a Rider explicitly enables Active Ride tracking;
- preserves the original observation timestamp when network delivery is delayed;
- keeps only a small bounded pending presence buffer, preferring the newest
  operational observation over replaying a long GPS trace;
- stops location and realtime publishing on local Ride end, server
  `ride.ended`, or sign-out.

Native Android/iOS platform configuration is not invented in repository-only
work. The platform projects are generated and verified with a real Flutter SDK
and real application identifiers before committing manifest, foreground-service,
Info.plist, or capability changes.

### Adaptive cadence
Exact values require field testing.

Initial controller policy:
- first valid sample after start/reconnect: send immediately;
- moving: emit at a moderate cadence rather than every GPS callback;
- stopped: slower cadence;
- weak connection: retain only bounded recent unsent state;
- critical operational actions are not blocked behind a location backlog.

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

Complex discovery such as “fuel stations along this route” remains behind the
map/place provider boundary. When the provider does not expose a single
along-route primitive, the CommRide server adapter may compose bounded corridor
queries and return normalized results.

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
- configure external API quotas/budgets.

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
- map/provider credentials restricted to the minimum trust boundary and API use where possible;
- rate limits on expensive external API actions;
- SOS/incident writes audited.

## 12. Privacy

Required behaviors:
- explicit contextual location permission;
- use the minimum platform authorization level that satisfies the accepted Ride lifecycle;
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
