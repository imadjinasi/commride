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
- authenticated Rider-owned Vehicle profile CRUD;
- provider-neutral route/place boundary;
- Google Routes + Places (New) web-service adapter;
- authenticated route/place planning endpoints;
- hibernatable Active Ride WebSocket room;
- persisted Checkpoints, private Ride Comms, persistent SOS, and Ride Recap;
- low-frequency Ride journey sampling;
- authenticated FCM device-token lifecycle and best-effort Ride notifications;
- scheduled privacy retention for sampled location history;
- realtime event cadence guards;
- unit tests and migration validation across the implemented MVP API.

Still environment/operator work:

- production Cloudflare resource identifiers and secrets;
- production Firebase/APNs configuration;
- production Google Maps Platform configuration;
- deployment and real-device verification.

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

### Rider Vehicle profile

Authenticated Rider-owned Vehicle endpoints:

- `GET /v1/me/vehicles` — list only the signed-in Rider's Vehicles;
- `POST /v1/me/vehicles` — create a Vehicle owned by the signed-in Rider;
- `PUT /v1/me/vehicles/:vehicleId` — update an owned Vehicle;
- `DELETE /v1/me/vehicles/:vehicleId` — delete an owned Vehicle.

Ownership is always derived from the authenticated Rider. Updating or deleting
another Rider's Vehicle returns `vehicle_not_found` rather than exposing
cross-Rider ownership details.

The persistence table is the existing `vehicles` table from migration `0001`; this corrective restore does not require a new migration.


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
- `ACTIVE_RIDE_ROOM` — Active Ride Durable Object namespace.

They are intentionally **not bound to invented production identifiers** in
`wrangler.jsonc`; deployment must use verified Cloudflare resource IDs.

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
- `convoy.separation_updated`
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

### Convoy separation operational state

The room evaluates the provider-independent convoy graph only from connected
Live presence.

The current derived state is included in `ride.snapshot` and meaningful
changes broadcast `convoy.separation_updated`.

To preserve hysteresis across Durable Object hibernation, the compact derived
state may be stored in Durable Object storage. The room writes it only when
phase, data sufficiency, component membership, Sweeper context, or hysteresis
timestamps change. A new GPS sample with the same meaningful separation state
does not cause another separation storage write.

This is not D1 history and does not persist every GPS calculation.

Initial field-test policy remains 600 m continuity, 20 s split confirmation,
and 15 s recovery confirmation. It is not presented as final production safety
truth.

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

## Private Ride communication

The API now defines D1-authoritative private Ride communication.

Endpoints:

- `GET /v1/rides/:rideId/messages` — paginated private history for
  participating Riders while the Ride is Active or Completed.
- `POST /v1/rides/:rideId/messages` — participant chat while the Ride is
  Active.
- `POST /v1/rides/:rideId/announcements` — Leader-only announcement while
  the Ride is Active.

Message bodies are trimmed, non-empty, and capped at 1000 Unicode characters.

Each send includes a bounded `clientMessageId`. The unique Ride + sender +
clientMessageId key makes retries idempotent. Reusing the same key for different
content returns a conflict.

The API derives sender Rider identity, display name, and Ride role from
authenticated server state. Client-supplied sender fields are ignored.

After D1 persistence succeeds, the API best-effort signals the Active Ride room,
which broadcasts `ride.message_created`. If realtime delivery is unavailable,
the persisted HTTP command still succeeds and clients recover through history.

Completed Ride communication is read-only. Draft/Published Ride chat is not part
of this initial operational slice.

Message persistence contains no location coordinates. Quick Actions,
Checkpoints, convoy separation, Ride End, and future SOS remain separate typed
operational events.

Migration `0005_ride_messages.sql` deliberately follows the Checkpoint stack's
reserved `0004_checkpoint_coordination.sql`. A branch may temporarily contain
a numbering gap while these stacked PRs remain unmerged.

## Persistent Ride SOS

SOS is a dedicated persistent incident model; it is not an ordinary Ride
message and is not the same as the lightweight **Butuh Bantuan** Quick Action.

Endpoints:

- `GET /v1/rides/:rideId/sos` — Active/Completed participating Rider history.
- `POST /v1/rides/:rideId/sos` — raise a new SOS while the Ride is Active.
- `POST /v1/rides/:rideId/sos/:sosId/cancel` — raising Rider cancels own
  Active SOS.
- `POST /v1/rides/:rideId/sos/:sosId/resolve` — Ride Leader resolves an
  Active SOS.

Raise requests include a bounded `clientCommandId` for retry idempotency and
an optional reason. Rider identity, display name, and Ride role are always
server-derived.

The API best-effort requests the Rider's latest server-accepted presence from
the Active Ride Durable Object. If available, one trusted snapshot is persisted
with coordinates, observation/receipt timestamps, movement, and
Live/Stale/Offline freshness. Missing GPS or an unavailable realtime room never
blocks SOS persistence.

After persistence, the room may broadcast:
- `ride.sos_raised`;
- `ride.sos_cancelled`;
- `ride.sos_resolved`.

Realtime failure never rolls back the authoritative D1 incident. Clients can
recover through the read endpoint.

Initial Ride-end policy is conservative: an Active SOS must be cancelled or
resolved before `POST /v1/rides/:rideId/end` can complete.

CommRide does **not** claim SOS contacts public emergency services. No such
integration is implemented by this slice.

Migration `0006_ride_sos.sql` stores one incident row and optional trusted
presence snapshot; it does not introduce permanent high-frequency location
history.

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


## Push notifications

Authenticated Riders register mobile delivery tokens through:

- `POST /v1/me/push-tokens`
- `DELETE /v1/me/push-tokens`

Only token + platform are accepted from mobile. Rider ownership is derived from
the verified Firebase identity.

FCM HTTP v1 delivery is best-effort. Notification failure never rolls back
Ride persistence or realtime state. Stable push event keys suppress duplicate
fan-out for retried authoritative commands.

Server-side FCM delivery requires deployment secrets:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL`
- `FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY`

Do not commit the private key.

## Operational location retention

Realtime RiderPresence remains operational/overwrite state. Completed Ride
history stores only low-frequency `ride_location_samples`, currently sampled
at most once per Rider per minute.

The Worker scheduled handler purges sampled location rows for completed Rides
older than the configured retention window. The default is **30 days**.

Optional configuration:

`LOCATION_SAMPLE_RETENTION_DAYS=1..365`

Unsafe/invalid values fall back to 30 days. The same maintenance pass removes
old push-delivery dedupe rows. Message/SOS/Recap records are not silently
deleted by this job.

`wrangler.jsonc` includes a daily cron schedule, but repository configuration
does not prove that a production Worker has been deployed.

## Realtime abuse guard

The Active Ride room keeps its normal low-write design while rejecting client
bursts that exceed product cadence:

- presence updates inside 750 ms of the last accepted update on the same socket
  are rejected;
- distinct Quick Actions inside 2 seconds of the last accepted Quick Action on
  the same socket are rejected;
- duplicate Quick Action event IDs remain idempotently ignored.

These guards are defensive ceilings, not a substitute for edge/WAF abuse
controls. The normal mobile location cadence is much slower (10 seconds / 25 m
starting policy).


## Scheduled Ride reminders

The Worker has a separate 15-minute cron for normal-priority Ride reminders.

Only Rides that are:

- `published`;
- have `scheduled_start_at`;
- scheduled after the current check time; and
- scheduled within the next 60 minutes

are considered.

The push event key includes Ride ID + exact scheduled-start timestamp, so
repeated 15-minute checks remain deduplicated by the existing push-event table.
Draft Rides are not reminded.

When a Ride first transitions Active -> Completed, the lifecycle handler also
best-effort sends **Ride Recap tersedia** using Ride ID + `endedAt` as the
stable dedupe key.

As with every CommRide notification, reminder/Recap delivery is non-authoritative:
failure never changes Ride status or persisted Recap availability.
