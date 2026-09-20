import type {
  RideMembershipStatus,
  RideRole,
} from '../clubs-rides/models';
import type {
  CheckpointCheckIn,
  CheckpointRelease,
} from './models';

export interface CheckpointParticipantRecord {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
  readonly membershipStatus: RideMembershipStatus;
}

export interface CheckpointRepository {
  listParticipants(rideId: string): Promise<readonly CheckpointParticipantRecord[]>;

  listCheckIns(
    rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointCheckIn[]>;

  listReleases(
    rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointRelease[]>;

  checkIn(
    rideId: string,
    routePlanId: string,
    checkpointId: string,
    riderId: string,
    checkedInAt: string,
  ): Promise<void>;

  release(
    rideId: string,
    routePlanId: string,
    checkpointId: string,
    checkpointSequence: number,
    releasedByRiderId: string,
    releasedAt: string,
  ): Promise<boolean>;
}

interface ParticipantRow {
  readonly rider_id: string;
  readonly display_name: string;
  readonly role: RideRole;
  readonly status: RideMembershipStatus;
}

interface CheckInRow {
  readonly route_plan_id: string;
  readonly checkpoint_stop_id: string;
  readonly rider_id: string;
  readonly checked_in_at: string;
  readonly method: 'manual';
}

interface ReleaseRow {
  readonly route_plan_id: string;
  readonly checkpoint_stop_id: string;
  readonly released_by_rider_id: string;
  readonly released_at: string;
}

export class D1CheckpointRepository implements CheckpointRepository {
  constructor(private readonly database: D1Database) {}

  async listParticipants(
    rideId: string,
  ): Promise<readonly CheckpointParticipantRecord[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT
          memberships.rider_id,
          riders.display_name,
          memberships.role,
          memberships.status
        FROM ride_memberships AS memberships
        JOIN riders ON riders.id = memberships.rider_id
        WHERE
          memberships.ride_id = ?
          AND memberships.status NOT IN ('invited', 'left')
        ORDER BY
          CASE memberships.role
            WHEN 'leader' THEN 0
            WHEN 'sweeper' THEN 1
            WHEN 'navigator' THEN 2
            ELSE 3
          END,
          lower(riders.display_name),
          memberships.rider_id
        `,
      )
      .bind(rideId)
      .all<ParticipantRow>();

    return rows.results.map((row) => ({
      riderId: row.rider_id,
      displayName: row.display_name,
      role: row.role,
      membershipStatus: row.status,
    }));
  }

  async listCheckIns(
    rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointCheckIn[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT route_plan_id, checkpoint_stop_id, rider_id, checked_in_at, method
        FROM ride_checkpoint_checkins
        WHERE ride_id = ? AND route_plan_id = ?
        ORDER BY checked_in_at ASC, rider_id ASC
        `,
      )
      .bind(rideId, routePlanId)
      .all<CheckInRow>();

    return rows.results.map((row) => ({
      routePlanId: row.route_plan_id,
      checkpointId: row.checkpoint_stop_id,
      riderId: row.rider_id,
      checkedInAt: row.checked_in_at,
      method: row.method,
    }));
  }

  async listReleases(
    rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointRelease[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT route_plan_id, checkpoint_stop_id, released_by_rider_id, released_at
        FROM ride_checkpoint_releases
        WHERE ride_id = ? AND route_plan_id = ?
        ORDER BY released_at ASC, checkpoint_stop_id ASC
        `,
      )
      .bind(rideId, routePlanId)
      .all<ReleaseRow>();

    return rows.results.map((row) => ({
      routePlanId: row.route_plan_id,
      checkpointId: row.checkpoint_stop_id,
      releasedByRiderId: row.released_by_rider_id,
      releasedAt: row.released_at,
    }));
  }

  async checkIn(
    rideId: string,
    routePlanId: string,
    checkpointId: string,
    riderId: string,
    checkedInAt: string,
  ): Promise<void> {
    await this.database
      .prepare(
        `
        INSERT INTO ride_checkpoint_checkins(
          ride_id,
          route_plan_id,
          checkpoint_stop_id,
          rider_id,
          checked_in_at,
          method
        ) VALUES (?, ?, ?, ?, ?, 'manual')
        ON CONFLICT(
          ride_id,
          route_plan_id,
          checkpoint_stop_id,
          rider_id
        ) DO NOTHING
        `,
      )
      .bind(rideId, routePlanId, checkpointId, riderId, checkedInAt)
      .run();
  }

  async release(
    rideId: string,
    routePlanId: string,
    checkpointId: string,
    checkpointSequence: number,
    releasedByRiderId: string,
    releasedAt: string,
  ): Promise<boolean> {
    await this.database
      .prepare(
        `
        INSERT INTO ride_checkpoint_releases(
          ride_id,
          route_plan_id,
          checkpoint_stop_id,
          released_by_rider_id,
          released_at
        )
        SELECT ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1
          FROM route_stops AS earlier
          WHERE
            earlier.route_plan_id = ?
            AND earlier.checkpoint_type IS NOT NULL
            AND earlier.sequence < ?
            AND NOT EXISTS (
              SELECT 1
              FROM ride_checkpoint_releases AS releases
              WHERE
                releases.ride_id = ?
                AND releases.route_plan_id = ?
                AND releases.checkpoint_stop_id = earlier.id
            )
        )
        ON CONFLICT(
          ride_id,
          route_plan_id,
          checkpoint_stop_id
        ) DO NOTHING
        `,
      )
      .bind(
        rideId,
        routePlanId,
        checkpointId,
        releasedByRiderId,
        releasedAt,
        routePlanId,
        checkpointSequence,
        rideId,
        routePlanId,
      )
      .run();

    const existing = await this.database
      .prepare(
        `
        SELECT 1
        FROM ride_checkpoint_releases
        WHERE
          ride_id = ?
          AND route_plan_id = ?
          AND checkpoint_stop_id = ?
        LIMIT 1
        `,
      )
      .bind(rideId, routePlanId, checkpointId)
      .first<{ readonly '1': number }>();

    return existing != null;
  }
}
