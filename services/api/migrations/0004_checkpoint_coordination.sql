-- CommRide Active Ride Checkpoint coordination.
-- Manual Rider check-ins and explicit Leader releases are persisted against
-- one immutable RoutePlan revision. This is operational coordination state,
-- not GPS verification.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_checkpoint_checkins (
  ride_id TEXT NOT NULL,
  route_plan_id TEXT NOT NULL,
  checkpoint_stop_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  checked_in_at TEXT NOT NULL,
  method TEXT NOT NULL DEFAULT 'manual'
    CHECK (method = 'manual'),
  PRIMARY KEY (
    ride_id,
    route_plan_id,
    checkpoint_stop_id,
    rider_id
  ),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (route_plan_id) REFERENCES route_plans(id) ON DELETE RESTRICT,
  FOREIGN KEY (checkpoint_stop_id) REFERENCES route_stops(id) ON DELETE RESTRICT,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE RESTRICT
);

CREATE INDEX idx_checkpoint_checkins_ride_plan_stop
  ON ride_checkpoint_checkins(
    ride_id,
    route_plan_id,
    checkpoint_stop_id,
    checked_in_at
  );

CREATE TABLE ride_checkpoint_releases (
  ride_id TEXT NOT NULL,
  route_plan_id TEXT NOT NULL,
  checkpoint_stop_id TEXT NOT NULL,
  released_by_rider_id TEXT NOT NULL,
  released_at TEXT NOT NULL,
  PRIMARY KEY (
    ride_id,
    route_plan_id,
    checkpoint_stop_id
  ),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (route_plan_id) REFERENCES route_plans(id) ON DELETE RESTRICT,
  FOREIGN KEY (checkpoint_stop_id) REFERENCES route_stops(id) ON DELETE RESTRICT,
  FOREIGN KEY (released_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT
);

CREATE INDEX idx_checkpoint_releases_ride_plan_time
  ON ride_checkpoint_releases(
    ride_id,
    route_plan_id,
    released_at
  );
