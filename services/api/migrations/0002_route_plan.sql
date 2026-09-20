-- CommRide RoutePlan persistence.
-- Each successful save creates a new immutable revision. Exactly one revision
-- per Ride is current. Failed provider computation happens before persistence,
-- so it must not disturb the last valid current revision.

PRAGMA foreign_keys = ON;

CREATE TABLE route_plans (
  id TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  created_by_rider_id TEXT NOT NULL,
  travel_mode TEXT NOT NULL CHECK (travel_mode IN ('drive', 'two_wheeler')),
  origin_label TEXT CHECK (origin_label IS NULL OR length(origin_label) <= 240),
  origin_latitude REAL NOT NULL CHECK (origin_latitude BETWEEN -90 AND 90),
  origin_longitude REAL NOT NULL CHECK (origin_longitude BETWEEN -180 AND 180),
  destination_label TEXT CHECK (
    destination_label IS NULL OR length(destination_label) <= 240
  ),
  destination_latitude REAL NOT NULL CHECK (
    destination_latitude BETWEEN -90 AND 90
  ),
  destination_longitude REAL NOT NULL CHECK (
    destination_longitude BETWEEN -180 AND 180
  ),
  distance_meters INTEGER NOT NULL CHECK (distance_meters >= 0),
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0),
  encoded_polyline TEXT NOT NULL CHECK (length(encoded_polyline) > 0),
  is_current INTEGER NOT NULL DEFAULT 1 CHECK (is_current IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  UNIQUE (ride_id, revision)
);

CREATE UNIQUE INDEX idx_route_plans_one_current
  ON route_plans(ride_id)
  WHERE is_current = 1;

CREATE INDEX idx_route_plans_ride_revision
  ON route_plans(ride_id, revision DESC);

CREATE TABLE route_stops (
  id TEXT PRIMARY KEY,
  route_plan_id TEXT NOT NULL,
  sequence INTEGER NOT NULL CHECK (sequence >= 0),
  label TEXT NOT NULL CHECK (length(trim(label)) BETWEEN 1 AND 200),
  formatted_address TEXT CHECK (
    formatted_address IS NULL OR length(formatted_address) <= 500
  ),
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  stop_type TEXT NOT NULL DEFAULT 'generic'
    CHECK (stop_type IN ('generic', 'fuel', 'rest', 'meal', 'hotel', 'custom')),
  checkpoint_type TEXT
    CHECK (
      checkpoint_type IS NULL OR checkpoint_type IN (
        'stop',
        'fuel',
        'rest',
        'meal',
        'regroup',
        'mandatory_regroup',
        'hotel',
        'custom',
        'finish'
      )
    ),
  planned_duration_minutes INTEGER
    CHECK (
      planned_duration_minutes IS NULL OR
      planned_duration_minutes BETWEEN 0 AND 1440
    ),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (route_plan_id) REFERENCES route_plans(id) ON DELETE CASCADE,
  UNIQUE (route_plan_id, sequence)
);

CREATE INDEX idx_route_stops_plan_sequence
  ON route_stops(route_plan_id, sequence);
