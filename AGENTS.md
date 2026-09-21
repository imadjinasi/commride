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

CommRide has an integrated **repository-side MVP candidate for the first-Club
pilot**. Repository CI can prove source, tests, migration validation, generated
native declarations, and CI Android build gates.

Do not treat repository readiness as deployed or field-tested reality.

Do not claim:
- production or pilot infrastructure exists;
- external provider accounts are configured;
- Google Maps billing/keys exist;
- Firebase or Cloudflare projects are configured;
- a store-signed mobile build exists;
- background GPS, push delivery, or convoy behavior passed on physical devices;

unless verified by repository evidence or explicitly supplied runtime/operator
evidence.

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

The initial direction uses Google Maps Platform, but product logic should use clear provider boundaries.

Do not scatter provider-specific response types through core domain logic.

MVP should rely on external navigation apps for full turn-by-turn navigation.

Expensive API actions such as Search Along Route should be:
- deliberate/on-demand;
- rate controlled;
- not redundantly repeated per Rider when shared Ride results are sufficient.

## Realtime rules

Realtime RiderPresence and permanent LocationSample history are different concepts.

Do not persist every realtime location update by default.

Use adaptive/sampled history and define retention behavior explicitly before production release.

## Architecture constraints

Initial direction:
- Flutter mobile app;
- Cloudflare Workers;
- Cloudflare D1;
- Durable Objects for Active Ride rooms;
- R2 for object storage where needed;
- Firebase Authentication;
- FCM for push;
- Google Maps/Routes/Places behind adapters.

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
