# AGENTS.md

## Scope

These instructions apply to the entire CommRide repository.

## Product identity

CommRide is a rider-first group riding coordination product.

Core promise:
- **Ride Connected.**
- **Nobody rides alone.**

The application is not a fleet surveillance product, racing product, or generic social network.

## Source-of-truth order

When implementation details conflict, resolve them in this order unless a newer explicit decision supersedes an older one:

1. Accepted product/domain decisions
2. `docs/prd-v0.1.md`
3. `docs/domain-model.md`
4. `docs/technical-architecture.md`
5. `docs/ux/`
6. tests / acceptance criteria
7. implementation

Brand/product principles in `docs/product-vision.md` remain constraints across all layers.

If a requested implementation introduces behavior not covered by the current product/domain documents, document the behavior before or together with implementation.

## Current project stage

CommRide has an integrated repository-side MVP candidate for the first-Club pilot.
MapLibre + Geoapify has already handled real autocomplete/place/route requests and
remains the working fallback while the low-cost navigation stack is introduced.

The newest explicit product decision (22 September 2026) makes the primary
navigation direction provider-neutral and cost-controlled:

- MapLibre owns the embedded map/navigation surface;
- CommRide Navigation Engine owns route progress, maneuver state, deviation
  detection and recovery UX;
- Valhalla is the target self-hosted motorcycle RoutePlan engine;
- TomTom REST APIs are the target external traffic/incident intelligence and may
  be used for place search where their commercial terms remain suitable;
- Geoapify remains the proven transition/fallback path until replacement runtime
  evidence exists;
- Google Places/Routes/Navigation preparation may remain as an optional future
  adapter, but Google billing is not a pilot prerequisite or the default path.

A second accepted behavior is **rejoin-first navigation**. Leaving the planned
route must not silently replace the authoritative RoutePlan. CommRide first
helps the Rider recover to a sensible future point on the current route. A new
route is only adopted after an explicit user decision, and a shared Active Ride
RoutePlan still requires Leader/Navigator authority and a persisted revision.

Operator evidence recorded on 21 September 2026 confirms only basic setup:

- Firebase project `commride-pilot` exists;
- Android Firebase app `CommRide` is registered for `io.github.imadjinasi.commride`;
- Firebase Email/Password authentication is enabled;
- Geoapify project `CommRide Pilot` exists.

Do not treat source implementation or provider account setup as deployed or
field-tested reality. Valhalla, TomTom traffic/search, CommRide embedded
navigation and voice media each require their own runtime/device evidence before
being described as live.

Keep Repository PASS, Provider/runtime PASS, Device PASS and Field convoy PASS
separate. Issues #33, #52, #55, #58 and #59 require more than repository CI.

## MVP boundaries

The first beta targets the Ride lifecycle:

**Plan -> Ride -> Coordinate -> Regroup -> Finish -> Review**

MVP does not require:
- a production voice-media/SFU provider before its dedicated acceptance gate;
- microservices;
- Kubernetes;
- competitive speed ranking;
- sophisticated AI route planning;
- advanced social influencer features;
- permanent storage of every GPS ping.

## Safety and privacy constraints

### Location
Location is sensitive operational data.

Implementation must preserve:
- explicit permission;
- clear active tracking state;
- Ride-scoped live visibility;
- stale/offline distinction;
- tracking termination when Ride ends by default;
- separation between social follow and location access.

Never present stale location as live.

### Riding safety
Do not introduce gamification that rewards:
- top speed;
- speeding;
- shortest travel time;
- longest continuous riding without rest.

Active Ride UI should minimize interaction load.

### SOS
Do not state or imply that SOS contacts public emergency services unless such integration is actually implemented and verified.

## Map/provider rules

MapLibre + Geoapify remains the proven fallback described by
`docs/deployment/maplibre-geoapify-pilot.md`. Do not remove or disable it until
a replacement has its own runtime evidence.

The accepted low-cost navigation target is MapLibre + CommRide Navigation Engine
with Valhalla for motorcycle routing and TomTom REST traffic/incident
intelligence. Provider selection stays explicit and adapters must normalize
provider payloads before they reach product/domain code.

- MapLibre renders maps and the Active Ride navigation surface.
- Valhalla is the target RoutePlan engine and must be self-hosted/verified before
  it replaces the current Geoapify route runtime.
- Geoapify remains a supported fallback for autocomplete, place resolution,
  Search Along Route and motorcycle routing during the transition.
- TomTom credentials are server-side only. Traffic/incident calls must be
  bounded, cached/shared per Ride where practical, and must not be repeated by
  every Rider independently.
- Google adapters may remain optional but must stay disabled unless their own
  billing, credential and device gates pass.
- `two_wheeler` must use a motorcycle-capable route engine, never an
  undisclosed car fallback.
- Provider-specific response types stay inside adapters.
- Search Along Route is bounded, on-demand sampled-area search, not exhaustive
  coverage, road-access verification or a fabricated detour. Unavailable totals
  stay null; adding a Stop recomputes the route.
- Route alternatives must materially differ; do not fabricate provider parity.
- Live Group maps must not request a second GPS stream.
- Active Ride navigation may follow the existing Ride location session; it must
  not create a hidden parallel tracking session.
- Preserve list fallback, freshness labels and provider/data attribution.

**Route deviation rule:** GPS deviation never authorizes an automatic shared
RoutePlan replacement. Use hysteresis so one noisy sample is not enough. After
confirmed deviation, keep the accepted route visible/authoritative, calculate
or present recovery toward a sensible future rejoin point, and expose a
deliberate “Cari rute baru” action. Only an explicitly accepted replacement may
become a new RoutePlan revision.

Expensive provider actions must be deliberate, bounded and not automatically
repeated by every Rider for shared planning state. Account quotas, provider
terms and operational abuse controls require verification before real pilot use.

## Realtime rules

Realtime RiderPresence and permanent LocationSample history are different concepts.

Do not persist every realtime location update by default.

Use adaptive/sampled history and define retention behavior explicitly before production release.

## Architecture constraints

Pilot direction:
- Flutter mobile app;
- Cloudflare Workers;
- Cloudflare D1;
- Durable Objects for Active Ride rooms;
- R2 for object storage where needed;
- Firebase Authentication;
- FCM for push;
- MapLibre as the embedded map/navigation renderer;
- CommRide Navigation Engine for progress, maneuver and rejoin-first deviation behavior;
- Valhalla as the target self-hosted motorcycle routing engine;
- TomTom REST traffic/incident intelligence, with place search available through a provider adapter;
- Geoapify as the proven transition/fallback map/place/route path;
- Google adapters only as optional future feature-gated integrations;
- WebRTC/SFU-class media architecture for voice, with provider selection handled
  separately from the Ride control channel.

Avoid premature infrastructure expansion without an evidenced product or scale need.

## UX constraints

Route planning should feel familiar:
- destination search;
- route alternatives;
- Add Stop;
- reorder;
- Search Along Route;
- Nearby Search;
- ETA recalculation.

Differentiation belongs in group coordination.

During Active Ride, operational information takes priority over social content.

See `docs/ux/`.

## Development workflow

Follow `docs/development/ai-assisted-workflow.md`.

Prefer:
- small scoped branches;
- reviewable PRs;
- explicit acceptance criteria;
- tests for behavior changes;
- documentation updates when behavior changes.

Do not merge a PR unless the user explicitly asks for a merge.
Do not commit provider files, API keys, service-account JSON, signing credentials,
or local `pilot-defines.local.json`. Do not hand-author dependency lockfiles.

## Documentation language

Repository documentation may use English for technical consistency.

User-facing Indonesian copy should remain natural and concise.

Product nouns may intentionally retain:
- Ride
- Rider
- Club
- Route
- Checkpoint
- Leader
- Sweeper.
