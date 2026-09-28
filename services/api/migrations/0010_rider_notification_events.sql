-- Direct Rider notification dedupe for actionable invitations.
-- Ride-scoped notification events remain in push_notification_events.

PRAGMA foreign_keys = ON;

CREATE TABLE rider_notification_events (
  event_key TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (length(trim(kind)) BETWEEN 1 AND 80),
  created_at TEXT NOT NULL,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE
);

CREATE INDEX idx_rider_notification_events_rider
  ON rider_notification_events(rider_id, created_at DESC);
