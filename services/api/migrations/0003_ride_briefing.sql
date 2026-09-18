-- CommRide RideBriefing persistence.
-- Briefings are immutable published revisions tied to an immutable RoutePlan
-- revision. Rider acknowledgements are scoped to one exact briefing revision.

PRAGMA foreign_keys = ON;

CREATE TABLE ride_briefings (
  id TEXT PRIMARY KEY,
  ride_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  route_plan_id TEXT NOT NULL,
  created_by_rider_id TEXT NOT NULL,
  scheduled_start_at TEXT,
  leader_rider_id TEXT NOT NULL,
  leader_display_name TEXT NOT NULL
    CHECK (length(trim(leader_display_name)) BETWEEN 1 AND 80),
  sweeper_rider_id TEXT,
  sweeper_display_name TEXT
    CHECK (
      sweeper_display_name IS NULL OR
      length(trim(sweeper_display_name)) BETWEEN 1 AND 80
    ),
  notes TEXT CHECK (notes IS NULL OR length(notes) <= 4000),
  is_current INTEGER NOT NULL DEFAULT 1 CHECK (is_current IN (0, 1)),
  published_at TEXT NOT NULL,
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (route_plan_id) REFERENCES route_plans(id) ON DELETE RESTRICT,
  FOREIGN KEY (created_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  FOREIGN KEY (leader_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  FOREIGN KEY (sweeper_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  UNIQUE (ride_id, revision)
);

CREATE UNIQUE INDEX idx_ride_briefings_one_current
  ON ride_briefings(ride_id)
  WHERE is_current = 1;

CREATE INDEX idx_ride_briefings_ride_revision
  ON ride_briefings(ride_id, revision DESC);

CREATE INDEX idx_ride_briefings_route_plan
  ON ride_briefings(route_plan_id);

CREATE TABLE ride_briefing_acknowledgements (
  briefing_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  acknowledged_at TEXT NOT NULL,
  PRIMARY KEY (briefing_id, rider_id),
  FOREIGN KEY (briefing_id) REFERENCES ride_briefings(id) ON DELETE CASCADE,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE
);

CREATE INDEX idx_briefing_ack_rider
  ON ride_briefing_acknowledgements(rider_id, briefing_id);
