-- CommRide private Ride communication.
-- 0004 is reserved by the Checkpoint coordination stack.
-- Messages are immutable low-frequency Ride records. Operational location is
-- deliberately not stored here.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_messages (
  id TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  sender_rider_id TEXT NOT NULL,
  sender_display_name TEXT NOT NULL,
  sender_ride_role TEXT NOT NULL
    CHECK (sender_ride_role IN ('leader', 'sweeper', 'navigator', 'member')),
  kind TEXT NOT NULL
    CHECK (kind IN ('chat', 'announcement')),
  body TEXT NOT NULL
    CHECK (length(trim(body)) BETWEEN 1 AND 1000),
  client_message_id TEXT NOT NULL
    CHECK (length(trim(client_message_id)) BETWEEN 1 AND 128),
  created_at TEXT NOT NULL,
  UNIQUE (ride_id, sender_rider_id, client_message_id),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_rider_id) REFERENCES riders(id) ON DELETE RESTRICT
);

CREATE INDEX idx_ride_messages_history
  ON ride_messages(ride_id, created_at DESC, id DESC);
