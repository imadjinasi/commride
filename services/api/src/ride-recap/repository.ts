import type {
  RideRecap,
  RideRecapCheckpoint,
  RideRecapIncident,
  RideRecapJourney,
  RideRecapParticipant,
  RideRecapPlannedRoute,
} from './models';
import type {
  RideMembershipStatus,
  RideRole,
} from '../clubs-rides/models';

export interface RideRecapRepository {
  build(rideId: string, generatedAt: string): Promise<RideRecap | null>;
}

interface RideRow {
  readonly id: string;
  readonly title: string;
  readonly actual_start_at: string | null;
  readonly ended_at: string | null;
}

interface ParticipantRow {
  readonly rider_id: string;
  readonly display_name: string;
  readonly role: RideRole;
  readonly status: RideMembershipStatus;
}

interface RouteRow {
  readonly id: string;
  readonly revision: number;
  readonly origin_label: string | null;
  readonly destination_label: string | null;
  readonly distance_meters: number;
  readonly duration_seconds: number;
  readonly stop_count: number;
}

interface JourneyRow {
  readonly sample_count: number;
  readonly tracked_rider_count: number;
  readonly first_observed_at: string | null;
  readonly last_observed_at: string | null;
}

interface CoordinateRow {
  readonly latitude: number;
  readonly longitude: number;
  readonly observed_at: string;
}

interface CheckpointRow {
  readonly checkpoint_id: string;
  readonly label: string;
  readonly checkpoint_type: string;
  readonly check_in_count: number;
  readonly released_at: string | null;
}

interface IncidentRow {
  readonly id: string;
  readonly rider_id: string;
  readonly rider_display_name: string;
  readonly state: 'active' | 'cancelled' | 'resolved';
  readonly reason: string | null;
  readonly raised_at: string;
  readonly cancelled_at: string | null;
  readonly resolved_at: string | null;
}

export class D1RideRecapRepository implements RideRecapRepository {
  constructor(private readonly database: D1Database) {}

  async build(rideId: string, generatedAt: string): Promise<RideRecap | null> {
    const ride = await this.database
      .prepare(
        `
        SELECT id, title, actual_start_at, ended_at
        FROM rides
        WHERE id = ?
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<RideRow>();

    if (ride == null) {
      return null;
    }

    const participants = await this.participants(rideId);
    const plannedRoute = await this.plannedRoute(rideId);
    const journey = await this.journey(rideId, participants);
    const checkpoints = plannedRoute == null
      ? []
      : await this.checkpoints(
          rideId,
          plannedRoute.routePlanId,
          participants.length,
        );
    const incidents = await this.incidents(rideId);

    return {
      rideId: ride.id,
      title: ride.title,
      actualStartAt: ride.actual_start_at,
      endedAt: ride.ended_at,
      durationSeconds: durationSeconds(
        ride.actual_start_at,
        ride.ended_at,
      ),
      participants,
      plannedRoute,
      journey,
      checkpoints,
      incidents,
      generatedAt,
    };
  }

  private async participants(
    rideId: string,
  ): Promise<readonly RideRecapParticipant[]> {
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

  private async plannedRoute(
    rideId: string,
  ): Promise<RideRecapPlannedRoute | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          plans.id,
          plans.revision,
          plans.origin_label,
          plans.destination_label,
          plans.distance_meters,
          plans.duration_seconds,
          (
            SELECT COUNT(*)
            FROM route_stops
            WHERE route_plan_id = plans.id
          ) AS stop_count
        FROM route_plans AS plans
        WHERE plans.ride_id = ? AND plans.is_current = 1
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<RouteRow>();

    return row == null
      ? null
      : {
          routePlanId: row.id,
          revision: row.revision,
          originLabel: row.origin_label,
          destinationLabel: row.destination_label,
          distanceMeters: row.distance_meters,
          durationSeconds: row.duration_seconds,
          stopCount: row.stop_count,
        };
  }

  private async journey(
    rideId: string,
    participants: readonly RideRecapParticipant[],
  ): Promise<RideRecapJourney> {
    const summary = await this.database
      .prepare(
        `
        SELECT
          COUNT(*) AS sample_count,
          COUNT(DISTINCT rider_id) AS tracked_rider_count,
          MIN(observed_at) AS first_observed_at,
          MAX(observed_at) AS last_observed_at
        FROM ride_location_samples
        WHERE ride_id = ?
        `,
      )
      .bind(rideId)
      .first<JourneyRow>();

    const leader = participants.find((item) => item.role === 'leader');
    let leaderTrackedDistanceMeters: number | null = null;

    if (leader != null) {
      const samples = await this.database
        .prepare(
          `
          SELECT latitude, longitude, observed_at
          FROM ride_location_samples
          WHERE ride_id = ? AND rider_id = ?
          ORDER BY observed_at ASC
          `,
        )
        .bind(rideId, leader.riderId)
        .all<CoordinateRow>();

      if (samples.results.length >= 2) {
        leaderTrackedDistanceMeters = Math.round(
          pathDistanceMeters(samples.results),
        );
      }
    }

    return {
      sampleCount: summary?.sample_count ?? 0,
      trackedRiderCount: summary?.tracked_rider_count ?? 0,
      firstObservedAt: summary?.first_observed_at ?? null,
      lastObservedAt: summary?.last_observed_at ?? null,
      leaderTrackedDistanceMeters,
    };
  }

  private async checkpoints(
    rideId: string,
    routePlanId: string,
    participantCount: number,
  ): Promise<readonly RideRecapCheckpoint[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT
          stops.id AS checkpoint_id,
          stops.label,
          stops.checkpoint_type,
          (
            SELECT COUNT(*)
            FROM ride_checkpoint_checkins AS checkins
            WHERE
              checkins.ride_id = ?
              AND checkins.route_plan_id = stops.route_plan_id
              AND checkins.checkpoint_stop_id = stops.id
          ) AS check_in_count,
          (
            SELECT releases.released_at
            FROM ride_checkpoint_releases AS releases
            WHERE
              releases.ride_id = ?
              AND releases.route_plan_id = stops.route_plan_id
              AND releases.checkpoint_stop_id = stops.id
            LIMIT 1
          ) AS released_at
        FROM route_stops AS stops
        WHERE
          stops.route_plan_id = ?
          AND stops.checkpoint_type IS NOT NULL
        ORDER BY stops.sequence ASC
        `,
      )
      .bind(rideId, rideId, routePlanId)
      .all<CheckpointRow>();

    return rows.results.map((row) => ({
      checkpointId: row.checkpoint_id,
      label: row.label,
      checkpointType: row.checkpoint_type,
      checkInCount: row.check_in_count,
      participantCount,
      releasedAt: row.released_at,
    }));
  }

  private async incidents(
    rideId: string,
  ): Promise<readonly RideRecapIncident[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT
          id,
          rider_id,
          rider_display_name,
          state,
          reason,
          raised_at,
          cancelled_at,
          resolved_at
        FROM ride_sos
        WHERE ride_id = ?
        ORDER BY raised_at ASC, id ASC
        `,
      )
      .bind(rideId)
      .all<IncidentRow>();

    return rows.results.map((row) => ({
      sosId: row.id,
      riderId: row.rider_id,
      riderDisplayName: row.rider_display_name,
      state: row.state,
      reason: row.reason,
      raisedAt: row.raised_at,
      closedAt: row.resolved_at ?? row.cancelled_at,
    }));
  }
}

function durationSeconds(
  startedAt: string | null,
  endedAt: string | null,
): number | null {
  if (startedAt == null || endedAt == null) {
    return null;
  }
  const start = Date.parse(startedAt);
  const end = Date.parse(endedAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) {
    return null;
  }
  return Math.round((end - start) / 1000);
}

function pathDistanceMeters(samples: readonly CoordinateRow[]): number {
  let total = 0;
  for (let index = 1; index < samples.length; index += 1) {
    total += haversineMeters(samples[index - 1], samples[index]);
  }
  return total;
}

function haversineMeters(
  a: Pick<CoordinateRow, 'latitude' | 'longitude'>,
  b: Pick<CoordinateRow, 'latitude' | 'longitude'>,
): number {
  const radiusMeters = 6_371_000;
  const toRadians = (value: number) => value * Math.PI / 180;
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const deltaLat = lat2 - lat1;
  const deltaLon = toRadians(b.longitude - a.longitude);

  const sinLat = Math.sin(deltaLat / 2);
  const sinLon = Math.sin(deltaLon / 2);
  const haversine =
    sinLat * sinLat +
    Math.cos(lat1) * Math.cos(lat2) * sinLon * sinLon;
  const centralAngle =
    2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
  return radiusMeters * centralAngle;
}
