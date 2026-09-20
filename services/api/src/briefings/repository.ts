import type {
  BriefingReadiness,
  BriefingRoleSnapshot,
  PublishRideBriefingInput,
  RideBriefing,
} from './models';

export interface RideBriefingRepository {
  findCurrent(rideId: string): Promise<RideBriefing | null>;

  resolveRoleSnapshot(rideId: string): Promise<BriefingRoleSnapshot | null>;

  publish(input: PublishRideBriefingInput): Promise<RideBriefing>;

  acknowledge(
    briefingId: string,
    riderId: string,
    timestamp: string,
  ): Promise<void>;

  getReadiness(
    rideId: string,
    briefingId: string,
    currentRiderId: string,
  ): Promise<BriefingReadiness>;
}

interface BriefingRow {
  readonly id: string;
  readonly ride_id: string;
  readonly revision: number;
  readonly route_plan_id: string;
  readonly created_by_rider_id: string;
  readonly scheduled_start_at: string | null;
  readonly leader_rider_id: string;
  readonly leader_display_name: string;
  readonly sweeper_rider_id: string | null;
  readonly sweeper_display_name: string | null;
  readonly notes: string | null;
  readonly is_current: number;
  readonly published_at: string;
}

interface RoleRow {
  readonly rider_id: string;
  readonly display_name: string;
  readonly role: 'leader' | 'sweeper';
}

interface ReadinessRow {
  readonly expected_count: number;
  readonly ready_count: number;
  readonly current_rider_acknowledged: number;
}

export class D1RideBriefingRepository implements RideBriefingRepository {
  constructor(private readonly database: D1Database) {}

  async findCurrent(rideId: string): Promise<RideBriefing | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          ride_id,
          revision,
          route_plan_id,
          created_by_rider_id,
          scheduled_start_at,
          leader_rider_id,
          leader_display_name,
          sweeper_rider_id,
          sweeper_display_name,
          notes,
          is_current,
          published_at
        FROM ride_briefings
        WHERE ride_id = ? AND is_current = 1
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<BriefingRow>();

    return row == null ? null : mapBriefing(row);
  }

  async resolveRoleSnapshot(
    rideId: string,
  ): Promise<BriefingRoleSnapshot | null> {
    const result = await this.database
      .prepare(
        `
        SELECT
          memberships.rider_id,
          riders.display_name,
          memberships.role
        FROM ride_memberships AS memberships
        JOIN riders ON riders.id = memberships.rider_id
        WHERE
          memberships.ride_id = ?
          AND memberships.status != 'left'
          AND memberships.role IN ('leader', 'sweeper')
        ORDER BY CASE memberships.role WHEN 'leader' THEN 0 ELSE 1 END
        `,
      )
      .bind(rideId)
      .all<RoleRow>();

    const leader = result.results.find((row) => row.role === 'leader');
    if (leader == null) {
      return null;
    }

    const sweeper = result.results.find((row) => row.role === 'sweeper');

    return {
      leader: {
        riderId: leader.rider_id,
        displayName: leader.display_name,
      },
      sweeper:
        sweeper == null
          ? null
          : {
              riderId: sweeper.rider_id,
              displayName: sweeper.display_name,
            },
    };
  }

  async publish(input: PublishRideBriefingInput): Promise<RideBriefing> {
    await this.database.batch([
      this.database
        .prepare(
          `
          UPDATE ride_briefings
          SET is_current = 0
          WHERE ride_id = ? AND is_current = 1
          `,
        )
        .bind(input.rideId),
      this.database
        .prepare(
          `
          INSERT INTO ride_briefings(
            id,
            ride_id,
            revision,
            route_plan_id,
            created_by_rider_id,
            scheduled_start_at,
            leader_rider_id,
            leader_display_name,
            sweeper_rider_id,
            sweeper_display_name,
            notes,
            is_current,
            published_at
          )
          SELECT
            ?,
            ?,
            COALESCE(MAX(revision), 0) + 1,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            ?,
            1,
            ?
          FROM ride_briefings
          WHERE ride_id = ?
          `,
        )
        .bind(
          input.id,
          input.rideId,
          input.routePlanId,
          input.createdByRiderId,
          input.scheduledStartAt,
          input.roles.leader.riderId,
          input.roles.leader.displayName,
          input.roles.sweeper?.riderId ?? null,
          input.roles.sweeper?.displayName ?? null,
          input.notes,
          input.publishedAt,
          input.rideId,
        ),
    ]);

    const briefing = await this.findCurrent(input.rideId);
    if (briefing == null || briefing.id !== input.id) {
      throw new Error('RideBriefing revision was not persisted.');
    }

    return briefing;
  }

  async acknowledge(
    briefingId: string,
    riderId: string,
    timestamp: string,
  ): Promise<void> {
    await this.database
      .prepare(
        `
        INSERT INTO ride_briefing_acknowledgements(
          briefing_id,
          rider_id,
          acknowledged_at
        ) VALUES (?, ?, ?)
        ON CONFLICT(briefing_id, rider_id) DO NOTHING
        `,
      )
      .bind(briefingId, riderId, timestamp)
      .run();
  }

  async getReadiness(
    rideId: string,
    briefingId: string,
    currentRiderId: string,
  ): Promise<BriefingReadiness> {
    const row = await this.database
      .prepare(
        `
        SELECT
          (
            SELECT COUNT(*)
            FROM ride_memberships
            WHERE
              ride_id = ?
              AND status NOT IN ('invited', 'left')
          ) AS expected_count,
          (
            SELECT COUNT(*)
            FROM ride_briefing_acknowledgements AS acknowledgements
            JOIN ride_memberships AS memberships
              ON memberships.rider_id = acknowledgements.rider_id
            WHERE
              acknowledgements.briefing_id = ?
              AND memberships.ride_id = ?
              AND memberships.status NOT IN ('invited', 'left')
          ) AS ready_count,
          EXISTS(
            SELECT 1
            FROM ride_briefing_acknowledgements
            WHERE briefing_id = ? AND rider_id = ?
          ) AS current_rider_acknowledged
        `,
      )
      .bind(
        rideId,
        briefingId,
        rideId,
        briefingId,
        currentRiderId,
      )
      .first<ReadinessRow>();

    if (row == null) {
      return {
        expectedCount: 0,
        readyCount: 0,
        currentRiderAcknowledged: false,
      };
    }

    return {
      expectedCount: Number(row.expected_count),
      readyCount: Number(row.ready_count),
      currentRiderAcknowledged:
        Number(row.current_rider_acknowledged) === 1,
    };
  }
}

function mapBriefing(row: BriefingRow): RideBriefing {
  return {
    id: row.id,
    rideId: row.ride_id,
    revision: row.revision,
    routePlanId: row.route_plan_id,
    createdByRiderId: row.created_by_rider_id,
    scheduledStartAt: row.scheduled_start_at,
    leader: {
      riderId: row.leader_rider_id,
      displayName: row.leader_display_name,
    },
    sweeper:
      row.sweeper_rider_id == null || row.sweeper_display_name == null
        ? null
        : {
            riderId: row.sweeper_rider_id,
            displayName: row.sweeper_display_name,
          },
    notes: row.notes,
    isCurrent: row.is_current === 1,
    publishedAt: row.published_at,
  };
}
