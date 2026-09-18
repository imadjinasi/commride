# AI-Assisted Development Workflow

Status: Initial  
Date: 18 September 2026

## 1. Purpose

CommRide will likely be developed iteratively with AI-assisted coding. This workflow keeps changes reviewable and prevents implementation from becoming the de facto product specification.

## 2. Before implementation

For every meaningful feature:

1. read `AGENTS.md`;
2. identify the relevant PRD/domain/UX sections;
3. confirm whether requested behavior is already specified;
4. if behavior is new or materially different, update documentation first or in the same PR;
5. define acceptance criteria;
6. only then implement.

## 3. Branch strategy

Use short-lived scoped branches.

Examples:
- `feat/auth-foundation`
- `feat/ride-lifecycle`
- `feat/route-planner`
- `docs/ux-foundation`
- `fix/location-stale-state`

Avoid unrelated product changes in one branch.

## 4. Pull requests

Each PR should explain:

### Why
What user/product problem is being addressed?

### Scope
What behavior/files are included?

### Out of scope
What deliberately remains for later?

### Acceptance
How can a reviewer verify success?

### Evidence
- tests;
- screenshots where applicable;
- logs;
- relevant provider docs;
- known limitations.

### Product/document impact
List documents changed or state why none are required.

## 5. Requirement traceability

Until a formal specification ID system is introduced, PR descriptions should link directly to the relevant documentation section.

When the backlog becomes large enough to justify IDs, introduce them centrally rather than inventing incompatible schemes per feature.

## 6. Tests

Behavior-changing implementation should include appropriate automated tests where practical.

Priority:
1. domain/business state transitions;
2. authorization/privacy boundaries;
3. Ride lifecycle;
4. location freshness semantics;
5. route planner transformations;
6. realtime event handling;
7. UI interaction tests for critical flows.

External map/provider calls should be wrapped so tests can use deterministic fakes/mocks.

## 7. High-risk areas

Changes involving the following deserve extra review and explicit test evidence:

- background location;
- Ride membership authorization;
- live location visibility;
- SOS;
- Start/End Ride idempotency;
- route replacement during Active Ride;
- account deletion/privacy;
- paid external APIs;
- notification fan-out.

## 8. External provider assumptions

Never infer provider runtime configuration from code alone.

Repository implementation can prove:
- adapter exists;
- environment variable is expected;
- request shape is tested.

It cannot prove:
- production API key is valid;
- billing is enabled;
- quota is sufficient;
- provider dashboard is configured.

Keep these statements separate.

## 9. Cost discipline

CommRide targets near-zero fixed cost at low usage.

When adding infrastructure or API calls, describe:
- whether cost is fixed or usage-based;
- what triggers billing;
- whether calls can be shared/cached;
- expected high-frequency behavior;
- quota/budget controls.

High-frequency location events must not blindly become high-frequency paid database/API writes.

## 10. Data model changes

Database changes should use migrations once implementation begins.

Do not edit production data assumptions into application code.

Every persistent entity should have:
- ownership/authorization model;
- lifecycle;
- deletion/retention behavior where relevant.

## 11. Realtime events

Realtime events should have explicit types and versionable payloads.

Examples:
- RiderPresenceUpdated
- QuickActionRaised
- CheckpointArrivalUpdated
- RegroupReleased
- RideEnded

Avoid using chat messages as an implicit transport for operational state.

## 12. Error handling

Prefer explicit degraded states.

Examples:
- route search failed -> retain prior route;
- realtime disconnected -> show stale/offline;
- Places failed -> keep current itinerary;
- push failed -> in-app state remains authoritative.

Never fabricate successful provider or network state.

## 13. Mobile permissions

Permission requests must be contextual.

Tests and product review should include:
- denied;
- denied permanently;
- foreground only;
- background granted;
- platform-specific interruption;
- permission revoked while Ride is active.

## 14. Definition of done

A feature is not done merely because code exists.

For product behavior, done means:
- implementation matches documented behavior;
- relevant tests pass;
- critical failure states are handled;
- privacy/security impact is addressed;
- user-facing copy is coherent;
- documentation is updated;
- reviewer can reproduce the acceptance evidence.

## 15. Current next implementation sequence

After UX baseline:

1. Flutter application scaffold
2. Worker/API scaffold
3. environment conventions
4. Firebase auth adapter
5. D1 schema/migrations
6. Rider profile vertical slice
7. basic CI
8. Club/Ride lifecycle

Do not start Touring Intelligence or full social feed before the core Ride lifecycle is working.
