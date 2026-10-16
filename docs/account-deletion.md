# Account deletion

Status: accepted product decision, 16 October 2026.

Google Play requires apps that let people create an account to also let them
delete it, both inside the app and through a web request. CommRide deletes a
Rider's personal data while keeping shared Ride history intact for the other
participants.

## Rules

| Data | Behavior |
|---|---|
| Rider profile (name, callsign, home area) | Scrubbed immediately; the Rider record becomes a tombstone named "Rider terhapus" |
| Login link (Firebase uid) | Cut immediately; the same login can never resolve to the old Rider again |
| Firebase Authentication account | Deleted by the app right after the server deletion succeeds |
| Vehicles | Deleted |
| Sampled Ride locations | Deleted |
| Push tokens | Deleted |
| Account/Club notification inbox | Deleted |
| Briefing readiness acknowledgements | Deleted |
| Club where the Rider is the only active owner and other active members exist | Deletion is blocked until ownership is transferred |
| Club where the Rider is owner and no other active member exists | Club is closed: every membership is ended, `closed_at` is set, open Rides are cancelled |
| Other Club memberships | Ended (`left`) |
| Upcoming Rides (draft/published) the Rider joined | Ride membership ended |
| Upcoming Rides (draft/published) the Rider created | Cancelled, so other Riders are not left with a Ride whose organiser is gone |
| Rider is in an Active Ride | Deletion is blocked until that Ride ends |
| Completed Ride participation, chat messages, SOS records, Briefing names | Kept for the other participants; every stored name becomes "Rider terhapus" |

The tombstone is required because shared records (Rides, RoutePlans,
Briefings, Checkpoints, messages, SOS) reference the Rider with restricting
foreign keys. Deleting the row would either fail or destroy other Riders'
history.

## Ownership transfer

An active Club owner can transfer ownership to another active member. The
previous owner becomes `admin`. Only one active owner exists at any time.

## Order of operations in the app

1. The Rider opens Profile → Hapus akun and sees what is deleted and kept.
2. The app asks the server for blockers (Clubs needing transfer, an Active
   Ride) and shows them with a way to resolve each.
3. The Rider re-enters their password (Firebase requires a recent sign-in to
   delete the login account).
4. The server deletes and scrubs data in one transaction.
5. The app deletes the Firebase account and signs out.

If step 5 fails, the login account may remain, but it is already detached from
the old Rider. Signing in again only offers a fresh profile.

## Web deletion request

Riders who no longer have the app can request deletion through the web page
linked from the privacy notice and the Play listing. The operator verifies the
request against the account email and completes it within 30 days using the
same server rules. The process is recorded in the operator runbook.

## API

- `GET /v1/me/deletion` — preview: Clubs that block deletion, Clubs that will
  be closed, and an Active Ride that blocks deletion.
- `DELETE /v1/me` — performs deletion; `409 account_deletion_blocked` with the
  same blocker details when something still blocks it.
- `GET /v1/clubs/{clubId}/members` — active members, visible to active
  members.
- `POST /v1/clubs/{clubId}/owner` — `{ "riderId": "..." }`, active owner only,
  target must be an active member.
