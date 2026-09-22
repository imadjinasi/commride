# CommRide Delivery Roadmap v0.1

Status: Draft  
Date: 18 September 2026

## Principle

Build in vertical slices that can be tested in a real Ride.

Do not build the social feed, advanced gamification, and sophisticated convoy intelligence before the basic Ride lifecycle works reliably.

## Phase 0 — Product baseline

Goal: establish source of truth before code.

Deliverables:
- Product Vision;
- PRD v0.1;
- Domain Model;
- Technical Architecture;
- Roadmap;
- repository contribution/development conventions;
- initial UX flow/wireframes.

Exit criteria:
- MVP boundaries are explicit;
- location privacy model is understood;
- map-provider responsibilities are clear;
- initial mobile/backend stack is accepted.

## Phase 1 — Foundation

Goal: usable application shell and identity.

Deliverables:
- Flutter project;
- environment configuration;
- authentication;
- Rider profile;
- vehicle profile;
- Cloudflare Worker API;
- D1 migrations/schema;
- basic CI;
- error/crash reporting foundation.

Exit criteria:
- a Rider can sign in on a test build;
- authenticated API works end-to-end.

## Phase 2 — Club and Ride lifecycle

Goal: create a real group and trip.

Deliverables:
- create/join Club;
- Club member list;
- create Ride;
- invite/join Ride;
- Ride roles;
- Draft/Published/Active/Completed states.

Exit criteria:
- multiple test users can join the same Ride with roles.

## Phase 3 — Route Planner

Goal: planning experience is already useful before realtime tracking exists.

Deliverables:
- map screen;
- origin/destination search;
- route alternatives;
- Add Stop;
- reorder/remove stops;
- Nearby Search;
- Search Along Route;
- checkpoint conversion;
- route summary;
- external Navigate action;
- Ride Briefing.

Exit criteria:
- a Leader can build and publish a realistic multi-stop touring plan.

## Phase 4 — Live Ride

Goal: prove the core CommRide proposition.

Deliverables:
- background location permission flow;
- Active Ride room;
- WebSocket realtime presence;
- live Rider map;
- stale/offline state;
- next checkpoint;
- basic distance/spread;
- start/end tracking.

Exit criteria:
- a small real Ride can run with screen locked and recover from normal connectivity changes.

## Phase 5 — Coordination

Goal: reduce dependency on separate chat/location tools during the Ride.

Deliverables:
- Ride chat;
- Leader announcement;
- I'm Stopping;
- I'm Left Behind;
- Need Help;
- SOS;
- checkpoint check-in;
- Mandatory Regroup;
- push notifications.

Exit criteria:
- operational events can be communicated without free-form chat.

## Phase 6 — Ride completion and history

Goal: close the Ride lifecycle.

Deliverables:
- completed Ride record;
- basic location history sampling;
- planned vs actual summary;
- checkpoint timeline;
- Ride recap;
- Ride history.

Exit criteria:
- users receive a useful record after the Ride and tracking is clearly terminated.

## Phase 7 — Pilot hardening

Goal: production-quality small-club release.

Deliverables:
- battery profiling;
- poor-signal testing;
- permission edge cases;
- quota/rate controls;
- provider billing alerts;
- privacy/retention controls;
- account deletion/export requirements;
- abuse/reporting basics where social visibility exists;
- Play Store release preparation.

Exit criteria:
- repeatable pilot with at least one real Club;
- known cost per Active Ride;
- no unresolved critical privacy or tracking failures.

## Phase 8 — Social Clubs

Goal: make CommRide valuable between rides.

Deliverables:
- public Club profile;
- Club timeline;
- Rider -> Club follow;
- Club -> Club follow;
- Ride recap post;
- upcoming Ride post;
- basic reactions/comments if warranted;
- discovery foundations.

Exit criteria:
- real Ride activity naturally populates the social layer.

## Phase 9 — Badges and Rider progression

Goal: strengthen identity and community without unsafe incentives.

Deliverables:
- badge definitions;
- achievement engine;
- initial Rider badges;
- Club achievements;
- lightweight Rider Level;
- event badges.

Exit criteria:
- badges can be awarded deterministically from trusted Ride events;
- no achievement rewards unsafe riding metrics.

## Phase 10 — Touring Intelligence

Goal: make planning and coordination genuinely group-aware.

Candidate deliverables:
- safe fuel-range warnings;
- recommended fuel/rest stops;
- segment planning;
- ETA per Rider;
- convoy split detection;
- predicted separation;
- group-aware intercept/rejoin optimization beyond the accepted single-Rider
  rejoin-first recovery;
- Plan A/Plan B;
- delay-aware replanning;
- skip optional stop;
- split convoy groups.

Each capability should be introduced only with a measurable user problem and field-testable acceptance criteria.

## Suggested MVP release boundary

A first public beta does **not** need Phases 8–10.

Recommended beta boundary:

**Phases 1–7**

This gives CommRide a complete product story:

> Plan a Ride -> Ride together -> coordinate -> regroup -> finish -> review.

The social and intelligence layers can then grow on top of proven Ride data.
