-- Account deletion support.
-- Deleted Riders stay as scrubbed tombstones because shared Ride records
-- reference them; see docs/account-deletion.md.

PRAGMA foreign_keys = ON;

ALTER TABLE riders ADD COLUMN deleted_at TEXT;

ALTER TABLE clubs ADD COLUMN closed_at TEXT;
