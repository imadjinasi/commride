-- Ride voice intercom room mapping.
-- One provider room per Ride, created on the first intercom join. Holds no
-- audio, no Rider data and no provider credentials; see
-- docs/voice-intercom-decision-2026-10-16.md.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_intercom_rooms (
  ride_id TEXT PRIMARY KEY NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('cloudflare_realtimekit')),
  provider_room_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE
);
