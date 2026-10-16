import { accountDeletionStatements } from './statements';

export { DELETED_RIDER_NAME } from './statements';

export interface DeletionClub {
  readonly clubId: string;
  readonly name: string;
}

export interface DeletionRide {
  readonly rideId: string;
  readonly title: string;
}

export interface AccountDeletionPreview {
  /** Clubs the Rider solely owns while other active members remain. */
  readonly clubsRequiringTransfer: readonly DeletionClub[];
  /** Clubs the Rider owns with no other active member; they will be closed. */
  readonly clubsToClose: readonly DeletionClub[];
  /** Active Rides the Rider is still taking part in. */
  readonly activeRides: readonly DeletionRide[];
}

export function isDeletionBlocked(preview: AccountDeletionPreview): boolean {
  return (
    preview.clubsRequiringTransfer.length > 0 || preview.activeRides.length > 0
  );
}

export interface AccountDeletionRepository {
  preview(riderId: string): Promise<AccountDeletionPreview>;

  /**
   * Deletes personal data and scrubs the Rider into a tombstone in one
   * transaction. Callers must check the preview for blockers first.
   */
  deleteAccount(
    riderId: string,
    clubsToClose: readonly string[],
    deletedAt: string,
  ): Promise<void>;
}

interface OwnedClubRow {
  readonly id: string;
  readonly name: string;
  readonly other_members: number;
}

interface ActiveRideRow {
  readonly id: string;
  readonly title: string;
}

export class D1AccountDeletionRepository implements AccountDeletionRepository {
  constructor(private readonly database: D1Database) {}

  async preview(riderId: string): Promise<AccountDeletionPreview> {
    const [owned, active] = await Promise.all([
      this.database
        .prepare(
          `
          SELECT
            c.id,
            c.name,
            (
              SELECT COUNT(*)
              FROM club_memberships other
              WHERE other.club_id = c.id
                AND other.status = 'active'
                AND other.rider_id <> ?1
            ) AS other_members
          FROM club_memberships m
          JOIN clubs c ON c.id = m.club_id
          WHERE m.rider_id = ?1
            AND m.status = 'active'
            AND m.role = 'owner'
          ORDER BY c.name, c.id
          `,
        )
        .bind(riderId)
        .all<OwnedClubRow>(),
      this.database
        .prepare(
          `
          SELECT r.id, r.title
          FROM ride_memberships rm
          JOIN rides r ON r.id = rm.ride_id
          WHERE rm.rider_id = ?1
            AND r.status = 'active'
            AND rm.status NOT IN ('invited', 'left')
          ORDER BY r.title, r.id
          `,
        )
        .bind(riderId)
        .all<ActiveRideRow>(),
    ]);

    const toClub = (row: OwnedClubRow): DeletionClub => ({
      clubId: row.id,
      name: row.name,
    });

    return {
      clubsRequiringTransfer: owned.results
        .filter((row) => row.other_members > 0)
        .map(toClub),
      clubsToClose: owned.results
        .filter((row) => row.other_members === 0)
        .map(toClub),
      activeRides: active.results.map((row) => ({
        rideId: row.id,
        title: row.title,
      })),
    };
  }

  async deleteAccount(
    riderId: string,
    clubsToClose: readonly string[],
    deletedAt: string,
  ): Promise<void> {
    const statements = accountDeletionStatements(
      riderId,
      clubsToClose,
      deletedAt,
    ).map(({ sql, params }) => this.database.prepare(sql).bind(...params));

    await this.database.batch(statements);
  }
}
