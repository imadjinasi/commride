import type { RouteManeuver } from '../maps/models';
import type {
  RoutePlan,
  RouteStop,
  SaveRoutePlanInput,
} from './models';

export interface RoutePlanRepository {
  findCurrent(rideId: string): Promise<RoutePlan | null>;

  findById(routePlanId: string): Promise<RoutePlan | null>;

  replaceCurrent(input: SaveRoutePlanInput): Promise<RoutePlan>;
}

interface RoutePlanRow {
  readonly id: string;
  readonly ride_id: string;
  readonly revision: number;
  readonly created_by_rider_id: string;
  readonly travel_mode: 'drive' | 'two_wheeler';
  readonly origin_label: string | null;
  readonly origin_latitude: number;
  readonly origin_longitude: number;
  readonly destination_label: string | null;
  readonly destination_latitude: number;
  readonly destination_longitude: number;
  readonly distance_meters: number;
  readonly duration_seconds: number;
  readonly encoded_polyline: string;
  readonly maneuvers_json: string;
  readonly is_current: number;
  readonly created_at: string;
}

interface RouteStopRow {
  readonly id: string;
  readonly sequence: number;
  readonly label: string;
  readonly formatted_address: string | null;
  readonly latitude: number;
  readonly longitude: number;
  readonly stop_type:
    | 'generic'
    | 'fuel'
    | 'rest'
    | 'meal'
    | 'hotel'
    | 'custom';
  readonly checkpoint_type:
    | 'stop'
    | 'fuel'
    | 'rest'
    | 'meal'
    | 'regroup'
    | 'mandatory_regroup'
    | 'hotel'
    | 'custom'
    | 'finish'
    | null;
  readonly planned_duration_minutes: number | null;
}

export class D1RoutePlanRepository implements RoutePlanRepository {
  constructor(private readonly database: D1Database) {}

  async findCurrent(rideId: string): Promise<RoutePlan | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          ride_id,
          revision,
          created_by_rider_id,
          travel_mode,
          origin_label,
          origin_latitude,
          origin_longitude,
          destination_label,
          destination_latitude,
          destination_longitude,
          distance_meters,
          duration_seconds,
          encoded_polyline,
          maneuvers_json,
          is_current,
          created_at
        FROM route_plans
        WHERE ride_id = ? AND is_current = 1
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<RoutePlanRow>();

    if (row == null) {
      return null;
    }

    const stops = await this.database
      .prepare(
        `
        SELECT
          id,
          sequence,
          label,
          formatted_address,
          latitude,
          longitude,
          stop_type,
          checkpoint_type,
          planned_duration_minutes
        FROM route_stops
        WHERE route_plan_id = ?
        ORDER BY sequence ASC
        `,
      )
      .bind(row.id)
      .all<RouteStopRow>();

    return mapRoutePlan(row, stops.results);
  }

  async findById(routePlanId: string): Promise<RoutePlan | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          ride_id,
          revision,
          created_by_rider_id,
          travel_mode,
          origin_label,
          origin_latitude,
          origin_longitude,
          destination_label,
          destination_latitude,
          destination_longitude,
          distance_meters,
          duration_seconds,
          encoded_polyline,
          maneuvers_json,
          is_current,
          created_at
        FROM route_plans
        WHERE id = ?
        LIMIT 1
        `,
      )
      .bind(routePlanId)
      .first<RoutePlanRow>();

    if (row == null) {
      return null;
    }

    const stops = await this.database
      .prepare(
        `
        SELECT
          id,
          sequence,
          label,
          formatted_address,
          latitude,
          longitude,
          stop_type,
          checkpoint_type,
          planned_duration_minutes
        FROM route_stops
        WHERE route_plan_id = ?
        ORDER BY sequence ASC
        `,
      )
      .bind(row.id)
      .all<RouteStopRow>();

    return mapRoutePlan(row, stops.results);
  }

  async replaceCurrent(input: SaveRoutePlanInput): Promise<RoutePlan> {
    const statements: D1PreparedStatement[] = [
      this.database
        .prepare(
          `
          UPDATE route_plans
          SET is_current = 0
          WHERE ride_id = ? AND is_current = 1
          `,
        )
        .bind(input.rideId),
      this.database
        .prepare(
          `
          INSERT INTO route_plans(
            id,
            ride_id,
            revision,
            created_by_rider_id,
            travel_mode,
            origin_label,
            origin_latitude,
            origin_longitude,
            destination_label,
            destination_latitude,
            destination_longitude,
            distance_meters,
            duration_seconds,
            encoded_polyline,
            maneuvers_json,
            is_current
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
            ?,
            ?,
            ?,
            ?,
            1
          FROM route_plans
          WHERE ride_id = ?
          `,
        )
        .bind(
          input.id,
          input.rideId,
          input.createdByRiderId,
          input.travelMode,
          input.originLabel,
          input.origin.latitude,
          input.origin.longitude,
          input.destinationLabel,
          input.destination.latitude,
          input.destination.longitude,
          input.distanceMeters,
          input.durationSeconds,
          input.encodedPolyline,
          JSON.stringify(input.maneuvers ?? []),
          input.rideId,
        ),
    ];

    for (const stop of input.stops) {
      statements.push(
        this.database
          .prepare(
            `
            INSERT INTO route_stops(
              id,
              route_plan_id,
              sequence,
              label,
              formatted_address,
              latitude,
              longitude,
              stop_type,
              checkpoint_type,
              planned_duration_minutes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `,
          )
          .bind(
            stop.id,
            input.id,
            stop.sequence,
            stop.label,
            stop.formattedAddress,
            stop.location.latitude,
            stop.location.longitude,
            stop.stopType,
            stop.checkpointType,
            stop.plannedDurationMinutes,
          ),
      );
    }

    await this.database.batch(statements);

    const routePlan = await this.findCurrent(input.rideId);
    if (routePlan == null || routePlan.id !== input.id) {
      throw new Error('RoutePlan revision was not persisted.');
    }

    return routePlan;
  }
}

function mapRoutePlan(
  row: RoutePlanRow,
  stopRows: readonly RouteStopRow[],
): RoutePlan {
  return {
    id: row.id,
    rideId: row.ride_id,
    revision: row.revision,
    createdByRiderId: row.created_by_rider_id,
    travelMode: row.travel_mode,
    originLabel: row.origin_label,
    origin: {
      latitude: row.origin_latitude,
      longitude: row.origin_longitude,
    },
    destinationLabel: row.destination_label,
    destination: {
      latitude: row.destination_latitude,
      longitude: row.destination_longitude,
    },
    distanceMeters: row.distance_meters,
    durationSeconds: row.duration_seconds,
    encodedPolyline: row.encoded_polyline,
    maneuvers: parseManeuvers(row.maneuvers_json),
    isCurrent: row.is_current === 1,
    createdAt: row.created_at,
    stops: stopRows.map(mapRouteStop),
  };
}

function mapRouteStop(row: RouteStopRow): RouteStop {
  return {
    id: row.id,
    sequence: row.sequence,
    label: row.label,
    formattedAddress: row.formatted_address,
    location: {
      latitude: row.latitude,
      longitude: row.longitude,
    },
    stopType: row.stop_type,
    checkpointType: row.checkpoint_type,
    plannedDurationMinutes: row.planned_duration_minutes,
  };
}


function parseManeuvers(value: string): readonly RouteManeuver[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new Error('Persisted RoutePlan maneuvers are invalid JSON.');
  }
  if (!Array.isArray(parsed)) {
    throw new Error('Persisted RoutePlan maneuvers must be an array.');
  }
  return parsed as RouteManeuver[];
}
