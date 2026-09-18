-- CommRide Checkpoint coordination.
-- Checkpoint identity stays owned by immutable route_stops. These tables store
-- only Ride operational facts: manual Rider arrival and Leader release.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_checkpoint_checkins (
  ride_id TEXT NOT NULL,
  checkpoint_stop_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  checked_in_at TEXT NOT NULL,
  method TEXT NOT NULL DEFAULT 'manual'
    CHECK (method = 'manual'),
  PRIMARY KEY (ride_id, checkpoint_stop_id, rider_id),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (checkpoint_stop_id) REFERENCES route_stops(id) ON DELETE RESTRICT,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE
);

CREATE INDEX idx_checkpoint_checkins_ride
  ON ride_checkpoint_checkins(ride_id, checkpoint_stop_id);

CREATE INDEX idx_checkpoint_checkins_rider
  ON ride_checkpoint_checkins(rider_id, ride_id);

CREATE TABLE ride_checkpoint_releases (
  ride_id TEXT NOT NULL,
  checkpoint_stop_id TEXT NOT NULL,
  released_by_rider_id TEXT NOT NULL,
  released_at TEXT NOT NULL,
  PRIMARY KEY (ride_id, checkpoint_stop_id),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (checkpoint_stop_id) REFERENCES route_stops(id) ON DELETE RESTRICT,
  FOREIGN KEY (released_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT
);

CREATE INDEX idx_checkpoint_releases_ride
  ON ride_checkpoint_releases(ride_id, released_at);
