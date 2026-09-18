-- CommRide core relational schema.
-- Scope: Rider, Vehicle, Club, ClubMembership, Ride, RideMembership.
-- Realtime RiderPresence and historical LocationSample are intentionally absent.
--
-- IDs are opaque application-generated TEXT identifiers. The API layer owns
-- identifier generation so the schema does not depend on a SQLite extension.

PRAGMA foreign_keys = ON;

CREATE TABLE riders (
  id TEXT PRIMARY KEY,
  auth_subject TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 80),
  callsign TEXT CHECK (callsign IS NULL OR length(trim(callsign)) BETWEEN 1 AND 40),
  home_area TEXT CHECK (home_area IS NULL OR length(trim(home_area)) <= 120),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE vehicles (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('motorcycle', 'car', 'other')),
  make TEXT CHECK (make IS NULL OR length(trim(make)) <= 80),
  model TEXT CHECK (model IS NULL OR length(trim(model)) <= 80),
  nickname TEXT CHECK (nickname IS NULL OR length(trim(nickname)) <= 80),
  fuel_type TEXT CHECK (fuel_type IS NULL OR length(trim(fuel_type)) <= 40),
  safe_range_km INTEGER CHECK (
    safe_range_km IS NULL OR (safe_range_km > 0 AND safe_range_km <= 2000)
  ),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE
);

CREATE INDEX idx_vehicles_rider_id
  ON vehicles(rider_id);

CREATE TABLE clubs (
  id TEXT PRIMARY KEY,
  created_by_rider_id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  slug TEXT NOT NULL COLLATE NOCASE UNIQUE
    CHECK (length(trim(slug)) BETWEEN 2 AND 60),
  home_area TEXT CHECK (home_area IS NULL OR length(trim(home_area)) <= 120),
  description TEXT CHECK (description IS NULL OR length(description) <= 2000),
  visibility TEXT NOT NULL DEFAULT 'private'
    CHECK (visibility IN ('private', 'unlisted', 'public')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (created_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT
);

CREATE INDEX idx_clubs_created_by_rider_id
  ON clubs(created_by_rider_id);

CREATE TABLE club_memberships (
  club_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('owner', 'admin', 'member')),
  status TEXT NOT NULL DEFAULT 'invited'
    CHECK (status IN ('invited', 'active', 'left')),
  invited_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  joined_at TEXT,
  left_at TEXT,
  PRIMARY KEY (club_id, rider_id),
  FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE,
  CHECK (
    (status = 'active' AND joined_at IS NOT NULL AND left_at IS NULL)
    OR (status = 'invited' AND joined_at IS NULL AND left_at IS NULL)
    OR (status = 'left' AND left_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX idx_club_one_active_owner
  ON club_memberships(club_id)
  WHERE role = 'owner' AND status = 'active';

CREATE INDEX idx_club_memberships_rider_status
  ON club_memberships(rider_id, status);

CREATE TABLE rides (
  id TEXT PRIMARY KEY,
  club_id TEXT NOT NULL,
  created_by_rider_id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 120),
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'published', 'active', 'completed', 'cancelled')),
  scheduled_start_at TEXT,
  actual_start_at TEXT,
  ended_at TEXT,
  notes TEXT CHECK (notes IS NULL OR length(notes) <= 4000),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE RESTRICT,
  FOREIGN KEY (created_by_rider_id) REFERENCES riders(id) ON DELETE RESTRICT,
  CHECK (
    status NOT IN ('active', 'completed')
    OR actual_start_at IS NOT NULL
  ),
  CHECK (
    status != 'completed'
    OR ended_at IS NOT NULL
  )
);

CREATE INDEX idx_rides_club_status_start
  ON rides(club_id, status, scheduled_start_at);

CREATE INDEX idx_rides_created_by_rider_id
  ON rides(created_by_rider_id);

CREATE TABLE ride_memberships (
  ride_id TEXT NOT NULL,
  rider_id TEXT NOT NULL,
  vehicle_id TEXT,
  role TEXT NOT NULL DEFAULT 'member'
    CHECK (role IN ('leader', 'sweeper', 'navigator', 'member')),
  status TEXT NOT NULL DEFAULT 'invited'
    CHECK (status IN ('invited', 'joined', 'ready', 'active', 'finished', 'left')),
  invited_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  joined_at TEXT,
  PRIMARY KEY (ride_id, rider_id),
  FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE,
  FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE,
  FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL,
  CHECK (
    status = 'invited'
    OR joined_at IS NOT NULL
  )
);

CREATE UNIQUE INDEX idx_ride_one_current_leader
  ON ride_memberships(ride_id)
  WHERE role = 'leader' AND status != 'left';

CREATE INDEX idx_ride_memberships_rider_status
  ON ride_memberships(rider_id, status);

CREATE INDEX idx_ride_memberships_ride_status
  ON ride_memberships(ride_id, status);
