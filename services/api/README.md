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

`ActiveRideRoom` exists only to make the intended boundary explicit.

It currently returns HTTP 501 and does not accept WebSockets. This avoids accidentally creating an underspecified realtime protocol before authorization, location freshness, and retention behavior are implemented together.

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

The initial API does not yet implement role transfer, route planning,
checkpoints, location, chat, or social feed behavior.


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
