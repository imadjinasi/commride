# CommRide

> **Ride Connected.**

CommRide is a rider-first application for people who ride together. Its core is
group route planning, live convoy awareness, private communication, checkpoints,
regrouping and Ride Recap. A lightweight Club social layer is a future extension,
not an implemented public feed in the pilot.

CommRide is not a surveillance tool or a replacement for full turn-by-turn
navigation. Its core job is to help a group answer:

> **How do we get there together?**

## Product promise

**Nobody rides alone.**

Riders do not have to remain in one formation. They should be able to stay
connected, understand where the group is, know what comes next and surface when
someone needs help.

## Product loop

**Discover -> Plan -> Ride -> Coordinate -> Review -> Share -> Connect -> Ride Again**

## Product vocabulary

- **Club** — a riding community or group.
- **Ride** — one shared trip.
- **Rider** — a participant.
- **Route** — the planned path.
- **Stop** — a planned place to stop.
- **Checkpoint** — a stop with coordination meaning.
- **Regroup** — a checkpoint where the group gathers again.
- **Segment** — part of a Ride between checkpoints.
- **Leader** — Ride coordinator.
- **Sweeper** — rider responsible for the back of the group.

## Documentation

### Product
- [Product Vision](docs/product-vision.md)
- [PRD v0.1](docs/prd-v0.1.md)
- [Domain Model](docs/domain-model.md)
- [Technical Architecture](docs/technical-architecture.md)
- [Delivery Roadmap](docs/roadmap.md)

### UX
- [Information Architecture](docs/ux/information-architecture.md)
- [Core User Flows](docs/ux/core-user-flows.md)
- [Low-Fidelity Wireframe Specification](docs/ux/wireframe-spec.md)
- [Interaction Principles](docs/ux/interaction-principles.md)

### Development and pilot
- [Repository Agent Instructions](AGENTS.md)
- [AI-Assisted Development Workflow](docs/development/ai-assisted-workflow.md)
- [First-Club Pilot Repository Baseline](docs/mvp-first-club-pilot-candidate.md)
- [First-Club Pilot Checklist](docs/pilot-release-checklist.md)
- [Pilot Operator Runbook](docs/deployment/pilot-operator-runbook.md)
- [MapLibre + Geoapify migration contract](docs/deployment/maplibre-geoapify-pilot.md)

## Current direction

Flutter mobile; Cloudflare Workers API, D1 persistence and Durable Objects for
Active Ride rooms; Firebase Authentication and FCM; MapLibre map rendering with
Geoapify map styles/tiles and server-side place/routing adapters. R2 remains an
option for later object storage, not a required media feature in this pilot.

This branch implements the provider migration in PR #68. Google Maps SDK and
server-provider dependencies have been replaced; external navigation links remain
independent of that choice. Google billing is not a pilot prerequisite.

The architecture targets near-zero fixed recurring cost at low usage, not a
guarantee of permanently free operation. Check actual provider usage and quotas.

## Status

The integrated MVP baseline covers Account / Rider profile, Vehicle, Club, Ride,
Route Planner, Briefing / Ready, Active Ride, Live Group, Quick Actions,
Checkpoints, private Ride communication, persistent SOS, End Ride and Ride Recap.
PR #68 adds the MapLibre/Geoapify implementation and its repository checks;
consult the exact-head CI runs for validation, not an earlier baseline's result.

Operator evidence on 21 September 2026 records Firebase project `commride-pilot`,
Android registration `io.github.imadjinasi.commride`, Email/Password enabled and
Geoapify project `CommRide Pilot`. These do not prove native Firebase integration,
real map requests, FCM delivery or a deployed Worker.

Cloudflare/D1 deployment, actual provider verification, local Firebase integration,
signing, physical-device GPS/notification/battery tests and a real convoy test
remain separate acceptance gates. iOS identity/registration remains pending.

**Repository PASS != Provider/runtime PASS != Device PASS != Field convoy PASS.**
