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

### Maps, route and navigation providers

The working runtime remains **MapLibre + Geoapify** during migration. The
accepted low-cost target deliberately avoids making an opaque navigation SDK the
product authority:

- **MapLibre** renders planning, convoy and embedded Active Ride navigation;
- **CommRide Navigation Engine** owns route progress, current maneuver,
  off-route hysteresis, recovery/rejoin state and the deliberate reroute UX;
- **Valhalla** is the target self-hosted route engine for motorcycle RoutePlans
  and maneuver generation;
- **TomTom Traffic REST APIs** provide bounded realtime traffic flow/incidents
  such as jams, roadworks, accidents and closures where coverage/runtime evidence
  exists;
- **TomTom Search/Places REST** is an optional place provider when its API/free
  allowance and commercial terms fit the launch stage;
- **Geoapify** stays as the already-working fallback for place search,
  Search Along Route and motorcycle routing until Valhalla/TomTom replacements
  pass runtime acceptance;
- **Google** provider/Navigation preparation can remain as an optional future
  adapter, but it is no longer the pilot default or a billing prerequisite.

Provider-specific payloads must remain behind CommRide adapters. Persist the
provider-independent RoutePlan: coordinates, Stops, encoded geometry, distance,
duration and normalized maneuvers. Ephemeral provider tokens are never route
truth.

The navigation contract is intentionally different from consumer navigators that
silently reroute. A confirmed GPS deviation keeps the current RoutePlan
authoritative. CommRide first enters a recovery state and guides the Rider toward
a sensible future rejoin point. Only a deliberate user action previews a
replacement route, and a shared Active Ride replacement still requires
Leader/Navigator authority plus a persisted RoutePlan revision.

Expected pilot capabilities:
- map rendering and RiderPresence overlays;
- destination/place search;
- motorcycle routing;
- normalized turn-by-turn maneuvers;
- route alternatives when materially different;
- Add Stop/waypoints;
- Nearby/Search Along Route through bounded provider calls;
- traffic/incident annotations when TomTom runtime is configured;
- rejoin-first off-route recovery without automatic RoutePlan replacement.

Cost discipline is architectural: shared Ride traffic/search data should be
queried server-side, cached/bounded where provider terms allow, and never fetched
independently by every Rider when one shared result is enough. The Active Ride
surface refreshes advisory traffic on a bounded 10-minute cadence rather than on
GPS updates. The Worker caches the normalized exact-RoutePlan traffic result for
a short TTL so Riders following the same route share upstream calls. Traffic
refresh failures are surfaced as degraded; old incidents are not kept
indefinitely as if they were current.

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
  |-- MapLibre navigation + convoy surface
  |-- CommRide Navigation Engine (local progress/deviation/recovery)
  |-- voice media client (provider/SFU selected separately)
  |
  | HTTPS
  v
Cloudflare Worker API
  |-- D1
  |-- R2
  |-- Route adapter -> Geoapify fallback / Valhalla target
  |-- Place adapter -> Geoapify fallback / TomTom option
  |-- Traffic adapter -> TomTom when configured
  |-- Firebase notification integration
  |
  | WebSocket / Ride control channel
  v
Durable Object: Active Ride Room
  |-- latest Rider presence
  |-- Ride operational state
  |-- voice signalling/control metadata where needed
  |-- broadcast events
  `-- checkpoint / quick-action realtime events
```

Map rendering and route-progress calculations do not require a provider request
for every GPS sample. The mobile engine consumes the accepted RoutePlan locally.
External APIs are used deliberately for planning, traffic refresh, search or a
user-requested replacement route.

Voice audio packets do not flow through the Durable Object. Group intercom needs
a media plane suited to realtime audio (for example WebRTC with an SFU).

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

## 8. Route planning and embedded navigation flow

The persisted RoutePlan is the shared authority. Planning-provider output is
normalized before persistence, including route geometry and maneuvers when
available.

Conceptual flow:

1. Leader searches destination through the configured place adapter.
2. Route adapter returns motorcycle-capable alternatives.
3. Leader selects a route and uses Add Stop / Search Along Route.
4. CommRide stores a provider-independent immutable RoutePlan revision.
5. Ride Briefing snapshots that exact revision.
6. Active Ride loads the accepted geometry/maneuvers into MapLibre + CommRide
   Navigation Engine.
7. The existing Ride location session supplies GPS samples; navigation does not
   start a second hidden location stream.
8. RiderPresence and traffic/incidents are overlaid on the same operational map.
9. Local progress selects the next maneuver and estimates remaining progress
   without continuously recomputing the route upstream.
10. GPS noise first enters a suspected-deviation state. Only sustained,
    meaningful deviation becomes confirmed off-route.
11. Confirmed off-route keeps the accepted RoutePlan visible and enters
    **Recovery**. CommRide seeks a sensible future rejoin point rather than
    silently replacing the route.
12. Recovery may request a temporary provider-computed road path from the
    Rider's current position to that future rejoin point. It is never persisted,
    is rate-bounded by time/movement, and disappears once the Rider rejoins.
    Provider failure keeps only honest RoutePlan/rejoin information; it must not
    fabricate a straight line as a drivable road.
13. The Rider may deliberately choose **Cari rute baru**. A candidate is
    previewed before adoption.
14. A shared route change is persisted only by Leader/Navigator as a new
    RoutePlan revision, then broadcast to connected Riders.

A provider outage must not be presented as a successful route replacement.
Repository implementation is not evidence that Valhalla or TomTom runtime is
available.

## 9. Search Along Route cost discipline

Search Along Route and similar Places queries should be user-driven and cacheable.

Rules:
- do not continuously query Places as the map moves;
- a Leader search should be shareable to the Ride rather than repeated by every Rider;
- cache appropriate results for the planning session where provider terms permit;
- impose server-side request controls;
- configure external API quotas/budgets.

Cost-control behavior is part of architecture.

## 9.5 Active Ride voice intercom

The default voice experience is an always-connected group intercom, closer to a
group call than a walkie-talkie. Push to Talk remains optional.

Control-state model:
- group-intercom, PTT and listen-only modes;
- explicit local mic on/off;
- per-Rider local mute;
- Leader moderator-mute, without remote unmute;
- active-speaker state for UI;
- Leader broadcast priority;
- SOS priority voice alert.

Audio priority target:
**SOS > Leader broadcast > Navigation prompt > Group voice > Music**.

Media controls must preserve ordinary headset/TWS play/pause behavior. CommRide
may bind a distinct hardware input when the accessory/OS exposes one, but it
must not redefine standard media play/pause as Mic Toggle or PTT by default.

The Durable Object remains the authoritative Ride control/presence channel. It
is not an audio relay. Provider/SFU selection, codec policy, echo/noise
suppression, Bluetooth routing and background-audio behavior require separate
implementation and actual-device acceptance.

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
- richer offline navigation/data packages;
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
- building a new map/routing dataset or routing graph from scratch;
- turning the local CommRide Navigation Engine into an unbounded provider clone;
- AI planner before deterministic planning flows work.
