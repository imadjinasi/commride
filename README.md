# CommRide

> **Ride Connected.**

CommRide is a rider-first application for people who ride together. It combines group route planning, live convoy awareness, communication, checkpoints and regrouping, ride history, and a lightweight social layer for clubs.

CommRide is not designed as a surveillance tool and is not intended to replace full turn-by-turn navigation. Its core job is to help a group answer a different question:

> **How do we get there together?**

## Product promise

**Nobody rides alone.**

The promise does not mean every rider must remain in one formation. It means riders can stay connected to the group, understand where the group is, know what comes next, and surface when someone needs help.

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

### Development
- [Repository Agent Instructions](AGENTS.md)
- [AI-Assisted Development Workflow](docs/development/ai-assisted-workflow.md)

## Current direction

The planned early stack is:

- Flutter for the mobile application;
- Cloudflare Workers for the API;
- Cloudflare D1 for initial relational persistence;
- Durable Objects for Active Ride realtime rooms;
- Cloudflare R2 for object storage when needed;
- Firebase Authentication and FCM;
- Google Maps / Routes / Places through provider adapters.

The architecture intentionally targets **near-zero fixed recurring infrastructure cost at low usage** and keeps full turn-by-turn navigation outside the MVP.

## Status

CommRide is **repository-complete for the first-Club pilot candidate**.

The end-to-end MVP source now covers Account / Rider profile, Vehicle, Club,
Ride, Route Planner, Briefing / Ready, Active Ride, Live Group, Quick Actions,
Checkpoints, private Ride communication, persistent SOS, End Ride, and Ride
Recap. API and mobile repository CI have passed on the integrated source.

This status is deliberately narrower than production readiness. Real provider
configuration and physical-device evidence are still required before the first
Club pilot can be accepted, including Cloudflare deployment, Firebase/FCM,
restricted Google Maps credentials, Android/iOS signing, background location
validation, notification delivery, and a real convoy field test.

See:

- [First-Club Pilot Repository Baseline](docs/mvp-first-club-pilot-candidate.md)
- [First-Club Pilot Checklist](docs/pilot-release-checklist.md)
- [Pilot Operator Runbook](docs/deployment/pilot-operator-runbook.md)
