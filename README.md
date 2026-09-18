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

CommRide is currently in **product definition / pre-implementation**.

The product baseline and UX foundation are being documented before feature code so behavior, privacy boundaries, routing interactions, Active Ride operations, and MVP scope are explicit before implementation.

The next implementation sequence is:

1. Flutter app scaffold
2. Worker/API scaffold
3. environment and CI conventions
4. authentication
5. initial D1 schema
6. Rider profile vertical slice
7. Club and Ride lifecycle
8. Route Planner
