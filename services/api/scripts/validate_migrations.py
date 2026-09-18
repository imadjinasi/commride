#!/usr/bin/env python3
"""Apply all CommRide SQLite/D1 migrations to an in-memory database.

This is a syntax/invariant smoke test. Cloudflare D1 remains the release target.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations"


def apply_migrations(connection: sqlite3.Connection) -> None:
    migration_paths = sorted(MIGRATIONS.glob("*.sql"))
    if not migration_paths:
        raise RuntimeError("No migrations found")

    for path in migration_paths:
        connection.executescript(path.read_text(encoding="utf-8"))


def assert_core_tables(connection: sqlite3.Connection) -> None:
    expected = {
        "riders",
        "vehicles",
        "clubs",
        "club_memberships",
        "rides",
        "ride_memberships",
        "route_plans",
        "route_stops",
        "ride_briefings",
        "ride_briefing_acknowledgements",
    }
    rows = connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'"
    ).fetchall()
    actual = {row[0] for row in rows}

    missing = expected - actual
    if missing:
        raise AssertionError(f"Missing core tables: {sorted(missing)}")


def assert_foreign_keys(connection: sqlite3.Connection) -> None:
    violations = connection.execute("PRAGMA foreign_key_check").fetchall()
    if violations:
        raise AssertionError(f"Foreign key violations: {violations}")


def assert_membership_invariants(connection: sqlite3.Connection) -> None:
    connection.execute(
        "INSERT INTO riders(id, auth_subject, display_name) VALUES (?, ?, ?)",
        ("rider-1", "auth-1", "Rider One"),
    )
    connection.execute(
        "INSERT INTO riders(id, auth_subject, display_name) VALUES (?, ?, ?)",
        ("rider-2", "auth-2", "Rider Two"),
    )
    connection.execute(
        """
        INSERT INTO clubs(id, created_by_rider_id, name, slug)
        VALUES (?, ?, ?, ?)
        """,
        ("club-1", "rider-1", "Club One", "club-one"),
    )
    connection.execute(
        """
        INSERT INTO club_memberships(
          club_id, rider_id, role, status, joined_at
        ) VALUES (?, ?, 'owner', 'active', ?)
        """,
        ("club-1", "rider-1", "2026-09-18T00:00:00Z"),
    )

    try:
        connection.execute(
            """
            INSERT INTO club_memberships(
              club_id, rider_id, role, status, joined_at
            ) VALUES (?, ?, 'owner', 'active', ?)
            """,
            ("club-1", "rider-2", "2026-09-18T00:00:00Z"),
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("A second active Club owner was accepted")


def assert_route_plan_invariants(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        INSERT INTO rides(id, club_id, created_by_rider_id, title)
        VALUES (?, ?, ?, ?)
        """,
        ("ride-1", "club-1", "rider-1", "RoutePlan Test Ride"),
    )
    connection.execute(
        """
        INSERT INTO ride_memberships(
          ride_id, rider_id, role, status, joined_at
        ) VALUES (?, ?, 'leader', 'joined', ?)
        """,
        ("ride-1", "rider-1", "2026-09-18T00:00:00Z"),
    )
    connection.execute(
        """
        INSERT INTO route_plans(
          id,
          ride_id,
          revision,
          created_by_rider_id,
          travel_mode,
          origin_latitude,
          origin_longitude,
          destination_latitude,
          destination_longitude,
          distance_meters,
          duration_seconds,
          encoded_polyline,
          is_current
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        """,
        (
            "plan-1",
            "ride-1",
            1,
            "rider-1",
            "drive",
            -6.732,
            108.552,
            -6.917,
            107.619,
            130000,
            9000,
            "polyline-v1",
        ),
    )

    try:
        connection.execute(
            """
            INSERT INTO route_plans(
              id,
              ride_id,
              revision,
              created_by_rider_id,
              travel_mode,
              origin_latitude,
              origin_longitude,
              destination_latitude,
              destination_longitude,
              distance_meters,
              duration_seconds,
              encoded_polyline,
              is_current
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """,
            (
                "plan-conflict",
                "ride-1",
                2,
                "rider-1",
                "drive",
                -6.732,
                108.552,
                -6.917,
                107.619,
                130000,
                9000,
                "polyline-conflict",
            ),
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("A second current RoutePlan revision was accepted")

    connection.execute(
        "UPDATE route_plans SET is_current = 0 WHERE id = ?",
        ("plan-1",),
    )
    connection.execute(
        """
        INSERT INTO route_plans(
          id,
          ride_id,
          revision,
          created_by_rider_id,
          travel_mode,
          origin_latitude,
          origin_longitude,
          destination_latitude,
          destination_longitude,
          distance_meters,
          duration_seconds,
          encoded_polyline,
          is_current
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        """,
        (
            "plan-2",
            "ride-1",
            2,
            "rider-1",
            "drive",
            -6.732,
            108.552,
            -6.917,
            107.619,
            132000,
            9100,
            "polyline-v2",
        ),
    )
    connection.execute(
        """
        INSERT INTO route_stops(
          id,
          route_plan_id,
          sequence,
          label,
          latitude,
          longitude,
          stop_type
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        ("stop-1", "plan-2", 0, "Fuel", -6.8, 108.0, "fuel"),
    )

    try:
        connection.execute(
            """
            INSERT INTO route_stops(
              id,
              route_plan_id,
              sequence,
              label,
              latitude,
              longitude,
              stop_type
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            ("stop-2", "plan-2", 0, "Rest", -6.85, 107.9, "rest"),
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("Duplicate RouteStop sequence was accepted")


def assert_briefing_invariants(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        INSERT INTO ride_briefings(
          id,
          ride_id,
          revision,
          route_plan_id,
          created_by_rider_id,
          leader_rider_id,
          leader_display_name,
          is_current,
          published_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
        """,
        (
            "briefing-1",
            "ride-1",
            1,
            "plan-2",
            "rider-1",
            "rider-1",
            "Rider One",
            "2026-09-18T09:00:00Z",
        ),
    )

    try:
        connection.execute(
            """
            INSERT INTO ride_briefings(
              id,
              ride_id,
              revision,
              route_plan_id,
              created_by_rider_id,
              leader_rider_id,
              leader_display_name,
              is_current,
              published_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
            """,
            (
                "briefing-conflict",
                "ride-1",
                2,
                "plan-2",
                "rider-1",
                "rider-1",
                "Rider One",
                "2026-09-18T09:01:00Z",
            ),
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("A second current RideBriefing revision was accepted")

    connection.execute(
        "UPDATE ride_briefings SET is_current = 0 WHERE id = ?",
        ("briefing-1",),
    )
    connection.execute(
        """
        INSERT INTO ride_briefings(
          id,
          ride_id,
          revision,
          route_plan_id,
          created_by_rider_id,
          leader_rider_id,
          leader_display_name,
          is_current,
          published_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
        """,
        (
            "briefing-2",
            "ride-1",
            2,
            "plan-2",
            "rider-1",
            "rider-1",
            "Rider One",
            "2026-09-18T09:02:00Z",
        ),
    )
    connection.execute(
        """
        INSERT INTO ride_briefing_acknowledgements(
          briefing_id,
          rider_id,
          acknowledged_at
        ) VALUES (?, ?, ?)
        """,
        ("briefing-2", "rider-1", "2026-09-18T09:03:00Z"),
    )

    try:
        connection.execute(
            """
            INSERT INTO ride_briefing_acknowledgements(
              briefing_id,
              rider_id,
              acknowledged_at
            ) VALUES (?, ?, ?)
            """,
            ("briefing-2", "rider-1", "2026-09-18T09:04:00Z"),
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("Duplicate briefing acknowledgement was accepted")


def main() -> None:
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")

    apply_migrations(connection)
    assert_core_tables(connection)
    assert_membership_invariants(connection)
    assert_route_plan_invariants(connection)
    assert_briefing_invariants(connection)
    assert_foreign_keys(connection)

    print("migration-validation-ok")


if __name__ == "__main__":
    main()
