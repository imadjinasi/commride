-- CommRide low-frequency journey samples for completed Ride recap.
-- The Active Ride room throttles persistence; this table must not be used as
-- a sink for every raw GPS/presence callback.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_location_samples (
  id TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  observed_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  movement TEXT NOT NULL
    CHECK (movement IN ('moving', 'stopped', 'unknown')),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE,
  UNIQUE (ride_id, rider_id, observed_at)
);

CREATE INDEX idx_ride_location_samples_ride_time
  ON ride_location_samples(ride_id, observed_at, rider_id);

CREATE INDEX idx_ride_location_samples_rider_time
  ON ride_location_samples(ride_id, rider_id, observed_at);
