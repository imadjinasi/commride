-- CommRide persistent Ride SOS lifecycle.
-- SOS is a low-frequency operational incident record. It is separate from
-- chat/Quick Actions and stores at most one trusted presence snapshot.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_sos (
  id TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  rider_display_name TEXT NOT NULL,
  rider_ride_role TEXT NOT NULL
    CHECK (rider_ride_role IN ('leader', 'sweeper', 'navigator', 'member')),
  state TEXT NOT NULL
    CHECK (state IN ('active', 'cancelled', 'resolved')),
  client_command_id TEXT NOT NULL
    CHECK (length(trim(client_command_id)) BETWEEN 1 AND 128),
  reason TEXT
    CHECK (reason IS NULL OR length(trim(reason)) BETWEEN 1 AND 500),
  raised_at TEXT NOT NULL,
  cancelled_at TEXT,
  resolved_at TEXT,
  resolved_by_rider_id TEXT,
  presence_latitude REAL,
  presence_longitude REAL,
  presence_observed_at TEXT,
  presence_received_at TEXT,
  presence_freshness TEXT
    CHECK (
      presence_freshness IS NULL OR
      presence_freshness IN ('live', 'stale', 'offline')
    ),
  presence_movement TEXT
    CHECK (
      presence_movement IS NULL OR
      presence_movement IN ('moving', 'stopped', 'unknown')
    ),
  UNIQUE (ride_id, rider_id, client_command_id),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  FOREIGN KEY (resolved_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  CHECK (
    (
      presence_latitude IS NULL AND
      presence_longitude IS NULL AND
      presence_observed_at IS NULL AND
      presence_received_at IS NULL AND
      presence_freshness IS NULL AND
      presence_movement IS NULL
    ) OR (
      presence_latitude IS NOT NULL AND
      presence_longitude IS NOT NULL AND
      presence_observed_at IS NOT NULL AND
      presence_received_at IS NOT NULL AND
      presence_freshness IS NOT NULL AND
      presence_movement IS NOT NULL
    )
  ),
  CHECK (
    (state = 'active' AND cancelled_at IS NULL AND resolved_at IS NULL AND resolved_by_rider_id IS NULL)
    OR
    (state = 'cancelled' AND cancelled_at IS NOT NULL AND resolved_at IS NULL AND resolved_by_rider_id IS NULL)
    OR
    (state = 'resolved' AND cancelled_at IS NULL AND resolved_at IS NOT NULL AND resolved_by_rider_id IS NOT NULL)
  )
);

CREATE INDEX idx_ride_sos_ride_state
  ON ride_sos(ride_id, state, raised_at DESC, id DESC);
