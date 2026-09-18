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
- a deliberately non-functional `ActiveRideRoom` placeholder;
- unit tests for the HTTP router.

Not implemented:

- production Cloudflare resources;
- authentication;
- D1 schema;
- Active Ride WebSockets;
- Google Maps/Routes/Places;
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

No secrets are required for the current scaffold.

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
