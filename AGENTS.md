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
The MapLibre + Geoapify pilot is now proven for real autocomplete/place/route
requests and remains the working fallback.

A newer explicit product decision accepts the next Active Ride direction:
embedded Google turn-by-turn navigation + live convoy overlays + always-connected
group intercom, with optional PTT. Google activation remains gated by billing,
API credentials and device acceptance. Until those gates pass, do not claim the
Google path is live or replace working Geoapify runtime evidence with repository
implementation alone.

Operator evidence recorded on 21 September 2026 confirms only basic setup:

- Firebase project `commride-pilot` exists;
- Android Firebase app `CommRide` is registered for `io.github.imadjinasi.commride`;
- Firebase Email/Password authentication is enabled;
- Geoapify project `CommRide Pilot` exists.

Do not treat source implementation or provider account setup as deployed or
field-tested reality. Do not claim Cloudflare/D1 runtime deployment, installed
FlutterFire integration, live provider requests, real FCM delivery, store signing,
background GPS, or convoy acceptance without their own evidence.

Keep Repository PASS, Provider/runtime PASS, Device PASS and Field convoy PASS
separate. Issues #33, #52, #55, #58 and #59 require more than repository CI.

## MVP boundaries

The first beta targets the Ride lifecycle:

**Plan -> Ride -> Coordinate -> Regroup -> Finish -> Review**

MVP does not require:
- embedded turn-by-turn navigation;
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

MapLibre + Geoapify remains the deployed/working fallback described by
`docs/deployment/maplibre-geoapify-pilot.md`.

The accepted next Active Ride direction uses Google Places + Routes + Navigation
SDK when explicitly configured. Planning and embedded guidance should use the
same provider route family and a fresh route token where supported. Provider
selection must remain explicit; missing Google billing/credentials must degrade
to an honest unavailable/fallback state, never a fabricated pass.

- MapLibre renders the fallback Live Group map using a separately supplied Geoapify client style.
- Geoapify server APIs remain a fallback for autocomplete, place resolution/search and routing.
- Google provider credentials remain separated between server web-service keys
  and mobile SDK keys with platform/API restrictions.
- Google route tokens are short-lived transport artifacts and are not persisted
  as RoutePlan source of truth.
- Embedded Navigation SDK activation must be feature-gated until real provider
  setup and device acceptance pass.
- `two_wheeler` must use motorcycle routing, never an undisclosed car fallback.
- `GEOAPIFY_API_KEY` stays in the backend secret store, not mobile configuration.
- Client map keys are recoverable from apps; do not claim Google-style platform
  restrictions unless the chosen provider actually offers them.
- Provider-specific response types stay inside the adapter.
- Search Along Route is bounded, on-demand sampled-area search, not exhaustive
  coverage, road-access verification or a measured detour. Unavailable totals
  stay null; adding a Stop recomputes the route.
- Route alternatives must materially differ; do not fabricate Google parity.
- Maps must not request a second GPS stream or recenter automatically.
- Preserve list fallback, freshness labels and provider/data attribution.

Google Maps remains a possible future provider. Google billing and keys are not
pilot prerequisites. External navigation links remain independent of the embedded
map; full turn-by-turn guidance stays outside MVP.

Expensive provider actions must be deliberate, bounded and not automatically
repeated by every Rider for shared planning state. Account quotas and operational
abuse controls still need verification before real pilot use.

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
- MapLibre for mobile rendering;
- Geoapify place/routing adapters and client map style/tiles.

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
