# CommRide API

Cloudflare Worker API for the first-Club CommRide pilot.

## Scope and evidence

Repository source includes health/version, request IDs and structured errors,
Firebase identity verification, Rider/Vehicle CRUD, Club/Ride lifecycle, RoutePlan,
Briefing, Checkpoints, Active Ride WebSocket coordination, private Comms, persistent
SOS, sampled Ride Recap, FCM token lifecycle, scheduled notifications and retention.

PR #68 uses a Geoapify route/place adapter instead of Google Routes/Places. Provider
DTOs stay inside the adapter; application endpoints and persisted route coordinates
remain provider-neutral. No new D1 migration is required for this provider change.

Repository CI does not prove provider accounts, real D1/Worker deployment, live
Geoapify calls, FCM/APNs delivery or physical-device/field acceptance. Basic Firebase
and Geoapify account setup recorded by the operator is not runtime acceptance.

## Development and runtime configuration

From `services/api`, using the Node toolchain pinned in API CI:

```bash
npm ci --no-audit --no-fund
npm run typecheck
npm test
python3 scripts/validate_migrations.py
npx wrangler deploy --dry-run
```

On Windows use the installed Python command. Missing Python is not a local PASS;
CI migration validation is separate evidence. The real npm-generated lockfile is
committed; do not invent a Flutter lockfile or alter dependency script policy only
to silence an installation warning.

`npm run dev` starts Wrangler development. Never use pilot/production secrets in
an unreviewed development environment.

Required for authenticated persistence:

- `FIREBASE_PROJECT_ID`: non-secret project configuration (`commride-pilot` for pilot);
- `DB`: real D1 binding.

Additional capabilities:

- `ACTIVE_RIDE_ROOM`: Durable Object namespace;
- `GEOAPIFY_API_KEY`: backend provider secret, never a mobile define;
- `FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL` and `FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY`:
  FCM deployment secrets;
- `LOCATION_SAMPLE_RETENTION_DAYS`: bounded retention configuration.

ID-token verification alone does not require a Firebase service-account private
key. The verifier uses Firebase's published signing certificates and configured
issuer/audience. Clients supply `Authorization: Bearer <firebase-id-token>`.

Wrangler declares the SQLite-backed ActiveRideRoom export and scheduled triggers.
D1 remains unbound until a real database is created. Do not invent IDs or replace
the declarative Durable Object configuration with an unrelated deployment model.
Follow the [operator runbook](../../docs/deployment/pilot-operator-runbook.md).

## Public diagnostics

`GET /health` returns service `commride-api`, version `0.1.0`, status `ok` and
request ID. `GET /version` returns service/version/request ID. These endpoints
require no credentials and do not validate D1, Firebase or provider readiness.
They do not currently expose an exact Git SHA; record that alongside the actual
Worker deployment/version identifier rather than inferring it from `0.1.0`.
Unknown endpoints return a structured `not_found` error with request ID.

## Rider and Vehicle

`GET /v1/me` returns the authenticated Rider profile; a new Firebase account
without a CommRide profile receives `404 rider_profile_not_found`.
`PUT /v1/me` accepts profile fields such as displayName, callsign and homeArea;
authSubject is derived from the verified token, never the request body.

Rider-owned Vehicles:

- `GET /v1/me/vehicles`
- `POST /v1/me/vehicles`
- `PUT /v1/me/vehicles/:vehicleId`
- `DELETE /v1/me/vehicles/:vehicleId`

Another Rider's Vehicle returns `vehicle_not_found` for update/delete, without
revealing cross-Rider ownership. The `vehicles` table belongs to migration `0001`;
its restored API did not require a new schema migration.

## Club and Ride lifecycle

All commands require authenticated identity and a completed Rider profile.

Club endpoints:

- `GET /v1/clubs`: membership-scoped list, including invitations;
- `POST /v1/clubs`: creator becomes active owner;
- `POST /v1/clubs/:clubId/members/invite`: active owner/admin invites admin/member;
- `POST /v1/clubs/:clubId/join`: invited Rider accepts.

Ride endpoints:

- `GET /v1/clubs/:clubId/rides`: active Club membership required;
- `POST /v1/clubs/:clubId/rides`: Club owner/admin creates a Ride and becomes Leader;
- `POST /v1/rides/:rideId/members/invite`: Leader invites Member/Sweeper/Navigator;
- `POST /v1/rides/:rideId/join`: invited Rider joins;
- `POST /v1/rides/:rideId/publish`: Draft -> Published;
- `POST /v1/rides/:rideId/start`: Published -> Active;
- `POST /v1/rides/:rideId/end`: Active -> Completed;
- `POST /v1/rides/:rideId/cancel`: Draft/Published -> Cancelled only.

Lifecycle transitions are Leader-only and idempotent when repeated in the target
state. Active Rides must finish as Completed, not Cancelled. Club and Ride roles
are separate; another Club owner does not automatically become this Ride's Leader.
A Ride list can include null Ride membership for a Club member not joined to the
Ride. These endpoints are not a public social directory.

## Route and place API

Authenticated Riders with completed profiles use:

- `POST /v1/maps/autocomplete`
- `POST /v1/maps/resolve-place`
- `POST /v1/maps/routes`
- `POST /v1/maps/search-along-route`

The Geoapify adapter maps autocomplete/place details into CommRide suggestions and
resolved places. Session-token fields remain compatible but are not Google billing
sessions. References are opaque lookup values, not persisted geographic truth.

Routing maps `two_wheeler` to `motorcycle` without a car fallback, keeps ordered
waypoints and converts metric GeoJSON to precision-five encoded geometry. The
pilot cap remains 10 intermediate Stops. Alternatives are requested before Stops
only: recommended (`balanced`) and shortest (`short`) when materially different.
Duplicate/nearly identical alternatives are suppressed; failure of only the
optional alternative preserves a valid recommended route.

Unsupported motorcycle toll/highway avoidance and mixed stopover/via modes fail
explicitly. Ordinary mobile Stops are stopovers. Provider avoidance preferences
are not guarantees of road exclusion, legality or real-world safety.

### Search Along Route limits

Search is user-triggered and capped at 10 results. It samples at most six centers
spaced by route distance, queries bounded 5 km circles and deduplicates place
references. Fuel/Food/Hotel use Places categories; custom text, including Rest,
uses bounded geocoding. Candidates outside the queried area or route corridor are
excluded; the remaining candidates are ranked by geographic route proximity.

This is approximate sampled-area search, not exhaustive coverage. Long routes can
have gaps between search circles. Geographic proximity does not establish road
access, suitability or actual detour distance. `viaPlaceDistanceMeters` and
`viaPlaceDurationSeconds` remain null. Adding a candidate as a Stop recomputes the
route through the routing API.

### Failure and cost boundary

Calls have a 15-second deadline and 2 MiB response cap; no automatic paid retry.
Malformed JSON/coordinates/geometry fail explicitly. The HTTP handler awaits
provider operations so typed asynchronous failures do not become an unrelated
internal error. Raw upstream error text and key-containing URLs are never returned
to clients. Provider quota failures remain 429, provider credential failures 503,
transport failures 502 and timeouts 504.

No provider query is triggered by GPS updates or map panning. Account quotas,
provider per-second limits, concurrent-Rider load and edge abuse controls still
need operator verification; a per-request result/call cap is not a global quota
or rate-limit guarantee. See the [migration contract](../../docs/deployment/maplibre-geoapify-pilot.md).

## RoutePlan and Briefing

`GET /v1/rides/:rideId/route-plan` is for joined participants, not invited-only
Riders. `PUT /v1/rides/:rideId/route-plan` is Leader-only while Draft/Published.
It replaces the entire revision: travel mode, endpoint labels/coordinates,
selected distance/duration/polyline, ordered Stops and optional Checkpoint metadata.
Array order defines a unique zero-based Stop sequence. A D1 batch creates a new
current revision while preserving superseded immutable revisions.

Active Ride RoutePlan replacement is rejected. Dynamic replanning requires a
separate future operational command, not silent rewriting of the pre-Ride plan.

Briefing endpoints:

- `GET /v1/rides/:rideId/briefing`: joined participants read the current immutable
  Briefing, referenced RoutePlan revision, current/stale state and Ready counts;
- `POST /v1/rides/:rideId/briefing/publish`: Leader publishes while Draft/Published,
  requiring a current RoutePlan; snapshots Leader/Sweeper and optional notes;
- `POST /v1/rides/:rideId/briefing/acknowledge`: Rider acknowledges the current
  revision idempotently.

Changed plans leave old Briefings readable with `routePlanIsCurrent: false`.
Acknowledgement returns `briefing_stale` until republished. Previous
acknowledgements stay historical and do not count toward a new revision.
Readiness is advisory, not a Start Ride blocker.

## Active Ride WebSocket room

`GET /v1/rides/:rideId/live?v=1` requires WebSocket upgrade, verified identity,
completed profile, Active Ride, participating membership (not invited/left/finished)
and a real Durable Object binding. The Worker derives identity/role server-side
and forwards internal identity headers; client payloads cannot select Rider identity.

Protocol v1 carries client `presence.update` / `quick_action.raise`, and room
snapshot, presence, Quick Action, convoy-separation, Comms, SOS, Ride-end and error
events. Observations remain ordered by observedAt; an older queued observation
cannot replace a newer latest-known position.

Quick Actions derive Rider identity from the socket and optionally attach the
last server-accepted presence with original timestamps/freshness. No presence is
required; absent GPS yields null context rather than fabricated coordinates.

Hibernation/low-write policy: connected latest presence uses socket attachments,
not a D1 write for every ping. Disconnect stores only the latest operational
presence for offline/reconnect snapshots. Ride completion closes sockets and
clears offline presence. This is not permanent GPS history.

Convoy separation is computed only from connected Live positions. Compact state
is persisted only when phase, data sufficiency, component/Sweeper context or
hysteresis changes. Initial policy remains 600 m continuity, 20 s split confirmation
and 15 s recovery confirmation, pending real field validation.

End Ride is D1-authoritative; repeating the idempotent command retries room
termination when available. The room also checks authoritative Ride state during
message processing; new connections independently require Active state.

Defensive cadence ceilings reject presence bursts inside 750 ms and distinct Quick
Actions inside 2 seconds on one socket. Duplicate action IDs remain idempotently
ignored. These are not global edge/WAF controls; normal mobile cadence is slower.

## Private communication and persistent SOS

Comms endpoints:

- `GET /v1/rides/:rideId/messages`: paginated private Active/Completed history;
- `POST /v1/rides/:rideId/messages`: participant chat while Active;
- `POST /v1/rides/:rideId/announcements`: Leader-only while Active.

Bodies are trimmed, nonempty and capped at 1000 Unicode characters. A bounded
clientMessageId provides Ride + sender retry idempotency; conflicting content with
the same key returns conflict. Identity/display name/role are server-derived.
D1 persists before best-effort realtime `ride.message_created`; HTTP/history
remains authoritative. Completed communication is read-only. Messages contain no
location coordinates; operational actions remain separate typed events.

SOS endpoints:

- `GET /v1/rides/:rideId/sos`: participating Active/Completed history;
- `POST /v1/rides/:rideId/sos`: raise while Active;
- `POST /v1/rides/:rideId/sos/:sosId/cancel`: raising Rider cancels;
- `POST /v1/rides/:rideId/sos/:sosId/resolve`: Leader resolves.

A bounded clientCommandId and optional reason are accepted; identity is derived.
A best-effort room lookup may attach one trusted last-known presence snapshot.
Missing GPS or room availability never blocks SOS persistence. Realtime failure
does not roll back the incident; history recovers state. Active SOS must be
cancelled/resolved before End Ride. SOS is distinct from Butuh Bantuan and never
claims automatic contact with public emergency services.

Migrations `0005_ride_messages.sql` and `0006_ride_sos.sql` follow Checkpoint
migration `0004_checkpoint_coordination.sql`; do not invent new migration numbers
for this provider-only change.

## Push, retention and scheduled work

`POST /v1/me/push-tokens` and `DELETE /v1/me/push-tokens` derive ownership from
verified identity. FCM HTTP v1 is best-effort; stable push event keys suppress
repeated fan-out. Failure never rolls back authoritative Ride/SOS/Briefing state.

Completed history samples at most once per Rider per minute, not every live ping.
The daily maintenance pass purges completed Ride samples beyond the retention
window and old push-dedupe rows. Default retention is 30 days, allowed
`LOCATION_SAMPLE_RETENTION_DAYS=1..365`; invalid values fall back to 30. It does not
silently delete Message/SOS/Recap history.

A separate 15-minute cron considers only Published Rides with a scheduled start
in the next 60 minutes. Ride ID + exact scheduled start deduplicates reminders.
First Active -> Completed transition best-effort sends Recap available using Ride
ID + endedAt. Neither notification delivery nor failure changes Ride state.

Repository cron configuration is not proof the Worker is deployed or the jobs
have run. Verify real scheduled execution and observed provider usage after setup.

## Source of truth and release boundary

Read `../../AGENTS.md`, the technical architecture, development workflow,
[provider migration contract](../../docs/deployment/maplibre-geoapify-pilot.md),
[pilot checklist](../../docs/pilot-release-checklist.md) and
[operator runbook](../../docs/deployment/pilot-operator-runbook.md).

Repository PASS != Provider/runtime PASS != Device PASS != Field convoy PASS.
