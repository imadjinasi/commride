# D1 Migrations

This directory contains ordered Cloudflare D1 / SQLite migrations for CommRide.

## Initial scope

`0001_core_identity_club_ride.sql` implements only the first persistent domain slice:

- Rider
- Vehicle
- Club
- ClubMembership
- Ride
- RideMembership

It deliberately does **not** add:

- realtime RiderPresence;
- high-frequency GPS event storage;
- LocationSample history;
- route plans/checkpoints;
- posts/follows;
- badges/achievements.

Those areas require their own retention, privacy, and lifecycle decisions.

## Role separation

Club roles:

- owner
- admin
- member

Ride roles:

- leader
- sweeper
- navigator
- member

They are separate columns in separate membership tables by design.

## Lifecycle constraints

The migration enforces several inexpensive invariants at the database boundary:

- one active Club owner;
- one current Ride leader;
- membership states use explicit enums;
- Active/Completed Rides require an actual start timestamp;
- Completed Rides require an end timestamp;
- selected Ride Vehicle references a Vehicle entity.

Application services still own state-transition authorization and idempotency.

## IDs

Primary keys are opaque application-generated TEXT IDs.

The initial migration intentionally does not lock the project to a database-specific ID generator. The API layer will define the concrete ID format when the first write service is implemented.

## Local validation

Once Wrangler/D1 is available:

```bash
cd services/api
npx wrangler d1 migrations apply <database-binding-or-name> --local
```

Do not use a production database for migration experimentation.

Plain SQLite can also be used for syntax/invariant smoke testing because D1 is SQLite-based, but D1 should remain the release target.

## Production

No production D1 resource is created or configured by this migration.

When a real database exists:

1. configure the verified D1 binding in `wrangler.jsonc`;
2. apply migrations in a controlled environment;
3. record deployment evidence;
4. never invent or commit a fake production database ID.
