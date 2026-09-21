-- CommRide Rider push-token registry and delivery dedupe.
-- FCM/APNs credentials remain environment secrets; only opaque device tokens are
-- persisted here for authenticated Rider notification delivery.

PRAGMA foreign_keys = ON;

CREATE TABLE rider_push_tokens (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE
    CHECK (length(trim(token)) BETWEEN 1 AND 4096),
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE
);

CREATE INDEX idx_rider_push_tokens_rider
  ON rider_push_tokens(rider_id, updated_at DESC);

CREATE TABLE push_notification_events (
  event_key TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (length(trim(kind)) BETWEEN 1 AND 80),
  created_at TEXT NOT NULL,
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE
);

CREATE INDEX idx_push_notification_events_ride
  ON push_notification_events(ride_id, created_at DESC);
