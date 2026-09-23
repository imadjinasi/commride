-- Persistent Rider notification inboxes.
-- In-app history is independent from OS push permission and delivery.

PRAGMA foreign_keys = ON;

CREATE TABLE rider_notifications (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('account', 'club')),
  club_id TEXT,
  ride_id TEXT,
  event_key TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (length(trim(kind)) BETWEEN 1 AND 80),
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 160),
  body TEXT NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 500),
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  read_at TEXT,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE,
  FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  UNIQUE (rider_id, event_key),
  CHECK (
    (scope = 'account') OR
    (scope = 'club' AND club_id IS NOT NULL)
  )
);

CREATE INDEX idx_rider_notifications_account
  ON rider_notifications(rider_id, scope, created_at DESC);

CREATE INDEX idx_rider_notifications_club
  ON rider_notifications(rider_id, club_id, created_at DESC);

CREATE INDEX idx_rider_notifications_unread
  ON rider_notifications(rider_id, read_at, created_at DESC);
