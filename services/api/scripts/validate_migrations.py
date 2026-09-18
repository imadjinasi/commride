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


def main() -> None:
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")

    apply_migrations(connection)
    assert_core_tables(connection)
    assert_foreign_keys(connection)
    assert_membership_invariants(connection)

    print("migration-validation-ok")


if __name__ == "__main__":
    main()
