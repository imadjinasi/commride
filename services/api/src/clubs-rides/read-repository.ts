import type {
  ClubMembershipStatus,
  ClubRole,
  RideMembershipStatus,
  RideRole,
  RideStatus,
} from './models';
import type { ClubListItem, RideListItem } from './read-models';

export interface ClubRideReadRepository {
  listClubsForRider(riderId: string): Promise<readonly ClubListItem[]>;

  listRidesForClub(
    clubId: string,
    riderId: string,
  ): Promise<readonly RideListItem[]>;
}

interface ClubListRow {
  readonly id: string;
  readonly created_by_rider_id: string;
  readonly name: string;
  readonly slug: string;
  readonly home_area: string | null;
  readonly description: string | null;
  readonly visibility: 'private' | 'unlisted' | 'public';
  readonly created_at: string;
  readonly updated_at: string;
  readonly membership_rider_id: string;
  readonly membership_role: ClubRole;
  readonly membership_status: ClubMembershipStatus;
}

interface RideListRow {
  readonly id: string;
  readonly club_id: string;
  readonly created_by_rider_id: string;
  readonly title: string;
  readonly status: RideStatus;
  readonly scheduled_start_at: string | null;
  readonly actual_start_at: string | null;
  readonly ended_at: string | null;
  readonly notes: string | null;
  readonly created_at: string;
  readonly updated_at: string;
  readonly membership_rider_id: string | null;
  readonly membership_role: RideRole | null;
  readonly membership_status: RideMembershipStatus | null;
}

export class D1ClubRideReadRepository implements ClubRideReadRepository {
  constructor(private readonly database: D1Database) {}

  async listClubsForRider(
    riderId: string,
  ): Promise<readonly ClubListItem[]> {
    const result = await this.database
      .prepare(
        `
        SELECT
          c.id,
          c.created_by_rider_id,
          c.name,
          c.slug,
          c.home_area,
          c.description,
          c.visibility,
          c.created_at,
          c.updated_at,
          m.rider_id AS membership_rider_id,
          m.role AS membership_role,
          m.status AS membership_status
        FROM club_memberships m
        JOIN clubs c ON c.id = m.club_id
        WHERE m.rider_id = ? AND m.status != 'left'
        ORDER BY c.name COLLATE NOCASE ASC
        `,
      )
      .bind(riderId)
      .all<ClubListRow>();

    return result.results.map((row) => ({
      club: {
        id: row.id,
        createdByRiderId: row.created_by_rider_id,
        name: row.name,
        slug: row.slug,
        homeArea: row.home_area,
        description: row.description,
        visibility: row.visibility,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
      membership: {
        clubId: row.id,
        riderId: row.membership_rider_id,
        role: row.membership_role,
        status: row.membership_status,
      },
    }));
  }

  async listRidesForClub(
    clubId: string,
    riderId: string,
  ): Promise<readonly RideListItem[]> {
    const result = await this.database
      .prepare(
        `
        SELECT
          r.id,
          r.club_id,
          r.created_by_rider_id,
          r.title,
          r.status,
          r.scheduled_start_at,
          r.actual_start_at,
          r.ended_at,
          r.notes,
          r.created_at,
          r.updated_at,
          m.rider_id AS membership_rider_id,
          m.role AS membership_role,
          m.status AS membership_status
        FROM rides r
        LEFT JOIN ride_memberships m
          ON m.ride_id = r.id AND m.rider_id = ?
        WHERE r.club_id = ?
        ORDER BY
          CASE WHEN r.scheduled_start_at IS NULL THEN 1 ELSE 0 END,
          r.scheduled_start_at ASC,
          r.created_at DESC
        `,
      )
      .bind(riderId, clubId)
      .all<RideListRow>();

    return result.results.map((row) => ({
      ride: {
        id: row.id,
        clubId: row.club_id,
        createdByRiderId: row.created_by_rider_id,
        title: row.title,
        status: row.status,
        scheduledStartAt: row.scheduled_start_at,
        actualStartAt: row.actual_start_at,
        endedAt: row.ended_at,
        notes: row.notes,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
      membership:
        row.membership_rider_id == null ||
        row.membership_role == null ||
        row.membership_status == null
          ? null
          : {
              rideId: row.id,
              riderId: row.membership_rider_id,
              role: row.membership_role,
              status: row.membership_status,
            },
    }));
  }
}
