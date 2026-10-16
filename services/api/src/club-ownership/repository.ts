export type ClubMemberRole = 'owner' | 'admin' | 'member';

export interface ClubMember {
  readonly riderId: string;
  readonly displayName: string;
  readonly callsign: string | null;
  readonly role: ClubMemberRole;
}

export interface ClubOwnershipRepository {
  /** Active members only; deleted Riders have already left every Club. */
  listActiveMembers(clubId: string): Promise<readonly ClubMember[]>;

  findActiveRole(
    clubId: string,
    riderId: string,
  ): Promise<ClubMemberRole | null>;

  /** Previous owner becomes admin; exactly one active owner remains. */
  transferOwnership(
    clubId: string,
    fromRiderId: string,
    toRiderId: string,
    now: string,
  ): Promise<void>;
}

interface ClubMemberRow {
  readonly rider_id: string;
  readonly display_name: string;
  readonly callsign: string | null;
  readonly role: ClubMemberRole;
}

export class D1ClubOwnershipRepository implements ClubOwnershipRepository {
  constructor(private readonly database: D1Database) {}

  async listActiveMembers(clubId: string): Promise<readonly ClubMember[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT m.rider_id, r.display_name, r.callsign, m.role
        FROM club_memberships m
        JOIN riders r ON r.id = m.rider_id
        WHERE m.club_id = ?1 AND m.status = 'active'
        ORDER BY
          CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
          r.display_name,
          r.id
        `,
      )
      .bind(clubId)
      .all<ClubMemberRow>();

    return rows.results.map((row) => ({
      riderId: row.rider_id,
      displayName: row.display_name,
      callsign: row.callsign,
      role: row.role,
    }));
  }

  async findActiveRole(
    clubId: string,
    riderId: string,
  ): Promise<ClubMemberRole | null> {
    const row = await this.database
      .prepare(
        `
        SELECT role FROM club_memberships
        WHERE club_id = ?1 AND rider_id = ?2 AND status = 'active'
        `,
      )
      .bind(clubId, riderId)
      .first<{ readonly role: ClubMemberRole }>();

    return row?.role ?? null;
  }

  async transferOwnership(
    clubId: string,
    fromRiderId: string,
    toRiderId: string,
    now: string,
  ): Promise<void> {
    // Demote first: the schema allows only one active owner per Club.
    await this.database.batch([
      this.database
        .prepare(
          `
          UPDATE club_memberships SET role = 'admin'
          WHERE club_id = ?1 AND rider_id = ?2
            AND role = 'owner' AND status = 'active'
          `,
        )
        .bind(clubId, fromRiderId),
      this.database
        .prepare(
          `
          UPDATE club_memberships SET role = 'owner'
          WHERE club_id = ?1 AND rider_id = ?2 AND status = 'active'
          `,
        )
        .bind(clubId, toRiderId),
      this.database
        .prepare(`UPDATE clubs SET updated_at = ?2 WHERE id = ?1`)
        .bind(clubId, now),
    ]);
  }
}
