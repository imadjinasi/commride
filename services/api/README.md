# CommRide API

Cloudflare Worker API scaffold for CommRide.

## Current scope

Implemented:

- module Worker entry point;
- `GET /health`;
- `GET /version`;
- request IDs;
- structured JSON errors;
- optional typed D1/Durable Object bindings;
- Firebase ID-token verification boundary;
- authenticated `GET /v1/me` and `PUT /v1/me`;
- D1 Rider profile repository;
- provider-neutral route/place boundary;
- Google Routes + Places (New) web-service adapter;
- authenticated route/place planning endpoints;
- a deliberately non-functional `ActiveRideRoom` placeholder;
- unit tests for the HTTP router, Rider profile, and map-provider behavior.

Not implemented:

- production Cloudflare resources;
- production Firebase configuration;
- Active Ride WebSockets;
- production Google Maps Platform configuration;
- notifications;
- deployment.

## Local development

Prerequisites:

- Node.js compatible with current Wrangler/Vitest
- npm

From `services/api`:

```bash
npm install
npm run typecheck
npm test
npm run dev
```

The public health/version endpoints require no secrets.

The Rider profile endpoints require verified runtime bindings:

- `FIREBASE_PROJECT_ID`
- `DB` (D1)

The route/place endpoints additionally require:

- `GOOGLE_MAPS_PLATFORM_API_KEY` — server-side secret/configuration only.

The repository does not contain a production key. CI uses fake providers and
mocked HTTP calls.

The Firebase project ID is configuration, not a private credential. No Firebase
service-account private key is required solely for ID-token verification.

## Endpoints

### GET /health

Example response:

```json
{
  "status": "ok",
  "service": "commride-api",
  "version": "0.1.0",
  "requestId": "..."
}
```

### GET /version

Returns the service name/version and request ID.

Unknown endpoints return a structured error:

```json
{
  "error": {
    "code": "not_found",
    "message": "The requested API endpoint does not exist.",
    "requestId": "..."
  }
}
```

## Bindings

`Env` reserves optional bindings:

- `DB` — future Cloudflare D1 database;
- `ACTIVE_RIDE_ROOM` — future Durable Object namespace.

They are intentionally **not configured** in `wrangler.jsonc` yet because no real Cloudflare resources have been verified or created.

When infrastructure is provisioned, use real resource identifiers and add the required Durable Object migration. Never commit provider secrets.

## Active Ride room

The repository now contains the first versioned Active Ride realtime protocol
and a hibernatable Cloudflare Durable Object room implementation.

### Public connection endpoint

`GET /v1/rides/:rideId/live?v=1`

Requires:
- WebSocket upgrade;
- verified Firebase identity;
- completed Rider profile;
- Ride state = `active`;
- participating RideMembership (not invited/left/finished);
- configured `ACTIVE_RIDE_ROOM` Durable Object binding.

The Worker derives Rider identity and role from verified server-side state,
then forwards the original WebSocket upgrade request to the room with internal
identity headers. Client events cannot select another Rider ID.

### Protocol v1

Client -> room:
- `presence.update`
- `quick_action.raise`

Room -> client:
- `ride.snapshot`
- `presence.updated`
- `quick_action.raised`
- `ride.ended`
- `error`

Presence observations are ordered by `observedAt`. An older queued
observation cannot replace a newer latest-known position.

`quick_action.raised` is built from the authenticated socket attachment. The
room derives Rider identity/role server-side and, when available, includes the
latest server-accepted RiderPresence as optional context. That context preserves
its timestamps and current Live/Stale/Offline freshness. When no accepted
presence exists, the action still broadcasts with `presence: null`; quick
actions do not require GPS availability.

### Cost and retention behavior

CommRide uses the Durable Object WebSocket Hibernation API.

While a Rider socket is connected, latest presence is carried in the
WebSocket attachment so each GPS update does not create a D1 write or an
append-only Durable Object location record.

When a Rider disconnects, only that Rider's latest operational presence is
stored so reconnecting Riders can receive a last-known/offline snapshot. This
is overwritten operational state, not permanent location history.

Ride completion broadcasts `ride.ended`, closes room sockets, and clears the
stored offline presence entries. Any long-term LocationSample/history feature
must use a separate sampled retention policy.

### Ride lifecycle integration

`POST /v1/rides/:rideId/end` remains D1-authoritative. After the Ride becomes
Completed, the API signals the Active Ride room to terminate. Repeating the
idempotent End Ride command retries room termination when a room binding is
available.

The room also periodically checks authoritative Ride status while processing
messages. New realtime connections are independently rejected by the Worker
unless the Ride is Active.

The repository still does **not** claim a production Durable Object binding is
provisioned. `wrangler.jsonc` intentionally contains no invented production
resource configuration.

## Source of truth

- `../../AGENTS.md`
- `../../docs/technical-architecture.md`
- `../../docs/development/ai-assisted-workflow.md`


## Authentication

Authenticated clients send a Firebase ID token using:

```
Authorization: Bearer <firebase-id-token>
```

The Worker validates the token against Firebase's published signing
certificates and the configured project audience/issuer.

### GET /v1/me

Returns the Rider profile for the authenticated Firebase subject.

A signed-in Firebase account that has not completed CommRide profile onboarding
receives `404 rider_profile_not_found`.

### PUT /v1/me

Creates or updates only the authenticated Rider's own profile.

Example body:

```json
{
  "displayName": "Imad",
  "callsign": "Sweep",
  "homeArea": "Cirebon"
}
```

The client does not supply `authSubject`; it is derived from the verified
Firebase token.

Repository code does not prove that a production Firebase project, D1 database,
or Cloudflare bindings exist. Those remain deployment configuration.


## Club and Ride lifecycle

The initial lifecycle API is intentionally command-oriented rather than open
CRUD.

All endpoints below require an authenticated Rider with a completed CommRide
Rider profile.

### Club

- `GET /v1/clubs` — list Clubs where the authenticated Rider has an invited or active membership.
- `POST /v1/clubs` — create a Club; creator becomes active `owner`.
- `POST /v1/clubs/:clubId/members/invite` — active owner/admin invites a Rider as `admin` or `member`.
- `POST /v1/clubs/:clubId/join` — authenticated invited Rider accepts the invitation.

### Ride

- `GET /v1/clubs/:clubId/rides` — list Club Rides for an active Club member, including the authenticated Rider's Ride membership when one exists.
- `POST /v1/clubs/:clubId/rides` — active Club owner/admin creates a Ride and becomes its `leader`.
- `POST /v1/rides/:rideId/members/invite` — Ride Leader invites a Rider as `member`, `sweeper`, or `navigator`.
- `POST /v1/rides/:rideId/join` — authenticated invited Rider joins.
- `POST /v1/rides/:rideId/publish` — `draft -> published`.
- `POST /v1/rides/:rideId/start` — `published -> active`.
- `POST /v1/rides/:rideId/end` — `active -> completed`.
- `POST /v1/rides/:rideId/cancel` — Leader-only `draft|published -> cancelled`; repeating cancellation is idempotent.

Publishing, starting, ending, and cancelling a Ride are Leader-only commands.
Repeating a successful transition command after the Ride is already in that
target state is idempotent.

Cancellation is intentionally limited to Draft or Published Rides. Once a Ride
is Active it must be ended as Completed instead of cancelled so the operational
record reflects that the Ride actually started.

Club roles and Ride roles are separate. A Club admin who creates a Ride becomes
Leader of that Ride; a different Club owner does not automatically gain Leader
authority over it.

The initial API does not yet implement role transfer, Active Ride route
revision, checkpoint check-in/release, location, chat, or social feed behavior.


### Read-model privacy

The Club list is membership-scoped; it is not a public Club directory.

The Ride list requires an active Club membership. It may return a null Ride
membership when the Rider belongs to the Club but has not joined that Ride.
These read endpoints are intended to support the authenticated mobile shell,
not public social discovery.


## Route and place API

All endpoints require an authenticated Rider with a completed Rider profile.

- `POST /v1/maps/autocomplete`
- `POST /v1/maps/resolve-place`
- `POST /v1/maps/routes`
- `POST /v1/maps/search-along-route`

The API returns CommRide DTOs rather than raw Google payloads.

### Route request guards

The MVP accepts at most 10 intermediate stops per route request. Current Google
Routes documentation allows more, but 11-25 intermediate waypoints are billed
at a higher tier, so CommRide deliberately stays below that boundary.

Alternative routes are requested only before intermediate stops are present.
After Add Stop, the selected route is recomputed rather than pretending that
the provider can return the same alternatives behavior with intermediates.

### Search Along Route

Search Along Route is on-demand and capped at 10 results per request. The
adapter requests routing summaries so CommRide can compare the total route via
a candidate place when Google returns both route legs.

Current provider limitation: Google Places Search Along Route does not support
`TWO_WHEELER`. CommRide returns
`search_along_route_mode_not_supported` rather than silently substituting
DRIVE results for motorcycle routing.

### Provider cost discipline

- no wildcard field masks in production adapter calls;
- no continuous Places query while panning a map;
- no web-service API key in the mobile app;
- no repeated per-Rider provider query for shared Ride planning state;
- quotas and billing alerts remain deployment prerequisites.


## RoutePlan persistence

A Ride can persist one current RoutePlan while retaining superseded immutable
revisions.

### GET /v1/rides/:rideId/route-plan

Returns the current RoutePlan to a Rider who has already joined the Ride.
Invited-only Riders cannot read the plan through this endpoint.

### PUT /v1/rides/:rideId/route-plan

Leader-only full-revision replacement while the Ride is Draft or Published.

The request contains:
- travel mode;
- origin and destination labels/coordinates;
- selected route distance/duration/polyline;
- ordered intermediate Stops;
- optional Checkpoint type and planned duration per Stop.

Stop order is derived from array order and persisted as a unique zero-based
sequence. The API accepts at most 10 intermediate Stops, matching the route
provider cost guard.

A successful PUT creates a new revision and makes it current. The prior
revision becomes superseded but is retained. The persistence operation uses one
D1 batch so the previous current plan is not intentionally left deactivated
with only a partial new plan.

The initial MVP rejects RoutePlan replacement once a Ride is Active. Dynamic
Active Ride replanning requires a later explicit operational command rather
than silently rewriting the pre-Ride plan.


## Checkpoint coordination

Checkpoint coordination is persisted operational Ride state tied to the current
immutable RoutePlan revision.

Endpoints:

- `GET /v1/rides/:rideId/checkpoints`
- `POST /v1/rides/:rideId/checkpoints/:checkpointId/check-in`
- `POST /v1/rides/:rideId/checkpoints/:checkpointId/release`

### Read model

A participating Rider may read Checkpoint state while the Ride is Active or
Completed.

The response includes:

- exact RoutePlan ID and revision;
- ordered Checkpoints only (ordinary Stops are excluded);
- current / upcoming / released state;
- expected, checked-in, and missing Rider counts;
- whether the authenticated Rider has checked in;
- release timestamp;
- compact participant/check-in state.

The current Checkpoint is the first unreleased Checkpoint in route order.

### Manual Rider check-in

Check-in is available only while the Ride is Active.

Identity is derived from authentication. A Rider cannot check in another Rider.

Check-in is idempotent for:

`Ride + RoutePlan revision + Checkpoint + Rider`

The server records the receipt timestamp and `method: manual`.

Manual check-in is a Rider claim of arrival. It is **not** labeled or treated as
GPS verification, and this slice does not request or persist device location.

Late check-in to a released Checkpoint remains historical and does not reopen
the Checkpoint.

### Leader release

Only the Ride Leader may release a Checkpoint while the Ride is Active.

Release is idempotent. Earlier Checkpoints must be released first, so
operational sequence cannot regress.

Release is allowed even when Riders are still missing. The updated read model
keeps the missing count explicit so mobile can require an appropriate
confirmation before sending the command.

The persisted API is authoritative. Realtime Checkpoint broadcasts are not
required by this slice; reconnect can reconstruct current state from this API.

No additional Cloudflare service/resource is introduced. These records use the
existing D1 database.

## Ride Briefing and readiness

Ride Briefing is an immutable published snapshot tied to one exact RoutePlan
revision.

### GET /v1/rides/:rideId/briefing

Returns the current published Briefing to a joined Ride participant.

The response includes:

- the immutable Briefing revision;
- the RoutePlan revision referenced by that Briefing;
- whether that RoutePlan is still the Ride's current plan;
- expected/ready Rider counts;
- whether the authenticated Rider acknowledged this exact revision.

Invited-only Riders cannot read the private Briefing.

### POST /v1/rides/:rideId/briefing/publish

Leader-only. Allowed while the Ride is Draft or Published.

A current valid RoutePlan is required. Publishing creates a new immutable
Briefing revision, snapshots the current Leader/Sweeper identity, and makes the
new revision current.

Optional body:

```json
{
  "notes": "Meet at 05:30. Fuel before departure."
}
```

If the RoutePlan changes later, the previously published Briefing remains
readable but is marked stale through `routePlanIsCurrent: false`.

### POST /v1/rides/:rideId/briefing/acknowledge

A joined Rider acknowledges the current Briefing revision for themselves.

Acknowledgement is idempotent for one Rider + Briefing revision.

If the current RoutePlan changed after the Briefing was published,
acknowledgement is rejected with `briefing_stale` until the Leader publishes a
new Briefing revision.

Acknowledgements for older Briefing revisions remain historical but do not
count toward readiness for a newer revision.

Readiness is advisory in the MVP. It is not a server-side Start Ride blocker.
